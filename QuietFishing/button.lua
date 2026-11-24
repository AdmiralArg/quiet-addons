local _, ns = ...

-- The fishing button on screen, for the mouse: a click is a press of the "Quiet Fishing" macro (it runs the macro
-- itself, so the macro stays the one place that says what a press does). By default it shows only while you fish
-- (the pole in hand) and no gamepad is connected (not the input used last: a nudge of the mouse would bring it up);
-- the macro on your bar starts it. /qfish button on | off | auto.
-- Faint until the mouse is over it. Shift-drag moves it. It's a secure button: shown, hidden and moved out of combat.
local NAME = "QuietFishingMouseButton"
local SIZE = 40
local IDLE_ALPHA, HOVER_ALPHA = 0.35, 1

local button = CreateFrame("Button", NAME, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
button:SetSize(SIZE, SIZE)
button:SetFrameStrata("MEDIUM")
button:SetClampedToScreen(true)
button:SetMovable(true)
button:SetAlpha(IDLE_ALPHA)
button:Hide()
button:SetAttribute("type", "macro")
button:SetAttribute("macro", ns.MACRO)
-- (both edges arrive from the mouse; it acts on the one the game's action buttons do, ActionButtonUseKeyDown.
-- With Shift held it's being moved, not pressed.)
button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
SecureHandlerWrapScript(button, "OnClick", button, [[
    if IsShiftKeyDown() then return false end
    if not down ~= not self:GetAttribute("qf-keydown") then return false end
]])

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", 2, -2)
icon:SetPoint("BOTTOMRIGHT", -2, 2)
icon:SetTexture("Interface\\Icons\\Trade_Fishing")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local border = button:CreateTexture(nil, "BACKGROUND")
border:SetAllPoints()
border:SetColorTexture(0, 0, 0, 0.7)

local hover = button:CreateTexture(nil, "HIGHLIGHT")
hover:SetPoint("TOPLEFT", 2, -2)
hover:SetPoint("BOTTOMRIGHT", -2, 2)
hover:SetColorTexture(1, 1, 1, 0.15)

button:SetScript("OnEnter", function(self) self:SetAlpha(HOVER_ALPHA) end)
button:SetScript("OnLeave", function(self) self:SetAlpha(IDLE_ALPHA) end)

-- No macro, nothing to run: say how to get it back
button:HookScript("OnClick", function(_, _, down)
    if IsShiftKeyDown() or not down ~= not button:GetAttribute("qf-keydown") then return end
    if GetMacroIndexByName(ns.MACRO) == 0 then
        ns.Toast('This button runs the macro "' .. ns.MACRO .. '", and it isn\'t there: /qfish macro makes it.')
    end
end)

-- ---------- moving ----------
local function Place()
    local pos = ns.DB().buttonPos
    button:ClearAllPoints()
    if pos then
        button:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else
        button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end
end

button:RegisterForDrag("LeftButton")
button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if InCombatLockdown() then return end
    local point, _, _, x, y = self:GetPoint()
    ns.DB().buttonPos = { point, x, y }
    Place()
end)

-- ---------- shown or not ----------
local pending = false

-- A gamepad plugged in (can't tell: taken as one, so the button stays away)
local function PadConnected()
    if not (C_GamePad and C_GamePad.GetAllDeviceIDs) then return true end
    local ok, ids = pcall(C_GamePad.GetAllDeviceIDs)
    if not ok or type(ids) ~= "table" then return true end
    return #ids > 0
end
ns.PadConnected = PadConnected

local function Mode()
    return ns.DB().button or "auto"
end

local function KeyDown()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return not get or get("ActionButtonUseKeyDown") ~= "0"
end

local function Update()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    button:SetAttribute("qf-keydown", KeyDown())
    button:SetAttribute("useOnKeyDown", KeyDown())
    local mode = Mode()
    button:SetShown(mode == "on" or (mode == "auto" and ns.PoleOut() and not PadConnected()))
end

-- Shown when it may be (auto, or always) or never (the settings panels' tick)
function ns.ButtonOn()
    return Mode() ~= "off"
end

function ns.SetButton(on)
    ns.DB().button = (not on) and "off" or nil
    Update()
end

function ns.ButtonCommand(arg)
    if arg == "auto" or arg == "on" or arg == "off" then
        ns.DB().button = arg ~= "auto" and arg or nil
    elseif arg ~= "" then
        ns.Print("/qfish button auto, on or off.")
        return
    end
    Update()
    local mode = Mode()
    ns.Print("the fishing button is " .. (mode == "auto" and "shown while you fish with no gamepad connected" or mode)
        .. (InCombatLockdown() and " (after the fight)" or "") .. ".")
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE", "GAME_PAD_CONNECTED",
    "GAME_PAD_DISCONNECTED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Place()
    elseif event == "PLAYER_REGEN_ENABLED" and not pending then
        return
    end
    Update()
end)
