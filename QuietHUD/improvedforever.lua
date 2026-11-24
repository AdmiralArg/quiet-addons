local addonName, privateTable = ...

-- Optional integration with Improved Forever (/if): Quiet HUD's presses on its Bindings tab. Its settings are on
-- QuietKit's page (settings.lua), which shows on Improved Forever's Quiet tab for the controller. Skipped when
-- Improved Forever isn't loaded.
local IF = _G.ImprovedForever
if not (IF and IF.Binds) then
    return
end

---------------------------------------------------------------------------
-- Controller presses on Improved Forever's Bindings tab: hold one to see every faded frame
-- (the quest tracker and minimap only show on hover otherwise), or press one to keep them shown.
-- Each is an override binding on the pad's key, clicking a button of ours; the keyboard press
-- the tab also offers runs through run(down).
---------------------------------------------------------------------------
local B = IF.Binds
if not (B and B.Add and B.KeyOf and B.Single and B.Overridable and B.One) then
    return
end

local PEEK_ICON = "Interface\\Icons\\Spell_Magic_LesserInvisibilty"
local bindOwner = CreateFrame("Frame")
local bindsPending = false

-- Override click bindings need a named button; both edges arrive (down true, then false)
local function PressButton(name, fn)
    local button = CreateFrame("Button", name, UIParent)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetScript("OnClick", function(_, _, down) fn(down) end)
    return button
end

local function Peek(down)
    privateTable.SetPeek(down)
end

local function Toggle(down)
    if down then privateTable.ToggleHud() end
end

local PAD_BUTTONS = {
    peek = PressButton("QuietHUDPeekButton", Peek):GetName(),
    toggle = PressButton("QuietHUDToggleButton", Toggle):GetName(),
}

local function GetPadBind(id)
    local binds = QuietHUDDB and QuietHUDDB.padBinds
    return binds and binds[id]
end

local function ApplyPadBinds()
    if InCombatLockdown() then
        bindsPending = true
        return
    end
    bindsPending = false
    ClearOverrideBindings(bindOwner)
    for id, buttonName in pairs(PAD_BUTTONS) do
        local spec = GetPadBind(id)
        local key = spec and B.KeyOf(spec)
        if key then
            SetOverrideBindingClick(bindOwner, false, key, buttonName, "LeftButton")
        end
    end
end

local function SetPadBind(id, spec)
    if not QuietHUDDB then return end
    QuietHUDDB.padBinds = QuietHUDDB.padBinds or {}
    QuietHUDDB.padBinds[id] = spec
    if id == "peek" and not spec then
        privateTable.SetPeek(false) -- in case it was unbound while held
    end
    ApplyPadBinds()
end

bindOwner:RegisterEvent("PLAYER_LOGIN")
bindOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
bindOwner:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" or bindsPending then
        ApplyPadBinds()
    end
end)

B.Add({
    id = "quiethud_peek", label = "Show faded frames (hold)", group = "Quiet HUD",
    icon = PEEK_ICON, context = "world", order = 60,
    desc = "Shows the quest tracker, minimap and every faded frame while held",
    tip = "While held, every frame Quiet HUD fades shows at its Hover alpha, as if the mouse were over it. "
        .. "They fade again after the fade delay.",
    -- (a single press only: a combo's buttons may be let go in any order, and the release must arrive)
    accepts = function(spec) return B.Single(spec) and B.KeyOf(spec) ~= nil end,
    specs = function() return B.One(GetPadBind("peek")) end,
    set = function(spec) SetPadBind("peek", spec) end,
    reset = function() SetPadBind("peek", nil) end,
    run = Peek,
})

B.Add({
    id = "quiethud_toggle", label = "Show / hide faded frames", group = "Quiet HUD",
    icon = PEEK_ICON, context = "world", order = 61,
    desc = "Keeps the faded frames shown until pressed again",
    tip = "Press once to keep every frame Quiet HUD fades shown at its Hover alpha (to read the quest "
        .. "tracker, say), again to let them fade.",
    accepts = B.Overridable,
    specs = function() return B.One(GetPadBind("toggle")) end,
    set = function(spec) SetPadBind("toggle", spec) end,
    reset = function() SetPadBind("toggle", nil) end,
    run = Toggle,
})
