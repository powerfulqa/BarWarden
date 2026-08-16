-- tests/run.lua
-- Run with `lua tests/run.lua` from the repo root. Exit code is 0 on all
-- pass and 1 on any failure so CI can gate on it.

package.path = "./tests/?.lua;" .. (package.path or "")

local mock = require("mock_wow")
mock.install()

local TEST_FILES = {
    "test_utils",
    "test_db_migrations",
    "test_conditions",
    "test_trackers_logic",
    "test_auto_track",
    "test_resources",
    "test_activity_tracker",
    "test_stack_badge",
    "test_aura_groups",
    "test_class_presets",
    "test_settings_schema",
    "test_frame_manager",
    "test_unit_frames",
    "test_help",
    "test_hygiene",
    "test_comms_version",
    "test_migration",
    "test_bug_report",
    "test_bar_display_name",
}

local totalPass, totalFail = 0, 0
local failures = {}

for _, file in ipairs(TEST_FILES) do
    io.write(string.format("=== %s ===\n", file))
    local suite = require(file)

    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        mock.reset()
        local ok, err = pcall(suite[name])
        if ok then
            totalPass = totalPass + 1
            io.write(string.format("  PASS  %s\n", name))
        else
            totalFail = totalFail + 1
            failures[#failures + 1] = file .. " :: " .. name .. "\n    " .. tostring(err)
            io.write(string.format("  FAIL  %s\n    %s\n", name, tostring(err)))
        end
    end
end

io.write(string.format("\n%d passed, %d failed\n", totalPass, totalFail))
if totalFail > 0 then
    io.write("\nFailures:\n")
    for _, f in ipairs(failures) do
        io.write("  " .. f .. "\n")
    end
    os.exit(1)
end
os.exit(0)
