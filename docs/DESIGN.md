# Design notes

How the Voice of Seren plugin works, why it is built this way, and what is
still unknown. Written October 22nd, 2026, against the RS3 Client API docs at
developer.runescape.com.

## Data flow

```
  game events                    sources                state            output
  -----------                    -------                -----            ------
  ServerLogic (0.6 s) ------> api_source.lua --\
  ChatMessage --------------> chat_source.lua --+--> vos_state.lua --> display.lua --> hud.lua
  VarTransmit --------------> game_source.lua --/        |                        \-> panel.lua
  Logic (50/s) -------------> clock.lua                   v
  ContentLayerReady --------> panel.lua              storage.lua (PersistentDB)
```

Every source produces the same thing, a **reading**:

```lua
{ clans = { "Iorwerth", "Cadarn" }, hourStart = 1792681200,
  source = "RuneScape Wiki API", observedAt = 1792683420 }
```

`vos_state.lua` is the only place that decides what is "current". Because of
that, adding or removing a source never touches the UI code.

## Rules in vos_state.lua

- A reading for an **older hour** never replaces a newer one. It only goes into history.
- Two readings for the **same hour** are merged, up to two clans. This covers the
  game announcing each district in its own chat message.
- A reading is **current** only if its hour matches the real clock. If the
  clock is unknown, the latest reading is trusted.
- **Alerts** fire only for current readings, only for watched clans, and at most
  once per clan per hour.
- History keeps 24 hours and is saved, so after a relog in the same hour the
  panel is not blank.

## The clock problem

The API documents no clock function (`Plugin`, `World` and the core pages have
nothing). A countdown needs one, so `clock.lua`:

1. Tries `os.time()`. This is undocumented, so it is attempted inside `pcall`.
2. Takes the `Date:` header from any Wiki API response.
3. Takes `timestamp` (Unix seconds) from any chat event.

Once synced, it counts forward with `Event.Logic`, which the docs say runs at a
fixed 50 ticks per second. Everything that schedules future work (web
requests, alert expiry) uses ticks, so it works even before the clock is known.

## Web request etiquette

- One request on start, then one about 90 seconds after each hour change.
- If the data is not for the current hour yet, or the request fails, it retries
  every 5 minutes, never faster.
- Sends a descriptive `User-Agent`, as the Wiki's API page asks.

That works out to roughly 1–3 requests per player per hour.

## Guideline risk review

| Feature | Guideline tier | Why |
|---|---|---|
| Showing the active clans | Allowed | Public information, shown in Prifddinas and on the Wiki |
| Countdown to the hour | Allowed | The Voice always moves on the hour; this is known, not predicted |
| Alerts for watched clans | Allowed | "Notifications based on visible or already-known non-combat events" |
| `httpAccess` | Subject to review | Any permission is reviewed; the URL is a single, well-known API |
| `chatAccess` | Subject to review | Read-only, filtered to the announcement; writes only the plugin's own alert |
| Predicting future hours | **Not built on purpose** | The rotation has rules (two-hour cooldown, 50% return chance), but showing likely next clans could count as predicting future state |

## Open questions (answer on the beta world)

1. **Is there a game variable for the active districts?** The Prifddinas clan
   icons suggest yes. If so, `game_source.lua` makes both permissions
   unnecessary for most players. → `tools/vos-discovery`
2. **Exact chat wording and type.** Is it one message per district or one for
   both? Which `ChatType`? Is it sent outside Prifddinas?
3. **Is `os.time()` available?** If yes, the clock works with no permissions.
4. **Fonts and markup.** Do `<col=...>` and `<br>` work in `ui.Text`? (The
   tutorial uses `<br>`; `<col>` is used in chat examples.)
5. **Panel size.** The ribbon content layer's size isn't documented. The panel
   is about 600 px tall; it may need a smaller font or a second page.

## Ideas for later

- A setting for where the strip sits on screen.
- A sound with alerts (the API can play built-in sounds by ID or bundled audio).
- Travelling Merchant stock from the same Wiki API (same permission, one more request a day).
