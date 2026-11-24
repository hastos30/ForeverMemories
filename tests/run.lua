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

local function start(options)
    local env = Mock.new(options)
    local ns = env.login(".")
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
    eq(ns.db.schemaVersion, 4, "schema")
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
    eq(db.schemaVersion, 4, "schema")
    eq(db.settings.enabled, false, "pause kept")
    eq(db.settings.locale, "ruRU", "language kept")
    eq(db.settings.sound, true, "sound kept (it was set)")
    eq(db.settings.minimap, false, "minimap kept")
    eq(db.settings.scale, 1.3, "scale clamped to the new range")
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
    eq(ns.db.extraKey, nil, "unknown key removed")
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
                    "Modules/Passive.lua",
                    "UI/Main.lua", "UI/Capture.lua", "UI/History.lua", "UI/Settings.lua", "UI/Minimap.lua" }
    for _, file in ipairs(files) do
        local text = assert(io.open(file)):read("*a")
        for key in string.gmatch(text, "L%.([%u_][%w_]*)") do
            eq(ns.locales.enUS[key] ~= nil, true, file .. ": L." .. key)
        end
    end
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
    for _, gone in ipairs({ "Events", "Journey", "Profiles", "Diagnostics", "About" }) do
        eq(findButton(env, gone), nil, "no tab " .. gone)
    end
    noErrors(ns)
end)

test("home: statistics cards, last shots, empty message and View all", function()
    local env, ns = start()
    ns.UI.Toggle()
    eq(hasText(env, "This character has no screenshots yet"), true, "empty message")
    levelUp(env, 11)
    env.advance(5)
    walk(env, 10, 7)
    ns.UI.ShowTab("home")
    eq(hasText(env, "Nedisan"), true, "character name")
    eq(hasText(env, "Reached level 11"), true, "recent shot")
    eq(hasText(env, ns.Num(ns.Steps.Today())), true, "steps today")
    findButton(env, "Settings"):Click()
    ns.UI.ShowTab("home")
    for _, frame in ipairs(env.frames) do
        if type(rawget(frame, "label")) == "table" and frame.label.text == "View all screenshots  >" then frame:Click() end
    end
    eq(ns.UI.CurrentTab(), "history", "opens history")
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
    env.advance(4)
    eq(_G.ForeverMemoriesToast:IsShown(), false, "notification gone")
end)

test("slash commands run without errors", function()
    local env, ns = start()
    for _, command in ipairs({ "", "status", "debug", "log", "ui", "reset", "off", "on", "toggle", "shot", "help" }) do
        SlashCmdList.FOREVERMEMORIES(command)
    end
    env.advance(3)
    noErrors(ns)
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

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
