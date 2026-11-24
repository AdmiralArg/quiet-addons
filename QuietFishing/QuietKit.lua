-- QuietKit: the look, the settings panel, the welcome window and the small notes every Quiet addon shares.
--
-- Each Quiet addon carries this same file and registers its page with QuietKit.Register (below). The newest copy
-- loaded wins (VERSION: raise it with every change, then copy the file to every Quiet addon). Once every addon has
-- loaded (PLAYER_LOGIN) the kit makes:
--  * one page in Options > AddOns, "Quiet": a welcome page and a page for each Quiet addon that's on, down the left;
--  * one "Quiet" tab on Improved Forever's panel (/if) when that's loaded, with the same pages, for the controller;
--  * a small window, once, saying what each newly installed Quiet addon does and how to start, or what's new in
--    one you had already (not chat: it's easy to miss there, and many addons fill it);
--  * when several arrive together (the bundle), the setup window instead: a line on each and a switch beside it,
--    so a newcomer keeps the ones they want. It's on the Welcome page afterwards, as "Choose addons".
-- And for the addons themselves: QuietKit.UI (the shared look: windows, buttons, switches, text), QuietKit.Toast
-- (a small note that fades, instead of a chat line), QuietKit.Print (a chat line in the shared style, for answers
-- to a command), macros a player can drag to a bar from the settings, and QuietKit.Stock: what each of the
-- player's characters holds, counted once here for every Quiet addon (see it, near the end). And QuietKit.Realm:
-- this realm's name, for anything kept by realm (never the game's GetRealmName itself: see it, before the Stock).
--
-- page = {
--   key      "quietfishing": the addon's folder name in lower case
--   title    "Quiet Fishing"
--   icon     a texture path
--   about    a line: what it does
--   how      a line (or a function giving one, read as it's shown): how to start
--   command  "/qfish", shown beside it
--   db       a function giving the addon's own saved table (account-wide): the welcome is remembered there
--   news     { version = "0.5.0", text = "..." }: shown once to players who had an older version
--   saved    "QuietFishingDB": the addon's account-wide saved variable's name. As the addon loads, anything in it
--            means this player had the addon before (what's new, not the welcome). Without it the kit looks at db()
--            when the welcome is due, which is wrong if the addon fills its table in its first seconds.
--   had      optional, instead: a function, true if this player had the addon before
--   items    the settings, in order: { label, tip, section (a title over it and the ones after), hidden (a
--            function: true leaves it out for now) } and one of
--     a toggle   get(), set(on)
--     a slider   min, max, step, get(), set(v), format(v) -> text
--     a choice   options = { { value, name } } (or a function giving them), get(), set(value)
--     a button   run(), text (its word; the label if none), confirm (true: a second press does it)
--     a macro    macro = { name, icon, body (text, or a function giving it), account (true: an account-wide
--                macro; else this character's) }, use() (optional: a click on its icon does it now). Its icon
--                drags onto an action bar; "Put on my bar" puts it in an empty slot you can see.
-- }
-- QuietKit.Refresh(key) draws a page's values again after they changed elsewhere (a command, a key).
local VERSION = 15

local kit = _G.QuietKit
if kit and (kit.version or 0) >= VERSION then return end
kit = kit or {}
_G.QuietKit = kit
kit.version = VERSION
kit.pages = kit.pages or {}

-- The Quiet addons that are shared together, in the order a newcomer meets them (the setup window, and the welcome
-- page: the ones you don't have are listed under yours). Each: its folder, its name, one light line on what it
-- does, one on where to start it (start: the command, the key or the button for your bar, and where that is; "its
-- settings" is its page in Options, AddOns, Quiet), its command if it has one, and the group it's listed under
-- (kit.groups). (Not the small fixes to other authors' addons, Quiet Escape and Quiet Popups: they aren't shared.)
kit.groups = { "You'll notice these straight away", "There when you ask for them" }
kit.catalog = {
    { addon = "QuietHUD", title = "Quiet HUD", command = "/qhud", group = 1,
        icon = "Interface\\Icons\\Spell_Holy_Silence",
        about = "Fades the interface while you explore. A fight or a target brings it back.",
        start = "Works by itself. One switch in its settings turns it all off; a key shows everything for a moment." },
    { addon = "QuietNames", title = "Quiet Names", command = "/qnames", group = 1,
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        about = "Softer names over heads, in a font you like.",
        start = "Works by itself. The font: its settings. /dark hides every name (a key: Key Bindings, AddOns)." },
    { addon = "BattleShoutGlow", title = "Buff Glow", command = "/bsg", group = 1,
        icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
        about = "A buff you let drop pulses on its button until it's back up.",
        start = "Works by itself, on the spells on your action bars." },
    { addon = "ZoneLevels", title = "Zone Levels", group = 1,
        icon = "Interface\\Icons\\Ability_Spy",
        about = "Each zone's level range, on the world map.",
        start = "Works by itself: point at a zone on the world map." },
    { addon = "QuietBags", title = "Quiet Bags", command = "/qbags", group = 2,
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        about = "What your other characters carry: bags, bank and mail.",
        start = "/qbags, or the round button on your bags. A button for your bar: its settings." },
    { addon = "QuietFriends", title = "Quiet Friends", command = "/qfriends", group = 2,
        icon = "Interface\\Icons\\INV_Letter_15",
        about = "Your friends' full names, one click away when you write a letter.",
        start = "/qfriends to add them. At a mailbox they're beside Send Mail." },
    { addon = "QuietPins", title = "Quiet Pins", command = "/qpin", group = 2,
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        about = "Notes on the map, and /way.",
        start = "/qpin. A button for your bar: its settings." },
    { addon = "QuietFishing", title = "Quiet Fishing", command = "/qfish", group = 2,
        icon = "Interface\\Icons\\Trade_Fishing",
        about = "One button fishes: pole out, cast, reel in, weapon back.",
        start = "The fishing button for your bar: its settings, Put on my bar. Press it by water." },
    { addon = "QuietProfessions", title = "Quiet Professions", command = "/qprof", group = 2,
        icon = "Interface\\Icons\\Trade_BlackSmithing",
        about = "The cheapest way to level a crafting profession, at today's prices.",
        start = "/qprof. A button for your bar: its settings. Open your profession's window once first." },
    { addon = "QuietAuctions", title = "Quiet Auctions", command = "/qah", group = 2,
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        about = "Steady gold from the auction house, on the characters you choose.",
        start = "Choose its characters in its settings; there are its buttons for your bar too." },
}

local function Resolve(v)
    if type(v) == "function" then return v() end
    return v
end

---------------------------------------------------------------------------
-- The look: QuietKit.UI. Calm and flat: a dark glass, a hairline border, one warm accent, soft text.
---------------------------------------------------------------------------
local UI = {}
kit.UI = UI
UI.C = {
    bg = { 0.045, 0.047, 0.06, 0.94 },
    raised = { 1, 1, 1, 0.06 },
    hover = { 1, 1, 1, 0.12 },
    line = { 1, 1, 1, 0.09 },
    accent = { 0.98, 0.80, 0.42 },
    title = { 0.96, 0.93, 0.86 },
    text = { 0.86, 0.85, 0.82 },
    muted = { 0.56, 0.56, 0.58 },
    good = { 0.55, 0.85, 0.55 },
    warn = { 1, 0.48, 0.36 },
}
local C = UI.C

local ROLES = {
    title = { "GameFontNormalLarge", C.title },
    heading = { "GameFontNormal", C.accent },
    body = { "GameFontHighlight", C.text },
    small = { "GameFontHighlightSmall", C.text },
    muted = { "GameFontHighlightSmall", C.muted },
}

-- A text in one of the roles above, left-aligned and wrapping
function UI.Text(parent, role, layer)
    local r = ROLES[role] or ROLES.body
    local fs = parent:CreateFontString(nil, layer or "ARTWORK", r[1])
    fs:SetTextColor(r[2][1], r[2][2], r[2][3])
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    return fs
end

local function Fill(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- A hairline border round a frame
function UI.Border(frame, c)
    c = c or C.line
    local edges = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = frame:CreateTexture(nil, "BORDER")
        Fill(t, c)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        edges[i] = t
    end
    return edges
end

-- The dark glass behind a window or a box
function UI.Panel(frame, alpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, { C.bg[1], C.bg[2], C.bg[3], alpha or C.bg[4] })
    UI.Border(frame)
    return bg
end

-- A flat button: { SetText, SetEnabled } as any button. primary: in the accent.
function UI.Button(parent, text, onClick, width, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    Fill(b.bg, primary and { C.accent[1], C.accent[2], C.accent[3], 0.22 } or C.raised)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    Fill(hover, C.hover)
    UI.Border(b, primary and { C.accent[1], C.accent[2], C.accent[3], 0.45 } or C.line)
    local label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetTextColor(C.title[1], C.title[2], C.title[3])
    b:SetFontString(label)
    b:SetText(text or "")
    b:SetWidth(width or math.max(96, math.ceil(label:GetStringWidth()) + 28))
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    b:SetScript("OnEnable", function() label:SetAlpha(1) end)
    b:SetScript("OnDisable", function() label:SetAlpha(0.4) end)
    return b
end

-- A circle cut out of a plain texture (a square, where the game has no masks)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function Round(parent, layer, size)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetSize(size, size)
    if parent.CreateMaskTexture then
        pcall(function()
            local mask = parent:CreateMaskTexture()
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(tex)
            tex:AddMaskTexture(mask)
        end)
    end
    return tex
end

-- A switch, the kind every phone has: a rounded track and a round knob, at the left and grey when off, at the
-- right on the accent when on; it slides across when clicked. Refresh() shows get(); a click sets the other.
function UI.Toggle(parent, get, set)
    local W, H, K = 34, 18, 14
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(W, H)
    -- (the track: two round ends and the middle between them)
    local track = { Round(t, "BACKGROUND", H), Round(t, "BACKGROUND", H), t:CreateTexture(nil, "BACKGROUND") }
    track[1]:SetPoint("LEFT")
    track[2]:SetPoint("RIGHT")
    track[3]:SetPoint("TOPLEFT", H / 2, 0)
    track[3]:SetPoint("BOTTOMRIGHT", -H / 2, 0)
    local shadow = Round(t, "BORDER", K + 2)
    local knob = Round(t, "ARTWORK", K)
    shadow:SetPoint("CENTER", knob, "CENTER", 0, -1)
    Fill(shadow, { 0, 0, 0, 0.45 })
    local travel = W - H
    local at, goal, hovered = nil, 0, false
    local function Place()
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", t, "LEFT", H / 2 + at * travel, 0)
    end
    local function Paint()
        local on = goal == 1
        local c = on and { C.accent[1], C.accent[2], C.accent[3], hovered and 1 or 0.9 }
            or { 1, 1, 1, hovered and 0.28 or 0.18 }
        for _, part in ipairs(track) do Fill(part, c) end
        Fill(knob, on and { 1, 1, 1, 1 } or { 0.74, 0.74, 0.77, 1 })
    end
    -- (the knob's slide: OnUpdate only while it moves)
    local function Slide(_, elapsed)
        local step = elapsed / 0.12
        at = at < goal and math.min(goal, at + step) or math.max(goal, at - step)
        Place()
        if at == goal then t:SetScript("OnUpdate", nil) end
    end
    function t.Refresh()
        goal = get() and 1 or 0
        Paint()
        if at == nil or not t:IsVisible() then
            at = goal
            Place()
        elseif at ~= goal then
            t:SetScript("OnUpdate", Slide)
        end
    end
    t:SetScript("OnClick", function()
        set(not get())
        t.Refresh()
    end)
    t:SetScript("OnEnter", function() hovered = true; Paint() end)
    t:SetScript("OnLeave", function() hovered = false; Paint() end)
    return t
end

-- A slider of our own (the client's slider templates differ between versions)
function UI.Slider(parent, min, max, step, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step or 1)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    Fill(track, { 1, 1, 1, 0.16 })
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    Fill(thumb, { C.accent[1], C.accent[2], C.accent[3], 0.95 })
    s:SetThumbTexture(thumb)
    s:SetScript("OnValueChanged", function(self, value)
        if self.filling then return end
        value = math.floor(value / (step or 1) + 0.5) * (step or 1)
        onChange(value)
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * (step or 1))
    end)
    function s.Fill(value)
        s.filling = true
        s:SetValue(value)
        s.filling = false
    end
    return s
end

-- A window: the glass, a title, a close button; moved by dragging it, closed with Escape. name: its global name.
-- store (optional): a function giving a saved table; where it's dragged to is kept in its .pos and used again.
-- Put things under w.body (below the title).
function UI.Window(name, title, width, height, store)
    local w = CreateFrame("Frame", name, UIParent)
    w:SetSize(width, height)
    local pos = store and store() and store().pos
    if pos then
        w:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else
        w:SetPoint("CENTER")
    end
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- (the place is the addon's to keep, in its saved table, not the game's layout cache)
        self:SetUserPlaced(false)
        local saved = store and store()
        if saved then
            local point, _, _, x, y = self:GetPoint()
            saved.pos = { point, x, y }
        end
    end)
    w:Hide()
    if name then tinsert(UISpecialFrames, name) end
    UI.Panel(w)
    local accent = w:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    Fill(accent, { C.accent[1], C.accent[2], C.accent[3], 0.7 })
    w.title = UI.Text(w, "title")
    w.title:SetPoint("TOPLEFT", 16, -14)
    w.title:SetPoint("RIGHT", -40, 0)
    w.title:SetText(title or "")
    w.close = CreateFrame("Button", nil, w)
    w.close:SetSize(24, 24)
    w.close:SetPoint("TOPRIGHT", -8, -8)
    local x = w.close:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    x:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    local hover = w.close:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    Fill(hover, C.hover)
    w.close:SetScript("OnClick", function() w:Hide() end)
    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT", 16, -44)
    w.body:SetPoint("BOTTOMRIGHT", -16, 14)
    return w
end

-- A flat text box. onEnter(text) on Enter; Escape lets go of it.
function UI.Box(parent, width, onEnter)
    local b = CreateFrame("EditBox", nil, parent)
    b:SetSize(width or 200, 24)
    b:SetAutoFocus(false)
    b:SetFontObject(GameFontHighlightSmall)
    b:SetTextInsets(8, 8, 0, 0)
    b:SetTextColor(C.title[1], C.title[2], C.title[3])
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, { 0, 0, 0, 0.35 })
    UI.Border(b)
    b:SetScript("OnEscapePressed", b.ClearFocus)
    b:SetScript("OnEnterPressed", function(self)
        if onEnter then onEnter(self:GetText()) end
        self:ClearFocus()
    end)
    return b
end

-- Places a wrapped text at (x, y) in a width; returns its height
local function Put(fs, parent, x, y, width, text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    fs:SetWidth(width)
    fs:SetText(text or "")
    fs:SetShown((text or "") ~= "")
    if (text or "") == "" then return 0 end
    return math.ceil(fs:GetStringHeight())
end
UI.Put = Put

---------------------------------------------------------------------------
-- The controller. Gamepad mode on: the game's options can't be opened from addon code, so the settings go to
-- Improved Forever's panel. The pad in hand: the input used last (Improved Forever knows; else gamepad mode).
---------------------------------------------------------------------------
local function PadMode()
    if C_GamePad and C_GamePad.IsEnabled then
        local ok, on = pcall(C_GamePad.IsEnabled)
        if ok then return on and true or false end
    end
    local get = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
    local ok, on = pcall(get, "GamePadEnable")
    return ok and on and true or false
end
kit.PadMode = PadMode

function kit.PadInHand()
    local IF = _G.ImprovedForever
    if IF and IF.Input and IF.Input.Pad then
        local ok, pad = pcall(IF.Input.Pad)
        if ok then return pad and true or false end
    end
    return PadMode()
end

---------------------------------------------------------------------------
-- Messages: a chat line in the shared style (for answers to a command), and a small note that fades (for
-- everything the player didn't ask for: chat is easy to miss)
---------------------------------------------------------------------------
function kit.Print(title, msg)
    print("|cff66ccff" .. title .. ":|r " .. msg)
end

-- Notes wait their turn (and while the welcome window, at the same place, is up); the same note twice is one
kit.toastQueue = kit.toastQueue or {}

function kit.Toast(text, icon)
    for _, q in ipairs(kit.toastQueue) do
        if q.text == text then return end
    end
    if kit.toast and kit.toast:IsShown() and kit.toast.text:GetText() == text then return end
    if #kit.toastQueue < 6 then kit.toastQueue[#kit.toastQueue + 1] = { text = text, icon = icon } end
    kit.NextToast()
end

function kit.NextToast()
    if (kit.toast and kit.toast:IsShown()) or (kit.welcome and kit.welcome:IsShown()) then return end
    local q = table.remove(kit.toastQueue, 1)
    if not q then return end
    local text, icon = q.text, q.icon
    local t = kit.toast
    if not t then
        t = CreateFrame("Frame", nil, UIParent)
        t:SetSize(320, 44)
        t:SetPoint("TOP", UIParent, "TOP", 0, -150)
        t:SetFrameStrata("DIALOG")
        UI.Panel(t, 0.88)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(28, 28)
        t.icon:SetPoint("LEFT", 9, 0)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.text = UI.Text(t, "body")
        t.text:SetPoint("LEFT", t.icon, "RIGHT", 10, 0)
        t.text:SetPoint("RIGHT", -12, 0)
        t.text:SetJustifyV("MIDDLE")
        t:Hide()
        t:SetScript("OnUpdate", function(self)
            local age = GetTime() - self.since
            if age < 0.2 then
                self:SetAlpha(age / 0.2)
            elseif age < 3.2 then
                self:SetAlpha(1)
            elseif age < 4 then
                self:SetAlpha(1 - (age - 3.2) / 0.8)
            else
                self:Hide()
                kit.NextToast()
            end
        end)
        kit.toast = t
    end
    t.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Note_01")
    t.text:SetText(text)
    t:SetHeight(math.max(44, math.ceil(t.text:GetStringHeight()) + 20))
    t.since = GetTime()
    t:SetAlpha(0)
    t:Show()
end

---------------------------------------------------------------------------
-- Macros a player can put on a bar: made (or brought up to date) out of combat, on demand only. spec.icon is the
-- icon's name, as macros take it ("Trade_Fishing").
---------------------------------------------------------------------------
local function IconPath(icon)
    if not icon then return nil end
    if icon:find("\\") then return icon end
    return "Interface\\Icons\\" .. icon
end
-- The macro there and up to date: true, or false and why
function kit.MacroReady(spec)
    if InCombatLockdown() then return false, "after the fight, please." end
    local body = Resolve(spec.body)
    if GetMacroIndexByName(spec.name) > 0 then
        local _, icon, old = GetMacroInfo(spec.name)
        if old ~= body then EditMacro(spec.name, spec.name, icon or spec.icon, body) end
        return true
    end
    local general, perChar = GetNumMacros()
    if spec.account then
        if general >= (MAX_ACCOUNT_MACROS or 120) then return false, "no room for another macro (/macro)." end
    elseif perChar >= (MAX_CHARACTER_MACROS or 18) then
        return false, "no room for another character macro (/macro to delete one)."
    end
    CreateMacro(spec.name, spec.icon or "INV_Misc_QuestionMark", body, not spec.account)
    return GetMacroIndexByName(spec.name) > 0, "the game wouldn't make the macro."
end

-- The action slot holding a macro, if any (every slot, the crossbar's too)
function kit.MacroSlot(name)
    local index = GetMacroIndexByName(name)
    if index == 0 then return nil end
    for slot = 1, 216 do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and (id == index or GetActionText(slot) == name) then return slot end
    end
end

-- The extra bars shown, then the main bar's page (a stance's own while in one)
local BARS = {
    { first = 61, command = "MULTIACTIONBAR1BUTTON" }, -- bottom left
    { first = 49, command = "MULTIACTIONBAR2BUTTON" }, -- bottom right
    { first = 25, command = "MULTIACTIONBAR3BUTTON" }, -- right
    { first = 37, command = "MULTIACTIONBAR4BUTTON" }, -- right 2
}

local function EmptySlot()
    local list = {}
    local ok, bottomLeft, bottomRight, right, right2 = pcall(GetActionBarToggles)
    if ok then
        local shown = { bottomLeft, bottomRight, right, right2 }
        for i, bar in ipairs(BARS) do
            if shown[i] then list[#list + 1] = bar end
        end
    end
    local page = (GetActionBarPage and GetActionBarPage()) or 1
    local offset = (GetBonusBarOffset and GetBonusBarOffset()) or 0
    local first = (offset > 0 and page == 1) and ((NUM_ACTIONBAR_PAGES or 6) + offset - 1) * 12 + 1
        or (page - 1) * 12 + 1
    list[#list + 1] = { first = first, command = "ACTIONBUTTON" }
    for _, bar in ipairs(list) do
        for n = 1, 12 do
            local slot = bar.first + n - 1
            if not HasAction(slot) then
                local key = GetBindingKey(bar.command .. n)
                return slot, key and (GetBindingText and GetBindingText(key) or key)
            end
        end
    end
end

-- Puts a macro in an empty slot you can see. Says how it went in a note; true if it's on a bar now.
function kit.PlaceMacro(spec)
    local ok, why = kit.MacroReady(spec)
    if not ok then
        kit.Toast(why, IconPath(spec.icon))
        return false
    end
    if kit.MacroSlot(spec.name) then
        kit.Toast('"' .. spec.name .. '" is on your bar already.', IconPath(spec.icon))
        return true
    end
    if PadMode() then
        kit.Toast('"' .. spec.name .. '" is ready: put it on your crossbar from /macro.', IconPath(spec.icon))
        return false
    end
    local slot, key = EmptySlot()
    if slot and not GetCursorInfo() then
        PickupMacro(spec.name)
        PlaceAction(slot)
        ClearCursor()
    end
    if kit.MacroSlot(spec.name) then
        kit.Toast('"' .. spec.name .. '" is on your bar' .. (key and (", key " .. key) or "") .. ".", IconPath(spec.icon))
        return true
    end
    kit.Toast('No empty slot on your bars: drag "' .. spec.name .. '" from /macro.', IconPath(spec.icon))
    return false
end

-- The macro on the cursor, to drop on a bar
function kit.PickupMacro(spec)
    local ok, why = kit.MacroReady(spec)
    if not ok then
        kit.Toast(why, IconPath(spec.icon))
        return
    end
    PickupMacro(spec.name)
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function Kind(item)
    if item.macro then return "macro" end
    if item.run then return "button" end
    if item.options then return "choice" end
    if item.min then return "slider" end
    return "toggle"
end

-- "on", "off" (installed, not on for this character) or "missing"
local function AddOnState(name)
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded then
        local ok, yes = pcall(loaded, name)
        if ok and yes then return "on" end
    end
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not info then return "missing" end
    local ok, _, _, _, _, reason = pcall(info, name)
    if not ok or reason == "MISSING" then return "missing" end
    return "off"
end

local function Pages()
    local list = {}
    for _, page in pairs(kit.pages) do list[#list + 1] = page end
    table.sort(list, function(a, b) return a.title < b.title end)
    return list
end

local function Options(item)
    return Resolve(item.options) or {}
end

local function ChoiceName(item)
    local value = item.get()
    for _, o in ipairs(Options(item)) do
        if o.value == value then return o.name end
    end
    return tostring(value)
end

-- Steps a choice to the next (dir 1) or the one before (-1)
local function StepChoice(item, dir)
    local list = Options(item)
    if #list == 0 then return end
    local at = 1
    for i, o in ipairs(list) do
        if o.value == item.get() then at = i end
    end
    item.set(list[(at - 1 + dir) % #list + 1].value)
end

local function HowLine(page)
    local how = Resolve(page.how)
    local command = page.command and ("Every command: " .. page.command .. " help") or nil
    if how and command then return how .. "  " .. command end
    return how or command
end

function kit.Register(page)
    assert(page and page.key and page.title, "QuietKit.Register: a page needs a key and a title")
    page.items = page.items or {}
    kit.pages[page.key] = page
    if kit.built then pcall(kit.AddToImprovedForever, page) end
end

-- A player who had this addon before the welcome existed: its saved table has more than the kit's own marks
local function HadBefore(db)
    for k in pairs(db) do
        if k ~= "quietWelcomed" and k ~= "quietNews" and k ~= "quietStock" then return true end
    end
    return false
end

-- As an addon's saved variables arrive (ADDON_LOADED, before the addon fills its table in its first seconds):
-- whether this player had it before, read from page.saved without making or touching anything
function kit.NoteLoaded(addon)
    local page = kit.pages[addon:lower()]
    if not page or not page.saved or page.hadBefore ~= nil then return end
    local saved = _G[page.saved]
    page.hadBefore = type(saved) == "table" and HadBefore(saved) or false
end

-- What the welcome window has to say for a page: "new", "news" or nil
local function WelcomeFor(page)
    local db = page.db and page.db()
    if not db then return nil end
    if not db.quietWelcomed then
        local had = page.hadBefore
        if page.had then had = page.had() end
        if had == nil then had = HadBefore(db) end
        if not had then return "new" end
        db.quietWelcomed = true
    end
    if page.news and db.quietNews ~= page.news.version then return "news" end
    return nil
end

-- This addon's welcome is still to come (its first session): the addon can leave its own first-time notes out
function kit.Welcoming(key)
    local page = kit.pages[key]
    return page ~= nil and WelcomeFor(page) == "new"
end

---------------------------------------------------------------------------
-- Options > AddOns > Quiet: the pages down the left, the chosen one on the right (a scrollbar when it's long)
---------------------------------------------------------------------------
local SIDE_W, GAP = 168, 16

-- One item's controls on a page's canvas: { Fill(), Layout(x, y, width) -> height }
local function Field(canvas, item)
    local kind = Kind(item)
    local f = { kind = kind }
    f.name = UI.Text(canvas, "body")
    f.tip = UI.Text(canvas, "muted")
    if item.section then f.head = UI.Text(canvas, "heading") end

    if kind == "toggle" then
        f.control = UI.Toggle(canvas, item.get, item.set)
    elseif kind == "slider" then
        function f.SliderLabel()
            local v = item.get()
            return item.label .. ":  |cffffffff" .. (item.format and item.format(v) or tostring(v)) .. "|r"
        end
        f.control = UI.Slider(canvas, item.min, item.max, item.step, function(value)
            if value ~= item.get() then item.set(value) end
            f.name:SetText(f.SliderLabel())
        end)
    elseif kind == "choice" then
        f.control = CreateFrame("Frame", nil, canvas)
        f.control:SetSize(220, 24)
        f.value = UI.Button(f.control, "", function(_, button) StepChoice(item, button == "RightButton" and -1 or 1); f.Fill() end, 156)
        f.value:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        f.prev = UI.Button(f.control, "<", function() StepChoice(item, -1); f.Fill() end, 28)
        f.next = UI.Button(f.control, ">", function() StepChoice(item, 1); f.Fill() end, 28)
        f.prev:SetPoint("LEFT")
        f.value:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
        f.next:SetPoint("LEFT", f.value, "RIGHT", 4, 0)
    elseif kind == "macro" then
        local spec = item.macro
        f.control = CreateFrame("Frame", nil, canvas)
        f.control:SetSize(260, 36)
        local icon = CreateFrame("Button", nil, f.control)
        icon:SetSize(36, 36)
        icon:SetPoint("LEFT")
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.tex:SetTexture(IconPath(spec.icon))
        UI.Border(icon, { C.accent[1], C.accent[2], C.accent[3], 0.5 })
        local hover = icon:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        Fill(hover, C.hover)
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnDragStart", function() kit.PickupMacro(spec) end)
        icon:SetScript("OnClick", function()
            if item.use then item.use() else kit.PickupMacro(spec) end
        end)
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(spec.name)
            GameTooltip:AddLine(item.use and "Click: do it now.  Drag: onto an action bar." or "Drag it onto an action bar.",
                1, 1, 1, true)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.put = UI.Button(f.control, "Put on my bar", function()
            kit.PlaceMacro(spec)
            f.Fill()
        end)
        f.put:SetPoint("LEFT", icon, "RIGHT", 12, 0)
        -- (where it stands: not made yet, made, on a bar)
        f.state = UI.Text(f.control, "muted")
        f.state:SetPoint("LEFT", f.put, "RIGHT", 12, 0)
        f.state:SetWordWrap(false)
        icon:SetScript("OnDragStop", function() C_Timer.After(0.2, f.Fill) end)
    elseif kind == "button" then
        local word = item.text or item.label
        f.control = UI.Button(canvas, word, function(self)
            -- (confirm: the first press asks, a second within 4 s does it)
            if item.confirm and not self.armed then
                self.armed = true
                self:SetText("Sure? Press again")
                C_Timer.After(4, function()
                    self.armed = nil
                    self:SetText(word)
                end)
                return
            end
            self.armed = nil
            self:SetText(word)
            item.run()
        end)
        if item.confirm then f.control:SetWidth(math.max(f.control:GetWidth(), 140)) end
    end

    function f.Fill()
        if kind == "toggle" then
            f.control.Refresh()
        elseif kind == "slider" then
            f.control.Fill(item.get())
            f.name:SetText(f.SliderLabel())
        elseif kind == "choice" then
            f.value:SetText(ChoiceName(item))
        elseif kind == "macro" then
            local name = item.macro.name
            f.state:SetText(kit.MacroSlot(name) and "On your bar" or GetMacroIndexByName(name) > 0 and "Made, not on a bar"
                or "Not made yet")
        end
    end

    function f.Hide()
        f.name:Hide()
        f.tip:Hide()
        f.control:Hide()
        if f.head then f.head:Hide() end
    end

    function f.Layout(x, y, width)
        local top = y
        f.control:Show()
        if f.head then
            y = y + 12 + Put(f.head, canvas, x, y + 12, width, item.section) + 10
        end
        f.control:ClearAllPoints()
        if kind == "toggle" then
            f.control:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -(y + 1))
            y = y + Put(f.name, canvas, x + 46, y + 2, width - 46, item.label)
            y = y + 4 + Put(f.tip, canvas, x + 46, y + 4, width - 46, item.tip)
            y = math.max(y, top + 20)
        else
            local label = kind == "slider" and f.SliderLabel() or item.label
            y = y + Put(f.name, canvas, x, y, width, label)
            f.control:SetPoint("TOPLEFT", canvas, "TOPLEFT", x + (kind == "slider" and 4 or 0), -(y + 8))
            if kind == "slider" then f.control:SetWidth(math.min(300, width - 8)) end
            y = y + 8 + f.control:GetHeight()
            y = y + 6 + Put(f.tip, canvas, x, y + 6, width, item.tip)
        end
        return y - top
    end

    return f
end

-- An addon's line on the welcome page and in the welcome window: its icon, name, what it does, how to start
local function Entry(canvas, iconSize)
    local e = {}
    e.icon = canvas:CreateTexture(nil, "ARTWORK")
    e.icon:SetSize(iconSize, iconSize)
    e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    e.title = UI.Text(canvas, "heading")
    e.about = UI.Text(canvas, "small")
    e.how = UI.Text(canvas, "muted")

    -- lines = { icon, title, about, how }; returns its height
    function e.Layout(x, y, width, lines)
        local indent = iconSize + 12
        e.icon:ClearAllPoints()
        e.icon:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
        e.icon:SetTexture(lines.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        e.icon:Show()
        local h = Put(e.title, canvas, x + indent, y + 1, width - indent, lines.title)
        h = h + 4 + Put(e.about, canvas, x + indent, y + h + 5, width - indent, lines.about)
        if lines.how and lines.how ~= "" then
            h = h + 4 + Put(e.how, canvas, x + indent, y + h + 5, width - indent, lines.how)
        else
            e.how:Hide()
        end
        return math.max(h + 2, iconSize)
    end

    function e.Hide()
        e.icon:Hide()
        e.title:Hide()
        e.about:Hide()
        e.how:Hide()
    end

    return e
end

function kit.BuildPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Quiet"
    panel:Hide()
    kit.panel = panel

    -- Left: the pages
    local side = CreateFrame("Frame", nil, panel)
    side:SetPoint("TOPLEFT", 10, -10)
    side:SetPoint("BOTTOMLEFT", 10, 10)
    side:SetWidth(SIDE_W)
    UI.Panel(side, 0.55)
    side.buttons = {}

    -- Right: the chosen page, scrolled, with a thin scrollbar when it's longer than the room
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", side, "TOPRIGHT", GAP, -6)
    scroll:SetPoint("BOTTOMRIGHT", -22, 10)
    local bar = CreateFrame("Slider", nil, panel)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
    local barTrack = bar:CreateTexture(nil, "BACKGROUND")
    barTrack:SetAllPoints()
    Fill(barTrack, { 1, 1, 1, 0.06 })
    local barThumb = bar:CreateTexture(nil, "OVERLAY")
    barThumb:SetSize(6, 40)
    Fill(barThumb, { C.accent[1], C.accent[2], C.accent[3], 0.6 })
    bar:SetThumbTexture(barThumb)
    bar:SetValueStep(1)
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    local function Most() return math.max(0, (scroll.height or 0) - scroll:GetHeight()) end
    local function ScrollTo(value)
        value = math.max(0, math.min(Most(), value))
        scroll:SetVerticalScroll(value)
        bar:SetValue(value)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta) ScrollTo(self:GetVerticalScroll() - delta * 40) end)
    local canvases = {}

    local function SideButton(i)
        local b = side.buttons[i]
        if b then return b end
        b = CreateFrame("Button", nil, side)
        b:SetHeight(26)
        b:SetPoint("TOPLEFT", 1, -(i - 1) * 26 - 6)
        b:SetPoint("RIGHT", -1, 0)
        b.lit = b:CreateTexture(nil, "BACKGROUND")
        b.lit:SetAllPoints()
        Fill(b.lit, { C.accent[1], C.accent[2], C.accent[3], 0.16 })
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetPoint("TOPLEFT")
        b.mark:SetPoint("BOTTOMLEFT")
        b.mark:SetWidth(2)
        Fill(b.mark, C.accent)
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        Fill(hover, { 1, 1, 1, 0.06 })
        b.label = UI.Text(b, "body")
        b.label:SetPoint("LEFT", 12, 0)
        b.label:SetPoint("RIGHT", -6, 0)
        b.label:SetJustifyV("MIDDLE")
        b.label:SetWordWrap(false)
        b:SetScript("OnClick", function(self) kit.Select(self.key) end)
        side.buttons[i] = b
        return b
    end

    -- A page's canvas, made the first time it's shown
    local function Canvas(key)
        if canvases[key] then return canvases[key] end
        local canvas = CreateFrame("Frame", nil, scroll)
        canvas:SetSize(1, 1)
        canvas:Hide()
        canvas.heading = UI.Text(canvas, "title")
        canvas.intro = UI.Text(canvas, "body")
        canvas.how = UI.Text(canvas, "muted")
        canvases[key] = canvas
        local page = kit.pages[key]

        if page then
            canvas.fields = {}
            for _, item in ipairs(page.items) do canvas.fields[#canvas.fields + 1] = Field(canvas, item) end
            function canvas.Layout(width)
                for _, f in ipairs(canvas.fields) do f.Fill() end
                local y = Put(canvas.heading, canvas, 0, 0, width, page.title)
                y = y + 8 + Put(canvas.intro, canvas, 0, y + 8, width, page.about)
                y = y + 6 + Put(canvas.how, canvas, 0, y + 6, width, HowLine(page))
                for i, f in ipairs(canvas.fields) do
                    if Resolve(page.items[i].hidden) then
                        f.Hide()
                    else
                        y = y + 20 + f.Layout(0, y + 20, width)
                    end
                end
                return y + 16
            end
        else
            -- The welcome page: your Quiet addons, then the others
            canvas.entries = {}
            canvas.headMine = UI.Text(canvas, "heading")
            canvas.headOther = UI.Text(canvas, "heading")
            -- (which of them you want on: the setup window, any time)
            canvas.choose = UI.Button(canvas, "Choose addons", function()
                kit.ClosePanel()
                kit.ShowSetup(false)
            end, 130)
            function canvas.Layout(width)
                local y = Put(canvas.heading, canvas, 0, 0, width, "Quiet")
                y = y + 8 + Put(canvas.intro, canvas, 0, y + 8, width,
                    "Calm little addons for WoW Forever. Pick one on the left for its settings.")
                Put(canvas.how, canvas, 0, y, width, "")
                canvas.choose:ClearAllPoints()
                canvas.choose:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -(y + 12))
                canvas.choose:SetShown(kit.CanChoose())
                if kit.CanChoose() then y = y + 12 + 24 end
                local mine, other = {}, {}
                for _, page in ipairs(Pages()) do
                    mine[#mine + 1] = { icon = page.icon, title = page.title, about = page.about, how = HowLine(page) }
                end
                for _, c in ipairs(kit.catalog) do
                    local state = AddOnState(c.addon)
                    if kit.pages[c.addon:lower()] then
                        -- (listed above)
                    elseif state == "on" then
                        mine[#mine + 1] = { icon = c.icon, title = c.title, about = c.about,
                            how = c.command and ("Its settings: " .. c.command) or nil }
                    else
                        other[#other + 1] = { icon = c.icon, title = c.title, about = c.about,
                            how = state == "off" and "Installed, but off for this character (the AddOns list)."
                                or "Not installed." }
                    end
                end
                local n = 0
                local function List(head, headText, lines)
                    if #lines == 0 then
                        head:Hide()
                        return
                    end
                    y = y + 22 + Put(head, canvas, 0, y + 22, width, headText)
                    for _, entry in ipairs(lines) do
                        n = n + 1
                        canvas.entries[n] = canvas.entries[n] or Entry(canvas, 30)
                        y = y + 14 + canvas.entries[n].Layout(0, y + 14, width, entry)
                    end
                end
                List(canvas.headMine, "Your Quiet addons", mine)
                List(canvas.headOther, "Other Quiet addons", other)
                for i = n + 1, #canvas.entries do canvas.entries[i].Hide() end
                return y + 16
            end
        end
        return canvas
    end

    -- keep: stay where it was scrolled to (a refresh)
    function kit.Select(key, keep)
        local at = keep and scroll:GetVerticalScroll() or 0
        kit.selected = key or "welcome"
        if not panel:IsShown() then return end
        if kit.selected ~= "welcome" and not kit.pages[kit.selected] then kit.selected = "welcome" end
        for _, b in ipairs(side.buttons) do
            local on = b.key == kit.selected
            b.lit:SetShown(on)
            b.mark:SetShown(on)
        end
        for _, c in pairs(canvases) do c:Hide() end
        local canvas = Canvas(kit.selected)
        local width = math.max(200, scroll:GetWidth() - 4)
        canvas:SetWidth(width)
        local height = canvas.Layout(width)
        canvas:SetHeight(height)
        scroll.height = height
        scroll:SetScrollChild(canvas)
        local most = Most()
        bar:SetMinMaxValues(0, most)
        bar:SetShown(most > 0)
        if most > 0 then
            barThumb:SetHeight(math.max(24, scroll:GetHeight() * scroll:GetHeight() / height))
        end
        ScrollTo(at)
        canvas:Show()
    end

    panel:SetScript("OnShow", function()
        local keys, names = { "welcome" }, { "Welcome" }
        for _, page in ipairs(Pages()) do
            keys[#keys + 1] = page.key
            names[#names + 1] = page.title
        end
        for i, key in ipairs(keys) do
            local b = SideButton(i)
            b.key = key
            b.label:SetText(names[i])
            b:Show()
        end
        for i = #keys + 1, #side.buttons do side.buttons[i]:Hide() end
        -- (sized only once it's on screen)
        C_Timer.After(0, function() kit.Select(kit.selected) end)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, made = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and made then
            kit.category = made
            pcall(Settings.RegisterAddOnCategory, made)
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end
end

---------------------------------------------------------------------------
-- Improved Forever's panel (/if): one "Quiet" tab, a category for each page. It reads its lists as it draws, so
-- pages added later show up. Its settings page isn't a published API: every call is guarded, and without it the
-- Options page is still there.
---------------------------------------------------------------------------
local function IFReady()
    local IF = _G.ImprovedForever
    return IF and IF.SettingsPage and IF.SettingsItem and IF.SettingsOnOff and IF.Menu and IF.Menu.Open and IF or nil
end

function kit.BuildImprovedForever()
    local IF = IFReady()
    if not IF then return end
    kit.ifGroups = { { key = "welcome", label = "Welcome" } }
    -- (the welcome category: this line, then one for each Quiet addon that's on)
    kit.ifItems = { IF.SettingsItem({
        key = "welcome:about", group = "welcome", label = "Quiet",
        tip = "Calm little addons for WoW Forever. Each one's settings are a category down the left.",
    }, { text = function() return "" end }) }
    for _, page in ipairs(Pages()) do kit.AddToImprovedForever(page) end
    kit.ifPage = IF.SettingsPage({
        key = "quiet", label = "Quiet", icon = "Interface\\Icons\\Spell_Holy_Silence", order = 62,
    }, kit.ifGroups, kit.ifItems)
end

function kit.AddToImprovedForever(page)
    local IF = IFReady()
    if not kit.ifGroups or not IF then return end
    for _, g in ipairs(kit.ifGroups) do
        if g.key == page.key then return end
    end
    kit.ifGroups[#kit.ifGroups + 1] = { key = page.key, label = page.title }
    -- (on the welcome category: what it does and its command; a category shows only its own items, in order)
    table.insert(kit.ifItems, IF.SettingsItem({
        key = "welcome:" .. page.key, group = "welcome", label = page.title,
        note = function() return page.about .. "  " .. (Resolve(page.how) or "") end,
    }, { text = function() return page.command or "" end }))
    for n, item in ipairs(page.items) do
        local def = { key = page.key .. ":" .. n, group = page.key, section = item.section, label = item.label,
            tip = item.tip, hidden = item.hidden }
        local kind = Kind(item)
        if kind == "toggle" then
            def = IF.SettingsItem(def, IF.SettingsOnOff(item.get, item.set, item.label))
        elseif kind == "slider" then
            def.slider = { min = item.min, max = item.max, step = item.step or 1, get = item.get, set = item.set,
                format = item.format }
        elseif kind == "choice" then
            def.value = item.get
            def.text = function() return ChoiceName(item) end
            def.options = function()
                local list = {}
                for _, o in ipairs(Options(item)) do list[#list + 1] = { action = o.value, name = o.name } end
                return list
            end
            def.choose = item.set
        elseif kind == "macro" then
            -- (no dragging with the controller: a press puts it on a bar; a second field does it now, if it can)
            def.run = function() kit.PlaceMacro(item.macro) end
            def.button = "Put on my bar"
            if item.use then
                kit.ifItems[#kit.ifItems + 1] = { key = def.key .. ":use", group = page.key, section = item.section,
                    label = item.label, tip = item.tip, hidden = item.hidden, run = item.use, button = "Now" }
                def.section, def.label = nil, item.label .. ": on a bar"
            end
        else
            def.run = item.run
            def.button = item.text
            def.confirm = item.confirm
        end
        kit.ifItems[#kit.ifItems + 1] = def
    end
end

---------------------------------------------------------------------------
-- Opening a page: in gamepad mode, Improved Forever's tab (the game's options can't be opened from addon code
-- then), else Options > AddOns > Quiet. false: it couldn't, the caller says where to look.
---------------------------------------------------------------------------
-- A page's values drawn again, where it's showing (Options or Improved Forever's panel)
function kit.Refresh(key)
    if kit.panel and kit.panel:IsShown() and kit.selected == key and kit.Select then kit.Select(key, true) end
    local IF = IFReady()
    if IF and IF.Menu.IsOpen and IF.Menu.Render then
        pcall(function() if IF.Menu.IsOpen() then IF.Menu.Render() end end)
    end
end

-- Closes whichever settings panel is open (before a button opens a window of its own, which would sit under it)
function kit.ClosePanel()
    local IF = IFReady()
    if IF and IF.Menu.IsOpen and IF.Menu.Close then
        pcall(function() if IF.Menu.IsOpen() then IF.Menu.Close() end end)
    end
    if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
end

function kit.CanOpen()
    if PadMode() then return kit.ifPage ~= nil and IFReady() ~= nil end
    return kit.category ~= nil and Settings ~= nil and Settings.OpenToCategory ~= nil
end

function kit.Open(key)
    if not kit.CanOpen() then return false end
    if PadMode() then
        for i, g in ipairs(kit.ifGroups) do
            if g.key == key then pcall(kit.ifPage.SetGroup, kit.ifPage, i) end
        end
        return pcall(IFReady().Menu.Open, "quiet") and true or false
    end
    kit.selected = key
    local id = kit.category.GetID and kit.category:GetID() or kit.category.ID
    return pcall(Settings.OpenToCategory, id) and true or false
end

---------------------------------------------------------------------------
-- The setup window: every Quiet addon you have, a line on what each does, and a switch beside it. It comes once in
-- place of the welcome when several arrive together (the bundle, unpacked: everything is on, switch off what you
-- don't want), and from the Welcome page's "Choose addons" at any time. A switch turns the addon on or off for all
-- your characters, at a reload. Closing it without a change (its button, or Escape) keeps everything as it is.
---------------------------------------------------------------------------
local SETUP_W, SETUP_FROM = 560, 3

-- The game lets an addon be turned on and off from here (else the switches are left out, and it says where to)
function kit.CanChoose()
    return C_AddOns ~= nil and C_AddOns.EnableAddOn ~= nil and C_AddOns.DisableAddOn ~= nil and ReloadUI ~= nil
end

-- On for this character: now, or from the next login
local function AddOnWanted(name)
    local state = C_AddOns and C_AddOns.GetAddOnEnableState
    if state then
        local ok, n = pcall(state, name, UnitName("player"))
        if ok and type(n) == "number" then return n > 0 end
    end
    return AddOnState(name) == "on"
end

-- The catalog's addons that are installed, in its order
function kit.SetupList()
    local list = {}
    for _, c in ipairs(kit.catalog) do
        if AddOnState(c.addon) ~= "missing" then list[#list + 1] = c end
    end
    return list
end

-- The words under the list and on its button: what a press will do
function kit.SetupChanged()
    local w = kit.setup
    local off, on = {}, {}
    for _, c in ipairs(w.list) do
        if w.want[c.addon] ~= w.was[c.addon] then
            local names = w.want[c.addon] and on or off
            names[#names + 1] = c.title
        end
    end
    local parts = {}
    if #off > 0 then parts[#parts + 1] = "Off: " .. table.concat(off, ", ") .. "." end
    if #on > 0 then parts[#parts + 1] = "On: " .. table.concat(on, ", ") .. "." end
    if #parts > 0 then
        w.note:SetText(table.concat(parts, "  ") .. "  For all your characters.")
        w.ok:SetText("Apply and reload")
    elseif not kit.CanChoose() then
        w.note:SetText("To turn one off: the AddOns list, at the character screen.")
        w.ok:SetText("Got it")
    else
        -- ("its settings", in the lines above: where they are, for everyone)
        w.note:SetText("Its settings: Options, AddOns, Quiet, then its name.")
        w.ok:SetText(w.first and "Keep them all" or "Close")
    end
end

function kit.ApplySetup()
    local w = kit.setup
    local changed = false
    if kit.CanChoose() then
        for _, c in ipairs(w.list) do
            if w.want[c.addon] ~= w.was[c.addon] then
                changed = pcall(w.want[c.addon] and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn, c.addon) or changed
            end
        end
    end
    w:Hide()
    if changed then ReloadUI() end
end

function kit.BuildSetup()
    local w = UI.Window("QuietKitSetup", "", SETUP_W, 300)
    w.rows, w.heads, w.list, w.want, w.was = {}, {}, {}, {}, {}
    w.intro = UI.Text(w.body, "body")
    w.ok = UI.Button(w, "Close", function() kit.ApplySetup() end, 140, true)
    w.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    w.note = UI.Text(w, "muted")
    w.note:SetPoint("LEFT", w, "BOTTOMLEFT", 16, 26)
    w.note:SetPoint("RIGHT", w.ok, "LEFT", -12, 0)
    w.note:SetJustifyV("MIDDLE")
    w:SetScript("OnHide", function()
        -- (met now: none of them gets a welcome of its own)
        for _, shown in ipairs(w.shown or {}) do
            local db = shown.page.db and shown.page.db()
            if db then db.quietWelcomed = true end
        end
        w.shown = nil
        C_Timer.After(0.3, function() kit.NextToast() end)
    end)
    kit.setup = w
end

-- first: the first meeting (shown: the new pages, remembered as met when it closes); else as asked for
function kit.ShowSetup(first, shown)
    if not kit.setup then kit.BuildSetup() end
    local w = kit.setup
    local can = kit.CanChoose()
    w.first, w.shown, w.list, w.want, w.was = first, shown, kit.SetupList(), {}, {}
    for _, c in ipairs(w.list) do
        w.was[c.addon] = AddOnWanted(c.addon)
        w.want[c.addon] = w.was[c.addon]
    end
    w.title:SetText(first and "Welcome to Quiet" or "Your Quiet addons")
    local width = SETUP_W - 32
    local intro = "Small, calm addons for WoW Forever. Each does one thing, then keeps out of your way."
    if can then
        intro = intro .. (first and " They're all on now: switch off any you'd rather not have."
            or " Switch on the ones you want.")
    end
    local y = Put(w.intro, w.body, 0, 0, width, intro)
    local left = can and 46 or 0
    local group, heads = nil, 0
    for i, c in ipairs(w.list) do
        if c.group ~= group then
            group, heads = c.group, heads + 1
            w.heads[heads] = w.heads[heads] or UI.Text(w.body, "muted")
            y = y + 16 + Put(w.heads[heads], w.body, 0, y + 16, width, kit.groups[group] or "")
        end
        local row = w.rows[i]
        if not row then
            row = { icon = w.body:CreateTexture(nil, "ARTWORK"), title = UI.Text(w.body, "heading"),
                about = UI.Text(w.body, "small"), start = UI.Text(w.body, "muted") }
            row.icon:SetSize(20, 20)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.title:SetWordWrap(false)
            -- (an addon switched off is greyed out: its icon, its name, its line)
            function row.Paint()
                local on = w.want[row.addon] or not kit.CanChoose()
                row.icon:SetDesaturated(not on)
                row.icon:SetAlpha(on and 1 or 0.45)
                row.title:SetAlpha(on and 1 or 0.45)
                row.about:SetAlpha(on and 1 or 0.55)
                row.start:SetAlpha(on and 1 or 0.55)
            end
            row.toggle = UI.Toggle(w.body, function() return w.want[row.addon] end, function(on)
                w.want[row.addon] = on
                row.Paint()
                kit.SetupChanged()
            end)
            -- (the whole row switches it too: its icon, name and line)
            row.hit = CreateFrame("Button", nil, w.body)
            local lit = row.hit:CreateTexture(nil, "HIGHLIGHT")
            lit:SetAllPoints()
            Fill(lit, { 1, 1, 1, 0.04 })
            row.hit:SetScript("OnClick", function() row.toggle:GetScript("OnClick")(row.toggle) end)
            row.hit:SetScript("OnEnter", function() row.toggle:GetScript("OnEnter")(row.toggle) end)
            row.hit:SetScript("OnLeave", function() row.toggle:GetScript("OnLeave")(row.toggle) end)
            w.rows[i] = row
        end
        row.addon = c.addon
        local page = kit.pages[c.addon:lower()]
        y = y + 8
        row.toggle:ClearAllPoints()
        row.toggle:SetPoint("TOPLEFT", w.body, "TOPLEFT", 0, -(y + 1))
        row.toggle:SetShown(can)
        row.toggle.Refresh()
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", w.body, "TOPLEFT", left, -y)
        row.icon:SetTexture((page and page.icon) or c.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:Show()
        Put(row.title, w.body, left + 28, y + 3, 128, c.title)
        local top = y
        local text = 4 + Put(row.about, w.body, left + 160, y + 4, width - left - 160, c.about)
        -- (and where to start it: its command, its key, its button for your bar)
        if c.start then text = text + 3 + Put(row.start, w.body, left + 160, y + text + 3, width - left - 160, c.start) end
        y = y + math.max(20, text)
        row.hit:ClearAllPoints()
        row.hit:SetPoint("TOPLEFT", w.body, "TOPLEFT", left - 4, -(top - 3))
        row.hit:SetSize(width - left + 4, y - top + 6)
        row.hit:SetShown(can)
        row.Paint()
    end
    for i = #w.list + 1, #w.rows do
        local row = w.rows[i]
        row.hit:Hide()
        row.start:Hide()
        row.toggle:Hide()
        row.icon:Hide()
        row.title:Hide()
        row.about:Hide()
    end
    for i = heads + 1, #w.heads do w.heads[i]:Hide() end
    local height = 44 + y + 20 + 24 + 14
    w:SetHeight(height)
    -- (a long list on a small screen: the whole window a little smaller, rather than off the edge)
    w:SetScale(math.min(1, (UIParent:GetHeight() - 40) / height))
    w:ClearAllPoints()
    w:SetPoint("CENTER")
    kit.SetupChanged()
    w:Show()
end

---------------------------------------------------------------------------
-- The welcome window: once for each newly installed Quiet addon, and once for what's new in one you had, a little
-- after you're in the world and out of a fight. Closing it (its buttons, or Escape) remembers them.
---------------------------------------------------------------------------
local WELCOME_W = 460

function kit.BuildWelcome()
    local w = UI.Window("QuietKitWelcome", "", WELCOME_W, 200)
    w:ClearAllPoints()
    w:SetPoint("TOP", UIParent, "TOP", 0, -140)
    w.entries = {}
    w.close:Hide()
    w.ok = UI.Button(w, "Got it", function() w:Hide() end, 110, true)
    w.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    w.settings = UI.Button(w, "Settings", function()
        w:Hide()
        kit.Open(w.first or "welcome")
    end, 110)
    w.settings:SetPoint("RIGHT", w.ok, "LEFT", -8, 0)
    -- (where the settings are, when the button can't open them: gamepad mode without Improved Forever)
    w.where = UI.Text(w, "muted")
    w.where:SetPoint("LEFT", w, "BOTTOMLEFT", 16, 26)
    w.where:SetPoint("RIGHT", w.ok, "LEFT", -12, 0)
    w.where:SetText("Settings: Options, AddOns, Quiet.")
    w:SetScript("OnHide", function()
        for _, shown in ipairs(w.shown or {}) do
            local db = shown.page.db and shown.page.db()
            if db then
                db.quietWelcomed = true
                if shown.page.news then db.quietNews = shown.page.news.version end
            end
        end
        w.shown = nil
        -- (notes held back while it was up)
        C_Timer.After(0.3, function() kit.NextToast() end)
    end)
    kit.welcome = w
end

function kit.TryWelcome()
    if InCombatLockdown() then
        kit.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local shown, new, news = {}, 0, 0
    for _, page in ipairs(Pages()) do
        local what = WelcomeFor(page)
        if what then
            shown[#shown + 1] = { page = page, what = what }
            if what == "new" then new = new + 1 else news = news + 1 end
        end
    end
    if #shown == 0 then return end
    -- (several new ones at once, the bundle unpacked: the setup window, where each can be switched off, instead)
    if new >= SETUP_FROM and kit.CanChoose() then
        local fresh = {}
        for _, s in ipairs(shown) do
            if s.what == "new" then fresh[#fresh + 1] = s end
        end
        kit.ShowSetup(true, fresh)
        return
    end
    if not kit.welcome then kit.BuildWelcome() end
    local w = kit.welcome
    w.title:SetText(news == 0 and (new == 1 and "A new Quiet addon" or "New Quiet addons")
        or new == 0 and "What's new in Quiet" or "Quiet")
    local width = WELCOME_W - 32
    local y = 0
    for i, s in ipairs(shown) do
        local page = s.page
        w.entries[i] = w.entries[i] or Entry(w.body, 32)
        local lines = { icon = page.icon, title = page.title, about = page.about, how = HowLine(page) }
        if s.what == "news" then
            lines.title = page.title .. "  |cff8f8f94" .. page.news.version .. "|r"
            lines.about, lines.how = page.news.text, nil
        end
        y = y + (i > 1 and 16 or 0)
        y = y + w.entries[i].Layout(0, y, width, lines)
    end
    for i = #shown + 1, #w.entries do w.entries[i].Hide() end
    w:SetHeight(44 + y + 20 + 24 + 14)
    local canOpen = kit.CanOpen()
    w.settings:SetShown(canOpen)
    w.where:SetShown(not canOpen)
    w.shown, w.first = shown, shown[1].page.key
    w:Show()
end

---------------------------------------------------------------------------
-- This realm's name: QuietKit.Realm. The one name everything kept by realm goes under.
--
-- The game can stop naming its realm (WoW Forever's GetRealmName() answers "" since November 2026), and then
-- everything kept as "Name-Realm" or "Realm-Faction" splits in two: the same character once with the realm and once
-- without, each half going stale. So no Quiet addon reads the game's name itself. It asks here:
--   QuietKit.Realm()   the game's name when it gives one; else the last name it gave (kept as quietRealm in every
--                      registered Quiet addon's saved table); else the realm your characters were last seen on.
--                      "" only when none of that is known (a new player on a nameless realm), until a name is.
--   QuietKit.RealmFold(list, side, join)
--                      what was kept under no realm is this realm's: each "Name-" key of list moves to
--                      "Name-Realm" (side true: each "-Faction" to "Realm-Faction"), and a realm = "" in it is
--                      filled in. Where both are there, join(named, nameless) gives the one to keep; without it
--                      the nameless one, the later of the two, stays. Returns how many moved. Call it once
--                      everything has loaded (PLAYER_LOGIN or later): the name isn't settled before.
---------------------------------------------------------------------------
local stockSecret = issecretvalue or function() return false end
local function Seen(value)
    if stockSecret(value) then return nil end
    return value
end

local STOCK_PLACES = { "bags", "bank", "mail" } -- (where a character's things are written down: the Stock, below)

local function LoggedIn()
    return kit.loggedIn or (IsLoggedIn and IsLoggedIn()) or false
end

-- Every registered Quiet addon's saved table, where it can be had
local function SavedTables()
    local list = {}
    for _, page in pairs(kit.pages) do
        if type(page.db) == "function" then
            local ok, db = pcall(page.db)
            if ok and type(db) == "table" then list[#list + 1] = db end
        end
    end
    return list
end

-- The realm the characters written down were last seen on (nil: none of them has one)
local function RealmOfRecords(dbs)
    local lists = {}
    for _, db in ipairs(dbs) do lists[#lists + 1] = db.quietStock end
    local qb = _G.QuietBagsDB
    if type(qb) == "table" then lists[#lists + 1] = qb.chars end
    local realm, newest = nil, -1
    for _, chars in ipairs(lists) do
        if type(chars) == "table" then
            for _, char in pairs(chars) do
                if type(char) == "table" and type(char.realm) == "string" and char.realm ~= "" then
                    local at = 0
                    for _, where in ipairs(STOCK_PLACES) do
                        local place = char[where]
                        at = math.max(at, type(place) == "table" and tonumber(place.at) or 0)
                    end
                    if at > newest then realm, newest = char.realm, at end
                end
            end
        end
    end
    return realm
end

function kit.Realm()
    if kit.realm then return kit.realm end
    local dbs = SavedTables()
    local realm = GetRealmName and Seen(GetRealmName())
    if type(realm) ~= "string" or realm == "" then
        realm = nil
        for _, db in ipairs(dbs) do
            if type(db.quietRealm) == "string" and db.quietRealm ~= "" then
                realm = db.quietRealm
                break
            end
        end
        realm = realm or RealmOfRecords(dbs)
    end
    -- (settled, and written down, only once every addon's saved table is there to be read)
    if not LoggedIn() then return realm or "" end
    kit.realm = realm or ""
    if realm then
        for _, db in ipairs(dbs) do db.quietRealm = realm end
    end
    return kit.realm
end

function kit.RealmFold(list, side, join)
    if type(list) ~= "table" then return 0 end
    local realm = kit.Realm()
    if realm == "" then return 0 end
    local moves = {}
    for key in pairs(list) do
        local rest = type(key) == "string" and key:match(side and "^%-(.+)$" or "^(.+)%-$")
        if rest then moves[#moves + 1] = { key, side and (realm .. "-" .. rest) or (rest .. "-" .. realm) } end
    end
    for _, move in ipairs(moves) do
        local nameless, named = list[move[1]], list[move[2]]
        list[move[1]] = nil
        if named ~= nil and join then nameless = join(named, nameless) end
        if type(nameless) == "table" and nameless.realm == "" then nameless.realm = realm end
        list[move[2]] = nameless
    end
    return #moves
end

---------------------------------------------------------------------------
-- What each character holds: QuietKit.Stock. One count, for every Quiet addon.
--
-- On every character where any Quiet addon is on, the kit writes down what's in its bags (the reagent bag too),
-- its bank (whenever that's open) and its mailbox (whenever that's open), each with when it was seen. It's kept in
-- the saved table of EVERY registered Quiet addon (db().quietStock["Name-Realm"]), small: only counts. So whichever
-- Quiet addons a character has on, its things are written down, and any Quiet addon on any other character reads
-- the same numbers: no addon counts for itself, and none goes stale because another was switched off.
--   QuietKit.Stock.Chars()   { ["Name-Realm"] = { name, realm, class, faction, bags, bank, mail } }, every character
--                            known, each place the freshest copy there is (Quiet Bags' own older records too)
--                            place = { at, slots, items = { [itemID] = { count, link, icon } } } (link and icon
--                            only where Quiet Bags saw it)
--   QuietKit.Stock.BagIDs()  the containers that are this character's bags: backpack, bags, reagent bag
--   QuietKit.Stock.BankIDs() the containers that are its bank
--   QuietKit.Stock.MyKey()   this character's "Name-Realm" (the realm as QuietKit.Realm names it); nil until the
--                            game has logged it in
--   QuietKit.Stock.version   goes up whenever anything was read anew
--   QuietKit.Stock.Touch()   (for Quiet Bags: its own records changed)   QuietKit.Stock.Forget(key)
---------------------------------------------------------------------------
local Stock = kit.Stock or {}
kit.Stock = Stock
Stock.version = Stock.version or 0

local StockSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local StockSlot = C_Container and C_Container.GetContainerItemInfo

-- Which containers are the bags and which the bank. The game's own list (Enum.BagIndex) when it has one, so a
-- reagent bag or bank tabs count too; the account bank is left out (it's everyone's, not this character's).
local function StockContainers()
    if Stock.bagIDs then return end
    local bagIDs, bankIDs, seen = {}, {}, {}
    local index = Enum and Enum.BagIndex
    if type(index) == "table" then
        for key, id in pairs(index) do
            if type(key) == "string" and type(id) == "number" and not seen[id] then
                if key == "Backpack" or key:find("^Bag_") or key:find("^ReagentBag") then
                    seen[id] = true
                    bagIDs[#bagIDs + 1] = id
                elseif key:find("^Bank") or key:find("^CharacterBankTab") or key:find("^Reagentbank") then
                    seen[id] = true
                    bankIDs[#bankIDs + 1] = id
                end
            end
        end
    end
    -- (the old numbers: backpack 0, bags 1-4, a reagent bag after them, bank -1, bank bags after those)
    local bags = NUM_BAG_SLOTS or 4
    local carried = NUM_TOTAL_EQUIPPED_BAG_SLOTS or (bags + (NUM_REAGENTBAG_SLOTS or 0))
    if #bagIDs == 0 then
        for bag = 0, carried do bagIDs[#bagIDs + 1] = bag end
    end
    if #bankIDs == 0 then
        bankIDs[1] = BANK_CONTAINER or -1
        for bag = carried + 1, carried + (NUM_BANKBAGSLOTS or 7) do bankIDs[#bankIDs + 1] = bag end
    end
    table.sort(bagIDs)
    table.sort(bankIDs)
    Stock.bagIDs, Stock.bankIDs = bagIDs, bankIDs
end

function Stock.BagIDs()
    StockContainers()
    return Stock.bagIDs
end

function Stock.BankIDs()
    StockContainers()
    return Stock.bankIDs
end

-- What's in some containers: { [itemID] = count }, and how many slots there were; nil when the game shows no
-- slots at all (not ready yet, or the bank already closed), so what was kept isn't wiped by an empty read
local function StockRead(containers)
    if not (StockSlots and StockSlot) then return nil end
    local items, slots = {}, 0
    for _, bag in ipairs(containers) do
        local ok, n = pcall(StockSlots, bag)
        n = ok and Seen(n)
        if type(n) == "number" and n > 0 then
            slots = slots + n
            for slot = 1, n do
                local got, info = pcall(StockSlot, bag, slot)
                info = got and Seen(info)
                local id = type(info) == "table" and Seen(info.itemID)
                if type(id) == "number" then
                    local count = Seen(info.stackCount)
                    items[id] = (items[id] or 0) + (type(count) == "number" and count or 1)
                end
            end
        end
    end
    if slots == 0 then return nil end
    return items, slots
end

-- Every registered Quiet addon's saved table: the place in it for the characters
local function StockStores()
    local list = {}
    for _, db in ipairs(SavedTables()) do
        if type(db.quietStock) ~= "table" then db.quietStock = {} end
        list[#list + 1] = db.quietStock
    end
    return list
end

-- A character written down twice, with the realm's name and without (QuietKit.Realm): one record again, each place
-- as it was seen last
local function StockJoin(named, nameless)
    if type(named) ~= "table" or type(nameless) ~= "table" then return nameless end
    for _, where in ipairs(STOCK_PLACES) do
        local old, new = named[where], nameless[where]
        if type(old) == "table" and (type(new) ~= "table" or (tonumber(old.at) or 0) > (tonumber(new.at) or 0)) then
            nameless[where] = old
        end
    end
    nameless.class, nameless.faction = nameless.class or named.class, nameless.faction or named.faction
    return nameless
end

-- Once a session, when everything has loaded: what was kept under no realm goes under this one, in every Quiet
-- addon's table and in Quiet Bags' own
local function StockFold()
    if Stock.folded or not LoggedIn() then return end
    Stock.folded = true
    local moved = 0
    for _, store in ipairs(StockStores()) do moved = moved + kit.RealmFold(store, false, StockJoin) end
    local qb = _G.QuietBagsDB
    if type(qb) == "table" then moved = moved + kit.RealmFold(qb.chars, false, StockJoin) end
    if moved > 0 then
        Stock.myKey, Stock.record, Stock.merged = nil, nil, nil
        Stock.version = Stock.version + 1
    end
end

function Stock.MyKey()
    if not Stock.myKey then
        if not LoggedIn() then return nil end
        StockFold()
        local name = Seen(UnitName("player"))
        if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
        Stock.myKey = name .. "-" .. kit.Realm()
    end
    return Stock.myKey
end

-- A place as it's handed out: counts as { count = n } (the kit keeps bare numbers, Quiet Bags keeps tables)
local function StockNormal(place)
    Stock.normal = Stock.normal or setmetatable({}, { __mode = "k" })
    local done = Stock.normal[place]
    if done then return done end
    local plain = false
    for _, item in pairs(place.items) do
        plain = type(item) == "number"
        break
    end
    done = place
    if plain then
        done = { at = place.at, slots = place.slots, items = {} }
        for id, n in pairs(place.items) do
            if type(n) == "number" then done.items[id] = { count = n } end
        end
    end
    Stock.normal[place] = done
    return done
end

function Stock.Chars()
    StockFold()
    if Stock.merged and Stock.mergedAt == Stock.version then return Stock.merged end
    -- (Quiet Bags' own records first: where both saw a place at the same time, its fuller one stays)
    local sources = {}
    local qb = _G.QuietBagsDB
    if type(qb) == "table" and type(qb.chars) == "table" then sources[1] = qb.chars end
    for _, store in ipairs(StockStores()) do sources[#sources + 1] = store end
    local merged = {}
    for _, chars in ipairs(sources) do
        for key, char in pairs(chars) do
            if type(key) == "string" and type(char) == "table" then
                local m = merged[key] or {}
                merged[key] = m
                m.name, m.realm = m.name or char.name, m.realm or char.realm
                m.class, m.faction = m.class or char.class, m.faction or char.faction
                for _, where in ipairs(STOCK_PLACES) do
                    local place = char[where]
                    if type(place) == "table" and type(place.items) == "table"
                        and (not m[where] or (tonumber(place.at) or 0) > (tonumber(m[where].at) or 0)) then
                        m[where] = StockNormal(place)
                    end
                end
            end
        end
    end
    Stock.merged, Stock.mergedAt = merged, Stock.version
    return merged
end

function Stock.Touch()
    Stock.version = Stock.version + 1
    Stock.merged = nil
end

function Stock.Forget(key)
    for _, store in ipairs(StockStores()) do store[key] = nil end
    Stock.Touch()
end

-- A character as the kit keeps it: its places with bare counts
local function StockCompact(char)
    local record = { name = char and char.name, realm = char and char.realm, class = char and char.class,
        faction = char and char.faction }
    for _, where in ipairs(STOCK_PLACES) do
        local place = char and char[where]
        if place then
            local items = {}
            for id, item in pairs(place.items) do
                items[id] = type(item) == "table" and tonumber(item.count) or tonumber(item) or nil
            end
            record[where] = { at = place.at, slots = place.slots, items = items }
        end
    end
    return record
end

-- Every other character's freshest record, written into each Quiet addon's table that has an older one or none:
-- so what one addon learned on another character is there for the rest, whichever of them are on next time
local function StockSpread()
    local stores, mine = StockStores(), Stock.MyKey()
    for key, char in pairs(Stock.Chars()) do
        if key ~= mine then
            local record
            for _, store in ipairs(stores) do
                local kept = store[key]
                local stale = type(kept) ~= "table"
                for _, where in ipairs(STOCK_PLACES) do
                    if not stale and char[where] and (type(kept[where]) ~= "table"
                        or (tonumber(kept[where].at) or 0) < (tonumber(char[where].at) or 0)) then
                        stale = true
                    end
                end
                if stale then
                    record = record or StockCompact(char)
                    store[key] = record
                end
            end
        end
    end
    Stock.Touch()
end

-- This character's record: one table, the same in every store. It starts from the freshest of what was kept.
local function StockMine()
    local key = Stock.MyKey()
    if not key then return nil end
    local record = Stock.record
    if not record then
        record = StockCompact(Stock.Chars()[key])
        Stock.record = record
    end
    record.name, record.realm = key:match("^(.-)%-(.*)$")
    local _, class = UnitClass("player")
    record.class = Seen(class) or record.class
    local faction = Seen(UnitFactionGroup("player"))
    if type(faction) == "string" and faction ~= "Neutral" then record.faction = faction end
    for _, store in ipairs(StockStores()) do store[key] = record end
    return record
end

local function StockKeep(where, items, slots)
    if not items then return end
    local me = StockMine()
    if not me then return end
    me[where] = { at = time(), items = items, slots = slots }
    Stock.Touch()
end

local function StockBags()
    StockContainers()
    StockKeep("bags", StockRead(Stock.bagIDs))
end

local function StockBank()
    if not Stock.bankOpen then return end
    StockContainers()
    StockKeep("bank", StockRead(Stock.bankIDs))
end

-- Away from the bank, a moment after login: some clients already know what's in it. Only taken when it shows
-- something, and at least as many slots as at the last visit; else what was seen at the bank stays.
local function StockBankAway()
    if Stock.bankOpen then return end
    StockContainers()
    local items, slots = StockRead(Stock.bankIDs)
    local me = StockMine()
    if not (items and me and next(items)) then return end
    if me.bank and (me.bank.slots or math.huge) > slots then return end
    StockKeep("bank", items, slots)
end

-- The mailbox's attachments, as far as the game shows them (it shows at most 50 mails at a time)
local function StockMail()
    if not Stock.mailOpen or not GetInboxNumItems then return end
    local ok, shown = pcall(GetInboxNumItems)
    shown = ok and Seen(shown)
    if type(shown) ~= "number" then return end
    local items = {}
    for i = 1, shown do
        local got, _, _, _, _, _, _, _, itemCount = pcall(GetInboxHeaderInfo, i)
        itemCount = got and Seen(itemCount)
        if type(itemCount) == "number" and itemCount > 0 then
            for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
                local had, _, id, _, count = pcall(GetInboxItem, i, a)
                id = had and Seen(id)
                if type(id) == "number" then
                    count = Seen(count)
                    items[id] = (items[id] or 0) + (type(count) == "number" and count or 1)
                end
            end
        end
    end
    StockKeep("mail", items)
end

local function StockOpenBank()
    Stock.bankOpen = true
    StockBank()
    -- (and again a moment later, in case the bank's slots fill in after the window opens)
    C_Timer.After(1, StockBank)
end

function Stock.OnEvent(_, event, arg)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            StockBags()
            StockBankAway()
            StockSpread()
        end)
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LOGOUT" then
        -- (bank bags changing while the bank is open come through here too)
        StockBags()
        StockBank()
    elseif event == "BANKFRAME_OPENED" then
        StockOpenBank()
    elseif event == "BANKFRAME_CLOSED" then
        Stock.bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        StockBank()
    elseif event == "MAIL_SHOW" then
        Stock.mailOpen = true
    elseif event == "MAIL_INBOX_UPDATE" then
        StockMail()
    elseif event == "MAIL_CLOSED" then
        Stock.mailOpen = false
    else
        -- The newer way the game says a bank or mailbox opened or closed
        local kinds = Enum and Enum.PlayerInteractionType
        local kind = Seen(arg)
        local shown = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        if kind == nil or type(kinds) ~= "table" then return end
        if kinds.Banker and kind == kinds.Banker then
            if shown and not Stock.bankOpen then StockOpenBank() elseif not shown then Stock.bankOpen = false end
        elseif kinds.MailInfo and kind == kinds.MailInfo then
            Stock.mailOpen = shown
        end
    end
end

if not Stock.events then
    Stock.events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LOGOUT", "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
        -- (pcall: a client that doesn't know an event refuses it)
        pcall(Stock.events.RegisterEvent, Stock.events, event)
    end
end
-- (the newest copy's function answers: it's looked up on the table each time)
Stock.events:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(Stock.OnEvent, self, event, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end)

---------------------------------------------------------------------------
-- Events (the newest copy's functions answer: they're looked up on the table each time)
---------------------------------------------------------------------------
function kit.OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        kit.loggedIn = true
        StockFold()
        if kit.built then return end
        kit.built = true
        kit.BuildPanel()
        local ok, err = pcall(kit.BuildImprovedForever)
        if not ok then
            kit.ifPage = nil
            geterrorhandler()(err)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- (a moment, so it isn't lost in the loading screen's last flicker and the addons' own first steps)
        C_Timer.After(4, function() kit.TryWelcome() end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        kit.TryWelcome()
    elseif event == "ADDON_LOADED" then
        kit.NoteLoaded(...)
    end
end

kit.events = kit.events or CreateFrame("Frame")
kit.events:RegisterEvent("ADDON_LOADED")
kit.events:RegisterEvent("PLAYER_LOGIN")
kit.events:RegisterEvent("PLAYER_ENTERING_WORLD")
kit.events:SetScript("OnEvent", function(self, event, ...) kit.OnEvent(self, event, ...) end)
