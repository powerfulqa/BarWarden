-- SharedMedia.lua - Optional LibSharedMedia integration.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- SharedMedia.lua - Optional LibSharedMedia-3.0 integration
--
-- If LSM is available (bundled or provided by another addon), BarWarden
-- registers its textures and fonts and exposes helpers for resolution and
-- dropdown population. If LSM is absent, everything falls back to the
-- hardcoded tables in Bar.lua and Options_Visuals.lua.
-- ============================================================================

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
ns.LSM = LSM

-- EC-TRAP: bailing the whole file when LSM is absent is intentional optional-dep
-- degradation, not dead code. Bar.lua and Options_Visuals.lua fall back to their
-- hardcoded media lists. Do NOT make LSM a hard requirement. See CLAUDE.md
-- (LibSharedMedia integration).
if not LSM then return end

-- Media type constants
local STATUSBAR = LSM.MediaType.STATUSBAR or "statusbar"
local FONT      = LSM.MediaType.FONT      or "font"

-- Register BarWarden's bundled textures
local T = "Interface\\AddOns\\BarWarden\\Textures\\"
local BW_TEXTURES = {
    ["BW Smooth"]   = T .. "Smooth.tga",
    ["BW Gloss"]    = T .. "Gloss.tga",
    ["BW Aluminum"] = T .. "Aluminum.tga",
    ["BW Armory"]   = T .. "Armory.tga",
    ["BW Graphite"] = T .. "Graphite.tga",
    ["BW Otravi"]   = T .. "Otravi.tga",
    ["BW Striped"]  = T .. "Striped.tga",
    ["BW Canvas"]   = T .. "Canvas.tga",
    ["BW LiteStep"] = T .. "LiteStep.tga",
    ["BW Glow"]     = T .. "Glow.tga",
    ["BW Metal"]    = T .. "Metal.tga",
    ["BW Leather"]  = T .. "Leather.tga",
}

for name, path in pairs(BW_TEXTURES) do
    LSM:Register(STATUSBAR, name, path)
end

-- Register BarWarden's bundled fonts
local BW_FONT = "Interface\\AddOns\\BarWarden\\Fonts\\"
local BW_FONTS = {
    ["BW Adventure"]     = BW_FONT .. "adventure.ttf",
    ["BW Bazooka"]       = BW_FONT .. "bazooka.ttf",
    ["BW Cooline"]       = BW_FONT .. "cooline.ttf",
    ["BW Diogenes"]      = BW_FONT .. "diogenes.ttf",
    ["BW Ginko"]         = BW_FONT .. "ginko.ttf",
    ["BW Heroic"]        = BW_FONT .. "heroic.ttf",
    ["BW Porky"]         = BW_FONT .. "porky.ttf",
    ["BW Talisman"]      = BW_FONT .. "talisman.ttf",
    ["BW Transformers"]  = BW_FONT .. "transformers.ttf",
    ["BW Yellow Jacket"] = BW_FONT .. "yellowjacket.ttf",
}

for name, path in pairs(BW_FONTS) do
    LSM:Register(FONT, name, path)
end

-- ============================================================================
-- Public helpers
-- ============================================================================

-- Resolve an LSM-registered name to a file path. Returns the path if found,
-- or nil so callers can fall back to their hardcoded lookup.
function ns:LSMFetch(mediaType, name)
    if not LSM or not name then return nil end
    return LSM:Fetch(mediaType, name)
end

-- Build a sorted dropdown items list from all LSM-registered media of a type.
-- Returns { { text = "Name", value = "Name" }, ... } compatible with
-- ns:CreateDropdown and the BuildSettings dropdown builder.
function ns:LSMDropdownItems(mediaType)
    if not LSM then return nil end
    local names = LSM:List(mediaType)
    if not names or #names == 0 then return nil end
    local items = {}
    for _, name in ipairs(names) do
        items[#items + 1] = { text = name, value = name }
    end
    return items
end
