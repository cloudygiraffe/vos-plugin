# Contributing

Thanks for helping. This guide covers setting up, the conventions the code
follows, testing (locally and on the beta world), and what a pull request
needs.

## Setting up

1. Fork and clone the repository.
2. Install **Lua 5.4** (CI uses the `lua5.4` package on Ubuntu; any 5.4
   build works).
3. Check everything passes before you change anything:

   ```sh
   lua tests/run_tests.lua
   lua tests/mock_game_test.lua
   ```

To try your changes in game you need access to the plugin beta world; see
[Testing on the beta world](#testing-on-the-beta-world).

## How the code is organised

- `voice-of-seren/main.lua` only wires game events to modules and owns the
  player's settings. Logic lives in `voice-of-seren/src/`.
- **Pure modules** (`clans`, `timeutil`, `vos_state`, `display`, and the parsing
  functions in `sources/`) never touch the game API. They're unit tested in
  `tests/run_tests.lua`. Keep new logic pure where you can.
- **Game-facing modules** (`hud`, `panel`, `storage`, the `Update` / `Poll` /
  `HandleEvent` parts of `sources/`) are thin, and are covered by
  `tests/mock_game_test.lua`.
- Every information source returns the same **reading** shape
  (`{ clans, hourStart, source, observedAt, rank }`) and reports through
  `handleReading` in `main.lua`. To add a source, add a file under
  `src/sources/`, give it a rank in `VosState.RANK`, and call it from
  `main.lua`. Nothing in the UI needs to change.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design and the state rules.

## Code conventions

- **4-space indentation**, no tabs; `camelCase` locals and functions,
  `PascalCase` module tables, `UPPER_CASE` constants.
- **One module table per file** (`local Display = {} ... return Display`),
  loaded with `require("src/...")`. Paths are relative to the plugin folder.
- **Comment as you go.** Every file starts with a header saying what it's for
  and where it fits. Every public function says what it takes, what it returns
  and any side effects. Explain *why* for anything non-obvious.
- **Mark where facts come from.** Game behaviour that isn't in Jagex's docs is
  written as "observed on the beta world, <date>", with the date written out
  US-style ("October 22nd, 2026").
- **Every game API call that can fail goes in `pcall`.** That covers anything
  undocumented, anything permission-gated, and anything reading components that
  may have gone away. The plugin should degrade, never crash.
- **Only documented component properties.** Don't set a property that isn't
  listed on developer.runescape.com. The fake API in `mock_game_test.lua` will
  fail the test if you do. If you need a new one, add it to the fake's
  `DOCUMENTED_PROPERTIES` list along with a link to the doc page.
- **PersistentDB is shared by every character on the computer.** This plugin's
  data (watched clans, Voice history) is the same for every character, so it
  uses plain keys. Per-character data would need the character's name in the
  key.
- **Text the player sees is built in `display.lua`**, so wording can be tested
  without the game. Use `<br>` for line breaks and `<col=RRGGBB>…</col>` for
  colour.

## Tests

- Add a unit test to `tests/run_tests.lua` for any change to a pure module:
  `test("what it checks", function() eq(actual, expected) end)`.
- If you change how `main.lua` uses the game API, extend
  `tests/mock_game_test.lua`. It fires fake events, and you assert on what the
  plugin drew or saved. If you use a new API member, add it to the fakes there.
- CI (`.github/workflows/tests.yml`) syntax-checks every `.lua` file and runs
  both suites on every push and pull request.

## Testing on the beta world

Full steps are in [docs/TESTING.md](docs/TESTING.md). In short: copy
`voice-of-seren/` (and, if needed, `tools/vos-discovery/`) into
`C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins`, then in the console (Alt +
the key under Esc) run `prf`, `plist` and `pon voice-of-seren`. Close the
plugin's panel before `prl`, or you'll keep seeing the old panel.

### plugin.json gotcha

The beta client of October 22nd, 2026 refuses to load a manifest that contains
an empty dependency list: `"requiredDependencies": []` gives "Failed to decode
metadata at plugin.json - unexpected json Array, expected a json Object".
Leave out `requiredDependencies` / `optionalDependencies` when they're empty.
Empty permission lists (`"requiredPermissions": []`) are fine.

## Pull request checklist

- [ ] `lua tests/run_tests.lua` and `lua tests/mock_game_test.lua` pass.
- [ ] New or changed behaviour has a test.
- [ ] New code is commented to the standard above, and no comment you touched
      is now out of date.
- [ ] README / `docs/` updated if behaviour, permissions or findings changed.
- [ ] `CHANGELOG.md` has a line under "Unreleased".
- [ ] Tested on the beta world if the change touches the game API or the UI
      (say what you tested in the PR).
- [ ] No new permission or URL without explaining why in the PR. Each one adds
      to Jagex's review.

## Submitting to the Plugin Hub

Jagex's AI policy requires that whoever submits a plugin has reviewed and
understood all of its code, including any parts written with AI assistance.
Before submitting, read every file and replace the placeholder
`contactEmailAddress` in `plugin.json`.
