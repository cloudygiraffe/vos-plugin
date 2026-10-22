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
-- On the beta world at 16:42 UTC the values were 1, 4 and 16 while Cadarn and
-- Iorwerth had the Voice: the hour is the UTC hour, and the clans are numbered
-- alphabetically from 0 (Amlodd) to 7 (Trahaearn). Since 0 is a real clan,
-- an all-zero (not yet sent) value is caught by the "same clan twice" check.

local Clock = require("src/clock")
local TimeUtil = require("src/timeutil")
local VosState = require("src/vos_state")

local GameSource = {}

GameSource.LABEL = "game data"

GameSource.CLAN_BY_NUMBER = {
    [0] = "Amlodd", [1] = "Cadarn", [2] = "Crwys", [3] = "Hefin",
    [4] = "Iorwerth", [5] = "Ithell", [6] = "Meilyr", [7] = "Trahaearn",
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
-- valid pair. Pure; unit tested.
function GameSource.Decode(voice1, voice2)
    if voice1 == nil or voice2 == nil then
        return nil
    end
    local first = GameSource.CLAN_BY_NUMBER[voice1]
    local second = GameSource.CLAN_BY_NUMBER[voice2]
    if first == nil or second == nil or first == second then
        return nil
    end
    return { first, second }
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
    if now then
        local gameHour = read(HOUR)
        local currentHour = math.floor(now / 3600) % 24
        if gameHour ~= currentHour then
            return nil
        end
        hourStart = TimeUtil.HourStart(now)
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
