# Progress

**English** · [Русский](PROGRESS.md)

Current version: **1.0.0-beta.18** (2026-11-25). Built, tests 54/54 and 118/118, checked in the
Forever client from Viktor's screenshots. The full history of every version is in
[CHANGELOG.en.md](CHANGELOG.en.md).

## Now
- beta.8 – beta.12 fixed the look of the window and the notifications from in-game
  screenshots: our own icons, cut frame corners, settings for each notification, the
  character picker in History, the mini notification background in the exact frame shape.
- beta.13 tidied the documentation: everything in Russian and English, outdated specs and
  plans removed, the changelog is built from two files.
- beta.14: the 14 old tests were updated to the current version; the whole suite passes. They
  found no bugs in the code: the expectations changed (schema 6, new settings pages, achievement
  catalog 1.0).
- beta.15: the Changelog page shows only changes of the add-on itself. Notes about tests,
  documentation and the build moved to a "Development" section (not shown in the game), versions
  without add-on changes are hidden; a test keeps technical words out of the game.
- beta.16: in History, another character's playtime card shows its saved /played ("Total
  playtime"), not the addon's count. Bug found by Viktor in the game from screenshots;
  the fix is checked in the game.
- beta.17: All characters shows the same time as the character cards (/played), the total is
  their sum; without a saved /played the time is marked "(addon)".
- beta.18: Viktor's idea: "ladder" achievements are joined into 24 chains (54 cards instead of 106
  rows), a card unfolds on click and shows every step; a progress dashboard by category and
  rarity; a pin moves to the next step. Saved data did not change.

## Check in Forever
- Achievements (beta.18): the dashboard fits and does not overlap the list; a category click
  scrolls; a chain card unfolds and folds; the step dots show next to the title; "Completed" and
  "In progress"; "Next: …" in chat after a new achievement.
- All characters (beta.17): the time in the rows matches the character cards, "(addon)" where
  there is no /played; the note at the bottom fits.
- Mini notification (beta.12): the dark background does not stick out of the frame, no gaps
  before the gold line.
- Notifications (beta.10–11): "Preview" / "Hide", the "Edit" panel, "x" inside the frame.
- History (beta.10): the character list, going back to your own character.
- The full checklist: [docs/TESTING.en.md](docs/TESTING.en.md).

## Before 1.0.0
1. Go through the checklist in the client and fix what turns up.
2. Final art for the discovery and legendary notification frames (temporary now, from
   `tools/make_borders.py`).
3. Release 1.0.0: zip with the right root folder, README, CHANGELOG.

## Development rules
- Work in stages; SemVer; Conventional Commits; after each stage update CHANGELOG.md,
  CHANGELOG.en.md and this file (both languages), then run `lua5.1 tools/changelog.lua`.
- A feature does not count as working until it is checked in the Forever client.
- Never invent client API: everything unconfirmed goes to [docs/TESTING.en.md](docs/TESTING.en.md), §3.
- KISS, DRY, YAGNI.
