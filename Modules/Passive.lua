-- Modules/Passive.lua
-- Passive capture: one screenshot after every N minutes of active play
-- (N = 15, 30, 45 or 60; account setting). It only measures time and asks
-- the Engine for a shot: mode, queue, duplicate protection, limits,
-- loading screens and history are the same as for game events.
--
-- Active time is counted only while all of these hold:
--   in the world (no loading screen), passive capture on, automatic
--   capture not paused, the character is not AFK.
-- Time outside the game is never counted: the clock is GetTime() deltas
-- inside a session, and a gap longer than MAX_GAP (loading, hitch) adds
-- nothing. The counted time is saved per character (character.passive),
-- so it survives /reload and logout.
--
-- When the interval is reached the timer stops at "due" (missed intervals
-- never stack up into several shots). In combat the shot waits for the
-- end of combat. A new interval setting restarts the count.
local _, ns = ...

local Passive = {}
ns.Passive = Passive

Passive.TICK = 1        -- seconds between checks
Passive.MAX_GAP = 5     -- longer gaps between ticks are not counted
Passive.RETRY = 60      -- seconds to wait when the Engine refused the shot
Passive.INTERVALS = { 15, 30, 45, 60 } -- minutes, the only allowed values

local API = ns.API
local ticker
local lastTickAt
local inWorld = false
local state = "-"

local function data()
    return ns.character and ns.character.passive
end

-- Seconds of active play needed for one shot.
function Passive.DueSeconds()
    return ns.db.settings.passiveInterval * 60
end

-- Why time is not counted right now, or nil.
local function blockReason(settings)
    if not inWorld then
        return "loading"
    end
    if not settings.passive then
        return "off"
    end
    if not settings.enabled then
        return "paused"
    end
    if API.IsAFK() then
        return "afk"
    end
    return nil
end

local function submit(p, due)
    local accepted, reason = ns.Engine.Submit({
        type = "PASSIVE",
        key = "passive",
        character = ns.characterKey,
        zone = API.ZoneName(),
    })
    if accepted then
        p.elapsed = 0
        state = "submitted"
    else
        -- Try again a bit later instead of every second.
        p.elapsed = math.max(0, due - Passive.RETRY)
        state = "refused:" .. tostring(reason)
    end
end

-- One check. `now` is GetTime().
function Passive.Tick(now)
    local dt = lastTickAt and (now - lastTickAt) or 0
    lastTickAt = now
    local p = data()
    if not p or not ns.db then
        return
    end
    local settings = ns.db.settings
    if p.interval ~= settings.passiveInterval then
        -- New interval (also chosen on another character): start again.
        p.interval = settings.passiveInterval
        p.elapsed = 0
    end
    local reason = blockReason(settings)
    if reason then
        state = reason
        return
    end
    local due = Passive.DueSeconds()
    if dt > 0 and dt <= Passive.MAX_GAP then
        p.elapsed = math.min(p.elapsed + dt, due)
    end
    if p.elapsed < due then
        state = "counting"
        return
    end
    if API.InCombat() then
        state = "combat"
        return
    end
    submit(p, due)
end

local function tick()
    ns.SafeCall("passive", Passive.Tick, API.Now())
end

function Passive.Start()
    if ticker then
        return
    end
    lastTickAt = nil
    ticker = API.NewTicker(Passive.TICK, tick)
end

-- For /fm debug: state, counted seconds, needed seconds.
function Passive.Status()
    local p = data()
    return state, p and p.elapsed or 0, ns.db and Passive.DueSeconds() or 0
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

table.insert(ns.onLogin, Passive.Start)
