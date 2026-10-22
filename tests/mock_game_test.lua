-- End-to-end test of main.lua against a fake version of the game's plugin API.
--
-- Run from the repository root:
--     lua tests/mock_game_test.lua
--
-- The fakes only implement the functions the plugin uses, with the signatures
-- documented at developer.runescape.com. Calling anything else raises an
-- error, which catches typos in API names before testing in game.

package.path = "voice-of-seren/?.lua;" .. package.path

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

-- A table that errors when an unknown field is read. Used for API tables.
local function strict(name, fields)
    return setmetatable(fields, {
        __index = function(_, key)
            error("plugin used unknown API member " .. name .. "." .. tostring(key), 2)
        end,
    })
end

--------------------------------------------------------------------------------
-- Fake events
--------------------------------------------------------------------------------

local subscribers = {}
local function fakeEvent(eventName)
    subscribers[eventName] = {}
    return strict("Event." .. eventName, {
        Subscribe = function(refName, callback)
            subscribers[eventName][refName] = callback
        end,
        Unsubscribe = function(refName)
            subscribers[eventName][refName] = nil
        end,
    })
end
local function fire(eventName, payload)
    for _, callback in pairs(subscribers[eventName]) do
        callback(payload)
    end
end

Event = strict("Event", {
    Logic = fakeEvent("Logic"),
    ServerLogic = fakeEvent("ServerLogic"),
    ChatMessage = fakeEvent("ChatMessage"),
    VarTransmit = fakeEvent("VarTransmit"),
    ContentLayerReady = fakeEvent("ContentLayerReady"),
    OptionalPermissionChanged = fakeEvent("OptionalPermissionChanged"),
})

--------------------------------------------------------------------------------
-- Fake UI
--------------------------------------------------------------------------------

local allComponents = {}
local function fakeComponent(kind)
    local component = {
        kind = kind,
        hooks = {},
        visibleGlobal = true,
    }
    function component.SetPos(self, x, y, px, py, sx, sy) self.pos = { x, y, px, py, sx, sy } end
    function component.SetSize(self, w, h, pw, ph) self.size = { w, h, pw, ph } end
    function component.AlignTo(self, h, v) self.align = { h, v } end
    function component.Subscribe(self, hook, callback) self.hooks[hook] = callback end
    table.insert(allComponents, component)
    return component
end

local pluginLayer = fakeComponent("Layer")
ui = strict("ui", {
    Interfaces = strict("ui.Interfaces", {
        GetComponent = function(_, componentId)
            if componentId == "PLUGIN_LAYER" then
                return pluginLayer
            end
            return nil
        end,
    }),
    Text = strict("ui.Text", { new = function() return fakeComponent("Text") end }),
    Check = strict("ui.Check", { new = function() return fakeComponent("Check") end }),
    -- Only the documented values, so a wrong name fails the test.
    AlignMode = strict("ui.AlignMode", { TOPLEFT = 0, CENTRE = 1, BOTTOMRIGHT = 2, JUSTIFY = 3 }),
    CheckAlignMode = strict("ui.CheckAlignMode", { LEFT = 1 }),
    Hook = strict("ui.Hook", { ONBUTTONPRESSED = "ONBUTTONPRESSED" }),
})

id = strict("id", {
    Font = strict("id.Font", { MUSEO_SANS_15PT_REGULAR = 1 }),
    Component = strict("id.Component", { TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = "PLUGIN_LAYER" }),
    StyleSheet = strict("id.StyleSheet", { CHECKBOX_DEFAULT = 1 }),
})

--------------------------------------------------------------------------------
-- Fake plugin services
--------------------------------------------------------------------------------

local granted = { httpAccess = true, chatAccess = true }
PluginPermissions = strict("PluginPermissions", {
    httpAccess = "httpAccess", chatAccess = "chatAccess", trackingAccess = "trackingAccess",
})
Plugin = strict("Plugin", {
    HasPermission = function(permission) return granted[permission] == true end,
    urls = strict("Plugin.urls", { weirdgloop = "https://api.weirdgloop.org" }),
})

