-- Modules/Locations.lua
-- Zones of the current character (v0.8.0): which zones were ever visited
-- (character.visited, kept since 0.4.2, also used by the "New zone"
-- event) and a per-day log of visits for Home and History:
--   character.locations.days["2026-11-24"][zoneKey] =
--       { name = "Duskwood", t = last arrival (Unix time), first = true|nil }
-- `first` marks the very first visit of this character to the zone.
-- A zone is recorded at login, on every zone change, and again after
-- local midnight, so the zone you stand in counts for the new day too.
local _, ns = ...

local Locations = {}
ns.Locations = Locations

local API = ns.API
local lastDay

local function days()
    local character = ns.character
    return character and character.locations and character.locations.days
end

-- Records the current zone. Returns the zone key and true when it is the
-- first visit of this character (a new memory for the "New zone" event).
function Locations.Visit()
    local character = ns.character
    local key = API.ZoneKey()
    if not character or not key then
        return nil
    end
    local isNew = not character.visited[key]
    character.visited[key] = true
    if isNew and not character.zonesSeeded then
        -- Fresh install: the zone you are standing in is not a new memory.
        character.zonesSeeded = true
        isNew = false
    end
    local now = API.Time()
    local today = ns.Util.DayKey(now)
    lastDay = today
    local log = days()
    log[today] = log[today] or {}
    local entry = log[today][key] or {}
    entry.name = API.ZoneName() or entry.name or key
    entry.t = now
    entry.first = entry.first or (isNew or nil)
    log[today][key] = entry
    return key, isNew
end

-- Number of different zones of a day (0 for a day without records).
function Locations.OnDay(day)
    local log = days()
    local count = 0
    for _ in pairs(log and log[day] or {}) do
        count = count + 1
    end
    return count
end

function Locations.Today()
    return Locations.OnDay(ns.Util.DayKey(API.Time()))
end

-- Different zones this character has ever visited.
function Locations.Total()
    local count = 0
    for _ in pairs(ns.character and ns.character.visited or {}) do
        count = count + 1
    end
    return count
end

-- Flat list for the history view, newest first:
--   { kind = "day", day = "2026-11-24", count = n } followed by
--   { kind = "zone", entry = entry } rows of that day (latest first).
function Locations.Rows()
    local rows = {}
    local log = days() or {}
    local dayKeys = ns.Util.SortedKeys(log)
    for i = #dayKeys, 1, -1 do
        local day = dayKeys[i]
        local entries = {}
        for _, entry in pairs(log[day]) do
            entries[#entries + 1] = entry
        end
        table.sort(entries, function(a, b) return a.t > b.t end)
        rows[#rows + 1] = { kind = "day", day = day, count = #entries }
        for _, entry in ipairs(entries) do
            rows[#rows + 1] = { kind = "zone", entry = entry }
        end
    end
    return rows
end

-- A new day starts at local midnight while you stay in the same zone.
table.insert(ns.Activity.listeners, function(_, reason)
    if reason ~= "loading" and lastDay and lastDay ~= ns.Util.DayKey(API.Time()) then
        Locations.Visit()
    end
end)
