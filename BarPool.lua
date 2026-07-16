-- BarPool.lua - Object pool for bar frame recycling.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local _, ns = ...
ns.barPool = {}

function ns:AcquireBar(parent)
    local bar
    if #ns.barPool > 0 then
        bar = table.remove(ns.barPool)
        bar:SetParent(parent)
        bar:Show()
    else
        bar = ns:CreateBarFrame(parent)
    end
    return bar
end

function ns:ReleaseBar(bar)
    bar:Hide()
    bar:SetScript("OnUpdate", nil)
    bar:SetParent(UIParent)
    -- Cancel any active glow so the glow timer doesn't animate a pooled bar
    if ns.CancelBarGlow then ns:CancelBarGlow(bar) end
    -- Hide the cooldown spiral so a pooled bar isn't reused with a stale sweep
    if bar.cooldownFrame then bar.cooldownFrame:Hide() end
    -- Clear stale state so recycled bars don't carry over old data
    bar.barData = nil
    bar.barIndex = nil
    bar.frameIndex = nil
    bar.barState = 0
    bar.isResourceBar = false   -- resource-bar flag must not leak across pool reuse
    bar.isStaticBar = false     -- permanent-aura flag must not leak across pool reuse
    bar.expirationTime = nil
    bar.duration = nil
    bar.lingerRemaining = nil
    bar.stacks = nil
    bar.textElapsed = nil
    bar.isTestBar = nil
    bar._lastSparkX = nil
    bar:SetValue(0)
    if bar.nameText then bar.nameText:SetText("") end
    if bar.timeText then bar.timeText:SetText("") end
    if bar.iconTexture then bar.iconTexture:SetTexture(nil) end
    bar.glowStartTime = nil
    table.insert(ns.barPool, bar)
end
