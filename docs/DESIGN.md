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
- Sources are **ranked**: game data, then the Prifddinas announcement, then the
  Wiki API. For the same hour, a higher-ranked reading replaces the clans and a
  lower-ranked one is ignored.
- Two readings of the **same rank** for the same hour are merged, up to two
  clans. This covers the game announcing each district in its own message.
- In a **new hour**, every clan counts as newly active (a clan can't hold the
  Voice two hours running), so watched clans always alert.
- A reading is **current** only if its hour matches the real clock. If the
  clock is unknown, the latest reading is trusted.
- **Alerts** fire only for current readings, only for watched clans, and at most
  once per clan per hour. Which clans already alerted is saved, so reloading the
  plugin doesn't repeat them.
- History keeps 24 hours and is saved, so after a relog in the same hour the
  panel is not blank.

## The clock problem

The API documents no clock function (`Plugin`, `World` and the core pages have
nothing). A countdown needs one, so `clock.lua`:

1. Tries `os.time()`. This is undocumented, so it is attempted inside `pcall`.
2. Takes the `Date:` header from any Wiki API response.
3. Takes `timestamp` (Unix seconds) from a chat event, only if nothing better
   is known.

Once synced, it counts forward with `Event.Logic`, which the docs say runs at a
fixed 50 ticks per second. The logic tick counts from when the *client*
started, so a sync made before the first tick is anchored to that first tick;
otherwise the clock would jump ahead by the client's uptime. Everything that schedules future work (web
requests, alert expiry) uses ticks, so it works even before the clock is known.

## Web request etiquette

- One request on start, then one 90–150 seconds after each hour change (the
  extra spread varies per player so requests don't all land at once).
- If the data is not for the current hour yet, or the request fails, it retries
  every 5 minutes, never faster. Without a clock it polls every 10 minutes.
- Sends a descriptive `User-Agent`, as the Wiki's API page asks.

Normally that is 1–2 requests per player per hour. While the Wiki is behind it
can reach 12 an hour.

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

1. **Is there a game variable for the active districts?** Yes (October 22nd,
   2026): `ELFCITY_VOICE1_PLAYER` (varbit -25159), `ELFCITY_VOICE2_PLAYER`
   (-25160) and `ELFCITY_VOS_PLAYER_HOUR` (-26417), all in VarPlayer 4783.
   Values 1 and 4 at 16:00 UTC (Cadarn and Iorwerth), 2 and 3 at 17:00 UTC
   (Crwys and Trahaearn): not alphabetical, so only seen pairs are decoded
   until every number is pinned down. The hour drops to 0 on leaving the
   city, so this source only works inside Prifddinas. Still to confirm: that they change on the
   hour, and whether they update away from Prifddinas.
2. **Exact chat wording and type.** Is it one message per district or one for
   both? Which `ChatType`? Is it sent outside Prifddinas?
3. **Is `os.time()` available?** If yes, the clock works with no permissions.
4. **Fonts and markup.** Do `<col=...>` and `<br>` work in `ui.Text`? (The
   tutorial uses `<br>`; `<col>` is used in chat examples.)
5. **Panel size.** The ribbon content layer's size isn't documented. The panel
   is about 630 px tall; it may need a smaller font or a second page.

6. **Saved lists.** Does `PersistentDB:SetStructuredData` keep list keys as
   numbers? `LoadHistory` copes either way, but it's worth confirming.
7. **Two text lines on the shared plugin layer.** The docs say component
   creation can fail on an ID clash; confirm the strip and alert line both appear.

## Ideas for later

- A setting for where the strip sits on screen.
- A sound with alerts (the API can play built-in sounds by ID or bundled audio).
- Travelling Merchant stock from the same Wiki API (same permission, one more request a day).
