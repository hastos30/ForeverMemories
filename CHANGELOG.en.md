# Changelog

**English** · [Русский](CHANGELOG.md)

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions: [SemVer](https://semver.org/).
Both files (this one and CHANGELOG.md) feed the in-game Changelog page: `lua5.1 tools/changelog.lua`.

## [1.0.0-beta.14] — 2026-11-25 — All tests match the current version

### Improved
- The full offline test suite (110) is updated to the current version and passes in full: data schema 6, the new settings pages, achievement catalog 1.0, notifications per kind.
- The release build (tools/release.sh) runs both test suites.

## [1.0.0-beta.13] — 2026-11-25 — Tidy documentation

### Improved
- Documentation in two languages: README, changelog, progress, architecture and testing are in English and Russian.
- The English changelog is now its own file and reaches the Changelog page the same way as the Russian one.

### Removed
- Outdated specs, the work plan and the 0.5 design notes; what is current lives in docs/ARCHITECTURE.en.md and docs/TESTING.en.md.

## [1.0.0-beta.12] — 2026-11-25 — Mini notification background fits the frame

### Fixed
- Mini notification: the dark background follows the frame shape, reaching the gold lines and no longer sticking out past the rounded ends.

## [1.0.0-beta.11] — 2026-11-25 — A tidy mini notification

### Fixed
- Mini notification: the title and the text sit in the middle between the gold lines and stay clear of the "x".
- The "x" of every notification is a plain mark inside the frame, with no square over the gold line; it turns gold under the mouse.

## [1.0.0-beta.10] — 2026-11-25 — Own settings for each notification, character picker

### Improved
- Notifications: the place on screen (top / middle / bottom) and the size (small / normal / large) are now in the "Edit" panel of each kind. The sample moves and resizes at once; "Done" saves.
- "Preview" is a toggle: a second press hides the sample, and the button reads "Hide" meanwhile.
- Kinds of notifications are tidy cards: on/off and the name, "Preview" and "Edit" on the first line, the time on screen on the second.
- History: one list instead of the "Character / All characters" buttons and the "Back to my character" link: your character (first, marked "Current"), the others, "All characters". Choose yourself to go back.

### Fixed
- Character list: no stray " -" after the name when the realm is unknown.

## [1.0.0-beta.9] — 2026-11-25 — Notifications: everything in one place

### Improved
- Settings / Notifications: an "All notifications" block on top with show, sound, wait for the end of combat, merge repeats, place and size. Choosing a place or a size applies to all kinds at once and clears their own places.
- The "Edit" button of each kind: the panel with the scale and "Lock" opens right under the sample notification and follows it while it is dragged (above it near the bottom of the screen). The panel is opaque.
- The Discovery and Legendary notifications have cut corners.

### Fixed
- Mini notification: the icon has no second frame and sits in its slot; the dark background stays inside the gold line.
- Home in a narrow window: goals show a percent instead of "19,850 / 36,000", and "Nearest" no longer runs into the number.
- Settings in a narrow window: the row of menu icons no longer touches the page caption; the language list no longer covers its note.

## [1.0.0-beta.8] — 2026-11-25 — Own art across the window

### Improved
- Icons on the main tabs (Home, Auto capture, History, Settings); a narrow window shows the names only.
- The addon's own icons instead of game icons: Home and Overview cards, Records, the Settings menu, Auto capture groups and modes, passive shots and new zones in the screenshot list, Chronicle.
- Gold window corners and a compass on the footer line.
- Achievements: larger medallions; earned ones in color with the frame of their rarity, the others grey.
- Chronicle: an entry takes two lines (title and time, then details), so almost twice as many fit.
- Auto capture: a group has "Enable all" / "Disable all" instead of "All / None".
- Steps and play time charts: a day without activity shows "—", not "0".

### Fixed
- Numbers in Records, the Data cards and the day summary use the Inter font, so "10" no longer looks like "ıo".
- Appearance: the "Illustrated" label fits its button.

## [1.0.0-beta.7] — 2026-11-25 — Week on Home, achievement counts, Russian zones

### Added
- Home: "This week" with screenshots, steps, locations, active play and new locations since Monday; a click opens History / Overview. It sits next to "Last adventure".
- Achievements: "X / Y earned · X / Y available", of all and of those that can be earned in Forever.
- Russian zone names (48 from the zone catalog) when the addon speaks Russian and the game is in English. The location search finds both the Russian and the English name. Saved data does not change.

### Improved
- The "View screenshot history" link is now to the right of the "Latest screenshots" heading.

## [1.0.0-beta.6] — 2026-11-25 — Notifications: time, pause, own place

### Added
- Its own time on screen for each kind: mini 3, 5 or 10 s (the earlier choice is kept), discovery 10, 15 or 20 s (15 by default), legendary 7, 10 or 15 s (10 by default).
- The mouse over a notification pauses it; the "x" button closes it at once.
- "Position…" for each kind: a sample stays on screen to be dragged with the mouse, scaled, locked or reset to the common place; "Done" saves, "Cancel" and leaving the page do not. While the editor is open, real notifications wait.
- "Wait for the end of combat": a legendary card waits until the fight is over (can be turned off); a discovery card always waits.

### Improved
- Shorter kind names: Mini, Discovery, Legendary (details in the tooltip).
- "Restore default settings" on the Notifications page also resets the own places of the kinds.

## [1.0.0-beta.5] — 2026-11-25 — A window of any size

### Added
- The window can be made as small as 440×600. The layout follows the width by itself: compact (below 520), standard, wide (from 780).
- A page that does not fit the height scrolls with the mouse wheel and a bar on the right (Home and the Settings pages).
- In a wide window the History menu shows the names of the sections next to the icons.

### Improved
- Compact window: the Settings menu is a row of icons above the page, the Data cards are in two columns, the date boxes and switches in History are narrower, the header keeps only the colored status dot.
- Lists get shorter in a low window, but never below 120 points.

## [1.0.0-beta.4] — 2026-11-25 — Settings by the prototype

### Added
- A side menu in Settings: General, Appearance, Notifications, Data, About, Changelog. A normal window shows icons (the name is in the tooltip), a wide window shows icons with names. Every page has an "Adventurer's Journal" header with its title and subtitle.
- General: language, minimap button, remember the last tab, what the minimap button clicks do, the assigned key bindings ("Not assigned" when there is no key) and "Open game key bindings".
- Appearance: scale, the current window layout (shown only), separate "Reset scale" and "Reset window size and position", "Classic / Illustrated" zone pictures with the ArtPack state, "Interface animations" (notifications fade in) and "Reset appearance".
- Data: "Reset all settings" puts every setting, Auto capture included, back to its default; history and achievements are kept.
- The /fm diag command: the diagnostics report to copy.

### Improved
- Data: four cards (characters, memories, tracked dates, unique zones), characters with class, level and the last day played, and "Export", "Create", "Import" and "Delete character history" buttons.
- About: logo, version, description, "Designed & developed by Nedisan", "© 2026 Nedisan". The technical block left the page; diagnostics are in /fm debug and /fm diag.

## [1.0.0-beta.3] — 2026-11-25 — Window resizing

### Fixed
- While the window corner is dragged, the content no longer spills outside the frame: it is clipped, and the pages are rebuilt for the new width when the mouse is released.

## [1.0.0-beta.2] — 2026-11-25 — Fixes after the first look in the game

### Improved
- The content of the window stretches with its frame (up to 1000 points, then it stays centered). Pages are rebuilt when the corner is released; the open page and sub-page stay.
- Long notes in History (playtime, records) wrap instead of ending in "…".

### Fixed
- Window corner: the size follows the mouse smoothly and no longer jumps to the default and then to the largest size.
- The scroll bar can be dragged with the mouse; a click on the bar scrolls there.
- Checkmarks sit inside their boxes: the checkboxes use the Obsidian Journal pictures.
- The Favorite star on screenshots and the pin diamond on achievements no longer look like arrows: only the icon itself is shown.
- Visit history shows the map name or "Unknown place" instead of "map:1415".

## [1.0.0-beta] — 2026-11-25 — Local beta

### Improved
- Version 1.0.0-beta. No new features: a build for testing in the client.

## [0.18.0] — 2026-11-25 — ArtPack & Trackers

### Added
- Trackers for the achievements that were waiting: taxi flights (take-off to landing), the first ride on a ground mount, joining a party and a raid, days played in a group and in a guild, dungeon and raid bosses (total and different ones), deaths, Duskwood at night by the server clock, the race's starting zone after the level cap, a return to the first zone. Only what the add-on sees from this version on counts; the state at login is a starting point, not an event.
- Optional ArtPack (a separate add-on, ForeverMemories_ArtPack): art for 51 zones on the Discovery card and on the location card in History. Without it everything works as before; Settings → Appearance shows whether it was found.
- Zone stories: a short story for 47 zones in English and Russian, on the new location card and on the zone card.
- Chronicle: milestones (screenshots, steps, hours played, gold, quests, deaths, Exalted, the first flight, mount, party and raid) and earned achievements. Three levels of entries (plain, milestones, legendary moments) and an "All / Important" switch. Milestones reached before the update create no entries.
- Records: "before: …" next to an improved record and a "Record history" section. Today's record is written down once the day is over.

### Improved
- Discovery and Legendary cards wait for the end of combat (the small card does not).
- The build also makes a second archive: ForeverMemories_ArtPack-v1.0.0.zip.

## [0.17.0] — 2026-11-25 — Settings & Notifications

### Added
- Three kinds of notifications: a small "Screenshot saved" card; "Discovery" with a compass for a new location and a common or rare achievement; "Legendary moment" with a golden frame and laurels for an epic or legendary achievement and a screenshot of a legendary item. A chat line for every earned achievement.
- Notifications come one at a time, the next ones wait (up to five). The same notification again adds "+N more" instead of a new card (can be turned off). A card on screen at the moment of a screenshot is hidden and shown again right after it.
- Settings → Notifications (a new page): the main switch, sound, each kind on its own with a "Preview" button, duration, position (top, middle, bottom), size (small, normal, large), merging, and restoring this page's defaults.
- Settings → Changelog is shown in the language of the game: this English history in an English client, the Russian one in a Russian client.

### Improved
- Settings → General became Appearance: language, scale, the Obsidian Journal fonts switch (with an offer to reload the interface), minimap button, last tab, window reset. "Restore default settings" on each page resets only that page.

## [0.16.0] — 2026-11-25 — Home, Auto Capture, History

### Added
- Home: three goal cards — your pinned achievements and the ones closest to completion. A click opens the Hall of Memories.
- Hall of Memories: the diamond button next to an achievement pins it to Home (up to three). Secret, earned and unavailable achievements cannot be pinned.
- Auto capture: a large "Auto capture is on / paused" switch with a short explanation; each capture mode shows a small picture of the screen (with and without the interface); the events are in four groups (Progress, Combat, Loot, World) that open and close, each with a counter and an "All / None" button; the passive capture timer is on this tab too.
- History → Screenshots: a "Favorite" star on every screenshot, an "All / Favorites / Important" switch (important = favorites, levels, bosses, epic and legendary items) and sorting "By location".
- Steps and Playtime: a "90 days" range (by week) next to 7 and 30 days.

### Improved
- History: sub-views are chosen from a vertical menu of icons on the left; the name is in the tooltip. Lifetime totals are shown only on Overview (and for all characters), so the other sub-views get the whole height of the window.
- Home: the location and the passive timer share one card.

## [0.15.0] — 2026-11-25 — Obsidian Journal

### Added
- Obsidian Journal look: a dark opaque background with a light texture, warm gold, parchment text and thin lines; new colors for success, warning and error.
- Cormorant Garamond (headings) and Inter (text and numbers) fonts with full Cyrillic. If the game cannot load a font, its own font is used, so text never disappears. /fm fonts turns them on and off (after /reload).
- A compass in the window header and on the minimap button; the full logo is on the About page.
- Category medallions and rarity frames for the Hall of Memories.
- The window can be resized by dragging its bottom-right corner; the size is remembered, never smaller than the default or larger than the screen. History and Settings lists grow with it.

### Improved
- "Reset window position" became "Reset window size and position"; /fm reset also restores the default size.

## [0.14.0] — 2026-11-25 — Hall of Memories

### Added
- History → Achievements became the Hall of Memories: the approved catalog 1.0 — 100 character achievements in 10 categories and 6 account achievements ("Legacy of Azeroth"). Each has a rarity, a condition, progress and the date when it is known. A "Character / Account" switch and an "earned / total" counter per category.
- Five secret achievements: only a hint is visible until they are earned.
- Four achievements are marked "Not available" with the reason (boat and zeppelin trips, full dungeon and raid clears). Achievements tracked in later versions say "Tracking comes later"; an unknown value is never shown as 0.
- New progress sources confirmed in the Forever client: the most money held, completed quests, Exalted factions and primary professions. Values only grow.

### Improved
- Saved data schema 6. The 15 achievements of 0.13.0 moved to the new IDs with their dates.
- Saved data is updated on a copy: if any total would shrink, the data stays as it was and the add-on says so in chat. A file from a newer version is never overwritten.
- Unknown fields of the saved data are no longer removed.

## [0.13.0] — 2026-11-25 — Memories & Achievements

### Added
- History → Overview → "On this day": what happened a week, a month and a year ago.
- Home → anniversary card: a week, 1, 3 and 6 months, then every year since the character's first login with ForeverMemories.
- History → Achievements: 15 achievements of ForeverMemories with progress and dates.

## [0.12.0] — 2026-11-25 — Adventure Records

### Added
- History → Records: the best day for steps, screenshots, locations and playtime, the longest session and the longest streak of days, each with its date.
- History → "Character / All characters": account totals and the list of saved characters; a click opens a character's history read-only.
- Home → "Last adventure": the last finished session; a click shows its details.

## [0.11.0] — 2026-11-25 — Location Analytics & Search

### Added
- Locations: a click on a zone opens its card — active time, days, visits, steps, screenshots, first and last visit and the latest screenshots there.
- Screenshots: search and filters (event type, location, dates, order).

### Improved
- Dropdown lists longer than 14 rows scroll with the mouse wheel.

## [0.10.0] — 2026-11-25 — Settings & Identity

### Added
- Settings are split into pages: General, Data, About and Changelog.
- Data: saved characters, statistics export, backup and import (checked, never run as code), deleting another character's history after a confirmation.
- About: the project, community links and diagnostics without personal data.
- Key bindings in the game menu (AddOns): open the window, take a screenshot, pause auto capture, clean screenshot.

### Improved
- Notifications stay 5 seconds by default (3 / 5 / 10 can be chosen); window scale 70–150 %.

## [0.9.0] — 2026-11-24 — Adventure History & World Explorer

### Added
- History became an adventure diary: Overview (Adventure Calendar, the selected day, Recap), Screenshots, Steps, Locations (World Explorer with 51 zones), Playtime and Journey.

## [0.8.3] — 2026-11-24

### Improved
- Durations of a day or more are shown with days: "5d 3h 30m".

## [0.8.2] — 2026-11-24

### Improved
- "Total playtime" comes from the game (/played); the add-on's own count is the fallback.

## [0.8.1] — 2026-11-24

### Improved
- History: "Days played" was replaced with "Total playtime".

## [0.8.0] — 2026-11-24

### Added
- Playtime tracker: active play per day, without AFK and loading screens.
- History → Locations and a lifetime dashboard.

### Improved
- Home shows today only: screenshots, steps, locations, playtime, the current location and the passive capture countdown.

## [0.7.0] — 2026-11-24

### Improved
- Home: the "Locations" card became "Total distance".

## [0.6.0] — 2026-11-24

### Added
- Passive capture: one screenshot every 15 / 30 / 45 / 60 minutes of active play.
- A chat line after every saved screenshot.

### Improved
- The window is 620×720.

## [0.5.1] — 2026-11-24

### Improved
- Step tracker: one step is 1.5 m.

## [0.5.0] — 2026-11-24 — UX Update & Step Tracker

### Added
- Step tracker, per-character statistics, the "Rare item" event, event and class icons.

### Improved
- Four tabs (Home, Auto capture, History, Settings), two capture modes and nine events.

### Removed
- Profiles, presets and many rarely used events and tools.

## [0.4.2-beta] — 2026-11-24

### Added
- Tooltips on every element of the window.

## [0.4.1-beta] — 2026-11-24

### Fixed
- Choice buttons open a list instead of cycling through the values.

## [0.4.0-beta] — 2026-11-24

### Added
- Automatic screenshots on game events, capture modes, a queue with limits, the journal, the minimap button and English and Russian.

## [0.0.1] — 2026-11-24

### Added
- The first version: a manual screenshot with /fm shot and diagnostics.
