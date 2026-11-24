-- Modules/Passive.lua
-- Passive capture: one screenshot after every N minutes of active play
-- (N = 15, 30, 45 or 60; account setting). It only measures time and asks
-- the Engine for a shot: mode, queue, duplicate protection, limits,
-- loading screens and history are the same as for game events.
--
-- Since v0.8.0 the time comes from the shared clock of active play
-- (Modules/Activity.lua, the same one as "Playtime today"). On top of
-- "in the world and not AFK" this timer also needs:
--   passive capture on, automatic capture not paused.
-- The counted time is saved per character (character.passive), so it
-- survives /reload and logout.
--
-- When the interval is reached the timer stops at "due" (missed intervals
-- never stack up into several shots). In combat the shot waits for the
-- end of combat. A new interval setting restarts the count.
local _, ns = ...

local Passive = {}
ns.Passive = Passive

Passive.RETRY = 60      -- seconds to wait when the Engine refused the shot
Passive.INTERVALS = { 15, 30, 45, 60 } -- minutes, the only allowed values

local API = ns.API
local state = "-"
local retrying = false  -- the Engine refused the last shot; a retry is pending

local function data()
    return ns.character and ns.character.passive
end

-- Seconds of active play needed for one shot.
function Passive.DueSeconds()
    return ns.db.settings.passiveInterval * 60
end

-- Why time is not counted right now, or nil. `activity` is the reason
-- from the shared clock ("loading", "afk") or nil.
local function blockReason(settings, activity)
    if activity == "loading" then
        return "loading"
    end
    if not settings.passive then
        return "off"
    end
    if not settings.enabled then
        return "paused"
    end
    return activity
end

local function submit(p, due)
    local accepted, reason = ns.Engine.Submit({
        type = "PASSIVE",
        key = "passive",
        character = ns.characterKey,
        zone = API.ZoneName(),
    })
    retrying = not accepted
    if accepted then
        p.elapsed = 0
        state = "submitted"
    else
        -- Try again a bit later instead of every second.
        p.elapsed = math.max(0, due - Passive.RETRY)
        state = "refused:" .. tostring(reason)
    end
end

-- Called by the shared clock every second with the seconds of active
-- play since the last call and the reason when there were none.
function Passive.Update(active, activity)
    local p = data()
    if not p or not ns.db then
        return
    end
    local settings = ns.db.settings
    if p.interval ~= settings.passiveInterval then
        -- New interval (also chosen on another character): start again.
        p.interval = settings.passiveInterval
        p.elapsed = 0
        retrying = false
    end
    local reason = blockReason(settings, activity)
    if reason then
        state = reason
        return
    end
    local due = Passive.DueSeconds()
    if active > 0 then
        p.elapsed = math.min(p.elapsed + active, due)
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

-- For /fm debug: state, counted seconds, needed seconds.
function Passive.Status()
    local p = data()
    return state, p and p.elapsed or 0, ns.db and Passive.DueSeconds() or 0
end

-- What the Home countdown shows. It reads the real timer, it never
-- counts on its own. Returns state, seconds left, part done (0..1):
--   "countdown" - time is being counted;
--   "disabled"  - passive capture is off;
--   "paused"    - auto capture is paused, or the character is AFK
--                 (then a fourth value "afk" is returned);
--   "waiting"   - the interval is reached, the shot waits for a safe
--                 moment (end of combat, or a retry after the Engine's
--                 limits refused it).
function Passive.Timer()
    local p = data()
    if not p or not ns.db then
        return "disabled", 0, 0
    end
    local settings = ns.db.settings
    local due = Passive.DueSeconds()
    local elapsed = p.interval == settings.passiveInterval and p.elapsed or 0
    local fraction = due > 0 and math.min(elapsed / due, 1) or 0
    local left = math.max(0, due - elapsed)
    if not settings.passive then
        return "disabled", left, 0
    end
    if not settings.enabled then
        return "paused", left, fraction
    end
    if elapsed >= due or retrying then
        return "waiting", 0, 1
    end
    if state == "afk" then
        return "paused", left, fraction, "afk"
    end
    return "countdown", left, fraction
end

table.insert(ns.Activity.listeners, Passive.Update)
