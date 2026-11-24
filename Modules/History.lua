-- Modules/History.lua
-- History and statistics of the current character's confirmed shots.
-- A record is written only after SCREENSHOT_SUCCEEDED, so a failed or
-- skipped shot never changes a counter. The addon cannot read, rename or
-- delete screenshot files: history keeps records only.
local _, ns = ...

local History = {}
ns.History = History

local L = ns.L

History.listeners = {}

local function notify()
    for _, listener in ipairs(History.listeners) do
        ns.SafeCall("history listener", listener)
    end
end
History.Notify = notify

-- Main event of a finished request: the most important one.
local function primaryIndex(request)
    local best, bestPriority = 1, math.huge
    for i, kind in ipairs(request.types) do
        local trigger = ns.Registry.TRIGGERS[kind]
        local priority = trigger and trigger.priority or 9
        if priority < bestPriority then
            best, bestPriority = i, priority
        end
    end
    return best
end

-- Called by the Engine after a confirmed shot.
function History.AddShot(request, t)
    local character = ns.db.characters[request.character]
    if not character then
        return nil
    end
    local i = primaryIndex(request)
    local record = {
        t = t or ns.API.Time(),
        ev = request.types[i],
        zone = request.zone,
        info = request.infos and request.infos[i] or nil,
        manual = request.manual or nil,
    }
    character.shots[#character.shots + 1] = record
    while #character.shots > ns.Database.MAX_SHOTS do
        table.remove(character.shots, 1)
    end
    ns.Database.CountShot(character, record)
    notify()
    return record
end

-- Statistics of the current character (all zeros for a new one).
function History.Stats()
    local character = ns.character
    if not character then
        return { total = 0, today = 0, zones = 0 }
    end
    local zones = 0
    for _ in pairs(character.shotZones) do
        zones = zones + 1
    end
    return {
        total = character.shotsTotal or 0,
        today = character.shotsByDay[ns.Util.DayKey(ns.API.Time())] or 0,
        zones = zones,
    }
end

-- Up to `count` newest records, newest first.
function History.Recent(count)
    local result = {}
    local shots = ns.character and ns.character.shots or {}
    for i = #shots, math.max(1, #shots - count + 1), -1 do
        result[#result + 1] = shots[i]
    end
    return result
end

-- Up to `count` newest records of today, newest first (Home).
function History.Today(count)
    local result = {}
    local shots = ns.character and ns.character.shots or {}
    local today = ns.Util.DayKey(ns.API.Time())
    for i = #shots, 1, -1 do
        if #result >= count or ns.Util.DayKey(shots[i].t) ~= today then
            break
        end
        result[#result + 1] = shots[i]
    end
    return result
end

-- Flat list for the history view, newest first:
--   { kind = "day", day = "2026-11-24", count = n } followed by
--   { kind = "shot", record = record } rows of that day.
function History.Rows()
    local rows = {}
    local shots = ns.character and ns.character.shots or {}
    local header
    for i = #shots, 1, -1 do
        local record = shots[i]
        local day = ns.Util.DayKey(record.t)
        if not header or header.day ~= day then
            header = { kind = "day", day = day, count = 0 }
            rows[#rows + 1] = header
        end
        header.count = header.count + 1
        rows[#rows + 1] = { kind = "shot", record = record }
    end
    return rows
end

---------------------------------------------------------------------------
-- Screenshot search (v0.11.0): metadata of registered shots only; the
-- image files are never opened.
--   filter = { text = "", type = "all" | event id | "MANUAL" | "PASSIVE",
--              zone = name | nil, from = day | nil, to = day | nil,
--              order = "new" | "old" }
-- Returns the matching records in the chosen order.
---------------------------------------------------------------------------
local function searchText(record)
    local parts = { History.Title(record), L["EVENT_" .. tostring(record.ev)] }
    if type(record.zone) == "string" then parts[#parts + 1] = record.zone end
    if type(record.info) == "string" or type(record.info) == "number" then
        parts[#parts + 1] = tostring(record.info)
    end
    return ns.Util.Lower(table.concat(parts, "\n"))
end

function History.Matches(record, filter, query)
    local kind = filter.type or "all"
    if kind == "MANUAL" then
        if not (record.manual or record.ev == "MANUAL") then return false end
    elseif kind ~= "all" and record.ev ~= kind then
        return false
    end
    if filter.zone and record.zone ~= filter.zone then
        return false
    end
    if filter.from or filter.to then
        local day = ns.Util.DayKey(record.t)
        if (filter.from and day < filter.from) or (filter.to and day > filter.to) then
            return false
        end
    end
    if query and query ~= "" and not string.find(searchText(record), query, 1, true) then
        return false
    end
    return true
end

function History.Search(filter)
    local shots = ns.character and ns.character.shots or {}
    local query = ns.Util.Lower(filter.text or "")
    local result = {}
    local first, last, step = #shots, 1, -1
    if filter.order == "old" then
        first, last, step = 1, #shots, 1
    end
    for i = first, last, step do
        local record = shots[i]
        if History.Matches(record, filter, query) then
            result[#result + 1] = record
        end
    end
    return result
end

-- Zones that appear in the shot history, sorted (location filter).
function History.ShotZones()
    local seen, list = {}, {}
    for _, record in ipairs(ns.character and ns.character.shots or {}) do
        if type(record.zone) == "string" and record.zone ~= "" and not seen[record.zone] then
            seen[record.zone] = true
            list[#list + 1] = record.zone
        end
    end
    table.sort(list, function(a, b) return ns.Util.Lower(a) < ns.Util.Lower(b) end)
    return list
end

---------------------------------------------------------------------------
-- Text for a record (also used by notifications).
---------------------------------------------------------------------------

-- "Reached level 24", "Boss defeated", "Epic item" ...
function History.Title(record)
    if record.ev == "LEVEL" and type(record.info) == "number" then
        return string.format(L.TITLE_LEVEL, record.info)
    end
    local name = L["EVENT_" .. record.ev]
    if name == "EVENT_" .. record.ev then
        return L.EVENT_UNKNOWN
    end
    return name
end

-- Second line: zone and extra info (boss name, item, opponent).
function History.Detail(record)
    local parts = {}
    if type(record.zone) == "string" and record.zone ~= "" then
        parts[#parts + 1] = record.zone
    end
    if type(record.info) == "string" and record.info ~= "" then
        parts[#parts + 1] = record.info
    end
    return table.concat(parts, "  ·  ")
end

-- "24 November", "24 ноября".
function History.DateText(day)
    local start = ns.Util.DayStart(day)
    if not start then
        return tostring(day)
    end
    local d = date("*t", start)
    return string.format(L.DATE_FORMAT, d.day, L["MONTH_" .. d.month])
end

-- The same with " · Today" for the current day.
function History.DayLabel(day)
    local text = History.DateText(day)
    if day == ns.Util.DayKey(ns.API.Time()) then
        text = text .. "  ·  " .. L.TODAY
    end
    return text
end
