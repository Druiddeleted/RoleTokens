local ADDON_NAME, NS = ...
local DB, Macros = NS.DB, NS.Macros

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

-- Roster changes arrive in bursts (several events per join), so collapse them
-- into one sync on the next frame.
local pending = false
local pendingReason
local function syncSoon(reason)
    pendingReason = pendingReason or reason
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        local r = pendingReason
        pendingReason = nil
        Macros.Sync(r)
    end)
end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then DB.Init() end
    elseif event == "PLAYER_LOGIN" then
        for _, line in ipairs(DB.TakeNotices()) do Macros.Say(line) end
        if NS.Menu then NS.Menu.Init() end
        if NS.UI then NS.UI.Init() end
        if NS.Minimap then NS.Minimap.Init() end
        f:RegisterEvent("GROUP_ROSTER_UPDATE")
        f:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        f:RegisterEvent("ROLE_CHANGED_INFORM")
        f:RegisterEvent("PARTY_LEADER_CHANGED")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("UPDATE_MACROS")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        syncSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Macros.OnCombatEnd()
    elseif event == "UPDATE_MACROS" then
        syncSoon()                       -- silent: our own edits fire this too
    elseif event == "PLAYER_ENTERING_WORLD" then
        syncSoon()
    else
        syncSoon("group changed")
    end
end)
