-- tests/test_hygiene.lua
-- Locks two repo conventions in CI so they cannot silently regress:
--   1. No em dashes (U+2014) in any shipped Lua file (the no-em-dash rule).
--   2. No leaked globals: a file-scope function must be `local function` or an
--      `ns:` / `ns.` method; a bare `function Foo()` at column 0 pollutes _G.
-- Reads the shipped file list from BarWarden.toc (so it auto-covers new files)
-- and scans the source directly. Run from the repo root (as tests/run.lua does).

local assertx = require("assert")

local M = {}

local EM_DASH = "\226\128\148" -- UTF-8 bytes for U+2014

-- Shipped Lua files from the TOC, excluding the bundled Libs/.
local function shippedFiles()
    local toc = io.open("BarWarden.toc", "r")
    assertx.assertNotNil(toc, "BarWarden.toc not found (run tests from the repo root)")
    local files = {}
    for line in toc:lines() do
        local path = line:gsub("%s+$", "")
        if path:match("%.lua$") and not path:match("^Libs[\\/]") then
            files[#files + 1] = (path:gsub("\\", "/"))
        end
    end
    toc:close()
    assertx.assertTrue(#files > 0, "no shipped .lua files parsed from BarWarden.toc")
    return files
end

local function readFile(path)
    local f = io.open(path, "r")
    assertx.assertNotNil(f, "could not open " .. path)
    local content = f:read("*a")
    f:close()
    return content
end

function M.test_noEmDashesInShippedLua()
    for _, path in ipairs(shippedFiles()) do
        local content = readFile(path)
        assertx.assertNil(content:find(EM_DASH, 1, true),
            "em dash (U+2014) found in " .. path .. " - use ' - ', commas, or colons")
    end
end

-- Intentional global overrides (each marked EC-TRAP at its site). SetItemRef is
-- replaced in Comms.lua to handle the custom update hyperlink on 3.3.5a.
local ALLOWED_GLOBAL_FN = { SetItemRef = true }

function M.test_noLeakedGlobalFunctions()
    for _, path in ipairs(shippedFiles()) do
        local content = readFile(path)
        local lineNo = 0
        for line in (content .. "\n"):gmatch("(.-)\n") do
            lineNo = lineNo + 1
            -- A bare `function Name(` at column 0 declares a global. `local
            -- function`, `ns:`/`ns.` methods, and local-table methods
            -- (`function Comms.foo`) all have a prefix or a dot/colon and are
            -- not matched by this pattern.
            local name = line:match("^function%s+([%w_]+)%s*%(")
            if name and not ALLOWED_GLOBAL_FN[name] then
                error(string.format("%s:%d leaks a global function: %s", path, lineNo, line), 0)
            end
        end
    end
end

return M
