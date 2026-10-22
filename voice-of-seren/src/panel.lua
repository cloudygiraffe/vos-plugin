-- panel.lua
-- The plugin's window, opened from its icon in the Plugins ribbon window.
--
-- The game hands the plugin an empty layer every time the window is shown
-- (the ContentLayerReady event), so Build() recreates the components each
-- time and Refresh() fills them in.
--
-- Layout, top to bottom:
--   title and status ("Active now. Changes in 37 min.")
--   the two active clans with what they boost
--   where the information came from
--   "Alert me when the Voice is in:" checkboxes, one per clan
--   on/off checkbox for the on-screen strip
--   the last few hours
--   tips, if the plugin has no way to read the Voice yet

local Clans = require("src/clans")
local Display = require("src/display")

local Panel = {}
Panel.__index = Panel

local FONT = id.Font.MUSEO_SANS_15PT_REGULAR
local LINE = 20       -- height of a one-line text row
local GAP = 4         -- space between rows
local EFFECT_ROWS = 4 -- effect lines reserved per clan card
local HISTORY_ROWS = 4

-- callbacks:
--   onWatchChanged(clanName, isWatched)
--   onHudToggled(isEnabled)
function Panel.new(callbacks)
    local self = setmetatable({}, Panel)
    self.callbacks = callbacks
    self.root = nil
    self.parts = {}
    return self
end

-- Adds a full-width text row at vertical position y and returns it.
local function addText(parent, y, rows)
    local text = ui.Text.new(parent)
    text:SetPos(0, y)
    text:SetSize(0, LINE * rows, 1.0, 0.0) -- full parent width
    text.font = FONT
    text.maxLines = rows
    -- ui.AlignMode has TOPLEFT, CENTRE, BOTTOMRIGHT and JUSTIFY; TOPLEFT means
    -- "left" when used horizontally and "top" when used vertically.
    text:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.TOPLEFT)
    text.content = ""
    return text
end

-- Adds a checkbox at (x as a fraction of the width, y in pixels).
local function addCheck(parent, xFraction, y, label, ticked, onToggle)
    local check = ui.Check.new(parent)
    check:SetPos(0, y, xFraction, 0.0)
    check:SetSize(0, LINE + 2, 0.5, 0.0) -- half the parent width
    check.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT
    check.alignment = ui.CheckAlignMode.LEFT
    check.label = label
    check.value = ticked
    check:Subscribe(ui.Hook.ONBUTTONPRESSED, function(_, isTicked)
        onToggle(isTicked == true)
    end)
    return check
end

-- Creates every component on the layer the game provided.
--   watched    : set of watched clan names (to tick the boxes)
--   hudEnabled : whether the on-screen strip is on
function Panel:Build(root, watched, hudEnabled)
    self.root = root
    self.parts = {}
    local parts = self.parts
    local y = 0

    parts.title = addText(root, y, 1)
    parts.title.content = "<col=ffd24a>Voice of Seren</col>"
    y = y + LINE + GAP

    parts.status = addText(root, y, 1)
    y = y + LINE + GAP * 2

    -- Two clan cards: a heading line, then effect lines.
    parts.cards = {}
    for index = 1, 2 do
        local heading = addText(root, y, 1)
        y = y + LINE
        local effects = addText(root, y, EFFECT_ROWS)
        y = y + LINE * EFFECT_ROWS + GAP
        parts.cards[index] = { heading = heading, effects = effects }
    end

    parts.source = addText(root, y, 1)
    y = y + LINE + GAP * 2

    local alertLabel = addText(root, y, 1)
    alertLabel.content = "Alert me when the Voice is in:"
    y = y + LINE + GAP

    -- Eight clan checkboxes in two columns.
    for index, clan in ipairs(Clans.LIST) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        addCheck(root, column * 0.5, y + row * (LINE + GAP), clan.name,
            watched[clan.name] == true,
            function(isTicked) self.callbacks.onWatchChanged(clan.name, isTicked) end)
    end
    y = y + 4 * (LINE + GAP) + GAP

    addCheck(root, 0.0, y, "Show on-screen strip", hudEnabled,
        function(isTicked) self.callbacks.onHudToggled(isTicked) end)
    y = y + LINE + GAP * 3

    local historyLabel = addText(root, y, 1)
    historyLabel.content = "Recent hours:"
    y = y + LINE

    parts.history = addText(root, y, HISTORY_ROWS)
    y = y + LINE * HISTORY_ROWS + GAP

    parts.help = addText(root, y, 3)
end

-- True if the panel is built and currently on screen.
function Panel:IsVisible()
    if self.root == nil then
        return false
    end
    local ok, visible = pcall(function() return self.root.visibleGlobal end)
    return ok and visible == true
end

-- Fills in the panel from the latest information. `view` is a table built by
-- main.lua with: current, isCurrent, now, history, httpAllowed, chatAllowed,
-- gameConfigured.
function Panel:Refresh(view)
    if not self:IsVisible() then
        return
    end
    local parts = self.parts

    -- Components can disappear if the window closes mid-update; never let
    -- that stop the plugin.
    pcall(function()
        parts.status.content = Display.StatusLine(view.current, view.isCurrent, view.now)

        for index = 1, 2 do
            local card = parts.cards[index]
            local clanName = view.current and view.current.clans[index] or nil
            if clanName then
                local heading, effects = Display.ClanCard(clanName)
                card.heading.content = heading
                card.effects.content = effects
            else
                card.heading.content = ""
                card.effects.content = ""
            end
        end

        parts.source.content = Display.SourceLine(view.current, view.now)
        parts.history.content = Display.HistoryText(view.history, view.now, HISTORY_ROWS)
        parts.help.content = Display.HelpText(view.httpAllowed, view.chatAllowed, view.gameConfigured)
    end)
end

return Panel
