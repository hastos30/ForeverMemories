-- Core/Logger.lua
-- Ring buffer of the last 200 messages, kept in memory for this session only.
-- Never store chat text here: only our own diagnostic messages.
local _, ns = ...

local Logger = {}
ns.Logger = Logger

local CAPACITY = 200
local entries = {}
local nextIndex = 1
local count = 0

local function add(level, message)
    entries[nextIndex] = { t = ns.API.Time(), level = level, msg = tostring(message) }
    nextIndex = nextIndex % CAPACITY + 1
    if count < CAPACITY then
        count = count + 1
    end
end

function Logger.Info(message) add("INFO", message) end
function Logger.Warn(message) add("WARN", message) end
function Logger.Error(message) add("ERROR", message) end

-- Returns up to `limit` most recent entries, oldest first.
function Logger.Recent(limit)
    limit = math.min(limit or count, count)
    local result = {}
    for i = limit, 1, -1 do
        local index = (nextIndex - i - 1) % CAPACITY + 1
        result[#result + 1] = entries[index]
    end
    return result
end

function Logger.Count()
    return count
end
