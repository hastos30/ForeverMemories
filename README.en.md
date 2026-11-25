# ForeverMemories

**English** · [Русский](README.md)

An addon for **World of Warcraft: Forever**: an automatic photographer and adventure diary.
Install it, log in, and it just works. The addon takes screenshots of important moments,
counts your steps and playtime, and keeps your character's story. *Your adventure. Your story.*

Version **1.0.0-beta.15**. The offline tests pass; in the Forever client it is checked while
playing (what exactly: [docs/TESTING.en.md](docs/TESTING.en.md)).

## Features
- **Home**: today's adventure. Screenshots, steps, locations and playtime of the day, the
  current location, the countdown to the next passive screenshot, the latest screenshots and
  the week of adventures.
- **Auto capture**: a screenshot on events: level up, death, boss, duel win, rare, epic and
  legendary item, new zone, joining a guild. Normal or clean shot (without the interface).
  Passive capture: one screenshot every 15 / 30 / 45 / 60 minutes of active play.
- **History**: eight sections: Overview (totals, calendar, "On this day"), Screenshots, Steps,
  Locations (exploring Azeroth), Playtime, Journey, Records, Achievements (Hall of Memories,
  106 achievements of the character and the account). View any of your characters or all of them.
- **Notifications**: three kinds (mini, discovery, legendary). Each has its own place on
  screen, size and time on screen; "Preview" shows a sample.
- **Settings**: General, Appearance, Notifications, Data (characters, export, backup and
  import), About, Changelog (version history).
- Languages: English and Russian.

## Installation
1. Download `ForeverMemories-v<version>.zip`.
2. Unpack it into `World of Warcraft/_forever_/Interface/AddOns/` so that you get the folder
   `AddOns/ForeverMemories/` with `ForeverMemories.toc` inside.
3. Restart the game and enable the addon in the addon list.

## Usage
- `/fm` opens the window. Minimap button: left click opens the window, right click pauses
  auto capture, middle click takes a screenshot.
- `/fm shot` takes a screenshot; `/fm on`, `/fm off`, `/fm toggle` control auto capture.
- `/fm status`, `/fm debug`, `/fm diag`, `/fm log`, `/fm zones` are diagnostics.
- `/fm ui` brings the interface back if it stayed hidden after a clean shot.
- `/fm reset` moves the window to the screen centre; `/fm fonts` turns the addon fonts on/off.
- Key bindings (none by default): Esc → Options → Keybindings → AddOns → ForeverMemories.

The game itself saves screenshots to `_forever_/Screenshots`. An addon cannot show, rename
or delete files, so the history keeps only records of them.
Steps are an estimate based on how far the character moves.

## For developers
- [docs/ARCHITECTURE.en.md](docs/ARCHITECTURE.en.md): how the addon is built.
- [docs/TESTING.en.md](docs/TESTING.en.md): tests and in-game checks.
- [PROGRESS.en.md](PROGRESS.en.md): current state and the plan to 1.0.
- [CHANGELOG.en.md](CHANGELOG.en.md): version history.

## License
Inter and Cormorant Garamond fonts: SIL Open Font License (`Media/Fonts/OFL-*.txt`).