local database = {}
PersistentDB = strict("PersistentDB", {
    GetStructuredData = function(_, key) return database[key] end,
    SetStructuredData = function(_, key, value) database[key] = value return true end,
    GetBool = function(_, key) return database[key] end,
    SetBool = function(_, key, value) database[key] = value return true end,
})

local chatLines = {}
Chat = strict("Chat", { AddMessage = function(message) table.insert(chatLines, message) end })
ChatType = strict("ChatType", {
    GENERAL = 0, ENGINE = 4, GENERAL_LINKABLE = 145, BROADCAST = 125, BROADCAST_WORLD = 138,
    BROADCAST_GLOBAL = 137, MISC_BROADCAST = 127, WORLD_EVENT = 126, TIMED_EVENT = 142, PUBLIC = 2,
})

-- HTTP: requests are queued; the test answers them by hand.
local pendingRequests = {}
HTTPRequest = strict("HTTPRequest", {
    new = function(baseUrl, path)
        local request = { url = tostring(baseUrl) .. (path or ""), headers = {} }
        function request.AddHeader(self, key, value) self.headers[key] = value end
        function request.Get(self, onDone) self.onDone = onDone table.insert(pendingRequests, self) end
        return request
    end,
})

var = strict("var", {})

-- Pretend os.time does not exist so the clock must come from the web response.
os.time = nil

--------------------------------------------------------------------------------
-- Run the plugin
--------------------------------------------------------------------------------

local OCT_22_2026_15_37 = 1792683420 -- Thursday, October 22nd, 2026 15:37:00 UTC
dofile("voice-of-seren/main.lua")

local strip = allComponents[2] -- first Text created on the plugin layer
local tick = 0
local function advanceSeconds(seconds)
    for _ = 1, math.floor(seconds / 0.6) do
        tick = tick + 30 -- 0.6 s of logic ticks at 50 per second
        fire("Logic", { logicTick = tick })
        fire("ServerLogic", nil)
    end
end

advanceSeconds(1)
check(#pendingRequests == 1, "a web request is made straight away")
local request = table.remove(pendingRequests, 1)
check(request.url == "https://api.weirdgloop.org/runescape/vos", "request URL is the VoS endpoint")
check(request.headers["User-Agent"] ~= nil, "request sends a User-Agent")

request.onDone({
    successful = true,
    header = "HTTP/1.1 200 OK\r\nDate: Thu, 22 Oct 2026 15:37:00 GMT\r\n",
    data = '{"timestamp":"2026-10-22T15:00:00.000Z","district1":"Iorwerth","district2":"Cadarn","source":"x"}',
})
advanceSeconds(6)
check(string.find(strip.content, "Iorwerth & Cadarn", 1, true) ~= nil,
    "strip shows the clans (got: " .. tostring(strip.content) .. ")")
check(string.find(strip.content, "min left", 1, true) ~= nil, "strip shows a countdown")

-- Open the panel and tick the Meilyr box.
local panelRoot = fakeComponent("Layer")
fire("ContentLayerReady", { component = panelRoot })
local meilyrBox
for _, component in ipairs(allComponents) do
    if component.kind == "Check" and component.label == "Meilyr" then
        meilyrBox = component
    end
end
check(meilyrBox ~= nil, "panel has a Meilyr checkbox")
meilyrBox.hooks.ONBUTTONPRESSED(meilyrBox, true)
check(database.watchedClans and database.watchedClans.Meilyr == true, "watching Meilyr is saved")

-- At the next hour, the Prifddinas announcement arrives for Meilyr.
advanceSeconds(23 * 60 + 5)
fire("ChatMessage", {
    chatMessage = "The Voice of Seren is now active in the Meilyr district.",
    senderNameUnfiltered = "",
    chatType = ChatType.GENERAL,
    timestamp = OCT_22_2026_15_37 + 23 * 60 + 5,
})
check(#chatLines == 1 and string.find(chatLines[1], "Meilyr", 1, true) ~= nil,
    "an alert is posted to chat for a watched clan")
check(string.find(strip.content, "Meilyr", 1, true) ~= nil, "strip switches to the new hour")
check(database.history ~= nil and #database.history == 2, "history is saved with two hours")

print(failures == 0 and "mock game test passed" or (failures .. " check(s) failed"))
if failures > 0 then
    os.exit(1)
end
