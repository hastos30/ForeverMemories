-- Modules/SessionRecap.lua
-- Session counters for "Last adventure" (v0.12.0). The session itself is
-- the one of the Activity clock (login to logout, /reload continues it,
-- midnight does not end it, AFK and loading excluded from its length).
-- This file only adds what happened in it, from existing sources:
--   shots    - every confirmed screenshot (Engine.onComplete)
--   steps    - every counted amount of the Step Tracker (Steps.onAdd)
--   zones    - zone keys recorded by Locations.Visit, newZones = first visits
--   levels   - LEVEL events (Events.listeners), photographed or not
-- No timers, no copies of history.
local _, ns = ...

local SessionRecap = {}
ns.SessionRecap = SessionRecap

local function session()
    return ns.Activity.Session()
end

function SessionRecap.OnShot(record, request)
    local s = session()
    if s and record and request and request.character == ns.characterKey and s.shots then
        s.shots = s.shots + 1
    end
end

function SessionRecap.OnSteps(amount)
    local s = session()
    if s and s.steps then
        s.steps = s.steps + amount
    end
end

function SessionRecap.OnZone(key, isNew)
    local s = session()
    if s and s.zones then
        s.zones[key] = true
        if isNew then
            s.newZones = s.newZones + 1
        end
    end
end

function SessionRecap.OnEvent(kind)
    local s = session()
    if s and s.levels and kind == "LEVEL" then
        s.levels = s.levels + 1
    end
end

table.insert(ns.Engine.onComplete, SessionRecap.OnShot)
table.insert(ns.Steps.onAdd, SessionRecap.OnSteps)
table.insert(ns.Locations.listeners, SessionRecap.OnZone)
table.insert(ns.Events.listeners, SessionRecap.OnEvent)
