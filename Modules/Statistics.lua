-- Modules/Statistics.lua
-- Real numbers for the Home tab, computed from the journal.
local _, ns = ...

local Statistics = {}
ns.Statistics = Statistics

function Statistics.Get()
    local total, today = 0, 0
    local dayStart = ns.Journal.DayStart(ns.API.Time())
    for _, entry in ipairs(ns.db.journal) do
        if ns.Journal.IsSuccess(entry) then
            total = total + 1
            if entry.t >= dayStart then
                today = today + 1
            end
        end
    end
    local zones = 0
    if ns.character then
        for _ in pairs(ns.character.visited) do
            zones = zones + 1
        end
    end
    return { total = total, today = today, zones = zones }
end
