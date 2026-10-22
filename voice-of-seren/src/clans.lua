-- clans.lua
-- Static information about the eight elven clans of Prifddinas and what the
-- Voice of Seren does for each of their districts.
--
-- The Voice is active in two districts at a time and moves every hour. This
-- file only describes the clans; it never decides which ones are active.
-- Effects are summarised from the RuneScape Wiki "Voice of Seren" page.

local Clans = {}

-- Every active district also gives bonus Thieving XP from its workers, more
-- golden rocks in the clan's skill, and a chance of a crystal impling. The
-- panel does not repeat those for each clan, to save space.

-- One entry per clan, in alphabetical order (the order used in the UI).
--   name    : the clan name exactly as the game writes it
--   skills  : short list of the skills the Voice boosts, for at-a-glance display
--   effects : one line per effect, shown in the panel
Clans.LIST = {
    {
        name = "Amlodd",
        skills = "Summoning, Divination",
        effects = {
            "More Summoning XP and scrolls when making pouches",
            "More Divination XP from shadow cores",
            "Chance of chronicle fragments from some shadows",
        },
    },
    {
        name = "Cadarn",
        skills = "Ranged, Magic",
        effects = {
            "Bonus Ranged or Magic XP for killing Cadarn rangers and magi",
        },
    },
    {
        name = "Crwys",
        skills = "Woodcutting, Farming",
        effects = {
            "Bonus Woodcutting and Farming XP",
            "Crystal geodes replace bird's nests",
            "Crops can skip growth stages, and butterflies spawn",
        },
    },
    {
        name = "Hefin",
        skills = "Agility, Prayer",
        effects = {
            "Bonus Agility XP and faster velocity on the Hefin course",
            "Bonus Prayer XP per lap",
            "Bonus Prayer XP for cleansing the Corrupted Seren Stone",
        },
    },
    {
        name = "Iorwerth",
        skills = "Attack, Strength, Slayer",
        effects = {
            "Bonus Attack and Strength XP for killing Iorwerth guards and scouts",
            "Some Slayer XP in Rush of Blood",
        },
    },
    {
        name = "Ithell",
        skills = "Crafting, Construction",
        effects = {
            "Bonus Crafting and Construction XP from harps",
            "Bonus Crafting XP from crystal flasks",
            "Double Construction Supplies stock; soft clay can go to the bank",
        },
    },
    {
        name = "Meilyr",
        skills = "Herblore, Farming",
        effects = {
            "Bonus Farming XP from fruit trees and harmony pillars",
            "Trees can skip growth stages",
            "Bonus Herblore XP from combination potions",
        },
    },
    {
        name = "Trahaearn",
        skills = "Mining, Smithing, Farming",
        effects = {
            "Bonus Smithing XP from smelting corrupted ore",
            "Animica rocks spawn, and mining gives extra ore",
            "Bonus Farming XP; trees can skip growth stages",
        },
    },
}

-- Lookup table from lower-case clan name to its entry, built once.
local byLowerName = {}
for _, clan in ipairs(Clans.LIST) do
    byLowerName[string.lower(clan.name)] = clan
end

-- Returns the clan entry for a name (case-insensitive), or nil if unknown.
function Clans.Get(name)
    if type(name) ~= "string" then
        return nil
    end
    return byLowerName[string.lower(name)]
end

-- Returns the correctly capitalised clan name, or nil if the name is unknown.
-- Used to clean up names that arrive from chat messages or the web API.
function Clans.Normalise(name)
    local clan = Clans.Get(name)
    if clan then
        return clan.name
    end
    return nil
end

-- Finds every clan name mentioned in a piece of text, in the order they first
-- appear. Each clan is returned at most once.
-- Example: "...active in the Amlodd and Cadarn districts" -> { "Amlodd", "Cadarn" }
function Clans.FindAllInText(text)
    local found = {}
    if type(text) ~= "string" then
        return found
    end
    local lowerText = string.lower(text)

    -- Record the position of each clan name so results follow the text order.
    local hits = {}
    for _, clan in ipairs(Clans.LIST) do
        local position = string.find(lowerText, string.lower(clan.name), 1, true)
        if position then
            table.insert(hits, { position = position, name = clan.name })
        end
    end
    table.sort(hits, function(a, b) return a.position < b.position end)

    for _, hit in ipairs(hits) do
        table.insert(found, hit.name)
    end
    return found
end

return Clans
