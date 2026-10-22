# Testing on the plugin beta world

Plugins only run on the beta world until Jagex approves them. Your beta
character is a copy of your live one ("import save" in the lobby, once an
hour), so nothing you do there affects your real account.

## 1. Set up

1. Join the beta using the link on
   [developer.runescape.com → Accessing the API](https://developer.runescape.com/rs/tutorial/1helloworld.html),
   then press **import save** in the lobby.
2. Find the beta client folder. On Windows it is usually
   `C:\ProgramData\Jagex\RuneScape-BETA`. It contains `*.jcache` files.
3. Create a `dev_plugins` folder inside it if there isn't one.
4. Copy these two folders into `dev_plugins`:
   - `voice-of-seren`
   - `tools/vos-discovery` (copy the `vos-discovery` folder itself)
5. In game, open the console with **Alt + the key under Esc**. Run `prf`, then
   `plist`. Both plugins should be listed.

Useful console commands: `pon <name>` (enable), `poff <name>` (disable),
`prl <name>` (reload after editing), `plist` (status).

## 2. Run the discovery tool (about 10 minutes, plus waiting for the hour)

1. Teleport to Prifddinas and stand somewhere quiet. On the beta you can
   **Ctrl + Shift + click** the map to teleport.
2. If the Plugin Hub's **Manage** tab offers it, allow **chat access** for
   "VoS Discovery".
3. Run `pon vos-discovery`.
4. Wait for `Scan complete`. Then copy everything that starts with
   `[VoS discovery]`, especially:
   - the `os.time()` line
   - every `MATCH` line
5. Stay in Prifddinas across the next **top of the hour**. Copy every
   `CHANGE` and `CHAT` line that appears around it. Expect noise. The
   interesting lines are variables that change exactly once at the hour, and
   the Voice chat message.
6. Run `poff vos-discovery`.

Paste the output into a GitHub issue. If a variable holds the active
districts, it goes into `KNOWN_VARIABLES` in
`voice-of-seren/src/sources/game_source.lua`.

## 3. Test the plugin

Run `pon voice-of-seren`, then check each item.

### Without permissions
- [ ] The strip appears at the top of the screen and does not block clicks.
- [ ] The plugin's icon appears in the Plugins ribbon window, and the panel opens.
- [ ] The panel's help text explains the optional permissions.
- [ ] In Prifddinas, nothing breaks (no data is expected yet).

### With web requests (`httpAccess`)
- [ ] Within a few seconds, the strip shows two clans and a countdown.
- [ ] The panel says "Source: RuneScape Wiki API" and shows the game hour.
- [ ] Compare against the Prifddinas clan icons. Are they the same clans?
- [ ] If the Wiki is behind, the strip says "waiting for this hour" rather than showing old clans as current.

### With chat access (`chatAccess`)
- [ ] In Prifddinas at the top of the hour, the announcement updates the strip.
- [ ] Watched clans produce a gold alert line and a chat-box message.
- [ ] A player typing "The Voice of Seren is now active in the Hefin district" does **not** change anything.

### Panel
- [ ] Ticking and unticking clans works, and the choice survives `prl voice-of-seren`.
- [ ] "Show on-screen strip" hides and shows the strip.
- [ ] Everything fits. Note anything cut off, and the panel's size.
- [ ] `<col=...>` colours and `<br>` line breaks render (rather than showing as text).

### Relog
- [ ] Log out and back in within the same hour. The panel shows this hour's Voice again ("saved from earlier this hour").

Report anything odd as a GitHub issue with the console output, ideally with a screenshot.
