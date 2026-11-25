-- tests/run.lua
-- Offline tests with a fake client. Run from the addon root:
--   lua5.1 tests/run.lua
-- Passing here proves our logic, not the behaviour of the real Forever
-- client: client checks are listed in docs/TESTING.md.
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

local function near(actual, expected, tolerance, what)
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected ~%s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- The fake client knows every catalog zone by its English name
-- (like an enUS Forever client), unless a test says otherwise.
local function fillAreas(env, ns)
    for _, region in ipairs(ns.ZoneCatalog.REGIONS) do
        for _, zone in ipairs(region.zones) do
            env.areaNames[zone[1]] = zone[2]
        end
    end
end

local function start(options)
    local env = Mock.new(options)
    local ns = env.loadAddon(".")
    fillAreas(env, ns)
    env.fire("ADDON_LOADED", "ForeverMemories")
    env.fire("PLAYER_LOGIN")
    env.fire("PLAYER_ENTERING_WORLD")
    return env, ns
end

local function shots(ns)
    return ns.character.shots
end

local function lastShot(ns)
    return shots(ns)[#shots(ns)]
end

local function levelUp(env, level)
    env.level = level
    env.fire("PLAYER_LEVEL_UP", level)
end

local function noErrors(ns)
    for _, entry in ipairs(ns.Logger.Recent(200)) do
        eq(entry.level ~= "ERROR", true, "no errors: " .. entry.msg)
    end
end

-- Walk in a straight line: `seconds` at `speed` yards/s along x.
local function walk(env, seconds, speed)
    env.speed = speed or 7
    local steps = math.floor(seconds / 0.1 + 0.5)
    for _ = 1, steps do
        env.world.x = env.world.x + env.speed * 0.1
        env.advance(0.1)
    end
end

-- Expected steps for a distance in yards.
local function stepsFor(yards)
    return yards * 0.9144 / 1.5
end

---------------------------------------------------------------------------
-- Data, defaults, migration
---------------------------------------------------------------------------
test("T01 fresh install: all defaults, nothing to set up", function()
    local _, ns = start()
    eq(ns.db.schemaVersion, 6, "schema")
    local s = ns.db.settings
    eq(s.enabled, true, "auto capture on")
    eq(s.mode, "normal", "normal shot")
    eq(s.notifications, true, "notifications")
    eq(s.sound, false, "sound off")
    eq(s.minimap, true, "minimap")
    eq(s.locale, "auto", "language")
    eq(s.scale, 1, "scale 100%")
    for _, id in ipairs(ns.Registry.EVENTS) do
        eq(s.events[id], true, id .. " on")
    end
    eq(#ns.Registry.EVENTS, 9, "nine events")
    eq(ns.Steps.IsRunning(), true, "step tracker on")
    noErrors(ns)
end)

local function oldDB()
    return {
        schemaVersion = 2,
        settings = { enabled = false, locale = "ruRU", sound = true, scale = 1.4, minimap = false,
                     defaultProfile = "Custom", advanced = true, manualTimer = 5, cleanAllowed = true },
        profiles = { Custom = { base = "Adventurer", rules = { DEATH = { enabled = false }, MOUNT = { enabled = true },
                                                             LEVEL = { frames = 4 } }, limits = {}, journey = {} } },
        characters = {
            ["Forever:Nedisan"] = { visited = { ["map:37"] = true }, zonesSeeded = true, firstEvents = {}, quests = {} },
        },
        journal = {
            { id = 1, t = 1795000000, char = "Forever:Nedisan", zone = "Elwynn Forest", events = { "LEVEL" },
              keys = { "level:24" }, ok = 2, failed = 0, status = "success" },
            { id = 2, t = 1795000100, char = "Forever:Nedisan", zone = "Westfall", events = { "LOOT_EPIC" },
              keys = { "loot:1" }, ok = 0, failed = 1, status = "failed" },
            { id = 3, t = 1795000200, char = "Forever:Alt", zone = "Durotar", events = { "MAX_LEVEL" },
              keys = { "level:60" }, ok = 1, failed = 0, status = "success" },
            { id = 4, t = 1795000300, zone = "Duskwood", events = { "ZONE" }, keys = { "z" }, ok = 1, status = "success" },
            { id = 5, t = 1795000400, char = "Forever:Nedisan", zone = "Westfall", events = { "MOUNT" },
              keys = { "mount:1" }, ok = 1, failed = 0, status = "success" },
        },
        nextJournalId = 6,
        counters = { unattributed = 3 },
        ui = { point = { "CENTER", "CENTER", 10, 20 } },
    }
end

test("migration 0.4.2 -> 0.5.0 keeps history, stats and compatible settings", function()
    local _, ns = start({ savedDB = oldDB() })
    local db = ns.db
    eq(db.schemaVersion, 6, "schema")
    eq(db.settings.enabled, false, "pause kept")
    eq(db.settings.locale, "ruRU", "language kept")
    eq(db.settings.sound, true, "sound kept (it was set)")
    eq(db.settings.minimap, false, "minimap kept")
    eq(db.settings.scale, 1.4, "scale kept: inside 70-150 % (v0.10.0)")
    eq(db.settings.events.DEATH, false, "a switch changed in the custom profile is kept")
    eq(db.settings.events.LEVEL, true, "others on")
    eq(db.settings.events.MOUNT, nil, "removed event dropped")
    eq(db.settings.advanced, nil, "old settings removed")
    eq(db.profiles, nil, "profiles removed")
    eq(db.journal, nil, "journal moved")
    local me = db.characters["Forever:Nedisan"]
    eq(#me.shots, 2, "only saved shots of this character")
    eq(me.shots[1].ev, "LEVEL", "event") eq(me.shots[1].info, 24, "level number")
    eq(me.shots[2].ev, "MOUNT", "old event type kept for history")
    eq(me.shotsTotal, 2, "total") eq(me.visited["map:37"], true, "visited zones kept")
    local alt = db.characters["Forever:Alt"]
    eq(#alt.shots, 1, "other character separate") eq(alt.shots[1].ev, "LEVEL", "max level -> level")
    eq(alt.shots[1].info, 60, "max level number")
    eq(#db.legacy, 1, "record without a character is not given to anyone")
    eq(db.counters.unattributed, 3, "counters kept")
    eq(db.ui.point[3], 10, "window position kept")
    eq(me.steps.total, 0, "no invented steps before the tracker existed")
    noErrors(ns)
end)

test("migration 0.5.0 -> 0.5.1: steps converted to the 1.5 m step, once", function()
    local saved = { schemaVersion = 3, settings = {}, characters = {
        ["Forever:Nedisan"] = { shots = {}, steps = { total = 1000, days = { ["2026-11-24"] = 400 } } } } }
    local _, ns = start({ savedDB = saved })
    local steps = ns.db.characters["Forever:Nedisan"].steps
    eq(steps.total, 500, "total halved") eq(steps.days["2026-11-24"], 200, "day halved")
    local _, ns2 = start({ savedDB = ns.db })
    eq(ns2.db.characters["Forever:Nedisan"].steps.total, 500, "not converted twice")
end)

test("one step = 1.5 m: a 1.5 m tap of W adds one step", function()
    local _, ns = start()
    eq(ns.Steps.STEP_METERS, 1.5, "step length")
    near(ns.Steps.YardsToSteps(1.5 / 0.9144), 1, 0.0001, "1.5 m")
end)

test("migration runs once: loading again does not duplicate records", function()
    local _, ns = start({ savedDB = oldDB() })
    local saved = ns.db
    local _, ns2 = start({ savedDB = saved })
    eq(#ns2.db.characters["Forever:Nedisan"].shots, 2, "same records")
    eq(ns2.db.characters["Forever:Nedisan"].shotsTotal, 2, "same total")
end)

test("migration from a preset profile gives the new defaults (all on)", function()
    local db = oldDB()
    db.settings.defaultProfile = "Adventurer"
    local _, ns = start({ savedDB = db })
    for _, id in ipairs(ns.Registry.EVENTS) do
        eq(ns.db.settings.events[id], true, id)
    end
end)

test("T24 damaged data is repaired without errors", function()
    local _, ns = start({ savedDB = {
        schemaVersion = 4,
        settings = { enabled = "yes", scale = 9, locale = "xx", mode = "dual", bogus = 1, events = { LEVEL = "on", RARE = true } },
        characters = { ["Forever:Nedisan"] = { shots = { { t = 1, ev = "LEVEL" }, "junk" }, steps = { total = "x", days = { a = -1 } } },
                       [5] = {} },
        extraKey = true,
    } })
    local s = ns.db.settings
    eq(s.enabled, true, "enabled") eq(s.scale, 1, "scale") eq(s.locale, "auto", "locale")
    eq(s.mode, "normal", "mode") eq(s.bogus, nil, "unknown setting")
    eq(s.events.LEVEL, true, "event repaired") eq(s.events.RARE, nil, "unknown event removed")
    local c = ns.db.characters["Forever:Nedisan"]
    eq(#c.shots, 1, "bad records removed") eq(c.steps.total, 0, "steps total") eq(c.steps.days.a, nil, "bad day")
    eq(ns.db.extraKey, true, "unknown top-level key kept (v0.14.0: never lose data)")
end)

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------
test("T03 new level: one normal shot, counted after the game confirms it", function()
    local env, ns = start()
    levelUp(env, 11)
    eq(ns.History.Stats().total, 0, "not counted before the result")
    env.advance(5)
    eq(env.screenshotCalls, 1, "one shot")
    local record = lastShot(ns)
    eq(record.ev, "LEVEL", "event") eq(record.info, 11, "level")
    eq(ns.History.Title(record), "Reached level 11", "title")
    local s = ns.History.Stats()
    eq(s.total, 1, "total") eq(s.today, 1, "today") eq(s.zones, 1, "zones")
    eq(env.uiShownAtShot, true, "normal shot keeps the game UI")
end)

test("max level is a normal level-up, not a separate event", function()
    local env, ns = start()
    env.level = 60
    levelUp(env, 60)
    env.advance(5)
    eq(#shots(ns), 1, "one shot") eq(lastShot(ns).ev, "LEVEL", "LEVEL")
end)

test("T04 disabled event: no automatic shot", function()
    local env, ns = start()
    ns.db.settings.events.LEVEL = false
    levelUp(env, 11)
    env.advance(5)
    eq(env.screenshotCalls, 0, "no calls")
end)

test("T05 the same event twice within the window: one shot", function()
    local env, ns = start()
    env.fire("PLAYER_DEAD")
    env.advance(0.2)
    env.fire("PLAYER_DEAD")
    env.advance(5)
    eq(env.screenshotCalls, 1, "one call")
    eq(#shots(ns), 1, "one record")
end)

test("items: rare / epic / legendary by quality, one shot per item, others ignored", function()
    local env, ns = start()
    env.fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:10::|h[Blue Sword]|h|r.")
    env.advance(3)
    env.fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:11::|h[Purple Axe]|h|r.")
    env.advance(3)
    env.fire("CHAT_MSG_LOOT", "You receive item: |cffff8000|Hitem:12::|h[Orange Bow]|h|r.")
    env.advance(3)
    env.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:13::|h[Green Ring]|h|r.")
    env.fire("CHAT_MSG_LOOT", "Arthas receives loot: |cffa335ee|Hitem:14::|h[Other]|h|r.")
    env.advance(3)
    local list = shots(ns)
    eq(#list, 3, "three shots")
    eq(list[1].ev, "LOOT_RARE", "rare") eq(list[2].ev, "LOOT_EPIC", "epic") eq(list[3].ev, "LOOT_LEGENDARY", "legendary")
    eq(string.find(list[2].info, "Purple Axe", 1, true) ~= nil, true, "item kept as info")
end)

test("duel: own win only", function()
    local env, ns = start()
    env.fire("CHAT_MSG_SYSTEM", "Arthas has defeated Nedisan in a duel")
    env.advance(3)
    eq(#shots(ns), 0, "loss ignored")
    env.fire("CHAT_MSG_SYSTEM", "Nedisan has defeated Arthas in a duel")
    env.advance(3)
    eq(#shots(ns), 1, "win") eq(lastShot(ns).ev, "DUEL", "duel")
end)

test("boss: only a won encounter inside a dungeon or raid", function()
    local env, ns = start()
    env.fire("ENCOUNTER_END", 1, "World Boss", 0, 40, 1)
    env.advance(3)
    eq(#shots(ns), 0, "open world ignored")
    env.instanceType = "party"
    env.fire("ENCOUNTER_END", 2, "Van Cleef", 1, 5, 0)
    env.advance(3)
    eq(#shots(ns), 0, "wipe ignored")
    env.fire("ENCOUNTER_END", 2, "Van Cleef", 1, 5, 1)
    env.advance(3)
    eq(#shots(ns), 1, "kill") eq(lastShot(ns).info, "Van Cleef", "boss name")
end)

test("zone: login zone seeded, a new zone once, a visited zone never again", function()
    local env, ns = start()
    eq(env.screenshotCalls, 0, "login zone not captured")
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(5)
    eq(#shots(ns), 1, "new zone")
    env.mapID, env.zone = 37, "Elwynn Forest"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(5)
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(30)
    eq(#shots(ns), 1, "known zones not again")
end)

test("guild: login is not a join; a real join is", function()
    local env, ns = start()
    env.advance(40) -- grace period over: "no guild" is known
    eq(ns.character.guild, false, "not in a guild")
    env.inGuild = true
    env.fire("PLAYER_GUILD_UPDATE")
    env.advance(3)
    eq(#shots(ns), 1, "joined") eq(lastShot(ns).info, "Heroes", "guild name")
    -- Next login: the client says "no guild" for a moment, then the guild.
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    env2.inGuild = false
    local ns2 = env2.login(".")
    env2.fire("PLAYER_GUILD_UPDATE")
    env2.inGuild = true
    env2.fire("PLAYER_GUILD_UPDATE")
    env2.advance(40)
    eq(#ns2.character.shots, 1, "no new shot at login")
end)

test("clean shot: UI hidden for the shot and restored", function()
    local env, ns = start()
    ns.db.settings.mode = "clean"
    levelUp(env, 11)
    env.advance(5)
    eq(env.uiShownAtShot, false, "UI hidden during the shot")
    eq(UIParent:IsShown(), true, "UI restored")
end)

test("T11 clean shot in combat: normal fallback, UI never hidden", function()
    local env, ns = start()
    ns.db.settings.mode = "clean"
    env.combat = true
    levelUp(env, 11)
    env.advance(5)
    eq(env.uiShownAtShot, true, "UI visible") eq(#shots(ns), 1, "shot taken")
end)

test("T12 combat starts while preparing a clean shot: UI back at once", function()
    local env, ns = start()
    ns.db.settings.mode = "clean"
    levelUp(env, 11)
    env.advance(0.52) -- delay 0.5 passed, settle 0.05 not yet
    eq(UIParent:IsShown(), false, "hidden while preparing")
    env.fire("PLAYER_REGEN_DISABLED")
    eq(UIParent:IsShown(), true, "shown on combat")
    env.advance(5)
end)

test("T18 UI hidden by the player stays hidden", function()
    local env, ns = start()
    ns.db.settings.mode = "clean"
    UIParent:Hide()
    levelUp(env, 11)
    env.advance(5)
    eq(UIParent:IsShown(), false, "still hidden")
end)

test("T13 loading screen: queued shot cancelled, nothing counted", function()
    local env, ns = start()
    levelUp(env, 11)
    env.fire("PLAYER_LEAVING_WORLD")
    env.advance(5)
    eq(env.screenshotCalls, 0, "no shot during loading")
    eq(#shots(ns), 0, "nothing counted")
end)

test("T14/T15 failed or unconfirmed screenshots never increase statistics", function()
    local env, ns = start({ screenshotMode = "failed" })
    levelUp(env, 11)
    env.advance(5)
    eq(#shots(ns), 0, "failed not counted")
    env.screenshotMode = "silent"
    levelUp(env, 12)
    env.advance(10)
    eq(#shots(ns), 0, "timeout not counted")
    eq(UIParent:IsShown(), true, "UI fine")
end)

test("T28 Print Screen is never counted as the addon's shot", function()
    local env, ns = start()
    env.fire("SCREENSHOT_STARTED")
    env.fire("SCREENSHOT_SUCCEEDED")
    eq(#shots(ns), 0, "no record")
    eq(ns.Engine.Session().unattributed, 1, "counted as foreign")
end)

test("T19/T20 pause stops auto capture, manual shot still works", function()
    local env, ns = start()
    ns.Engine.SetEnabled(false)
    levelUp(env, 11)
    env.advance(5)
    eq(env.screenshotCalls, 0, "no auto shot")
    ns.Engine.ManualShot()
    env.advance(2)
    eq(#shots(ns), 1, "manual works") eq(lastShot(ns).ev, "MANUAL", "manual")
    eq(lastShot(ns).manual, true, "flag")
end)

test("T09 event storm: queue bounded, internal limit stops automatic calls", function()
    local env, ns = start()
    for i = 1, 100 do
        env.fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:" .. (1000 + i) .. "::|h[X]|h|r.")
    end
    eq(ns.Queue.Size() <= 20, true, "queue bounded")
    env.advance(120)
    eq(env.screenshotCalls <= ns.Engine.LIMIT_PER_HOUR, true, "limit")
    eq(ns.Queue.Size(), 0, "queue drained or expired")
end)

test("T23 characters are isolated; a new character starts at zero", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(5)
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    _G.UnitName = function() return "Alt" end
    local ns2 = env2.login(".")
    local s = ns2.History.Stats()
    eq(s.total, 0, "new character: no shots") eq(ns2.Steps.Today(), 0, "no steps")
    eq(#ns2.History.Recent(5), 0, "no history")
    eq(#saved.characters["Forever:Nedisan"].shots, 1, "first character untouched")
end)

test("T26 unknown client event: event unavailable, greyed out, no Lua error", function()
    local env, ns = start({ unknownEvents = { ENCOUNTER_END = true } })
    eq(ns.Registry.IsAvailable("BOSS"), false, "unavailable")
    ns.UI.Toggle("capture")
    noErrors(ns)
end)

---------------------------------------------------------------------------
-- Step Tracker
---------------------------------------------------------------------------
test("steps: walking and running count, standing does not", function()
    local env, ns = start()
    env.advance(2)
    eq(ns.Steps.Today(), 0, "idle")
    walk(env, 10, 7)
    near(ns.character.steps.days[ns.Util.DayKey(time())], stepsFor(70), 6, "70 yards")
    local before = ns.character.steps.total
    env.speed = 0
    env.advance(5)
    eq(ns.character.steps.total, before, "standing adds nothing")
end)

test("steps: ground mount counts as equivalent steps", function()
    local env, ns = start()
    env.advance(1)
    walk(env, 10, 14)
    near(ns.character.steps.total, stepsFor(140), 10, "140 yards")
end)

test("steps: swimming, flying, taxi and vehicles are not counted", function()
    for _, state in ipairs({ "swimming", "flying", "taxi", "vehicle" }) do
        local env, ns = start()
        env[state] = true
        walk(env, 10, 7)
        eq(ns.character.steps.total, 0, state)
    end
end)

test("steps: teleport, boat and zone change create no false steps", function()
    local env, ns = start()
    env.speed = 7
    env.advance(1)
    env.world.x = env.world.x + 3000 -- hearthstone / teleport
    env.advance(1)
    eq(ns.character.steps.total, 0, "teleport")
    env.speed = 0 -- standing on a boat that moves
    for _ = 1, 20 do
        env.world.x = env.world.x + 3
        env.advance(0.5)
    end
    eq(ns.character.steps.total, 0, "boat")
    env.speed = 7
    env.world.instance = 1 -- another continent
    env.world.x = 0
    env.advance(1)
    eq(ns.character.steps.total, 0, "space change")
    env.fire("PLAYER_LEAVING_WORLD")
    walk(env, 5, 7)
    eq(ns.character.steps.total, 0, "loading screen")
end)

test("steps: no coordinates -> own speed x time; nothing if exclusions unknown", function()
    local env, ns = start()
    env.unitPosition = false -- e.g. in an instance; mock has no map->world
    env.advance(1)
    walk(env, 10, 7)
    near(ns.character.steps.total, stepsFor(70), 6, "speed fallback")
    local env2, ns2 = start()
    env2.unitPosition = false
    _G.UnitOnTaxi = nil
    walk(env2, 10, 7)
    eq(ns2.character.steps.total, 0, "cannot exclude taxi -> nothing invented")
end)

test("steps: secret values are never used", function()
    local env, ns = start()
    _G.issecretvalue = function(v) return type(v) == "number" end
    walk(env, 5, 7)
    eq(ns.character.steps.total, 0, "secret speed")
    noErrors(ns)
end)

test("steps: fractions accumulate, whole numbers shown", function()
    local env, ns = start()
    for _ = 1, 10 do
        walk(env, 0.5, 0.3)
    end
    eq(ns.character.steps.total > 0, true, "small moves add up")
    eq(ns.Steps.Total(), math.floor(ns.character.steps.total), "shown as whole number")
end)

test("decimal numbers: cut, not rounded", function()
    local env, ns = start()
    eq(ns.Dec(12.4589, 2), "12.45", "two decimals, cut not rounded")
    eq(ns.Util.FormatDecimal(12458.567, 2, " ", ","), "12 458,56", "russian style")
    eq(ns.Util.FormatDecimal(0.07, 2, ",", "."), "0.07", "leading zero kept")
    eq(ns.Util.FormatDecimal(5, 2, ",", "."), "5.00", "whole number")
end)

test("steps: midnight splits the counting between days, no restart needed", function()
    local midnight = os.time({ year = 2026, month = 11, day = 25, hour = 0 })
    local env = Mock.new()
    env.unix = midnight - 6
    local ns = env.login(".")
    env.advance(1)
    walk(env, 10, 7)
    local days = ns.character.steps.days
    local before, after = days["2026-11-24"] or 0, days["2026-11-25"] or 0
    eq(before > 0, true, "yesterday part") eq(after > 0, true, "today part")
    near(before + after, stepsFor(70), 6, "sum")
    eq(ns.Steps.Today(), math.floor(after), "today starts from zero")
end)

test("steps: kept after reload and next login, continue counting", function()
    local env, ns = start()
    walk(env, 10, 7)
    local today = ns.Steps.Today()
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    _G.UnitName = function() return "Nedisan" end
    local ns2 = env2.login(".")
    eq(ns2.Steps.Today(), today, "same after reload")
    walk(env2, 5, 7)
    eq(ns2.Steps.Today() > today, true, "continues")
end)

test("steps work while auto capture is paused; an error in one module does not stop the other", function()
    local env, ns = start()
    ns.Engine.SetEnabled(false)
    walk(env, 5, 7)
    eq(ns.Steps.Today() > 0, true, "paused capture, steps go on")
    ns.Engine.SetEnabled(true)
    local realPosition = ns.API.WorldPosition
    ns.API.WorldPosition = function() error("broken") end
    walk(env, 2, 7)
    levelUp(env, 11)
    env.advance(5)
    eq(#shots(ns), 1, "capture works while steps fail")
    ns.API.WorldPosition = realPosition
end)

---------------------------------------------------------------------------
-- Passive capture (v0.6.0)
---------------------------------------------------------------------------
local MIN = 60

local function passiveShots(ns)
    local n = 0
    for _, record in ipairs(shots(ns)) do
        if record.ev == "PASSIVE" then n = n + 1 end
    end
    return n
end

local function elapsed(ns)
    return ns.character.passive.elapsed
end

test("passive: defaults on, 30 min, account-wide; timer stored per character", function()
    local _, ns = start()
    eq(ns.db.settings.passive, true, "on by default")
    eq(ns.db.settings.passiveInterval, 30, "30 minutes")
    eq(type(ns.character.passive), "table", "timer of the character")
    eq(ns.db.settings.events.PASSIVE, nil, "not one of the nine events")
end)

test("passive: one shot after 30 min of active play, in history and statistics", function()
    local env, ns = start()
    env.advance(29 * MIN)
    eq(passiveShots(ns), 0, "not yet")
    env.advance(1 * MIN + 5)
    eq(passiveShots(ns), 1, "one passive shot")
    local record = lastShot(ns)
    eq(ns.History.Title(record), "Passive screenshot", "title")
    eq(record.zone, "Elwynn Forest", "zone") eq(type(record.t), "number", "date and time")
    local s = ns.History.Stats()
    eq(s.total, 1, "total") eq(s.today, 1, "today")
    eq(ns.History.Recent(5)[1], record, "in last shots")
    eq(elapsed(ns) < 10, true, "timer restarted")
    env.advance(30 * MIN)
    eq(passiveShots(ns), 2, "next interval")
    noErrors(ns)
end)

test("passive: Russian title", function()
    local env, ns = start({ locale = "ruRU" })
    env.advance(30 * MIN + 5)
    eq(ns.History.Title(lastShot(ns)), "Пассивный снимок", "ru title")
end)

test("passive: uses the chosen mode (clean hides the UI for the shot)", function()
    local env, ns = start()
    ns.db.settings.mode = "clean"
    env.advance(30 * MIN + 5)
    eq(passiveShots(ns), 1, "shot")
    eq(env.uiShownAtShot, false, "clean frame")
    eq(UIParent:IsShown(), true, "UI back")
end)

test("passive: independent of the event switches; its own switch stops it", function()
    local env, ns = start()
    for _, id in ipairs(ns.Registry.EVENTS) do ns.db.settings.events[id] = false end
    env.advance(30 * MIN + 5)
    eq(passiveShots(ns), 1, "events off, passive still works")
    ns.db.settings.events.LEVEL = true
    ns.db.settings.passive = false
    env.advance(60 * MIN)
    eq(passiveShots(ns), 1, "passive off: no shots")
    levelUp(env, 11)
    env.advance(5)
    eq(lastShot(ns).ev, "LEVEL", "events work without passive")
end)

test("passive: AFK, loading screens and global pause do not count", function()
    local env, ns = start()
    env.advance(10 * MIN)
    local before = elapsed(ns)
    env.afk = true
    env.advance(40 * MIN)
    near(elapsed(ns), before, 1.01, "AFK not counted")
    env.afk = false
    ns.Engine.SetEnabled(false)
    env.advance(40 * MIN)
    near(elapsed(ns), before, 1.01, "pause: timer stopped")
    ns.Engine.SetEnabled(true)
    env.fire("PLAYER_LEAVING_WORLD")
    env.advance(40 * MIN)
    near(elapsed(ns), before, 1.01, "loading screen not counted")
    env.fire("PLAYER_ENTERING_WORLD")
    eq(passiveShots(ns), 0, "no shots meanwhile")
    env.advance(20 * MIN + 5)
    eq(passiveShots(ns), 1, "counting resumes where it stopped")
end)

test("passive: in combat the shot waits; missed intervals give one shot", function()
    local env, ns = start()
    env.combat = true
    env.fire("PLAYER_REGEN_DISABLED")
    env.advance(100 * MIN)
    eq(passiveShots(ns), 0, "no shot in combat")
    eq(elapsed(ns), 30 * MIN, "timer stops at the interval")
    env.combat = false
    env.fire("PLAYER_REGEN_ENABLED")
    env.advance(5)
    eq(passiveShots(ns), 1, "one shot after combat, not three")
    env.advance(5 * MIN)
    eq(passiveShots(ns), 1, "no catch-up shots")
end)

test("passive: changing the interval restarts the count", function()
    local env, ns = start()
    env.advance(20 * MIN)
    ns.db.settings.passiveInterval = 15
    env.advance(2)
    eq(elapsed(ns) <= 2, true, "restarted")
    eq(passiveShots(ns), 0, "20 min counted for 30 do not fire the 15")
    env.advance(15 * MIN)
    eq(passiveShots(ns), 1, "15 min later")
end)

test("passive: duplicate protection and the shared queue", function()
    local env, ns = start()
    local ok1 = ns.Engine.Submit({ type = "PASSIVE", key = "passive", character = ns.characterKey })
    local ok2, why = ns.Engine.Submit({ type = "PASSIVE", key = "passive", character = ns.characterKey })
    eq(ok1, true, "first accepted") eq(ok2, false, "second refused") eq(why, "duplicate", "dedupe")
    env.advance(5)
    eq(passiveShots(ns), 1, "one shot")
end)

test("passive: refused by the Engine's limits -> Waiting until the retry", function()
    local env, ns = start()
    local submit = ns.Engine.Submit
    ns.Engine.Submit = function() return false, "limit_hour" end
    env.advance(30 * MIN + 2)
    eq((ns.Passive.Timer()), "waiting", "refused: waiting")
    env.advance(30)
    eq((ns.Passive.Timer()), "waiting", "still waiting for the retry")
    ns.Engine.Submit = submit
    env.advance(31)
    eq(passiveShots(ns), 1, "retry succeeds")
    eq((ns.Passive.Timer()), "countdown", "new countdown")
end)

test("passive: timer kept after reload and next login, per character", function()
    local env, ns = start()
    env.advance(20 * MIN)
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    local ns2 = env2.login(".")
    near(ns2.character.passive.elapsed, 20 * MIN, 2, "kept after reload")
    env2.advance(10 * MIN + 5)
    eq(passiveShots(ns2), 1, "continues to the interval")
    local env3 = Mock.new({ savedDB = saved })
    _G.UnitName = function() return "Alt" end
    local ns3 = env3.login(".")
    eq(ns3.character.passive.elapsed, 0, "another character has its own timer")
    eq(passiveShots(ns3), 0, "and its own history")
    _G.UnitName = function() return "Nedisan" end
end)

test("passive: damaged saved values are repaired", function()
    local env = Mock.new({ savedDB = {
        schemaVersion = 4,
        settings = { passive = "yes", passiveInterval = 20, events = { PASSIVE = true } },
        characters = { ["Forever:Nedisan"] = { passive = { elapsed = -5, interval = "x" } } },
    } })
    local ns = env.login(".")
    eq(ns.db.settings.passive, true, "switch reset") eq(ns.db.settings.passiveInterval, 30, "interval reset")
    eq(ns.db.settings.events.PASSIVE, nil, "not an event switch")
    eq(ns.character.passive.elapsed, 0, "elapsed reset")
end)

---------------------------------------------------------------------------
-- Formatting and locales
---------------------------------------------------------------------------
test("numbers: separators and Russian word forms", function()
    local _, ns = start({ locale = "ruRU" })
    eq(ns.Count(0, "STEPS"), "0 шагов") eq(ns.Count(1, "STEPS"), "1 шаг")
    eq(ns.Count(22, "STEPS"), "22 шага") eq(ns.Count(11, "STEPS"), "11 шагов")
    eq(ns.Count(245, "STEPS"), "245 шагов") eq(ns.Count(1258, "STEPS"), "1 258 шагов")
    eq(ns.Num(12458), "12 458") eq(ns.Count(1245872, "STEPS"), "1 245 872 шага")
    eq(ns.Count(3, "SHOTS"), "3 снимка")
    local _, en = start()
    eq(en.Count(12458, "STEPS"), "12,458 steps") eq(en.Count(1, "SHOTS"), "1 screenshot")
end)

local function keysOf(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    return keys
end

test("T27 ruRU has every English key, and no distance units are shown", function()
    local _, ns = start()
    for _, key in ipairs(keysOf(ns.locales.enUS)) do
        if not string.find(key, "_one$") or key ~= "x" then
            eq(ns.locales.ruRU[key] ~= nil, true, "ruRU." .. key)
        end
    end
    for _, code in ipairs({ "enUS", "ruRU" }) do
        for key, text in pairs(ns.locales[code]) do
            local lower = string.lower(text)
            for _, unit in ipairs({ " km", "meter", "metre", " yard", "метр", " км", "ярд" }) do
                eq(string.find(lower, unit, 1, true), nil, code .. "." .. key .. " has '" .. unit .. "'")
            end
        end
    end
end)

test("every L.KEY used in code exists in enUS", function()
    local _, ns = start()
    local files = { "Core/Commands.lua", "Core/Events.lua", "Modules/History.lua", "Modules/Notifications.lua",
                    "Modules/Passive.lua", "Modules/Activity.lua", "Modules/Locations.lua",
                    "UI/Main.lua", "UI/Capture.lua", "UI/History.lua", "UI/Settings.lua", "UI/Minimap.lua",
                    "UI/SettingsData.lua", "UI/SettingsAbout.lua", "UI/Dialogs.lua", "Modules/DataTools.lua" }
    for _, file in ipairs(files) do
        local text = assert(io.open(file)):read("*a")
        for key in string.gmatch(text, "L%.([%u_][%w_]*)") do
            eq(ns.locales.enUS[key] ~= nil, true, file .. ": L." .. key)
        end
    end
end)

---------------------------------------------------------------------------
-- Playtime (shared clock of active play)
---------------------------------------------------------------------------
test("playtime: counts active play only; independent of auto capture", function()
    local env, ns = start()
    env.advance(10 * MIN)
    near(ns.Activity.Today(), 10 * MIN, 1.01, "ten minutes")
    ns.Engine.SetEnabled(false)
    ns.db.settings.passive = false
    env.advance(5 * MIN)
    near(ns.Activity.Today(), 15 * MIN, 1.01, "pause and passive off do not stop it")
    local before = ns.Activity.Today()
    env.afk = true
    env.advance(30 * MIN)
    eq(ns.Activity.Today(), before, "AFK not counted")
    env.afk = false
    env.fire("PLAYER_LEAVING_WORLD")
    env.advance(30 * MIN)
    eq(ns.Activity.Today(), before, "loading screen not counted")
    env.fire("PLAYER_ENTERING_WORLD")
    env.advance(60)
    near(ns.Activity.Today(), before + 60, 1.01, "counting resumes")
end)

test("playtime: one shared clock drives playtime and the passive timer", function()
    local env, ns = start()
    eq(ns.Passive.Start, nil, "passive has no ticker of its own")
    eq(ns.Util.Contains(ns.Activity.listeners, ns.Passive.Update), true, "passive listens to the clock")
    env.advance(7 * MIN)
    near(ns.character.passive.elapsed, ns.Activity.Today(), 1.01, "same seconds")
end)

test("playtime: format 5d 3h 30m / 3h 42m / 3 ч 42 мин", function()
    local _, ns = start()
    eq(ns.UI.FormatDuration(3 * 3600 + 42 * 60 + 59), "3h 42m", "hours and minutes")
    eq(ns.UI.FormatDuration(42 * 60), "42m", "under an hour")
    eq(ns.UI.FormatDuration(0), "0m", "zero")
    local _, ru = start({ locale = "ruRU" })
    eq(ru.UI.FormatDuration(3 * 3600 + 42 * 60), "3 ч 42 мин", "russian")
    eq(ns.UI.FormatDuration(5 * 86400 + 3 * 3600 + 30 * 60), "5d 3h 30m", "days")
    eq(ru.UI.FormatDuration(5 * 86400 + 30 * 60), "5 д 0 ч 30 мин", "russian days")
end)

test("playtime: midnight starts a new day; kept after reload; per character", function()
    local midnight = os.time({ year = 2026, month = 11, day = 25, hour = 0 })
    local env = Mock.new()
    env.unix = midnight - 30
    local ns = env.login(".")
    env.advance(90)
    local days = ns.character.playtime.days
    near(days["2026-11-24"] or 0, 30, 2, "yesterday part")
    near(days["2026-11-25"] or 0, 60, 2, "today part")
    near(ns.Activity.Today(), 60, 2, "today starts from zero")
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    env2.unix = midnight + 60
    local ns2 = env2.login(".")
    near(ns2.Activity.Today(), 60, 2, "kept after reload")
    env2.advance(60)
    near(ns2.Activity.Today(), 120, 2, "continues")
    local env3 = Mock.new({ savedDB = saved })
    _G.UnitName = function() return "Alt" end
    local ns3 = env3.login(".")
    eq(ns3.Activity.Today(), 0, "another character starts at zero")
    _G.UnitName = function() return "Nedisan" end
end)

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------
test("locations: today, lifetime and first visits from one source", function()
    local env, ns = start()
    eq(ns.Locations.Today(), 1, "login zone counts today")
    eq(ns.Locations.Total(), 1, "one zone known")
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(5)
    env.mapID, env.zone = 37, "Elwynn Forest"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(5)
    eq(ns.Locations.Today(), 2, "two different zones, Elwynn not twice")
    eq(ns.Locations.Total(), 2, "lifetime")
    eq(#shots(ns), 1, "New zone event still once")
    local today = ns.character.locations.days[ns.Util.DayKey(time())]
    eq(today["map:52"].first, true, "Westfall: first visit")
    eq(today["map:37"].first, nil, "login zone of a fresh install is not marked")
    local rows = ns.Locations.Rows()
    eq(rows[1].kind, "day", "day header") eq(rows[1].count, 2, "two zones")
    eq(rows[2].entry.name, "Elwynn Forest", "latest first")
end)

test("locations: old visited zones count, a new day re-records the zone you stand in", function()
    local midnight = os.time({ year = 2026, month = 11, day = 25, hour = 0 })
    local env = Mock.new()
    env.unix = midnight - 10
    local ns = env.login(".")
    ns.character.visited["map:1"] = true -- a zone from an earlier version
    eq(ns.Locations.Total(), 2, "earlier zones are kept and counted")
    env.advance(20)
    eq(ns.Locations.OnDay("2026-11-24"), 1, "yesterday")
    eq(ns.Locations.Today(), 1, "today without moving")
end)

local function playedLines(env)
    local n = 0
    for _, line in ipairs(env.chat) do
        if string.find(line, "Total time played", 1, true) then n = n + 1 end
    end
    return n
end

test("total playtime: the game's /played, asked once, without a chat line", function()
    local env, ns = start()
    local _, source = ns.Activity.Lifetime()
    eq(source, "addon", "before the answer: own count")
    env.advance(5)
    eq(env.playedCalls, 1, "asked once after login")
    local value, from = ns.Activity.Lifetime()
    eq(from, "game", "from the game")
    near(value, 125 * 3600 + 30 * 60, 5, "game value")
    eq(playedLines(env), 0, "no chat line for the addon's request")
    env.advance(20)
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true, "chat gets the event back")
    near(ns.Activity.Lifetime(), 125 * 3600 + 30 * 60 + 20, 2, "advances with the session")
    env.afk = true
    env.advance(60)
    near(ns.Activity.Lifetime(), 125 * 3600 + 30 * 60 + 80, 2, "AFK included, like /played")
    RequestTimePlayed() -- the player types /played
    env.advance(1)
    eq(playedLines(env), 1, "a typed /played is printed as usual")
    ns.UI.Toggle("history", "shots")
    noErrors(ns)
end)

test("total playtime: no RequestTimePlayed -> the addon's own count, no error", function()
    local env = Mock.new()
    _G.RequestTimePlayed = nil
    local ns = env.login(".")
    env.advance(10 * MIN)
    local value, from = ns.Activity.Lifetime()
    eq(from, "addon", "own count") near(value, 10 * MIN, 2, "active playtime")
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true, "chat untouched")
end)

test("history: total playtime sums every day of the character", function()
    local env, ns = start()
    ns.character.playtime.days["2026-11-01"] = 3 * 3600
    ns.character.playtime.total = 3 * 3600
    env.advance(10 * MIN)
    near(ns.Activity.Total(), 3 * 3600 + 10 * MIN, 1.01, "old days + today")
end)

test("data from 0.7.0 is kept; new fields are added without a migration", function()
    local _, ns = start()
    local saved = ns.db
    for _, c in pairs(saved.characters) do
        c.playtime, c.locations = nil, nil
        c.shots[#c.shots + 1] = { t = time(), ev = "LEVEL", info = 11 }
        c.shotsTotal = 1
        c.steps.total, c.steps.days[ns.Util.DayKey(time())] = 500, 500
    end
    saved.characters["Forever:Nedisan"].locations = { days = { bad = 5, ["2026-11-20"] = { x = 1 } } }
    local env2 = Mock.new({ savedDB = saved })
    local ns2 = env2.login(".")
    eq(ns2.db.schemaVersion, 6, "same schema")
    eq(ns2.History.Stats().total, 1, "shots kept") eq(ns2.Steps.Total(), 500, "steps kept")
    eq(type(ns2.character.playtime.days), "table", "playtime added")
    eq(ns2.Locations.OnDay("2026-11-20"), 0, "damaged entries removed")
    noErrors(ns2)
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function texts(env)
    local all = {}
    for _, frame in ipairs(env.frames) do
        if frame.shown and type(frame.text) == "string" and frame.text ~= "" then
            all[#all + 1] = frame.text
        end
    end
    return all
end

local function hasText(env, wanted)
    for _, text in ipairs(texts(env)) do
        if text == wanted then return true end
    end
    return false
end

local function findButton(env, text)
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and type(rawget(frame, "label")) == "table" and frame.label.text == text then
            return frame
        end
    end
end

-- The same, but only a button that is shown (list rows reuse hidden buttons).
local function findShownButton(env, text)
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and type(rawget(frame, "label")) == "table" and frame.label.text == text
            and frame:IsVisible() then
            return frame
        end
    end
end

test("window: four tabs, each builds and refreshes without errors", function()
    local env, ns = start()
    eq(#ns.UI.TABS, 4, "four tabs")
    ns.UI.Toggle()
    for _, id in ipairs(ns.UI.TABS) do
        ns.UI.ShowTab(id)
        eq(ns.UI.CurrentTab(), id, id)
    end
    for _, name in ipairs({ "Home", "Auto capture", "History", "Settings" }) do
        eq(findButton(env, name) ~= nil, true, "tab " .. name)
    end
    -- "Journey" is a History sub-view since v0.9.0, not a main tab.
    for _, gone in ipairs({ "Events", "Profiles", "Diagnostics" }) do
        eq(findButton(env, gone), nil, "no tab " .. gone)
    end
    -- "About" is a page inside Settings since v0.10.0, not a main tab.
    noErrors(ns)
end)

test("home: daily adventure: date, four today cards, location, latest three of today", function()
    local env, ns = start()
    ns.UI.Toggle()
    eq(hasText(env, "Daily adventure"), true, "caption")
    eq(hasText(env, ns.History.DateText(ns.Util.DayKey(time()))), true, "today's date")
    eq(hasText(env, "No screenshots today yet"), true, "empty message")
    for _, label in ipairs({ "Screenshots today", "Steps today", "Locations today", "Playtime today" }) do
        eq(hasText(env, label), true, "card " .. label)
    end
    for _, gone in ipairs({ "Total distance", "Total screenshots" }) do
        eq(hasText(env, gone), false, "not on Home: " .. gone)
    end
    eq(hasText(env, "Elwynn Forest"), true, "current location")
    -- A shot of yesterday is not "today".
    local old = { t = time() - 86400, ev = "DEATH", zone = "Duskwood" }
    ns.character.shots[#ns.character.shots + 1] = old
    ns.Database.CountShot(ns.character, old)
    for level = 11, 15 do
        levelUp(env, level)
        env.advance(15)
    end
    walk(env, 10, 7)
    ns.UI.ShowTab("home")
    eq(hasText(env, "Nedisan"), true, "character name")
    eq(hasText(env, "Reached level 15"), true, "newest shot")
    eq(hasText(env, "Reached level 13"), true, "third shot")
    eq(hasText(env, "Reached level 12"), false, "only three")
    eq(hasText(env, ns.Num(ns.Steps.Today())), true, "steps today")
    eq(#ns.History.Today(3), 3, "three of today") eq(#ns.History.Today(10), 5, "yesterday not included")
    findButton(env, "Settings"):Click()
    ns.UI.ShowTab("home")
    for _, frame in ipairs(env.frames) do
        if type(rawget(frame, "label")) == "table" and frame.label.text == "View screenshot history  >" then frame:Click() end
    end
    eq(ns.UI.CurrentTab(), "history", "opens history")
    noErrors(ns)
end)

test("home: passive countdown follows the real timer, MM:SS and every state", function()
    local env, ns = start()
    ns.UI.Toggle()
    env.advance(10 * MIN)
    local state, left, fraction = ns.Passive.Timer()
    eq(state, "countdown", "counting") near(left, 20 * MIN, 1.01, "left")
    near(fraction, 1 / 3, 0.01, "progress")
    eq(hasText(env, ns.UI.FormatCountdown(left)), true, "MM:SS on Home")
    eq(ns.UI.FormatCountdown(14 * 60 + 32), "14:32", "format")
    eq(ns.UI.FormatCountdown(3600), "60:00", "a 60 min interval")
    env.afk = true
    env.advance(2)
    local s, _, _, why = ns.Passive.Timer()
    eq(s, "paused", "afk pauses") eq(why, "afk", "reason") eq(hasText(env, "AFK"), true, "AFK shown")
    env.afk = false
    ns.Engine.SetEnabled(false)
    env.advance(2)
    eq((ns.Passive.Timer()), "paused", "auto capture paused") eq(hasText(env, "Paused"), true, "Paused shown")
    ns.Engine.SetEnabled(true)
    ns.db.settings.passive = false
    env.advance(2)
    eq((ns.Passive.Timer()), "disabled", "off") eq(hasText(env, "Off"), true, "Off shown")
    ns.db.settings.passive = true
    env.combat = true
    env.advance(21 * MIN)
    eq((ns.Passive.Timer()), "waiting", "due in combat: waiting") eq(hasText(env, "Waiting"), true, "Waiting shown")
    env.combat = false
    env.advance(5)
    eq((ns.Passive.Timer()), "countdown", "after the shot a new countdown")
    eq(passiveShots(ns), 1, "one shot")
    noErrors(ns)
end)

test("history: thousands of records use a few rows, grouped by day", function()
    local env, ns = start()
    local c = ns.character
    local t0 = time() - 3 * 86400
    for i = 1, 3000 do
        local record = { t = t0 + i * 60, ev = "ZONE", zone = "Zone " .. (i % 7) }
        c.shots[#c.shots + 1] = record
        ns.Database.CountShot(c, record)
    end
    local before = #env.frames
    ns.UI.Toggle("history", "shots")
    local created = #env.frames - before
    eq(created < 1500, true, "frames created: " .. created)
    local rows = ns.History.Rows()
    eq(rows[1].kind, "day", "first row is a day")
    eq(rows[2].record.t > rows[3].record.t, true, "newest first")
    findButton(env, "Steps"):Click()
    noErrors(ns)
end)

test("history: lifetime dashboard stays visible over Screenshots, Steps and Locations", function()
    local env, ns = start()
    ns.character.steps.total, ns.character.steps.days[ns.Util.DayKey(time())] = 358724, 12458
    env.played = 3 * 3600 + 42 * 60
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(5)
    env.advance(4) -- /played answer
    ns.UI.Toggle("history", "shots")
    eq(hasText(env, "Lifetime statistics"), true, "caption")
    for _, sub in ipairs({ "Screenshots", "Steps", "Locations" }) do
        findButton(env, sub):Click()
        for _, label in ipairs({ "Total screenshots", "Total steps", "Locations visited", "Total playtime" }) do
            eq(hasText(env, label), true, sub .. ": card " .. label)
        end
        eq(hasText(env, "358,724"), true, sub .. ": total steps value")
        eq(hasText(env, "3h 42m"), true, sub .. ": total playtime value")
    end
    -- Opening Locations at a day (Overview's day panel) opens the history there.
    ns.UI.OpenHistory("zones", ns.Util.DayKey(time()))
    eq(hasText(env, "Westfall"), true, "locations list")
    eq(hasText(env, "First visit"), true, "first visit mark")
    eq(hasText(env, "2 locations"), true, "count of the day")
    eq(findButton(env, "Home") ~= nil, true, "still four main tabs")
    noErrors(ns)
end)

test("history: seven-day chart and daily steps", function()
    local env, ns = start()
    local today = ns.Util.DayKey(time())
    ns.character.steps.days[ns.Util.DayBefore(today, 2)] = 5000
    ns.character.steps.days[today] = 1200
    ns.UI.Toggle("history", "steps")
    eq(hasText(env, "5,000"), true, "bar value")
    eq(hasText(env, "1,200"), true, "today value")
    local days = ns.Steps.Days()
    eq(days[1].day, today, "newest first")
end)

test("settings: checks, language with consent, scale and window position", function()
    local env, ns = start()
    env.autoConfirm = false
    ns.UI.Toggle("settings")
    findButton(env, "Automatic"):Click()
    local russian
    for _, frame in ipairs(env.frames) do
        if type(rawget(frame, "text")) == "table" and frame.text.text == "Русский" then russian = frame end
    end
    russian:Click()
    eq(ns.db.settings.locale, "ruRU", "saved at once")
    eq(env.reloads, 0, "no reload without consent")
    eq(#env.popups, 1, "asked")
    ns.UI.ResetPosition()
    eq(ns.db.ui.point, nil, "position reset")
end)

test("minimap: left window, right pause, middle shot; tooltip shows steps", function()
    local env, ns = start()
    local button = _G.ForeverMemoriesMinimapButton
    button:Click("RightButton")
    eq(ns.db.settings.enabled, false, "paused")
    button:Click("MiddleButton")
    env.advance(2)
    eq(#shots(ns), 1, "manual shot")
    button:Click("LeftButton")
    eq(ns.UI.IsShown(), true, "window")
    button.scripts.OnEnter(button)
    local found = false
    for _, line in ipairs(env.tooltip) do
        if string.find(line, "Steps today", 1, true) then found = true end
    end
    eq(found, true, "steps in tooltip")
end)

test("window and notification are hidden during a shot", function()
    local env, ns = start()
    ns.UI.Toggle()
    levelUp(env, 11)
    env.advance(0.53)
    eq(_G.ForeverMemoriesMainFrame:IsShown(), false, "hidden for the shot")
    env.advance(1)
    eq(_G.ForeverMemoriesMainFrame:IsShown(), true, "back")
    eq(_G.ForeverMemoriesToast:IsShown(), true, "notification after the shot")
    env.advance(6) -- 5 s by default since v0.10.0
    eq(_G.ForeverMemoriesToast:IsShown(), false, "notification gone")
end)

test("slash commands run without errors", function()
    local env, ns = start()
    for _, command in ipairs({ "", "status", "debug", "log", "zones", "ui", "reset", "off", "on", "toggle", "shot", "help" }) do
        SlashCmdList.FOREVERMEMORIES(command)
    end
    env.advance(3)
    eq(type(ns.db.zoneDump), "table", "/fm zones saved for the file")
    eq(ns.db.zoneDump.lines[#ns.db.zoneDump.lines - 1], "missing in client: -", "every catalog zone known")
    noErrors(ns)
end)

test("world explorer: client knows none of the IDs -> English names in enUS, none otherwise", function()
    local env = Mock.new()
    local ns = env.login(".") -- areaNames stay empty: GetAreaInfo knows nothing
    eq(ns.ZoneCatalog.Explorer().status, "english", "enUS")
    local env2 = Mock.new({ locale = "ruRU" })
    local ru = env2.login(".")
    eq(ru.ZoneCatalog.Explorer().percent, nil, "ruRU: not confirmed")
end)

test("passive: Auto capture tab block, interval buttons and switch", function()
    local env, ns = start()
    ns.UI.Toggle("capture")
    eq(hasText(env, "Passive capture"), true, "heading")
    eq(hasText(env, "One extra screenshot every 30 minutes of active play."), true, "hint")
    findButton(env, "45 min"):Click()
    eq(ns.db.settings.passiveInterval, 45, "interval chosen")
    eq(hasText(env, "One extra screenshot every 45 minutes of active play."), true, "hint updated")
    eq(findButton(env, "45 min").selected, true, "selected")
    eq(findButton(env, "30 min").selected, false, "old one not selected")
    ns.db.settings.passive = false
    ns.UI.Refresh()
    eq(hasText(env, "Passive capture is off."), true, "off hint")
    eq(findButton(env, "45 min").disabled, true, "buttons disabled when off")
    eq(hasText(env, "9 of 9"), true, "event counter unchanged")
    noErrors(ns)
end)

test("chat: every saved screenshot is reported in chat (manual, event, passive)", function()
    local env, ns = start()
    local function saidSaved()
        local n = 0
        for _, msg in ipairs(env.chat) do
            if string.find(msg, "Screenshot saved", 1, true) then n = n + 1 end
        end
        return n
    end
    ns.Engine.ManualShot()
    env.advance(2)
    levelUp(env, 11)
    env.advance(5)
    env.advance(30 * 60 + 5)
    eq(saidSaved(), 3, "three chat messages")
    local last = env.chat[#env.chat]
    eq(string.find(last, "Passive screenshot", 1, true) ~= nil, true, "title in chat")
    eq(string.find(last, "Elwynn Forest", 1, true) ~= nil, true, "zone in chat")
    ns.db.settings.notifications = false
    ns.Engine.ManualShot()
    env.advance(2)
    eq(saidSaved(), 3, "notifications off: no chat message")
end)


---------------------------------------------------------------------------
-- v0.9.0: adventure diary
---------------------------------------------------------------------------
local function schema4DB()
    local t0 = os.time({ year = 2026, month = 11, day = 19, hour = 16 })
    return {
        schemaVersion = 4,
        settings = { enabled = true },
        characters = {
            ["Forever:Nedisan"] = {
                name = "Nedisan", realm = "Forever", class = "DRUID",
                shots = {
                    { t = t0, ev = "ZONE", zone = "Westfall" },
                    { t = t0 + 60, ev = "LOOT_RARE", zone = "Westfall", info = "[Blue]" },
                    { t = t0 + 120, ev = "LEVEL", zone = "Westfall", info = 10 },
                    { t = t0 + 180, ev = "LOOT_RARE", zone = "Westfall", info = "[Blue 2]" },
                    { t = t0 + 240, ev = "BOSS", zone = "The Deadmines", info = "VanCleef" },
                    { t = t0 + 300, ev = "DUEL", zone = "Elwynn Forest", info = "Bob" },
                    { t = t0 + 360, ev = "GUILD", zone = "Stormwind City", info = "Heroes" },
                    { t = t0 + 420, ev = "LEVEL", zone = "Duskwood", info = 11 },
                },
                shotsTotal = 8, shotsByDay = { ["2026-11-19"] = 8 }, shotZones = {},
                visited = { ["map:52"] = true, ["map:37"] = true, ["map:1"] = true }, zonesSeeded = true,
                steps = { total = 9436, days = { ["2026-11-19"] = 9436 }, since = t0 - 3600 },
                passive = { elapsed = 0 },
                playtime = { total = 3600, days = { ["2026-11-20"] = 3600 } },
                locations = { days = {
                    ["2026-11-20"] = { ["map:52"] = { name = "Westfall", t = t0 + 86400, first = true },
                                       ["map:37"] = { name = "Elwynn Forest", t = t0 + 86400 + 50 } },
                } },
            },
        },
    }
end

test("migration 0.8 -> 0.9: diary from real records only, nothing lost, runs once", function()
    local env = Mock.new({ savedDB = schema4DB() })
    local ns = env.loadAddon(".")
    fillAreas(env, ns)
    env.fire("ADDON_LOADED", "ForeverMemories")
    env.fire("PLAYER_LOGIN")
    env.fire("PLAYER_ENTERING_WORLD")
    local c = ns.character
    eq(ns.db.schemaVersion, 6, "schema 6")
    eq(#c.shots, 8, "shots kept") eq(ns.Steps.Total(), 9436, "steps kept")
    eq(c.playtime.days["2026-11-20"], 3600, "playtime kept")
    eq(c.playtime.sinceDay, "2026-11-20", "playtime counted since its first day")
    eq(c.visited["map:1"], true, "visited zones kept")
    local kinds = {}
    for _, e in ipairs(c.journey.events) do kinds[#kinds + 1] = e.kind end
    eq(table.concat(kinds, ","), "FIRST_RARE,LEVEL,FIRST_DUEL,GUILD,LEVEL", "journey from shots")
    eq(c.journey.events[1].info, "[Blue]", "the first rare item, once")
    eq(c.journey.started, os.time({ year = 2026, month = 11, day = 19, hour = 15 }), "start = earliest record (steps)")
    eq(c.visitedAt["map:52"], os.time({ year = 2026, month = 11, day = 20, hour = 16 }), "first registered visit")
    eq(c.visitedAt["map:1"], nil, "no invented date for an old visit")
    -- Loading the saved data again changes nothing.
    local env2 = Mock.new({ savedDB = ns.db })
    local ns2 = env2.login(".")
    eq(#ns2.character.journey.events, 5, "no duplicates")
    noErrors(ns2)
end)

test("migration 0.4.2 -> 0.9: journey from old shots too", function()
    local _, ns = start({ savedDB = oldDB() })
    local journey = ns.db.characters["Forever:Nedisan"].journey
    eq(journey.events[1] and journey.events[1].kind, "LEVEL", "level 24 from the old journal")
    eq(journey.events[1].info, 24, "level number")
    eq(journey.started, 1795000000, "start = the earliest old record")
    noErrors(ns)
end)

test("journey: levels, max level, first boss / items / duel, guild; independent of capture", function()
    local env, ns = start()
    ns.Engine.SetEnabled(false)              -- auto capture paused
    ns.db.settings.events.LOOT_EPIC = false  -- and this event not photographed
    levelUp(env, 11)
    env.advance(2)
    env.maxLevel = 12
    levelUp(env, 12)
    env.advance(2)
    env.instanceType = "party"
    env.fire("ENCOUNTER_END", 1, "Boss A", 1, 5, 1)
    env.advance(2)
    env.fire("ENCOUNTER_END", 2, "Boss B", 1, 5, 1)
    env.advance(2)
    env.instanceType = "raid"
    env.fire("ENCOUNTER_END", 3, "Onyxia", 1, 5, 1)
    env.instanceType = "none"
    env.advance(2)
    local epic = "|cffa335ee|Hitem:100::::::::|h[Epic]|h|r"
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. epic .. ".")
    env.advance(2)
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. epic .. ".")
    env.advance(70)
    env.fire("CHAT_MSG_SYSTEM", "Nedisan has defeated Bob in a duel")
    env.advance(2)
    -- Earned achievements are journey events too (v0.14.0); this test is
    -- about the other kinds, so they are left out here.
    local rows, kinds = {}, {}
    for _, e in ipairs(ns.Journey.Rows()) do
        if e.kind ~= "ACHIEVEMENT" then rows[#rows + 1] = e; kinds[#kinds + 1] = e.kind end
    end
    eq(table.concat(kinds, ","), "FIRST_DUEL,FIRST_EPIC,FIRST_RAID_BOSS,FIRST_DUNGEON_BOSS,MAX_LEVEL,LEVEL,START",
        "newest first, each first once, start last")
    eq(rows[4].info, "Boss A", "boss name") eq(rows[5].info, 12, "max level")
    eq(ns.Journey.Title(rows[6]), "Reached level 11", "title")
    eq(#shots(ns), 0, "no screenshots were taken for the journey")
    noErrors(ns)
end)

test("calendar: fixed levels without overlaps, 12 Monday weeks, today, future, no data", function()
    local env = Mock.new()
    env.unix = os.time({ year = 2026, month = 11, day = 25, hour = 12 }) -- Wednesday
    local ns = env.login(".")
    local A = ns.Adventure
    eq(A.Level(0), 0, "0 min") eq(A.Level(1), 1, "seconds") eq(A.Level(59 * 60 + 59), 1, "under 60")
    eq(A.Level(60 * 60), 2, "60") eq(A.Level(119 * 60 + 59), 2, "under 120")
    eq(A.Level(120 * 60), 3, "120") eq(A.Level(239 * 60), 3, "under 240") eq(A.Level(240 * 60), 4, "240")
    ns.character.playtime.days["2026-11-24"] = 3 * 3600
    local columns = A.Calendar("2026-11-25", 12)
    eq(#columns, 12, "12 weeks")
    local last = columns[12].days
    eq(last[1].day, "2026-11-23", "week starts on Monday")
    eq(last[3].today, true, "today marked")
    eq(last[2].state, "nodata", "before the tracker started: no data, not zero")
    eq(last[3].state, 0, "today without play yet: level 0")
    eq(last[4].state, "future", "future days are not past days")
    eq(columns[1].days[1].day, "2026-09-07", "first week")
    eq(columns[4].month, 10, "October label where the 1st is")
    ns.character.playtime.sinceDay = "2026-11-20"
    eq(A.Calendar("2026-11-25", 12)[12].days[2].state, 3, "3 h -> gold")
    eq(A.Calendar("2026-11-25", 12)[11].days[6].state, 0, "a tracked day without play")
end)

test("recap: week Monday-Sunday, month 1st-last, unique zones as a union", function()
    local env = Mock.new()
    env.unix = os.time({ year = 2026, month = 11, day = 25, hour = 12 })
    local ns = env.login(".")
    local c = ns.character
    c.shotsByDay = { ["2026-11-22"] = 5, ["2026-11-23"] = 2, ["2026-11-29"] = 1, ["2026-11-01"] = 4 }
    c.steps.days = { ["2026-11-23"] = 1000.7, ["2026-11-24"] = 500.6 }
    c.playtime.days = { ["2026-11-23"] = 3600, ["2026-11-24"] = 0, ["2026-11-02"] = 600 }
    c.locations.days = {
        ["2026-11-23"] = { ["map:52"] = { name = "Westfall", t = 1, first = true }, ["map:37"] = { name = "Elwynn", t = 2 } },
        ["2026-11-24"] = { ["map:52"] = { name = "Westfall", t = 3 }, ["map:10"] = { name = "Duskwood", t = 4, first = true } },
        ["2026-11-02"] = { ["map:40"] = { name = "X", t = 5 } },
    }
    local first, last = ns.Adventure.WeekRange("2026-11-25")
    eq(first .. " " .. last, "2026-11-23 2026-11-29", "week")
    eq(table.concat({ ns.Adventure.MonthRange("2026-02-10") }, " "), "2026-02-01 2026-02-28", "February")
    local w = ns.Adventure.Week("2026-11-25")
    eq(w.shots, 3, "shots of the week") eq(w.steps, 1501, "steps") eq(w.zones, 3, "unique zones, not 4")
    eq(w.newZones, 2, "new zones") eq(w.playtime, 3600, "playtime") eq(w.days, 1, "days played")
    local m = ns.Adventure.Month("2026-11-25")
    eq(m.shots, 12, "month shots") eq(m.zones, 4, "month zones") eq(m.days, 2, "month days")
end)

test("world explorer: catalog counted, zones by area, dungeons excluded, per character", function()
    local env, ns = start()
    local e = ns.ZoneCatalog.Explorer()
    local total = 0
    for _, region in ipairs(ns.ZoneCatalog.REGIONS) do total = total + #region.zones end
    eq(e.total, total, "total = catalog size, computed")
    eq(#e.regions, 3, "Eastern Kingdoms, Kalimdor, Zephras Isle")
    eq(e.visited, 1, "Elwynn Forest (login zone)")
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.instanceType, env.mapID, env.zone = "party", 291, "The Deadmines"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(5)
    e = ns.ZoneCatalog.Explorer()
    eq(e.visited, 2, "the dungeon does not count")
    near(e.percent, 2 / total * 100, 0.001, "percent computed")
    local westfall
    for _, z in ipairs(e.regions[1].zones) do if z.name == "Westfall" then westfall = z end end
    eq(westfall.visited, true, "visited") eq(type(westfall.firstAt), "number", "first visit date")
    eq(e.regions[1].zones[1].name, "Alterac Mountains", "alphabetical")
    local day = ns.Locations.Day(ns.Util.DayKey(time()))
    eq(day["inst:The Deadmines"].instance, "party", "dungeon kept in the daily history")
    eq(ns.Locations.Total(), 2, "dungeon is not a visited zone")
    eq(#shots(ns), 1, "only Westfall gave a New zone shot")
    noErrors(ns)
end)

test("world explorer: no confirmed catalog -> no percentage", function()
    local env, ns = start({ noAreaInfo = true, locale = "ruRU" })
    local e = ns.ZoneCatalog.Explorer()
    eq(e.percent, nil, "no percent")
    ns.UI.Toggle("history", "zones")
    eq(hasText(env, "Нет данных"), true, "shown as no data")
    noErrors(ns)
    local _, en = start({ noAreaInfo = true })
    eq(en.ZoneCatalog.Explorer().percent ~= nil, true, "English client: English names are the client's")
end)

test("locations: first arrival of the day kept, one row per zone and day", function()
    local env, ns = start()
    local key = ns.Util.DayKey(time())
    local first = ns.Locations.Day(key)["map:37"].t
    env.advance(60)
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(60)
    env.mapID, env.zone = 37, "Elwynn Forest"
    env.fire("ZONE_CHANGED_NEW_AREA")
    eq(ns.Locations.Day(key)["map:37"].t, first, "first arrival time")
    eq(ns.Locations.OnDay(key), 2, "two rows")
end)

test("sessions: reload continues, a later login starts a new one; longest kept", function()
    local env = Mock.new()
    local ns = env.login(".")
    env.advance(30 * MIN)
    eq(select(1, ns.Activity.Sessions()), 1, "current session counts")
    local saved = ns.db
    local env2 = Mock.new({ savedDB = saved })
    env2.unix = env.unix + 30 * MIN + 30 -- /reload
    local ns2 = env2.login(".")
    env2.advance(10 * MIN)
    local count, longest = ns2.Activity.Sessions()
    eq(count, 1, "reload is the same session") near(longest, 40 * MIN, 3, "40 min so far")
    local env3 = Mock.new({ savedDB = saved })
    env3.unix = env2.unix + 3 * 3600 -- next evening
    local ns3 = env3.login(".")
    env3.advance(5 * MIN)
    count, longest = ns3.Activity.Sessions()
    eq(count, 2, "new session") near(longest, 40 * MIN, 3, "longest kept")
    eq(ns3.character.playtime.sessions, 1, "one closed")
    local days, total, average = ns3.Activity.PlayedDays()
    eq(days, 1, "one day") eq(average, total, "average of one day")
end)

test("search: case-insensitive, Russian letters too", function()
    local _, ns = start()
    eq(ns.Util.Lower("ДУСКВУД Ёж Westfall"), "дусквуд ёж westfall", "lower")
end)

test("history v0.9: six sub-views, Overview first, calendar day opens its history", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(65)
    ns.UI.Toggle()
    findButton(env, "History"):Click()
    eq(hasText(env, "Adventure Calendar"), true, "Overview opens by default")
    -- One scroll area below the dashboard: the recap is further down.
    for _, frame in ipairs(env.frames) do
        if frame.shown and frame.scripts.OnMouseWheel then frame.scripts.OnMouseWheel(frame, -5) end
    end
    eq(hasText(env, "Adventure Recap"), true, "recap")
    eq(hasText(env, "Unique locations"), true, "recap rows")
    for _, sub in ipairs({ "Overview", "Screenshots", "Steps", "Locations", "Playtime", "Journey" }) do
        local button = findButton(env, sub)
        eq(button ~= nil, true, "sub-view " .. sub)
        button:Click()
        for _, label in ipairs({ "Total screenshots", "Total steps", "Locations visited", "Total playtime" }) do
            eq(hasText(env, label), true, sub .. ": card " .. label)
        end
    end
    eq(hasText(env, "Reached level 11"), true, "journey entry")
    eq(hasText(env, "Journey Started"), true, "journey start")
    findButton(env, "Playtime"):Click()
    eq(hasText(env, "Longest Session"), true, "playtime tiles")
    findButton(env, "Locations"):Click()
    eq(hasText(env, "World Explorer"), true, "explorer")
    eq(hasText(env, "1 / 51"), true, "progress of the catalog")
    eq(hasText(env, "Eastern Kingdoms"), true, "region")
    ns.UI.OpenHistory("shots", ns.Util.DayKey(time()))
    eq(hasText(env, "Reached level 11"), true, "shots of the day")
    eq(#ns.UI.TABS, 4, "still four main tabs")
    noErrors(ns)
end)

test("home: Last adventure card (v0.12, replaces Adventure This Week)", function()
    local env, ns = start()
    ns.UI.Toggle()
    eq(hasText(env, "Last adventure"), true, "card")
    eq(hasText(env, "Your first completed session will appear here"), true, "no session yet")
    eq(hasText(env, "Total screenshots"), false, "no lifetime cards on Home")
    noErrors(ns)
    local ru = select(2, start({ locale = "ruRU" }))
    ru.UI.Toggle()
    noErrors(ru)
end)

---------------------------------------------------------------------------
-- v0.10.0: Settings & Identity
---------------------------------------------------------------------------
local function dialogText()
    return _G.ForeverMemoriesTextDialog and _G.ForeverMemoriesTextDialog.edit:GetText()
end

test("v0.10 settings: new defaults, scale 70-150 %, four pages under Settings", function()
    local env, ns = start()
    local s = ns.db.settings
    eq(s.rememberTab, true, "remember tab")
    eq(s.toastDuration, 5, "5 s")
    eq(s.notifications, true, "notifications")
    eq(s.sound, false, "sound off")
    eq(s.locale, "auto", "language from the client")
    ns.UI.Toggle("settings")
    for _, name in ipairs({ "General", "Data", "About", "Changelog" }) do
        local button = findButton(env, name)
        eq(button ~= nil, true, "page " .. name)
        button:Click()
    end
    eq(#ns.UI.TABS, 4, "still four main tabs")
    noErrors(ns)
    local _, low = start({ savedDB = { schemaVersion = 5, settings = { scale = 0.6, toastDuration = 4 }, characters = {} } })
    eq(low.db.settings.scale, 1, "below 70 % reset")
    eq(low.db.settings.toastDuration, 5, "unknown duration reset")
    local _, high = start({ savedDB = { schemaVersion = 5, settings = { scale = 1.5 }, characters = {} } })
    eq(high.db.settings.scale, 1.5, "150 % allowed")
end)

test("restore defaults: Reset appearance resets only its page, after confirmation", function()
    local env, ns = start()
    env.autoConfirm = false
    local s = ns.db.settings
    s.scale, s.locale, s.minimap, s.notifications, s.durationMini = 1.4, "ruRU", false, false, 10
    s.mode, s.passive, s.enabled, s.events.LEVEL = "clean", false, false, false
    ns.db.ui.point = { "CENTER", "CENTER", 5, 5 }
    levelUp(env, 11)
    ns.Engine.ManualShot()
    env.advance(2)
    local before = #shots(ns)
    s.locale = "enUS"
    ns.UI.Toggle("settings")
    findButton(env, "Appearance"):Click()
    findButton(env, "Reset appearance"):Click()
    eq(s.scale, 1.4, "nothing changed before the answer")
    env.autoConfirm = true
    findButton(env, "Reset appearance"):Click()
    eq(s.scale, 1, "scale")
    eq(ns.db.ui.point, nil, "window position")
    eq(s.locale, "enUS", "language kept")
    eq(s.minimap, false, "minimap kept")
    eq(s.notifications, false, "notifications kept")
    eq(s.durationMini, 10, "notification time kept")
    eq(s.mode, "clean", "capture mode kept")
    eq(s.passive, false, "passive kept")
    eq(s.enabled, false, "pause kept")
    eq(s.events.LEVEL, false, "event switch kept")
    eq(#shots(ns), before, "history kept")
    noErrors(ns)
end)

test("v0.10 remember tab: last tab after /reload; off -> Home", function()
    local env, ns = start()
    ns.UI.Toggle("history")
    eq(ns.db.ui.lastTab, "history", "saved")
    local env2, ns2 = start({ savedDB = ns.db })
    ns2.UI.Toggle()
    eq(ns2.UI.CurrentTab(), "history", "opens where it was")
    ns2.db.settings.rememberTab = false
    local _, ns3 = start({ savedDB = ns2.db })
    ns3.UI.Toggle()
    eq(ns3.UI.CurrentTab(), "home", "always Home when off")
    ns3.UI.Toggle("settings")
    ns3.UI.Toggle() -- close
    ns3.UI.Toggle() -- open again
    eq(ns3.UI.CurrentTab(), "home", "reopened on Home")
end)

test("notifications: own time per kind, Preview works even when off and toggles", function()
    local env, ns = start()
    ns.db.settings.durationMini = 10
    ns.db.settings.notifications = false
    ns.UI.Toggle("settings")
    findButton(env, "Notifications"):Click()
    local preview = findButton(env, "Preview") -- the first card is the mini one
    preview:Click()
    eq(_G.ForeverMemoriesToast:IsShown(), true, "shown although notifications are off")
    eq(ns.Notifications.IsPreviewing("mini"), true, "it is the preview")
    env.advance(9)
    eq(_G.ForeverMemoriesToast:IsShown(), true, "still shown at 9 s")
    env.advance(2)
    eq(_G.ForeverMemoriesToast:IsShown(), false, "gone after 10 s")
    ns.Notifications.Test("mini")
    eq(ns.Notifications.IsPreviewing("mini"), true, "shown again")
    ns.Notifications.Test("mini")
    eq(ns.Notifications.IsPreviewing("mini"), false, "a second press hides it")
    eq(#shots(ns), 0, "no screenshot")
    findButton(env, "3 sec"):Click()
    eq(ns.db.settings.durationMini, 3, "3 s chosen for the mini kind")
    noErrors(ns)
end)

test("v0.10 serialize: round trip, and nothing but the format is accepted", function()
    local _, ns = start()
    local S = ns.Serialize
    local data = { a = "Elwynn Forest; |cffff0000x|r 100% \\ \n", n = { 1, 2.5, -3e-7, 1795000000 },
                   yes = true, no = false, ru = "Сумеречный лес", [7] = { deep = { deeper = "x" } } }
    local text = S.Encode(data, 5)
    eq(string.find(text, "|", 1, true), nil, "no | in the text (chat escapes)")
    eq(string.find(text, " ", 1, true), nil, "no spaces")
    local back, schema = S.Decode("  " .. string.sub(text, 1, 40) .. "\n" .. string.sub(text, 41) .. "\n")
    eq(schema, 5, "schema")
    eq(back.a, data.a, "string")
    eq(back.n[2], 2.5, "number")
    eq(back.n[3], -3e-7, "small number")
    eq(back.yes, true, "true")
    eq(back.no, false, "false")
    eq(back.ru, data.ru, "UTF-8")
    eq(back[7].deep.deeper, "x", "nested")
    eq(select(2, S.Decode("")), "empty", "empty")
    eq(select(2, S.Decode("return os.exit()")), "format", "Lua code is not a backup")
    eq(select(2, S.Decode(string.sub(text, 1, -3))), "checksum", "cut text")
    local payload = "TSa;F"
    eq(select(2, S.Decode("FMB1:5:" .. S.Checksum(payload) .. ":" .. payload)), "damaged", "unfinished table")
    payload = "TSa;S%4;E"
    eq(select(2, S.Decode("FMB1:5:" .. S.Checksum(payload) .. ":" .. payload)), "damaged", "bad escape")
    payload = "TYSa;E"
    eq(select(2, S.Decode("FMB1:5:" .. S.Checksum(payload) .. ":" .. payload)), "damaged", "boolean key")
end)

test("v0.10 backup and import: checked, confirmed, restored; never executed", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(2)
    walk(env, 30)
    local shotsBefore, stepsBefore = #shots(ns), ns.Steps.Total()
    ns.db.characters["Forever:Alt"] = { name = "Alt", realm = "Forever", class = "MAGE" }
    ns.db.characters["Forever:Alt"] = ns.Database.Load({ schemaVersion = 5, settings = {},
        characters = { ["Forever:Alt"] = { name = "Alt", realm = "Forever", class = "MAGE" } } }).characters["Forever:Alt"]
    local text = ns.DataTools.BackupText()
    -- A string that looks like code stays a string.
    ns.character.shots[1].zone = "os.exit(1) --]]"
    local evil = ns.DataTools.BackupText()
    ns.character.shots[1].zone = "Elwynn Forest"

    ns.DataTools.ClearCurrent()
    ns.DataTools.Delete("Forever:Alt")
    eq(#shots(ns), 0, "cleared")
    eq(ns.db.characters["Forever:Alt"], nil, "alt deleted")

    eq(select(2, ns.DataTools.CheckBackup("hello")), "format", "not a backup")
    local newer = string.gsub(text, "^FMB1:%d+:", "FMB1:9:")
    eq(select(2, ns.DataTools.CheckBackup(newer)), "newer", "newer schema refused")
    local plan = assert(ns.DataTools.CheckBackup(text))
    eq(plan.characters, 2, "two characters")
    eq(plan.shots, shotsBefore, "shot records")
    eq(plan.version, ns.version, "made by")
    eq(#shots(ns), 0, "checking changes nothing")

    env.autoConfirm = true
    ns.UI.Toggle("settings")
    findButton(env, "Data"):Click()
    findButton(env, "Import"):Click()
    _G.ForeverMemoriesTextDialog.edit:SetText(text)
    findButton(env, "Check"):Click()
    eq(#shots(ns), shotsBefore, "shots restored")
    near(ns.Steps.Total(), stepsBefore, 0.01, "steps restored")
    eq(ns.db.characters["Forever:Alt"] ~= nil, true, "alt restored")
    eq(ForeverMemoriesDB, ns.db, "saved variable replaced")
    eq(env.reloads, 1, "reload offered and accepted")
    local evilPlan = assert(ns.DataTools.CheckBackup(evil))
    eq(evilPlan.db.characters["Forever:Nedisan"].shots[1].zone, "os.exit(1) --]]", "text kept as text")
    levelUp(env, 12)
    env.advance(2)
    eq(#shots(ns), shotsBefore + 1, "recording continues")
    noErrors(ns)
end)

test("v0.10 data page: storage, characters, delete asks with the name", function()
    local env, ns = start()
    levelUp(env, 11)
    env.advance(2)
    ns.db.characters["Forever:Aeloria"] = ns.Database.Load({ schemaVersion = 5, settings = {},
        characters = { ["Forever:Aeloria"] = { name = "Aeloria", realm = "Forever", class = "MAGE",
            shotsByDay = { ["2020-01-01"] = 2 }, shots = { { t = 1, ev = "MANUAL" } }, shotsTotal = 2 } } }).characters["Forever:Aeloria"]
    local storage = ns.Database.Storage(ns.db)
    eq(storage.characters, 2, "characters")
    eq(storage.shots, 2, "records")
    eq(storage.days >= 2, true, "days of both characters")
    local list = ns.DataTools.Characters()
    eq(list[1].current, true, "current first")
    eq(list[2].key, "Forever:Aeloria", "other")
    env.autoConfirm = false
    ns.UI.Toggle("settings")
    findButton(env, "Data"):Click()
    findShownButton(env, "Delete"):Click()
    eq(string.find(env.popups[#env.popups], "Aeloria", 1, true) ~= nil, true, "name in the question")
    eq(ns.db.characters["Forever:Aeloria"] ~= nil, true, "not deleted without an answer")
    eq(ns.DataTools.Delete(ns.characterKey), false, "current character is cleared, not deleted")
    env.autoConfirm = true
    findShownButton(env, "Delete"):Click()
    eq(ns.db.characters["Forever:Aeloria"], nil, "deleted")
    findButton(env, "Delete…"):Click()
    eq(string.find(env.popups[#env.popups], "Nedisan", 1, true) ~= nil, true, "name in the question")
    eq(#shots(ns), 0, "current cleared")
    eq(ns.character.name, "Nedisan", "identity kept")
    eq(type(ns.character.journey.started), "number", "tracking starts again")
    eq(ns.Locations.Total(), 1, "current zone recorded again")
    findButton(env, "Export"):Click()
    eq(string.find(dialogText(), "Nedisan", 1, true) ~= nil, true, "export has the character")
    findButton(env, "Create"):Click()
    eq(string.sub(dialogText(), 1, 5), "FMB1:", "backup text")
    -- Memory in use moved to the diagnostics report (v1.0.0-beta.4).
    eq(string.find(ns.DataTools.DiagnosticsText(), "Unavailable", 1, true) ~= nil, true, "no memory API in the mock")
    _G.GetAddOnMemoryUsage = function() return 248.4 end
    _G.UpdateAddOnMemoryUsage = function() end
    eq(string.find(ns.DataTools.DiagnosticsText(), "248 KB", 1, true) ~= nil, true, "memory in KB")
    noErrors(ns)
end)

test("about: only confirmed facts and links; diagnostics without personal data", function()
    local env, ns = start()
    ns.UI.Toggle("settings")
    findButton(env, "About"):Click()
    eq(hasText(env, "Nedisan"), true, "the approved author")
    eq(hasText(env, "Community and support"), false, "no links while none is confirmed")
    eq(hasText(env, "Copy link"), false, "no links")
    eq(hasText(env, "License"), false, "no invented license")
    local report = ns.DataTools.DiagnosticsText()
    for _, private in ipairs({ "Nedisan", "Forever:", "Player-1-0000ABCD", "Heroes" }) do
        eq(string.find(report, private, 1, true), nil, "no " .. private)
    end
    eq(string.find(report, "1.60.1 (71037)", 1, true) ~= nil, true, "client build")
    eq(string.find(report, "16001", 1, true) ~= nil, true, "interface")
    eq(string.find(report, "Screenshot engine", 1, true) ~= nil, true, "technical lines")
    SlashCmdList.FOREVERMEMORIES("diag") -- the report moved to /fm diag (v1.0.0-beta.4)
    eq(string.find(dialogText(), "ForeverMemories diagnostics", 1, true) ~= nil, true, "copy box")
    ns.ProjectInfo.links[1].url = "https://example.invalid/repo"
    findButton(env, "General"):Click()
    findButton(env, "About"):Click()
    eq(hasText(env, "Copy link"), true, "a set link is shown")
    ns.ProjectInfo.links[1].url = nil
    noErrors(ns)
end)

test("v0.10 changelog: generated from CHANGELOG.md and CHANGELOG.en.md, newest open, what's new mark", function()
    local builder = assert(loadfile("tools/changelog.lua"))("changelog")
    local current = assert(io.open("Modules/ChangelogData.lua")):read("*a")
    eq(builder.Build(".") == current, true, "Modules/ChangelogData.lua is up to date (run lua5.1 tools/changelog.lua)")
    local env, ns = start()
    eq(ns.CHANGELOG[1].version, ns.version, "newest entry is this version")
    eq(ns.CHANGELOG_EN[1].version, ns.version, "the English history too (CHANGELOG.en.md)")
    eq(#ns.CHANGELOG_EN, #ns.CHANGELOG, "both languages have every version")
    eq(ns.UI.WhatsNew(), false, "fresh install: nothing new")
    local saved = ns.db
    saved.ui.seenVersion = "0.9.0"
    local env2, ns2 = start({ savedDB = saved })
    eq(ns2.UI.WhatsNew(), true, "after an update")
    ns2.UI.Toggle("settings")
    findButton(env2, "Changelog"):Click()
    eq(hasText(env2, "v" .. ns2.version), true, "version card")
    local firstKind = ns2.UI.ChangelogList()[1].sections[1].kind
    eq(hasText(env2, ns2.L["CHANGELOG_" .. string.upper(firstKind)]), true, "newest is open")
    eq(ns2.UI.WhatsNew(), false, "seen")
    noErrors(ns2)
end)

test("v0.10 key bindings: four actions, no default keys, safe clean shot", function()
    local xml = assert(io.open("Bindings.xml")):read("*a")
    for _, name in ipairs({ "TOGGLE", "SHOT", "AUTOCAPTURE", "CLEANSHOT" }) do
        eq(string.find(xml, 'name="FOREVERMEMORIES_' .. name .. '"', 1, true) ~= nil, true, name)
    end
    eq(string.find(xml, "default", 1, true), nil, "no default keys")
    local env, ns = start()
    eq(BINDING_NAME_FOREVERMEMORIES_CLEANSHOT, "Take Clean Screenshot", "name in the key bindings menu")
    ForeverMemories_ToggleAutoCapture()
    eq(ns.db.settings.enabled, false, "paused")
    ForeverMemories_ToggleAutoCapture()
    eq(ns.db.settings.enabled, true, "resumed")
    ForeverMemories_CleanShot()
    env.advance(3)
    eq(env.uiShownAtShot, false, "UI hidden for the clean shot")
    eq(UIParent:IsShown(), true, "UI back")
    eq(#shots(ns), 1, "saved")
    eq(ns.db.settings.mode, "normal", "setting not changed")
    env.combat = true
    ForeverMemories_CleanShot()
    env.advance(3)
    eq(env.uiShownAtShot, true, "combat: never hides the UI")
    eq(#shots(ns), 2, "normal shot in combat")
    ForeverMemories_ToggleWindow()
    eq(ns.UI.IsShown(), true, "window")
    noErrors(ns)
end)

test("v0.10 settings pages in Russian: all four build without errors", function()
    local env, ns = start({ locale = "ruRU" })
    ns.UI.Toggle("settings")
    for _, name in ipairs({ "Общие", "Данные", "Об аддоне", "Обновления" }) do
        findButton(env, name):Click()
    end
    findButton(env, "Техническая информация")
    eq(BINDING_NAME_FOREVERMEMORIES_TOGGLE, "Открыть / закрыть ForeverMemories", "binding name")
    noErrors(ns)
end)

---------------------------------------------------------------------------
-- v0.11.0: Location Analytics & Search
---------------------------------------------------------------------------
test("v0.11 zone stats: time, steps, visits per zone; reload, sub-zone, AFK, dungeon", function()
    local env, ns = start()
    local zs = ns.character.zoneStats
    eq(type(zs.since), "number", "tracking start recorded")
    local elwynn = ns.API.ZoneKey()
    eq(zs.zones[elwynn].visits, 1, "arrival at login")
    walk(env, 60)
    near(zs.zones[elwynn].time, 60, 1.5, "active time in the zone")
    near(zs.zones[elwynn].steps, ns.character.steps.total, 0.01, "every step belongs to the zone")
    env.fire("ZONE_CHANGED_NEW_AREA") -- same map: a sub-zone or a repeat
    eq(zs.zones[elwynn].visits, 1, "no new visit inside the same zone")
    env.afk = true
    env.advance(60)
    env.afk = false
    near(zs.zones[elwynn].time, 60, 2.5, "AFK not counted")
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    local westfall = ns.API.ZoneKey()
    eq(zs.zones[westfall].visits, 1, "Westfall visit")
    env.advance(30)
    env.mapID, env.zone = 37, "Elwynn Forest"
    env.fire("ZONE_CHANGED_NEW_AREA")
    eq(zs.zones[elwynn].visits, 2, "coming back is a new visit")
    env.instanceType, env.zone = "party", "The Deadmines"
    env.fire("ZONE_CHANGED_NEW_AREA")
    local before = zs.zones[elwynn].time
    env.advance(30)
    eq(zs.zones[elwynn].time, before, "dungeon time is not given to a zone")
    env.instanceType, env.zone = "none", "Elwynn Forest"
    env.fire("ZONE_CHANGED_NEW_AREA")
    eq(zs.zones[elwynn].visits, 3, "leaving the dungeon is an arrival")
    -- /reload: the same visit goes on.
    local _, ns2 = start({ savedDB = ns.db })
    eq(ns2.character.zoneStats.zones[elwynn].visits, 3, "reload is not a visit")
    noErrors(ns2)
end)

test("v0.11 location card: stats from tracked and existing data, latest shots", function()
    local env, ns = start()
    walk(env, 30)
    ns.Engine.ManualShot()
    env.advance(2)
    levelUp(env, 11)
    env.advance(3)
    local card = ns.ZoneStats.Card(12, 5) -- Elwynn Forest
    eq(card.name, "Elwynn Forest", "name")
    eq(card.region, "Eastern Kingdoms", "continent")
    eq(card.visited, true, "visited")
    eq(card.visits, 1, "visits")
    eq(card.days, 1, "days")
    eq(card.shots, 2, "screenshots from history")
    eq(#card.latest, 2, "latest")
    eq(card.latest[1].ev, "LEVEL", "newest first")
    eq(card.steps, math.floor(ns.Steps.Total()), "steps")
    eq(card.time >= 30, true, "time")
    eq(type(card.firstAt), "number", "first visit")
    eq(card.lastAt >= card.firstAt, true, "last visit")
    local never = ns.ZoneStats.Card(10, 5) -- Duskwood
    eq(never.visited, false, "not visited")
    eq(never.visits, 0, "no visits")
    eq(never.firstAt, nil, "no invented date")
    -- Old data without tracking: no time is invented.
    local old = { schemaVersion = 5, settings = {}, characters = { ["Forever:Nedisan"] = {
        name = "Nedisan", realm = "Forever", visited = { ["map:52"] = true }, visitedAt = { ["map:52"] = 1700000000 },
        locations = { days = { ["2023-11-14"] = { ["map:52"] = { name = "Westfall", t = 1700000000 } } } } } } }
    local db = ns.Database.Load(old)
    eq(db.characters["Forever:Nedisan"].zoneStats, nil, "nothing created by loading")
    ns.UI.Toggle("history")
    ns.UI.ShowTab("history", "zones")
    local row
    for _ = 1, 40 do
        for _, frame in ipairs(env.frames) do
            if rawget(frame, "area") == 12 and frame:IsShown() then row = frame end
        end
        if row then break end
        for _, frame in ipairs(env.frames) do
            if type(rawget(frame, "items")) == "function" then frame:Scroll(-1) end
        end
    end
    eq(row ~= nil, true, "Elwynn row")
    row:Click()
    eq(hasText(env, "<  Back to locations"), true, "card open")
    eq(hasText(env, "Active time here"), true, "time row")
    noErrors(ns)
end)

test("v0.11 screenshot search: text, type, manual/passive, location, dates, order, reset", function()
    local env, ns = start()
    ns.Engine.ManualShot()
    env.advance(2)
    env.fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:11::|h[Purple Axe]|h|r.")
    env.advance(3)
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(3)
    levelUp(env, 11)
    env.advance(3)
    local n = #shots(ns)
    eq(n, 4, "manual, epic, new zone, level")
    local H = ns.History
    local function search(f)
        local filter = { text = "", type = "all", order = "new" }
        for k, v in pairs(f) do filter[k] = v end
        return H.Search(filter)
    end
    eq(#search({}), 4, "all")
    eq(search({})[1].ev, "LEVEL", "newest first")
    eq(search({ order = "old" })[1].ev, "MANUAL", "oldest first")
    eq(#search({ text = "purple" }), 1, "item name")
    eq(#search({ text = "WESTF" }), 2, "zone name, any case")
    eq(#search({ text = "epic" }), 1, "event name")
    eq(#search({ type = "MANUAL" }), 1, "manual")
    eq(#search({ type = "PASSIVE" }), 0, "passive")
    eq(#search({ type = "LEVEL" }), 1, "one type")
    eq(#search({ zone = "Elwynn Forest" }), 2, "location")
    local today = ns.Util.DayKey(ns.API.Time())
    eq(#search({ from = today, to = today }), 4, "today")
    eq(#search({ to = ns.Util.DayBefore(today, 1) }), 0, "before today")
    eq(ns.Util.ParseDate("25.11.2026"), "2026-11-25", "date")
    eq(ns.Util.ParseDate("31.02.2026"), nil, "no such day")
    eq(ns.Util.ParseDate("abc"), nil, "not a date")
    -- Window.
    ns.UI.Toggle("history")
    ns.UI.ShowTab("history", "shots")
    eq(hasText(env, "Found: 4"), true, "count")
    findButton(env, "Filters  >"):Click()
    eq(hasText(env, "All event types"), true, "filters open")
    findButton(env, "All event types"):Click()
    local manual
    for _, frame in ipairs(env.frames) do
        if type(rawget(frame, "text")) == "table" and frame.text.text == "Manual screenshot" and rawget(frame, "value") then
            manual = frame
        end
    end
    manual:Click()
    eq(hasText(env, "Found: 1"), true, "filtered")
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and type(rawget(frame, "label")) == "table" and frame.label.text == "Reset" then
            frame:Click()
        end
    end
    eq(hasText(env, "Found: 4"), true, "reset")
    noErrors(ns)
end)

---------------------------------------------------------------------------
-- v0.12.0: Adventure Records
---------------------------------------------------------------------------
test("v0.12 last adventure: counters, logout end, reload continues, crash marked", function()
    local env = Mock.new()
    local ns = env.login(".")
    walk(env, 60)
    ns.Engine.ManualShot()
    env.advance(3)
    levelUp(env, 11)
    env.advance(5)
    env.mapID, env.zone = 52, "Westfall"
    env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(30)
    local taken = #ns.character.shots
    local steps = math.floor(ns.character.steps.total)
    -- /reload: PLAYER_LOGOUT fires, but the session goes on.
    env.fire("PLAYER_LOGOUT")
    local t1 = ns.API.Time()
    local env2 = Mock.new({ savedDB = ns.db })
    env2.unix = t1 + 20
    env2.mapID, env2.zone = 52, "Westfall"
    local ns2 = env2.login(".")
    eq(ns2.Activity.LastSession(), nil, "reload does not close the session")
    eq(ns2.Activity.Session().ended, nil, "possible end cleared")
    env2.advance(60)
    env2.fire("PLAYER_LOGOUT")
    local logout = ns2.API.Time()
    -- Next evening: the session is closed with the reported end.
    local env3 = Mock.new({ savedDB = ns2.db })
    env3.unix = logout + 5 * 3600
    local ns3 = env3.login(".")
    local last = ns3.Activity.LastSession()
    eq(last ~= nil, true, "closed")
    eq(last.endKnown, true, "end reported by the game")
    eq(last.finish, logout, "end = logout")
    eq(last.shots, taken, "screenshots of the session")
    eq(last.steps, steps, "steps of the session")
    eq(last.zones, 2, "two zones")
    eq(last.levels, 1, "one level")
    near(last.active, 60 + 3 + 5 + 30 + 60, 4, "active time")
    -- A crash: no PLAYER_LOGOUT; the last activity is kept and marked.
    env3.advance(120)
    local lastActive = ns3.Activity.Session().last
    local t3 = ns3.API.Time()
    local env4 = Mock.new({ savedDB = ns3.db })
    env4.unix = t3 + 5 * 3600
    local ns4 = env4.login(".")
    last = ns4.Activity.LastSession()
    eq(last.endKnown, false, "end unknown after a crash")
    eq(last.finish, lastActive, "last activity, not an invented end")
    ns4.UI.Toggle()
    eq(hasText(env4, "Last adventure"), true, "card")
    ns4.UI.TabView("home").LastAdventure:Click()
    eq(hasText(env4, "Last activity"), true, "marked as last activity")
    noErrors(ns4)
end)

test("v0.12 records: best day, first date on a tie, streak, no data", function()
    local env, ns = start()
    local r = ns.Records.Get()
    eq(r.shots.value, nil, "no screenshots yet: no data")
    eq(r.session.value, nil, "no session yet")
    local today = ns.Util.DayKey(ns.API.Time())
    local d = function(n) return ns.Util.DayBefore(today, n) end
    local c = ns.character
    c.steps.days = { [d(5)] = 100, [d(4)] = 300, [d(2)] = 300, [d(1)] = 50 }
    c.shotsByDay = { [d(4)] = 2, [d(2)] = 7 }
    c.playtime.days = { [d(5)] = 600, [d(4)] = 1200 }
    ns.Records.Invalidate()
    r = ns.Records.Get()
    eq(r.steps.value, 300, "most steps") eq(r.steps.day, d(4), "tie keeps the first date")
    eq(r.shots.value, 7, "most shots") eq(r.shots.day, d(2), "its day")
    eq(r.playtime.value, 1200, "most play")
    eq(r.streak.value, 3, "longest run: two days ago, yesterday, today")
    eq(r.streak.day, d(2), "run start") eq(r.streak.last, today, "run end")
    ns.UI.Toggle("history", "records")
    eq(hasText(env, "Personal records"), true, "records view")
    eq(hasText(env, "Most steps in a day"), true, "row")
    noErrors(ns)
end)

test("v0.12 all characters: totals, union of zones, read-only view, back to current", function()
    local env, ns = start()
    walk(env, 30)
    local otherKey = "Other Realm:Thrall"
    local other = ns.Database.Character(ns.db, otherKey, { name = "Thrall", realm = "Other Realm", class = "SHAMAN" })
    other.shotsTotal = 5
    other.steps.total = 1000
    other.playtime.total = 3600
    for key in pairs(ns.character.visited) do
        other.visited[key] = true -- the same zone: counted once
    end
    other.visited["map:999"] = true
    local mine = ns.DataTools.Summary(ns.character)
    local t = ns.DataTools.AccountTotals()
    eq(t.characters, 2, "characters")
    eq(t.shots, mine.shots + 5, "shots summed")
    eq(t.steps, mine.steps + 1000, "steps summed")
    eq(t.zones, mine.zones + 1, "union of zones")
    eq(t.playtime, mine.playtime + 3600, "addon time summed")
    ns.UI.Toggle("history")
    ns.UI.TabView("history").Pick("account") -- beta.10: the character list
    eq(hasText(env, "Saved characters"), true, "list")
    eq(hasText(env, "Time in game"), true, "beta.17: not every character has /played saved")
    local row
    for _, frame in ipairs(env.frames) do
        if rawget(frame, "key") == otherKey then row = frame end
    end
    eq(row ~= nil, true, "row of the other character")
    local current = ns.character
    row:Click()
    eq(hasText(env, "Thrall"), true, "viewed character in the header")
    eq(hasText(env, "Read-only view"), true, "read-only")
    eq(ns.character, current, "current character restored after drawing")
    for _, name in ipairs({ "Overview", "Screenshots", "Steps", "Locations", "Playtime", "Journey", "Records" }) do
        findButton(env, name):Click()
        eq(ns.character, current, "restored after " .. name)
    end
    ns.UI.TabView("history").Pick(ns.characterKey) -- back: choose yourself
    eq(hasText(env, "Read-only view"), false, "back")
    -- Opening the tab again starts with the current character.
    ns.UI.TabView("history").Pick("account")
    ns.UI.ShowTab("home")
    ns.UI.ShowTab("history")
    eq(select(1, ns.UI.TabView("history").Mode()), "character", "reset to the character")
    noErrors(ns)
end)

test("v0.12 history: seven sub-views in two rows, all build in Russian", function()
    local env, ns = start({ locale = "ruRU" })
    ns.UI.Toggle("history")
    for _, name in ipairs({ "Обзор", "Рекорды" }) do
        local button = findButton(env, name)
        eq(button ~= nil, true, name)
        button:Click()
    end
    ns.UI.TabView("history").Pick("account") -- beta.10: «Все персонажи» is in the list
    ns.UI.TabView("history").Pick(ns.characterKey)
    noErrors(ns)
end)

---------------------------------------------------------------------------
-- v0.13.0: Memories & Achievements
---------------------------------------------------------------------------
test("v0.13 on this day: week, month, year ago; no duplicates; hidden when empty", function()
    local env, ns = start()
    local M = ns.Memories
    eq(M.AddMonths("2026-03-31", -1), nil, "31 February does not exist")
    eq(M.AddMonths("2026-03-31", -1, true), "2026-02-28", "clamped")
    eq(M.AddMonths("2024-02-29", -12), nil, "29 February of a non-leap year")
    eq(M.AddMonths("2026-01-15", -1), "2025-12-15", "across a year")
    eq(#M.OnThisDay(), 0, "nothing to remember")
    ns.UI.Toggle("history", "overview")
    eq(hasText(env, "On this day"), false, "block hidden")
    local today = ns.Util.DayKey(ns.API.Time())
    local noon = function(day) return ns.Util.DayStart(day) + 12 * 3600 end
    local week, year = noon(ns.Util.DayBefore(today, 7)), noon(M.AddMonths(today, -12))
    local c = ns.character
    table.insert(c.shots, 1, { t = week, ev = "LEVEL", zone = "Westfall", info = 20 })
    table.insert(c.shots, 2, { t = week + 600, ev = "BOSS", zone = "The Deadmines", info = "Edwin VanCleef" })
    table.insert(c.journey.events, { t = week + 30, kind = "LEVEL", zone = "Westfall", info = 20 })
    table.insert(c.journey.events, { t = year, kind = "LEVEL", zone = "Elwynn Forest", info = 5 })
    M.Invalidate()
    local periods = M.OnThisDay()
    eq(#periods, 2, "week and year, no month")
    eq(periods[1].period, "week", "week first")
    eq(#periods[1].items, 2, "level once (journey), boss shot")
    eq(periods[1].items[2].detail, "Edwin VanCleef", "details kept")
    eq(periods[2].period, "year", "year")
    ns.UI.ShowTab("home")
    ns.UI.ShowTab("history", "overview")
    local seen, label = false, false
    for _ = 1, 20 do
        seen = seen or hasText(env, "On this day")
        label = label or hasText(env, "A week ago")
        for _, frame in ipairs(env.frames) do
            if type(rawget(frame, "items")) == "function" and frame:IsShown() then
                frame:Scroll(-1)
            end
        end
    end
    eq(seen, true, "block shown")
    eq(label, true, "period label")
    noErrors(ns)
end)

test("v0.13 anniversary: week, months, years from the first login; not every day", function()
    local env, ns = start()
    local M = ns.Memories
    local today = ns.Util.DayKey(ns.API.Time())
    local at = function(day) return ns.Util.DayStart(day) + 10 * 3600 end
    local journey = ns.character.journey
    eq(M.Anniversary(), nil, "first day: nothing")
    journey.started = at(ns.Util.DayBefore(today, 7))
    eq(M.Anniversary().kind, "WEEK", "one week")
    journey.started = at(M.AddMonths(today, -3))
    eq(M.Anniversary().kind, "MONTHS3", "three months")
    journey.started = at(M.AddMonths(today, -24))
    local a = M.Anniversary()
    eq(a.kind, "YEAR", "yearly") eq(a.years, 2, "two years")
    journey.started = at(ns.Util.DayBefore(today, 8))
    eq(M.Anniversary(), nil, "an ordinary day")
    for _ = 1, 3 do
        ns.Engine.ManualShot()
        env.advance(5)
    end
    journey.started = at(ns.Util.DayBefore(today, 7))
    ns.UI.Toggle()
    eq(hasText(env, "One week of memories"), true, "card on Home")
    local rows = 0
    for _, frame in ipairs(env.frames) do
        if rawget(frame, "title") and rawget(frame, "time") and frame:IsShown() and frame.title.text == "Manual screenshot" then
            rows = rows + 1
        end
    end
    eq(#ns.History.Today(3), 3, "three shots today")
    eq(rows, 2, "two latest screenshots next to the card")
    noErrors(ns)
end)

test("achievements: progress, earned date, unknown date for old progress, never revoked", function()
    local env, ns = start()
    local function finder(n)
        return function(id)
            for _, a in ipairs(n.Achievements.Get()) do
                if a.def.id == id then return a end
            end
        end
    end
    local get = finder(ns)
    local characterCount, accountCount = 0, 0
    for _, def in ipairs(ns.Achievements.CATALOG.list) do
        if def.scope == "character" then characterCount = characterCount + 1 else accountCount = accountCount + 1 end
    end
    eq(characterCount, 100, "100 character achievements") eq(accountCount, 6, "6 account achievements")
    eq(get("fm.memories.first").done, false, "no shot yet")
    ns.Engine.ManualShot()
    env.advance(3)
    ns.Achievements.Check()
    local first = get("fm.memories.first")
    eq(first.done, true, "first screenshot")
    eq(type(first.at), "number", "date known: earned while playing")
    eq(get("fm.memories.photographer").value, 1, "progress 1")
    eq(get("fm.memories.photographer").target, 100, "of 100")
    -- Progress from before the achievements existed: earned, date unknown.
    local saved = ns.db
    local char = saved.characters[ns.characterKey]
    char.achievements = nil
    char.shotsTotal = 150
    local _, ns2 = start({ savedDB = saved })
    ns2.Achievements.Check()
    local get2 = finder(ns2)
    eq(get2("fm.memories.photographer").done, true, "earned before")
    eq(get2("fm.memories.photographer").at, nil, "date not invented")
    eq(ns2.character.achievements.unlocked["fm.memories.photographer"].src, "seed", "stored as already reached")
    -- Never revoked: a stored achievement stays even if progress is lower.
    ns2.character.achievements.unlocked["fm.memories.keeper"] = { at = 12345, src = "live" }
    ns2.character.shotsTotal = 0
    eq(get2("fm.memories.keeper").done, true, "kept")
    eq(get2("fm.memories.master").done, false, "not earned")
    eq(get2("fm.memories.photographer").done, true, "still earned")
    noErrors(ns2)
end)

test("achievements view: filters and category headings, English and Russian", function()
    for _, locale in ipairs({ "enUS", "ruRU" }) do
        local env, ns = start({ locale = locale })
        ns.UI.Toggle("history", "achievements")
        local names = locale == "enUS" and { "Completed", "In progress", "All" } or { "Выполненные", "В процессе", "Все" }
        for _, name in ipairs(names) do
            local button = findButton(env, name)
            eq(button ~= nil, true, "filter " .. name)
            button:Click()
        end
        eq(hasText(env, ns.L.ACH_CAT_MEMORIES), true, "group heading")
        noErrors(ns)
    end
end)

test("changelog page: only changes of the add-on, no developer words", function()
    local env, ns = start()
    -- Words that belong to development, not to the player: files, modules,
    -- tests, the data schema, the build, function and event names.
    local banned = {
        "%.lua", "%.md", "%.zip", "%.sh", "tools/", "docs/", "Modules/", "Core/", "UI/",
        "[Тт]ест", "%f[%a][Tt]est", "[Сс]хема данных", "[Сс]хемы данных", "[Ss]chema", "[Мм]играци", "[Mm]igration",
        "[Сс]борк", "%f[%a][Bb]uild", "[Дд]окументац", "[Dd]ocumentation", "README", "PROGRESS",
        "SavedVariables", "ForeverMemoriesDB", "API", "GUID", "TTL", "ID AreaTable",
        "%u%l+%.%u%a+%(", "%a+%(%)", "ключ локали", "locale key", "%u%u+_%u%u+",
    }
    local count = 0
    for _, list in ipairs({ ns.CHANGELOG, ns.CHANGELOG_EN }) do
        for _, version in ipairs(list) do
            eq(#version.sections > 0, true, version.version .. " has something to show")
            for _, section in ipairs(version.sections) do
                for _, text in ipairs(section.items) do
                    count = count + 1
                    for _, pattern in ipairs(banned) do
                        if text:find(pattern) then
                            eq(text, nil, version.version .. " shows a developer word (" .. pattern .. ")")
                        end
                    end
                end
            end
        end
    end
    eq(count > 100, true, "the history is still there")
    noErrors(ns)
end)

test("beta.16-17 history: /played of another character and in All characters", function()
    local env, ns = start()
    env.advance(5) -- the game answers /played
    local own = ns.character.playtime
    eq(type(own.played), "table", "the answer is saved")
    near(own.played.total, 125 * 3600 + 30 * 60, 5, "saved /played")
    env.advance(100)
    env.fire("PLAYER_LOGOUT")
    near(own.played.total, 125 * 3600 + 30 * 60 + 100, 5, "updated at logout")

    local other = ns.Database.Character(ns.db, "Other Realm:Thrall", { name = "Thrall", realm = "Other Realm", class = "SHAMAN" })
    other.playtime.total = 600
    other.playtime.played = { total = 2 * 86400 + 3600, at = 1 }
    local fresh = ns.Database.Character(ns.db, "Other Realm:Jaina", { name = "Jaina", realm = "Other Realm", class = "MAGE" })
    fresh.playtime.total = 300
    ns.UI.Toggle("history")
    local view = ns.UI.TabView("history")
    view.Pick("Other Realm:Thrall")
    eq(hasText(env, "Read-only view"), true, "viewing another character")
    eq(hasText(env, "Total playtime"), true, "the same caption as for the current one")
    eq(hasText(env, ns.UI.FormatDuration(2 * 86400 + 3600)), true, "its saved /played")
    eq(hasText(env, "Active play (addon)"), false, "not the addon count")
    view.Pick("Other Realm:Jaina")
    eq(hasText(env, "Active play (addon)"), true, "no /played saved yet: the addon count, named so")
    eq(hasText(env, ns.UI.FormatDuration(300)), true, "its addon count")
    view.Pick(ns.characterKey)
    eq(hasText(env, "Total playtime"), true, "back: the live /played")

    -- beta.17: All characters shows the same numbers as each card.
    view.Pick("account")
    eq(hasText(env, "Time in game"), true, "Jaina has no /played: no \"Total playtime\" on the sum")
    local t = ns.DataTools.AccountTotals()
    eq(t.allGame, false, "not all /played")
    eq(t.lifetime, ns.Activity.Lifetime() + 2 * 86400 + 3600 + 300, "sum of the cards")
    local thrall = ns.DataTools.Summary(other)
    eq(thrall.lifetime, 2 * 86400 + 3600, "Thrall: saved /played") eq(thrall.lifetimeSource, "game", "source")
    local found
    for _, text in ipairs(texts(env)) do
        if text:find(ns.UI.FormatDuration(300) .. " (addon)", 1, true) then found = true end
    end
    eq(found, true, "Jaina's row marks the addon count")
    fresh.playtime.played = { total = 4000, at = 1 }
    view.Refresh()
    eq(hasText(env, "Total playtime"), true, "everyone has /played: the usual caption")

    -- A broken saved value is dropped by validation.
    local db = ns.Database.Load({ schemaVersion = ns.Database.SCHEMA_VERSION, settings = {}, characters = {
        ["R:A"] = { name = "A", realm = "R", playtime = { total = 1, days = {}, played = { total = "x" } } } } })
    eq(db.characters["R:A"].playtime.played, nil, "broken /played removed")
    noErrors(ns)
end)

---------------------------------------------------------------------------
-- v1.0.0-beta.18: achievement chains and the dashboard
---------------------------------------------------------------------------
local function shownText(env, part)
    for _, text in ipairs(texts(env)) do
        if text:find(part, 1, true) then return true end
    end
    return false
end

-- The shown card row whose title starts with `title`.
local function cardRow(env, title)
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and rawget(frame, "dots") and frame:IsShown()
            and frame.title.text:sub(1, #title) == title then
            return frame
        end
    end
end

test("beta.18 catalog: chains are ladders in catalog order", function()
    local env, ns = start()
    local A = ns.Achievements
    local chains, steps = 0, 0
    for id, list in pairs(A.CHAINS) do
        chains = chains + 1
        steps = steps + #list
        eq(#list >= 2, true, id .. ": at least two steps")
        for i = 2, #list do
            eq(list[i].scope, list[1].scope, id .. ": one scope")
            eq(list[i].category, list[1].category, id .. ": one category")
            if list[i].metric == list[i - 1].metric then
                eq(list[i].target > list[i - 1].target, true, id .. ": growing target")
            end
        end
        -- The steps follow each other in the catalog.
        local first
        for i, def in ipairs(A.CATALOG.list) do
            if def == list[1] then first = i end
        end
        for i, def in ipairs(list) do
            eq(A.CATALOG.list[first + i - 1], def, id .. ": steps side by side")
        end
    end
    eq(chains, 24, "24 chains") eq(steps, 76, "76 steps in chains")
    eq(#A.Steps(A.BY_ID["fm.memories.manual"]), 1, "a lone achievement is its own chain")
    local cards = A.Cards(A.Get("character"))
    local accountCards = A.Cards(A.Get("account"))
    eq(#cards + #accountCards, 54, "54 cards instead of 106 rows")
    noErrors(ns)
end)

test("beta.18 cards: current step, earned steps, complete chain", function()
    local env, ns = start()
    local A = ns.Achievements
    local function card(key)
        for _, c in ipairs(A.Cards(A.Get("character"))) do
            if c.key == key then return c end
        end
    end
    local shots = card("memories.shots")
    eq(#shots.steps, 5, "five steps") eq(shots.earned, 0, "nothing yet")
    eq(shots.current.def.id, "fm.memories.first", "first step is the goal") eq(shots.last, nil, "none earned")
    ns.character.shotsTotal = 150
    A.Check()
    shots = card("memories.shots")
    eq(shots.earned, 2, "two steps") eq(shots.current.def.id, "fm.memories.keeper", "goal moved on")
    eq(shots.last.def.id, "fm.memories.photographer", "highest earned")
    eq(shots.complete, false, "not complete")
    ns.character.shotsTotal = 5000
    A.Check()
    shots = card("memories.shots")
    eq(shots.complete, true, "every step") eq(shots.current.def.id, "fm.memories.archive", "last step shown")
    -- Steps unlock one by one even when the counter jumps.
    for _, step in ipairs(shots.steps) do
        eq(ns.character.achievements.unlocked[step.def.id] ~= nil, true, step.def.id .. " stored")
    end
    local d = A.Breakdown(A.Get("character"))
    eq(d.total, 100, "dashboard counts steps") eq(d.categories.memories.done >= 5, true, "category count")
    eq(d.rarities.legendary.done >= 1, true, "rarity count")
    noErrors(ns)
end)

test("beta.18 pins move to the next step; one goal per chain on Home", function()
    local env, ns = start()
    local A = ns.Achievements
    A.Check()
    eq(A.TogglePin("fm.memories.first"), true, "pinned")
    ns.character.shotsTotal = 1
    A.Check()
    eq(A.IsPinned("fm.memories.first"), false, "earned step unpinned")
    eq(A.IsPinned("fm.memories.photographer"), true, "pin moved to the next step")
    -- Two steps of one chain are never two goals.
    ns.db.ui.pins = {}
    ns.character.shotsTotal = 99
    local chains = {}
    for _, g in ipairs(A.Goals(3)) do
        local key = g.achievement.def.chain or g.achievement.def.id
        eq(chains[key], nil, "one goal per chain: " .. key)
        chains[key] = true
    end
    noErrors(ns)
end)

test("beta.18 achievements view: one card per chain, unfold, dashboard, Russian too", function()
    for _, locale in ipairs({ "enUS", "ruRU" }) do
        local env, ns = start({ locale = locale })
        local A, L = ns.Achievements, ns.L
        ns.character.shotsTotal = 1
        A.Check()
        ns.UI.Toggle("history", "achievements")
        local function title(id) return A.Text(A.BY_ID[id], "title") end
        eq(shownText(env, L.ACH_DASH_TITLE), true, "dashboard")
        eq(shownText(env, L.ACH_RARITIES_COMMON), true, "rarities on the dashboard")
        local row = cardRow(env, title("fm.memories.photographer"))
        eq(row ~= nil, true, "the card shows the current step")
        eq(cardRow(env, title("fm.memories.first")), nil, "the earned step is not a card of its own")
        eq(shownText(env, string.format(L.ACH_STEP, 3, 5)), false, "folded")
        row:Click()
        eq(shownText(env, title("fm.memories.keeper")), true, "unfolded: later steps")
        eq(shownText(env, L.ACH_STEP_NOW), true, "the current goal is marked")
        local function stepRows()
            local n = 0
            for _, frame in ipairs(env.frames) do
                if rawget(frame, "tint") and frame:IsShown() then n = n + 1 end
            end
            return n
        end
        eq(stepRows() >= 3, true, "step rows shown")
        cardRow(env, title("fm.memories.photographer")):Click()
        eq(stepRows(), 0, "folded again")
        -- Completed: the highest earned step.
        findButton(env, L.ACH_DONE):Click()
        eq(cardRow(env, title("fm.memories.first")) ~= nil, true, "completed shows the earned step")
        eq(cardRow(env, title("fm.memories.photographer")), nil, "not the goal")
        findButton(env, L.ACH_ALL):Click()
        noErrors(ns)
    end
end)

test("beta.18 dashboard: a category scrolls to its list", function()
    local env, ns = start()
    ns.UI.Toggle("history", "achievements")
    local cell
    for _, frame in ipairs(env.frames) do
        if frame.kind == "Button" and rawget(frame, "category") == "special" and frame:IsShown() then
            cell = frame
        end
    end
    eq(cell ~= nil, true, "category cell")
    cell:Click()
    local scrolled = false
    for _, frame in ipairs(env.frames) do
        if type(rawget(frame, "items")) == "function" and frame:IsShown() and frame:Offset() > 0 then
            scrolled = true
        end
    end
    eq(scrolled, true, "list scrolled")
    noErrors(ns)
end)

test("beta.18 chat names the next step of a chain", function()
    local env, ns = start()
    ns.Achievements.Check()
    ns.Engine.ManualShot()
    env.advance(3)
    ns.Achievements.Check()
    local found = false
    for _, line in ipairs(env.chat) do
        if line:find("Next: Photographer (100)", 1, true) then found = true end
    end
    eq(found, true, "next step in chat")
    noErrors(ns)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
