-- Modules/Memories.lua
-- Memories (v0.13.0): "On This Day" for History / Overview and the
-- Adventure Anniversary card for Home. Read-only: everything comes from
-- what is already saved (screenshot history, Journey, first visits).
-- Nothing is invented: a date that does not exist (31 February) has no
-- memories, and the anniversary counts from the first login with
-- ForeverMemories (journey.started), never from the character creation.
local _, ns = ...

local Memories = {}
ns.Memories = Memories

Memories.LIMIT = 3 -- memories shown per period ("+N more" for the rest)
Memories.PERIODS = { "week", "month", "year" }

---------------------------------------------------------------------------
-- Calendar arithmetic on day keys "YYYY-MM-DD".
---------------------------------------------------------------------------
local function parse(day)
    local y, m, d = string.match(tostring(day), "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    return tonumber(y), tonumber(m), tonumber(d)
end

local function daysIn(y, m)
    if m == 2 then
        return (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28
    end
    return (m == 4 or m == 6 or m == 9 or m == 11) and 30 or 31
end

-- `day` moved by `months`. A missing date (31 Feb) gives nil, or with
-- `clamp` the last day of that month.
function Memories.AddMonths(day, months, clamp)
    local y, m, d = parse(day)
    if not y then
        return nil
    end
    local index = y * 12 + (m - 1) + months
    local ny, nm = math.floor(index / 12), index % 12 + 1
    local last = daysIn(ny, nm)
    if d > last then
        if not clamp then
            return nil
        end
        d = last
    end
    return string.format("%04d-%02d-%02d", ny, nm, d)
end

---------------------------------------------------------------------------
-- On This Day: a week, a month and a year ago.
---------------------------------------------------------------------------
local cache = { character = nil, day = nil, result = nil }

function Memories.Invalidate()
    cache.result = nil
end

local function journeyItems(character, wanted, out)
    for _, e in ipairs(character.journey and character.journey.events or {}) do
        local period = wanted[ns.Util.DayKey(e.t)]
        if period then
            out[period][#out[period] + 1] = {
                t = e.t, kind = e.kind, icon = ns.Journey.Icon(e.kind), title = ns.Journey.Title(e),
                zone = e.zone, detail = type(e.info) == "string" and e.info or nil,
            }
        end
    end
end

local function visitItems(character, wanted, out)
    local logs = character.locations and character.locations.days or {}
    for key, t in pairs(character.visitedAt or {}) do
        local day = ns.Util.DayKey(t)
        local period = wanted[day]
        -- The name the client gave that day; a key without one is skipped.
        local entry = period and logs[day] and logs[day][key]
        local name = entry and entry.name or (period and string.match(key, "^zone:(.+)$"))
        if name then
            out[period][#out[period] + 1] = {
                t = t, kind = "ZONE", icon = ns.Registry.Icon("ZONE"), title = ns.L.MEMORY_FIRST_VISIT,
                zone = name,
            }
        end
    end
end

-- A screenshot of a moment that Journey already lists is not repeated.
local function shotItems(character, wanted, out)
    for _, record in ipairs(character.shots or {}) do
        local period = type(record.t) == "number" and wanted[ns.Util.DayKey(record.t)]
        if period then
            local duplicate = false
            for _, item in ipairs(out[period]) do
                if item.kind == record.ev and math.abs(item.t - record.t) <= 120 then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                out[period][#out[period] + 1] = {
                    t = record.t, kind = "SHOT", icon = ns.Registry.Icon(record.ev),
                    title = ns.History.Title(record), zone = record.zone,
                    detail = type(record.info) == "string" and record.info ~= "" and record.info or nil,
                }
            end
        end
    end
end

local function compute(character, today)
    local days = {
        week = ns.Util.DayBefore(today, 7),
        month = Memories.AddMonths(today, -1),
        year = Memories.AddMonths(today, -12),
    }
    local wanted, out = {}, {}
    for _, period in ipairs(Memories.PERIODS) do
        if days[period] and not wanted[days[period]] then
            wanted[days[period]] = period
            out[period] = {}
        end
    end
    journeyItems(character, wanted, out)
    visitItems(character, wanted, out)
    shotItems(character, wanted, out)
    local result = {}
    for _, period in ipairs(Memories.PERIODS) do
        local items = out[period]
        if items and #items > 0 then
            table.sort(items, function(a, b) return a.t < b.t end)
            local shown = {}
            for i = 1, math.min(#items, Memories.LIMIT) do
                shown[i] = items[i]
            end
            result[#result + 1] = { period = period, day = days[period], items = shown,
                                    more = #items - #shown }
        end
    end
    return result
end

-- { { period, day, items = { { t, icon, title, zone, detail } }, more } }
-- for the current (or viewed) character; periods without memories are
-- left out, so an empty list hides the block.
function Memories.OnThisDay()
    local character = ns.character
    if not character then
        return {}
    end
    local today = ns.Util.DayKey(ns.API.Time())
    if cache.result and cache.character == character and cache.day == today then
        return cache.result
    end
    cache.character, cache.day, cache.result = character, today, compute(character, today)
    return cache.result
end

---------------------------------------------------------------------------
-- Adventure Anniversary: 1 week, 1, 3 and 6 months, then every year after
-- the first registered login with ForeverMemories.
---------------------------------------------------------------------------
local MONTHS = { { 1, "MONTH" }, { 3, "MONTHS3" }, { 6, "MONTHS6" } }

-- { kind = "WEEK"|"MONTH"|"MONTHS3"|"MONTHS6"|"YEAR", years, started } or nil.
function Memories.Anniversary()
    local character = ns.character
    local started = character and character.journey and character.journey.started
    if type(started) ~= "number" then
        return nil
    end
    local first = ns.Util.DayKey(started)
    local today = ns.Util.DayKey(ns.API.Time())
    if today <= first then
        return nil
    end
    if ns.Util.DayBefore(today, 7) == first then
        return { kind = "WEEK", started = started }
    end
    for _, m in ipairs(MONTHS) do
        if Memories.AddMonths(first, m[1], true) == today then
            return { kind = m[2], started = started }
        end
    end
    local years = parse(today) - parse(first)
    if years > 0 and Memories.AddMonths(first, 12 * years, true) == today then
        return { kind = "YEAR", years = years, started = started }
    end
    return nil
end

table.insert(ns.History.listeners, Memories.Invalidate)
table.insert(ns.Journey.listeners, Memories.Invalidate)
table.insert(ns.Locations.listeners, Memories.Invalidate)
