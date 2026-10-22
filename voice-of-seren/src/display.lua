-- display.lua
-- Builds the text shown in the on-screen strip and the ribbon panel.
--
-- Kept separate from the UI code so the wording can be unit tested without
-- the game. Uses RuneScape text markup: "<br>" for a line break and
-- "<col=RRGGBB>...</col>" for colour.

local Clans = require("src/clans")
local TimeUtil = require("src/timeutil")

local Display = {}

local HIGHLIGHT_COLOUR = "ffd24a" -- gold, for clans the player is watching
local MUTED_COLOUR = "9a9a9a"     -- grey, for out-of-date information

local function colour(text, hex)
    return "<col=" .. hex .. ">" .. text .. "</col>"
end

-- Joins clan names with a separator, highlighting watched ones.
function Display.ClanNames(clans, watched)
    local parts = {}
    for _, name in ipairs(clans) do
        if watched and watched[name] then
            table.insert(parts, colour(name, HIGHLIGHT_COLOUR))
        else
            table.insert(parts, name)
        end
    end
    return table.concat(parts, " & ")
end

-- One-line summary for the on-screen strip.
--   current   : reading from VosState.Current(), or nil
--   isCurrent : VosState.IsCurrent(now)
--   now       : Unix time or nil
--   watched   : set of watched clan names
function Display.StripText(current, isCurrent, now, watched)
    if current == nil then
        return "Voice of Seren: not known yet"
    end
    local names = Display.ClanNames(current.clans, watched)
    if not isCurrent then
        return colour("Voice of Seren: waiting for this hour (last: "
            .. table.concat(current.clans, " & ") .. ")", MUTED_COLOUR)
    end
    if now == nil then
        return "Voice of Seren: " .. names
    end
    return "Voice of Seren: " .. names .. " | "
        .. TimeUtil.FormatDuration(TimeUtil.SecondsUntilNextHour(now)) .. " left"
end

-- Status line for the panel, under the title.
function Display.StatusLine(current, isCurrent, now)
    if current == nil then
        return "No reading yet. See the tips below."
    end
    if not isCurrent then
        return "Showing an earlier hour. Waiting for this hour's Voice."
    end
    if now == nil then
        return "Active now. Changes at the top of the hour."
    end
    return "Active now. Changes in "
        .. TimeUtil.FormatDuration(TimeUtil.SecondsUntilNextHour(now)) .. "."
end

-- Where the current reading came from, and how old it is.
function Display.SourceLine(current, now)
    if current == nil then
        return ""
    end
    local text = "Source: " .. (current.source or "unknown")
    if current.hourStart then
        text = text .. " | for " .. TimeUtil.FormatGameHour(current.hourStart)
    end
    if now and current.observedAt then
        text = text .. " | updated " .. TimeUtil.FormatAgo(now - current.observedAt)
    end
    return text
end

-- Heading and effect lines for one active clan.
function Display.ClanCard(clanName)
    local clan = Clans.Get(clanName)
    if clan == nil then
        return clanName, ""
    end
    local heading = clan.name .. "  (" .. clan.skills .. ")"
    local lines = {}
    for _, effect in ipairs(clan.effects) do
        table.insert(lines, "- " .. effect)
    end
    return heading, table.concat(lines, "<br>")
end

-- Recent hours, newest first, as one block of text.
function Display.HistoryText(history, now, maxEntries)
    local lines = {}
    for index, entry in ipairs(history) do
        if index > maxEntries then
            break
        end
        local when = TimeUtil.FormatGameHour(entry.hourStart)
        if now then
            local age = TimeUtil.HourStart(now) - entry.hourStart
            if age <= 0 then
                when = "This hour"
            else
                when = when .. " (" .. TimeUtil.FormatAgo(age) .. ")"
            end
        end
        table.insert(lines, when .. ": " .. table.concat(entry.clans, " & "))
    end
    if #lines == 0 then
        return colour("No history yet.", MUTED_COLOUR)
    end
    return table.concat(lines, "<br>")
end

-- Tips for the bottom of the panel (at most 3 lines, the space panel.lua
-- reserves), or a note about the last problem reaching the Wiki API.
--   httpAllowed  : the optional "web requests" permission is granted
--   chatAllowed  : the optional "chat access" permission is granted
--   gameReadable : the game's own Voice variables can be read. They are only
--                  kept up to date inside Prifddinas (observed on the beta
--                  world, October 22nd, 2026), so they never replace the tip
--                  about web requests, which is the only source that works
--                  everywhere.
--   apiError     : text of the last Wiki API problem, or nil
-- Returns "" when there is nothing useful to say.
function Display.HelpText(httpAllowed, chatAllowed, gameReadable, apiError)
    if httpAllowed and apiError then
        return colour(apiError .. ". Retrying in a few minutes.", MUTED_COLOUR)
    end
    if httpAllowed then
        return ""
    end
    local lines = {}
    if gameReadable then
        table.insert(lines, "In Prifddinas the Voice is read from the game. Elsewhere,")
    else
        table.insert(lines, "To see the Voice from anywhere,")
    end
    table.insert(lines, "allow the optional \"web requests\" permission (Plugin Hub > Manage).")
    if not chatAllowed then
        table.insert(lines, "\"Chat access\" also reads the city's own announcement.")
    end
    return colour(table.concat(lines, "<br>"), MUTED_COLOUR)
end

-- Text for an alert when a watched clan becomes active.
function Display.AlertText(clanName)
    local clan = Clans.Get(clanName)
    local skills = clan and (" (" .. clan.skills .. ")") or ""
    return "Voice of Seren is now in " .. clanName .. skills .. "!"
end

return Display
