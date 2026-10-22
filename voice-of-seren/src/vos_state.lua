-- vos_state.lua
-- Holds what the plugin currently believes the Voice of Seren is, plus a short
-- history of previous hours.
--
-- Readings arrive from several sources (game data, a Prifddinas chat
-- announcement, or the RuneScape Wiki's API). Each one is handed to
-- VosState.Report(), which decides whether it is new, a duplicate, part of
-- the same hour, or out of date.
--
-- A "reading" is a table:
--   clans      : list of one or two clan names, e.g. { "Iorwerth", "Cadarn" }
--   hourStart  : Unix time of the start of the hour it applies to, or nil if
--                the source could not say
--   source     : short label for where it came from ("Prifddinas", "Wiki API", ...)
--   observedAt : Unix time the plugin received it, or nil if the clock is unknown
--   rank       : how trustworthy the source is; higher wins for the same hour
--                (VosState.RANK below)

local TimeUtil = require("src/timeutil")

local VosState = {}

-- Source trust levels. Game data is exact; the Prifddinas announcement comes
-- from the game too; the Wiki API is crowdsourced and can be wrong or late.
VosState.RANK = {
    SAVED = 0,
    WIKI_API = 1,
    CHAT = 2,
    GAME = 3,
}

local MAX_HISTORY = 24 -- one day of hourly entries
local MAX_ACTIVE_CLANS = 2

local current = nil -- the latest reading, or nil if nothing has been seen yet
local history = {}  -- newest first: { hourStart = number, clans = { ... } }

-- Returns a copy of a list so callers cannot change our stored data.
local function copyList(list)
    local result = {}
    for index, value in ipairs(list) do
        result[index] = value
    end
    return result
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

-- Adds or replaces the history entry for one hour, keeping newest first.
local function recordHistory(hourStart, clans)
    if hourStart == nil then
        return
    end
    for index, entry in ipairs(history) do
        if entry.hourStart == hourStart then
            history[index] = { hourStart = hourStart, clans = copyList(clans) }
            return
        end
    end
    table.insert(history, { hourStart = hourStart, clans = copyList(clans) })
    table.sort(history, function(a, b) return a.hourStart > b.hourStart end)
    while #history > MAX_HISTORY do
        table.remove(history)
    end
end

-- Takes in a new reading. Returns two values:
--   changed  : true if what the plugin shows should be refreshed
--   newClans : list of clans that became active because of this reading
--              (used for alerts); empty if nothing new
function VosState.Report(reading)
    if reading == nil or reading.clans == nil or #reading.clans == 0 then
        return false, {}
    end

    -- Ignore readings about an older hour than the one we already know.
    if current and current.hourStart and reading.hourStart
        and reading.hourStart < current.hourStart then
        recordHistory(reading.hourStart, reading.clans)
        return false, {}
    end

    local rank = reading.rank or 1
    local sameHour = current ~= nil
        and current.hourStart ~= nil
        and current.hourStart == reading.hourStart

    if sameHour then
        if rank < current.rank then
            -- A less trustworthy source (e.g. the Wiki API) never overrides
            -- what the game itself said about this hour.
            return false, {}
        end

        if rank > current.rank then
            -- A more trustworthy source corrects this hour: take its clans.
            local newClans = {}
            for _, clan in ipairs(reading.clans) do
                if not contains(current.clans, clan) then
                    table.insert(newClans, clan)
                end
            end
            current.clans = copyList(reading.clans)
            current.rank = rank
            current.source = reading.source
            current.observedAt = reading.observedAt or current.observedAt
            recordHistory(current.hourStart, current.clans)
            return true, newClans
        end

        -- Same source quality: merge in any clan we did not have yet. This
        -- handles the game announcing each district in a separate message.
        local newClans = {}
        for _, clan in ipairs(reading.clans) do
            if not contains(current.clans, clan) and #current.clans < MAX_ACTIVE_CLANS then
                table.insert(current.clans, clan)
                table.insert(newClans, clan)
            end
        end
        if #newClans > 0 then
            current.observedAt = reading.observedAt or current.observedAt
            recordHistory(current.hourStart, current.clans)
            return true, newClans
        end
        return false, {}
    end

    -- A different (newer, or undated) hour: replace the current reading.
    -- Every clan in it counts as new. A clan cannot hold the Voice two hours
    -- running, so even a clan seen in an earlier hour is a fresh activation.
    current = {
        clans = copyList(reading.clans),
        hourStart = reading.hourStart,
        source = reading.source,
        observedAt = reading.observedAt,
        rank = rank,
    }
    recordHistory(current.hourStart, current.clans)
    return true, copyList(reading.clans)
end

-- Returns the current reading (a copy), or nil if nothing is known.
function VosState.Current()
    if current == nil then
        return nil
    end
    return {
        clans = copyList(current.clans),
        hourStart = current.hourStart,
        source = current.source,
        observedAt = current.observedAt,
    }
end

-- Works out the hour a reading applies to, using hourStart if the source gave
-- one, or the time it was observed otherwise. Returns nil if neither is known.
local function readingHour(reading)
    if reading.hourStart then
        return reading.hourStart
    end
    if reading.observedAt then
        return TimeUtil.HourStart(reading.observedAt)
    end
    return nil
end

-- Returns true if the current reading is for the hour we are in now.
-- `now` is Unix time, or nil if the clock is unknown. Without a clock the
-- plugin cannot tell, so it trusts the latest reading.
function VosState.IsCurrent(now)
    if current == nil then
        return false
    end
    if now == nil then
        return true
    end
    local hour = readingHour(current)
    if hour == nil then
        return true
    end
    return hour == TimeUtil.HourStart(now)
end

-- Returns the history list (copies), newest first.
function VosState.History()
    local result = {}
    for index, entry in ipairs(history) do
        result[index] = { hourStart = entry.hourStart, clans = copyList(entry.clans) }
    end
    return result
end

-- Restores history saved from a previous session (see storage.lua).
function VosState.LoadHistory(savedHistory)
    history = {}
    if type(savedHistory) ~= "table" then
        return
    end
    -- pairs (not ipairs) in case storage returns the list with string keys;
    -- recordHistory sorts the entries anyway.
    for _, entry in pairs(savedHistory) do
        if type(entry) == "table" and type(entry.hourStart) == "number"
            and type(entry.clans) == "table" then
            local clans = {}
            for _, clan in pairs(entry.clans) do
                table.insert(clans, clan)
            end
            recordHistory(entry.hourStart, clans)
        end
    end
end

-- After a relog, the saved history may already contain this hour's Voice.
-- Once the clock is known, this promotes that entry to "current" so the panel
-- is not blank until the next announcement. It also replaces a reading that
-- turned out to be for an older hour. Returns true if it did.
function VosState.RestoreCurrentFromHistory(now)
    if now == nil or history[1] == nil or VosState.IsCurrent(now) then
        return false
    end
    if history[1].hourStart ~= TimeUtil.HourStart(now) then
        return false
    end
    current = {
        clans = copyList(history[1].clans),
        hourStart = history[1].hourStart,
        source = "saved from earlier this hour",
        observedAt = nil,
        rank = VosState.RANK.SAVED,
    }
    return true
end

-- Test helper: clear everything.
function VosState.Reset()
    current = nil
    history = {}
end

return VosState
