local addonName, ns = ...

-- ============================================================================
-- Utils.lua - Shared utility functions for BarWarden
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CopyTable: Deep copy a table (handles nested tables, skips metatables)
-- ----------------------------------------------------------------------------
function ns:CopyTable(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = self:CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- ----------------------------------------------------------------------------
-- MergeDefaults: Recursively merge defaults into target without overwriting
-- existing user values. Only fills in missing keys.
-- ----------------------------------------------------------------------------
function ns:MergeDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = self:CopyTable(v)
            else
                self:MergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- ----------------------------------------------------------------------------
-- FormatTime: Format seconds into human-readable time string
-- 0-60s: "X.X" (one decimal), 60-3600: "M:SS", 3600+: "H:MM:SS"
-- ----------------------------------------------------------------------------
function ns:FormatTime(seconds)
    if not seconds or seconds < 0 then seconds = 0 end

    if seconds < 60 then
        return string.format("%.1f", seconds)
    elseif seconds < 3600 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds - m * 60)
        return string.format("%d:%02d", m, s)
    else
        local h = math.floor(seconds / 3600)
        local remaining = seconds - h * 3600
        local m = math.floor(remaining / 60)
        local s = math.floor(remaining - m * 60)
        return string.format("%d:%02d:%02d", h, m, s)
    end
end

-- ----------------------------------------------------------------------------
-- Color Helpers
-- ----------------------------------------------------------------------------

-- RAID_CLASS_COLORS is a Blizzard global available in 3.3.5a
function ns:GetClassColor(class)
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

function ns:GetPlayerClassColor()
    local _, class = UnitClass("player")
    return self:GetClassColor(class)
end

-- ----------------------------------------------------------------------------
-- Base64 Encode/Decode
-- ----------------------------------------------------------------------------

local Base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(data)
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local b1 = string.byte(data, i)
        local b2 = i + 1 <= len and string.byte(data, i + 1) or 0
        local b3 = i + 2 <= len and string.byte(data, i + 2) or 0

        local n = b1 * 65536 + b2 * 256 + b3

        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64

        out[#out + 1] = Base64Chars:sub(c1 + 1, c1 + 1)
        out[#out + 1] = Base64Chars:sub(c2 + 1, c2 + 1)
        out[#out + 1] = (i + 1 <= len) and Base64Chars:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = (i + 2 <= len) and Base64Chars:sub(c4 + 1, c4 + 1) or "="
    end
    return table.concat(out)
end

local Base64Lookup = {}
for i = 1, 64 do
    Base64Lookup[Base64Chars:sub(i, i)] = i - 1
end

local function Base64Decode(data)
    if not data then return nil end
    data = data:gsub("[^" .. Base64Chars .. "=]", "")
    local out = {}
    for i = 1, #data, 4 do
        local c1 = Base64Lookup[data:sub(i, i)] or 0
        local c2 = Base64Lookup[data:sub(i + 1, i + 1)] or 0
        local c3 = Base64Lookup[data:sub(i + 2, i + 2)] or 0
        local c4 = Base64Lookup[data:sub(i + 3, i + 3)] or 0

        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4

        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if data:sub(i + 2, i + 2) ~= "=" then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if data:sub(i + 3, i + 3) ~= "=" then
            out[#out + 1] = string.char(n % 256)
        end
    end
    return table.concat(out)
end

ns.Base64Encode = Base64Encode
ns.Base64Decode = Base64Decode

-- ----------------------------------------------------------------------------
-- Table Serializer/Deserializer (for profile export/import)
-- Simple recursive key=value format, no external libs
-- ----------------------------------------------------------------------------

local function SerializeValue(val)
    local t = type(val)
    if t == "string" then
        -- Escape special characters
        local escaped = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
        return '"' .. escaped .. '"'
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "table" then
        local parts = {}
        -- Serialize array part
        local arrayLen = #val
        for i = 1, arrayLen do
            parts[#parts + 1] = SerializeValue(val[i])
        end
        -- Serialize hash part
        for k, v in pairs(val) do
            if type(k) == "number" and k >= 1 and k <= arrayLen and math.floor(k) == k then
                -- skip, already serialized in array part
            else
                local keyStr
                if type(k) == "string" then
                    keyStr = "[" .. SerializeValue(k) .. "]"
                elseif type(k) == "number" then
                    keyStr = "[" .. tostring(k) .. "]"
                else
                    keyStr = "[" .. SerializeValue(tostring(k)) .. "]"
                end
                parts[#parts + 1] = keyStr .. "=" .. SerializeValue(v)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return "nil"
    end
end

local function DeserializeValue(str, pos)
    pos = pos or 1
    -- Skip whitespace
    while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end

    local ch = str:sub(pos, pos)

    if ch == '"' then
        -- String
        local result = {}
        pos = pos + 1
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == "\\" and pos < #str then
                local next = str:sub(pos + 1, pos + 1)
                if next == "n" then result[#result + 1] = "\n"
                elseif next == "r" then result[#result + 1] = "\r"
                elseif next == "\\" then result[#result + 1] = "\\"
                elseif next == '"' then result[#result + 1] = '"'
                else result[#result + 1] = next end
                pos = pos + 2
            elseif c == '"' then
                return table.concat(result), pos + 1
            else
                result[#result + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(result), pos

    elseif ch == "{" then
        -- Table
        local tbl = {}
        local arrayIndex = 1
        pos = pos + 1
        while pos <= #str do
            while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
            if str:sub(pos, pos) == "}" then return tbl, pos + 1 end
            if str:sub(pos, pos) == "," then pos = pos + 1 end
            while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
            if str:sub(pos, pos) == "}" then return tbl, pos + 1 end

            if str:sub(pos, pos) == "[" then
                -- Keyed entry
                pos = pos + 1
                local key
                key, pos = DeserializeValue(str, pos)
                while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == "]" then pos = pos + 1 end
                while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == "=" then pos = pos + 1 end
                local val
                val, pos = DeserializeValue(str, pos)
                tbl[key] = val
            else
                -- Array entry (no key)
                local val
                val, pos = DeserializeValue(str, pos)
                tbl[arrayIndex] = val
                arrayIndex = arrayIndex + 1
            end
        end
        return tbl, pos

    elseif str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif str:sub(pos, pos + 2) == "nil" then
        return nil, pos + 3
    else
        -- Number
        local numStr = str:match("^%-?%d+%.?%d*[eE]?%-?%d*", pos)
        if numStr then
            return tonumber(numStr), pos + #numStr
        end
        return nil, pos + 1
    end
end

function ns:Serialize(tbl)
    return SerializeValue(tbl)
end

function ns:Deserialize(str)
    if not str or #str == 0 then return nil end
    local ok, result = pcall(DeserializeValue, str, 1)
    if ok then return result end
    return nil
end

-- ----------------------------------------------------------------------------
-- Profile Export/Import Helpers
-- Format: "BarWarden:v1:<base64-encoded-serialized-data>"
-- ----------------------------------------------------------------------------

function ns:ExportProfile(profileData)
    local serialized = self:Serialize(profileData)
    if not serialized then return nil end
    local encoded = Base64Encode(serialized)
    return "BarWarden:v1:" .. encoded
end

function ns:ImportProfile(str)
    if not str then return nil end
    local prefix, version, data = str:match("^(BarWarden):v(%d+):(.+)$")
    if not prefix or not data then return nil end
    if tonumber(version) ~= 1 then return nil end
    local decoded = Base64Decode(data)
    if not decoded then return nil end
    local result = self:Deserialize(decoded)
    if type(result) ~= "table" then return nil end
    return result
end
