-- Core/Util.lua
-- Small pure helpers shared by modules.
local _, ns = ...

local Util = {}
ns.Util = Util

-- Returns `value` limited to [low, high], or `default` if it is not a number.
function Util.Clamp(value, low, high, default)
    if type(value) ~= "number" or value ~= value then
        return default
    end
    if value < low then return low end
    if value > high then return high end
    return value
end

function Util.Copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = Util.Copy(item)
    end
    return result
end

-- Copies every field of `source` onto `target`, recursing into tables.
function Util.Overlay(target, source)
    if type(source) ~= "table" then
        return target
    end
    for key, item in pairs(source) do
        if type(item) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            Util.Overlay(target[key], item)
        else
            target[key] = item
        end
    end
    return target
end

function Util.Contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

function Util.AddUnique(list, value)
    if not Util.Contains(list, value) then
        list[#list + 1] = value
    end
end

function Util.SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- Turns a client format string such as "You receive loot: %s." into a Lua
-- pattern. Returns the pattern and, for positional strings ("%2$s"), the
-- argument number of each capture in order.
function Util.FormatToPattern(format)
    if type(format) ~= "string" then
        return nil
    end
    local order = {}
    local nextIndex = 1
    -- 1) mark format tokens, 2) escape magic characters, 3) put captures in.
    local marked = string.gsub(format, "%%(%d?)%$?([sd])", function(position, kind)
        local index = tonumber(position)
        if not index then
            index = nextIndex
            nextIndex = nextIndex + 1
        end
        order[#order + 1] = index
        return kind == "d" and "\001" or "\002"
    end)
    local pattern = string.gsub(marked, "([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = string.gsub(pattern, "\001", "(%%d+)")
    pattern = string.gsub(pattern, "\002", "(.+)")
    return "^" .. pattern .. "$", order
end

-- Matches `text` with a pattern from FormatToPattern; returns captures
-- arranged by their argument number (captures[1] is "%1$s").
function Util.MatchFormat(text, pattern, order)
    local captures = { string.match(text, pattern) }
    if #captures == 0 then
        return nil
    end
    local result = {}
    for i, value in ipairs(captures) do
        result[order[i] or i] = value
    end
    return result
end
