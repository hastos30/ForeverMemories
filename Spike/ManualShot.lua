-- Spike/ManualShot.lua
-- One manual screenshot at a time, with a result taken only from a client
-- signal (SCREENSHOT_SUCCEEDED / SCREENSHOT_FAILED) or else "unconfirmed".
--
-- States (subset of ARCHITECTURE.md section 4):
--   IDLE -> CAPTURING -> WAIT_RESULT -> IDLE
-- CAPTURING lasts only while Screenshot() runs; if the client fires the
-- result event during the call, we record it as a synchronous result.
local _, ns = ...

local Shot = {}
ns.ManualShot = Shot

Shot.RESULT_TIMEOUT = 5  -- seconds to wait for a result event
Shot.QUARANTINE = 5      -- seconds after a timeout when results are ignored

local state = "IDLE"
local generation = 0       -- increases with each request; old timers check it
local current = nil        -- the active request, or nil
local inWorld = false      -- false during loading screens
local quarantineUntil = 0

function Shot.GetState()
    return state
end

local function finish(status, detail)
    local request = current
    current = nil
    state = "IDLE"

    local spike = ns.db.spike
    local entry = {
        id = request.id,
        t = request.t,
        status = status,               -- success | failed | unconfirmed | error
        detail = detail,
        seconds = ns.API.Now() - request.started,
        synchronous = request.synchronous,
        sawStarted = request.sawStarted,
        inCombat = request.inCombat,
    }
    ns.Database.AppendCapped(spike.shots, entry, ns.Database.MAX_SHOTS)

    if status == "unconfirmed" then
        quarantineUntil = ns.API.Now() + Shot.QUARANTINE
    end
    local text = string.format("Shot #%d: %s (%.2f s)%s", entry.id, status, entry.seconds,
        detail and (" - " .. detail) or "")
    ns.Logger.Info(text)
    ns.API.Print(text)
    return entry
end

-- Returns true when a screenshot was requested, or false plus a reason.
function Shot.Request()
    if not ns.db then
        return false, "not loaded"
    end
    if state ~= "IDLE" then
        return false, "busy (" .. state .. ")"
    end
    if not inWorld then
        return false, "loading screen"
    end
    if ns.API.Now() < quarantineUntil then
        return false, "waiting after an unconfirmed shot"
    end

    local spike = ns.db.spike
    generation = generation + 1
    local myGeneration = generation
    current = {
        id = spike.nextShotId,
        generation = myGeneration,
        t = ns.API.Time(),
        started = ns.API.Now(),
        inCombat = ns.API.InCombat(),
        synchronous = false,
        sawStarted = false,
    }

    -- Start the timeout before the call: if the timer API is missing we
    -- refuse, so a request can never hang forever.
    local timerOk, timerReason = ns.API.After(Shot.RESULT_TIMEOUT, function()
        if current and current.generation == myGeneration then
            finish("unconfirmed", "no result event within " .. Shot.RESULT_TIMEOUT .. " s")
        end
    end)
    if not timerOk then
        current = nil
        return false, timerReason
    end
    spike.nextShotId = spike.nextShotId + 1

    state = "CAPTURING"
    local ok, reason = ns.API.TakeScreenshot()
    if ok then
        spike.screenshotCalls = spike.screenshotCalls + 1
    end
    if current and current.generation == myGeneration then
        if ok then
            state = "WAIT_RESULT"
        else
            finish("error", reason)
        end
    end
    return true
end

local function onResult(event)
    if not ns.db then
        return
    end
    if not current then
        if event == "SCREENSHOT_STARTED" then
            return
        end
        -- No request of ours is active: a native Print Screen, a late
        -- result after a timeout, or another addon. Never attribute it.
        ns.db.spike.unattributedResults = ns.db.spike.unattributedResults + 1
        local why = ns.API.Now() < quarantineUntil and "late result after timeout" or "not ours"
        ns.Logger.Warn(event .. " ignored: " .. why)
        return
    end
    if event == "SCREENSHOT_STARTED" then
        current.sawStarted = true
        return
    end
    current.synchronous = (state == "CAPTURING")
    if event == "SCREENSHOT_SUCCEEDED" then
        finish("success")
    else
        finish("failed", "SCREENSHOT_FAILED")
    end
end

ns.On("SCREENSHOT_STARTED", onResult)
ns.On("SCREENSHOT_SUCCEEDED", onResult)
ns.On("SCREENSHOT_FAILED", onResult)
ns.On("PLAYER_ENTERING_WORLD", function() inWorld = true end)
ns.On("PLAYER_LEAVING_WORLD", function() inWorld = false end)
