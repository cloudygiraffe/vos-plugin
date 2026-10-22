-- hud.lua
-- The small always-visible strip near the top of the game screen, plus a
-- short-lived alert line underneath it.
--
-- Both are plain Text components on the layer the API provides for plugins
-- (TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP). That layer only exists once the game
-- interface is loaded, so building is retried until it succeeds.

local Clock = require("src/clock")

local Hud = {}
Hud.__index = Hud

local STRIP_WIDTH = 420
local STRIP_HEIGHT = 22
local STRIP_TOP = 6
local ALERT_SECONDS = 10

local FONT = id.Font.MUSEO_SANS_15PT_REGULAR

-- Creates the strip controller. Components are built lazily on first use
-- (see EnsureBuilt), because the plugin layer may not exist yet at load time.
function Hud.new()
    local self = setmetatable({}, Hud)
    self.strip = nil
    self.alert = nil
    self.enabled = true
    self.alertHideTick = nil
    return self
end

-- Creates one centred, shadowed line of text on the plugin layer.
local function makeLine(parent, topOffset)
    local text = ui.Text.new(parent)
    text:SetSize(STRIP_WIDTH, STRIP_HEIGHT)
    -- x = 0 px from the parent's centre (0.5), shifted left by half our width (-0.5)
    text:SetPos(0, topOffset, 0.5, 0.0, -0.5, 0.0)
    text.font = FONT
    text.isShadowed = true
    text:AlignTo(ui.AlignMode.CENTRE)
    text.clickthrough = true -- never block clicks on the game underneath
    text.content = ""
    return text
end

-- Tries to build the components. Returns true once they exist.
function Hud:EnsureBuilt()
    if self.strip ~= nil then
        return true
    end
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if parent == nil then
        return false
    end
    local ok = pcall(function()
        self.strip = makeLine(parent, STRIP_TOP)
        self.alert = makeLine(parent, STRIP_TOP + STRIP_HEIGHT + 2)
        self.alert.hidden = true
        self.strip.hidden = not self.enabled
    end)
    if not ok then
        self.strip, self.alert = nil, nil
    end
    return ok
end

-- Runs a change on the components. If they have stopped working (for
-- example the game rebuilt its interface after a trip to the lobby), forget
-- them so the next call builds fresh ones instead of failing every tick.
function Hud:Apply(change)
    if not self:EnsureBuilt() then
        return
    end
    local ok = pcall(change)
    if not ok then
        self.strip, self.alert = nil, nil
    end
end

-- Turns the strip on or off (alerts still show either way).
function Hud:SetEnabled(enabled)
    self.enabled = enabled
    self:Apply(function()
        self.strip.hidden = not enabled
    end)
end

-- Updates the strip's text.
function Hud:SetText(content)
    self:Apply(function()
        self.strip.content = content
    end)
end

-- Shows an alert line for a few seconds.
function Hud:ShowAlert(content)
    self:Apply(function()
        self.alert.content = "<col=ffd24a>" .. content .. "</col>"
        self.alert.hidden = false
    end)
    self.alertHideTick = Clock.CurrentTick() + Clock.SecondsToTicks(ALERT_SECONDS)
end

-- Called every server tick to hide expired alerts.
function Hud:Update()
    if self.alertHideTick and Clock.CurrentTick() >= self.alertHideTick then
        self.alertHideTick = nil
        self:Apply(function()
            self.alert.hidden = true
        end)
    end
end

return Hud
