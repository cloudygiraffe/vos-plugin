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
--   * The data is crowdsourced (from Alt1 users standing in Prifddinas), so
--     it can lag behind the game. On October 22nd, 2026 it was two days out of
--     date, and there is no public way for this plugin to contribute readings. The timestamp
--     says which hour it describes; the plugin only treats it as current if
--     that hour matches the real clock. It also ranks lowest of the sources,
--     so the game's own announcement always wins for the same hour.
--   * The Wiki asks API users to send a descriptive User-Agent.
--   * Requests are spaced out: once shortly after each hour change (with a
--     little spread so every player does not ask at the same second), and
--     retries no more often than every 5 minutes.
--
-- Permission: needs the optional "httpAccess" permission. The base URL is
-- declared in plugin.json under "urls" -> "weirdgloop".

local Clans = require("src/clans")
local TimeUtil = require("src/timeutil")
local Clock = require("src/clock")
local VosState = require("src/vos_state")

local ApiSource = {}

ApiSource.LABEL = "RuneScape Wiki API"
ApiSource.PATH = "/runescape/vos"
ApiSource.USER_AGENT = "rs3-voice-of-seren-plugin/0.1 (+https://github.com/cloudygiraffe/vos-plugin)"

local RETRY_SECONDS = 300            -- data not updated yet, or request failed
local AFTER_HOUR_CHANGE_SECONDS = 90 -- give the wiki time to update each hour
local SPREAD_SECONDS = 60            -- up to this much extra delay, varies per player
local UNKNOWN_CLOCK_SECONDS = 600    -- poll interval if we never learn the time
local HTTP_OK = 200

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
        rank = VosState.RANK.WIKI_API,
    }
end

-- True if the player granted the optional web-request permission.
function ApiSource.IsAllowed()
    local ok, granted = pcall(function()
        return Plugin.HasPermission(PluginPermissions.httpAccess)
    end)
    return ok and granted == true
end

-- Decides how long to wait before the next request:
--   clock unknown       -> every 10 minutes
--   data is this hour's -> just after the next hour change (+ per-player spread)
--   data is old/failed  -> retry in 5 minutes
local function scheduleNext(dataIsCurrent)
    local delaySeconds
    local now = Clock.Now()
    if now == nil then
        delaySeconds = UNKNOWN_CLOCK_SECONDS
    elseif dataIsCurrent then
        -- A per-player spread taken from the client's tick count, so that
        -- not every player asks the Wiki at exactly the same moment.
        local spread = Clock.CurrentTick() % (SPREAD_SECONDS + 1)
        delaySeconds = TimeUtil.SecondsUntilNextHour(now) + AFTER_HOUR_CHANGE_SECONDS + spread
    else
        delaySeconds = RETRY_SECONDS
    end
    nextRequestTick = Clock.CurrentTick() + Clock.SecondsToTicks(delaySeconds)
end

-- Asks for a request on the next Update() call, e.g. right after the player
-- grants the web-request permission.
function ApiSource.RequestSoon()
    nextRequestTick = 0
end

-- Text describing the last problem talking to the Wiki, or nil if the last
-- request worked. Shown in the panel.
function ApiSource.LastError()
    return lastErrorText
end

-- Records a failed request and schedules a retry.
local function fail(message)
    lastErrorText = message
    scheduleNext(false)
end

-- Called regularly (every server tick). Starts a request when one is due and
-- the player has granted httpAccess; at most one request is in flight.
-- onReading(reading) is called with each successful result, even an
-- out-of-date one (VosState keeps it as history and shows "waiting for this
-- hour"). Failures are recorded for LastError() and retried later.
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

        if finished.cancelled then
            fail(nil)
            return
        end
        if finished.timedOut then
            fail("Wiki API timed out")
            return
        end
        if not finished.successful then
            fail("Wiki API request failed (error " .. tostring(finished.errorCode) .. ")")
            return
        end
        -- "successful" means a response arrived; check it was not an error page.
        if finished.responseCode ~= nil and finished.responseCode ~= HTTP_OK then
            fail("Wiki API returned HTTP " .. tostring(finished.responseCode))
            return
        end

        -- The response's Date header tells us the real time.
        local serverTime = TimeUtil.ParseHttpDateHeader(finished.header)
        if serverTime then
            Clock.Sync(serverTime)
        end

        local reading, parseError = ApiSource.ParseBody(finished.data)
        if reading == nil then
            fail("Wiki API: " .. parseError)
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
