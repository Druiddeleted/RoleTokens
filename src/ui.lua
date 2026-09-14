local ADDON_NAME, NS = ...
NS.UI = {}
local UI = NS.UI
local DB, Expand, Resolve, Macros, Names = NS.DB, NS.Expand, NS.Resolve, NS.Macros, NS.Names

-- The token window (/rtk ui). Built once on first open, repainted on demand.
-- Costs nothing while hidden: no frames until first open, no events while
-- closed. Picker data (friends, guild) is only walked while the picker is open.

local W, H = 640, 480
local LEFT_W = 150
local ROW_H, SUB_H = 26, 20
local GOLD = { 0.9, 0.7, 0.13 }
local GREY = "|cff888888"

local frame, picker
local selected            -- token name or "tank"/"healer"/"dps"
local scroll = 0
local lines = {}          -- flattened rows for the right pane
local rowPool = {}
local tokenButtons = {}

local function classColor(unit)
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS[class]
    return c and c:GenerateHexColor() or "ffdddddd"
end
local function classHexByFile(class)
    local c = class and RAID_CLASS_COLORS[class]
    return c and c:GenerateHexColor() or "ffdddddd"
end

-- ---- data -> lines ----------------------------------------------------------
local function buildLines()
    lines = {}
    if not selected then return end
    if Expand.IsRole(selected) then
        local units = Macros.lastUnits or {}
        for slot = 1, Expand.MAX_SLOT do
            local u = units[Expand.Key(selected, slot)]
            if not u then break end
            lines[#lines + 1] = { kind = "builtin", index = slot, label = ("@%s%s"):format(selected, slot == 1 and "" or slot),
                                  status = u .. "  |c" .. classColor(u) .. (UnitName(u) or "") .. "|r", present = true }
        end
        if #lines == 0 then lines[1] = { kind = "empty", label = "nobody in this role right now" } end
        return
    end
    local token = DB.Token(selected)
    if not token then return end
    local _, detail = Resolve.Units(DB.DropSelf(), { [selected] = token }, true)
    local rows = detail[selected] or {}
    if #rows == 0 then lines[1] = { kind = "empty", label = "empty. Use + Add, or right-click a player." } end
    for i, r in ipairs(rows) do
        local e = r.entry
        local status = r.status
        if r.unit then
            local f = Names.UnitFull(r.unit)
            status = status:gsub("on .*$", "on |c" .. classColor(r.unit) .. Names.Short(f or "") .. "|r")
        elseif e.kind == "bnet" and e.lastSeen then
            status = "last seen " .. Names.Short(e.lastSeen)
        end
        lines[#lines + 1] = { kind = "entry", index = i, entry = e, label = Names.Label(e) .. (e.kind == "bnet" and (GREY .. " (friend)|r") or ""),
                              status = status, present = r.slot ~= nil,
                              slot = r.slot and ("@" .. selected .. (r.slot == 1 and "" or r.slot)) or nil }
        if e.kind == "bnet" and e.exclude then
            local ex = {}
            for k in pairs(e.exclude) do ex[#ex + 1] = k end
            table.sort(ex)
            for _, k in ipairs(ex) do
                lines[#lines + 1] = { kind = "except", entry = e, key = k, label = "except", status = k }
            end
        end
    end
end

-- ---- widgets ---------------------------------------------------------------
local function makeIconButton(parent, texture, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", onClick)
    return b
end

local function getRow(i)
    local r = rowPool[i]
    if r then return r end
    r = CreateFrame("Frame", nil, frame.list)
    r:SetHeight(ROW_H)
    r:SetPoint("LEFT", frame.list, "LEFT", 0, 0)
    r:SetPoint("RIGHT", frame.list, "RIGHT", 0, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.num:SetPoint("LEFT", 8, 0); r.num:SetWidth(18); r.num:SetJustifyH("LEFT")
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(12, 12); r.dot:SetPoint("LEFT", 28, 0)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", 46, 0); r.label:SetWidth(150); r.label:SetJustifyH("LEFT")
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    r.status:SetPoint("LEFT", 200, 0); r.status:SetPoint("RIGHT", -110, 0); r.status:SetJustifyH("LEFT")
    r.slot = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.slot:SetPoint("RIGHT", -8, 0)
    r.del = makeIconButton(r, "Interface\\RaidFrame\\ReadyCheck-NotReady", 16, function() r.onDelete() end)
    r.del:SetPoint("RIGHT", -8, 0)
    r.down = makeIconButton(r, "Interface\\Buttons\\Arrow-Down-Up", 16, function() r.onMove(1) end)
    r.down:SetPoint("RIGHT", r.del, "LEFT", -4, -2)
    r.up = makeIconButton(r, "Interface\\Buttons\\Arrow-Up-Up", 16, function() r.onMove(-1) end)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -4, 4)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function() r.bg:SetColorTexture(1, 1, 1, 0.06); r.up:SetAlpha(1); r.down:SetAlpha(1); r.del:SetAlpha(1) end)
    r:SetScript("OnLeave", function() r.bg:SetColorTexture(r.present and 0.12 or 0.09, r.present and 0.17 or 0.09, r.present and 0.12 or 0.09, 1); r.up:SetAlpha(0.35); r.down:SetAlpha(0.35); r.del:SetAlpha(0.35) end)
    rowPool[i] = r
    return r
end

local function paintRows()
    local list = frame.list
    local avail = list:GetHeight()
    local y = 0
    local visible = 0
    local skip = scroll
    for i = 1, #rowPool do rowPool[i]:Hide() end
    local ri = 0
    for li, line in ipairs(lines) do
        if skip > 0 then skip = skip - 1
        else
            local h = line.kind == "except" and SUB_H or ROW_H
            if y + h > avail then break end
            ri = ri + 1
            local r = getRow(ri)
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
            r.present = line.present
            r.num:SetText(line.index and line.kind == "entry" and tostring(line.index) or "")
            r.dot:SetShown(line.kind == "entry")
            r.dot:SetTexture(line.present and "Interface\\COMMON\\Indicator-Green" or "Interface\\COMMON\\Indicator-Gray")
            r.label:SetText(line.label or "")
            r.label:SetFontObject(line.kind == "except" and "GameFontDisableSmall" or line.kind == "builtin" and "GameFontNormal" or "GameFontHighlight")
            r.status:SetText(line.status or "")
            r.slot:SetText(line.slot or "")
            r.slot:SetShown(line.slot ~= nil)
            local editable = line.kind == "entry"
            r.up:SetShown(editable); r.down:SetShown(editable)
            r.del:SetShown(editable or line.kind == "except")
            if line.slot then r.del:ClearAllPoints(); r.del:SetPoint("RIGHT", r.slot, "LEFT", -10, 0)
            else r.del:ClearAllPoints(); r.del:SetPoint("RIGHT", -8, 0) end
            if line.kind == "except" then
                r.label:ClearAllPoints(); r.label:SetPoint("LEFT", 46, 0)
                r.status:SetPoint("LEFT", 100, 0)
            else
                r.status:SetPoint("LEFT", 200, 0)
            end
            r.onMove = function(dir)
                local token = DB.Token(selected)
                if token and DB.MoveEntry(token, line.index, line.index + dir) then Macros.Sync("token changed") end
            end
            r.onDelete = function()
                local token = DB.Token(selected)
                if not token then return end
                if line.kind == "except" then DB.SetExclude(line.entry, line.key, false)
                else DB.RemoveEntry(token, line.index) end
                Macros.Sync("token changed")
            end
            r:GetScript("OnLeave")(r)
            r:Show()
            y = y + h
            visible = visible + 1
        end
    end
    frame.moreBelow:SetShown(scroll + visible < #lines)
end

local function paintTokens()
    local names = DB.TokenNames()
    local all = { "tank", "healer", "dps" }
    for _, n in ipairs(names) do all[#all + 1] = n end
    for i, name in ipairs(all) do
        local b = tokenButtons[i]
        if not b then
            b = CreateFrame("Button", nil, frame.left)
            b:SetHeight(24)
            b:SetPoint("LEFT", 0, 0); b:SetPoint("RIGHT", 0, 0)
            b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
            b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetWidth(2); b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.text:SetPoint("LEFT", 12, 0)
            b:SetScript("OnClick", function() selected = b.name; scroll = 0; UI.Refresh() end)
            tokenButtons[i] = b
        end
        b.name = name
        local y = (i <= 3) and (22 + (i - 1) * 24) or (22 + 3 * 24 + 26 + (i - 4) * 24)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame.left, "TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", frame.left, "TOPRIGHT", 0, -y)
        b.text:SetText("@" .. name)
        local builtin = i <= 3
        local sel = name == selected
        b.text:SetFontObject(builtin and "GameFontDisable" or sel and "GameFontNormal" or "GameFontHighlight")
        b.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], sel and 0.18 or 0)
        b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], sel and 1 or 0)
        b:Show()
    end
    for i = #all + 1, #tokenButtons do tokenButtons[i]:Hide() end
    frame.yoursHeader:SetShown(true)
