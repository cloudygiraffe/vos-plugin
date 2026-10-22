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
--      chatAccess permission was granted).
--
-- If none of these are available, Clock.Now() returns nil and the rest of the
-- plugin falls back to messages like "changes at the top of the hour".

local Clock = {}

local LOGIC_TICKS_PER_SECOND = 50

local latestLogicTick = 0   -- updated by OnLogicTick, ~50 times a second
local syncedUnix = nil      -- Unix time at the moment of the last sync
local syncedLogicTick = nil -- logic tick at the moment of the last sync
local syncSource = nil      -- human-readable name of the last sync source

-- Called from the Logic event with the client's running tick count.
function Clock.OnLogicTick(logicTick)
    latestLogicTick = logicTick
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

-- Records that "right now" is `unixSeconds`, according to `sourceName`.
function Clock.Sync(unixSeconds, sourceName)
    if type(unixSeconds) ~= "number" then
        return
    end
    syncedUnix = unixSeconds
    syncedLogicTick = latestLogicTick
    syncSource = sourceName
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
        Clock.Sync(value, "system clock")
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
    local elapsedTicks = latestLogicTick - syncedLogicTick
    return syncedUnix + elapsedTicks / LOGIC_TICKS_PER_SECOND
end

-- Name of the source the clock was last synced from (for the panel), or nil.
function Clock.Source()
    return syncSource
end

-- Test helper: forget any sync. Not used by the plugin itself.
function Clock.Reset()
    latestLogicTick = 0
    syncedUnix = nil
    syncedLogicTick = nil
    syncSource = nil
end

return Clock
