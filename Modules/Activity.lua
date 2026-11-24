-- Modules/Activity.lua
-- The one clock of active play (v0.8.0). Every second it measures how much
-- of the last tick was active play and hands that to its listeners:
--   * the Playtime Tracker (this file): "Playtime today" on Home;
--   * the passive capture timer (Modules/Passive.lua);
--   * the Home countdown (UI), which only redraws, never counts.
-- So there is one ticker and one definition of "active" for both.
--
-- Active play = in the world (no loading screen) and not AFK. Time outside
-- the game is never counted: the clock is GetTime() deltas inside a
-- session, and a gap longer than MAX_GAP (loading, hitch) adds nothing.
-- Playtime is saved per character and per calendar day (local midnight
-- starts a new day), so it survives /reload and logout.
local _, ns = ...

local Activity = {}
ns.Activity = Activity

Activity.TICK = 1     -- seconds between checks
Activity.MAX_GAP = 5  -- longer gaps between ticks are not counted

-- listener(activeSeconds, reason): reason is nil while playing,
-- "loading" or "afk" otherwise (activeSeconds is 0 then).
Activity.listeners = {}

local API = ns.API
local ticker
local lastTickAt
local inWorld = false

local function data()
    return ns.character and ns.character.playtime
end

-- Why the current moment is not active play, or nil.
function Activity.BlockReason()
    if not inWorld then
        return "loading"
    end
    if API.IsAFK() then
        return "afk"
    end
    return nil
end

-- Adds seconds of play to the day of `t` and to the total.
function Activity.Add(seconds, t)
    local playtime = data()
    if not playtime or seconds <= 0 then
        return
    end
    local day = ns.Util.DayKey(t or API.Time())
    playtime.days[day] = (playtime.days[day] or 0) + seconds
    playtime.total = playtime.total + seconds
end

-- One check. `now` is GetTime().
function Activity.Tick(now)
    local dt = lastTickAt and (now - lastTickAt) or 0
    lastTickAt = now
    local reason = Activity.BlockReason()
    local active = 0
    if not reason and dt > 0 and dt <= Activity.MAX_GAP then
        active = dt
        Activity.Add(active)
    end
    for i = 1, #Activity.listeners do
        ns.SafeCall("activity listener", Activity.listeners[i], active, reason)
    end
end

local function tick()
    ns.SafeCall("activity", Activity.Tick, API.Now())
end

function Activity.Start()
    if ticker then
        return
    end
    lastTickAt = nil
    ticker = API.NewTicker(Activity.TICK, tick)
end

-- Whole seconds of play of the current character today / on a day.
function Activity.OnDay(day)
    local playtime = data()
    return playtime and math.floor(playtime.days[day] or 0) or 0
end

function Activity.Today()
    return Activity.OnDay(ns.Util.DayKey(API.Time()))
end

-- Calendar days on which this character played: any playtime, steps,
-- screenshots or visited zones (days before v0.8.0 come from steps and
-- screenshots, playtime was not recorded then).
function Activity.DaysPlayed()
    local character = ns.character
    if not character then
        return 0
    end
    local seen, count = {}, 0
    local function add(map)
        for day, value in pairs(map or {}) do
            if not seen[day] and (type(value) == "table" or value > 0) then
                seen[day] = true
                count = count + 1
            end
        end
    end
    add(character.playtime and character.playtime.days)
    add(character.steps and character.steps.days)
    add(character.shotsByDay)
    add(character.locations and character.locations.days)
    return count
end

-- A loading screen breaks the chain: its time is not counted.
ns.On("PLAYER_ENTERING_WORLD", function()
    inWorld = true
    lastTickAt = nil
end)
ns.On("PLAYER_LEAVING_WORLD", function()
    inWorld = false
    lastTickAt = nil
end)

table.insert(ns.onLogin, Activity.Start)
