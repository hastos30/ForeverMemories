-- Capture/Engine.lua
-- Runs one capture request at a time (ARCHITECTURE.md section 4):
--   IDLE -> PREPARING -> CAPTURING -> WAIT_RESULT -> RESTORING
--        -> (INTERVAL -> PREPARING ...) -> IDLE
-- A result counts only from SCREENSHOT_SUCCEEDED / SCREENSHOT_FAILED
-- (confirmed in Forever: async, about 0.08 s, one signal per file).
-- Every timer carries a token; changing state invalidates old timers.
local _, ns = ...

local Engine = {}
ns.Engine = Engine

Engine.RESULT_TIMEOUT = 5  -- seconds to wait for the result event
Engine.QUARANTINE = 5      -- seconds after a timeout when results are ignored
Engine.SETTLE = 0.05       -- let hidden frames disappear before the shot
Engine.PAIR_GAP = 0.3      -- between the normal and clean frame of "dual"
Engine.onComplete = {}     -- functions(entry, request)

local API = ns.API
local state = "IDLE"
local token = 0
local active = nil
local inWorld = false
local quarantineUntil = 0
local nextWakeAt = nil
local lastByKey = {}
local autoCalls, journeyCalls = {}, {}
local sessionAuto = 0
local session = { calls = 0, unattributed = 0 }

function Engine.GetState() return state end
function Engine.IsInWorld() return inWorld end
function Engine.QueueSize() return ns.Queue.Size() end
function Engine.Session() return session end
function Engine.IsActive() return active ~= nil end

local function schedule(delay, fn)
    local myToken = token
    API.After(delay, function()
        if myToken == token then
            fn()
        end
    end)
end

---------------------------------------------------------------------------
-- Limits (counted per real Screenshot() call, confirmed or not)
---------------------------------------------------------------------------
local function countSince(list, since)
    while list[1] and list[1] < since do
        table.remove(list, 1)
    end
    return #list
end

function Engine.LimitReason(request)
    if request.manual then
        return nil
    end
    local limits = request.limits
    local now = API.Now()
    if sessionAuto >= limits.perSession then
        return "limit_session"
    end
    if countSince(autoCalls, now - 3600) >= limits.perHour then
        return "limit_hour"
    end
    if request.journey and countSince(journeyCalls, now - 3600) >= limits.journeyPerHour then
        return "limit_journey"
    end
    return nil
end

