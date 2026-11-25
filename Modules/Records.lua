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

---------------------------------------------------------------------------
-- History of improvements (v0.18.0). A record is written to the log only
-- when its period is over (the day of a "best day" has ended, a streak is
-- not running today), so a record growing during the day is one entry,
-- not one per step. The first entry of each record is the baseline found
-- in the existing history and is not shown as an improvement.
--   character.recordLog = { [id] = { { value, day, at, prev, base }, ... } }
---------------------------------------------------------------------------
Records.MAX_LOG = 20

local function log(character)
    if type(character.recordLog) ~= "table" then
        character.recordLog = {}
    end
    return character.recordLog
end

-- Writes finished improvements of the logged-in character; returns the
-- number of new entries (baselines included).
function Records.Finalize()
    local character = ns.character
    if not character or character ~= ns.db.characters[ns.characterKey] or ns.readOnly then
        return 0
    end
    local today = ns.Util.DayKey(ns.API.Time())
    local records, book, added = Records.Get(), log(character), 0
    for _, id in ipairs(Records.ORDER) do
        local r = records[id]
        local endDay = r and (r.last or r.day)
        if r and r.value and endDay and endDay < today then
            local entries = book[id]
            if type(entries) ~= "table" then
                entries = {}
                book[id] = entries
            end
            local last = entries[#entries]
            if not last then
                entries[1] = { value = r.value, day = r.day, last = r.last, base = true }
                added = added + 1
            elseif type(last.value) == "number" and r.value > last.value then
                entries[#entries + 1] = { value = r.value, day = r.day, last = r.last,
                                          prev = last.value, at = ns.API.Time() }
                added = added + 1
                while #entries > Records.MAX_LOG do
                    table.remove(entries, 2) -- the baseline stays first
                end
            end
        end
    end
    return added
end

-- Improvements of the current (or viewed) character, newest first:
-- { { id, value, prev, day, last }, ... } (baselines are left out).
function Records.Improvements()
    local character = ns.character
    local book = character and type(character.recordLog) == "table" and character.recordLog or {}
    local list = {}
    for _, id in ipairs(Records.ORDER) do
        for _, e in ipairs(type(book[id]) == "table" and book[id] or {}) do
            if not e.base and type(e.value) == "number" then
                list[#list + 1] = { id = id, value = e.value, prev = e.prev, day = e.day, last = e.last }
            end
        end
    end
    table.sort(list, function(a, b) return (a.day or "") > (b.day or "") end)
    return list
end

-- The previous value of a record, when its last improvement is logged.
function Records.Previous(id)
    local character = ns.character
    local entries = character and type(character.recordLog) == "table" and character.recordLog[id]
    local last = type(entries) == "table" and entries[#entries]
    return last and not last.base and last.prev or nil
end

local lastFinalized
table.insert(ns.onLogin, function()
    lastFinalized = ns.Util.DayKey(ns.API.Time())
    Records.Finalize()
end)
-- A new day while playing: yesterday's records are final now.
table.insert(ns.Activity.listeners, function()
    local today = ns.Util.DayKey(ns.API.Time())
    if lastFinalized and today ~= lastFinalized then
        lastFinalized = today
        Records.Invalidate()
        Records.Finalize()
    end
end)
