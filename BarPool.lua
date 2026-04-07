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
    -- Clear stale state so recycled bars don't carry over old data
    bar.barData = nil
    bar.barIndex = nil
    bar.frameIndex = nil
    bar.barState = 0
    bar:SetValue(0)
    if bar.nameText then bar.nameText:SetText("") end
    if bar.timeText then bar.timeText:SetText("") end
    if bar.iconTexture then bar.iconTexture:SetTexture(nil) end
    table.insert(ns.barPool, bar)
end
