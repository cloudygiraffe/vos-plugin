-- storage.lua
-- Saves and loads the player's settings and the Voice history using the
-- plugin API's PersistentDB.
--
-- PersistentDB records are per plugin and shared by every character played on
-- this computer. That suits this plugin: the Voice is the same on every world
-- and every account, and alert choices are a personal preference.

local Storage = {}

local KEY_WATCHED = "watchedClans" -- table: { Iorwerth = true, Cadarn = true }
local KEY_HUD = "showOnScreenStrip" -- boolean
local KEY_HISTORY = "history"       -- list: { { hourStart = n, clans = {...} }, ... }
local KEY_ALERTED = "alerted"       -- table: { hour = n, clans = { Iorwerth = true } }

-- Wraps a PersistentDB call so a storage problem never stops the plugin.
local function safely(action, fallback)
    local ok, result = pcall(action)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

-- Returns the set of clans the player wants alerts for (may be empty).
function Storage.LoadWatchedClans()
    local saved = safely(function()
        return PersistentDB:GetStructuredData(KEY_WATCHED)
    end, {})
    if type(saved) ~= "table" then
        return {}
    end
    return saved
end

-- Saves the set of watched clans (same shape as LoadWatchedClans returns).
function Storage.SaveWatchedClans(watched)
    safely(function()
        return PersistentDB:SetStructuredData(KEY_WATCHED, watched)
    end)
end

-- Returns whether the small on-screen strip is enabled (default: on).
function Storage.LoadHudEnabled()
    local saved = safely(function()
        return PersistentDB:GetBool(KEY_HUD)
    end, nil)
    if saved == nil then
        return true
    end
    return saved
end

-- Saves whether the on-screen strip is shown.
function Storage.SaveHudEnabled(enabled)
    safely(function()
        return PersistentDB:SetBool(KEY_HUD, enabled == true)
    end)
end

-- Returns the saved Voice history (list of { hourStart, clans }), or {}.
-- VosState.LoadHistory validates each entry.
function Storage.LoadHistory()
    local saved = safely(function()
        return PersistentDB:GetStructuredData(KEY_HISTORY)
    end, {})
    if type(saved) ~= "table" then
        return {}
    end
    return saved
end

-- Saves the Voice history from VosState.History().
function Storage.SaveHistory(history)
    safely(function()
        return PersistentDB:SetStructuredData(KEY_HISTORY, history)
    end)
end

-- Which clans have already alerted, and for which hour, so a reload in the
-- same hour does not repeat alerts.
function Storage.LoadAlerted()
    local saved = safely(function()
        return PersistentDB:GetStructuredData(KEY_ALERTED)
    end, nil)
    if type(saved) ~= "table" or type(saved.clans) ~= "table" then
        return { hour = nil, clans = {} }
    end
    return { hour = saved.hour, clans = saved.clans }
end

-- Saves the alert record ({ hour, clans }) from main.lua.
function Storage.SaveAlerted(alerted)
    safely(function()
        return PersistentDB:SetStructuredData(KEY_ALERTED, alerted)
    end)
end

return Storage
