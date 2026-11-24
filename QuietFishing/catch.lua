local _, ns = ...

-- Same key catches: the key you fished with reels the line in, as the controller's interact button does. When the
-- macro casts from a key (an action bar's, or a crossbar button's: held as its /click runs), that key is bound to
-- the game's Interact with Target while the line is out: a press then reels in the bobber the game has
-- soft-targeted. (A crossbar button's key is the pad button itself, L2 / R2 or not: the crossbar reads those
-- itself, so the binding catches its press on every bar.) Soft targeting
-- of objects is often on for the pad only, so it's put on for the keyboard and mouse too while the line is out,
-- and back as it was after (QuietFishingDB.softWas keeps it over a reload). Override bindings can't change in a
-- fight: they go as one starts (PLAYER_REGEN_DISABLED comes just before the lockdown). Never Left / Right click.
-- /qfish catch on | off.
local INTERACT = "INTERACTTARGET"
local SOFT = "SoftTargetInteract"
local SOFT_BOTH = "3" -- soft targeting for the pad and the keyboard / mouse
local PREFIXES = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON" }
local MODS = { SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown, ALT = IsAltKeyDown }
local MOUSE = { BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

local owner = CreateFrame("Frame")
local keys, capturedAt = {}, 0
local bound = false
local told = false

local function Enabled()
    return ns.DB().catch ~= false
end

-- A binding's key held right now, with just its modifiers ("SHIFT-5"); never a left / right click. A pad button
-- counts held whatever else is (the pad's own shoulders may stand in for Shift / Ctrl).
local function Held(key)
    local base, wanted = key, {}
    while true do
        local mod, rest = base:match("^(%u+)%-(.+)$")
        if not (mod and MODS[mod]) then break end
        wanted[mod] = true
        base = rest
    end
    if base:find("^PAD") then return IsKeyDown(base) and true or false end
    if base == "BUTTON1" or base == "BUTTON2" then return false end
    local down
    if MOUSE[base] then
        down = IsMouseButtonDown and IsMouseButtonDown(MOUSE[base])
    elseif base:find("^BUTTON") or base:find("^MOUSEWHEEL") then
        return false
    else
        down = IsKeyDown(base)
    end
    if not down then return false end
    for mod, isDown in pairs(MODS) do
        if (wanted[mod] or false) ~= (isDown() and true or false) then return false end
    end
    return true
end

-- The keys that can press the macro: the macro's own binding, the action bars', the crossbar's (the D-pad and face
-- buttons, Native.lua in Improved Forever). Read again when the bindings change.
local candidates
local function Candidates()
    if candidates then return candidates end
    candidates = {}
    local commands = { "MACRO " .. ns.MACRO }
    for _, prefix in ipairs(PREFIXES) do
        for n = 1, 12 do commands[#commands + 1] = prefix .. n end
    end
    for n = 1, 8 do commands[#commands + 1] = "GAMEPADACTIONBUTTON" .. n end
    for _, command in ipairs(commands) do
        for _, key in ipairs({ GetBindingKey(command) }) do candidates[#candidates + 1] = key end
    end
    return candidates
end

-- When each was last seen going down. A press that runs on its release (a crossbar's, or with "cast on key
-- release") has the key up again by the time the macro runs, so held-now alone misses it. The controller's face
-- buttons and D-pad count whatever they're bound to (the crossbar may press a slot through bindings of its own);
-- never the triggers or shoulders, which the crossbar holds as modifiers.
local PAD_BUTTONS = { "PAD1", "PAD2", "PAD3", "PAD4", "PAD5", "PAD6", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT",
    "PADLSTICK", "PADRSTICK", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4" }
local RECENT = 0.6 -- seconds a key counts as just pressed
local downAt, wasDown = {}, {}
local function Watch(key, now)
    local down = Held(key)
    if down and not wasDown[key] then downAt[key] = now end
    wasDown[key] = down
end
-- Pressed for the press at capturedAt: held still, or seen going down from RECENT before it to just after it. (The
-- game reports a key as down only after the macro its press runs: in the press itself, IsKeyDown is still false.)
local function Recent(key)
    local at = downAt[key]
    return Held(key) or (at and at >= capturedAt - RECENT and at <= capturedAt + 0.2)
end

-- Which key made the press, worked out a frame after it (above): the action bar key (or the macro's own key
-- binding), or the controller button pressed last. The controller press set on Improved Forever's Bindings tab
-- first: that one alone (it's ours, switched there: ns.SetPadReel).
local viaPadBind = false
local unresolved = false
local function Resolve()
    if not unresolved then return end
    unresolved = false
    local padKey = ns.PadBindKey and ns.PadBindKey()
    if padKey and Recent(padKey) then
        keys[1], viaPadBind = padKey, true
        return
    end
    for _, key in ipairs(Candidates()) do
        if Recent(key) then keys[#keys + 1] = key end
    end
    if #keys > 0 then return end
    local last, lastAt
    for _, key in ipairs(PAD_BUTTONS) do
        local at = Recent(key) and (downAt[key] or capturedAt)
        if at and (not lastAt or at > lastAt) then last, lastAt = key, at end
    end
    if last then keys[1] = last end
end

-- At the press: noted, worked out on the next frame (the poller), or sooner if the line is out already
local function Capture()
    wipe(keys)
    viaPadBind = false
    capturedAt = GetTime()
    unresolved = not InCombatLockdown() and Enabled()
end

-- Every frame with the pole in hand (the press that casts): keys going down, and the last press worked out
local poller = CreateFrame("Frame")
poller:SetScript("OnUpdate", function()
    if not Enabled() or not ns.PoleOut() then return end
    local now = GetTime()
    for _, key in ipairs(PAD_BUTTONS) do Watch(key, now) end
    for _, key in ipairs(Candidates()) do Watch(key, now) end
    if unresolved and now > capturedAt then Resolve() end
end)

-- For /qfish, to see where reeling in stops: the controller buttons seen going down in the 3 s before the last
-- press, what each captured key does right now (overrides counted), soft targeting, and what it has targeted.
local function SeenBefore()
    local seen = {}
    for key, at in pairs(downAt) do
        local before = capturedAt - at
        if before >= -0.1 and before <= 3 then seen[#seen + 1] = string.format("%s %.2fs", key, before) end
    end
    return #seen > 0 and table.concat(seen, ", ") or "none"
end

function ns.CatchDetail()
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = key .. " does " .. tostring(GetBindingAction(key, true))
    end
    local ok, soft = pcall(UnitName, "softinteract")
    return "pressed before the cast: " .. SeenBefore()
        .. ";  " .. (#parts > 0 and table.concat(parts, ", ") or "no key taken")
        .. ";  bound " .. tostring(bound) .. (viaPadBind and " (Improved Forever press)" or "")
        .. ";  soft targeting " .. tostring(GetCVar(SOFT))
        .. ";  soft target " .. tostring(ok and soft or "?")
        .. ";  line out " .. tostring(UnitChannelInfo and UnitChannelInfo("player") ~= nil)
end

local function KeyNames()
    local names = {}
    for _, key in ipairs(keys) do names[#names + 1] = GetBindingText and GetBindingText(key) or key end
    return table.concat(names, " or ")
end

local function Bind()
    Resolve()
    if InCombatLockdown() or #keys == 0 or not Enabled() then return end
    if viaPadBind then
        ns.SetPadReel(true)
    else
        for _, key in ipairs(keys) do
            SetOverrideBinding(owner, true, key, INTERACT)
        end
    end
    bound = true
    local soft = GetCVar(SOFT)
    if soft and soft ~= SOFT_BOTH then
        ns.DB().softWas = ns.DB().softWas or soft
        SetCVar(SOFT, SOFT_BOTH)
    end
    if not told then
        told = true
        ns.Toast("While your line is out, " .. KeyNames() .. " reels it in.")
    end
end

-- The key back to its action, soft targeting back as it was. Out of combat.
local function Unbind()
    if InCombatLockdown() then return end
    if bound then
        ClearOverrideBindings(owner)
        if ns.SetPadReel then ns.SetPadReel(false) end
        bound = false
    end
    local was = ns.DB().softWas
    if was then
        SetCVar(SOFT, was)
        ns.DB().softWas = nil
    end
end

-- (the macro's first line clicks this, its key still down)
local press = _G.QuietFishingPress
if press then
    press:HookScript("OnClick", Capture)
end

-- What /qfish says of it: the key seen at the last cast
function ns.CatchStatus()
    if not Enabled() then return "off (/qfish catch on)" end
    if capturedAt == 0 then return "press the macro to see which button reels in" end
    if #keys == 0 then return "no key or button was seen pressed at your last press (a mouse click can't reel in)" end
    return KeyNames() .. (bound and " reels in now" or " reels in while the line is out")
end

-- On or off (the settings panels, /qfish catch)
function ns.SetCatch(on)
    ns.DB().catch = (not on) and false or nil
    if not on then Unbind() end
end

function ns.CatchOn()
    return Enabled()
end

function ns.CatchCommand(arg)
    if arg == "on" or arg == "off" then
        ns.SetCatch(arg == "on")
    elseif arg ~= "" then
        ns.Print("/qfish catch on or off.")
        return
    end
    ns.Print("the key you fish with " .. (Enabled() and "also reels the line in." or "only casts (catch off)."))
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "LOOT_CLOSED" }) do
    events:RegisterEvent(event)
end
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterEvent("UPDATE_BINDINGS")
events:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" then
        candidates = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- (the cast of the press just made: its line is out)
        if GetTime() - capturedAt < 3 then Bind() end
    else
        Unbind()
    end
end)
