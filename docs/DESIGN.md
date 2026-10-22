# Design notes

How the Voice of Seren plugin works, why it is built this way, and what is
still unknown. Written October 22nd, 2026, against the RS3 Client API docs at
developer.runescape.com, and updated the same day with what was observed on
the plugin beta world (see [Findings on the beta world](#findings-on-the-beta-world)).

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
  source = "RuneScape Wiki API", observedAt = 1792683420,
  rank = VosState.RANK.WIKI_API }
```

`hourStart` and `observedAt` are nil when the source can't say (for example,
game data read before the plugin knows the time).

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
   **Not available** in the sandbox (observed on the beta world, October 22nd,
   2026), but kept in case that changes.
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

## Findings on the beta world

Observed on October 22nd, 2026 (beta client of that date):

| Question | Answer |
|---|---|
| Is there a game variable for the active districts? | **Yes.** `ELFCITY_VOICE1_PLAYER` (varbit -25159), `ELFCITY_VOICE2_PLAYER` (-25160) and `ELFCITY_VOS_PLAYER_HOUR` (-26417), all packed in VarPlayer 4783 (`ELFCITY_TEMP_2`). Found with the console command `pan VarPlayer`, which copies the client's whole variable list to the clipboard. |
| Do they change on the hour? | **Yes**, while standing in Prifddinas (16:00 → 17:00 UTC). |
| Do they work outside Prifddinas? | **No.** On leaving the city the hour dropped to 0 and the clan numbers stopped updating. |
| How are clans numbered? | **Not alphabetically**, and not in any clan order found in the variable list. Seen: 1 + 4 = Cadarn and Iorwerth (16:00 UTC), 2 + 3 = Crwys and Trahaearn (17:00 UTC). Only seen pairs are decoded (`GameSource.KNOWN_PAIRS`). |
| Is `os.time()` available? | **No.** |
| Do `<col=…>` and `<br>` render in `ui.Text`? | **Yes.** |
| Does the strip appear and update by itself? | **Yes.** It switched clans at the hour with no permissions. |
| Is the Wiki API current? | **Not reliably.** It was two days behind all day. |
| `plugin.json` | The beta client rejects empty `requiredDependencies` / `optionalDependencies` lists ("unexpected json Array, expected a json Object"). Leave them out. |

## Open questions

1. **A source that works outside Prifddinas.** Alerts exist to bring the
   player back to the city, so they need one. Options:
   - Check whether the chat announcement is shown outside Prifddinas.
   - Ask Weird Gloop whether plugin users could submit readings, since the
     plugin reads the Voice for free inside the city. That would keep the API
     fresh for everyone. There's no public submission endpoint today.
2. **Pin down each clan number.** Each hour observed in Prifddinas adds a pair.
   With enough pairs every number resolves to one clan, and `KNOWN_PAIRS` can
   become a number → clan table.
3. **Exact chat wording and type.** One message per district or one for both?
   Which `ChatType`? (`tools/vos-discovery` prints these as `CHAT` lines.)
4. **Panel size.** The ribbon content layer's size isn't documented. The panel
   is about 650 px tall and may need a smaller font or a second page.
5. **Saved lists.** Does `PersistentDB:SetStructuredData` keep list keys as
   numbers? `LoadHistory` copes either way, but it's worth confirming.

## Ideas for later

- A setting for where the strip sits on screen.
- A sound with alerts (the API can play built-in sounds by ID or bundled audio).
- Travelling Merchant stock from the same Wiki API (same permission, one more request a day).
