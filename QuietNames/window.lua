local addonName, privateTable = ...

-- The Quiet Names window: names as the game draws them over heads, in the font you pick, and every font you can pick,
-- each written in itself. The game takes a new choice when it's started again. /qnames fonts, or the settings page.

local UI = QuietKit.UI
local C = UI.C

local WIDTH, HEIGHT = 440, 520
local PREVIEW_SIZE = 18
local ROW_HEIGHT = 24

local window

-- A font in the list: its name in itself, a soft highlight on hover, the accent while chosen. Or a heading.
local function Row(list, i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], C.hover[4])
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetAllPoints()
    row.lit:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.14)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(2)
    row.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 12, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.key then privateTable.SetFont(self.key) end
    end)
    list.rows[i] = row
    return row
end

local function FillList(w)
    local list = w.list
    local chosen = privateTable.Chosen()
    local n = 0
    local addons = false
    for _, font in ipairs(privateTable.Fonts()) do
        if font.from == "addons" and not addons then
            addons = true
            n = n + 1
            local head = Row(list, n)
            head.key = nil
            head:EnableMouse(false)
            head.lit:Hide()
            head.bar:Hide()
            head.text:SetFont(GameFontNormalSmall:GetFont())
            head.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            head.text:SetText("From your other addons")
            head:Show()
        end
        n = n + 1
        local row = Row(list, n)
        row.key = font.key
        row:EnableMouse(true)
        local on = font.key == chosen
        row.lit:SetShown(on)
        row.bar:SetShown(on)
        -- (a font that won't load keeps the plain one)
        row.text:SetFont(GameFontHighlight:GetFont())
        pcall(row.text.SetFont, row.text, font.path, 15, "")
        local color = on and C.title or C.text
        row.text:SetTextColor(color[1], color[2], color[3])
        row.text:SetText(font.label)
        row:Show()
    end
    for i = n + 1, #list.rows do list.rows[i]:Hide() end
    list:SetHeight(math.max(1, n * ROW_HEIGHT))
    local most = math.max(0, n * ROW_HEIGHT - w.scroll:GetHeight())
    w.bar:SetMinMaxValues(0, most)
    w.bar:SetShown(most > 0)
    if most > 0 then
        w.bar.thumb:SetHeight(math.max(20, w.scroll:GetHeight() * w.scroll:GetHeight() / (n * ROW_HEIGHT)))
    end
    if w.scroll:GetVerticalScroll() > most then w.bar:SetValue(most) end
end

local function BuildWindow()
    local w = UI.Window("QuietNamesWindow", "Quiet Names", WIDTH, HEIGHT)
    local body = w.body

    -- Preview: names as the game draws them over heads, in the chosen font
    local preview = CreateFrame("Frame", nil, body)
    preview:SetPoint("TOPLEFT")
    preview:SetPoint("TOPRIGHT")
    preview:SetHeight(110)
    local previewBackground = preview:CreateTexture(nil, "BACKGROUND")
    previewBackground:SetAllPoints()
    previewBackground:SetColorTexture(0.12, 0.08, 0.16, 0.95)
    UI.Border(preview)

    local npcName = preview:CreateFontString(nil, "OVERLAY")
    npcName:SetPoint("TOP", preview, "TOP", -70, -16)
    local npcTitle = preview:CreateFontString(nil, "OVERLAY")
    npcTitle:SetPoint("TOP", npcName, "BOTTOM", 0, -2)
    local playerName = preview:CreateFontString(nil, "OVERLAY")
    playerName:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -16, 16)
    w.previewLines = {
        { text = npcName, value = "Jannok Breezesong", color = { 0.1, 1.0, 0.1 } },
        { text = npcTitle, value = "<Rogue Trainer>", color = { 0.1, 1.0, 0.1 } },
        { text = playerName, value = "<Away>Elowen Velyssar", color = { 0.6, 0.6, 1.0 } },
    }

    local previewNote = UI.Text(body, "muted")
    previewNote:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -6)
    previewNote:SetPoint("RIGHT", body, "RIGHT")
    previewNote:SetText("A preview. In the world, names are larger up close and smaller far away; the game sets "
        .. "their size, not the font.")

    -- The fonts, each written in itself, with a thin scrollbar when there are more than fit
    local heading = UI.Text(body, "heading")
    heading:SetPoint("TOPLEFT", previewNote, "BOTTOMLEFT", 0, -14)
    heading:SetText("Fonts")

    w.status = UI.Text(body, "small")
    w.status:SetPoint("BOTTOMLEFT")
    w.status:SetPoint("BOTTOMRIGHT")

    local scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    scroll:SetPoint("BOTTOM", w.status, "TOP", 0, 12)
    w.scroll = scroll
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(WIDTH - 44, 1)
    list.rows = {}
    scroll:SetScrollChild(list)
    w.list = list

    local bar = CreateFrame("Slider", nil, body)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.06)
    bar.thumb = bar:CreateTexture(nil, "OVERLAY")
    bar.thumb:SetSize(6, 40)
    bar.thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    bar:SetThumbTexture(bar.thumb)
    bar:SetValueStep(1)
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    w.bar = bar
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local _, most = bar:GetMinMaxValues()
        bar:SetValue(math.max(0, math.min(most, bar:GetValue() - delta * ROW_HEIGHT * 2)))
    end)

    w:SetScript("OnShow", function() C_Timer.After(0, privateTable.RefreshWindow) end)
    return w
end

--- Redraws the window from the saved choice (called on every change, here or on the settings page)
function privateTable.RefreshWindow()
    if not window or not window:IsShown() or not QuietNamesDB then return end
    local path = privateTable.PathOf((privateTable.Chosen()))
    for _, line in ipairs(window.previewLines) do
        line.text:SetFont(path, PREVIEW_SIZE, "")
        line.text:SetShadowOffset(1, -1)
        line.text:SetShadowColor(0, 0, 0, 1)
        line.text:SetTextColor(line.color[1], line.color[2], line.color[3])
        line.text:SetText(line.value)
    end
    FillList(window)
    if privateTable.changed then
        window.status:SetText("|cffffd24aExit the game and start it again to see this in the world.|r "
            .. "The game sets the name font as it starts; a /reload doesn't change it.")
    else
        window.status:SetText("The game sets the name font as it starts: a new choice shows after you exit and "
            .. "start the game again.")
    end
end

function privateTable.ToggleWindow()
    window = window or BuildWindow()
    window:SetShown(not window:IsShown())
end