local function recordCall(request)
    session.calls = session.calls + 1
    if request.manual then
        return
    end
    local now = API.Now()
    sessionAuto = sessionAuto + 1
    autoCalls[#autoCalls + 1] = now
    if request.journey then
        journeyCalls[#journeyCalls + 1] = now
    end
end

---------------------------------------------------------------------------
-- Finishing
---------------------------------------------------------------------------
local function finishRequest(request, result)
    local entry = ns.Journal.Append(request, result)
    if result.ok and result.ok > 0 and ns.character then
        for _, key in ipairs(request.keys) do
            ns.character.firstEvents[key] = true
        end
    end
    for _, callback in ipairs(Engine.onComplete) do
        ns.SafeCall("onComplete", callback, entry, request)
    end
    return entry
end

local function skip(request, reason)
    ns.Logger.Info("Skipped " .. table.concat(request.types, "+") .. ": " .. reason)
    return finishRequest(request, { status = "skipped", skipReason = reason, ok = 0, failed = 0 })
end

local function statusOf(a)
    local attempted = a.ok + a.failed + a.unconfirmed
    if attempted == 0 then
        return "skipped"
    elseif a.ok > 0 and a.failed == 0 and a.unconfirmed == 0 and not a.cancelReason then
        return "success"
    elseif a.ok > 0 then
        return "partial"
    elseif a.unconfirmed > 0 then
        return "unconfirmed"
    end
    return "failed"
end

local complete -- forward declarations
local nextFrame

complete = function()
    local a = active
    active = nil
    token = token + 1
    state = "IDLE"
    ns.UIState.Restore()
    local modes = ns.Util.SortedKeys(a.actualModes)
    finishRequest(a.request, {
        status = statusOf(a),
        skipReason = a.cancelReason,
        ok = a.ok,
        failed = a.failed + a.unconfirmed,
        modeActual = #modes > 0 and table.concat(modes, "+") or nil,
    })
    Engine.Pump()
end

local function afterFrame()
    local a = active
    token = token + 1
    state = "RESTORING"
    ns.UIState.Restore()
    local following = a.plan[a.index + 1]
    if following and not a.cancelReason then
        state = "INTERVAL"
        local gap = following.cycle == a.plan[a.index].cycle and Engine.PAIR_GAP or a.request.interval
        schedule(gap, nextFrame)
    else
        complete()
    end
end

local function onTimeout()
    local a = active
    a.unconfirmed = a.unconfirmed + 1
    a.cancelReason = "timeout"
    quarantineUntil = API.Now() + Engine.QUARANTINE
    ns.Logger.Warn("No screenshot result within " .. Engine.RESULT_TIMEOUT .. " s")
    afterFrame()
end

local function capture()
    local a = active
    state = "CAPTURING"
    schedule(Engine.RESULT_TIMEOUT, onTimeout)
    local ok, reason = API.TakeScreenshot()
    if ok then
        recordCall(a.request)
    end
    if active ~= a or state ~= "CAPTURING" then
        return -- the result already arrived during the call
    end
    if ok then
        state = "WAIT_RESULT"
    else
        a.failed = a.failed + 1
        ns.Logger.Error("Screenshot: " .. tostring(reason))
        afterFrame()
    end
end

nextFrame = function()
    local a = active
    a.index = a.index + 1
    local frame = a.plan[a.index]
    if not frame or a.cancelReason then
        return complete()
    end
    if not inWorld then
        a.cancelReason = "loading"
        return complete()
    end
    local limitReason = Engine.LimitReason(a.request)
    if limitReason then
        a.cancelReason = limitReason
        return complete()
    end
    local mode = ns.Strategies.Resolve(frame, {
        inCombat = API.InCombat(),
        cleanAllowed = ns.db.settings.cleanAllowed,
    })
    if mode == "skip" then
        return nextFrame()
    end
    state = "PREPARING"
    a.frameMode = ns.UIState.Prepare(mode)
    schedule(Engine.SETTLE, capture)
end

local function start(request)
    token = token + 1
    active = {
        request = request,
        plan = ns.Strategies.Plan(request.mode, request.frames),
        index = 0, ok = 0, failed = 0, unconfirmed = 0,
        actualModes = {},
    }
    nextFrame()
end

---------------------------------------------------------------------------
-- Queue processing
---------------------------------------------------------------------------
local function wake(delay)
    local now = API.Now()
    local at = now + math.max(delay, 0.01)
    if nextWakeAt and nextWakeAt > now and nextWakeAt <= at then
        return
    end
    nextWakeAt = at
    API.After(at - now, function()
        nextWakeAt = nil
        Engine.Pump()
    end)
end

function Engine.Pump()
    if state ~= "IDLE" or not ns.db then
        return
    end
    local now = API.Now()
    for _, request in ipairs(ns.Queue.Expire(now)) do
        skip(request, "expired")
    end
    if not inWorld then
        return
    end
    if now < quarantineUntil then
        if ns.Queue.Size() > 0 then
            wake(quarantineUntil - now)
        end
        return
    end
    local request = ns.Queue.PopDue(now)
    if request then
        return start(request)
    end
    local nextDue = ns.Queue.NextDue()
    if nextDue then
        wake(nextDue - now)
    end
end

local function pruneKeys(now)
    local count = 0
    for key, t in pairs(lastByKey) do
        count = count + 1
        if now - t > 300 then
            lastByKey[key] = nil
        end
    end
    return count
end

-- Entry point for every normalized event {type, key, character, zone,
-- mode?, frames?, delay?}. Returns true or false plus a reason.
function Engine.Submit(event)
    if not ns.db then
        return false, "not_loaded"
    end
    local now = API.Now()
    local context = {
        now = now,
        paused = not ns.db.settings.enabled,
        lastByKey = lastByKey,
        isFirst = function(key)
            return not (ns.character and ns.character.firstEvents[key])
        end,
        limitReason = Engine.LimitReason,
    }
    local request, reason = ns.Rules.Evaluate(event, ns.Profiles.Current(), context)
    if not request then
        ns.Logger.Info(event.type .. " ignored: " .. reason)
        return false, reason
    end
    lastByKey[event.key] = now
    if pruneKeys(now) > 500 then
        lastByKey = {}
    end
    local accepted, dropped = ns.Queue.Push(request)
    if dropped then
        skip(dropped, "queue_full")
    end
    Engine.Pump()
    return accepted, not accepted and "queue_full" or nil
end

---------------------------------------------------------------------------
-- Client signals
---------------------------------------------------------------------------
local function onResult(event)
    local a = active
    if not a or (state ~= "CAPTURING" and state ~= "WAIT_RESULT") then
        if event ~= "SCREENSHOT_STARTED" then
            -- Print Screen, a late result or another addon: never ours.
            session.unattributed = session.unattributed + 1
            ns.db.counters.unattributed = ns.db.counters.unattributed + 1
        end
        return
    end
    if event == "SCREENSHOT_STARTED" then
        return
    end
    if event == "SCREENSHOT_SUCCEEDED" then
        a.ok = a.ok + 1
        a.actualModes[a.frameMode] = true
    else
        a.failed = a.failed + 1
    end
    afterFrame()
end

-- If the client ever blocks one of our calls, say so in the log.
local function onBlocked(event, addon, func)
    if addon == ns.name then
        ns.Logger.Error(event .. ": " .. tostring(func))
    end
end
ns.On("ADDON_ACTION_BLOCKED", onBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)

ns.On("SCREENSHOT_STARTED", onResult)
ns.On("SCREENSHOT_SUCCEEDED", onResult)
ns.On("SCREENSHOT_FAILED", onResult)

-- Combat started while the UI was hidden: the frame becomes "normal".
function Engine.OnUIRestoredByCombat()
    if active and active.frameMode == "clean" then
        active.frameMode = "normal"
    end
end

local function cancelAuto(reason)
    for _, request in ipairs(ns.Queue.CancelAuto()) do
        skip(request, reason)
    end
    if active and not active.request.manual then
        active.cancelReason = reason
    end
end

ns.On("PLAYER_ENTERING_WORLD", function()
    inWorld = true
    Engine.Pump()
end)

ns.On("PLAYER_LEAVING_WORLD", function()
    inWorld = false
    cancelAuto("loading")
    if active then
        active.cancelReason = active.cancelReason or "loading"
        complete()
    end
end)

-- Pause / resume automatic capture. Manual shots keep working.
function Engine.SetEnabled(enabled)
    ns.db.settings.enabled = enabled and true or false
    if not enabled then
        cancelAuto("paused")
    end
    for _, listener in ipairs(Engine.stateListeners) do
        ns.SafeCall("state listener", listener)
    end
end
Engine.stateListeners = {}

---------------------------------------------------------------------------
-- Manual shots (optional countdown timer)
---------------------------------------------------------------------------
local manualCount = 0
local countdownToken = 0
local countdownActive = false

function Engine.SubmitManual(options)
    options = options or {}
    manualCount = manualCount + 1
    return Engine.Submit({
        type = "MANUAL",
        key = "manual:" .. manualCount,
        character = ns.characterKey,
        zone = API.ZoneName(),
        mode = options.mode,
        frames = options.frames,
    })
end

-- Starts the countdown from settings (0 = immediately).
function Engine.ManualShot(options)
    local seconds = (options and options.timer) or ns.db.settings.manualTimer
    if seconds <= 0 then
        return Engine.SubmitManual(options)
    end
    countdownToken = countdownToken + 1
    countdownActive = true
    local myToken = countdownToken
    for remaining = seconds, 1, -1 do
        API.After(seconds - remaining, function()
            if myToken == countdownToken then
                API.Print(remaining .. "...")
            end
        end)
    end
    API.After(seconds, function()
        if myToken == countdownToken then
            countdownActive = false
            Engine.SubmitManual(options)
        end
    end)
    return true
end

function Engine.IsCountingDown()
    return countdownActive
end

function Engine.CancelCountdown()
    if not countdownActive then
        return false
    end
    countdownToken = countdownToken + 1
    countdownActive = false
    return true
end
