-- Modules/ZoneStats.lua
-- Location Analytics (v0.11.0): active time, steps and visits per zone of
-- the current character. No own timer and no own events:
--   * time  - the seconds of active play from the shared Activity clock;
--   * steps - every amount the Step Tracker counts (Steps.onAdd);
--   * visits - Locations.Visit() tells which normalized zone (map key) the
--     character is in. A visit is a real arrival: a /reload, midnight or a
--     sub-zone of the same territory continue the current visit.
-- AFK, loading screens, dungeons and an unknown position count nothing.
-- Screenshots per zone, days and first visits come from data that already
-- exists (shots, the daily location log, visitedAt): no duplicate counters.
-- Nothing is reconstructed for the time before tracking started:
--   character.zoneStats = { since = t, current = { key, t },
--       zones = { [key] = { time = s, steps = n, visits = n, last = t } } }
local _, ns = ...

local ZoneStats = {}
ns.ZoneStats = ZoneStats

local API = ns.API

-- A return to the same zone within this many seconds is the same visit
-- (the same rule as a session: /reload, a short disconnect).
ZoneStats.CONTINUE_GAP = 180

local function data()
    local character = ns.character
    if not character then
        return nil
    end
    local zs = character.zoneStats
    if type(zs) ~= "table" then
        zs = { zones = {} }
        character.zoneStats = zs
    end
    zs.since = zs.since or API.Time()
    return zs
end

local function entryOf(zs, key)
    local entry = zs.zones[key]
    if not entry then
        entry = { time = 0, steps = 0, visits = 0 }
        zs.zones[key] = entry
    end
    return entry
end

-- The character is in the open-world zone `key` (called by Locations).
function ZoneStats.Enter(key, now)
    local zs = data()
    if not zs then
        return
    end
    now = now or API.Time()
    local current = zs.current
    local same = current and current.key == key and math.abs(now - current.t) <= ZoneStats.CONTINUE_GAP
    local entry = entryOf(zs, key)
    if not same then
        entry.visits = entry.visits + 1
    end
    entry.last = now
    zs.current = { key = key, t = now }
end

-- A dungeon or an unknown place: the zone visit ends, nothing is counted.
function ZoneStats.Leave()
    local zs = data()
    if zs then
        zs.current = nil
    end
end

function ZoneStats.CurrentKey()
    local zs = ns.character and ns.character.zoneStats
    return zs and zs.current and zs.current.key
end

-- Active play: the same seconds as Playtime.
function ZoneStats.AddTime(seconds, now)
    local zs = data()
    local key = zs and zs.current and zs.current.key
    if not key then
        return
    end
    now = now or API.Time()
    zs.current.t = now
    if seconds > 0 then
        local entry = entryOf(zs, key)
        entry.time = entry.time + seconds
        entry.last = now
    end
end

function ZoneStats.AddSteps(amount)
    local zs = data()
    local key = zs and zs.current and zs.current.key
    if key and amount > 0 then
        local entry = entryOf(zs, key)
        entry.steps = entry.steps + amount
    end
end

---------------------------------------------------------------------------
-- Card of a catalog zone: every key of the character that belongs to it
-- (a zone can have more than one map key) is summed up.
---------------------------------------------------------------------------

-- Keys of the current character that are this catalog zone, and the names
-- the day log recorded for them (to find its screenshots).
local function keysOf(area)
    local character = ns.character or {}
    local keys, names = {}, {}
    local logNames = {}
    for _, zones in pairs(character.locations and character.locations.days or {}) do
        for key, entry in pairs(zones) do
            logNames[key] = logNames[key] or entry.name
        end
    end
    local all = {}
    for key in pairs(character.visited or {}) do all[key] = true end
    for key in pairs(character.zoneStats and character.zoneStats.zones or {}) do all[key] = true end
    for key in pairs(all) do
        local zone = ns.ZoneCatalog.ZoneOfKey(key, logNames[key])
        if zone and zone.area == area then
            keys[key] = true
            if logNames[key] then
                names[logNames[key]] = true
            end
        end
    end
    return keys, names
end

-- Newest first, up to `limit` screenshot records taken in the zone.
local function shotsIn(names, limit)
    local list, count = {}, 0
    local shots = ns.character and ns.character.shots or {}
    for i = #shots, 1, -1 do
        local record = shots[i]
        if type(record.zone) == "string" and names[record.zone] then
            count = count + 1
            if #list < limit then
                list[#list + 1] = record
            end
        end
    end
    return list, count
end

-- Everything the location card shows:
--   { area, name, region, visited, time, steps, visits, days, shots,
--     firstAt, lastAt, since, latest = { records } }
function ZoneStats.Card(area, latestLimit)
    local catalog = ns.ZoneCatalog.Resolve()
    local zone, region
    for _, r in ipairs(catalog.regions) do
        for _, z in ipairs(r.zones) do
            if z.area == area then
                zone, region = z, r
            end
        end
    end
    if not zone then
        return nil
    end
    local character = ns.character or {}
    local keys, names = keysOf(area)
    names[zone.name] = true
    local card = {
        area = area, name = zone.name, region = region.name, visited = false,
        time = 0, steps = 0, visits = 0, days = 0, shots = 0,
        since = character.zoneStats and character.zoneStats.since,
    }
    local stats = character.zoneStats and character.zoneStats.zones or {}
    for key in pairs(keys) do
        if character.visited and character.visited[key] then
            card.visited = true
        end
        local at = character.visitedAt and character.visitedAt[key]
        if at and (not card.firstAt or at < card.firstAt) then
            card.firstAt = at
        end
        local s = stats[key]
        if s then
            card.time = card.time + s.time
            card.steps = card.steps + s.steps
            card.visits = card.visits + s.visits
            if s.last and (not card.lastAt or s.last > card.lastAt) then
                card.lastAt = s.last
            end
        end
    end
    -- Days: the daily location log (since 0.8.0); last arrival seen there.
    for _, zones in pairs(character.locations and character.locations.days or {}) do
        local seen = false
        for key, entry in pairs(zones) do
            if keys[key] then
                seen = true
                if not card.lastAt or entry.t > card.lastAt then
                    card.lastAt = entry.t
                end
            end
        end
        if seen then
            card.days = card.days + 1
        end
    end
    card.latest, card.shots = shotsIn(names, latestLimit or 5)
    card.time = math.floor(card.time)
    card.steps = math.floor(card.steps)
    return card
end

table.insert(ns.Activity.listeners, function(active, reason)
    if reason == "loading" then
        return
    end
    ZoneStats.AddTime(reason and 0 or active) -- AFK: the visit goes on, no time
end)
table.insert(ns.Steps.onAdd, ZoneStats.AddSteps)
