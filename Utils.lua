-- Utils.lua - Shared helpers (CopyTable, MergeDefaults, GetVisual, ...).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Utils.lua - Shared utility functions for BarWarden
-- ============================================================================

-- Deep copy a table. Skips metatables.
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

-- Recursively fill in missing keys from `defaults` without overwriting
-- user-set values in `target`.
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

-- True if `frames` already holds a user layout worth protecting: any bar in
-- any group, or more than one group. Gates the first-login starter prompt so
-- it never auto-replaces an existing layout - the v1 "bars lost after
-- upgrading" data-loss bug, where an upgrader with one tuned group was treated
-- as a fresh install and had it overwritten.
function ns:HasExistingLayout(frames)
    if type(frames) ~= "table" then return false end
    if #frames > 1 then return true end
    for _, f in ipairs(frames) do
        if type(f) == "table" and f.bars and #f.bars > 0 then
            return true
        end
    end
    return false
end

-- Should the icon-corner stack badge be shown?
--
-- Only counts that mean something to the player: 2 or more. Suppressed on
-- resource bars (combo points and runes already read as current/max in the bar
-- text) and when the resolved text format is already showing the stack number,
-- so it never appears twice. Pure, so it is unit-testable.
function ns:ShouldShowStackBadge(stacks, textFormat, showStacks, isResourceBar)
    if showStacks == false then return false end
    if isResourceBar then return false end
    if textFormat == "NAME_STACKS" or textFormat == "STACKS" then return false end
    return (stacks or 0) >= 2
end

-- Build a group frame's anchor from its current screen edges.
--
-- Offsets are always expressed against UIParent's BOTTOMLEFT, which is the
-- screen origin and therefore 0 in every frame's own unit space. That lets
-- GetLeft/GetTop/GetBottom pass through verbatim: SetPoint offsets are already
-- interpreted in the frame's own scaled space, so any GetEffectiveScale
-- conversion here would double-apply the frame's scale. Doing exactly that was
-- the group-position drift bug - a scaled group's offset was multiplied by its
-- scale on every relayout and written back to the DB, so it crept toward the
-- corner and the error persisted across reloads.
--
-- Grow DOWN pins the top edge (bars grow downward); grow UP pins the bottom
-- edge (bars grow upward). Pure arithmetic, so it is unit-testable without
-- frame stubs.
function ns:NormalizeGroupAnchor(growUp, left, top, bottom)
    if growUp then
        return { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = left, y = bottom }
    end
    return { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
end

-- Format seconds as a readable uptime string: "12.3s", "5m 30s", "2h 15m".
function ns.FormatUptime(seconds)
    if not seconds or seconds <= 0 then return "0s" end
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    end
    if seconds < 3600 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds % 60)
        return string.format("%dm %ds", m, s)
    end
    if seconds < 86400 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds - h * 3600) / 60)
        return string.format("%dh %dm", h, m)
    end
    -- Days + hours for long cumulative all-time uptimes, so the value stays
    -- compact (e.g. "4d 20h" instead of "116h 46m", which wrapped the column).
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds - d * 86400) / 3600)
    return string.format("%dd %dh", d, h)
end

-- ----------------------------------------------------------------------------
-- One-shot delay
--
-- 3.3.5a has no C_Timer.After, so schedule fn to run once after `seconds`
-- via a shared OnUpdate ticker. Used by deferred UI tasks that must run
-- after a frame has laid out (the Help deep-link scroll). The ticker frame
-- is created lazily on first use so loading this file under the test mock
-- (which does not stub CreateFrame) stays frame-free.
-- ----------------------------------------------------------------------------

local afterQueue
local afterFrame

