local ADDON_NAME, NS = ...
NS.Commands = {}
local DB, Expand, Resolve, Macros = NS.DB, NS.Expand, NS.Resolve, NS.Macros

local TAG = "|cff33ff99[RoleTokens]|r "
local function out(fmt, ...) print(TAG .. fmt:format(...)) end

local function status()
    local units = Macros.lastUnits or {}
    out("current tokens:")
    for _, t in ipairs(Expand.TOKENS) do
        out("  @%-8s -> %s", t, Resolve.Describe(units[t]))
    end
    local pins = DB.Pins()
    for _, t in ipairs(Expand.TOKENS) do
        if pins[t] then out("  pinned @%s = %s", t, pins[t]) end
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
    out("  /rt            - show resolved tokens and managed macros")
    out("  /rt refresh    - re-scan macros and rewrite now")
    out("  /rt forget <MacroName> - stop managing a macro (its current text stays)")
    out("  /rt pin <token> <Name>  - e.g. /rt pin healer Moonwell; that player is @healer whenever grouped")
    out("  /rt unpin <token>       - clear a pin")
    out("  /rt quiet | /rt verbose - toggle chat notices")
    out("tokens: @tank @tank2 @healer @healer2. In raids the assigned main tank is @tank.")
end

SLASH_ROLETOKENS1 = "/rt"
SLASH_ROLETOKENS2 = "/roletokens"
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
        local token, name = rest:match("^@?(%S+)%s*(.*)$")
        token = (token or ""):lower()
        local valid = false
        for _, t in ipairs(Expand.TOKENS) do if t == token then valid = true end end
        if not valid then out("token must be one of: tank, tank2, healer, healer2") return end
        if cmd == "pin" then
            if name == "" then out("pin whom? /rt pin %s <Name>", token) return end
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
