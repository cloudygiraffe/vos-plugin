-- VoS Discovery (developer tool, never meant for the Plugin Hub)
--
-- Run this on the plugin beta world to answer the open questions the Voice of
-- Seren plugin depends on. Everything is printed to the client console
-- (ALT + the key under Esc). Copy the console output into an issue or message.
--
-- What it checks:
--   1. Whether os.time() exists in the plugin sandbox (a free clock).
--   2. Whether the optional permissions are granted.
--   3. Every VarPlayer / VarClient whose name looks Voice-of-Seren related,
--      with its current value.
--   4. Every variable that changes in the minute around the top of the hour
--      (when the Voice moves). Stand in Prifddinas across an hour change.
--   5. Any chat message mentioning "Seren", with its chat type and wording
--      (needs the optional chatAccess permission).

local KEYWORDS = {
    "VOICE", "SEREN", "VOS", "PRIF", "CLAN", "DISTRICT", "ELF",
    "AMLODD", "CADARN", "CRWYS", "HEFIN", "IORWERTH", "ITHELL", "MEILYR", "TRAHAEARN",
}
local DOMAINS = { "VarPlayer", "VarClient" }
local IDS_PER_TICK = 600          -- how much to scan per server tick
local MAX_CONSECUTIVE_MISSES = 5000
local HARD_ID_LIMIT = 150000
local HOUR_WINDOW_SECONDS = 45    -- log changes this close to the hour

local function say(...)
    print("[VoS discovery]", ...)
end

--------------------------------------------------------------------------------
-- 1 and 2: environment
--------------------------------------------------------------------------------

local clockUnix, clockTick, latestTick = nil, nil, 0
local okTime, osTime = pcall(function() return os and os.time and os.time() end)
if okTime and type(osTime) == "number" then
    clockUnix, clockTick = osTime, 0
    say("os.time() is AVAILABLE:", osTime)
else
    say("os.time() is NOT available (" .. tostring(osTime) .. ")")
end

local function permissionState(permission)
    local ok, granted = pcall(function() return Plugin.HasPermission(permission) end)
    if not ok then return "unknown" end
    return granted and "granted" or "not granted"
end
say("httpAccess:", permissionState(PluginPermissions.httpAccess))
say("chatAccess:", permissionState(PluginPermissions.chatAccess))

local function now()
    if clockUnix == nil then return nil end
    return clockUnix + (latestTick - clockTick) / 50
end

Event.Logic.Subscribe("vosDiscoveryClock", function(event)
    latestTick = event.logicTick
    if clockTick == 0 and clockUnix ~= nil then
        clockTick = latestTick -- anchor os.time() to the first tick we see
    end
end)

--------------------------------------------------------------------------------
-- 3: scan variable names
--------------------------------------------------------------------------------

local matches = {} -- configName -> { domain = ..., id = ... }

local function nameMatches(name)
    local upper = string.upper(name or "")
    for _, keyword in ipairs(KEYWORDS) do
        if string.find(upper, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function describe(variable)
    local ok, value = pcall(function() return variable.value end)
    local okType, valueType = pcall(function() return variable.valueType end)
    return string.format("id=%s name=%s type=%s value=%s varbit=%s",
        tostring(variable.id), tostring(variable.configName),
        okType and tostring(valueType) or "?", ok and tostring(value) or "?",
        tostring(variable.isVarBit))
end

local function lookup(domain, variableId)
    local ok, variable = pcall(function() return var[domain].FromID(variableId) end)
    if ok then return variable end
    return nil
end

-- A scan job walks IDs in one direction (up from 0, or down from -1 for
-- varbits, whose IDs are negative) until it hits a long run of gaps.
local jobs = {}
for _, domain in ipairs(DOMAINS) do
    table.insert(jobs, { domain = domain, nextId = 0, step = 1, misses = 0, found = 0 })
    table.insert(jobs, { domain = domain, nextId = -1, step = -1, misses = 0, found = 0 })
end

local function scanStep()
    local job = jobs[1]
    if job == nil then return false end
    for _ = 1, IDS_PER_TICK do
        local variable = lookup(job.domain, job.nextId)
        if variable ~= nil then
            job.misses = 0
            job.found = job.found + 1
            local name = variable.configName
            if nameMatches(name) then
                matches[name] = { domain = job.domain, id = job.nextId }
                say("MATCH", job.domain, describe(variable))
            end
        else
            job.misses = job.misses + 1
        end
        job.nextId = job.nextId + job.step
        if job.misses >= MAX_CONSECUTIVE_MISSES or math.abs(job.nextId) > HARD_ID_LIMIT then
            say(string.format("finished %s %s: %d variables found",
                job.domain, job.step > 0 and "(normal)" or "(varbits)", job.found))
            table.remove(jobs, 1)
            if #jobs == 0 then
                say("Scan complete. Matching variables will be logged when they change.")
            end
            return true
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- 4: variables that change around the top of the hour
--------------------------------------------------------------------------------

local function nearHourChange(unixSeconds)
    if unixSeconds == nil then return false end
    local intoHour = math.floor(unixSeconds) % 3600
    return intoHour <= HOUR_WINDOW_SECONDS or intoHour >= 3600 - HOUR_WINDOW_SECONDS
end

Event.VarTransmit.Subscribe("vosDiscoveryVars", function(event)
    local name = event.var and event.var.configName or "?"
    local isMatch = matches[name] ~= nil
    local t = now()
    if isMatch or nearHourChange(t) then
        say(isMatch and "CHANGE (matched)" or "CHANGE (near hour)",
            "t=" .. tostring(t and math.floor(t) or "?"), name,
            tostring(event.oldValue) .. " -> " .. tostring(event.newValue))
    end
end)

--------------------------------------------------------------------------------
-- 5: chat messages mentioning Seren
--------------------------------------------------------------------------------

Event.ChatMessage.Subscribe("vosDiscoveryChat", function(event)
    if clockUnix == nil and type(event.timestamp) == "number" then
        clockUnix, clockTick = event.timestamp, latestTick
        say("Clock learned from chat timestamp:", event.timestamp)
    end
    local text = event.chatMessage or ""
    if string.find(string.lower(text), "seren", 1, true) then
        say("CHAT type=" .. tostring(event.chatType),
            "sender='" .. tostring(event.senderNameUnfiltered) .. "'",
            "time=" .. tostring(event.timestamp), "text=" .. text)
    end
end)

--------------------------------------------------------------------------------
-- Drive the scan from the server tick
--------------------------------------------------------------------------------

say("Scanning variable names. This takes a minute or two...")
Event.ServerLogic.Subscribe("vosDiscoveryScan", function()
    if not scanStep() then
        Event.ServerLogic.Unsubscribe("vosDiscoveryScan")
    end
end)
