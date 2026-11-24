-- Capture/Engine.lua
-- Runs one capture request at a time, one screenshot per request:
--   IDLE -> PREPARING -> CAPTURING -> WAIT_RESULT -> IDLE
-- A result counts only from SCREENSHOT_SUCCEEDED / SCREENSHOT_FAILED
-- (confirmed in Forever: async, about 0.08 s, one signal per file).
-- Every timer carries a token; changing state invalidates old timers.
-- Delays, priorities, limits and the queue are internal (spec 5.4).
local _, ns = ...

local Engine = {}
ns.Engine = Engine

Engine.RESULT_TIMEOUT = 5  -- seconds to wait for the result event
Engine.QUARANTINE = 5      -- seconds after a timeout when results are ignored
Engine.SETTLE = 0.05       -- let hidden frames disappear before the shot
Engine.LIMIT_PER_HOUR = 60 -- automatic shots; protects from event storms
Engine.LIMIT_PER_SESSION = 300
Engine.onComplete = {}     -- functions(record or nil, request, result)
Engine.stateListeners = {} -- pause / resume

local API = ns.API
local state = "IDLE"
local token = 0
local active = nil
local inWorld = false
local quarantineUntil = 0
local nextWakeAt = nil
local lastByKey = {}
local autoCalls = {}
local sessionAuto = 0
local session = { calls = 0, saved = 0, unattributed = 0 }

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
    if sessionAuto >= Engine.LIMIT_PER_SESSION then
        return "limit_session"
    end
    if countSince(autoCalls, API.Now() - 3600) >= Engine.LIMIT_PER_HOUR then
        return "limit_hour"
    end
    return nil
end

local function recordCall(request)
    session.calls = session.calls + 1
    if not request.manual then
        sessionAuto = sessionAuto + 1
        autoCalls[#autoCalls + 1] = API.Now()
    end
end

---------------------------------------------------------------------------
-- Finishing
---------------------------------------------------------------------------
local function finishRequest(request, result)
    local record
    if result.status == "success" then
        session.saved = session.saved + 1
        record = ns.History.AddShot(request)
    else
        ns.Logger.Info(table.concat(request.types, "+") .. ": " .. result.status
            .. (result.reason and (" (" .. result.reason .. ")") or ""))
    end
    for _, callback in ipairs(Engine.onComplete) do
        ns.SafeCall("onComplete", callback, record, request, result)
    end
end

local function skip(request, reason)
    finishRequest(request, { status = "skipped", reason = reason })
end

local function complete(status, reason)
    local a = active
    active = nil
    token = token + 1
    state = "IDLE"
    ns.UIState.Restore()
    finishRequest(a.request, { status = status, reason = reason, mode = a.mode })
    Engine.Pump()
end

local function onTimeout()
    quarantineUntil = API.Now() + Engine.QUARANTINE
    ns.Logger.Warn("No screenshot result within " .. Engine.RESULT_TIMEOUT .. " s")
    complete("unconfirmed", "timeout")
end

local function capture()
    local a = active
    if not inWorld then
        return complete("skipped", "loading")
    end
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
        ns.Logger.Error("Screenshot: " .. tostring(reason))
        complete("failed", "error")
    end
end

local function start(request)
    token = token + 1
    active = { request = request }
    if not inWorld then
        return complete("skipped", "loading")
    end
    local limitReason = Engine.LimitReason(request)
    if limitReason then
        return complete("skipped", limitReason)
    end
    state = "PREPARING"
    -- "clean" falls back to "normal" in combat (UIState decides).
    active.mode = ns.UIState.Prepare(request.mode)
    schedule(Engine.SETTLE, capture)
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

-- Entry point for every normalized event {type, key, info, character,
-- zone}. Returns true or false plus a reason.
function Engine.Submit(event)
    if not ns.db or not event.character then
        return false, "not_loaded"
    end
    local now = API.Now()
    local request, reason = ns.Rules.Evaluate(event, ns.db.settings, {
        now = now,
        lastByKey = lastByKey,
        limitReason = Engine.LimitReason,
    })
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
        complete("success")
    else
        complete("failed", "client")
    end
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
    if active and active.mode == "clean" then
        active.mode = "normal"
    end
end

local function cancelAuto(reason)
    for _, request in ipairs(ns.Queue.CancelAuto()) do
        skip(request, reason)
    end
    if active and not active.request.manual and state == "PREPARING" then
        complete("skipped", reason)
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
        complete("skipped", "loading")
    end
end)

-- Pause / resume automatic capture. Manual shots keep working.
-- The Step Tracker does not depend on this switch.
function Engine.SetEnabled(enabled)
    ns.db.settings.enabled = enabled and true or false
    if not enabled then
        cancelAuto("paused")
    end
    for _, listener in ipairs(Engine.stateListeners) do
        ns.SafeCall("state listener", listener)
    end
end

-- Manual shot: the chosen mode and the same safe pipeline.
local manualCount = 0
function Engine.ManualShot()
    if not ns.characterKey then
        return false, "not_loaded"
    end
    manualCount = manualCount + 1
    return Engine.Submit({
        type = "MANUAL",
        key = "manual:" .. manualCount,
        character = ns.characterKey,
        zone = API.ZoneName(),
    })
end
