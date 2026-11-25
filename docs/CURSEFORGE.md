# CurseForge page

Texts for the CurseForge project page. Copy them into the project form.
Тексты для страницы проекта на CurseForge. Их копируют в форму проекта.

## Project name

ForeverMemories

## Summary (one line)

Automatic screenshots, step counter, playtime and an adventure diary for World of Warcraft: Forever.

## Description (Markdown)

In the editor switch WYSIWYG to Markdown, then paste the text between the lines.

The banner `logo_full` (512×256) can be inserted at the top with the editor's image button.

---

**Your adventure. Your story.**

ForeverMemories is an automatic photographer and adventure diary for **World of Warcraft: Forever**.
Install it, log in, and it just works: the addon takes screenshots of important moments, counts
your steps and playtime, and keeps your character's story.

> **First release.** The addon is checked in the Forever client while playing.
> Please report bugs in the Comments.

### Features

- **Home**: today's adventure. Screenshots, steps, locations and playtime of the day, the
  current location, the countdown to the next passive screenshot, the latest screenshots and
  the week of adventures.
- **Auto capture**: a screenshot on level up, death, boss kill, duel win, rare, epic and
  legendary loot, new zone, joining a guild. Normal or clean shot (without the interface).
- **Passive capture**: one screenshot every 15 / 30 / 45 / 60 minutes of active play
  (not while AFK, loading or in combat).
- **History**: Overview (totals, calendar, "On this day"), Screenshots, Steps, Locations,
  Playtime, Journey, Records and Achievements (Hall of Memories: 106 achievements in 54 cards,
  with step chains and a progress dashboard). View any of your characters or all of them.
- **Notifications**: mini, discovery and legendary. Each has its own position, size and time
  on screen.
- **Data**: per-character statistics, export, backup and import.
- Languages: English and Russian.

### Usage

- `/fm` opens the window. Minimap button: left click opens the window, right click pauses
  auto capture, middle click takes a screenshot.
- `/fm shot` takes a screenshot; `/fm on`, `/fm off`, `/fm toggle` control auto capture.
- `/fm ui` brings the interface back if it stayed hidden after a clean shot.
- `/fm reset` moves the window to the screen centre.
- Key bindings: Esc → Options → Keybindings → AddOns → ForeverMemories.

### Good to know

- The game itself saves screenshots to `_forever_/Screenshots`. An addon cannot show, rename
  or delete files, so the history keeps only records of them.
- Steps are an estimate based on how far the character moves.

---

### По-русски

**ForeverMemories** — автоматический фотограф и дневник приключений для **World of Warcraft: Forever**.
Установил, зашёл в игру — всё работает: аддон сам делает скриншоты важных моментов, считает шаги
и время в игре и собирает историю персонажа.

- Снимки при новом уровне, смерти, победе над боссом, победе в дуэли, редком, эпическом и
  легендарном предмете, новой зоне, вступлении в гильдию. Обычный или чистый кадр (без интерфейса).
- Пассивная съёмка каждые 15 / 30 / 45 / 60 минут активной игры.
- История: обзор и календарь, снимки, шаги, локации, время, хроника, рекорды, достижения.
- Уведомления, экспорт и резервная копия данных. Русский и английский язык.
- `/fm` — открыть окно.

> **Первый выпуск.** Об ошибках пишите в комментариях.

---

Fonts Inter and Cormorant Garamond are used under the SIL Open Font License.

## Upload settings

| Field | Value |
| --- | --- |
| Game | World of Warcraft |
| Game version | Forever (client 1.60.1, Interface 16001) |
| Release type | Release (Beta files are hidden from most users) |
| Display name | ForeverMemories 1.0.0 |
| Changelog | The CHANGELOG.en.md entry of this version |
| File | `dist/ForeverMemories-v<version>.zip` from `tools/release.sh <version>` |

## Release procedure / Как выпускать версию

1. Number by SemVer: fixes `1.0.1`, new features `1.1.0`. Change it in `ForeverMemories.toc`,
   `Core/Init.lua`, README and add the entry to CHANGELOG.md and CHANGELOG.en.md.
2. `sh tools/release.sh <version>`: tests, then `releases/ForeverMemories-v<version>.zip` and
   `releases/ForeverMemories-v<version>.changelog.md` (git ignores `releases/`).
3. CurseForge → Files → Add File: the zip, display name `ForeverMemories <version>`,
   game version 1.60.1, Release, changelog in Markdown from the `.changelog.md` file.

Never rename the `ForeverMemories` folder or the `.toc`: the game would treat it as another addon.
