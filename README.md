# Voice of Seren — RuneScape 3 plugin

See which two Prifddinas clans have the **Voice of Seren** right now, what they
boost, and how long until it moves, **from anywhere in the game**. Tick the
clans you care about and the plugin tells you when one of them becomes active.

> **Status: pre-release (0.1.0).** The code is complete and unit tested, but it
> has not run in the game client yet. The next step is testing on the plugin
> beta world. See [docs/TESTING.md](docs/TESTING.md).

## Why

The Voice moves between the eight elven clan districts every hour, two at a
time. In game, you can only see which ones are active while you are standing
in Prifddinas. Players who want a specific Voice (Iorwerth or Cadarn for
combat, Hefin for Agility, Trahaearn for Mining and Smithing, and so on) have
to travel there, check an outside website, or ask around. No plugin in the
official RS3 Plugin Hub covers this yet.

## What it does

- **On-screen strip** at the top of the game screen:
  `Voice of Seren: Iorwerth & Cadarn | 23 min left`. Clans you watch are shown
  in gold. It can be switched off.
- **Panel** (open from the Plugins ribbon window) showing:
  - both active clans and what each one boosts
  - a countdown to the next change
  - where the information came from and how old it is
  - checkboxes to pick which clans you want alerts for
  - the last few hours of history
- **Alerts** when a clan you watch becomes active: a gold line under the strip,
  plus a chat-box message if chat access is allowed.

## Where the information comes from

The plugin can learn the Voice three ways. It uses whichever ones you allow.

| Source | Permission | Works outside Prifddinas? | Notes |
|---|---|---|---|
| Game data | none | yes (to confirm away from Prifddinas) | The game's own `ELFCITY_VOICE1_PLAYER` / `ELFCITY_VOICE2_PLAYER` variables (clans numbered alphabetically, 0 = Amlodd to 7 = Trahaearn) plus `ELFCITY_VOS_PLAYER_HOUR` (the UTC hour they're for). Found on the beta world on October 22nd, 2026. Best source: no permissions, instant. |
| RuneScape Wiki API | optional *web requests* (`httpAccess`) | yes | Uses `https://api.weirdgloop.org/runescape/vos`. Crowdsourced, so it can lag. Once the plugin knows the time, data for an older hour is shown as "waiting for this hour", not as current. The game's own announcement always overrides it. |
| Prifddinas announcement | optional *chat access* (`chatAccess`) | no | Reads the game's own "The Voice of Seren is now active in the ... district." message. Only player-free system messages are accepted. |

Both permissions are **optional**. The plugin runs without them, and the panel
explains what each one adds.

### The clock

The plugin API has no documented clock, but a countdown needs the time. The
plugin tries Lua's `os.time()` (undocumented, so it may not exist), then the
Wiki API's response date, then a chat message timestamp. After that it counts
forward using the client's fixed 50 logic ticks per second. With no clock
source, the strip shows the clans and says the Voice changes at the top of the
hour.

## Plugin guidelines

This plugin is built to stay inside Jagex's
[plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html):

- It only **displays information that is already public**: the Voice is the
  same on every world, shown in Prifddinas, and published on the Wiki.
- It **never sends input or performs actions** for the player.
- It does not look at or export anything about other players.
- The two permissions are optional and only add information sources. Jagex
  reviews any plugin that requests a permission, so expect that in review.

## Repository layout

```
voice-of-seren/          the plugin itself (this folder goes in dev_plugins)
  plugin.json            manifest: name, version, permissions, URLs
  main.lua               wires game events to the modules below
  src/
    clans.lua            the eight clans and their effects (static data)
    timeutil.lua         date maths and formatting (no clock access)
    clock.lua            learns the real time and counts forward
    vos_state.lua        current Voice + history; merges and ages readings
    display.lua          all text shown to the player
    storage.lua          saved settings and history (PersistentDB)
    hud.lua              on-screen strip and alert line
    panel.lua            the ribbon panel
    sources/
      api_source.lua     RuneScape Wiki API
      chat_source.lua    Prifddinas chat announcement
      game_source.lua    the game's own Voice variables
tools/vos-discovery/     beta-world tool that finds the game variables
tests/                   unit tests and an end-to-end test with a fake API
docs/DESIGN.md           how it works, decisions, and open questions
docs/TESTING.md          step-by-step beta world testing
```

## Running the tests

Any Lua 5.1 or newer interpreter works. From the repository root:

```
lua tests/run_tests.lua
lua tests/mock_game_test.lua
```

`run_tests.lua` covers the logic (time maths, parsing, state). `mock_game_test.lua`
runs `main.lua` against a fake version of the plugin API that only knows the
documented functions, so a misspelled API name fails the test.

## Trying it on the beta world

Copy the `voice-of-seren` folder into your beta client's `dev_plugins` folder
(on Windows: `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\`), then in the
client console (`Alt` + the key under `Esc`) run `prf`, then `pon voice-of-seren`.
Full steps, including the discovery tool, are in [docs/TESTING.md](docs/TESTING.md).

## Before submitting to the Plugin Hub

- [ ] Replace `contactEmailAddress` in `plugin.json` (Jagex recommends one that
      is different from your mod.io login).
- [ ] Test every item in [docs/TESTING.md](docs/TESTING.md).
- [ ] Confirm the game variables update at the hour, and whether they do away
      from Prifddinas.
- [ ] Re-read every file: Jagex's AI policy requires the author to have reviewed
      and understood all submitted code.

## Credits

- Clan effect summaries are based on the
  [RuneScape Wiki's Voice of Seren page](https://runescape.wiki/w/Voice_of_Seren).
- Live Voice data comes from the RuneScape Wiki's API, run by
  [Weird Gloop](https://runescape.wiki/w/Help:APIs).
- Written with AI assistance (Claude). Per Jagex's AI policy, the author reviews
  and understands every line before anything is submitted.

## License

[MIT](LICENSE)
