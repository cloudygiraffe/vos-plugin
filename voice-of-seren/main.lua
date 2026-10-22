-- main.lua (Voice of Seren plugin entry point)
--
-- Shows which two Prifddinas clans have the Voice of Seren right now, what
-- they boost, and how long until it moves. Optionally alerts you when a clan
-- you care about becomes active.
--
-- How the pieces fit together (see docs/DESIGN.md for more):
--
--   sources/game_source.lua  (game variables; inside Prifddinas only)
--   sources/chat_source.lua  (Prifddinas announcement; optional chatAccess)
--   sources/api_source.lua   (RuneScape Wiki API; optional httpAccess)
--          |
--          | readings: { clans, hourStart, source, observedAt, rank }
--          v
--   vos_state.lua  --view-->  display.lua (text)  -->  hud.lua (strip),
--                                                      panel.lua (window)
--
-- This file only wires game events to those modules and owns the player's
-- settings (watched clans, strip on/off, alerts already shown). It holds no
-- Voice logic itself.
--
-- Every call into the game API that is not guaranteed by the docs is wrapped
-- in pcall, so a missing permission or an API change degrades the plugin
-- instead of stopping it.

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

-- True if the player granted `permission` (a PluginPermissions value).
-- Never errors, even if the API call does.
local function hasPermission(permission)
    local ok, granted = pcall(function()
        return Plugin.HasPermission(permission)
    end)
    return ok and granted == true
end

-- Everything the strip and panel need, gathered in one place. Fields:
--   now, current, isCurrent, history : see Clock and VosState
--   httpAllowed, chatAllowed          : optional permissions granted
--   gameReadable                      : game variables can be read (true
--                                       whenever the game data source exists;
--                                       only current inside Prifddinas)
--   apiError                          : last Wiki API problem, or nil
local function buildView()
    local now = Clock.Now()
    return {
        now = now,
        current = VosState.Current(),
        isCurrent = VosState.IsCurrent(now),
        history = VosState.History(),
        httpAllowed = hasPermission(PluginPermissions.httpAccess),
        chatAllowed = hasPermission(PluginPermissions.chatAccess),
        gameReadable = GameSource.IsConfigured(),
        apiError = ApiSource.LastError(),
    }
end

local hud = Hud.new()
hud:SetEnabled(hudEnabled)

local panel -- created below, after its callbacks are defined

-- Redraws the strip and (if open) the panel from the current state.
local function refreshUi()
    local view = buildView()
    hud:SetText(Display.StripText(view.current, view.isCurrent, view.now, watchedClans))
    panel:Refresh(view)
end

-- Shows an alert for each newly active clan the player is watching: a gold
-- line under the strip and, with chat access, a line in the chat box. Each
-- clan alerts at most once per hour; the record is saved so a reload or relog
-- in the same hour doesn't repeat it.
--   newClans : list of clan names that just became active (from VosState.Report)
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

-- Every source reports through here. VosState decides whether the reading
-- changes anything (see its ranking rules); if so, history is saved, alerts
-- are raised for newly active clans and the UI is redrawn.
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

-- Fetch straight away when the player grants web access. The docs don't say
-- whether permissionName is the string "httpAccess" or the enum value, so
-- both are accepted.
Event.OptionalPermissionChanged.Subscribe("vosPermissions", function(event)
    local isHttp = event.permissionName == "httpAccess"
        or event.permissionName == PluginPermissions.httpAccess
    if event.enabled and isHttp then
        ApiSource.RequestSoon()
    end
    refreshUi()
end)

--------------------------------------------------------------------------------
-- Start-up: try the free clock, read the game variables once (they may not be
-- readable yet before login; the server-tick poll retries), draw the UI.
--------------------------------------------------------------------------------

Clock.TrySystemClock()
GameSource.Poll(handleReading)
refreshUi()
