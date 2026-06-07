-- tests/assert.lua
-- Tiny assertion helpers. Each raises on failure so the test runner's pcall
-- can catch and report. `level` offset in error() points blame one frame up
-- so the stack trace shows the calling test line, not this file.

local M = {}

local function fail(msg)
    error(msg, 3)
end

function M.assertEqual(actual, expected, msg)
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s",
            msg or "assertEqual", tostring(expected), tostring(actual)))
    end
end

function M.assertTrue(cond, msg)
    if not cond then fail(msg or "assertTrue failed") end
end

function M.assertFalse(cond, msg)
    if cond then fail(msg or "assertFalse failed (value was truthy)") end
end

function M.assertNil(v, msg)
    if v ~= nil then fail((msg or "assertNil") .. ": got " .. tostring(v)) end
end

function M.assertNotNil(v, msg)
    if v == nil then fail((msg or "assertNotNil") .. ": got nil") end
end

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function M.assertDeepEqual(actual, expected, msg)
    if not deepEqual(actual, expected) then
        fail((msg or "assertDeepEqual") .. ": tables differ")
    end
end

function M.assertError(fn, msg)
    local ok, err = pcall(fn)
    if ok then fail((msg or "assertError") .. ": no error raised") end
    return err
end

-- Asserts that `actual` has exactly the same top-level key set as `expected`
-- (value types/contents are not checked - use assertDeepEqual or specific
-- value asserts for that). The failure message enumerates missing/extra keys
-- so a schema drift test can point straight at the offending field rather
-- than emitting "tables differ".
function M.assertSameKeys(actual, expected, context)
    local missing, extras = {}, {}
    for k in pairs(expected) do
        if actual[k] == nil then missing[#missing + 1] = tostring(k) end
    end
    for k in pairs(actual) do
        if expected[k] == nil then extras[#extras + 1] = tostring(k) end
    end
    table.sort(missing)
    table.sort(extras)
    if #missing > 0 or #extras > 0 then
        local parts = {}
        if #missing > 0 then parts[#parts + 1] = "missing: " .. table.concat(missing, ", ") end
        if #extras  > 0 then parts[#parts + 1] = "extra: "   .. table.concat(extras,  ", ") end
        fail((context or "assertSameKeys") .. ": " .. table.concat(parts, "; "))
    end
end

return M