function ns:After(seconds, fn)
    if type(fn) ~= "function" then return end
    if not afterFrame then
        afterQueue = {}
        afterFrame = CreateFrame("Frame")
        afterFrame:SetScript("OnUpdate", function(_, elapsed)
            for i = #afterQueue, 1, -1 do
                local task = afterQueue[i]
                task.remaining = task.remaining - elapsed
                if task.remaining <= 0 then
                    table.remove(afterQueue, i)
                    task.fn()
                end
            end
        end)
    end
    afterQueue[#afterQueue + 1] = { remaining = seconds or 0, fn = fn }
end

-- ----------------------------------------------------------------------------
-- Shared constants
-- ----------------------------------------------------------------------------

-- EC-TRAP: the 1.5s floor intentionally hides global-cooldown triggers from the
-- cooldown/item trackers. Lowering it will spam bars on every GCD. Do NOT "fix".
ns.GCD_THRESHOLD = 1.5    -- ignore GCD triggers in cooldown/item trackers
ns.MAX_AURA_INDEX = 40    -- WoW 3.3.5a maximum buff/debuff index

-- Track modes that read auras. Shared by the event dispatcher in BarEngine and
-- the auto-track duplicate filter, which have to agree on what counts as
-- "already tracked" or the filter silently disagrees with the scanner.
ns.AURA_TRACK_MODES = { Buff = true, Debuff = true, Proc = true }

-- ----------------------------------------------------------------------------
-- Shared colour palette (design tokens)
--
-- Use these instead of inline |cff... hex so BarWarden and EbonClearance read
-- as one product family. Documented in docs/ADDON_GUIDE.md "Colour palette".
-- ----------------------------------------------------------------------------
ns.COLORS = {
    title    = "|cff4db8ff",  -- addon title (blue)
    good     = "|cffb6ffb6",  -- success / good (green)
    bad      = "|cffff4444",  -- error / bad (red)
    warning  = "|cffffb84d",  -- warning / note (orange)
    emphasis = "|cffffff00",  -- emphasis (yellow)
    prefix   = "|cff7fbfff",  -- chat prefix (cyan)
    muted    = "|cff888888",  -- muted / caption (grey)
}

-- ----------------------------------------------------------------------------
-- Config accessors
-- ----------------------------------------------------------------------------

-- Current visual settings, falling back to defaults before the DB is loaded
-- or if a fresh install hasn't populated the visual table yet.
--
-- Cached once BarWardenDB is loaded because Bar_OnUpdate and other hot paths
-- call this every frame. The cache holds a *reference* to the live visual
-- table, so edits via the options UI (which mutate BarWardenDB.visual in
-- place) are reflected without invalidation. Explicit invalidation is only
-- needed when the pointer itself changes, e.g. profile load/reset replacing
-- BarWardenDB.visual with a new table.
local cachedVisual
function ns:GetVisual()
    if cachedVisual then return cachedVisual end
    if not BarWardenDB then return ns.DEFAULTS.visual end
    cachedVisual = BarWardenDB.visual or ns.DEFAULTS.visual
    return cachedVisual
end

function ns:InvalidateVisualCache()
    cachedVisual = nil
end

-- ----------------------------------------------------------------------------
-- Callback bus
--
-- Tiny pub/sub so producers can fire-and-forget cross-module notifications
-- (e.g. "OnProfileChanged") without hard-coding the consumer list at the
-- call site. Firing with no subscribers is a no-op.
-- ----------------------------------------------------------------------------

local callbacks = {}

function ns:RegisterCallback(event, handler)
    callbacks[event] = callbacks[event] or {}
    callbacks[event][#callbacks[event] + 1] = handler
end

function ns:FireCallback(event, ...)
    local list = callbacks[event]
    if not list then return end
    for _, handler in ipairs(list) do
        handler(...)
    end
end

-- ----------------------------------------------------------------------------
-- Color helpers
-- ----------------------------------------------------------------------------

-- RAID_CLASS_COLORS is a Blizzard global available in 3.3.5a.
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
-- Base64 encode/decode
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
-- Fingerprint: salted, deterministic 24-bit djb2 hash.
--
-- Not cryptographic; the goal is trivial verifiability of BarWarden origin
-- in any derivative work. The salt below is a deliberately visible
-- signature: anyone with our source has it, but to use our fingerprint
-- format they must either (a) carry the salt verbatim - which is the
-- evidence - or (b) re-implement and diverge from the canonical export
-- format, also detectable. Do NOT "clean up" or refactor the salt string
-- away; its presence in code is the point.
--
-- The salt lives inside the function body (not at module scope) only so
-- it doesn't consume a main-chunk local slot - Lua 5.1 caps that at 200.
-- ----------------------------------------------------------------------------

function ns:Fingerprint(payload)
    local SALT = "BarWarden|Serv|powerfulqa|2026"
    local s = (payload or "") .. "|" .. SALT
    local h = 5381
    for i = 1, #s do
        -- djb2 step, folded to 24 bits so the printed form fits in 6 hex chars.
        h = ((h * 33) + string.byte(s, i)) % 16777216
    end
    return string.format("%06x", h)
end

-- ----------------------------------------------------------------------------
-- Table serializer / deserializer (for profile export/import).
-- Simple recursive key=value format; no external libraries required.
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
-- Profile export / import.
-- Format: "BarWarden:v1:<base64-encoded-serialized-data>".
-- ----------------------------------------------------------------------------

function ns:ExportProfile(profileData)
    local serialized = self:Serialize(profileData)
    if not serialized then return nil end
    local encoded = Base64Encode(serialized)
    local payload = "BarWarden:v1:" .. encoded
    -- Fingerprint suffix flags this export as BarWarden-produced. See
    -- ns:Fingerprint comment above for the convention.
    return payload .. ";fp=" .. self:Fingerprint(payload)
end

function ns:ImportProfile(str)
    if not str then return nil end
    -- Strip a trailing ";fp=<hex>" fingerprint suffix before format
    -- validation so pre-fingerprint and hand-edited strings still parse.
    -- The fingerprint marks our exports going OUT; imports tolerate both
    -- fingerprinted and unfingerprinted strings without warning.
    str = str:gsub(";fp=[0-9a-fA-F]+$", "")
    local prefix, version, data = str:match("^(BarWarden):v(%d+):(.+)$")
    if not prefix or not data then return nil end
    if tonumber(version) ~= 1 then return nil end
    local decoded = Base64Decode(data)
    if not decoded then return nil end
    local result = self:Deserialize(decoded)
    if type(result) ~= "table" then return nil end
    return result
end
