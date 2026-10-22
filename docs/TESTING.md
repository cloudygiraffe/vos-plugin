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
`prl <name>` (reload after editing), `plist` (status, including load errors).
Close the plugin's panel before `prl`, or the old panel stays on screen.

If `plist` shows "Failed to decode metadata at plugin.json - unexpected json
Array", the manifest has an empty `requiredDependencies` or
`optionalDependencies` list. Remove it (the October 22nd, 2026 beta client
rejects them).

## 2. Run the discovery tool (stay in Prifddinas across an hour change)

The tool's main job now is pinning down which number means which clan.

1. Teleport to Prifddinas. On the beta you can **Ctrl + Shift + click** the
   map to teleport.
2. Optional: allow **chat access** for "VoS Discovery" in the Plugin Hub's
   **Manage** tab, so it also logs Seren chat messages and has a clock.
3. Run `pon vos-discovery`. It prints its environment, then a line like:
   `VOS VARS: ELFCITY_VOICE1_PLAYER=1 ELFCITY_VOICE2_PLAYER=4 ELFCITY_VOS_PLAYER_HOUR=16 ...`
4. Screenshot that line **together with the two clan icons** shown at the top
   left of the screen in Prifddinas. Hover an icon if you're unsure which clan
   it is.
5. Stay in Prifddinas across the top of the hour. A new `VOS VARS` line
   appears when the Voice moves; screenshot it with the new icons too.
6. Optional: allow chat access, go **outside** Prifddinas before the next
   hour, and note whether a "The Voice of Seren is now active…" `CHAT` line
   appears. This decides whether chat can drive alerts away from the city.
7. Run `poff vos-discovery`.

Open an issue with the screenshots. Each new pair of numbers goes into
`GameSource.KNOWN_PAIRS` in `voice-of-seren/src/sources/game_source.lua`.

To see every variable the client knows, run `pan VarPlayer` or `pan VarClient`
in the console. It copies the full list (ID, name, type and, for varbits, the
VarPlayer and bit mask) to the clipboard.

## 3. Test the plugin

Run `pon voice-of-seren`, then check each item.

### Without permissions
- [ ] The strip appears at the top of the screen and does not block clicks.
- [ ] The plugin's icon appears in the Plugins ribbon window, and the panel opens.
- [ ] In Prifddinas, the strip shows the two active clans within a few seconds
      (only for clan pairs already in `KNOWN_PAIRS`; otherwise it stays
      "not known yet").
- [ ] At the top of the hour, still in Prifddinas, the strip switches by itself.
- [ ] Outside Prifddinas, the panel's tip suggests allowing web requests.

### With web requests (`httpAccess`)
- [ ] Within a few seconds, the strip shows two clans and a countdown.
- [ ] The panel says "Source: RuneScape Wiki API" and shows the game hour.
- [ ] Compare against the Prifddinas clan icons. Are they the same clans?
- [ ] If the Wiki is behind, the strip says "waiting for this hour" rather than showing old clans as current.

### With chat access (`chatAccess`)
- [ ] In Prifddinas at the top of the hour, the announcement updates the strip.
- [ ] Outside Prifddinas at the top of the hour: does the announcement appear
      at all? (Record the answer in an issue either way.)
- [ ] Watched clans produce a gold alert line and a chat-box message.
- [ ] A player typing "The Voice of Seren is now active in the Hefin district" does **not** change anything.

### Panel
- [ ] Ticking and unticking clans works, and the choice survives `prl voice-of-seren`.
- [ ] "Show on-screen strip" hides and shows the strip.
- [ ] Everything fits. Note anything cut off, and the panel's size.
- [ ] `<col=...>` colours and `<br>` line breaks render (rather than showing as text).

### Relog
- [ ] Log out and back in within the same hour. Once the plugin knows the time
      (system clock, Wiki API or a chat message), the panel shows this hour's
      Voice again ("saved from earlier this hour"). With no permissions and no
      `os.time()`, this can't happen; note which case you tested.
- [ ] Reload with `prl voice-of-seren` while a watched clan is active. The alert
      should not repeat.

Report anything odd as a GitHub issue with the console output, ideally with a screenshot.
