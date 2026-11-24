local addonName, privateTable = ...

-- Which frames Quiet HUD fades, and how much: a small window in QuietKit's look (the settings page holds only simple
-- settings). The frames down the left, grouped, each with its switch; pick one for its alphas on the right.
-- For the mouse and the controller's cursor alike: every value has < and > beside its slider (the mouse wheel steps
-- it too), Up and Down move the list, and nothing needs a right-click. Opened from the page's Frames button, or
-- /qhud frames.
local UI = QuietKit.UI
local C = UI.C
local ToSteps, FromSteps = privateTable.ToSteps, privateTable.FromSteps

local WIDTH, HEIGHT = 680, 480
local LIST_W = 230
local ROW = 24
local HEAD = 26
local VALUE_ROW = 30
local LABEL_W = 100
local SLIDER_W = 150
local DEFAULT_FRAME = "GamepadMainActionBarFrame"

local window
local selected = DEFAULT_FRAME
local scroll, maxScroll = 0, 0

local function Config(frameName)
    local frames = QuietHUDDB and QuietHUDDB.frames
    return frames and frames[frameName]
end

-- ---------- a frame's values, in the steps the sliders take ----------
-- alpha: 0-100 (%); off: one step below 0 is Off (-1 stored: the controller or the mouse doesn't change it);
-- time: tenths of a second, one step below 0 is Global (the page's fade time)
local VALUES = {
    { key = "alphaExplore", label = "Explore", fallback = 0,
        tip = "While nothing else is going on." },
    { key = "alphaMouse", label = "Mouse", off = true,
        tip = "In place of Explore while you play with keyboard and mouse (the page's \"Show more on keyboard and "
            .. "mouse\"). Off: the same as with the controller." },
    { key = "alphaPad", label = "Controller", off = true,
        tip = "While you hold L2 / R2 or press the D-pad (the page's \"Reveal with the controller\"). Off: the "
            .. "controller doesn't show this frame." },
    { key = "alphaCombat", label = "Combat", fallback = 1,
        tip = "While you're in a fight." },
    { key = "alphaTarget", label = "Target", fallback = 1,
        tip = "While you have a target." },
    { key = "alphaHover", label = "Pointed at", fallback = 1,
        tip = "While the mouse (or the controller's cursor) is over it, while \"Show faded frames\" is held, and for a "
            .. "while after something it shows happens (a message, quest progress, a new zone)." },
    { key = "alphaHealthLow", label = "Low health", fallback = 0.5, playerOnly = true,
        tip = "While your health comes back after a fight." },
    { key = "alphaManaLow", label = "Low mana", fallback = 0.5, playerOnly = true,
        tip = "While your mana comes back." },
    { key = "duration", label = "Fade time", time = true,
        tip = "This frame's own fade time. Global: the settings page's." },
}

local function Range(spec)
    if spec.time then return -1, 20, 1 end
    return spec.off and -5 or 0, 100, 5
end

local function GetSteps(spec)
    local cfg = Config(selected)
    local value = cfg and cfg[spec.key]
    if spec.time then
        if value == nil or value < 0 then return -1 end
        return ToSteps(value, 10)
    end
    if value == nil then value = spec.off and -1 or spec.fallback end
    if spec.off and value < 0 then return -5 end
    return ToSteps(value, 100)
end

local function SetSteps(spec, steps)
    local cfg = Config(selected)
    if not cfg then return end
    if steps < 0 then
        cfg[spec.key] = -1
    else
        cfg[spec.key] = FromSteps(steps, spec.time and 10 or 100)
    end
end

local function Format(spec, steps)
    if spec.time then return steps < 0 and "Global" or string.format("%.1f s", steps / 10) end
    if steps < 0 then return "Off" end
    return steps .. "%"
end

-- ---------- the list ----------
local function Fill(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function ScrollTo(value)
    scroll = math.max(0, math.min(value, maxScroll))
    window.scroller:SetVerticalScroll(scroll)
    window.up:SetEnabled(scroll > 0)
    window.down:SetEnabled(scroll < maxScroll)
end

local Refresh

local function Select(frameName)
    selected = frameName
    Refresh()
end

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LIST_W - 8, ROW)
    row.toggle = UI.Toggle(row, function()
        local cfg = Config(row.frameName)
        return cfg and cfg.enabled
    end, function(on)
        local cfg = Config(row.frameName)
        if not cfg then return end
        cfg.enabled = on and true or false
        -- (off: its fade is cancelled and it's shown in full again)
        if not on then privateTable.ResetFrame(row.frameName) end
        if row.frameName == selected then Refresh() end
    end)
    row.toggle:SetPoint("LEFT", 0, 0)
    local name = CreateFrame("Button", nil, row)
    name:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
    name:SetPoint("RIGHT")
    name:SetHeight(ROW - 2)
    name.lit = name:CreateTexture(nil, "BACKGROUND")
    name.lit:SetAllPoints()
    Fill(name.lit, { C.accent[1], C.accent[2], C.accent[3], 0.16 })
    name.mark = name:CreateTexture(nil, "ARTWORK")
    name.mark:SetPoint("TOPLEFT")
    name.mark:SetPoint("BOTTOMLEFT")
    name.mark:SetWidth(2)
    Fill(name.mark, C.accent)
    local hover = name:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    Fill(hover, { 1, 1, 1, 0.06 })
    name.label = UI.Text(name, "body")
    name.label:SetPoint("LEFT", 8, 0)
    name.label:SetPoint("RIGHT", -4, 0)
    name.label:SetJustifyV("MIDDLE")
    name.label:SetWordWrap(false)
    name:SetScript("OnClick", function() Select(row.frameName) end)
    -- (the frame's own name, for /qhud remove or /fstack)
    name:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(privateTable.GetFrameLabel(row.frameName))
        if privateTable.GetFrameLabel(row.frameName) ~= row.frameName then
            GameTooltip:AddLine(row.frameName, C.muted[1], C.muted[2], C.muted[3])
        end
        GameTooltip:Show()
    end)
    name:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.name = name
    return row
end

local function FillList()
    local child = window.child
    local rows, heads = window.rows, window.heads
    for _, row in ipairs(rows) do row:Hide() end
    for _, head in ipairs(heads) do head:Hide() end
    local y, nRows, nHeads = 0, 0, 0
    for _, group in ipairs(privateTable.GetFrameGroups()) do
        if #group.frames > 0 then
            nHeads = nHeads + 1
            local head = heads[nHeads] or UI.Text(child, "heading")
            heads[nHeads] = head
            head:SetWordWrap(false)
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", 2, -(y + 8))
            head:SetText(group.name)
            head:Show()
            y = y + HEAD
            for _, frameName in ipairs(group.frames) do
                nRows = nRows + 1
                local row = rows[nRows] or NewRow(child)
                rows[nRows] = row
                row.frameName = frameName
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row.toggle.Refresh()
                row.name.label:SetText(privateTable.GetFrameLabel(frameName))
                row.name.lit:SetShown(frameName == selected)
                row.name.mark:SetShown(frameName == selected)
                row:Show()
                y = y + ROW
            end
        end
    end
    child:SetHeight(math.max(y + 6, 1))
    maxScroll = math.max(0, y + 6 - window.scroller:GetHeight())
    ScrollTo(scroll)
end

-- ---------- the chosen frame's values ----------
local function NewValueRow(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(VALUE_ROW)
    row.spec = spec
    row.label = UI.Text(row, "body")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(LABEL_W)
    row.label:SetWordWrap(false)
    row.label:SetText(spec.label)
    local min, max, step = Range(spec)
    local function Show(steps)
        row.value:SetText(Format(spec, steps))
    end
    local function Step(dir)
        local steps = math.max(min, math.min(max, GetSteps(spec) + dir * step))
        SetSteps(spec, steps)
        row.slider.Fill(steps)
        Show(steps)
    end
    row.prev = UI.Button(row, "<", function() Step(-1) end, 24)
    row.prev:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
    row.slider = UI.Slider(row, min, max, step, function(steps)
        SetSteps(spec, steps)
        Show(steps)
    end)
    row.slider:SetWidth(SLIDER_W)
    row.slider:SetPoint("LEFT", row.prev, "RIGHT", 8, 0)
    row.next = UI.Button(row, ">", function() Step(1) end, 24)
    row.next:SetPoint("LEFT", row.slider, "RIGHT", 8, 0)
    row.value = UI.Text(row, "small")
    row.value:SetPoint("LEFT", row.next, "RIGHT", 10, 0)
    row.value:SetWordWrap(false)
    -- (what it means, on pointing at it)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(spec.label)
        GameTooltip:AddLine(spec.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function row.Refresh()
        local steps = GetSteps(spec)
        row.slider.Fill(steps)
        Show(steps)
    end
    return row
end

local function FillValues()
    local right = window.right
    local cfg = Config(selected)
    right.name:SetText(privateTable.GetFrameLabel(selected))
    right.fade.Refresh()
    local y = 64
    for _, row in ipairs(right.values) do
        local shown = cfg ~= nil and (not row.spec.playerOnly or selected == "PlayerFrame")
        row:SetShown(shown)
        if shown then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("RIGHT")
            row.Refresh()
            -- (a frame that isn't faded: its values wait, dimmed)
            row:SetAlpha(cfg.enabled and 1 or 0.45)
            y = y + VALUE_ROW
        end
    end
    right.remove:SetShown(cfg ~= nil and cfg.custom and true or false)
end

function Refresh()
    if not (window and window:IsShown()) then return end
    if not Config(selected) then selected = DEFAULT_FRAME end
    FillList()
    FillValues()
end

-- ---------- the window ----------
local function Build()
    local w = UI.Window("QuietHUDFramesWindow", "Quiet HUD: frames", WIDTH, HEIGHT)
    local body = w.body

    -- Left: the frames, in a frame that scrolls, Up and Down under it
    w.scroller = CreateFrame("ScrollFrame", nil, body)
    w.scroller:SetPoint("TOPLEFT", 0, 0)
    w.scroller:SetPoint("BOTTOMLEFT", 0, 38)
    w.scroller:SetWidth(LIST_W)
    w.child = CreateFrame("Frame", nil, w.scroller)
    w.child:SetSize(LIST_W, 1)
    w.scroller:SetScrollChild(w.child)
    w.scroller:EnableMouseWheel(true)
    w.scroller:SetScript("OnMouseWheel", function(_, delta) ScrollTo(scroll - delta * 3 * ROW) end)
    w.rows, w.heads = {}, {}
    w.up = UI.Button(body, "Up", function() ScrollTo(scroll - 8 * ROW) end, 60)
    w.up:SetPoint("BOTTOMLEFT", 0, 0)
    w.down = UI.Button(body, "Down", function() ScrollTo(scroll + 8 * ROW) end, 60)
    w.down:SetPoint("LEFT", w.up, "RIGHT", 6, 0)
    local pick = UI.Button(body, "Pick on screen", function()
        w:Hide()
        privateTable.StartPicker()
    end)
    pick:SetPoint("LEFT", w.down, "RIGHT", 6, 0)

    local divider = body:CreateTexture(nil, "BORDER")
    Fill(divider, C.line)
    divider:SetPoint("TOPLEFT", LIST_W + 12, 0)
    divider:SetPoint("BOTTOMLEFT", LIST_W + 12, 0)
    divider:SetWidth(1)

    -- Right: the chosen frame
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", LIST_W + 26, 0)
    right:SetPoint("BOTTOMRIGHT")
    w.right = right
    right.name = UI.Text(right, "heading")
    right.name:SetPoint("TOPLEFT", 0, -2)
    right.name:SetPoint("RIGHT")
    right.name:SetWordWrap(false)
    right.fade = UI.Toggle(right, function()
        local cfg = Config(selected)
        return cfg and cfg.enabled
    end, function(on)
        local cfg = Config(selected)
        if not cfg then return end
        cfg.enabled = on and true or false
        if not on then privateTable.ResetFrame(selected) end
        Refresh()
    end)
    right.fade:SetPoint("TOPLEFT", 0, -30)
    local fadeLabel = UI.Text(right, "body")
    fadeLabel:SetPoint("LEFT", right.fade, "RIGHT", 12, 0)
    fadeLabel:SetText("Fade this frame")
    local fadeTip = UI.Text(right, "muted")
    fadeTip:SetPoint("LEFT", fadeLabel, "RIGHT", 10, 0)
    fadeTip:SetText("(off: it's left as the game shows it)")
    right.values = {}
    for i, spec in ipairs(VALUES) do right.values[i] = NewValueRow(right, spec) end
    local hint = UI.Text(right, "muted")
    hint:SetPoint("BOTTOMLEFT", 0, 34)
    hint:SetPoint("RIGHT")
    hint:SetText("How much of it shows in each case, from 0% (gone) to 100%. Point at a line for what it means.")
    right.remove = UI.Button(right, "Remove from the list", function()
        privateTable.RemoveCustomFrame(selected)
    end)
    right.remove:SetPoint("BOTTOMLEFT", 0, 0)

    w:SetScript("OnShow", Refresh)
    return w
end

function privateTable.ShowFramesWindow()
    window = window or Build()
    window:Show()
    Refresh()
end

function privateTable.FramesWindowShown()
    return window ~= nil and window:IsShown()
 end

function privateTable.ToggleFramesWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        privateTable.ShowFramesWindow()
    end
end

-- Picked frames come and go (picker.lua), and a reset changes every value: drawn again
privateTable.frameListListeners = privateTable.frameListListeners or {}
table.insert(privateTable.frameListListeners, Refresh)
