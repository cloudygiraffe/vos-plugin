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

-- Properties the plugin may set, taken from the Component, Text and Check
-- doc pages. Writing anything else (e.g. a typo like "isShadowd") fails.
local DOCUMENTED_PROPERTIES = {
    Layer = {},
    Text = { content = true, font = true, maxLines = true, isShadowed = true,
             hidden = true, clickthrough = true, stylesheetID = true },
    Check = { label = true, value = true, alignment = true, stylesheetID = true,
              hidden = true, clickthrough = true },
}

local allComponents = {}
local function fakeComponent(kind)
    local state = { kind = kind, hooks = {}, visibleGlobal = true }
    local methods = {}
    function methods.SetPos(_, x, y, px, py, sx, sy) state.pos = { x, y, px, py, sx, sy } end
    function methods.SetSize(_, w, h, pw, ph) state.size = { w, h, pw, ph } end
    function methods.AlignTo(_, h, v) state.align = { h, v } end
    function methods.Subscribe(_, hook, callback) state.hooks[hook] = callback end
    local component = setmetatable({}, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            return state[key]
        end,
        __newindex = function(_, key, value)
            if not DOCUMENTED_PROPERTIES[kind][key] then
                error("plugin set undocumented property " .. kind .. "." .. tostring(key), 2)
            end
            state[key] = value
        end,
    })
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
    responseCode = 200,
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
-- The game ticks the box, then calls the hook. The Component docs say the
-- second argument is an Int, so pass 1 rather than true.
meilyrBox.value = true
meilyrBox.hooks.ONBUTTONPRESSED(meilyrBox, 1)
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

-- The game's own Voice variables (ELFCITY_VOICE1/2_PLAYER, hour). A value
-- left over from the previous hour (15) must be ignored...
local voiceVars = { [-25159] = 1, [-25160] = 4, [-26417] = 15 }
var = strict("var", {
    VarPlayer = strict("var.VarPlayer", {
        FromID = function(variableId)
            if voiceVars[variableId] == nil then error("unknown variable") end
            return { value = voiceVars[variableId] }
        end,
    }),
})
advanceSeconds(6)
check(string.find(strip.content, "Amlodd", 1, true) == nil, "last hour's game values are ignored")

-- ...and this hour's values (16:00 UTC: Meilyr = 7, Trahaearn = 8) are used.
voiceVars = { [-25159] = 7, [-25160] = 8, [-26417] = 16 }
fire("VarTransmit", { var = { configName = "ELFCITY_VOICE2_PLAYER" }, oldValue = 4, newValue = 8 })
check(string.find(strip.content, "Trahaearn", 1, true) ~= nil and string.find(strip.content, "Meilyr", 1, true) ~= nil,
    "strip shows the clans from the game's variables (got: " .. tostring(strip.content) .. ")")
check(#chatLines == 1, "no second alert for Meilyr in the same hour")

print(failures == 0 and "mock game test passed" or (failures .. " check(s) failed"))
if failures > 0 then
    os.exit(1)
end
