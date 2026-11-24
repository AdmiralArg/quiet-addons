-- The Quiet Bags window: your other characters down the left, and you last (your own bank, away from it). Pick one
-- to see what it carries as squares, like the game's own bags: its bags, then its bank, then its mail, each under a
-- small heading that says when it was last seen. A search box dims what doesn't match. /qbags opens and closes it
-- (or its macro, for a bar or the crossbar: the settings page has it; a key: Key Bindings, AddOns; or the round
-- button on the game's bag window). It wears QuietKit's look (QuietKit.UI), as every Quiet addon's windows do.
--
-- Made for the gamepad cursor as well as the mouse: ordinary frames (the game's gamepad frames are closed to
-- addons), squares and buttons big enough for a thumb, Up and Down buttons as well as the mouse wheel, and nothing
-- that needs a right-click. Pointing at a square shows the item's tooltip.
local _, ns = ...
local UI = QuietKit.UI
local C = UI.C

local LEFT = 168 -- (where the squares start; the characters are left of it)
local SIZE, GAP = 37, 4 -- (a square, as in the game's own bags, and the space between)
local COLUMNS = 10
local WIDTH, HEIGHT = LEFT + COLUMNS * (SIZE + GAP) - GAP + 16, 560
local CHAR_BUTTONS = 12
local GRID_TOP = -104
local GRID_BOTTOM = 50 -- (room under the squares for Up and Down)
local VIEW = HEIGHT + GRID_TOP - GRID_BOTTOM
local HEADING = 22
local STEP = 4 * (SIZE + GAP) -- (how far Up and Down move)
local BUTTON_HEIGHT = 26
local PLACES = { { "bags", "Bags" }, { "bank", "Bank" }, { "mail", "Mail" } }

local window
local scroll, maxScroll = 0, 0
local selected -- the character shown (its "Name-Realm")

local function Button(parent, text, width, onClick)
    local button = UI.Button(parent, text, onClick, width)
    button:SetHeight(BUTTON_HEIGHT)
    return button
end

local function Line(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

-- A character's button: lit, with a mark in the accent at its left edge, while it's the one shown (as QuietKit's
-- settings pages mark theirs)
local function CharButton(parent, onClick)
    local button = Button(parent, "", LEFT - 32, onClick)
    button.lit = Line(button, "BORDER", C.accent[1], C.accent[2], C.accent[3], 0.16)
    button.lit:SetAllPoints()
    button.mark = Line(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    button.mark:SetPoint("TOPLEFT")
    button.mark:SetPoint("BOTTOMLEFT")
    button.mark:SetWidth(2)
    function button.SetChosen(on)
        button.lit:SetShown(on)
        button.mark:SetShown(on)
    end
    return button
end

-- The others, then you last (your own bank, to look at away from it)
local function Listed()
    local chars = ns.Characters()
    local me = ns.MyKey()
    local mine = me and ns.Chars()[me]
    if mine then chars[#chars + 1] = { key = me, char = mine, label = ns.Label(me, mine) .. " (you)" } end
    return chars
end

-- A quality's colour, or nil
local function QualityColour(quality)
    local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if type(colour) == "table" and colour.r then return colour.r, colour.g, colour.b end
    local QualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    local ok, r, g, b = pcall(QualityColor or error, quality)
    if ok and type(r) == "number" then return r, g, b end
end

-- What's in one place, like with like (the game's item classes), then by name
local function PlaceItems(char, where)
    local section = char[where]
    local list = {}
    for id, item in pairs(section and section.items or {}) do list[#list + 1] = ns.Describe(id, item) end
    table.sort(list, function(a, b)
        if a.classID ~= b.classID then return a.classID < b.classID end
        if a.subclassID ~= b.subclassID then return a.subclassID < b.subclassID end
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return list
end

-- The words after a heading: "30 kinds, seen 2 h ago"
local function Note(char, where, kinds)
    local section = char[where]
    if not (section and section.at) then
        if where == "bank" then return "open the bank once on " .. (char.name or "them") end
        if where == "mail" then return "open the mailbox once on " .. (char.name or "them") end
        return "not seen yet"
    end
    local seen = "seen " .. ns.Ago(section.at)
    if kinds == 0 then return "empty, " .. seen end
    return kinds .. (kinds == 1 and " kind, " or " kinds, ") .. seen
end

-- ---------- scrolling ----------
local function ScrollTo(value)
    scroll = math.max(0, math.min(value, maxScroll))
    window.scroller:SetVerticalScroll(scroll)
    window.up:SetShown(maxScroll > 0)
    window.down:SetShown(maxScroll > 0)
    window.up:SetEnabled(scroll > 0)
    window.down:SetEnabled(scroll < maxScroll)
end

-- ---------- a square ----------
-- (pointing at it shows the item, and where it is)
local function ShowItem(square)
    GameTooltip:SetOwner(square, "ANCHOR_RIGHT")
    local shown = false
    if square.link then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, square.link) end
    if not shown then pcall(GameTooltip.SetItemByID, GameTooltip, square.id) end
    GameTooltip:AddLine(square.whereText, 1, 0.82, 0)
    GameTooltip:Show()
end

local function NewSquare(parent)
    local square = CreateFrame("Button", nil, parent)
    square:SetSize(SIZE, SIZE)
    square.border = Line(square, "BACKGROUND", 1, 1, 1, 0.12)
    square.border:SetAllPoints()
    square.icon = square:CreateTexture(nil, "ARTWORK")
    square.icon:SetPoint("TOPLEFT", 2, -2)
    square.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    square.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    square.count = square:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    square.count:SetPoint("BOTTOMRIGHT", -3, 3)
    square:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    square:SetScript("OnEnter", ShowItem)
    square:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return square
end

local function Fill(square, item, where, match)
    square.id, square.link = item.id, item.link
    square.whereText = "In the " .. where .. ": " .. item.count
    square.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    square.count:SetText(item.count > 1 and item.count or "")
    -- (a thin edge in the quality's colour, uncommon and better)
    local r, g, b
    if (item.quality or 0) >= 2 then r, g, b = QualityColour(item.quality) end
    if r then square.border:SetColorTexture(r, g, b, 0.9) else square.border:SetColorTexture(1, 1, 1, 0.12) end
    -- (what the search doesn't match is dimmed, as in the game's own bags)
    square.icon:SetDesaturated(not match)
    square:SetAlpha(match and 1 or 0.25)
    square:Show()
end

-- ---------- what it shows ----------
local function Refresh()
    if not window or not window:IsShown() then return end
    local chars = Listed()
    local db = ns.DB()
    -- (the character last picked, kept between sessions; the first in the list until one is picked, or while the
    -- one picked is of the other faction or realm, which stays remembered for when you're back on that side)
    selected = selected or db.selected
    local listed = false
    for _, entry in ipairs(chars) do
        if entry.key == selected then listed = true end
    end
    if not listed then selected = chars[1] and chars[1].key end

    for i, button in ipairs(window.charButtons) do
        local entry = chars[i]
        button:SetShown(entry ~= nil)
        if entry then
            button.key = entry.key
            button:SetText(entry.label)
            button.SetChosen(entry.key == selected)
        end
    end
    window.noChars:SetShown(#chars <= 1)

    for _, square in ipairs(window.squares) do square:Hide() end
    for _, heading in ipairs(window.headings) do heading:Hide() end
    local char = selected and ns.Chars()[selected]
    if not char then
        window.who:SetText("")
        maxScroll = 0
        ScrollTo(0)
        return
    end

    -- Bags, then bank, then mail: a heading, then the squares, ten to a row
    local query = strtrim(window.box:GetText() or ""):lower()
    local y, used, kinds, matched = 0, 0, {}, {}
    for p, place in ipairs(PLACES) do
        local where = place[1]
        local list = PlaceItems(char, where)
        local heading = window.headings[p]
        heading:SetPoint("TOPLEFT", 0, -y)
        heading:SetText(place[2] .. "   |cff8f8f94" .. Note(char, where, #list) .. "|r")
        heading:Show()
        y = y + HEADING
        for i, item in ipairs(list) do
            used = used + 1
            local square = window.squares[used] or NewSquare(window.child)
            window.squares[used] = square
            square:ClearAllPoints()
            square:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * (SIZE + GAP), -(y + math.floor((i - 1) / COLUMNS) * (SIZE + GAP)))
            local match = query == "" or item.name:lower():find(query, 1, true) ~= nil
            Fill(square, item, where, match)
            kinds[item.id] = true
            if match then matched[item.id] = true end
        end
        y = y + math.ceil(#list / COLUMNS) * (SIZE + GAP) + 10
    end

    local total, found = 0, 0
    for _ in pairs(kinds) do total = total + 1 end
    for _ in pairs(matched) do found = found + 1 end
    local count = query ~= "" and (found .. " of " .. total .. " match")
        or (total .. (total == 1 and " kind of item" or " kinds of item"))
    window.who:SetText(ns.Label(selected, char) .. "  |cff8f8f94(" .. count .. ")|r")

    window.child:SetHeight(math.max(y, 1))
    maxScroll = math.max(0, y - VIEW)
    ScrollTo(scroll)
end
ns.RefreshWindow = Refresh

local function Pick(key)
    selected = key
    ns.DB().selected = key
    scroll = 0
    Refresh()
end

-- ---------- the window ----------
local function Build()
    -- QuietKit's window: the glass, the title, a close button, dragged to move (its place kept), closed with Escape
    local db = ns.DB()
    if type(db.window) == "table" and db.window.point and not db.pos then
        -- (its place as it was kept before the kit kept it)
        db.pos = { db.window.point, db.window.x or 0, db.window.y or 0 }
    end
    db.window = nil
    local frame = UI.Window("QuietBagsWindow", "Quiet Bags", WIDTH, HEIGHT, ns.DB)

    -- The characters, down the left
    local charsTitle = UI.Text(frame, "muted")
    charsTitle:SetPoint("TOPLEFT", 16, -44)
    charsTitle:SetText("Characters")
    frame.charButtons = {}
    for i = 1, CHAR_BUTTONS do
        local button = CharButton(frame, function(self) Pick(self.key) end)
        button:SetPoint("TOPLEFT", 16, -60 - (i - 1) * (BUTTON_HEIGHT + 4))
        frame.charButtons[i] = button
    end
    -- (under your own button, the only one then)
    frame.noChars = UI.Text(frame, "muted")
    frame.noChars:SetPoint("TOPLEFT", 16, -60 - (BUTTON_HEIGHT + 4) - 6)
    frame.noChars:SetWidth(LEFT - 32)
    frame.noChars:SetText("No other characters yet. Log in once on each one with Quiet Bags turned on.")

    local divider = Line(frame, "BORDER", C.line[1], C.line[2], C.line[3], C.line[4])
    divider:SetPoint("TOPLEFT", LEFT - 10, -40)
    divider:SetPoint("BOTTOMLEFT", LEFT - 10, 16)
    divider:SetWidth(1)

    -- Whose, and how many kinds of item
    frame.who = UI.Text(frame, "heading")
    frame.who:SetPoint("TOPLEFT", LEFT, -44)
    frame.who:SetPoint("RIGHT", -16, 0)
    frame.who:SetWordWrap(false)

    -- The search box: a flat field in the kit's look (raised, a hairline edge)
    local clear = Button(frame, "Clear", 64, function()
        frame.box:SetText("")
        frame.box:ClearFocus()
    end)
    clear:SetPoint("TOPRIGHT", -16, -64)
    local searchLabel = UI.Text(frame, "muted")
    searchLabel:SetPoint("TOPLEFT", LEFT, -71)
    searchLabel:SetText("Search")
    frame.box = CreateFrame("EditBox", nil, frame)
    frame.box:SetFontObject("GameFontHighlight")
    frame.box:SetTextInsets(8, 8, 0, 0)
    Line(frame.box, "BACKGROUND", C.raised[1], C.raised[2], C.raised[3], C.raised[4]):SetAllPoints()
    UI.Border(frame.box)
    frame.box:SetHeight(BUTTON_HEIGHT)
    frame.box:SetPoint("TOPLEFT", searchLabel, "TOPRIGHT", 12, 7)
    frame.box:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    frame.box:SetAutoFocus(false)
    frame.box:SetMaxLetters(60)
    frame.box:SetScript("OnTextChanged", Refresh)
    frame.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- The squares, in a frame that scrolls when they're more than fit
    frame.scroller = CreateFrame("ScrollFrame", nil, frame)
    frame.scroller:SetPoint("TOPLEFT", LEFT, GRID_TOP)
    frame.scroller:SetPoint("BOTTOMRIGHT", -16, GRID_BOTTOM)
    frame.child = CreateFrame("Frame", nil, frame.scroller)
    frame.child:SetSize(COLUMNS * (SIZE + GAP), 1)
    frame.scroller:SetScrollChild(frame.child)
    frame.scroller:EnableMouseWheel(true)
    frame.scroller:SetScript("OnMouseWheel", function(_, delta) ScrollTo(scroll - delta * 2 * (SIZE + GAP)) end)
    frame.squares, frame.headings = {}, {}
    for p = 1, #PLACES do
        local heading = UI.Text(frame.child, "heading", "OVERLAY")
        heading:SetWordWrap(false)
        frame.headings[p] = heading
    end

    frame.down = Button(frame, "Down", 64, function() ScrollTo(scroll + STEP) end)
    frame.down:SetPoint("BOTTOMRIGHT", -16, 14)
    frame.up = Button(frame, "Up", 64, function() ScrollTo(scroll - STEP) end)
    frame.up:SetPoint("RIGHT", frame.down, "LEFT", -8, 0)

    frame:SetScript("OnShow", Refresh)
    frame:SetScript("OnHide", function() frame.box:ClearFocus() end)
    return frame
end

function ns.ToggleWindow()
    window = window or Build()
    window:SetShown(not window:IsShown())
end

-- /qbags <name>: open on that character
function ns.ShowCharacter(name)
    name = (name or ""):lower()
    for _, entry in ipairs(Listed()) do
        if entry.key:lower() == name or entry.label:lower() == name or (entry.char.name or ""):lower() == name then
            window = window or Build()
            window:Show()
            Pick(entry.key)
            return
        end
    end
    ns.Print("no one by that name. /qbags help for the commands.")
end


-- ---------- a button on the game's own bags ----------
-- A small round button on the bag window (the combined bags, or the backpack when the bags are apart) that opens
-- and closes this window. Our own button on top of the game's frame: nothing of the game's is changed, only its
-- showing is listened to. It's for the mouse: the gamepad opens the window with the macro on the settings page (put
-- on the crossbar) or the key in Key Bindings, AddOns. The settings can turn it off (DB().bagButton false).
local BAG_BUTTON_SIZE = 31
local bagButtonUpdates = {} -- (each button's Update, for the settings' switch)

-- The bag window's portrait, whichever way this client names it
local function Portrait(frame)
    local name = frame:GetName()
    return frame.PortraitContainer or frame.portrait or frame.Portrait or frame.PortraitButton
        or (name and (_G[name .. "Portrait"] or _G[name .. "PortraitButton"]))
end

-- Just left of the search box when the box is on this window (it's shared, and moves to whichever bag window is
-- open), so it sits over the portrait's lower right; else on that corner of the portrait itself
local function Place(button, frame)
    button:ClearAllPoints()
    local box = BagItemSearchBox
    local onFrame = box and box:IsShown() and box:GetParent() == frame
    local portrait = Portrait(frame)
    if onFrame then
        button:SetPoint("RIGHT", box, "LEFT", -8, 0)
    elseif portrait then
        button:SetPoint("CENTER", portrait, "BOTTOMRIGHT", -8, 8)
    else
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    end
end

-- The backpack's window (the bags apart): a bag window shows one bag, and the backpack is bag 0
local function IsBackpack(frame)
    local ok, id = pcall(function() return frame.GetBagID and frame:GetBagID() or frame:GetID() end)
    return ok and id == 0
end

local function BagButton(frame, onlyBackpack)
    -- The bag window's own child, above its other parts. (It was once put on the screen itself, pinned to the bag
    -- window, so Forever's gamepad cursor wouldn't stop on it; but there the bag window's parts could cover it, and
    -- it couldn't be clicked. The player uses the mouse now, so it's back on the window.)
    local button = CreateFrame("Button", nil, frame)
    button:Hide()
    button:SetSize(BAG_BUTTON_SIZE, BAG_BUTTON_SIZE)
    -- (the round look of the minimap's buttons)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function() ns.ToggleWindow() end)
    -- (a hover only says what it is)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Quiet Bags")
        GameTooltip:AddLine("What your other characters carry.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function Update()
        if not frame:IsShown() or (onlyBackpack and not IsBackpack(frame)) or ns.DB().bagButton == false then
            button:Hide()
            return
        end
        -- (above the window's own parts: its portrait and search box)
        button:SetFrameLevel(frame:GetFrameLevel() + 20)
        Place(button, frame)
        button:Show()
    end
    frame:HookScript("OnShow", function()
        Update()
        -- (and once more next frame: the game moves the search box over after showing the window)
        C_Timer.After(0, Update)
    end)
    frame:HookScript("OnHide", function() button:Hide() end)
    if frame:IsShown() then Update() end
    bagButtonUpdates[#bagButtonUpdates + 1] = Update
end

-- The settings page's switch for the round button: shown or hidden at once on the bag windows open now
function ns.UpdateBagButtons()
    for _, update in ipairs(bagButtonUpdates) do pcall(update) end
end

local bagButtons = CreateFrame("Frame")
bagButtons:RegisterEvent("PLAYER_LOGIN")
bagButtons:SetScript("OnEvent", function()
    if ContainerFrameCombinedBags then pcall(BagButton, ContainerFrameCombinedBags, false) end
    -- (bags apart: the backpack is usually the first window, but the game hands them out as bags open)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then pcall(BagButton, frame, true) end
    end
end)

-- (the key binding's, Bindings.xml)
function QuietBags_ToggleWindow()
    ns.ToggleWindow()
end
BINDING_HEADER_QUIETBAGS = "Quiet Bags"
BINDING_NAME_QUIETBAGS_TOGGLE = "Open / close the Quiet Bags window"
