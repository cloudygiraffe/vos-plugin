-- Unit tests for the parts of the plugin that do not need the game client.
--
-- Run from the repository root with any Lua 5.1+ interpreter:
--     lua tests/run_tests.lua
--
-- The plugin's modules are loaded with require("src/..."), relative to the
-- plugin folder, so the search path is pointed at voice-of-seren/.

package.path = "voice-of-seren/?.lua;" .. package.path

local Clans = require("src/clans")
local TimeUtil = require("src/timeutil")
local Clock = require("src/clock")
local VosState = require("src/vos_state")
local ChatSource = require("src/sources/chat_source")
local ApiSource = require("src/sources/api_source")
local Display = require("src/display")

--------------------------------------------------------------------------------
-- Tiny test framework
--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function test(name, body)
    Clock.Reset()
    VosState.Reset()
    local ok, err = pcall(body)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. "\n      " .. tostring(err))
    end
end

local function eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function listEq(actual, expected, label)
    eq(type(actual), "table", label)
    eq(#actual, #expected, (label or "list") .. " length")
    for i = 1, #expected do
        eq(actual[i], expected[i], (label or "list") .. "[" .. i .. "]")
    end
end

-- Handy fixed times.
local OCT_22_2026_15_00 = TimeUtil.ToUnix(2026, 10, 22, 15, 0, 0)
local OCT_22_2026_15_37 = TimeUtil.ToUnix(2026, 10, 22, 15, 37, 0)
local OCT_22_2026_16_00 = TimeUtil.ToUnix(2026, 10, 22, 16, 0, 0)

--------------------------------------------------------------------------------
-- timeutil
--------------------------------------------------------------------------------

test("Unix epoch is day 0", function()
    eq(TimeUtil.DaysFromCivil(1970, 1, 1), 0)
end)

test("RuneDate day 0 (February 27th, 2002) matches the known Unix time", function()
    eq(TimeUtil.ToUnix(2002, 2, 27, 0, 0, 0), 1014768000)
end)

test("Leap day 2024 is handled", function()
    eq(TimeUtil.DaysFromCivil(2024, 3, 1) - TimeUtil.DaysFromCivil(2024, 2, 28), 2)
end)

test("ISO timestamp from the wiki API parses", function()
    eq(TimeUtil.ParseIso8601("2026-10-20T14:00:00.000Z"), TimeUtil.ToUnix(2026, 10, 20, 14, 0, 0))
end)

test("ISO timestamp with a non-UTC offset is rejected", function()
    eq(TimeUtil.ParseIso8601("2026-10-20T14:00:00+05:00"), nil)
end)

test("HTTP Date header parses", function()
    local header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        .. "Date: Thu, 22 Oct 2026 15:37:00 GMT\r\n"
    eq(TimeUtil.ParseHttpDateHeader(header), OCT_22_2026_15_37)
end)

test("HTTP Date ignores Last-Modified style headers", function()
    eq(TimeUtil.ParseHttpDateHeader("X-Last-Date: Thu, 22 Oct 2026 15:37:00 GMT\r\n"), nil)
end)

test("Hour start and countdown", function()
    eq(TimeUtil.HourStart(OCT_22_2026_15_37), OCT_22_2026_15_00)
    eq(TimeUtil.SecondsUntilNextHour(OCT_22_2026_15_37), 23 * 60)
end)

test("Durations format for people", function()
    eq(TimeUtil.FormatDuration(30), "less than a minute")
    eq(TimeUtil.FormatDuration(23 * 60), "23 min")
    eq(TimeUtil.FormatDuration(3600), "1 h")
    eq(TimeUtil.FormatDuration(3900), "1 h 5 min")
    eq(TimeUtil.FormatGameHour(OCT_22_2026_15_00), "15:00 game time")
end)

--------------------------------------------------------------------------------
-- clans
--------------------------------------------------------------------------------

test("All eight clans exist", function()
    eq(#Clans.LIST, 8)
end)

test("Clan names normalise regardless of case", function()
    eq(Clans.Normalise("iorwerth"), "Iorwerth")
    eq(Clans.Normalise("TRAHAEARN"), "Trahaearn")
    eq(Clans.Normalise("Zamorak"), nil)
end)

test("Clans are found in text order", function()
    listEq(Clans.FindAllInText("active in the Meilyr and Amlodd districts"), { "Meilyr", "Amlodd" })
end)

--------------------------------------------------------------------------------
-- clock
--------------------------------------------------------------------------------

test("Clock is unknown until synced", function()
    eq(Clock.Now(), nil)
end)

test("Clock counts forward with logic ticks (50 per second)", function()
    Clock.OnLogicTick(1000)
    Clock.Sync(OCT_22_2026_15_00, "test")
    Clock.OnLogicTick(1000 + 50 * 90) -- 90 seconds later
    eq(Clock.Now(), OCT_22_2026_15_00 + 90)
end)

--------------------------------------------------------------------------------
-- chat source
--------------------------------------------------------------------------------

test("The documented announcement is recognised", function()
    listEq(ChatSource.ParseMessage("The Voice of Seren is now active in the Amlodd district."), { "Amlodd" })
end)

test("Colour tags are ignored", function()
    listEq(ChatSource.ParseMessage("<col=ff0000>The Voice of Seren is now active in the Cadarn district.</col>"),
        { "Cadarn" })
end)

test("Ordinary chat mentioning a clan is ignored", function()
    eq(ChatSource.ParseMessage("anyone know if Iorwerth is good xp?"), nil)
    eq(ChatSource.ParseMessage("Voice of Seren was in Hefin earlier"), nil)
end)

test("Messages from players are ignored even if worded like the announcement", function()
    local readings = 0
    ChatSource.HandleEvent({
        chatMessage = "The Voice of Seren is now active in the Hefin district.",
        senderNameUnfiltered = "Some Player",
        timestamp = OCT_22_2026_15_00,
    }, function() end, function() readings = readings + 1 end)
    eq(readings, 0)
end)

test("A game announcement becomes a reading for that hour", function()
    local reading
    ChatSource.HandleEvent({
        chatMessage = "The Voice of Seren is now active in the Hefin district.",
        senderNameUnfiltered = "",
        timestamp = OCT_22_2026_15_00 + 3,
    }, function() end, function(r) reading = r end)
    listEq(reading.clans, { "Hefin" })
    eq(reading.hourStart, OCT_22_2026_15_00)
end)

--------------------------------------------------------------------------------
-- API source
--------------------------------------------------------------------------------

test("The real API response parses", function()
    local reading = ApiSource.ParseBody(
        '{"timestamp":"2026-10-20T14:00:00.000Z","district1":"Iorwerth","district2":"Trahaearn","source":"alt1-crowdsourced"}')
    listEq(reading.clans, { "Iorwerth", "Trahaearn" })
    eq(reading.hourStart, TimeUtil.ToUnix(2026, 10, 20, 14, 0, 0))
end)

test("Garbage API responses are rejected", function()
    eq(ApiSource.ParseBody(""), nil)
    eq(ApiSource.ParseBody('{"district1":"Nope","district2":"Iorwerth"}'), nil)
end)

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local function reading(clans, hourStart, source)
    return { clans = clans, hourStart = hourStart, source = source or "test", observedAt = hourStart }
end

test("First reading is new and reports both clans", function()
    local changed, newClans = VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_15_00))
    eq(changed, true)
    listEq(newClans, { "Iorwerth", "Cadarn" })
end)

