-- tests/run.lua
-- Offline tests with a fake client. Run from the addon root:
--   lua5.1 tests/run.lua
-- IDs in names refer to TESTING.md. Passing here does not mean the game
-- client behaves the same way: client checks are listed in TESTING.md.
package.path = "./tests/?.lua;" .. package.path
local Mock = require("mock_wow")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n     " .. tostring(err))
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function start(options)
    local env = Mock.new(options)
    local ns = env.login(".")
    return env, ns
end

local function last(ns)
    return ns.db.journal[#ns.db.journal]
end

local function levelUp(env, level)
    env.level = level
    env.fire("PLAYER_LEVEL_UP", level)
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
test("T01 fresh install: defaults, no errors", function()
    local _, ns = start()
    eq(ns.db.schemaVersion, 2, "schema")
    eq(ns.db.settings.enabled, true, "enabled")
    eq(ns.Profiles.ActiveName(), "Adventurer", "profile")
    eq(#ns.Logger.Recent(200) > 0, true, "log has entries")
    for _, entry in ipairs(ns.Logger.Recent(200)) do
        eq(entry.level ~= "ERROR", true, "no errors: " .. entry.msg)
    end
end)

test("migration v1 (spike) -> v2 keeps nothing of the spike", function()
    local _, ns = start({ savedDB = { schemaVersion = 1, spike = { loadCount = 5, shots = {} } } })
    eq(ns.db.schemaVersion, 2, "schema")
    eq(ns.db.spike, nil, "spike removed")
end)

test("T24 corrupted configuration is repaired", function()
    local _, ns = start({ savedDB = {
        schemaVersion = 2, settings = { enabled = "yes", scale = 9, locale = "xx", bogus = 1 },
        profiles = { Bad = 5, Good = { rules = 3 } }, characters = 7,
        journal = { { id = 1, t = 1 }, "junk", { id = "x" } }, extraKey = true,
    } })
    eq(ns.db.settings.enabled, true, "enabled")
    eq(ns.db.settings.scale, 1, "scale")
    eq(ns.db.settings.locale, "auto", "locale")
    eq(ns.db.settings.bogus, nil, "unknown setting removed")
    eq(ns.db.profiles.Bad, nil, "bad profile removed")
    eq(type(ns.db.profiles.Good.rules), "table", "rules repaired")
    eq(#ns.db.journal, 1, "invalid journal entries removed")
    eq(ns.db.nextJournalId, 2, "next id")
    eq(ns.db.extraKey, nil, "unknown key removed")
end)

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
test("Adventurer matches the spec table", function()
    local _, ns = start()
    local rules = ns.Profiles.Current().rules
    eq(rules.LEVEL.enabled, true) eq(rules.LEVEL.frames, 2) eq(rules.LEVEL.mode, "clean")
    eq(rules.MAX_LEVEL.priority, 1) eq(rules.ZONE.delay, 2) eq(rules.BOSS.mode, "normal")
    eq(rules.DEATH.enabled, false) eq(rules.MANUAL.priority, 0)
end)

test("editing a preset creates Custom, presets stay unchanged", function()
    local _, ns = start()
    ns.Profiles.SetRule("LEVEL", "frames", 4)
    eq(ns.Profiles.ActiveName(), "Custom", "switched")
    eq(ns.Profiles.Current().rules.LEVEL.frames, 4, "custom value")
    eq(ns.Profiles.Resolve("Adventurer").rules.LEVEL.frames, 2, "preset untouched")
end)

test("character override, rename and delete keep references valid", function()
    local _, ns = start()
    assert(ns.Profiles.Copy("Explorer", "Mine"))
    ns.Profiles.SetActive("Mine", true)
    eq(ns.Profiles.ActiveName(), "Mine", "override")
    assert(ns.Profiles.Rename("Mine", "Ours"))
    eq(ns.Profiles.ActiveName(), "Ours", "renamed reference")
    assert(ns.Profiles.Delete("Ours"))
    eq(ns.Profiles.ActiveName(), "Adventurer", "fallback after delete")
    eq((ns.Profiles.Delete("Explorer")), false, "preset delete refused")
end)

test("unsupported triggers are never enabled (Archivist)", function()
    local _, ns = start()
    ns.Profiles.SetActive("Archivist")
    local rules = ns.Profiles.Current().rules
    eq(rules.DEATH.enabled, true, "supported on")
    eq(rules.RARE.enabled, false, "RARE off")
    eq(rules.BG.enabled, false, "BG off")
end)

---------------------------------------------------------------------------
-- Capture flow
---------------------------------------------------------------------------
test("T03 new level: 2 clean frames, UI hidden for the shot and restored", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(10)
    local entry = last(ns)
    eq(entry.events[1], "LEVEL", "event")
    eq(entry.status, "success", "status")
    eq(entry.ok, 2, "frames")
    eq(entry.modeActual, "clean", "mode")
    eq(env.uiShownAtShot, false, "UI hidden during shot")
    eq(UIParent:IsShown(), true, "UI restored")
end)

test("T04 disabled event: no automatic shot", function()
    local env, ns = start()
    ns.Profiles.SetRule("LEVEL", "enabled", false)
    levelUp(env, 11)
    env.advance(10)
    eq(env.screenshotCalls, 0, "no calls")
end)

test("T05 same key within cooldown: one request", function()
    local env, ns = start()
    levelUp(env, 11)
    levelUp(env, 11)
    env.advance(10)
    eq(#ns.db.journal, 1, "one record")
end)

test("T06 level and max level at once: only MAX_LEVEL", function()
    local env, ns = start()
    levelUp(env, 60)
    env.advance(15)
    eq(#ns.db.journal, 1, "one record")
    eq(last(ns).events[1], "MAX_LEVEL", "event")
    eq(last(ns).ok, 3, "3 frames")
end)

test("T07 compatible events merge: one request, all reasons", function()
    local env, ns = start()
    ns.Events.Emit("BOSS", "boss:1:1")
    ns.Events.Emit("MOUNT", "mount:5")
    env.advance(10)
    eq(#ns.db.journal, 1, "one record")
    eq(#last(ns).events, 2, "both reasons")
end)

test("T08 incompatible modes are not merged", function()
    local env, ns = start()
    ns.Events.Emit("BOSS", "boss:1:1")   -- normal
    levelUp(env, 11)                      -- clean
    env.advance(20)
    eq(#ns.db.journal, 2, "two records")
end)

test("T09 full queue: bounded, least important dropped and logged", function()
    local env, ns = start()
    env.screenshotMode = "silent"
    ns.Profiles.SetRule("DEATH", "enabled", true)
    ns.Profiles.SetRule("DEATH", "delay", 10)
    for i = 1, 30 do
        ns.Events.Emit("DEATH", "death:" .. i)
        env.advance(0.6) -- outside the merge window
    end
    eq(ns.Queue.Size() <= 20, true, "bounded")
    local skipped = 0
    for _, e in ipairs(ns.db.journal) do
        if e.skipReason == "queue_full" then skipped = skipped + 1 end
    end
    eq(skipped >= 5, true, "drops recorded")
end)

test("T10 expired TTL: no stale shot", function()
    local env, ns = start()
    env.fire("PLAYER_LEAVING_WORLD")
    ns.Events.Emit("BOSS", "boss:9:1")
    env.advance(30)
    env.fire("PLAYER_ENTERING_WORLD")
    env.advance(5)
    eq(env.screenshotCalls, 0, "no call")
end)

test("T11 combat before clean: normal fallback, UI not hidden", function()
    local env, ns = start()
    env.combat = true
    levelUp(env, 11)
    env.advance(10)
    eq(last(ns).modeActual, "normal", "fallback")
    eq(env.uiShownAtShot, true, "UI visible")
end)

test("T12 combat starts while preparing clean: UI restored at once", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(0.21) -- delay passed, UI hidden, waiting to settle
    eq(UIParent:IsShown(), false, "hidden while preparing")
    env.fire("PLAYER_REGEN_DISABLED")
    env.combat = true
    eq(UIParent:IsShown(), true, "restored on combat")
    env.advance(10)
    eq(UIParent:IsShown(), true, "still shown")
end)

test("T13 loading screen: active request cancelled, queue cleared", function()
    local env, ns = start()
    ns.Events.Emit("BOSS", "boss:1:1")
    env.fire("PLAYER_LEAVING_WORLD")
    env.advance(5)
    eq(env.screenshotCalls, 0, "no call")
    eq(last(ns).skipReason, "loading", "reason")
end)

test("T14 Screenshot error: recorded, UI restored", function()
    local env, ns = start({ screenshotMode = "error" })
    levelUp(env, 11)
    env.advance(10)
    eq(last(ns).status, "failed", "status")
    eq(UIParent:IsShown(), true, "UI restored")
end)

test("T15 no result: timeout, unconfirmed, no retry", function()
    local env, ns = start({ screenshotMode = "silent" })
    levelUp(env, 11)
    env.advance(20)
    eq(last(ns).status, "unconfirmed", "status")
    eq(env.screenshotCalls, 1, "series stopped, no retry")
    eq(UIParent:IsShown(), true, "UI restored")
end)

test("T16 late result does not change a new request", function()
    local env, ns = start({ screenshotMode = "silent" })
    ns.Engine.SubmitManual()
    env.advance(6)
    env.fire("SCREENSHOT_SUCCEEDED") -- late
    eq(last(ns).status, "unconfirmed", "unchanged")
    eq(ns.Engine.Session().unattributed, 1, "counted as not ours")
end)

test("T17 dual series: alternating frames, UI restored between", function()
    local env, ns = start()
    ns.Profiles.SetRule("BOSS", "mode", "dual")
    ns.Profiles.SetRule("BOSS", "frames", 2)
    ns.Events.Emit("BOSS", "boss:2:1")
    env.advance(20)
    eq(last(ns).ok, 4, "2 cycles x 2 frames")
    eq(last(ns).modeActual, "clean+normal", "both modes")
end)

test("T18 UI hidden by the player stays hidden", function()
    local env, ns = start()
    UIParent:Hide()
    levelUp(env, 11)
    env.advance(10)
    eq(UIParent:IsShown(), false, "not shown by addon")
end)

test("T19 pause: queued automatic shots removed", function()
    local env, ns = start()
    ns.Events.Emit("BOSS", "boss:1:1")
    ns.Engine.SetEnabled(false)
    env.advance(10)
    eq(env.screenshotCalls, 0, "no call")
    ns.Events.Emit("BOSS", "boss:3:1")
    env.advance(10)
    eq(env.screenshotCalls, 0, "still none")
end)

test("T20 manual shot works while paused", function()
    local env, ns = start()
    ns.Engine.SetEnabled(false)
    ns.Engine.ManualShot()
    env.advance(2)
    eq(last(ns).status, "success", "manual ok")
end)

test("manual timer counts down and can be cancelled", function()
    local env, ns = start()
    ns.db.settings.manualTimer = 3
    ns.Engine.ManualShot()
    env.advance(1)
    eq(ns.Engine.CancelCountdown(), true, "cancelled")
    env.advance(5)
    eq(env.screenshotCalls, 0, "no call")
    ns.Engine.ManualShot()
    env.advance(4)
    eq(env.screenshotCalls, 1, "taken after timer")
end)

test("T21 journey skipped while AFK or in combat, taken otherwise", function()
    local env, ns = start()
    ns.Profiles.SetRule("JOURNEY", "enabled", true)
    ns.Profiles.SetJourney("interval", 5)
    env.afk = true
    env.advance(400)
    eq(env.screenshotCalls, 0, "AFK: none")
    env.afk = false
    env.combat = true
    env.advance(60)
    eq(env.screenshotCalls, 0, "combat: none")
    env.combat = false
    env.advance(60)
    eq(env.screenshotCalls, 1, "taken")
    eq(last(ns).events[1], "JOURNEY", "journey record")
end)

test("T22 limit reached: automatic calls stop", function()
    local env, ns = start()
    ns.Profiles.SetLimit("perHour", 1)
    ns.Profiles.SetRule("DEATH", "enabled", true)
    ns.Events.Emit("DEATH", "death:1")
    env.advance(5)
    ns.Events.Emit("DEATH", "death:2")
    env.advance(5)
    eq(env.screenshotCalls, 1, "one call")
end)

test("T23 reload keeps data; characters are isolated", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(10)
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    _G.UnitName = function() return "Other" end
    local ns2 = env2.login(".")
    eq(#ns2.db.journal, 1, "journal kept")
    eq(ns2.characterKey, "Forever:Other", "other character")
    eq(ns2.db.characters["Forever:Nedisan"] ~= nil, true, "first character kept")
end)

test("T25 journal limit, favorites protected", function()
    local _, ns = start()
    local journal = {}
    for i = 1, 30 do journal[i] = { id = i, t = i, events = {}, fav = (i <= 5) or nil } end
    ns.Journal.Trim(journal, 20, 10)
    eq(#journal, 20, "trimmed")
    eq(journal[1].id, 1, "favorite kept")
    eq(journal[6].id, 16, "oldest normal removed")
end)

test("T26 unknown client event: trigger unavailable, no Lua error", function()
    local _, ns = start({ unknownEvents = { NEW_MOUNT_ADDED = true } })
    eq(ns.Registry.IsAvailable("MOUNT"), false, "MOUNT unavailable")
    eq(ns.Profiles.Current().rules.MOUNT.enabled, false, "forced off")
    eq(ns.Registry.IsAvailable("LEVEL"), true, "LEVEL fine")
end)

test("T28 Print Screen is counted, never attributed", function()
    local env, ns = start()
    env.fire("SCREENSHOT_STARTED")
    env.fire("SCREENSHOT_SUCCEEDED")
    eq(#ns.db.journal, 0, "no record")
    eq(ns.db.counters.unattributed, 1, "counted")
end)

test("T29 long session: bounded timers and queue", function()
    local env, ns = start()
    ns.Profiles.SetRule("JOURNEY", "enabled", true)
    ns.Profiles.SetRule("RANDOM", "enabled", true)
    for _ = 1, 240 do env.advance(30) end -- 2 hours
    eq(env.tickers, 1, "one ticker")
    eq(#env.timers < 10, true, "few pending timers: " .. #env.timers)
    eq(ns.Queue.Size(), 0, "empty queue")
end)

test("T30 deleting a record touches only the journal", function()
    local env, ns = start()
    ns.Engine.SubmitManual()
    env.advance(2)
    local id = last(ns).id
    eq(ns.Journal.Delete(id), true, "deleted")
    eq(#ns.db.journal, 0, "gone")
end)

---------------------------------------------------------------------------
-- Event parsing
---------------------------------------------------------------------------
test("own epic and legendary loot from chat text", function()
    local env, ns = start()
    env.fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ4:|Hitem:19019::|h[Thunderfury]|h|r.")
    env.advance(5)
    eq(last(ns).events[1], "LOOT_EPIC", "epic")
    env.fire("CHAT_MSG_LOOT", "You receive loot: |cffff8000|Hitem:17182::|h[Sulfuras]|h|r.")
    env.advance(5)
    eq(last(ns).events[1], "LOOT_LEGENDARY", "legendary (not epic)")
    env.fire("CHAT_MSG_LOOT", "Bob receives loot: |cnIQ4:|Hitem:1::|h[X]|h|r.")
    env.advance(5)
    eq(#ns.db.journal, 2, "other players ignored")
end)

test("duel win detected, loss ignored", function()
    local env, ns = start()
    ns.Profiles.SetRule("DUEL", "enabled", true)
    env.fire("CHAT_MSG_SYSTEM", "Bob has defeated Nedisan in a duel")
    env.advance(5)
    eq(#ns.db.journal, 0, "loss ignored")
    env.fire("CHAT_MSG_SYSTEM", "Nedisan has defeated Bob in a duel")
    env.advance(5)
    eq(last(ns).events[1], "DUEL", "win")
end)

test("first zone visit: login zone seeded, new zone captured once", function()
    local env, ns = start()
    env.advance(5)
    eq(#ns.db.journal, 0, "login zone not captured")
    env.mapID, env.zone = 12, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(10)
    eq(last(ns).events[1], "ZONE", "new zone")
    env.mapID = 37
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.mapID = 12
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(10)
    eq(#ns.db.journal, 1, "visited zones ignored")
end)

test("quest, guild and druid form triggers", function()
    local env, ns = start()
    for _, id in ipairs({ "QUEST", "GUILD", "FORM" }) do ns.Profiles.SetRule(id, "enabled", true) end
    ns.character.quests[42] = true
    env.fire("QUEST_TURNED_IN", 41) env.fire("QUEST_TURNED_IN", 42)
    env.advance(5)
    env.inGuild = true env.fire("PLAYER_GUILD_UPDATE")
    env.advance(5)
    env.forms = 3 env.fire("UPDATE_SHAPESHIFT_FORMS")
    env.advance(5)
    local kinds = {}
    for _, e in ipairs(ns.db.journal) do kinds[#kinds + 1] = e.events[1] end
    eq(table.concat(kinds, ","), "QUEST,GUILD,FORM", "events")
end)

---------------------------------------------------------------------------
-- UI and commands (smoke tests: build every widget, click buttons)
---------------------------------------------------------------------------
test("window: every tab builds and refreshes", function()
    local env, ns = start()
    ns.Engine.SubmitManual()
    env.advance(2)
    for _, tab in ipairs(ns.UI.TABS) do
        ns.UI.Open(tab)
    end
    eq(ForeverMemoriesMainFrame:IsShown(), true, "window shown")
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and frame.scripts.OnClick and frame.text ~= "" then
            -- harmless buttons only
            if frame.text == ns.L.TAKE_SHOT or frame.text == ns.L.TEST_SHOT or frame.text == ">" then
                frame:Click()
            end
        end
    end
    env.advance(5)
    for _, entry in ipairs(ns.Logger.Recent(200)) do
        eq(entry.level ~= "ERROR", true, "no errors: " .. entry.msg)
    end
end)

test("window is hidden during a shot and shown again", function()
    local env, ns = start()
    ns.UI.Open("home")
    local shown
    local original = _G.Screenshot
    _G.Screenshot = function() shown = ForeverMemoriesMainFrame:IsShown() original() end
    ns.Engine.SubmitManual()
    env.advance(2)
    eq(shown, false, "hidden at shot")
    eq(ForeverMemoriesMainFrame:IsShown(), true, "back")
end)

test("first run, minimap, manual panel, settings and journal actions", function()
    local env, ns = start()
    env.autoConfirm = true
    env.advance(6)
    eq(ForeverMemoriesFirstRun:IsShown(), true, "first run shown")
    ForeverMemoriesMinimapButton.scripts.OnEnter(ForeverMemoriesMinimapButton)
    ForeverMemoriesMinimapButton:Click("RightButton")
    eq(ns.db.settings.enabled, false, "paused by right click")
    ForeverMemoriesMinimapButton:Click("MiddleButton")
    env.advance(2)
    eq(last(ns).manual, true, "manual by middle click")
    ns.ManualPanel.Toggle()
    eq(ForeverMemoriesManualPanel:IsShown(), true, "panel")
    ns.Journal.Update(last(ns).id, { note = "hi", fav = true })
    eq(last(ns).note, "hi", "note")
    ForeverMemories_OnAddonCompartmentClick()
    ForeverMemories_ManualShot()
    env.advance(2)
end)

-- Finds a shown button by its text (dropdown buttons show the current option).
local function findButton(env, text)
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and frame.text == text and frame.scripts.OnClick then
            return frame
        end
    end
end

test("dropdown opens a list, a pick saves the value and closes the list", function()
    local env, ns = start()
    ns.UI.Open("capture")
    local button = assert(findButton(env, ns.L.TIMER_OFF), "timer dropdown")
    button:Click()
    local list = ForeverMemoriesDropdownList
    eq(list:IsShown(), true, "list open")
    eq(list.rows[4]:IsShown(), true, "4 options")
    eq(list.rows[3].text:GetText(), "5 s", "option text")
    list.rows[3]:Click()
    eq(list:IsShown(), false, "closed after pick")
    eq(ns.db.settings.manualTimer, 5, "saved in SavedVariables table")
    eq(button.text, "5 s", "button shows the new value")
    button:Click()
    button:Click()
    eq(list:IsShown(), false, "second click closes")
    button:Click()
    list.catcher:Click()
    eq(list:IsShown(), false, "click outside closes")
end)

test("profile and rule mode dropdowns save through Profiles", function()
    local env, ns = start()
    ns.UI.Open("home")
    findButton(env, ns.L.PRESET_Adventurer):Click()
    local list = ForeverMemoriesDropdownList
    local target
    for i, row in ipairs(list.rows) do
        if row:IsShown() and row.value == "Explorer" then target = row end
    end
    assert(target, "Explorer listed"):Click()
    eq(ns.Profiles.ActiveName(), "Explorer", "profile switched")
end)

test("language: saved at once, reload only after consent", function()
    local env, ns = start()
    ns.UI.Open("settings")
    local button = assert(findButton(env, ns.L.LANG_AUTO), "language dropdown")
    -- "No": the choice stays saved, nothing reloads.
    button:Click()
    ForeverMemoriesDropdownList.rows[2]:Click() -- Русский
    eq(ns.db.settings.locale, "ruRU", "saved")
    eq(#env.popups, 1, "asked")
    eq(env.popups[1], ns.L.CONFIRM_RELOAD_LANGUAGE, "reload question")
    eq(env.reloads, 0, "no reload without consent")
    -- "Yes": reload.
    env.autoConfirm = true
    button:Click()
    ForeverMemoriesDropdownList.rows[1]:Click() -- auto (= enUS here, already shown)
    eq(#env.popups, 1, "no question when the visible language does not change")
    button:Click()
    ForeverMemoriesDropdownList.rows[2]:Click()
    eq(env.reloads, 1, "reloaded after consent")
    -- After the reload the saved language is used.
    local env2, ns2 = start({ savedDB = ns.db })
    eq(ns2.L.TAKE_SHOT, "Сделать кадр", "russian after reload")
end)

test("slash commands", function()
    local env, ns = start()
    for _, cmd in ipairs({ "", "on", "off", "toggle", "shot", "status", "debug", "log", "ui",
                           "panel", "quest add 5", "quest remove 5", "quest", "nonsense" }) do
        SlashCmdList.FOREVERMEMORIES(cmd)
    end
    env.advance(3)
    for _, entry in ipairs(ns.Logger.Recent(200)) do
        eq(entry.level ~= "ERROR", true, "no errors: " .. entry.msg)
    end
end)

test("ruRU locale is complete and used", function()
    local _, ns = start({ locale = "ruRU" })
    eq(ns.L.TAKE_SHOT, "Сделать кадр", "russian")
    for key in pairs(ns.locales.enUS) do
        eq(ns.locales.ruRU[key] ~= nil, true, "ruRU missing " .. key)
    end
    for key in pairs(ns.locales.ruRU) do
        eq(ns.locales.enUS[key] ~= nil, true, "enUS missing " .. key)
    end
end)

test("every L.KEY used in code exists in enUS", function()
    local _, ns = start()
    local files = io.popen("find Core Capture Modules UI -name '*.lua'")
    for path in files:lines() do
        local source = assert(io.open(path)):read("*a")
        for key in source:gmatch("[^%w_]L%.([A-Z][%w_]+)") do
            eq(ns.locales.enUS[key] ~= nil, true, path .. ": " .. key)
        end
    end
    files:close()
    local families = { TRIGGER_ = {}, TAB_ = ns.UI.TABS, STATUS_ = { "success", "partial", "unconfirmed", "failed", "skipped" },
                       MODE_ = { "normal", "clean", "dual" }, PRESET_ = ns.Profiles.PRESET_ORDER,
                       REASON_ = { "disabled", "paused", "not_first", "cooldown", "unknown_trigger", "limit_session",
                                   "limit_hour", "limit_journey", "queue_full", "expired", "loading", "timeout", "not_loaded" } }
    for _, t in ipairs(ns.Registry.TRIGGERS) do table.insert(families.TRIGGER_, t.id) end
    for prefix, list in pairs(families) do
        for _, suffix in ipairs(list) do
            eq(ns.locales.enUS[prefix .. suffix] ~= nil, true, prefix .. suffix)
        end
    end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
