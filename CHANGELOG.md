# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased] — 0.1.0

First version, in testing on the plugin beta world.

### Added

- On-screen strip with the two active clans and a countdown to the next hour;
  watched clans are highlighted, and the strip can be turned off.
- Ribbon panel with both clans' effects, the information source and its age,
  alert checkboxes, a strip toggle, recent history and setup tips.
- Alerts for watched clans (screen, plus chat with `chatAccess`), at most once
  per clan per hour, remembered across reloads.
- Three ranked information sources:
  - the game's own `ELFCITY_VOICE1/2_PLAYER` and `ELFCITY_VOS_PLAYER_HOUR`
    variables (no permissions; current inside Prifddinas only). Only number
    pairs matched to clans on the beta world are decoded: 1 + 4 = Cadarn and
    Iorwerth, 2 + 3 = Crwys and Trahaearn.
  - the Prifddinas chat announcement (optional `chatAccess`), filtered to
    system messages so players can't spoof it.
  - the RuneScape Wiki API at api.weirdgloop.org (optional `httpAccess`), with
    polite request spacing and a descriptive User-Agent.
- A clock built from web `Date` headers or chat timestamps, counted forward
  with logic ticks.
- Voice history (24 hours), saved and restored after a relog.
- `tools/vos-discovery` developer plugin for beta-world investigation.
- Unit tests, an end-to-end test against a strict fake game API, and CI.

### Fixed during beta testing (October 22nd, 2026)

- Removed empty `requiredDependencies` / `optionalDependencies` lists, which
  the beta client refuses to load.
- The panel tip about web requests is shown again when game data is
  available, because game data only works inside Prifddinas.
- Clan numbers are no longer assumed to be alphabetical. Only pairs that have
  been seen are decoded.
- Game values are ignored once you leave Prifddinas (hour drops to 0).
