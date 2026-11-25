# Testing

**English** · [Русский](TESTING.md)

The main rule: a feature counts as working only once it has been checked in the Forever
client. An offline test proves that the Lua runs without errors, not how it looks and
works in the game.

## 1. Offline (without the game)
Needs `lua5.1`. Run from the addon root:

| Command | What it checks | State (1.0.0-beta.17) |
|---|---|---|
| `lua5.1 tests/smoke.lua` | The addon loads, every tab and every History/Settings page opens in both languages, every file listed in `UI/Media.lua` exists. | 54 / 54 PASS |
| `lua5.1 tests/run.lua` | The full suite: migrations and schema 6, auto capture, steps, diary, achievements, settings, changelog. | 112 / 112 PASS |

`tests/mock_wow.lua` is the fake client (WoW functions and frames) both suites run on.
Before a release both suites must pass in full.

## 2. In the Forever client: checklist
Tick these while playing. If something is wrong, take a screenshot and run `/fm diag`.

**Installation and window**
- [ ] The addon is in the list, no Lua errors at login; `/fm` opens the window, Esc closes it.
- [ ] Our textures and fonts show (no green squares); English and Russian switch.
- [ ] The window drags; scale and size are kept after `/reload`.

**Auto capture**
- [ ] Level up, death, boss, duel, rare/epic/legendary item, new zone, guild: a screenshot
      appears in `_forever_/Screenshots` and in History.
- [ ] A clean shot hides the interface and brings it back; `/fm ui` restores it in an emergency.
- [ ] A passive screenshot after the chosen interval of active play; time stops in AFK and combat.

**Notifications**
- [ ] Mini, discovery and legendary look tidy: background inside the frame, "x" inside the frame.
- [ ] "Preview" shows and hides a sample; "Edit" applies place, size and scale at once.

**History and data**
- [ ] All eight sections open; picking a character and "All characters" work.
- [ ] Steps: running 30 s in a straight line ≈ 210 yards ≈ 128 steps.
- [ ] Everything is kept after `/reload` and relog; backup → import brings the data back.

## 3. Client API: what is known
Viktor's client: Forever 1.60.1, build 71037, `GetBuildInfo()` → 16001 (matches the TOC), Linux (Wine).

| What | State |
|---|---|
| `Screenshot()`, `SCREENSHOT_STARTED/SUCCEEDED` | work (v0.0.1 spike): success arrives asynchronously, ~0.08 s, in combat too; `FAILED` could not be triggered |
| `GetBuildInfo`, `C_Timer.After/NewTimer/NewTicker`, `InCombatLockdown`, `UnitLevel`, `GetMaxPlayerLevel`, `GetRealZoneText`, `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `IsInInstance`, `issecretvalue`, `C_EventUtils.IsEventValid`, `C_AddOns.GetAddOnMetadata`, `GetLocale` | present in the client |
| `UnitPosition`, `GetUnitSpeed`, `IsSwimming/IsFlying/UnitOnTaxi/UnitInVehicle` | not checked; on a secret or `nil` no steps are counted |
| `RequestTimePlayed` / `TIME_PLAYED_MSG` | not checked; without them the addon shows its own active playtime |
| `UnitIsAFK` | present; behaviour on `/afk` not checked (without it the character counts as not AFK) |
| `UnitGUID("player")` | not checked whether it is stable between sessions |

The character key is `Realm:Name`, not the GUID: the community says GUIDs are obfuscated in
Forever, and a GUID key could lose the history. The GUID is saved and compared: `/fm debug`
→ the Character line shows `(changed!)` if it changed. `/fm debug` also lists functions the
client lacks.
