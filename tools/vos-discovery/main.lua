-- VoS Discovery (developer tool; never submit this to the Plugin Hub)
--
-- Run on the plugin beta world to collect what the Voice of Seren plugin
-- needs to know about the game. Everything is printed to the client console
-- (Alt + the key under Esc). Copy the console output into an issue.
--
-- What it prints, in order:
--   1. Environment: whether os.time() exists in the plugin sandbox, and
--      whether the optional permissions are granted.
--   2. "VOS VARS ..." lines: the known Voice variables (ELFCITY_VOICE1/2_PLAYER,
--      ELFCITY_VOS_PLAYER_HOUR, plus the VoS-weekend ones), once at load and
--      again whenever any of them changes. This is the main job now: stand in
--      Prifddinas across an hour change and note which two clans the city
--      shows, to pin down which number means which clan
--      (voice-of-seren/src/sources/game_source.lua, KNOWN_PAIRS).
--   3. "CHANGE ..." lines: any variable that changes within 45 seconds of the
--      top of the hour (needs a clock: os.time() or a chat timestamp), plus
--      changes to variables found by the name scan.
--   4. "CHAT ..." lines: chat messages mentioning "Seren", with their chat
--      type, sender and timestamp (needs the optional chatAccess permission).
--      Useful to check whether the announcement is shown outside Prifddinas.
--   5. Optional (SCAN_NAMES = true): a slow scan of every VarPlayer/VarClient
--      ID for Voice-related names. No longer needed: the console commands
--      `pan VarPlayer` / `pan VarClient` copy the client's full variable list
--      to the clipboard.
--
-- Status: findings so far are recorded in docs/DESIGN.md ("Findings on the
-- beta world").

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SCAN_NAMES = false          -- set to true to run the slow name scan (5)
local KEYWORDS = {                -- name fragments the scan looks for
    "VOICE", "SEREN", "VOS", "PRIF", "CLAN", "DISTRICT", "ELF",
    "AMLODD", "CADARN", "CRWYS", "HEFIN", "IORWERTH", "ITHELL", "MEILYR", "TRAHAEARN",
}
local DOMAINS = { "VarPlayer", "VarClient" }
local IDS_PER_TICK = 600          -- IDs scanned per server tick
local MAX_CONSECUTIVE_MISSES = 5000
local HARD_ID_LIMIT = 150000
local HOUR_WINDOW_SECONDS = 45    -- log every change this close to the hour

-- Variables printed as "VOS VARS" (from the client's `pan` lists).
local WATCH = {
    { name = "ELFCITY_VOICE1_PLAYER",          domain = "VarPlayer", id = -25159 },
    { name = "ELFCITY_VOICE2_PLAYER",          domain = "VarPlayer", id = -25160 },
    { name = "ELFCITY_VOS_PLAYER_HOUR",        domain = "VarPlayer", id = -26417 },
    { name = "VOS_WEEKEND_ACTIVE_VOICE",       domain = "VarPlayer", id = -43944 },
    { name = "VOS_WEEKEND_NEXT_VOICE_MINUTES", domain = "VarClient", id = 6567 },
}

local function say(...)
    print("[VoS discovery]", ...)
end

--------------------------------------------------------------------------------
-- 1: environment, and a simple clock for time-stamping output
--------------------------------------------------------------------------------

-- clockUnix is the Unix time at logic tick clockTick (0 means "anchor to the
-- first tick seen"); latestTick is updated 50 times a second.
local clockUnix, clockTick, latestTick = nil, nil, 0
local okTime, osTime = pcall(function() return os and os.time and os.time() end)
if okTime and type(osTime) == "number" then
    clockUnix, clockTick = osTime, 0
    say("os.time() is AVAILABLE:", osTime)
else
    say("os.time() is NOT available (" .. tostring(osTime) .. ")")
end

-- "granted", "not granted" or "unknown" (if the API call fails).
local function permissionState(permission)
    local ok, granted = pcall(function() return Plugin.HasPermission(permission) end)
    if not ok then return "unknown" end
    return granted and "granted" or "not granted"
end
say("httpAccess:", permissionState(PluginPermissions.httpAccess))
say("chatAccess:", permissionState(PluginPermissions.chatAccess))

-- Current Unix time, or nil if no clock source has been seen yet.
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
-- 2: watch the known Voice variables ("VOS VARS")
-- Polled every server tick rather than relying on VarTransmit, whose naming
-- of varbits isn't documented.
--------------------------------------------------------------------------------

-- Reads a watched variable, or returns "unreadable".
local function readWatched(entry)
    local ok, value = pcall(function() return var[entry.domain].FromID(entry.id).value end)
    if ok then return value end
    return "unreadable"
end

local lastWatched = {}

-- Prints one "VOS VARS" line if any watched value changed (or if `force`).
local function checkWatched(force)
    local changed = false
    for _, entry in ipairs(WATCH) do
        local value = readWatched(entry)
        if force or value ~= lastWatched[entry.name] then
            lastWatched[entry.name] = value
            changed = true
        end
    end
    if changed then
        local parts = {}
        for _, entry in ipairs(WATCH) do
            table.insert(parts, entry.name .. "=" .. tostring(lastWatched[entry.name]))
        end
        local unix = now()
        say("VOS VARS" .. (unix and (" at unix " .. unix) or "") .. ": " .. table.concat(parts, "  "))
    end
end

checkWatched(true)
Event.ServerLogic.Subscribe("vosDiscoveryWatch", function()
    checkWatched(false)
end)

--------------------------------------------------------------------------------
-- 5 (optional): scan variable names
--------------------------------------------------------------------------------

local matches = {} -- configName -> { domain = ..., id = ... }, filled by the scan

local function nameMatches(name)
    local upper = string.upper(name or "")
    for _, keyword in ipairs(KEYWORDS) do
        if string.find(upper, keyword, 1, true) then
            return true
        end
    end
    return false
end

-- One-line description of a variable for the console.
local function describe(variable)
    local ok, value = pcall(function() return variable.value end)
    local okType, valueType = pcall(function() return variable.valueType end)
    return string.format("id=%s name=%s type=%s value=%s varbit=%s",
        tostring(variable.id), tostring(variable.configName),
        okType and tostring(valueType) or "?", ok and tostring(value) or "?",
        tostring(variable.isVarBit))
end

-- The variable with this ID, or nil if there isn't one.
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

-- Scans up to IDS_PER_TICK IDs. Returns false once every job is finished.
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

if SCAN_NAMES then
    say("Scanning variable names. This takes a minute or two...")
end
-- Once finished, the handler does nothing (unsubscribing from inside its own
-- handler is not documented).
local scanFinished = not SCAN_NAMES
Event.ServerLogic.Subscribe("vosDiscoveryScan", function()
    if not scanFinished then
        scanFinished = not scanStep()
    end
end)

--------------------------------------------------------------------------------
-- 3: variables that change around the top of the hour
--------------------------------------------------------------------------------

-- True if unixSeconds is within HOUR_WINDOW_SECONDS of an hour boundary.
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
-- 4: chat messages mentioning Seren (only delivered with chatAccess)
--------------------------------------------------------------------------------

Event.ChatMessage.Subscribe("vosDiscoveryChat", function(event)
    -- A chat timestamp is also a clock, if os.time() wasn't available.
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
