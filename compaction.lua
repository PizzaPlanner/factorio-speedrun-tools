-- Thanks ChatGPT!

local compaction = {}

-- Base64 character map
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64map = {}
for i = 1, #b64chars do
    b64map[b64chars:sub(i, i)] = i - 1
end

-- Bitwise AND
local function bit_and(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit == 1 and b_bit == 1 then
            result = result + bitval
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end
    return result
end

-- Bitwise OR
local function bit_or(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit == 1 or b_bit == 1 then
            result = result + bitval
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end
    return result
end

-- Bitwise Right Shift
local function bit_rshift(a, n)
    return math.floor(a / (2 ^ n))
end

-- Bitwise Left Shift
local function bit_lshift(a, n)
    return (a or 0) * (2 ^ n)
end

-- Function to encode a string to Base64
local function base64_encode(data)
    local result = {}
    local padding = (3 - #data % 3) % 3
    data = data .. string.rep('\0', padding) -- Pad with null bytes if necessary

    for i = 1, #data, 3 do
        local bytes = {data:byte(i, i + 2)}
        local n = bit_or(bit_or(bit_lshift(bytes[1], 16), bit_lshift(bytes[2], 8)), bytes[3])
        result[#result + 1] = b64chars:sub(bit_rshift(n, 18) % 64 + 1, bit_rshift(n, 18) % 64 + 1)
        result[#result + 1] = b64chars:sub(bit_rshift(n, 12) % 64 + 1, bit_rshift(n, 12) % 64 + 1)
        result[#result + 1] = b64chars:sub(bit_rshift(n, 6) % 64 + 1, bit_rshift(n, 6) % 64 + 1)
        result[#result + 1] = b64chars:sub(n % 64 + 1, n % 64 + 1)
    end

    if padding > 0 then
        for i = 1, padding do
            result[#result] = '='
        end
    end

    return table.concat(result)
end

-- Function to decode a Base64 string
local function base64_decode(data)
    local result = {}
    data = data:gsub('=', '') -- Remove padding

    for i = 1, #data, 4 do
        local chars = {
            b64map[data:sub(i, i)],
            b64map[data:sub(i + 1, i + 1)],
            b64map[data:sub(i + 2, i + 2)] or 0,
            b64map[data:sub(i + 3, i + 3)] or 0
        }
        local n = bit_or(bit_or(bit_or(bit_lshift(chars[1], 18), bit_lshift(chars[2], 12)), bit_lshift(chars[3], 6)), chars[4])
        result[#result + 1] = string.char(bit_rshift(n, 16) % 256, bit_rshift(n, 8) % 256, n % 256)
    end

    return table.concat(result):gsub('%z', '') -- Remove null padding
end

compaction.serialize64 = function(tbl)
    local function serialize_inner(t)
        local result = {}
        for k, v in pairs(t) do
            if v then
                result[#result + 1] = "['" ..k .. "']=" .. tostring(v)
            end
        end
        return '{' .. table.concat(result, ',') .. '}'
    end
    return base64_encode(serialize_inner(tbl))
end

compaction.deserialize64 = function(str)
    local f, err = load("return " .. base64_decode(str), "deserialize", "t", {})
    if not f then error("Invalid serialization: " .. err) end
    return f() or { } 
end

return compaction