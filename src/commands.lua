local ADDON_NAME, NS = ...
NS.Commands = {}
local DB, Expand, Resolve, Macros = NS.DB, NS.Expand, NS.Resolve, NS.Macros

local TAG = "|cff33ff99[RoleTokens]|r "
local function out(fmt, ...) print(TAG .. fmt:format(...)) end

local function status()
    local units = Macros.lastUnits or {}
    out("current tokens:")
    local pins = DB.Pins()
    for _, role in ipairs(Expand.ROLES) do
        local shown = false
        for slot = 1, Expand.MAX_SLOT do
            local key = Expand.Key(role, slot)
            local unit, pin = units[key], pins[key]
            if unit or pin then
                shown = true
                out("  @%-9s -> %s%s", key, Resolve.Describe(unit),
                    pin and ("  |cff888888pinned: " .. pin .. "|r") or "")
            end
        end
        if not shown then out("  @%-9s -> %s", role, Resolve.Describe(nil)) end
    end
    local any = false
    DB.Each(function(scope, name, entry)
        any = true
        out("  managing |cffffff00%s|r (%s macro)", name, scope)
    end)
    if not any then
        out("no macros managed yet. Put @tank or @healer in any macro and it will be picked up.")
    end
end

local function help()
    out("usage:")
    out("  /rtk            - show resolved tokens and managed macros")
    out("  /rtk refresh    - re-scan macros and rewrite now")
    out("  /rtk forget <MacroName> - stop managing a macro (its current text stays)")
    out("  /rtk pin <token> <Name>  - e.g. /rtk pin healer Moonwell; that player is @healer whenever grouped")
    out("  /rtk unpin <token>       - clear a pin")
    out("  /rtk quiet | /rtk verbose - toggle chat notices")
    out("tokens: @tank/@tankN, @healer/@healerN, @dps/@dpsN for N up to 40 (@tank = @tank1).")
    out("in raids the assigned main tank is @tank unless something is pinned there.")
end

SLASH_ROLETOKENS1 = "/roletokens"
SLASH_ROLETOKENS2 = "/rtk"
SlashCmdList.ROLETOKENS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "status" then
        Macros.Sync()
        status()
    elseif cmd == "refresh" then
        Macros.Sync("manual refresh")
        status()
    elseif cmd == "forget" then
        if rest == "" then out("forget which macro?") return end
        if Macros.Forget(rest) then out("no longer managing |cffffff00%s|r", rest)
        else out("not managing any macro named |cffffff00%s|r", rest) end
    elseif cmd == "pin" or cmd == "unpin" then
        local word, name = rest:match("^@?(%S+)%s*(.*)$")
        local role, slot = Expand.ParseToken(word or "")
        if not role then out("token must be tank, healer or dps, optionally numbered 1-%d", Expand.MAX_SLOT) return end
        local token = Expand.Key(role, slot)
        if cmd == "pin" then
            if name == "" then out("pin whom? /rtk pin %s <Name>", token) return end
            DB.SetPin(token, name)
            out("@%s pinned to |cffffff00%s|r", token, name)
        else
            DB.SetPin(token, nil)
            out("@%s unpinned", token)
        end
        Macros.Sync("pin changed")
    elseif cmd == "quiet" then
        DB.SetVerbose(false); out("notices off")
    elseif cmd == "verbose" then
        DB.SetVerbose(true); out("notices on")
    else
        help()
    end
end
