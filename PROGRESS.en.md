# Progress

**English** · [Русский](PROGRESS.md)

Current version: **1.0.0-beta.14** (2026-11-25). Built, tests 54/54 and 110/110, checked in the
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

## Check in Forever
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
