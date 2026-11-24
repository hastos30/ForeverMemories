-- Modules/Steps.lua
-- Step Tracker: estimated steps of the current character (spec section 6).
-- Independent from auto capture: pause does not stop it, and an error in
-- one module never stops the other (every tick runs in its own pcall).
--
-- Model: steps = measured ground distance in meters / 1.5.
-- Positions and speeds come in yards (1 yard = 0.9144 m).
--
-- Every TICK seconds:
--   1. Skip and drop the anchor if the movement must not count (taxi,
--      vehicle, flying, swimming), if the player is not moving on their
--      own (own speed 0: standing on a boat or a zeppelin), or if the
--      client state is unknown (a needed function is missing or secret).
--   2. Read the world position. Distance is measured only between two
--      positions of the same coordinate space (same instance/continent).
--   3. A jump longer than own speed allows (teleport, hearthstone, boat
--      moving under you, loading) drops the anchor and counts nothing.
--   4. No position (e.g. instances): steps from own speed x time, only if
--      the exclusions in step 1 are known. Nothing is invented otherwise.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

Steps.TICK = 0.5              -- seconds between measurements
Steps.STEP_METERS = 1.5       -- one running stride in game (v0.5.1; was 0.75)
Steps.YARD_METERS = 0.9144
Steps.SPEED_SLACK = 1.5       -- measured distance may exceed speed x time by 50 %
Steps.MIN_ALLOWANCE = 1       -- yards, for rounding and turns
Steps.MAX_GAP = 2 * Steps.TICK -- longer gaps (hitch, loading) are not counted
Steps.MAX_ERRORS = 10          -- the tracker stops after this many errors

Steps.listeners = {}           -- called when today's whole number changes

local API = ns.API
local ticker
local anchor                   -- { space, x, y }
local lastTickAt
local errors = 0
local status = { source = "-", reason = "-" }
local inWorld = false

local function yardsToSteps(yards)
    return yards * Steps.YARD_METERS / Steps.STEP_METERS
end
Steps.YardsToSteps = yardsToSteps

local function data()
    return ns.character and ns.character.steps
end

-- Adds steps to the day of `t` and to the total. Fractions are kept, the
-- interface shows whole numbers.
function Steps.Add(amount, t)
    local steps = data()
    if not steps or amount <= 0 then
        return
    end
    local day = ns.Util.DayKey(t or API.Time())
    local before = math.floor(steps.days[day] or 0)
    steps.days[day] = (steps.days[day] or 0) + amount
    steps.total = steps.total + amount
    steps.since = steps.since or (t or API.Time())
    if math.floor(steps.days[day]) ~= before then
        for _, listener in ipairs(Steps.listeners) do
            ns.SafeCall("steps listener", listener)
        end
    end
end

function Steps.Reset(reason)
    anchor = nil
    status.reason = reason or status.reason
end

-- One measurement. `now` is GetTime(); returns the steps added (for tests).
function Steps.Measure(now)
    local dt = lastTickAt and (now - lastTickAt) or 0
    lastTickAt = now
    if not inWorld or not data() then
        return Steps.Reset("loading")
    end
    local exclusion = API.MovementExclusion()
    if exclusion then
        return Steps.Reset(exclusion)
    end
    local speed = API.UnitSpeed()
    if not speed then
        return Steps.Reset("no_speed")
    end
    local space, x, y, source = API.WorldPosition()
    if speed <= 0 then
        -- Standing, or carried by a boat / zeppelin / platform.
        anchor = space and { space = space, x = x, y = y } or nil
        status.reason = "idle"
        return
    end
    if dt <= 0 or dt > Steps.MAX_GAP then
        anchor = space and { space = space, x = x, y = y } or nil
        status.reason = "gap"
        return
    end
    local yards
    if space then
        status.source = source
        if anchor and anchor.space == space then
            local dx, dy = x - anchor.x, y - anchor.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance <= speed * dt * Steps.SPEED_SLACK + Steps.MIN_ALLOWANCE then
                yards = distance
                status.reason = "ok"
            else
                status.reason = "jump"
            end
        else
            status.reason = "new_anchor"
        end
        anchor = { space = space, x = x, y = y }
    else
        -- No coordinates here: own speed x time (exclusions are known).
        anchor = nil
        yards = speed * dt
        status.source = "speed"
        status.reason = "ok"
    end
    if yards and yards > 0 then
        local amount = yardsToSteps(yards)
        Steps.Add(amount)
        return amount
    end
end

local function tick()
    local ok, err = pcall(Steps.Measure, API.Now())
    if not ok then
        errors = errors + 1
        anchor = nil
        ns.Logger.Error("Steps: " .. tostring(err))
        if errors >= Steps.MAX_ERRORS and ticker then
            ticker:Cancel()
            ticker = nil
            ns.Logger.Error("Steps: stopped after " .. errors .. " errors")
        end
    end
end

function Steps.Start()
    if ticker then
        return
    end
    lastTickAt, anchor = nil, nil
    ticker = API.NewTicker(Steps.TICK, tick)
end

function Steps.IsRunning()
    return ticker ~= nil
end

function Steps.Status()
    return status.source, status.reason, errors
end

-- Whole steps of the current character today / in total.
function Steps.Today()
    local steps = data()
    return steps and math.floor(steps.days[ns.Util.DayKey(API.Time())] or 0) or 0
end

function Steps.Total()
    local steps = data()
    return steps and math.floor(steps.total) or 0
end

-- Whole steps of a day key (0 for a day without records).
function Steps.OnDay(day)
    local steps = data()
    return steps and math.floor(steps.days[day] or 0) or 0
end

-- Days that have records, newest first: { { day, steps }, ... }.
function Steps.Days()
    local list = {}
    local steps = data()
    if steps then
        for day, value in pairs(steps.days) do
            list[#list + 1] = { day = day, steps = math.floor(value) }
        end
    end
    table.sort(list, function(a, b) return a.day > b.day end)
    return list
end

-- Loading screens, teleports and map changes break the chain.
ns.On("PLAYER_ENTERING_WORLD", function()
    inWorld = true
    Steps.Reset("loading")
end)
ns.On("PLAYER_LEAVING_WORLD", function()
    inWorld = false
    Steps.Reset("loading")
end)
ns.On("ZONE_CHANGED_NEW_AREA", function() Steps.Reset("zone") end)

table.insert(ns.onLogin, Steps.Start)
