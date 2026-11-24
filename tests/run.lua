-- tests/run.lua
-- Run from the addon root:  lua5.1 tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local Mock = require("mock_wow")

local ROOT = "."
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
        error(string.format("%s: expected %s, got %s", what or "value",
            tostring(expected), tostring(actual)), 2)
    end
end

-- Builds a fresh client, loads the addon and enters the world.
local function start(options)
    local env = Mock.new(options)
    local ns = env.loadAddon(ROOT)
    env.fire("ADDON_LOADED", "ForeverMemories")
    if not (options and options.stayLoading) then
        env.fire("PLAYER_ENTERING_WORLD")
    end
    return env, ns
end

local function lastShot(ns)
    local shots = ns.db.spike.shots
    return shots[#shots]
end

test("fresh install creates defaults (T01)", function()
    local _, ns = start()
    eq(ns.db.schemaVersion, 1, "schemaVersion")
    eq(ns.db.spike.loadCount, 1, "loadCount")
    eq(#ns.db.spike.probes, 1, "probe saved")
end)

test("loadCount grows on reload (SavedVariables check)", function()
    local _, ns = start({ savedDB = { schemaVersion = 1, spike = { loadCount = 4 } } })
    eq(ns.db.spike.loadCount, 5, "loadCount")
end)

test("corrupted saved data is repaired (T24)", function()
    local _, ns = start({ savedDB = { schemaVersion = "x", spike = { shots = 7, loadCount = "?" } } })
    eq(ns.db.schemaVersion, 1, "schemaVersion")
    eq(type(ns.db.spike.shots), "table", "shots")
    eq(ns.db.spike.loadCount, 1, "loadCount")
    eq(_G.ForeverMemoriesDB, ns.db, "global points to repaired table")
end)

test("synchronous success is recorded once (T02)", function()
    local _, ns = start()
    assert(ns.ManualShot.Request())
    local shot = lastShot(ns)
    eq(shot.status, "success", "status")
    eq(shot.synchronous, true, "synchronous")
    eq(shot.sawStarted, true, "sawStarted")
    eq(ns.db.spike.screenshotCalls, 1, "calls")
    eq(ns.ManualShot.GetState(), "IDLE", "state")
end)

test("asynchronous success", function()
    local env, ns = start({ screenshotMode = "async" })
    assert(ns.ManualShot.Request())
    eq(ns.ManualShot.GetState(), "WAIT_RESULT", "state while waiting")
    env.advance(0.3)
    env.fire("SCREENSHOT_SUCCEEDED")
    eq(lastShot(ns).status, "success", "status")
    eq(lastShot(ns).synchronous, false, "synchronous")
end)

test("SCREENSHOT_FAILED gives failed status", function()
    local _, ns = start({ screenshotMode = "sync_failed" })
    assert(ns.ManualShot.Request())
    eq(lastShot(ns).status, "failed", "status")
end)

test("Lua error in Screenshot gives error status, state restored (T14)", function()
    local _, ns = start({ screenshotMode = "error" })
    assert(ns.ManualShot.Request())
    eq(lastShot(ns).status, "error", "status")
    eq(ns.ManualShot.GetState(), "IDLE", "state")
    eq(ns.db.spike.screenshotCalls, 0, "calls")
end)

test("no result: timeout, unconfirmed, no retry (T15)", function()
    local env, ns = start({ screenshotMode = "silent" })
    assert(ns.ManualShot.Request())
    env.advance(5)
    eq(lastShot(ns).status, "unconfirmed", "status")
    eq(#ns.db.spike.shots, 1, "only one entry")
    eq(ns.db.spike.screenshotCalls, 1, "one call, no retry")
end)

test("late result after timeout is not attributed (T16)", function()
    local env, ns = start({ screenshotMode = "silent" })
    assert(ns.ManualShot.Request())
    env.advance(5)
    env.fire("SCREENSHOT_SUCCEEDED")
    eq(lastShot(ns).status, "unconfirmed", "status unchanged")
    eq(ns.db.spike.unattributedResults, 1, "unattributed")
    local ok, reason = ns.ManualShot.Request()
    eq(ok, false, "quarantine refuses")
    assert(reason:find("unconfirmed"), reason)
    env.advance(5)
    eq((ns.ManualShot.Request()), true, "allowed after quarantine")
end)

test("old timer does not finish a newer request (generation token)", function()
    local env, ns = start({ screenshotMode = "async" })
    assert(ns.ManualShot.Request())
    env.advance(1)
    env.fire("SCREENSHOT_SUCCEEDED")          -- shot 1 done at t=1
    assert(ns.ManualShot.Request())           -- shot 2, timer due at t=6
    env.advance(4.5)                          -- t=5.5: shot 1 timer fires
    eq(ns.ManualShot.GetState(), "WAIT_RESULT", "shot 2 still waiting")
    env.fire("SCREENSHOT_SUCCEEDED")
    eq(lastShot(ns).status, "success", "shot 2 status")
    eq(#ns.db.spike.shots, 2, "two entries")
end)

test("second request while busy is refused", function()
    local _, ns = start({ screenshotMode = "async" })
    assert(ns.ManualShot.Request())
    local ok, reason = ns.ManualShot.Request()
    eq(ok, false, "refused")
    assert(reason:find("busy"), reason)
end)

test("no shot during loading screen (T13)", function()
    local env, ns = start({ stayLoading = true })
    local ok, reason = ns.ManualShot.Request()
    eq(ok, false, "refused")
    eq(reason, "loading screen", "reason")
    env.fire("PLAYER_ENTERING_WORLD")
    env.fire("PLAYER_LEAVING_WORLD")
    eq((ns.ManualShot.Request()), false, "refused after leaving world")
end)

test("native screenshot is counted but not attributed (T28)", function()
    local env, ns = start()
    env.fire("SCREENSHOT_STARTED")
    env.fire("SCREENSHOT_SUCCEEDED")
    eq(#ns.db.spike.shots, 0, "no entry")
    eq(ns.db.spike.unattributedResults, 1, "unattributed")
end)

test("unknown event is rejected without a Lua error (T26)", function()
    local _, ns = start({ unknownEvents = { ENCOUNTER_END = true } })
    eq(ns.Probe.last.events.ENCOUNTER_END, "rejected: unknown event", "status")
    eq(ns.Probe.last.events.PLAYER_LEVEL_UP, "registered", "status")
end)

test("shot history is capped at 50", function()
    local env, ns = start()
    for _ = 1, 60 do
        assert(ns.ManualShot.Request())
        env.advance(0.1)
    end
    eq(#ns.db.spike.shots, 50, "capped")
    eq(lastShot(ns).id, 60, "newest kept")
end)

test("logger keeps only the last 200 lines", function()
    local _, ns = start()
    for i = 1, 250 do ns.Logger.Info("line " .. i) end
    eq(ns.Logger.Count(), 200, "count")
    local recent = ns.Logger.Recent(2)
    eq(recent[1].msg, "line 249", "older first")
    eq(recent[2].msg, "line 250", "newest last")
end)

test("slash commands run without errors", function()
    local env, ns = start()
    ns.ManualShot.Request()
    for _, cmd in ipairs({ "shot", "status", "debug", "log", "", "nonsense" }) do
        SlashCmdList.FOREVERMEMORIES(cmd)
    end
    assert(#env.chat > 10, "printed output")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
