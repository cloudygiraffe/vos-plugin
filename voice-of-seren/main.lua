-- Voice of Seren
-- Shows which two Prifddinas clans have the Voice of Seren right now, what
-- they boost, and how long until it moves, from anywhere in the game.
-- Optionally alerts you when a clan you care about becomes active.
--
-- How the pieces fit together (see docs/DESIGN.md for more):
--
--   sources/*.lua  --readings-->  vos_state.lua  --view-->  hud.lua, panel.lua
--        ^                                                     (display.lua
--        |                                                      builds text)
--   game events (chat, variables, web responses, ticks)
--
-- This file only wires events to modules. It holds no Voice logic itself.

local Clock = require("src/clock")
local TimeUtil = require("src/timeutil")
local VosState = require("src/vos_state")
local Display = require("src/display")
local Storage = require("src/storage")
local Hud = require("src/hud")
local Panel = require("src/panel")
local ChatSource = require("src/sources/chat_source")
local ApiSource = require("src/sources/api_source")
local GameSource = require("src/sources/game_source")

-- How often the countdown text is refreshed, in server ticks (0.6 s each).
local REFRESH_EVERY_SERVER_TICKS = 8 -- about 5 seconds

--------------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------------

local watchedClans = Storage.LoadWatchedClans() -- { Iorwerth = true, ... }
local hudEnabled = Storage.LoadHudEnabled()
VosState.LoadHistory(Storage.LoadHistory())

-- Alerts already shown, so each clan alerts at most once per hour, even
-- across a reload or relog.
local alerted = Storage.LoadAlerted() -- { hour = number|nil, clans = { Iorwerth = true } }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function hasPermission(permission)
    local ok, granted = pcall(function()
        return Plugin.HasPermission(permission)
    end)
    return ok and granted == true
end

-- Everything the strip and panel need, gathered in one place.
local function buildView()
    local now = Clock.Now()
    return {
        now = now,
        current = VosState.Current(),
        isCurrent = VosState.IsCurrent(now),
        history = VosState.History(),
        httpAllowed = hasPermission(PluginPermissions.httpAccess),
        chatAllowed = hasPermission(PluginPermissions.chatAccess),
        gameConfigured = GameSource.IsConfigured(),
        apiError = ApiSource.LastError(),
    }
end

local hud = Hud.new()
hud:SetEnabled(hudEnabled)

local panel -- created below, after its callbacks are defined

local function refreshUi()
    local view = buildView()
    hud:SetText(Display.StripText(view.current, view.isCurrent, view.now, watchedClans))
    panel:Refresh(view)
end

-- Shows an alert for each newly active clan the player is watching.
local function alertFor(newClans)
    local now = Clock.Now()
    if not VosState.IsCurrent(now) then
        return -- never alert about an old hour
    end
    local current = VosState.Current()
    -- Which hour these alerts belong to. Fall back to when the reading was
    -- seen if the source did not say.
    local hour = current and current.hourStart
    if hour == nil and current and current.observedAt then
        hour = TimeUtil.HourStart(current.observedAt)
    end
    if hour ~= alerted.hour then
        alerted = { hour = hour, clans = {} }
    end
    for _, clanName in ipairs(newClans) do
        if watchedClans[clanName] and not alerted.clans[clanName] then
            alerted.clans[clanName] = true
            Storage.SaveAlerted(alerted)
            local message = Display.AlertText(clanName)
            hud:ShowAlert(message)
            if hasPermission(PluginPermissions.chatAccess) then
                pcall(function() Chat.AddMessage(message) end)
            end
        end
    end
end

-- Every source reports through here.
local function handleReading(reading)
    local changed, newClans = VosState.Report(reading)
    if changed then
        Storage.SaveHistory(VosState.History())
        alertFor(newClans)
        refreshUi()
    end
end

-- Once the real time is known, saved history can fill in this hour's Voice
-- (after a relog) or replace a reading that turned out to be out of date.
local function restoreFromHistoryIfUseful()
    if VosState.RestoreCurrentFromHistory(Clock.Now()) then
        refreshUi()
    end
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

panel = Panel.new({
    onWatchChanged = function(clanName, isWatched)
        if isWatched then
            watchedClans[clanName] = true
        else
            watchedClans[clanName] = nil
        end
        Storage.SaveWatchedClans(watchedClans)
        refreshUi()
    end,
    onHudToggled = function(isEnabled)
        hudEnabled = isEnabled
        hud:SetEnabled(isEnabled)
        Storage.SaveHudEnabled(isEnabled)
    end,
})

-- The game gives us a fresh, empty layer each time the window opens.
Event.ContentLayerReady.Subscribe("vosPanel", function(event)
    panel:Build(event.component, watchedClans, hudEnabled)
    refreshUi()
end)

--------------------------------------------------------------------------------
-- Game events
--------------------------------------------------------------------------------

-- 50 times a second: keep the clock ticking. Kept as small as possible.
Event.Logic.Subscribe("vosClock", function(event)
    Clock.OnLogicTick(event.logicTick)
end)

-- Every server tick (0.6 s): web requests, alert expiry, countdown refresh.
local serverTicks = 0
Event.ServerLogic.Subscribe("vosTick", function()
    serverTicks = serverTicks + 1
    ApiSource.Update(handleReading)
    hud:Update()
    if Clock.IsKnown() then
        restoreFromHistoryIfUseful()
    end
    if serverTicks % REFRESH_EVERY_SERVER_TICKS == 0 then
        -- Also re-read the game's Voice variables (after login they may only
        -- arrive a moment later, and VarTransmit naming isn't documented).
        GameSource.Poll(handleReading)
        refreshUi()
    end
end)

-- Chat: the Prifddinas announcement, and a fallback source of the real time.
-- Only delivered if the player granted the optional chatAccess permission.
-- The docs do not say whether subscribing without the permission is allowed,
-- so the subscription is guarded: the plugin must work without it.
pcall(function()
    Event.ChatMessage.Subscribe("vosChat", function(event)
        ChatSource.HandleEvent(event, Clock.SyncIfUnknown, handleReading)
    end)
end)

-- Game variables: the Voice changed (ELFCITY_VOICE1/2_PLAYER).
Event.VarTransmit.Subscribe("vosVars", function(event)
    GameSource.HandleVarTransmit(event, handleReading)
end)

-- Fetch straight away when the player grants web access.
Event.OptionalPermissionChanged.Subscribe("vosPermissions", function(event)
    local isHttp = event.permissionName == "httpAccess"
        or event.permissionName == PluginPermissions.httpAccess
    if event.enabled and isHttp then
        ApiSource.RequestSoon()
    end
    refreshUi()
end)

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------

Clock.TrySystemClock()
GameSource.Poll(handleReading)
refreshUi()
