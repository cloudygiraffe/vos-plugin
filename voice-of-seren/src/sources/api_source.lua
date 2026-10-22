-- sources/api_source.lua
-- Reads the Voice of Seren from the RuneScape Wiki's public API, run by
-- Weird Gloop at https://api.weirdgloop.org.
--
-- Endpoint: GET /runescape/vos
-- Example response (checked October 22nd, 2026):
--   {"timestamp":"2026-10-20T14:00:00.000Z","district1":"Iorwerth",
--    "district2":"Trahaearn","source":"alt1-crowdsourced"}
--
-- Notes:
--   * The data is crowdsourced, so it can lag behind the game. The timestamp
--     says which hour it describes; the plugin only treats it as current if
--     that hour matches the real clock.
--   * The Wiki asks API users to send a descriptive User-Agent.
--   * Requests are spaced out: once shortly after each hour change, with
--     retries no more often than every 5 minutes.
--
-- Permission: needs the optional "httpAccess" permission. The base URL is
-- declared in plugin.json under "urls" -> "weirdgloop".

local Clans = require("src/clans")
local TimeUtil = require("src/timeutil")
local Clock = require("src/clock")

local ApiSource = {}

ApiSource.LABEL = "RuneScape Wiki API"
ApiSource.PATH = "/runescape/vos"
ApiSource.USER_AGENT = "rs3-voice-of-seren-plugin/0.1 (+https://github.com/cloudygiraffe/vos-plugin)"

local RETRY_SECONDS = 300            -- data not updated yet, or request failed
local AFTER_HOUR_CHANGE_SECONDS = 90 -- give the wiki time to update each hour
local UNKNOWN_CLOCK_SECONDS = 600    -- poll interval if we never learn the time

local requestInFlight = false
local nextRequestTick = 0
local lastErrorText = nil

-- Pulls one string field out of a flat JSON object. The API returns a tiny,
-- flat object, so a full JSON parser is not needed.
local function jsonString(body, fieldName)
    return string.match(body, '"' .. fieldName .. '"%s*:%s*"([^"]*)"')
end

-- Turns a response body into a reading, or returns nil, errorText.
-- Pure function: easy to unit test.
function ApiSource.ParseBody(body)
    if type(body) ~= "string" or body == "" then
        return nil, "empty response"
    end
    local first = Clans.Normalise(jsonString(body, "district1"))
    local second = Clans.Normalise(jsonString(body, "district2"))
    if first == nil or second == nil then
        return nil, "unrecognised clan names in response"
    end
    local hourStart = TimeUtil.ParseIso8601(jsonString(body, "timestamp"))
    return {
        clans = { first, second },
        hourStart = hourStart and TimeUtil.HourStart(hourStart) or nil,
        source = ApiSource.LABEL,
        observedAt = Clock.Now(),
    }
end

-- True if the player granted the optional web-request permission.
function ApiSource.IsAllowed()
    if Plugin == nil or PluginPermissions == nil then
        return false
    end
    return Plugin.HasPermission(PluginPermissions.httpAccess)
end

-- Decides how long to wait before the next request.
local function scheduleNext(dataIsCurrent)
    local delaySeconds
    local now = Clock.Now()
    if now == nil then
        delaySeconds = UNKNOWN_CLOCK_SECONDS
    elseif dataIsCurrent then
        delaySeconds = TimeUtil.SecondsUntilNextHour(now) + AFTER_HOUR_CHANGE_SECONDS
    else
        delaySeconds = RETRY_SECONDS
    end
    nextRequestTick = Clock.CurrentTick() + Clock.SecondsToTicks(delaySeconds)
end

-- Asks for an immediate refresh on the next Update() call (e.g. the player
-- just granted the permission, or pressed "Refresh").
function ApiSource.RequestSoon()
    nextRequestTick = 0
end

-- Last error, for the panel ("" or nil when everything is fine).
function ApiSource.LastError()
    return lastErrorText
end

-- Called regularly (every server tick). Starts a request when one is due.
-- onReading(reading) is called with each successful result.
function ApiSource.Update(onReading)
    if requestInFlight or not ApiSource.IsAllowed() then
        return
    end
    if Clock.CurrentTick() < nextRequestTick then
        return
    end

    requestInFlight = true
    local request = HTTPRequest.new(Plugin.urls.weirdgloop, ApiSource.PATH)
    request:AddHeader("User-Agent", ApiSource.USER_AGENT)
    request:Get(function(finished)
        requestInFlight = false

        if not finished.successful then
            if finished.timedOut then
                lastErrorText = "Wiki API timed out"
            else
                lastErrorText = "Wiki API request failed (" .. tostring(finished.errorCode) .. ")"
            end
            scheduleNext(false)
            return
        end

        -- The response's Date header tells us the real time.
        local serverTime = TimeUtil.ParseHttpDateHeader(finished.header)
        if serverTime then
            Clock.Sync(serverTime, "Wiki API server time")
        end

        local reading, parseError = ApiSource.ParseBody(finished.data)
        if reading == nil then
            lastErrorText = "Wiki API: " .. parseError
            scheduleNext(false)
            return
        end

        lastErrorText = nil
        local now = Clock.Now()
        local isCurrent = now ~= nil and reading.hourStart == TimeUtil.HourStart(now)
        reading.observedAt = now
        scheduleNext(isCurrent)
        onReading(reading)
    end)
end

return ApiSource
