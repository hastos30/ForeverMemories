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

-- Calendar day of a Unix time in the computer's local time: "2026-11-24".
function Util.DayKey(t)
    return date("%Y-%m-%d", t)
end

-- Unix time of local midnight for a day key, or nil for a bad key.
function Util.DayStart(key)
    local y, m, d = string.match(tostring(key), "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        return nil
    end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

-- Day key `offset` days before `key` (noon avoids daylight-saving edges).
function Util.DayBefore(key, offset)
    local start = Util.DayStart(key)
    local d = date("*t", start)
    d.day, d.hour = d.day - offset, 12
    return Util.DayKey(time(d))
end

-- Whole number with a thousands separator: 1245872 -> "1 245 872".
-- Fractions are cut, not rounded: 0.9 steps is still 0 steps.
function Util.FormatNumber(value, separator)
    local n = math.floor(tonumber(value) or 0)
    local text = tostring(math.abs(n))
    local result = string.gsub(string.reverse(text), "(%d%d%d)", "%1" .. string.reverse(separator or " "))
    result = string.reverse(result)
    if string.sub(result, 1, #(separator or " ")) == (separator or " ") then
        result = string.sub(result, #(separator or " ") + 1)
    end
    return (n < 0 and "-" or "") .. result
end

-- Number with `decimals` digits after the separator, cut (not rounded) so
-- the text never shows more than really counted: 12458.567 -> "12 458,56".
function Util.FormatDecimal(value, decimals, separator, decimalSep)
    local scale = 10 ^ decimals
    local scaled = math.floor((tonumber(value) or 0) * scale + 1e-9)
    local whole = math.floor(scaled / scale)
    local fraction = scaled - whole * scale
    return Util.FormatNumber(whole, separator) .. (decimalSep or ".")
        .. string.format("%0" .. decimals .. "d", fraction)
end

-- Plural form for a count: "one", "few" or "many" (Russian rules) or
-- "one" / "many" for English.
function Util.PluralForm(n, locale)
    n = math.floor(math.abs(tonumber(n) or 0))
    if locale == "ruRU" then
        local mod10, mod100 = n % 10, n % 100
        if mod10 == 1 and mod100 ~= 11 then
            return "one"
        elseif mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) then
            return "few"
        end
        return "many"
    end
    return n == 1 and "one" or "many"
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
