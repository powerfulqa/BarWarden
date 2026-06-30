-- Luacheck configuration for BarWarden (WoW 3.3.5a / WotLK / Lua 5.1).
-- Run:  luacheck *.lua
-- (Checks the 27 shipped top-level files; the bundled Libs/ and the tests/
-- harness are out of scope and excluded by the *.lua glob.)
-- The CI luacheck step is NON-BLOCKING (informational) for now, matching
-- EbonClearance's deferred gate; the luac -p syntax check is the hard gate.
-- See docs/ADDON_GUIDE.md for the rationale behind these settings.

std = "lua51"
max_line_length = 140

-- Ignore:
--   212/self : unused "self" argument (WoW script handlers are self-receiving,
--              and ns: methods that ignore self are common)
--   213      : unused loop variable (pairs/ipairs with only the value used)
--   631      : line is too long (some colour-coded strings are unavoidably long)
ignore = { "212/self", "213", "631" }

-- Saved variables, slash-command handles, and provenance globals the addon
-- writes at global scope. Everything else stays local on the `ns` table.
globals = {
    "BarWardenDB",
    "BarWardenAccountDB",
    "SLASH_BARWARDEN1",
    "SLASH_BARWARDEN2",
    "SlashCmdList",
    -- Provenance / attribution globals (see LICENSE; do not remove).
    "BARWARDEN_IDENT",
    "BARWARDEN_AUTHOR",
    "BARWARDEN_ORIGIN",
    "__BarWarden_origin",
    "__BarWarden_author",
    "__BarWarden_watermark",
    -- We register our own StaticPopup templates (StaticPopupDialogs.BARWARDEN_*).
    "StaticPopupDialogs",
    -- StaticPopup_Show returns named StaticPopupN frames we sometimes read.
    "_G",
}

-- WoW 3.3.5a API surface BarWarden touches. Add to this list rather than
-- silencing the whole check when the addon starts using a new API.
read_globals = {
    -- Frame / UI
    "CreateFrame", "UIParent", "GameTooltip", "Minimap",
    "GetCursorPosition", "GetEffectiveScale",
    "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "PanelTemplates_SetTab", "PanelTemplates_SetNumTabs",
    "PlaySound", "StaticPopup_Show", "StaticPopup_Hide",
    "UISpecialFrames",
    "FauxScrollFrame_GetOffset", "FauxScrollFrame_Update", "FauxScrollFrame_OnVerticalScroll",
    -- Dropdown menu API
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton",
    "UIDropDownMenu_SetWidth", "UIDropDownMenu_SetText", "UIDropDownMenu_SetSelectedID",
    "UIDropDownMenu_SetSelectedValue",
    -- Colour picker (per-bar colour swatch)
    "ColorPickerFrame", "OpacitySliderFrame",
    -- Chat / error handler
    "DEFAULT_CHAT_FRAME", "geterrorhandler",
    -- Spells / cooldowns / auras
    "GetSpellInfo", "GetSpellCooldown", "UnitAura", "UnitBuff", "UnitDebuff",
    "GetWeaponEnchantInfo", "GetTotemInfo",
    -- Class resources
    "GetComboPoints", "GetRuneCooldown", "GetRuneType", "UnitPower", "UnitPowerMax",
    -- Items
    "GetItemInfo", "GetItemIcon", "GetItemCooldown", "GetItemCount",
    "GetInventoryItemTexture",
    -- Units / player state
    "UnitClass", "UnitName", "UnitLevel", "UnitExists", "UnitAffectingCombat", "UnitInVehicle",
    "UnitHealth", "UnitHealthMax", "InCombatLockdown",
    "IsMounted", "IsResting", "IsInInstance",
    "GetNumPartyMembers", "GetNumRaidMembers",
    -- Talents (spec detection)
    "GetNumTalentTabs", "GetTalentTabInfo", "GetActiveTalentGroup",
    -- Class colours
    "RAID_CLASS_COLORS",
    -- Addon comms (Comms.lua)
    "SendAddonMessage", "SetItemRef",
    -- Metadata
    "GetAddOnMetadata", "GetBuildInfo",
    -- Misc utilities / Lua-ish globals provided by the client
    "hooksecurefunc", "wipe", "strtrim", "strsplit", "strjoin",
    "time", "date", "GetTime", "math", "string", "table",
}
