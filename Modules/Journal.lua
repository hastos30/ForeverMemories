-- Modules/Journal.lua
-- One record per capture request: append/query/update/trim.
-- Deleting a record never deletes the screenshot file (Lua cannot do that).
local _, ns = ...

local Journal = {}
ns.Journal = Journal

Journal.PAGE_SIZE = 50
Journal.listeners = {}

local function notify()
    for _, listener in ipairs(Journal.listeners) do
        ns.SafeCall("journal listener", listener)
    end
end

-- Removes the oldest records above the limits. Favorites are kept unless
-- they exceed their own limit.
function Journal.Trim(journal, maxEntries, maxFavorites)
    local favorites = 0
    for i = 1, #journal do
        if journal[i].fav then
            favorites = favorites + 1
        end
    end
    local i = 1
    while #journal > maxEntries and i <= #journal do
        local entry = journal[i]
        if not entry.fav or favorites > maxFavorites then
            if entry.fav then
                favorites = favorites - 1
            end
            table.remove(journal, i)
        else
            i = i + 1
        end
    end
end

-- Builds a record from a finished (or skipped) request.
function Journal.Append(request, result)
    local db = ns.db
    local entry = {
        id = db.nextJournalId,
        t = ns.API.Time(),
        char = request.character,
        zone = request.zone,
        events = ns.Util.Copy(request.types),
        keys = ns.Util.Copy(request.keys),
        modeRequested = request.mode,
        modeActual = result.modeActual,
        ok = result.ok or 0,
        failed = result.failed or 0,
        status = result.status,
        skipReason = result.skipReason,
        manual = request.manual or nil,
    }
    db.nextJournalId = db.nextJournalId + 1
    db.journal[#db.journal + 1] = entry
    Journal.Trim(db.journal, ns.Database.MAX_JOURNAL, ns.Database.MAX_FAVORITES)
    notify()
    return entry
end

function Journal.Get(id)
    for _, entry in ipairs(ns.db.journal) do
        if entry.id == id then
            return entry
        end
    end
end

-- Only `note` and `fav` can be changed by the player.
function Journal.Update(id, fields)
    local entry = Journal.Get(id)
    if not entry then
        return false
    end
    if fields.note ~= nil then
        entry.note = fields.note ~= "" and string.sub(tostring(fields.note), 1, 200) or nil
    end
    if fields.fav ~= nil then
        entry.fav = fields.fav and true or nil
    end
    notify()
    return true
end

function Journal.Delete(id)
    for i, entry in ipairs(ns.db.journal) do
        if entry.id == id then
            table.remove(ns.db.journal, i)
            notify()
            return true
        end
    end
    return false
end

local function matches(entry, filter)
    if filter.char and entry.char ~= filter.char then
        return false
    end
    if filter.status and entry.status ~= filter.status then
        return false
    end
    if filter.event and not ns.Util.Contains(entry.events, filter.event) then
        return false
    end
    if filter.since and entry.t < filter.since then
        return false
    end
    if filter.fav and not entry.fav then
        return false
    end
    return true
end

-- Newest first. Returns the page items, total matches and page count.
function Journal.Query(filter, page)
    filter = filter or {}
    page = page or 1
    local all = {}
    local journal = ns.db.journal
    for i = #journal, 1, -1 do
        if matches(journal[i], filter) then
            all[#all + 1] = journal[i]
        end
    end
    local pages = math.max(1, math.ceil(#all / Journal.PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    local items = {}
    for i = (page - 1) * Journal.PAGE_SIZE + 1, math.min(#all, page * Journal.PAGE_SIZE) do
        items[#items + 1] = all[i]
    end
    return items, #all, pages, page
end

function Journal.IsSuccess(entry)
    return entry.ok and entry.ok > 0
end

-- Start of the local day containing `t`.
function Journal.DayStart(t)
    local d = date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

-- Time Capsule: first and last confirmed records of the day containing `t`.
function Journal.DayCapsule(t)
    local from = Journal.DayStart(t)
    local to = from + 86400
    local first, last
    for _, entry in ipairs(ns.db.journal) do
        if entry.t >= from and entry.t < to and Journal.IsSuccess(entry) then
            first = first or entry
            last = entry
        end
    end
    return first, last
end

-- Anniversary: confirmed records from the same day in earlier years.
function Journal.Anniversary(t)
    local today = date("*t", t)
    local result = {}
    for _, entry in ipairs(ns.db.journal) do
        local d = date("*t", entry.t)
        if d.month == today.month and d.day == today.day and d.year < today.year
            and Journal.IsSuccess(entry) then
            result[#result + 1] = entry
        end
    end
    return result
end
