-- Capture/Queue.lua
-- Bounded priority queue of capture requests (SPECIFICATION.md section 4).
-- Lower priority number = more important. Equal priority: first in, first out.
local _, ns = ...

local Queue = {}
ns.Queue = Queue

Queue.MAX = 20
Queue.MERGE_WINDOW = 0.5

local items = {}
local sequence = 0

local function compatible(a, b)
    return not a.manual and not b.manual
        and a.mode == b.mode and a.journey == b.journey
        and math.abs(a.createdAt - b.createdAt) <= Queue.MERGE_WINDOW
end

-- Merges `incoming` into `target`; the earliest due time wins so a
-- critical frame is never delayed.
local function merge(target, incoming)
    for i, kind in ipairs(incoming.types) do
        if not ns.Util.Contains(target.types, kind) then
            target.types[#target.types + 1] = kind
            target.keys[#target.keys + 1] = incoming.keys[i]
        end
    end
    target.priority = math.min(target.priority, incoming.priority)
    target.frames = math.max(target.frames, incoming.frames)
    target.dueAt = math.min(target.dueAt, incoming.dueAt)
end

local function isWorse(a, b)
    -- true when `a` should be dropped before `b`
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.seq > b.seq
end

-- Returns accepted, droppedRequest, merged.
-- droppedRequest is the request that did not fit (evicted or rejected).
function Queue.Push(request)
    for _, item in ipairs(items) do
        if compatible(item, request) then
            merge(item, request)
            return true, nil, true
        end
    end
    sequence = sequence + 1
    request.seq = sequence
    if #items >= Queue.MAX then
        local worstIndex
        for i, item in ipairs(items) do
            if not item.manual and (not worstIndex or isWorse(item, items[worstIndex])) then
                worstIndex = i
            end
        end
        if not worstIndex or (not request.manual and not isWorse(items[worstIndex], request)) then
            return false, request, false
        end
        local evicted = table.remove(items, worstIndex)
        items[#items + 1] = request
        return true, evicted, false
    end
    items[#items + 1] = request
    return true, nil, false
end

-- Removes and returns the most important request that is due.
function Queue.PopDue(now)
    local bestIndex
    for i, item in ipairs(items) do
        if item.dueAt <= now then
            local best = items[bestIndex]
            if not best or item.priority < best.priority
                or (item.priority == best.priority and item.seq < best.seq) then
                bestIndex = i
            end
        end
    end
    if bestIndex then
        return table.remove(items, bestIndex)
    end
end

-- Removes requests whose time to live has passed; returns them.
function Queue.Expire(now)
    local expired = {}
    for i = #items, 1, -1 do
        if now > items[i].dueAt + items[i].ttl then
            table.insert(expired, 1, table.remove(items, i))
        end
    end
    return expired
end

-- Removes automatic requests (pause, loading screen); returns them.
function Queue.CancelAuto()
    local removed = {}
    for i = #items, 1, -1 do
        if not items[i].manual then
            table.insert(removed, 1, table.remove(items, i))
        end
    end
    return removed
end

function Queue.NextDue()
    local nextDue
    for _, item in ipairs(items) do
        if not nextDue or item.dueAt < nextDue then
            nextDue = item.dueAt
        end
    end
    return nextDue
end

function Queue.Size()
    return #items
end

function Queue.Clear()
    items = {}
end
