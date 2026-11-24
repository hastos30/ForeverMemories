-- Core/Serialize.lua
-- Plain-text backup format (v0.10.0). Pure Lua, no client calls.
--
-- The text is never run as Lua code: Decode is a small parser that
-- understands only this format and rejects anything else.
--
--   FMB1:<schema>:<checksum>:<payload>
--   payload = value
--   value   = "T" { value value } "E"   table: key, value, key, value ...
--           | "S" text ";"              string; % | \ ; space and control
--                                       bytes are written as %HH
--           | "N" number ";"            number (%.17g)
--           | "Y" | "F"                 true / false
-- Keys may be strings or numbers. Functions and other types are skipped.
-- The checksum (Adler-32 style, 8 hex digits) catches a text that was cut
-- or changed while copying.
local _, ns = ...

local Serialize = {}
ns.Serialize = Serialize

Serialize.PREFIX = "FMB1"
Serialize.MAX_DEPTH = 32

local function escapeByte(c)
    return string.format("%%%02X", string.byte(c))
end

local function encodeString(s)
    return "S" .. string.gsub(s, "[%%|\\; %c]", escapeByte) .. ";"
end

local function encodeValue(value, out, depth)
    local kind = type(value)
    if kind == "string" then
        out[#out + 1] = encodeString(value)
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return false
        end
        out[#out + 1] = "N" .. string.format("%.17g", value) .. ";"
    elseif kind == "boolean" then
        out[#out + 1] = value and "Y" or "F"
    elseif kind == "table" then
        if depth >= Serialize.MAX_DEPTH then
            return false
        end
        out[#out + 1] = "T"
        -- Sorted keys: the same data always gives the same text.
        local keys = {}
        for key in pairs(value) do
            local keyType = type(key)
            if keyType == "string" or (keyType == "number" and key == key) then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then
                return a < b
            end
            return type(a) == "number"
        end)
        for _, key in ipairs(keys) do
            local mark = #out
            if encodeValue(key, out, depth + 1) == false or encodeValue(value[key], out, depth + 1) == false then
                for i = #out, mark + 1, -1 do
                    out[i] = nil -- unsupported value: the pair is left out
                end
            end
        end
        out[#out + 1] = "E"
    else
        return false
    end
    return true
end

function Serialize.Checksum(text)
    local a, b = 1, 0
    local length = #text
    local i = 1
    while i <= length do
        local last = math.min(i + 3999, length)
        local bytes = { string.byte(text, i, last) }
        for j = 1, #bytes do
            a = (a + bytes[j]) % 65521
            b = (b + a) % 65521
        end
        i = last + 1
    end
    return string.format("%04X%04X", b, a)
end

-- Text for a table. `schema` is the schemaVersion of the data.
function Serialize.Encode(data, schema)
    local out = {}
    encodeValue(data, out, 0)
    local payload = table.concat(out)
    return table.concat({ Serialize.PREFIX, tostring(schema), Serialize.Checksum(payload), payload }, ":")
end

---------------------------------------------------------------------------
-- Decoding: returns data, schema or nil plus an error code:
--   "empty", "format", "checksum", "damaged"
---------------------------------------------------------------------------
local function unescape(hex)
    return string.char(tonumber(hex, 16))
end

local function decodeValue(text, pos, depth)
    local tag = string.sub(text, pos, pos)
    if tag == "S" or tag == "N" then
        local stop = string.find(text, ";", pos + 1, true)
        if not stop then
            return nil
        end
        local body = string.sub(text, pos + 1, stop - 1)
        if tag == "N" then
            if not string.match(body, "^%-?[%d%.]+[eE]?[%+%-]?%d*$") then
                return nil
            end
            local number = tonumber(body)
            if not number then
                return nil
            end
            return number, stop + 1
        end
        if string.find((string.gsub(body, "%%%x%x", "")), "%", 1, true) then
            return nil -- "%" must be followed by two hex digits
        end
        return (string.gsub(body, "%%(%x%x)", unescape)), stop + 1
    elseif tag == "Y" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "T" then
        if depth >= Serialize.MAX_DEPTH then
            return nil
        end
        local result = {}
        pos = pos + 1
        while true do
            if string.sub(text, pos, pos) == "E" then
                return result, pos + 1
            end
            local key, value
            key, pos = decodeValue(text, pos, depth + 1)
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then
                return nil
            end
            value, pos = decodeValue(text, pos, depth + 1)
            if value == nil then
                return nil
            end
            result[key] = value
        end
    end
    return nil
end

function Serialize.Decode(text)
    if type(text) ~= "string" then
        return nil, "empty"
    end
    text = string.gsub(text, "%s", "") -- line breaks and spaces from copying
    if text == "" then
        return nil, "empty"
    end
    local prefix, schema, checksum, payload = string.match(text, "^([^:]+):(%d+):(%x+):(.*)$")
    if prefix ~= Serialize.PREFIX or not payload then
        return nil, "format"
    end
    if string.upper(checksum) ~= Serialize.Checksum(payload) then
        return nil, "checksum"
    end
    local ok, data, stop = pcall(decodeValue, payload, 1, 0)
    if not ok or type(data) ~= "table" or stop ~= #payload + 1 then
        return nil, "damaged"
    end
    return data, tonumber(schema)
end
