-- sources/chat_source.lua
-- Reads the Voice of Seren from the game's own chat announcement.
--
-- When the Voice moves, the game posts a message such as
--   "The Voice of Seren is now active in the Amlodd district."
-- The RuneScape Wiki notes this appears inside Prifddinas; it may not be shown
-- elsewhere. One message may name one district or both, so each message is
-- reported on its own and vos_state.lua merges readings for the same hour.
--
-- Permission: plugins only receive chat events if the player grants the
-- optional "chatAccess" permission. Without it this source simply never fires.
-- Bonus: each chat event carries a Unix timestamp, which also lets the plugin
-- learn the real time (see clock.lua).

local Clans = require("src/clans")
local TimeUtil = require("src/timeutil")

local ChatSource = {}

ChatSource.LABEL = "Prifddinas announcement"

-- Removes RuneScape text markup such as "<col=ff0000>" and "</col>".
local function stripTags(text)
    return (string.gsub(text, "<[^>]*>", ""))
end

-- Returns the list of clans a chat message announces, or nil if the message
-- is not a Voice of Seren announcement. Pure function: easy to unit test.
function ChatSource.ParseMessage(message)
    if type(message) ~= "string" then
        return nil
    end
    local plain = string.lower(stripTags(message))
    -- Both phrases must be present so ordinary chat that mentions Seren, or a
    -- player typing a clan name, is ignored.
    if not string.find(plain, "voice of seren", 1, true) then
        return nil
    end
    if not string.find(plain, "now active", 1, true) then
        return nil
    end
    local clans = Clans.FindAllInText(plain)
    if #clans == 0 then
        return nil
    end
    return clans
end

-- Chat types that can carry game announcements. Player chat (public, private,
-- clan, friends) is deliberately excluded so players cannot spoof the Voice.
-- These come from the ChatType enum in the API docs.
local function isGameMessageType(chatType)
    if ChatType == nil then
        return true -- running outside the game (unit tests)
    end
    return chatType == ChatType.GENERAL
        or chatType == ChatType.ENGINE
        or chatType == ChatType.GENERAL_LINKABLE
        or chatType == ChatType.BROADCAST
        or chatType == ChatType.BROADCAST_WORLD
        or chatType == ChatType.BROADCAST_GLOBAL
        or chatType == ChatType.MISC_BROADCAST
        or chatType == ChatType.WORLD_EVENT
        or chatType == ChatType.TIMED_EVENT
end

-- Handles one ChatMessage event. Calls onTime(unixSeconds) with the message
-- timestamp, and onReading(reading) if it was a Voice announcement.
function ChatSource.HandleEvent(event, onTime, onReading)
    if event == nil then
        return
    end
    if type(event.timestamp) == "number" and event.timestamp > 0 then
        onTime(event.timestamp)
    end
    if not isGameMessageType(event.chatType) then
        return
    end
    -- Sender names are empty for system messages; anything sent by a player
    -- is ignored as an extra guard against spoofing.
    if event.senderNameUnfiltered ~= nil and event.senderNameUnfiltered ~= "" then
        return
    end
    local clans = ChatSource.ParseMessage(event.chatMessage)
    if clans == nil then
        return
    end
    local observedAt = event.timestamp
    onReading({
        clans = clans,
        hourStart = observedAt and TimeUtil.HourStart(observedAt) or nil,
        source = ChatSource.LABEL,
        observedAt = observedAt,
    })
end

return ChatSource
