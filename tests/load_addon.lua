-- tests/load_addon.lua
--
-- Loads a BarWarden source file under standalone Lua, mimicking how WoW's
-- addon loader runs each `local addonName, ns = ...` header: the chunk is
-- called with the addon name and a shared namespace table as varargs.
--
-- Callers own the ns table, so a test can layer modules (Utils -> DB ->
-- Conditions) onto the same ns incrementally, or start fresh per test.

local M = {}

-- Resolve path relative to the addon root. Tests run from the repo root,
-- so module paths are just the bare filename ("Utils.lua", "DB.lua").
local ROOT = "./"

function M.setRoot(path)
    ROOT = path
    if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
end

function M.load(relativePath, addonName, ns)
    local full = ROOT .. relativePath
    local chunk, err = loadfile(full)
    if not chunk then
        error("load_addon: loadfile(" .. full .. ") failed: " .. tostring(err), 2)
    end
    return chunk(addonName or "BarWarden", ns)
end

-- Convenience: build a fresh ns with Utils pre-loaded (which every other
-- module depends on for CopyTable / MergeDefaults / InvalidateVisualCache
-- and for the GCD_THRESHOLD / MAX_AURA_INDEX constants).
function M.newNsWithUtils()
    local ns = {}
    M.load("Utils.lua", "BarWarden", ns)
    return ns
end

return M
