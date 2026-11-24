-- Modules/Adventure.lua
-- Adventure Calendar and Adventure Recap (v0.9.0). No data of its own:
-- every number is read from the per-day records the other modules keep
-- (shots by day, steps by day, zones by day, playtime by day), so Home,
-- History, the calendar and the recap always agree.
local _, ns = ...

local Adventure = {}
ns.Adventure = Adventure

local Util = ns.Util

-- Activity levels of a day by active playtime (minutes), no overlaps:
-- 0 = 0 min, 1 = under 60, 2 = 60 to under 120, 3 = 120 to under 240,
-- 4 = 240 and more.
Adventure.LEVEL_MINUTES = { 60, 120, 240 }
Adventure.WEEKS = 12

function Adventure.Level(seconds)
    seconds = seconds or 0
    if seconds <= 0 then
        return 0
    end
    local minutes = seconds / 60
    for i, limit in ipairs(Adventure.LEVEL_MINUTES) do
        if minutes < limit then
            return i
        end
    end
    return #Adventure.LEVEL_MINUTES + 1
end

function Adventure.Today()
    return Util.DayKey(ns.API.Time())
end

local function nextDay(day)
    return Util.DayBefore(day, -1)
end

-- Everything known about one day of the current character.
--   recorded: the Playtime Tracker was already counting on that day
--   (false = "no data", not "no activity").
function Adventure.Day(day)
    local character = ns.character
    local since = ns.Activity.SinceDay()
    local result = {
        day = day,
        shots = character and character.shotsByDay[day] or 0,
        steps = ns.Steps.OnDay(day),
        zones = ns.Locations.OnDay(day),
        playtime = ns.Activity.OnDay(day),
        recorded = since ~= nil and day >= since,
    }
    result.level = Adventure.Level(result.playtime)
    result.any = result.shots > 0 or result.steps > 0 or result.zones > 0 or result.playtime > 0
    return result
end

-- Monday and Sunday of the week of `day` (weeks start on Monday).
function Adventure.WeekRange(day)
    local monday = Util.DayBefore(day, Util.Weekday(day) - 1)
    return monday, Util.DayBefore(monday, -6)
end

-- First and last calendar day of the month of `day`.
function Adventure.MonthRange(day)
    local y, m = string.match(day, "^(%d+)%-(%d+)")
    y, m = tonumber(y), tonumber(m)
    local first = string.format("%04d-%02d-01", y, m)
    local ny, nm = y, m + 1
    if nm > 12 then
        ny, nm = y + 1, 1
    end
    local last = Util.DayBefore(string.format("%04d-%02d-01", ny, nm), 1)
    return first, last
end

-- Totals of a period from `first` to `last` (day keys, inclusive).
-- Unique zones are the union of zone keys, not a sum of daily counts.
function Adventure.Period(first, last)
    local character = ns.character
    local totals = { shots = 0, steps = 0, zones = 0, newZones = 0, playtime = 0, days = 0 }
    local seen = {}
    local day, guard = first, 0
    while day <= last and guard < 400 do
        totals.shots = totals.shots + (character and character.shotsByDay[day] or 0)
        totals.steps = totals.steps + (character and character.steps.days[day] or 0)
        local seconds = character and character.playtime.days[day] or 0
        totals.playtime = totals.playtime + seconds
        if seconds > 0 then
            totals.days = totals.days + 1
        end
        for key, entry in pairs(ns.Locations.Day(day)) do
            if not seen[key] then
                seen[key] = true
                totals.zones = totals.zones + 1
            end
            if entry.first then
                totals.newZones = totals.newZones + 1
            end
        end
        day, guard = nextDay(day), guard + 1
    end
    totals.steps = math.floor(totals.steps)
    totals.playtime = math.floor(totals.playtime)
    return totals
end

function Adventure.Week(day)
    return Adventure.Period(Adventure.WeekRange(day or Adventure.Today()))
end

function Adventure.Month(day)
    return Adventure.Period(Adventure.MonthRange(day or Adventure.Today()))
end

-- Calendar grid: `weeks` columns (oldest first), each with seven days from
-- Monday to Sunday. Every cell: { day, future, today, state, info } where
-- state is "future", "nodata" or 0..4 (activity level).
-- Columns carry `month` (1..12) when the 1st of a month falls in them.
function Adventure.Calendar(today, weeks)
    today = today or Adventure.Today()
    weeks = weeks or Adventure.WEEKS
    local monday = Adventure.WeekRange(today)
    local start = Util.DayBefore(monday, (weeks - 1) * 7)
    local columns = {}
    local day = start
    for w = 1, weeks do
        local column = { days = {} }
        for d = 1, 7 do
            local cell = { day = day, today = day == today, future = day > today }
            if cell.future then
                cell.state = "future"
            else
                cell.info = Adventure.Day(day)
                cell.state = cell.info.recorded and cell.info.level or "nodata"
            end
            if string.sub(day, 9, 10) == "01" then
                column.month = tonumber(string.sub(day, 6, 7))
            end
            column.days[d] = cell
            day = nextDay(day)
        end
        columns[w] = column
    end
    -- The first column is labelled too when no label is close to it.
    if not columns[1].month and not (columns[2] and columns[2].month) and not (columns[3] and columns[3].month) then
        columns[1].month = tonumber(string.sub(start, 6, 7))
    end
    return columns
end

-- All days from the first recorded one to today, newest first, with the
-- value `get(day)`: daily lists of Steps and Playtime (days without
-- activity in between show 0; nothing before the first record).
function Adventure.DailyList(firstDay, get)
    local list = {}
    if not firstDay then
        return list
    end
    local today = Adventure.Today()
    local day, guard = today, 0
    while day >= firstDay and guard < 3660 do
        list[#list + 1] = { day = day, value = get(day) }
        day, guard = Util.DayBefore(day, 1), guard + 1
    end
    return list
end

-- Earliest key of a { [day] = value } table, or nil.
function Adventure.FirstDay(map)
    local first
    for day in pairs(map or {}) do
        if not first or day < first then
            first = day
        end
    end
    return first
end
