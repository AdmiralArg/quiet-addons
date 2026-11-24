local _, ns = ...

-- Optional integration with Improved Forever (skipped when it isn't loaded): a controller press for the fishing macro
-- on its Bindings tab. (The settings on its panel, /if, are QuietKit's Quiet tab: options.lua.)
local IF = _G.ImprovedForever
if not IF then
    return
end

local ICON = "Interface\\Icons\\Trade_Fishing"

---------------------------------------------------------------------------
-- A controller press on Improved Forever's Bindings tab: an override binding on the pad's key, running our macro
-- as a press of it on a bar would.
---------------------------------------------------------------------------
local B = IF.Binds
if not (B and B.Add and B.KeyOf and B.Overridable and B.One) then
    return
end

local bindOwner = CreateFrame("Frame")
local bindsPending = false
local reeling = false -- the line is out: the press reels in (catch.lua)

local function GetPadBind()
    return QuietFishingDB and QuietFishingDB.padBind
end

local function ApplyPadBind()
    if InCombatLockdown() then
        bindsPending = true
        return
    end
    bindsPending = false
    ClearOverrideBindings(bindOwner)
    local spec = GetPadBind()
    local key = spec and B.KeyOf(spec)
    if key then
        -- (the press runs our macro: setting it was asking for the macro, so it's made if it isn't there)
        if GetMacroIndexByName(ns.MACRO) == 0 then
            local ok, why = ns.MakeMacro()
            if not ok then ns.Toast("Your Fish press needs a macro, and " .. why) end
        end
        -- (with priority, as Improved Forever's own presses: the game's gamepad bindings would win otherwise)
        if reeling then
            SetOverrideBinding(bindOwner, true, key, "INTERACTTARGET")
        else
            SetOverrideBindingMacro(bindOwner, true, key, ns.MACRO)
        end
    end
end

-- The press's key (catch.lua: it reels in while the line is out), and that switch
function ns.PadBindKey()
    local spec = GetPadBind()
    return spec and B.KeyOf(spec)
end

function ns.SetPadReel(on)
    reeling = on and true or false
    ApplyPadBind()
end

local function SetPadBind(spec)
    QuietFishingDB = QuietFishingDB or {}
    QuietFishingDB.padBind = spec
    ApplyPadBind()
end

bindOwner:RegisterEvent("PLAYER_LOGIN")
bindOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
bindOwner:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or bindsPending then
        ApplyPadBind()
    end
end)

B.Add({
    id = "quietfishing_fish", label = "Fish", group = "Quiet Fishing",
    icon = ICON, context = "world", order = 62,
    desc = "Takes out your fishing pole, then casts",
    tip = "The first press takes out your fishing pole, the next ones cast Fishing. Leave it a few seconds "
        .. "and what it replaced (your weapon, shield or off-hand) goes back on (/qfish delay). With Improved "
        .. "Forever's Fishing module, leave R2 to its fishing mode.",
    accepts = B.Overridable,
    specs = function() return B.One(GetPadBind()) end,
    set = function(spec) SetPadBind(spec) end,
    reset = function() SetPadBind(nil) end,
})
ns.HasPadPress = true

-- (Improved Forever's own Fishing module, ImprovedForever_Fishing, has a fishing mode of its own: a pole in hand, R2
-- twice starts it, R2 casts, catches are looted at once. The two work side by side: a catch looted twice is
-- harmless, and the sound and soft targeting go back only while they're still ours. Our press set on R2 would take
-- R2 from its mode (override bindings with priority), so the tip above says to leave R2 to it.)
