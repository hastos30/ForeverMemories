-- Modules/ProjectInfo.lua
-- Facts for Settings / About (v0.10.0). Only confirmed values go here:
-- nil hides the line or link in the window. Nothing is guessed: no
-- license, repository, CurseForge page, Discord server or donation page
-- until the author confirms it. The author and the copyright are from
-- the approved Settings specification (v1.0.0-beta.4).
local _, ns = ...

ns.ProjectInfo = {
    author = "Nedisan",
    copyright = "© 2026 Nedisan",
    license = nil,  -- e.g. "MIT"; hidden while nil (LICENSE file needed)
    thanks = nil,   -- e.g. "Testers: ..."; hidden while nil
    game = "World of Warcraft: Forever",
    languages = "English, Русский",
    -- Community and support: shown only when set. The game cannot open a
    -- browser, so a click shows the address in a copy box.
    links = {
        { id = "GITHUB", url = nil },
        { id = "CURSEFORGE", url = nil },
        { id = "DISCORD", url = nil },
        { id = "REPORT_BUG", url = nil },
        { id = "SUGGEST_FEATURE", url = nil },
        { id = "SUPPORT_AUTHOR", url = nil },
    },
}
