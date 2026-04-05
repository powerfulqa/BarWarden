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
    table.insert(ns.barPool, bar)
end
