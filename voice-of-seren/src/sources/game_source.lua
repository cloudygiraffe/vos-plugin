-- sources/game_source.lua
-- Reads the Voice of Seren straight from game variables, if the client has
-- them. This would be the best source: no permissions needed, and instant.
--
-- STATUS: not wired up yet. Inside Prifddinas the game shows two clan icons
-- for the active Voice, so the client must receive that data somehow, but the
-- variable names and their value encoding are not documented. Finding them is
-- the job of the discovery tool in tools/vos-discovery (see docs/TESTING.md).
--
-- Once the discovery tool has identified the variable(s), add them to
-- KNOWN_VARIABLES below. Each entry says where the variable lives and how to
-- turn its value into clan names. Everything else in this file already works
-- off that table, so no other code needs to change.

local Clock = require("src/clock")
local TimeUtil = require("src/timeutil")

local GameSource = {}

GameSource.LABEL = "game data"

-- Example of what an entry will look like once the variable is known:
--
--   {
--       domain = "VarPlayer",       -- "VarPlayer" or "VarClient"
--       name = "PRIF_VOS_DISTRICTS", -- configName reported by the discovery tool
--       decode = function(value)
--           -- turn the raw value into a list of clan names, e.g. via a
--           -- lookup table of clan IDs -> names
--           return { "Iorwerth", "Cadarn" }
--       end,
--   },
local KNOWN_VARIABLES = {
}

-- Looks up a variable config by domain and name. Returns nil if the game
-- does not expose it (for example, it only exists while in Prifddinas).
local function findVariable(entry)
    local ok, variable = pcall(function()
        return var[entry.domain][entry.name]
    end)
    if ok then
        return variable
    end
    return nil
end

-- Builds a reading from the current values of all known variables, or
-- returns nil if nothing usable was found.
local function readAll()
    for _, entry in ipairs(KNOWN_VARIABLES) do
        local variable = findVariable(entry)
        if variable ~= nil then
            local ok, clans = pcall(entry.decode, variable.value)
            if ok and type(clans) == "table" and #clans > 0 then
                local now = Clock.Now()
                return {
                    clans = clans,
                    hourStart = now and TimeUtil.HourStart(now) or nil,
                    source = GameSource.LABEL,
                    observedAt = now,
                }
            end
        end
    end
    return nil
end

-- True once at least one variable has been configured.
function GameSource.IsConfigured()
    return #KNOWN_VARIABLES > 0
end

-- Reads the variables once, e.g. when the plugin starts.
function GameSource.Poll(onReading)
    if not GameSource.IsConfigured() then
        return
    end
    local reading = readAll()
    if reading then
        onReading(reading)
    end
end

-- Handles a VarTransmit event: re-read if one of our variables changed.
function GameSource.HandleVarTransmit(event, onReading)
    if not GameSource.IsConfigured() or event == nil or event.var == nil then
        return
    end
    local changedName = event.var.configName
    for _, entry in ipairs(KNOWN_VARIABLES) do
        if entry.name == changedName then
            GameSource.Poll(onReading)
            return
        end
    end
end

return GameSource
