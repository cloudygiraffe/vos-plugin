-- sources/game_source.lua
-- Reads the Voice of Seren straight from the game's variables: no
-- permissions needed, and it updates the moment the game sends the change.
--
-- From the client's own variable list (console command `pan VarPlayer`,
-- October 22nd, 2026 beta client):
--
--   ELFCITY_VOICE1_PLAYER    varbit -25159 (VarPlayer 4783, bits 0-6)
--   ELFCITY_VOICE2_PLAYER    varbit -25160 (VarPlayer 4783, bits 7-12)
--   ELFCITY_VOS_PLAYER_HOUR  varbit -26417 (VarPlayer 4783, bits 13-18)
--
-- The hour is the UTC hour. The clan numbers are not alphabetical (nor in
-- any order found in the client's variable list), so only pairs of numbers
-- that have been seen alongside the clans actually active are decoded:
--
--   October 22nd, 2026 16:00 UTC: 1 and 4 = Cadarn and Iorwerth
--   October 22nd, 2026 17:00 UTC: 2 and 3 = Crwys and Trahaearn
--
-- Which number in a pair is which clan isn't known yet, but it doesn't matter
-- for showing the pair. Add more pairs as they are seen (tools/vos-discovery
-- prints the numbers as "VOS VARS"); once every number is pinned down, this
-- can become a simple number -> clan table.
--
-- On leaving Prifddinas the hour dropped to 0 while the clans stayed (same
-- session, 16:57 UTC), so the values are only kept up to date in the city.
-- Without a clock, an hour of 0 is therefore treated as "not in Prifddinas"
-- (at the cost of ignoring the real midnight-UTC hour in that case).

local Clock = require("src/clock")
local TimeUtil = require("src/timeutil")
local VosState = require("src/vos_state")

local GameSource = {}

GameSource.LABEL = "game data"

-- "smaller,larger" -> the two clans, as seen on the beta world.
GameSource.KNOWN_PAIRS = {
    ["1,4"] = { "Cadarn", "Iorwerth" },
    ["2,3"] = { "Crwys", "Trahaearn" },
}

local VOICE1 = { domain = "VarPlayer", id = -25159, name = "ELFCITY_VOICE1_PLAYER" }
local VOICE2 = { domain = "VarPlayer", id = -25160, name = "ELFCITY_VOICE2_PLAYER" }
local HOUR = { domain = "VarPlayer", id = -26417, name = "ELFCITY_VOS_PLAYER_HOUR" }
-- VarTransmit may name the varbit or the VarPlayer that holds all three.
local OUR_NAMES = {
    [VOICE1.name] = true, [VOICE2.name] = true, [HOUR.name] = true, ELFCITY_TEMP_2 = true,
}
local lastKey = nil -- the last reading passed on, so repeats are skipped

local function read(entry)
    local ok, value = pcall(function()
        return var[entry.domain].FromID(entry.id).value
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

-- For tests: replaces the reader and forgets the last reading.
function GameSource.SetReader(reader)
    read = reader
    lastKey = nil
end

-- Turns the raw values into a list of clan names, or nil if they aren't a
-- pair that has been seen before. Pure; unit tested.
function GameSource.Decode(voice1, voice2)
    if type(voice1) ~= "number" or type(voice2) ~= "number" or voice1 == voice2 then
        return nil
    end
    local key = math.min(voice1, voice2) .. "," .. math.max(voice1, voice2)
    local clans = GameSource.KNOWN_PAIRS[key]
    if clans == nil then
        return nil
    end
    return { clans[1], clans[2] }
end

-- Builds a reading from the current values, or nil if nothing usable.
-- If the plugin knows the time, the reading only counts when the game's hour
-- matches the current UTC hour (otherwise it's last hour's Voice).
local function readAll()
    local clans = GameSource.Decode(read(VOICE1), read(VOICE2))
    if clans == nil then
        return nil
    end
    local now = Clock.Now()
    local hourStart = nil
    local gameHour = read(HOUR)
    if now then
        local currentHour = math.floor(now / 3600) % 24
        if gameHour ~= currentHour then
            return nil
        end
        hourStart = TimeUtil.HourStart(now)
    elseif gameHour == nil or gameHour == 0 then
        return nil
    end
    return {
        clans = clans,
        hourStart = hourStart,
        source = GameSource.LABEL,
        observedAt = now,
        rank = VosState.RANK.GAME,
    }
end

-- True once at least one variable has been configured.
function GameSource.IsConfigured()
    return true
end

-- Reads the variables once, e.g. when the plugin starts.
function GameSource.Poll(onReading)
    if not GameSource.IsConfigured() then
        return
    end
    local reading = readAll()
    if reading then
        local key = table.concat(reading.clans, ",") .. "@" .. tostring(reading.hourStart)
        if key ~= lastKey then
            lastKey = key
            onReading(reading)
        end
    end
end

-- Handles a VarTransmit event: re-read if one of our variables changed.
function GameSource.HandleVarTransmit(event, onReading)
    local ok, changedName = pcall(function() return event.var.configName end)
    if ok and OUR_NAMES[changedName] then
        GameSource.Poll(onReading)
    end
end

return GameSource
