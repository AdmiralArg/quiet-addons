-- The Quiet Pins window: your notes, each with Pin, Rename and Delete; a box to paste coordinates or a /way line
-- into; a note where you stand; the pin taken off, or kept as a note. /qpin opens and closes it (or a key: Key
-- Bindings, AddOns; or the macro from its settings, for the crossbar). In the look every Quiet addon shares
-- (QuietKit.UI).
--
-- Made for the gamepad cursor as well as the mouse: ordinary frames (the game's gamepad frames are closed to
-- addons), buttons big enough for a thumb, and nothing that needs a hover or a right-click. Typing is only for a
-- paste or a note's new words.
local _, ns = ...

local UI = QuietKit.UI
local C = UI.C

local WIDTH, HEIGHT = 540, 530
local ROWS = 7 -- (notes on a page; Prev and Next, or the mouse wheel, for more)
local ROW_HEIGHT = 38
local ROW_TOP = -204
local CONFIRM_SECONDS = 3

local window
local page = 1
local renaming -- the number of the note whose words the box is changing, or nil
local confirmDelete, confirmUntil = nil, 0 -- a Delete pressed once reads "Sure?" a few seconds

local function Fill(parent, layer, c, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
    return texture
end

-- A flat text box, its edge in the accent while you type
local function Box(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(24)
    box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    Fill(box, "BACKGROUND", { 0, 0, 0 }, 0.35):SetAllPoints()
    local edges = UI.Border(box)
    local function Edge(c)
        for _, edge in ipairs(edges) do edge:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end
    box:SetScript("OnEditFocusGained", function() Edge({ C.accent[1], C.accent[2], C.accent[3], 0.6 }) end)
    box:SetScript("OnEditFocusLost", function() Edge(C.line) end)
    return box
end

-- ---------- what it shows ----------
local function Refresh()
    if not window or not window:IsShown() then return end
    local notes = ns.Notes()
    local pages = math.max(1, math.ceil(#notes / ROWS))
    page = math.max(1, math.min(page, pages))
    if renaming and not ns.ByID(renaming) then renaming = nil end

    local pinned
    for _, note in ipairs(notes) do
        if ns.Pinned(note) then
            pinned = note
            break
        end
    end
    local way = not pinned and ns.WayPinned()
    if pinned then
        window.pinLine:SetText("Pinned: " .. ns.Describe(pinned))
    elseif way then
        window.pinLine:SetText("Pinned from /way, not saved: " .. ns.PlaceText(way))
    elseif ns.Pin() then
        window.pinLine:SetText("Pinned: a place that isn't one of your notes.")
    else
        window.pinLine:SetText("No pin on the map.")
    end
    -- (any pin that isn't a note yet can be kept)
    window.keep:SetShown(not pinned and ns.Pin() ~= nil)

    window.listTitle:SetText(#notes == 0 and "Notes" or ("Notes (" .. #notes .. ")"))
    window.empty:SetShown(#notes == 0)
    window.pageText:SetText(page .. " / " .. pages)
    window.prev:SetEnabled(page > 1)
    window.next:SetEnabled(page < pages)
    for _, part in ipairs({ window.prev, window.next, window.pageText }) do part:SetShown(pages > 1) end

    local now = GetTime()
    for r, row in ipairs(window.rows) do
        local note = notes[(page - 1) * ROWS + r]
        row:SetShown(note ~= nil)
        if note then
            row.id = note.id
            local on = note == pinned
            row.pinned = on
            row.place:SetText(note.id .. ".  " .. ns.MapName(note.map) .. "   " .. ns.Coords(note.x, note.y))
            local c = on and C.accent or C.text
            row.place:SetTextColor(c[1], c[2], c[3])
            row.words:SetText(note.text ~= "" and note.text or "(no words)")
            row.pinnedShade:SetShown(on)
            row.bar:SetShown(on)
            row.pin:SetText(on and "Unpin" or "Pin")
            row.rename:SetText(renaming == note.id and "Cancel" or "Rename")
            row.delete:SetText(confirmDelete == note.id and now < confirmUntil and "Sure?" or "Delete")
        end
    end

    window.pasteLabel:SetText(renaming and ("New words for note " .. renaming .. ", then Save:")
        or "Paste coordinates or a /way line, then Add:")
    window.add:SetText(renaming and "Save" or "Add")
end
ns.RefreshWindow = Refresh

-- The last thing Quiet Pins said, at the bottom of the window
function ns.OnMessage(msg)
    if not window then return end
    window.message:SetText((msg:gsub("^%l", string.upper)))
    Refresh()
end

-- ---------- what it does ----------
local function StopRenaming()
    renaming = nil
    window.box:SetText("")
    window.box:ClearFocus()
end

-- Add (a paste) or Save (a note's new words)
local function Submit()
    local text = window.box:GetText() or ""
    if renaming then
        local id = renaming
        StopRenaming()
        ns.Rename(id, text)
    elseif strtrim(text) == "" then
        ns.OnMessage("paste coordinates into the box first, like 45.2 63.8 Goldshire.")
    else
        page = math.huge -- (a new note is the last)
        -- (a paste that didn't work stays in the box, to be put right)
        if ns.AddAt(text) then
            window.box:SetText("")
            window.box:ClearFocus()
        end
    end
    Refresh()
end

local function OnPin(row)
    if row.pinned then
        ns.ClearPin()
    else
        ns.PinNote(ns.ByID(row.id))
    end
    Refresh()
end

local function OnRename(row)
    local note = ns.ByID(row.id)
    if renaming == row.id or not note then
        StopRenaming()
    else
        renaming = row.id
        window.box:SetText(note.text or "")
        window.box:SetFocus()
        window.box:HighlightText()
    end
    Refresh()
end

-- Delete twice: once more within a few seconds deletes it (a gamepad cursor slips easily)
local function OnDelete(row)
    local id = row.id
    if confirmDelete == id and GetTime() < confirmUntil then
        confirmDelete = nil
        if renaming == id then StopRenaming() end
        ns.Remove(id)
    else
        confirmDelete, confirmUntil = id, GetTime() + CONFIRM_SECONDS
        C_Timer.After(CONFIRM_SECONDS + 0.1, Refresh)
    end
    Refresh()
end

-- ---------- the window ----------
local function Row(parent, r)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 32, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, ROW_TOP - (r - 1) * (ROW_HEIGHT + 2))
    Fill(row, "BACKGROUND", C.raised):SetAllPoints()
    row.pinnedShade = Fill(row, "BORDER", C.accent, 0.12)
    row.pinnedShade:SetAllPoints()
    row.bar = Fill(row, "ARTWORK", C.accent, 0.9)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(2)

    row.delete = UI.Button(row, "Delete", function() OnDelete(row) end, 64)
    row.delete:SetPoint("RIGHT", -6, 0)
    row.rename = UI.Button(row, "Rename", function() OnRename(row) end, 72)
    row.rename:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.pin = UI.Button(row, "Pin", function() OnPin(row) end, 60)
    row.pin:SetPoint("RIGHT", row.rename, "LEFT", -4, 0)

    row.place = UI.Text(row, "body")
    row.place:SetPoint("TOPLEFT", 10, -5)
    row.place:SetPoint("RIGHT", row.pin, "LEFT", -8, 0)
    row.place:SetWordWrap(false)
    row.words = UI.Text(row, "muted")
    row.words:SetPoint("TOPLEFT", row.place, "BOTTOMLEFT", 0, -3)
    row.words:SetPoint("RIGHT", row.pin, "LEFT", -8, 0)
    row.words:SetWordWrap(false)
    return row
end

local function Build()
    -- (the glass, the title, the close button, Escape, dragging and the saved place are QuietKit's)
    local frame = UI.Window("QuietPinsWindow", "Quiet Pins", WIDTH, HEIGHT, ns.DB)

    -- The pin, and Keep for one that isn't a note yet
    frame.keep = UI.Button(frame, "Keep", function()
        page = math.huge
        ns.Keep("")
        Refresh()
    end, 80, true)
    frame.keep:SetPoint("TOPRIGHT", -16, -42)
    frame.pinLine = UI.Text(frame, "body")
    frame.pinLine:SetPoint("LEFT", frame, "TOPLEFT", 16, -54)
    frame.pinLine:SetPoint("RIGHT", frame.keep, "LEFT", -10, 0)
    frame.pinLine:SetJustifyV("MIDDLE")
    frame.pinLine:SetWordWrap(false)

    -- The paste box
    frame.pasteLabel = UI.Text(frame, "heading")
    frame.pasteLabel:SetPoint("TOPLEFT", 16, -76)
    frame.add = UI.Button(frame, "Add", Submit, 80)
    frame.add:SetPoint("TOPRIGHT", -16, -92)
    frame.box = Box(frame)
    frame.box:SetPoint("TOPLEFT", 16, -92)
    frame.box:SetPoint("RIGHT", frame.add, "LEFT", -8, 0)
    frame.box:SetMaxLetters(255)
    frame.box:SetScript("OnEnterPressed", Submit)
    frame.box:SetScript("OnEscapePressed", function()
        if renaming then StopRenaming() else frame.box:ClearFocus() end
        Refresh()
    end)
    local hint = UI.Text(frame, "muted")
    hint:SetPoint("TOPLEFT", 16, -122)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetText("Like 45.2 63.8 Goldshire, or /way Elwynn Forest 42 65 Goldshire. Added notes are pinned at once.")

    -- Buttons that need no typing
    local here = UI.Button(frame, "Add where I stand", function()
        page = math.huge
        ns.AddHere("")
        Refresh()
    end, 160)
    here:SetPoint("TOPLEFT", 16, -142)
    local nextPin = UI.Button(frame, "Pin next", function()
        ns.Next()
        Refresh()
    end, 100)
    nextPin:SetPoint("LEFT", here, "RIGHT", 8, 0)
    local clear = UI.Button(frame, "Clear pin", function()
        ns.ClearPin()
        Refresh()
    end, 100)
    clear:SetPoint("LEFT", nextPin, "RIGHT", 8, 0)

    local divider = Fill(frame, "BORDER", C.line)
    divider:SetPoint("TOPLEFT", 16, -176)
    divider:SetPoint("TOPRIGHT", -16, -176)
    divider:SetHeight(1)

    -- The notes, a page at a time
    frame.listTitle = UI.Text(frame, "heading")
    frame.listTitle:SetPoint("TOPLEFT", 16, -186)
    frame.next = UI.Button(frame, "Next", function()
        page = page + 1
        Refresh()
    end, 56)
    frame.next:SetPoint("TOPRIGHT", -16, -180)
    frame.pageText = UI.Text(frame, "muted")
    frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.pageText:SetWordWrap(false)
    frame.prev = UI.Button(frame, "Prev", function()
        page = page - 1
        Refresh()
    end, 56)
    frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -8, 0)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        page = page - delta
        Refresh()
    end)

    frame.rows = {}
    for r = 1, ROWS do frame.rows[r] = Row(frame, r) end
    frame.empty = UI.Text(frame, "muted")
    frame.empty:SetPoint("TOPLEFT", 16, ROW_TOP - 8)
    frame.empty:SetText("No notes yet. Paste coordinates above, or add one where you stand.")

    frame.message = UI.Text(frame, "small")
    frame.message:SetPoint("BOTTOMLEFT", 16, 14)
    frame.message:SetPoint("RIGHT", -16, 0)
    frame.message:SetJustifyV("BOTTOM")

    -- The pin can change outside the window (the map, another addon)
    frame:SetScript("OnEvent", Refresh)
    for _, event in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnShow", function()
        frame.message:SetText("")
        Refresh()
    end)
    frame:SetScript("OnHide", function()
        if renaming then StopRenaming() end
        frame.box:ClearFocus()
    end)
    return frame
end

function ns.ToggleWindow()
    window = window or Build()
    window:SetShown(not window:IsShown())
end

-- (the key binding's, Bindings.xml)
function QuietPins_ToggleWindow()
    ns.ToggleWindow()
end
BINDING_HEADER_QUIETPINS = "Quiet Pins"
BINDING_NAME_QUIETPINS_TOGGLE = "Open / close the Quiet Pins window"
