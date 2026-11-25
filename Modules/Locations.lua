-- Modules/Locations.lua
-- Zones of the current character (v0.8.0): which zones were ever visited
-- (character.visited, kept since 0.4.2, also used by the "New zone"
-- event) and a per-day log of visits for Home and History:
--   character.locations.days["2026-11-24"][zoneKey] =
--       { name = "Duskwood", t = first arrival that day (Unix time; until
--         0.9.0 the last arrival), first = true|nil, instance = "party"|... }
-- `first` marks the very first visit of this character to the zone.
-- Dungeons, raids, battlegrounds (v0.9.0) get an "inst:<name>" entry in
-- the day log only: they are not open-world zones, so they never count as
-- visited zones nor trigger the "New zone" shot.
-- A zone is recorded at login, on every zone change, and again after
-- local midnight, so the zone you stand in counts for the new day too.
local _, ns = ...

local Locations = {}
ns.Locations = Locations

-- listener(zoneKey, isNew) after every recorded open-world zone.
Locations.listeners = {}

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
    if not character then
        return nil
    end
    local now = API.Time()
    local today = ns.Util.DayKey(now)
    local instance = API.InstanceType()
    if instance and instance ~= "none" then
        ns.ZoneStats.Leave()
        local name = API.ZoneName()
        if name then
            lastDay = today
            local log = days()
            log[today] = log[today] or {}
            local key = "inst:" .. name
            log[today][key] = log[today][key] or { name = name, t = now, instance = instance }
        end
        return nil
    end
    local key = API.ZoneKey()
    if not key then
        ns.ZoneStats.Leave() -- unknown place: nothing is counted
        return nil
    end
    local isNew = not character.visited[key]
    character.visited[key] = true
    if isNew and not character.zonesSeeded then
        -- Fresh install: the zone you are standing in is not a new memory.
        character.zonesSeeded = true
        isNew = false
    end
    character.visitedAt[key] = character.visitedAt[key] or now
    lastDay = today
    local log = days()
    log[today] = log[today] or {}
    local entry = log[today][key] or {}
    entry.name = API.ZoneName() or entry.name or Locations.KeyName(key)
    entry.t = entry.t or now -- one record per zone and day: first arrival
    entry.first = entry.first or (isNew or nil)
    log[today][key] = entry
    ns.ZoneStats.Enter(key, now)
    for i = 1, #Locations.listeners do -- v0.12.0: session recap
        ns.SafeCall("location listener", Locations.listeners[i], key, isNew)
    end
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

-- Zone keys and entries of a day: { [key] = entry } (empty table if none).
function Locations.Day(day)
    local log = days()
    return log and log[day] or {}
end

-- Different zones this character has ever visited.
function Locations.Total()
    local count = 0
    for _ in pairs(ns.character and ns.character.visited or {}) do
        count = count + 1
    end
    return count
end

-- Name to show for a visit (v1.0.1): a raw key such as "map:1415" (the
-- zone had no name yet when it was recorded) becomes the map's own name,
-- or "Unknown place". The saved record is not changed.
-- Best name for a key at the moment of the visit (map name, then the key).
function Locations.KeyName(key)
    local mapID = type(key) == "string" and tonumber(string.match(key, "^map:(%d+)$"))
    return mapID and API.MapName(mapID) or key
end

function Locations.DisplayName(entry, key)
    local name = entry and entry.name or key
    if type(name) ~= "string" or name == "" then
        return ns.L.UNKNOWN_PLACE
    end
    local mapID = tonumber(string.match(name, "^map:(%d+)$"))
    if mapID then
        return API.MapName(mapID) or ns.L.UNKNOWN_PLACE
    end
    local zone = string.match(name, "^zone:(.+)$")
    return ns.ZoneText(zone or name)
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
