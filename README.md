# Voice of Seren — RuneScape 3 plugin

[![Tests](https://github.com/cloudygiraffe/vos-plugin/actions/workflows/tests.yml/badge.svg)](https://github.com/cloudygiraffe/vos-plugin/actions/workflows/tests.yml)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Lua](https://img.shields.io/badge/Lua-5.4-2C2D72)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A plugin for the official RuneScape 3 Client API that shows which two
Prifddinas clans have the **Voice of Seren**, what they boost and how long
until it moves, and alerts you when a clan you care about becomes active.

> **Status: pre-release (0.1.0), in beta-world testing.** The plugin loads and
> runs on the plugin beta world. Reading the Voice from the game works inside
> Prifddinas. The open problem is a reliable source *outside* the city, which
> the alerts depend on. See [Known issues and roadmap](#known-issues-and-roadmap).

## Contents

- [Features](#features)
- [Installation (beta world)](#installation-beta-world)
- [Usage](#usage)
- [Permissions](#permissions)
- [How it works](#how-it-works)
- [Project structure](#project-structure)
- [Development](#development)
- [Known issues and roadmap](#known-issues-and-roadmap)
- [Plugin guidelines](#plugin-guidelines)
- [Contributing](#contributing)
- [Licence and credits](#licence-and-credits)

## Features

- **On-screen strip** at the top of the game screen, for example
  `Voice of Seren: Iorwerth & Cadarn | 23 min left`. Clans you watch are shown
  in gold. It never blocks clicks, and it can be switched off.
- **Panel** (opened from the plugin's icon in the Plugins ribbon window):
  - both active clans and what each one boosts
  - a countdown to the next change
  - where the information came from and how old it is
  - checkboxes for the clans you want alerts for
  - the last few hours of history
- **Alerts** when a watched clan becomes active: a gold line under the strip,
  plus a chat-box message if chat access is allowed. At most once per clan per
  hour, even across a reload or relog.
- **Works with no permissions** inside Prifddinas, by reading the game's own
  Voice variables. The optional permissions add sources that work elsewhere.

## Installation (beta world)

Plugins only run on the plugin beta world until Jagex approves them. Your beta
character is a copy of your live one (press **import save** in the lobby), so
nothing you do there affects your real account. Joining is explained on
[developer.runescape.com](https://developer.runescape.com/rs/tutorial/1helloworld.html).

1. Download or clone this repository.
2. Copy the `voice-of-seren` folder into the beta client's `dev_plugins`
   folder. On Windows that is `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins`
   (create `dev_plugins` if it doesn't exist; `ProgramData` is a hidden folder).
3. In game, open the console with **Alt + the key under Esc** and run:

   | Command | What it does |
   |---|---|
   | `prf` | Re-scan `dev_plugins` for plugins |
   | `plist` | List plugins and their status (load errors show here) |
   | `pon voice-of-seren` | Turn the plugin on |
   | `poff voice-of-seren` | Turn it off |
   | `prl voice-of-seren` | Reload it after editing files (close its panel first) |

## Usage

- The strip appears at the top of the screen as soon as the plugin knows the
  Voice. "Voice of Seren: not known yet" means no source has reported yet:
  visit Prifddinas, or allow one of the optional permissions.
- Open the panel from the Plugins ribbon window to see both clans' effects,
  tick the clans you want alerts for, and turn the strip on or off.
- "waiting for this hour (last: …)" means the newest information is for an
  earlier hour, usually because the Wiki API hasn't caught up yet.

## Permissions

Both permissions are optional. Grant them in the Plugin Hub's **Manage** tab.

| Permission | What it adds | Why it is optional |
|---|---|---|
| none | Reads the Voice from the game's variables while you're in Prifddinas | — |
| `httpAccess` (web requests) | The Voice from the RuneScape Wiki's API, anywhere in the game, plus the real time (from the response's `Date` header) for the countdown | The only source that works outside the city, but it's crowdsourced and can lag |
| `chatAccess` (chat access) | Reads the game's own "The Voice of Seren is now active…" announcement, uses chat timestamps as a clock, and posts alerts in your chat box | The announcement is (as far as we know) only shown inside Prifddinas |

The plugin only ever calls one web address, declared in `plugin.json`:
`https://api.weirdgloop.org` (path `/runescape/vos`).

## How it works

### Sources

Every source produces the same thing, a **reading**: two clan names, the hour
they're for, where they came from and how trustworthy that is.
`vos_state.lua` is the only place that decides what's current:

| Rank | Source | File | Notes |
|---|---|---|---|
| 3 (highest) | Game variables | `sources/game_source.lua` | Exact and instant, but only current inside Prifddinas |
| 2 | Prifddinas announcement | `sources/chat_source.lua` | Needs `chatAccess`. Only system messages with no sender are accepted, so players can't spoof it |
| 1 | RuneScape Wiki API | `sources/api_source.lua` | Needs `httpAccess`. Crowdsourced by Alt1 users in Prifddinas; it can be hours or days behind |
| 0 | Saved history | `vos_state.lua` | Fills in this hour's Voice after a relog |

For the same hour, a higher rank replaces a lower one and never the other way
round. A reading for an older hour only goes into history.

### The game's Voice variables

From the client's own variable list (console command `pan VarPlayer`, beta
client of October 22nd, 2026). None of this is in Jagex's documentation.

| Name | ID | Holds |
|---|---|---|
| `ELFCITY_VOICE1_PLAYER` | varbit `-25159` (VarPlayer 4783, bits 0–6) | First active clan, as a number |
| `ELFCITY_VOICE2_PLAYER` | varbit `-25160` (VarPlayer 4783, bits 7–12) | Second active clan |
| `ELFCITY_VOS_PLAYER_HOUR` | varbit `-26417` (VarPlayer 4783, bits 13–18) | The UTC hour those values are for |

Observed on the beta world on October 22nd, 2026:

- The values change on the hour while you're in Prifddinas.
- When you leave the city, the hour drops to 0 and the clan numbers stop
  updating. So this source can't drive alerts away from the city.
- The clan numbers aren't alphabetical, and they don't match any clan order
  in the client's variable list. So far: **1 + 4 = Cadarn and Iorwerth**,
  **2 + 3 = Crwys and Trahaearn**. The plugin only decodes pairs it has
  actually seen (`GameSource.KNOWN_PAIRS`). Any other pair is ignored rather
  than guessed.

### The clock

The countdown needs the real time, but the API has no clock function, and
`os.time()` isn't available in the plugin sandbox (observed on the beta
world). `clock.lua` takes the time from the Wiki API's `Date` header or a chat
message timestamp, then counts forward with the client's 50 logic ticks per
second. With no clock, the strip shows the clans without a countdown, and the
game variables still work.

## Project structure

```
voice-of-seren/              the plugin (this folder goes in dev_plugins)
  plugin.json                manifest: name, version, permissions, URLs
  main.lua                   wires game events to the modules below
  src/
    clans.lua                the eight clans and their effects (static data)
    timeutil.lua             calendar maths and formatting (pure)
    clock.lua                learns the real time, counts forward with ticks
    vos_state.lua            current Voice + history; ranks and merges readings
    display.lua              every piece of text the player sees (pure)
    storage.lua              saved settings and history (PersistentDB)
    hud.lua                  on-screen strip and alert line
    panel.lua                the ribbon panel
    sources/
      game_source.lua        the game's own Voice variables
      chat_source.lua        the Prifddinas chat announcement
      api_source.lua         the RuneScape Wiki API
tools/vos-discovery/         developer tool for the beta world (not for release)
tests/
  run_tests.lua              unit tests for the pure modules
  mock_game_test.lua         runs main.lua against a strict fake game API
docs/
  DESIGN.md                  architecture, decisions, beta-world findings
  TESTING.md                 step-by-step beta-world test plan
.github/workflows/tests.yml  CI: syntax check + both test suites on Lua 5.4
```

## Development

**Requirements:** Lua 5.4. That's what CI uses. The game client runs its own
Lua, and the code avoids anything version-specific.

```sh
lua tests/run_tests.lua        # unit tests: time maths, parsing, state rules, display text
lua tests/mock_game_test.lua   # end-to-end: main.lua against a fake game API
```

Run both from the repository root. `mock_game_test.lua` uses a **strict** fake
API. Reading an API member the fake doesn't define, or setting a component
property the docs don't list, fails the test. So a misspelled API name is
caught before you ever start the client.

**Discovery tool.** `tools/vos-discovery` is a developer-only plugin. It prints
the Voice variables (`VOS VARS …`), variable changes around the hour, and
Seren-related chat to the console. Run it in Prifddinas across an hour change,
note which two clans the city shows, and add the pair to
`GameSource.KNOWN_PAIRS`. See [docs/TESTING.md](docs/TESTING.md).

See [CONTRIBUTING.md](CONTRIBUTING.md) for code conventions and the PR checklist.

## Known issues and roadmap

- **No reliable source outside Prifddinas.** Alerts are meant to bring you back
  to the city, so they need a source that works elsewhere. Today that's only
  the Wiki API, which was two days out of date on October 22nd, 2026.
  - *Idea:* every plugin user who passes through Prifddinas could report the
    Voice (read for free from the game) to Weird Gloop, keeping the API fresh
    for everyone. There's no public submission endpoint. Next step: ask Weird
    Gloop on the [RuneScape Wiki Discord](https://runescape.wiki/w/Help:APIs).
  - *To test:* whether the chat announcement also appears outside Prifddinas
    (allow chat access, stand outside the city at the top of an hour).
- **Clan numbering only partly known.** Two pairs are decoded so far, and
  any other pair falls back to the other sources. Each hour observed in
  Prifddinas adds a pair. Once each number is pinned to one clan,
  `KNOWN_PAIRS` can become a number → clan table that decodes every hour.
- **Panel size.** The ribbon panel's size isn't documented. The layout is about
  650 px tall and may need trimming.
- **Before submitting to the Plugin Hub:** replace `contactEmailAddress` in
  `plugin.json` (Jagex recommends an address that isn't your mod.io login),
  and work through [docs/TESTING.md](docs/TESTING.md).

Ideas for later: strip position setting, alert sound, Travelling Merchant stock
from the same API.

## Plugin guidelines

Built to stay inside Jagex's
[plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html):

- Only shows information that is already public. The Voice is the same on
  every world, shown in Prifddinas and published on the Wiki.
- Never sends input or performs actions for the player.
- Doesn't look at or export anything about other players.
- Both permissions are optional and only add information sources. Plugins that
  request permissions are reviewed by Jagex.
- Deliberately does **not** predict future hours. The rotation has known rules,
  but showing likely next clans could count as predicting hidden state.

## Contributing

Issues and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) first. Beta-world observations (console
output plus a screenshot of the clan icons) are especially useful.

## Licence and credits

- Code: [MIT](LICENSE).
- Clan effect summaries are based on the RuneScape Wiki's
  [Voice of Seren](https://runescape.wiki/w/Voice_of_Seren) page.
- Live Voice data comes from the RuneScape Wiki's API, run by
  [Weird Gloop](https://runescape.wiki/w/Help:APIs).
- Written with AI assistance (Claude). Under Jagex's AI policy, the submitter
  reviews and understands every line before anything is submitted.
- Not affiliated with or endorsed by Jagex. RuneScape is a trademark of Jagex Ltd.
