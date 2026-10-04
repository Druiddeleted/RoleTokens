local ADDON_NAME, NS = ...
NS.Menu = {}
local Menu_ = NS.Menu
local DB, Names, Macros = NS.DB, NS.Names, NS.Macros

-- Right-click a player anywhere the client offers a unit menu and add them to
-- a token without typing. Uses the retail menu system (Menu.ModifyMenu).
-- Verified in 12.1: PARTY/RAID/PLAYER menus carry unit+name+server (+ the
-- Battle.net account when they are a friend); BN_FRIEND rows carry
-- battleTag; guild rows carry name+server+guid.

-- No COMMUNITIES_* menus: our callback runs inside the member list's right-click
-- stack, which leaves taint on that frame, and its scroll initializer then trips
-- over secret booleans (CommunitiesMemberList.lua IsTruncated). Guildmates can
-- still be added from the window's picker.
local TAGS = { "PARTY", "RAID_PLAYER", "RAID", "TARGET", "FOCUS", "PLAYER",
               "FRIEND", "BN_FRIEND", "BN_FRIEND_OFFLINE", "GUILD", "GUILD_OFFLINE" }

-- Work out who the menu is about: character "Name-Realm" (or nil) and BattleTag (or nil).
local function identify(cd)
    local full, tag
    if cd.unit and UnitExists(cd.unit) then
        if UnitIsUnit(cd.unit, "player") then return nil end
        full = Names.UnitFull(cd.unit)
        tag = Names.FriendOfUnit(cd.unit)
    end
    if not full and cd.name and type(cd.name) == "string" and not cd.name:find("|K", 1, true) then
        if cd.name:find("-", 1, true) then full = Names.Normalize(cd.name)
        else full = cd.name .. "-" .. ((cd.server and cd.server ~= "" and cd.server:gsub("%s", "")) or Names.OwnRealm()) end
    end
    local acct = cd.accountInfo
    if not acct and cd.guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        acct = C_BattleNet.GetAccountInfoByGUID(cd.guid)
    end
    if not acct and cd.bnetIDAccount and C_BattleNet and C_BattleNet.GetAccountInfoByID then
        acct = C_BattleNet.GetAccountInfoByID(cd.bnetIDAccount)
    end
    tag = tag or cd.battleTag or (acct and acct.battleTag)
    -- friends-list rows carry no character name, but the account says which one they're on
    if not full and acct then full = Names.FriendCharacter(acct) end
    if full and Names.Key(full) == Names.Key(Names.UnitFull("player") or "") then return nil end
    return full, tag
end

local function disabled(desc, text)
    if desc and desc.SetEnabled then desc:SetEnabled(false) end
    return desc
end

local function build(owner, root, cd)
    local full, tag = identify(cd or {})
    if not full and not tag then return end
    local names = DB.TokenNames()

    root:CreateDivider()
    root:CreateTitle("RoleTokens")
    if #names == 0 then
        disabled(root:CreateButton("No tokens yet: /rtk token <name> add target", function() end))
        return
    end

    local function submenu(label, kind)
        local sub = root:CreateButton(label)
        for _, name in ipairs(names) do
            local token = DB.Token(name)
            local has = kind == "char" and DB.FindEntry(token, full, nil) or (kind == "bnet" and DB.FindEntry(token, nil, tag))
            if has then
                disabled(sub:CreateButton("@" .. name .. "  |cff888888on list|r", function() end))
            else
                sub:CreateButton("@" .. name, function()
                    local entry = kind == "char" and { kind = "char", name = full } or { kind = "bnet", tag = tag }
                    DB.AddEntry(token, entry)
                    Macros.Say("added %s to |cffffff00@%s|r", kind == "char" and Names.Short(full) or Names.TagPrefix(tag), name)
                    Macros.Sync("token changed")
                end)
            end
        end
    end
    if full then submenu("Add " .. Names.Short(full) .. " to", "char") end
    if tag then submenu("Add friend " .. Names.TagPrefix(tag) .. " to", "bnet") end

    for _, name in ipairs(names) do
        local token = DB.Token(name)
        local ci = full and DB.FindEntry(token, full, nil)
        local bi = tag and DB.FindEntry(token, nil, tag)
        if ci or bi then
            root:CreateButton("Remove from @" .. name, function()
                if ci then DB.RemoveEntry(token, ci) end
                local bi2 = tag and DB.FindEntry(token, nil, tag)
                if bi2 then DB.RemoveEntry(token, bi2) end
                Macros.Say("removed from |cffffff00@%s|r", name)
                Macros.Sync("token changed")
            end)
        end
        if bi and full and not ci then
            local e = token.entries[bi]
            local excluded = e.exclude and e.exclude[Names.Key(full)]
            root:CreateButton((excluded and "Allow " or "Never ") .. Names.Short(full) .. " for @" .. name, function()
                DB.SetExclude(e, full, not excluded)
                Macros.Sync("token changed")
            end)
        end
    end
end

function Menu_.Init()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, which in ipairs(TAGS) do
        Menu.ModifyMenu("MENU_UNIT_" .. which, build)
    end
end
