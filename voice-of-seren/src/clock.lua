-- clock.lua
-- Keeps track of the real-world time (Unix seconds, UTC).
--
-- Why this exists: the plugin API has no clock function, but the countdown to
-- the next Voice change needs to know what minute it is. So the plugin learns
-- the time from whatever trustworthy source it can find, then keeps counting
-- forward on its own using the client's logic ticks (a fixed 50 per second).
--
-- Time sources, best first:
--   1. Lua's os.time(), if the plugin sandbox exposes it (not documented, so
--      it is only tried, never assumed).
--   2. The "Date" header on a web response (only if the optional httpAccess
--      permission was granted).
--   3. The timestamp on an incoming chat message (only if the optional
--      chatAccess permission was granted). Only used while nothing better is
--      known, via Clock.SyncIfUnknown.
--
-- If none of these are available, Clock.Now() returns nil and the rest of the
-- plugin falls back to messages like "changes at the top of the hour".

local Clock = {}

local LOGIC_TICKS_PER_SECOND = 50

local latestLogicTick = 0   -- updated by OnLogicTick, ~50 times a second
local hasSeenTick = false   -- false until the first Logic event arrives
local syncedUnix = nil      -- Unix time at the moment of the last sync
local syncedLogicTick = nil -- logic tick at the moment of the last sync
local anchorPending = false -- synced before any tick was seen (see OnLogicTick)

-- Called from the Logic event with the client's running tick count.
function Clock.OnLogicTick(logicTick)
    latestLogicTick = logicTick
    hasSeenTick = true
    -- The logic tick counts up from when the client started, not from when
    -- the plugin loaded. If the clock was synced before the first tick
    -- arrived, anchor it to this first real tick; otherwise the clock would
    -- jump forward by the client's whole uptime.
    if anchorPending then
        syncedLogicTick = logicTick
        anchorPending = false
    end
end

-- Returns the most recent logic tick. Also used by other modules to measure
-- elapsed time without needing the real clock.
function Clock.CurrentTick()
    return latestLogicTick
end

-- Converts a number of seconds into logic ticks.
function Clock.SecondsToTicks(seconds)
    return math.floor(seconds * LOGIC_TICKS_PER_SECOND)
end

-- Records that "right now" is `unixSeconds`.
function Clock.Sync(unixSeconds)
    if type(unixSeconds) ~= "number" then
        return
    end
    syncedUnix = unixSeconds
    if hasSeenTick then
        syncedLogicTick = latestLogicTick
        anchorPending = false
    else
        syncedLogicTick = 0
        anchorPending = true
    end
end

-- Like Sync, but only if the time is not known yet. Used for lower-quality
-- sources such as chat timestamps.
function Clock.SyncIfUnknown(unixSeconds)
    if syncedUnix == nil then
        Clock.Sync(unixSeconds)
    end
end

-- Tries to read the time from os.time(). Returns true if that worked.
function Clock.TrySystemClock()
    local ok, value = pcall(function()
        if os and os.time then
            return os.time()
        end
        return nil
    end)
    if ok and type(value) == "number" then
        Clock.Sync(value)
        return true
    end
    return false
end

-- Returns true once the plugin knows the real time.
function Clock.IsKnown()
    return syncedUnix ~= nil
end

-- Returns the current Unix time, or nil if the time is not known yet.
function Clock.Now()
    if syncedUnix == nil then
        return nil
    end
    if anchorPending then
        return syncedUnix -- no ticks have passed since the sync yet
    end
    local elapsedTicks = latestLogicTick - syncedLogicTick
    return syncedUnix + elapsedTicks / LOGIC_TICKS_PER_SECOND
end

-- Test helper: forget everything. Not used by the plugin itself.
function Clock.Reset()
    latestLogicTick = 0
    hasSeenTick = false
    syncedUnix = nil
    syncedLogicTick = nil
    anchorPending = false
end

return Clock
