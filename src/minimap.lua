local ADDON_NAME, NS = ...
NS.Minimap = {}
local Minimap_ = NS.Minimap
local DB, Macros = NS.DB, NS.Macros

-- Minimap button via LibDataBroker + LibDBIcon (vendored under Libs/).
-- Left-click opens the options page; the button can be hidden from the page
-- or with /rtk minimap. Position and hidden state live in RoleTokensDB.minimap.

local ldb, icon

function Minimap_.Init()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and icon) then return end
    ldb = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = "RoleTokens",
        icon = "Interface\\Icons\\Ability_Hunter_Misdirection",
        OnClick = function(_, button)
            if button == "RightButton" then Macros.Sync("manual refresh"); Macros.Say("refreshed")
            else NS.UI.Toggle() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("RoleTokens")
            local units = Macros.lastUnits or {}
            for _, name in ipairs(DB.TokenNames()) do
                local u = units[name .. "1"]
                tt:AddDoubleLine("@" .. name, u and (u .. " (" .. (UnitName(u) or "") .. ")") or "none", 1, 0.82, 0, u and 1 or 0.5, u and 1 or 0.5, u and 1 or 0.5)
            end
            tt:AddLine(" ")
            tt:AddLine("|cffaaaaaaLeft-click: options page.  Right-click: refresh macros now.|r")
        end,
    })
    icon:Register(ADDON_NAME, ldb, DB.Minimap())
    if icon.AddButtonToCompartment then icon:AddButtonToCompartment(ADDON_NAME) end
end

function Minimap_.SetShown(show)
    if not icon then return end
    DB.Minimap().hide = not show
    if show then icon:Show(ADDON_NAME) else icon:Hide(ADDON_NAME) end
    Macros.Say("minimap button %s", show and "shown" or "hidden (/rtk minimap to bring it back)")
end
