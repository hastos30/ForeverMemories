-- Modules/Records.lua
-- Adventure Records (v0.12.0): personal records of the current character,
-- computed from the history that already exists (no extra counters):
--   steps    - most steps in a calendar day       (steps.days)
--   shots    - most screenshots in a day           (shotsByDay)
--   zones    - most different open-world zones in a day (location log)
--   playtime - most active play in a day           (playtime.days)
--   session  - longest session                     (playtime.longest)
--   streak   - longest run of consecutive days with any recorded play
-- A tie keeps the first date the value was reached. A record without
-- enough data is "no data" (value nil). Results are cached and computed
-- again only after a change of the history (listeners) or a new day.
local _, ns = ...

local Records = {}
ns.Records = Records

Records.ORDER = { "steps", "shots", "zones", "playtime", "session", "streak" }

local cache = { character = nil, day = nil, result = nil }

function Records.Invalidate()
    cache.result = nil
end

-- Highest value of a { [day] = value } map; the earliest day on a tie.
local function best(map, measure)
    local value, day
    for _, d in ipairs(ns.Util.SortedKeys(map or {})) do
        local v = measure and measure(map[d]) or map[d]
        if type(v) == "number" and v > 0 and (not value or v > value) then
            value, day = v, d
        end
    end
    return value, day
end

local function zonesOfDay(entries)
    local n = 0
    for key in pairs(type(entries) == "table" and entries or {}) do
        if string.sub(key, 1, 5) ~= "inst:" then
            n = n + 1
        end
    end
    return n
end

-- Days with any recorded play (union of every daily source).
function Records.PlayedDays(character)
    local days = {}
    local sources = {
        character.playtime and character.playtime.days, character.steps and character.steps.days,
        character.shotsByDay,
    }
    for _, map in ipairs(sources) do
        for day, value in pairs(map or {}) do
            if type(value) == "number" and value > 0 then
                days[day] = true
            end
        end
    end
    for day, entries in pairs(character.locations and character.locations.days or {}) do
        if next(entries) then
            days[day] = true
        end
    end
    return days
end

-- Longest run of consecutive days: length, first and last day (the
-- earliest run on a tie).
local function streak(days)
    local bestLength, bestFirst, bestLast = 0, nil, nil
    local length, first, previous = 0, nil, nil
    for _, day in ipairs(ns.Util.SortedKeys(days)) do
        if previous and ns.Util.DayBefore(day, 1) == previous then
            length = length + 1
        else
            length, first = 1, day
        end
        if length > bestLength then
            bestLength, bestFirst, bestLast = length, first, day
        end
        previous = day
    end
    return bestLength, bestFirst, bestLast
end

local function compute(character)
    local r = {}
    local v, d = best(character.steps and character.steps.days, math.floor)
    r.steps = { value = v, day = d }
    v, d = best(character.shotsByDay)
    r.shots = { value = v, day = d }
    v, d = best(character.locations and character.locations.days, zonesOfDay)
    r.zones = { value = v, day = d }
    v, d = best(character.playtime and character.playtime.days, math.floor)
    r.playtime = { value = v, day = d }
    local saved = ns.character
    ns.character = character
    local longest, at = ns.Activity.Longest()
    ns.character = saved
    r.session = { value = longest > 0 and longest or nil, day = at and ns.Util.DayKey(at) or nil }
    local length, first, last = streak(Records.PlayedDays(character))
    r.streak = { value = length > 0 and length or nil, day = first, last = last }
    return r
end

-- Records of the current (or viewed) character: { [id] = { value, day, last } }.
function Records.Get()
    local character = ns.character
    if not character then
        return {}
    end
    local today = ns.Util.DayKey(ns.API.Time())
    if cache.result and cache.character == character and cache.day == today then
        return cache.result
    end
    cache.character, cache.day, cache.result = character, today, compute(character)
    return cache.result
end

table.insert(ns.History.listeners, Records.Invalidate)
table.insert(ns.Locations.listeners, Records.Invalidate)
