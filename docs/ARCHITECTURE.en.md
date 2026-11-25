# ForeverMemories architecture

**English** · [Русский](ARCHITECTURE.md)

An addon for one client: World of Warcraft: Forever (`## Interface: 16001`), Lua 5.1.
`ForeverMemories.toc` sets the load order of the files.

## 1. Folders
```
ForeverMemories/
  ForeverMemories.toc  Bindings.xml (key bindings, the game loads it by itself)
  Core/      API, Logger, Util, Serialize, Database, Init, Registry, Events, Commands
  Capture/   Rules, Queue, UIState, Engine            — auto capture
  Modules/   data and logic without UI (see §2)
  UI/        Media, Fonts, Widgets, Main, Dialogs, Capture, History, Settings*, Minimap
  Locales/   enUS, ruRU, ZoneNames (Russian zone names for an English client)
  Media/     own textures (TGA) and fonts (TTF)
  tests/     offline tests and the fake client      — not copied to the game
  tools/     generators and the release build       — not copied to the game
  docs/      documentation                          — not copied to the game
```

## 2. Modules
| Module | Responsibility |
|---|---|
| Core/API | The only place that calls client functions. Returns a value or `nil`; secret values never reach arithmetic. |
| Core/Init | The `ns` namespace, one event dispatcher (`ns.On`), `SafeCall`, localization, start order. |
| Core/Database | Loading, migrations, validation and repair of `ForeverMemoriesDB`. Pure logic. **The data schema is described at the top of this file.** |
| Core/Registry | 9 events + `MANUAL` + `PASSIVE`: delay, priority, icon, availability. |
| Core/Events | Client event → `{type, key, info, character, zone}` → Journey and Engine. |
| Core/Serialize | The `FMB1:…` backup format. Own parser: the text is never run as Lua. |
| Core/Commands | The `/fm …` commands. |
| Capture/* | Rules (event + settings → request), Queue (priority queue), UIState (hide/restore the interface for a clean shot), Engine (one screenshot at a time, confirmed by `SCREENSHOT_SUCCEEDED`, limits). |
| Modules/History | Screenshot records and counters. |
| Modules/Activity | The shared clock of active play (1 s, not AFK): playtime by day, seconds for Passive and UI. |
| Modules/Steps | Step counter with its own 0.5 s timer (see §4). |
| Modules/Passive | Passive capture from the accumulated active time. |
| Modules/Locations, ZoneCatalog, ZoneStats | Visited zones, the Forever zone catalog (AreaTable IDs), time/steps/visits per zone. |
| Modules/Stories, ArtPack | Short zone texts; pictures from the optional `ForeverMemories_ArtPack` addon. |
| Modules/Adventure, Journey, Memories | Calendar and recaps, the journey of important moments, "On this day" and anniversaries. |
| Modules/Records, SessionRecap | Personal records, the play session recap. |
| Modules/Progress, Trackers | Character states for achievements (money, reputations, professions…). Only confirmed values; the past is never guessed. |
| Modules/AchievementCatalog, Achievements | The catalog of 106 achievements (character + account, 54 cards) and their checks; step chains (`chain`) and cards for the page. |
| Modules/Notifications | Three kinds of notifications (mini, discovery, legendary) and the chat line. Each kind has its own place and size (`ui.notify`). |
| Modules/DataTools, ProjectInfo | Characters, export, backup, deletion; diagnostics without name, realm or GUID. |
| Modules/ChangelogData | **Generated** by `tools/changelog.lua` from CHANGELOG.md and CHANGELOG.en.md. |
| UI/* | Display only. Screenshots go through `Engine.ManualShot`. |

Auto capture and the step counter never call each other. Every handler runs in `pcall`,
so an error in one does not stop the other.

## 3. Screenshot flow
```
client event → Events ────────────┐
Activity clock → Passive (interval) ┴→ Engine.Submit → Rules → Queue
  → (event delay) → UIState.Prepare (clean shot) → Screenshot()
  → SCREENSHOT_SUCCEEDED → History.AddShot → Notifications
  → FAILED / 5 s timeout → logged, counters unchanged
```
Timers carry a token: a state change turns old timers into no-ops. Loading screens and
pause cancel automatic requests.

## 4. Step counter
Every 0.5 s: taxi, vehicle, flying and swimming are not counted. Position comes from
`UnitPosition` (yards) or map → world. A jump farther than `speed × time × 1.5 + 1 yard`
(teleport, charge) is not counted. Steps = yards × 0.9144 / 1.5 m.

## 5. Data
`ForeverMemoriesDB` (SavedVariables), schema **6**. All fields and the migration rules are
described in the comment at the top of `Core/Database.lua` (one place, so it never drifts).
A migration runs on a copy and is applied only if no total (characters, screenshots, steps,
days, zones, achievements) went down. A file from a newer addon version is never touched.

## 6. Look
- The palette is `W.COLORS` in `UI/Widgets.lua`: dark matte surfaces, thin gold frames.
- Every path to our own textures and fonts lives only in `UI/Media.lua`. A test checks that
  each file listed there exists.
- TGA: power-of-two size, no RLE compression.
- `tools/make_borders.py` makes the notification borders (9-slice); `tools/make_mini_back.py`
  makes the mini notification background in the exact shape of its frame. Run
  `python3 tools/<file>` from the root (needs Pillow).

## 7. Tools
| File | What it does |
|---|---|
| `tools/changelog.lua` | CHANGELOG.md + CHANGELOG.en.md → `Modules/ChangelogData.lua`. Run after editing the changelog. |
| `tools/release.sh <version>` | Updates the changelog page, runs the smoke test, builds `dist/ForeverMemories-v<version>.zip`. |
| `tools/make_*.py` | Texture generators (see §6). |

`Modules/AchievementCatalog.lua` and `Locales/ZoneNames.lua` were once generated from
`docs/catalog/`; those sources are no longer in the repository, so these files are edited by hand.