end

local function paintHeader()
    local custom = selected and not Expand.IsRole(selected)
    frame.title:SetText(selected and ("@" .. selected) or "")
    frame.roleBtn:SetShown(custom)
    frame.delBtn:SetShown(custom)
    frame.addBtn:SetShown(custom)
    if custom then
        local token = DB.Token(selected)
        frame.roleBtn:SetText("Role: " .. ((token and token.role) or "any"))
    end
    local units = Macros.lastUnits or {}
    local parts = {}
    if selected then
        for slot = 1, 4 do
            local u = units[Expand.Key(selected, slot)]
            local key = ("@%s%s"):format(selected, slot == 1 and "" or slot)
            parts[#parts + 1] = ("|cffffd100%s|r %s"):format(key, u and ("→ " .. u) or (GREY .. "→ none|r"))
            if not u then break end
        end
    end
    frame.resolves:SetText(#parts > 0 and (GREY .. "resolves now:|r  " .. table.concat(parts, "   ")) or "")
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    if selected and not Expand.IsRole(selected) and not DB.Token(selected) then selected = nil end
    if not selected then selected = DB.TokenNames()[1] or "tank" end
    paintTokens()
    paintHeader()
    buildLines()
    if scroll > math.max(0, #lines - 1) then scroll = math.max(0, #lines - 1) end
    paintRows()
    if picker and picker:IsShown() then UI.RefreshPicker() end
end

function UI.OnSync() UI.Refresh() end

-- ---- picker ----------------------------------------------------------------
local pickRows = {}
local pickItems = {}
local pickScroll = 0
local PICK_ROW = 24

local function buildPickItems()
    pickItems = {}
    local token = DB.Token(selected)
    if not token then return end
    local filter = (picker.search:GetText() or ""):lower()
    local function want(text) return filter == "" or text:lower():find(filter, 1, true) end
    local function header(t) pickItems[#pickItems + 1] = { header = t } end

    -- Group: adds the character
    local units = {}
    if IsInRaid() then for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end end
    local first = true
    for _, u in ipairs(units) do
        if not UnitIsUnit(u, "player") then
            local full = Names.UnitFull(u)
            if full and want(full) then
                if first then header("Group  " .. GREY .. "adds the character|r"); first = false end
                local role = Resolve.ROLE_OF[UnitGroupRolesAssigned(u)]
                pickItems[#pickItems + 1] = { text = "|c" .. classColor(u) .. Names.Short(full) .. "|r", note = role or "",
                    onList = DB.FindEntry(token, full, nil) ~= nil, entry = { kind = "char", name = full } }
            end
        end
    end
    -- Friends online: adds the friend on any character
    first = true
    if BNGetNumFriends then
        for i = 1, (BNGetNumFriends() or 0) do
            local acct = C_BattleNet.GetFriendAccountInfo(i)
            if acct and acct.battleTag and acct.gameAccountInfo and acct.gameAccountInfo.isOnline then
                local prefix = Names.TagPrefix(acct.battleTag)
                local char = Names.FriendCharacter(acct, i)
                if want(prefix) or (char and want(char)) then
                    if first then header("Friends online  " .. GREY .. "adds the friend, any character|r"); first = false end
                    pickItems[#pickItems + 1] = { text = prefix, note = char and ("on " .. Names.Short(char)) or "not in WoW",
                        onList = DB.FindEntry(token, nil, acct.battleTag) ~= nil, entry = { kind = "bnet", tag = acct.battleTag, lastSeen = char } }
                end
            end
        end
    end
    -- Guild online: adds the character
    first = true
    if IsInGuild() then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, _, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
            if name and online and want(name) then
                local full = Names.Normalize(name)
                if Names.Key(full) ~= Names.Key(Names.UnitFull("player") or "") then
                    if first then header("Guild online  " .. GREY .. "adds the character|r"); first = false end
                    pickItems[#pickItems + 1] = { text = "|c" .. classHexByFile(class) .. Names.Short(full) .. "|r", note = "",
                        onList = DB.FindEntry(token, full, nil) ~= nil, entry = { kind = "char", name = full } }
                end
            end
        end
    end
    if filter ~= "" and filter:match("^[^%s#]+$") then
        pickItems[#pickItems + 1] = { text = "Add " .. Names.Short(Names.Normalize(picker.search:GetText())) .. " as typed", note = "",
            entry = { kind = "char", name = Names.Normalize(picker.search:GetText()) } }
    end
end

local function addFromPicker(item)
    local token = DB.Token(selected)
    if not token or not item.entry then return end
    local _, new = DB.AddEntry(token, item.entry)
    if new then Macros.Say("added %s to |cffffff00@%s|r", item.entry.kind == "char" and Names.Short(item.entry.name) or Names.TagPrefix(item.entry.tag), selected) end
    Macros.Sync("token changed")
end

function UI.RefreshPicker()
    if not picker or not picker:IsShown() then return end
    buildPickItems()
    local avail = picker.list:GetHeight()
    local maxRows = math.floor(avail / PICK_ROW)
    if pickScroll > math.max(0, #pickItems - maxRows) then pickScroll = math.max(0, #pickItems - maxRows) end
    for i = 1, #pickRows do pickRows[i]:Hide() end
    for ri = 1, maxRows do
        local item = pickItems[ri + pickScroll]
        if not item then break end
        local r = pickRows[ri]
        if not r then
            r = CreateFrame("Button", nil, picker.list)
            r:SetHeight(PICK_ROW)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.text:SetPoint("LEFT", 8, 0)
            r.note = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.note:SetPoint("LEFT", r.text, "RIGHT", 6, 0)
            r.right = r:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall"); r.right:SetPoint("RIGHT", -8, 0)
            r:SetScript("OnEnter", function() if r.item and r.item.entry then r.bg:SetColorTexture(1, 1, 1, 0.08) end end)
            r:SetScript("OnLeave", function() r.bg:SetColorTexture(0, 0, 0, 0) end)
            r:SetScript("OnClick", function() if r.item and r.item.entry and not r.item.onList then addFromPicker(r.item) end end)
            pickRows[ri] = r
        end
        r.item = item
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", picker.list, "TOPLEFT", 0, -(ri - 1) * PICK_ROW)
        r:SetPoint("TOPRIGHT", picker.list, "TOPRIGHT", 0, -(ri - 1) * PICK_ROW)
        if item.header then
            r.text:SetFontObject("GameFontDisableSmall"); r.text:SetText(item.header:upper():gsub("|CFF", "|cff"):gsub("|R", "|r"))
            r.note:SetText(""); r.right:SetText("")
        else
            r.text:SetFontObject("GameFontHighlight"); r.text:SetText(item.text)
            r.note:SetText(item.note or ""); r.right:SetText(item.onList and "on list" or "")
        end
        r.bg:SetColorTexture(0, 0, 0, 0)
        r:Show()
    end
end

local function buildPicker()
    picker = CreateFrame("Frame", "RoleTokensPicker", frame, "BackdropTemplate")
    picker:SetSize(300, 300)
    picker:SetPoint("TOPLEFT", frame.addBtn, "BOTTOMLEFT", 0, -4)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(frame:GetFrameLevel() + 20)
    picker:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    picker:EnableMouse(true)
    picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.title:SetPoint("TOP", 0, -8)
    picker.search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    picker.search:SetSize(270, 22)
    picker.search:SetPoint("TOP", 0, -28)
    picker.search:SetAutoFocus(false)
    picker.search:SetScript("OnTextChanged", function() pickScroll = 0; UI.RefreshPicker() end)
    picker.search:SetScript("OnEscapePressed", function() picker:Hide() end)
    picker.search:SetScript("OnEnterPressed", function()
        for _, item in ipairs(pickItems) do
            if item.entry and not item.onList then addFromPicker(item); break end
        end
    end)
    picker.hint = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.hint:SetPoint("TOPLEFT", picker.search, "BOTTOMLEFT", -2, -2)
    picker.hint:SetText("search, or type Name-Realm and press Enter")
    picker.list = CreateFrame("Frame", nil, picker)
    picker.list:SetPoint("TOPLEFT", 6, -66)
    picker.list:SetPoint("BOTTOMRIGHT", -6, 6)
    picker.list:EnableMouseWheel(true)
    picker.list:SetScript("OnMouseWheel", function(_, d) pickScroll = math.max(0, pickScroll - d * 3); UI.RefreshPicker() end)
    picker:SetScript("OnShow", function()
        picker.title:SetText("Add to @" .. (selected or ""))
        pickScroll = 0
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        picker.events:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        picker.events:RegisterEvent("FRIENDLIST_UPDATE")
        picker.events:RegisterEvent("GUILD_ROSTER_UPDATE")
        UI.RefreshPicker()
    end)
    picker:SetScript("OnHide", function() picker.events:UnregisterAllEvents() end)
    picker.events = CreateFrame("Frame")
    picker.events:SetScript("OnEvent", function() UI.RefreshPicker() end)
end

-- ---- panel (Options -> AddOns -> RoleTokens) ------------------------------
local category

local function build()
    frame = CreateFrame("Frame", "RoleTokensPanel")
    frame:SetSize(W, H)   -- the settings canvas resizes it; this is the design size
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10); title:SetText("RoleTokens")
    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText(GREY .. "@tank / @healer / @dps by role; your tokens by priority list. Fallbacks go in the macro: [@pi,exists,nodead] [@dps,exists,nodead]|r")

    frame.minimapCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.minimapCB:SetSize(24, 24)
    frame.minimapCB:SetPoint("TOPRIGHT", -8, -6)
    frame.minimapCB.text = frame.minimapCB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.minimapCB.text:SetPoint("RIGHT", frame.minimapCB, "LEFT", -2, 0)
    frame.minimapCB.text:SetText("Minimap button")
    frame.minimapCB:SetScript("OnClick", function(self) if NS.Minimap then NS.Minimap.SetShown(self:GetChecked()) end end)

    -- left pane
    frame.left = CreateFrame("Frame", nil, frame)
    frame.left:SetPoint("TOPLEFT", 8, -40)
    frame.left:SetPoint("BOTTOMLEFT", 8, 8)
    frame.left:SetWidth(LEFT_W)
    local sep = frame.left:CreateTexture(nil, "ARTWORK"); sep:SetWidth(1); sep:SetColorTexture(1, 1, 1, 0.1)
    sep:SetPoint("TOPRIGHT"); sep:SetPoint("BOTTOMRIGHT")
    local h1 = frame.left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h1:SetPoint("TOPLEFT", 12, -6); h1:SetText("BUILT IN")
    frame.yoursHeader = frame.left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.yoursHeader:SetPoint("TOPLEFT", 12, -(22 + 3 * 24 + 8)); frame.yoursHeader:SetText("YOURS")
    frame.newBtn = CreateFrame("Button", nil, frame.left, "UIPanelButtonTemplate")
    frame.newBtn:SetSize(LEFT_W - 20, 24)
    frame.newBtn:SetPoint("BOTTOM", -1, 6)
    frame.newBtn:SetText("+ New token")
    frame.newBtn:SetScript("OnClick", function() StaticPopup_Show("ROLETOKENS_NEW_TOKEN") end)

    -- right pane
    frame.right = CreateFrame("Frame", nil, frame)
    frame.right:SetPoint("TOPLEFT", frame.left, "TOPRIGHT", 12, 0)
    frame.right:SetPoint("BOTTOMRIGHT", -10, 8)
    frame.title = frame.right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 4, -8)
    frame.delBtn = CreateFrame("Button", nil, frame.right, "UIPanelButtonTemplate")
    frame.delBtn:SetSize(70, 22); frame.delBtn:SetPoint("TOPRIGHT", 0, -6); frame.delBtn:SetText("Delete")
    frame.delBtn:SetScript("OnClick", function() StaticPopup_Show("ROLETOKENS_DELETE_TOKEN", "@" .. selected, nil, selected) end)
    frame.roleBtn = CreateFrame("Button", nil, frame.right, "UIPanelButtonTemplate")
    frame.roleBtn:SetSize(110, 22); frame.roleBtn:SetPoint("RIGHT", frame.delBtn, "LEFT", -6, 0)
    frame.roleBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(owner, root)
            root:CreateTitle("Only count them while playing")
            local token = DB.Token(selected)
            local function isSel(v) return token and token.role == v end
            local function set(v) DB.SetRole(selected, v); Macros.Sync("token changed") end
            root:CreateRadio("any role", isSel, set, nil)
            for _, r in ipairs(Expand.ROLES) do root:CreateRadio(r, isSel, set, r) end
        end)
    end)
    frame.list = CreateFrame("Frame", nil, frame.right)
    frame.list:SetPoint("TOPLEFT", 0, -38)
    frame.list:SetPoint("BOTTOMRIGHT", 0, 34)
    frame.list:EnableMouseWheel(true)
    frame.list:SetScript("OnMouseWheel", function(_, d) scroll = math.max(0, scroll - d); paintRows() end)
    local lbg = frame.list:CreateTexture(nil, "BACKGROUND"); lbg:SetAllPoints(); lbg:SetColorTexture(0, 0, 0, 0.25)
    frame.moreBelow = frame.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.moreBelow:SetPoint("BOTTOM", 0, 2); frame.moreBelow:SetText("scroll for more")
    frame.addBtn = CreateFrame("Button", nil, frame.right, "UIPanelButtonTemplate")
    frame.addBtn:SetSize(70, 24); frame.addBtn:SetPoint("BOTTOMLEFT", 0, 4); frame.addBtn:SetText("+ Add")
    frame.addBtn:SetScript("OnClick", function()
        if not picker then buildPicker() end
        if picker:IsShown() then picker:Hide() else picker:Show(); picker.search:SetText(""); picker.search:SetFocus() end
    end)
    frame.resolves = frame.right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.resolves:SetPoint("BOTTOMRIGHT", 0, 9); frame.resolves:SetPoint("LEFT", frame.addBtn, "RIGHT", 10, 0)
    frame.resolves:SetJustifyH("RIGHT")

    frame:SetScript("OnShow", function()
        frame.minimapCB:SetChecked(not DB.Minimap().hide)
        Macros.Sync(); UI.Refresh()
    end)
    frame:SetScript("OnHide", function() if picker then picker:Hide() end end)

    StaticPopupDialogs["ROLETOKENS_NEW_TOKEN"] = {
        text = "New token name (letters only, used as @name in macros):",
        button1 = CREATE or "Create", button2 = CANCEL, hasEditBox = true, maxLetters = 12,
        whileDead = true, hideOnEscape = true, timeout = 0,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local name, why = Expand.ValidName(eb and eb:GetText() or "")
            if not name then Macros.Say("|cffff4444%s|r", why or "invalid name") return end
            DB.CreateToken(name); selected = name; scroll = 0
            Macros.Sync("token changed")
        end,
        EditBoxOnEnterPressed = function(self) StaticPopup_OnClick(self:GetParent(), 1) end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopupDialogs["ROLETOKENS_DELETE_TOKEN"] = {
        text = "Delete %s? Macros keep their text; it just stops being rewritten.",
        button1 = DELETE or "Delete", button2 = CANCEL, whileDead = true, hideOnEscape = true, timeout = 0,
        OnAccept = function(self, name) DB.DeleteToken(name); selected = nil; Macros.Sync("token changed") end,
    }

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(frame, "RoleTokens")
        category.ID = "RoleTokens"
        Settings.RegisterAddOnCategory(category)
    end
end

-- Called once at PLAYER_LOGIN so the category exists in Options -> AddOns
-- before anyone opens the panel. Cheap: frames only, no data work until shown.
function UI.Init()
    if not frame then build() end
end

function UI.Toggle()
    if not frame then build() end
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category.ID)
    end
end