test("Two single-district messages in the same hour merge", function()
    VosState.Report(reading({ "Hefin" }, OCT_22_2026_15_00))
    local changed, newClans = VosState.Report(reading({ "Ithell" }, OCT_22_2026_15_00))
    eq(changed, true)
    listEq(newClans, { "Ithell" })
    listEq(VosState.Current().clans, { "Hefin", "Ithell" })
end)

test("A repeated reading is not a change", function()
    VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_15_00))
    local changed = VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_15_00))
    eq(changed, false)
end)

test("An older hour never replaces a newer one", function()
    VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_16_00))
    local changed = VosState.Report(reading({ "Hefin", "Ithell" }, OCT_22_2026_15_00))
    eq(changed, false)
    listEq(VosState.Current().clans, { "Iorwerth", "Cadarn" })
end)

test("A new hour only reports clans that were not already active", function()
    VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_15_00))
    local _, newClans = VosState.Report(reading({ "Cadarn", "Meilyr" }, OCT_22_2026_16_00))
    listEq(newClans, { "Meilyr" })
end)

test("Readings are only current during their own hour", function()
    VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_15_00))
    eq(VosState.IsCurrent(OCT_22_2026_15_37), true)
    eq(VosState.IsCurrent(OCT_22_2026_16_00 + 5), false)
end)

test("History keeps one entry per hour, newest first", function()
    VosState.Report(reading({ "Iorwerth", "Cadarn" }, OCT_22_2026_15_00))
    VosState.Report(reading({ "Hefin", "Ithell" }, OCT_22_2026_16_00))
    local history = VosState.History()
    eq(#history, 2)
    eq(history[1].hourStart, OCT_22_2026_16_00)
end)

test("Saved history restores this hour after a relog", function()
    VosState.LoadHistory({ { hourStart = OCT_22_2026_15_00, clans = { "Crwys", "Amlodd" } } })
    eq(VosState.RestoreCurrentFromHistory(OCT_22_2026_15_37), true)
    listEq(VosState.Current().clans, { "Crwys", "Amlodd" })
end)

test("Saved history from an earlier hour is not restored as current", function()
    VosState.LoadHistory({ { hourStart = OCT_22_2026_15_00, clans = { "Crwys", "Amlodd" } } })
    eq(VosState.RestoreCurrentFromHistory(OCT_22_2026_16_00 + 60), false)
end)

--------------------------------------------------------------------------------
-- display
--------------------------------------------------------------------------------

test("Strip shows clans and the countdown", function()
    local text = Display.StripText({ clans = { "Iorwerth", "Cadarn" } }, true, OCT_22_2026_15_37, {})
    eq(text, "Voice of Seren: Iorwerth & Cadarn | 23 min left")
end)

test("Watched clans are highlighted", function()
    local text = Display.ClanNames({ "Iorwerth", "Cadarn" }, { Iorwerth = true })
    eq(text, "<col=ffd24a>Iorwerth</col> & Cadarn")
end)

test("Strip without a clock still shows the clans", function()
    eq(Display.StripText({ clans = { "Hefin", "Ithell" } }, true, nil, {}), "Voice of Seren: Hefin & Ithell")
end)

test("Help text appears only when nothing can read the Voice from anywhere", function()
    eq(Display.HelpText(true, false, false), "")
    eq(Display.HelpText(false, false, true), "")
    eq(Display.HelpText(false, false, false) ~= "", true)
end)

--------------------------------------------------------------------------------

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
