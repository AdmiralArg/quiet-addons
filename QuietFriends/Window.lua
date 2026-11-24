-- The Quiet Friends window: your friends, each with Mail (their name in To), Note and Delete, and one box that finds
-- and adds. /qfriends opens and closes it (or a key: Key Bindings, AddOns; or the macro from its settings, for the
-- crossbar). In the look every Quiet addon shares (QuietKit.UI).
--
-- Made for the gamepad cursor as well as the mouse: ordinary frames, buttons big enough for a thumb, nothing that
-- needs a hover or a right-click. Add my target saves a friend without typing.
local _, ns = ...

local UI = QuietKit.UI
local C = UI.C

local WIDTH, HEIGHT = 520, 500
local ROWS = 7 -- (friends on a page; Prev and Next, or the mouse wheel, for more)
local ROW_HEIGHT = 38
local ROW_TOP = -176
local CONFIRM_SECONDS = 3

local window
local page = 1
local editing -- the friend whose note the box is changing, or nil
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

-- What the box narrows the list to: the name part of "Ana Smith, Mia" (nothing while it changes a note)
local function Filter()
    if editing or not window then return "" end
    return ((window.box:GetText() or ""):match("^([^,]*)") or "")
end

-- ---------- what it shows ----------
local function Refresh()
    if not window or not window:IsShown() then return end
    if editing and not ns.ByName(editing.name) then editing = nil end
    local all = ns.Friends()
    local friends = ns.Matching(Filter())
    local pages = math.max(1, math.ceil(#friends / ROWS))
    page = math.max(1, math.min(page, pages))

    if #friends == #all then
        window.listTitle:SetText(#all == 0 and "Friends" or ("Friends (" .. #all .. ")"))
    else
        window.listTitle:SetText("Friends (" .. #friends .. " of " .. #all .. ")")
    end
    window.empty:SetShown(#friends == 0)
    window.empty:SetText(#all == 0
        and "No friends saved yet. Type a name above and press Add, or target a friend and press Add my target."
        or "No name or note has that in it. Add saves it as a new friend.")
    window.pageText:SetText(page .. " / " .. pages)
    window.prev:SetEnabled(page > 1)
    window.next:SetEnabled(page < pages)
    for _, part in ipairs({ window.prev, window.next, window.pageText }) do part:SetShown(pages > 1) end

    local mailOpen = ns.ToBox() ~= nil
    local now = GetTime()
    for r, row in ipairs(window.rows) do
        local friend = friends[(page - 1) * ROWS + r]
        row:SetShown(friend ~= nil)
        if friend then
            row.friend = friend
            row.name:SetText(friend.name)
            row.note:SetText(friend.note ~= "" and friend.note or "(no note)")
            row.mail:SetEnabled(mailOpen)
            row.edit:SetText(editing == friend and "Cancel" or "Note")
            row.delete:SetText(confirmDelete == friend and now < confirmUntil and "Sure?" or "Delete")
        end
    end

    window.boxLabel:SetText(editing and ("New note for " .. editing.name .. ", then Save:")
        or "Find or add a friend: their name, then a note after a comma if you like")
    window.add:SetText(editing and "Save" or "Add")
    window.target:SetEnabled(ns.UnitFull("target") ~= nil)
end
ns.RefreshWindow = Refresh

function ns.RefreshAll()
    Refresh()
    if ns.RefreshMail then ns.RefreshMail() end
end

-- The last thing Quiet Friends said, at the bottom of the window
function ns.OnMessage(msg)
    if not window then return end
    window.message:SetText((msg:gsub("^%l", string.upper)))
    Refresh()
end

-- ---------- what it does ----------
local function StopEditing()
    editing = nil
    window.box:SetText("")
    window.box:ClearFocus()
end

-- Add (a name, and a note) or Save (a friend's new note)
local function Submit()
    local text = window.box:GetText() or ""
    if editing then
        local friend = editing
        StopEditing()
        ns.SetNote(friend, text)
    elseif strtrim(text) == "" then
        ns.OnMessage("type a name into the box first, like Ana Smith, Mia.")
    else
        local name, note = text:match("^([^,]*),?(.*)$")
        -- (a name that didn't do stays in the box, to be put right)
        if ns.Add(name, note) then
            window.box:SetText("")
            window.box:ClearFocus()
        end
    end
    Refresh()
end

local function OnMail(row)
    if ns.MailTo(row.friend) then
        window.message:SetText(row.friend.name .. " is in To.")
    end
end

local function OnEdit(row)
    if editing == row.friend then
        StopEditing()
    else
        editing = row.friend
        window.box:SetText(row.friend.note or "")
        window.box:SetFocus()
        window.box:HighlightText()
    end
    Refresh()
end

-- Delete twice: once more within a few seconds deletes it (a gamepad cursor slips easily)
local function OnDelete(row)
    local friend = row.friend
    if confirmDelete == friend and GetTime() < confirmUntil then
        confirmDelete = nil
        if editing == friend then StopEditing() end
        ns.Remove(friend)
    else
        confirmDelete, confirmUntil = friend, GetTime() + CONFIRM_SECONDS
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

    row.delete = UI.Button(row, "Delete", function() OnDelete(row) end, 64)
    row.delete:SetPoint("RIGHT", -6, 0)
    row.edit = UI.Button(row, "Note", function() OnEdit(row) end, 64)
    row.edit:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.mail = UI.Button(row, "Mail", function() OnMail(row) end, 60, true)
    row.mail:SetPoint("RIGHT", row.edit, "LEFT", -4, 0)

    row.name = UI.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 10, -5)
    row.name:SetPoint("RIGHT", row.mail, "LEFT", -8, 0)
    row.name:SetWordWrap(false)
    row.note = UI.Text(row, "muted")
    row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.note:SetPoint("RIGHT", row.mail, "LEFT", -8, 0)
    row.note:SetWordWrap(false)
    return row
end

local function Build()
    -- (the glass, the title, the close button, Escape, dragging and the saved place are QuietKit's)
    local frame = UI.Window("QuietFriendsWindow", "Quiet Friends", WIDTH, HEIGHT, ns.DB)

    -- The box: what's typed narrows the list; Add saves it
    frame.boxLabel = UI.Text(frame, "heading")
    frame.boxLabel:SetPoint("TOPLEFT", 16, -46)
    frame.boxLabel:SetPoint("RIGHT", -16, 0)
    frame.add = UI.Button(frame, "Add", Submit, 80, true)
    frame.add:SetPoint("TOPRIGHT", -16, -64)
    frame.box = Box(frame)
    frame.box:SetPoint("TOPLEFT", 16, -64)
    frame.box:SetPoint("RIGHT", frame.add, "LEFT", -8, 0)
    frame.box:SetMaxLetters(140)
    frame.box:SetScript("OnEnterPressed", Submit)
    frame.box:SetScript("OnEscapePressed", function()
        if editing then StopEditing() else frame.box:ClearFocus() end
        Refresh()
    end)
    frame.box:SetScript("OnTextChanged", function(_, typed)
        if typed and not editing then
            page = 1
            Refresh()
        end
    end)
    local hint = UI.Text(frame, "muted")
    hint:SetPoint("TOPLEFT", 16, -94)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetText("Like Ana Smith, Mia. On WoW Forever a letter needs both names, first name and surname.")

    -- Buttons that need no typing
    frame.target = UI.Button(frame, "Add my target", function()
        ns.AddTarget("")
        Refresh()
    end, 140)
    frame.target:SetPoint("TOPLEFT", 16, -114)
    local clear = UI.Button(frame, "Show all", function()
        if editing then StopEditing() end
        frame.box:SetText("")
        frame.box:ClearFocus()
        Refresh()
    end, 100)
    clear:SetPoint("LEFT", frame.target, "RIGHT", 8, 0)

    local divider = Fill(frame, "BORDER", C.line)
    divider:SetPoint("TOPLEFT", 16, -148)
    divider:SetPoint("TOPRIGHT", -16, -148)
    divider:SetHeight(1)

    -- The friends, a page at a time
    frame.listTitle = UI.Text(frame, "heading")
    frame.listTitle:SetPoint("TOPLEFT", 16, -158)
    frame.next = UI.Button(frame, "Next", function()
        page = page + 1
        Refresh()
    end, 56)
    frame.next:SetPoint("TOPRIGHT", -16, -152)
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
    frame.empty:SetPoint("RIGHT", -16, 0)

    frame.message = UI.Text(frame, "small")
    frame.message:SetPoint("BOTTOMLEFT", 16, 14)
    frame.message:SetPoint("RIGHT", -16, 0)
    frame.message:SetJustifyV("BOTTOM")

    -- Mail opens and closes, the target changes: the buttons follow
    frame:SetScript("OnEvent", Refresh)
    for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_TARGET_CHANGED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnShow", function()
        frame.message:SetText("")
        Refresh()
    end)
    frame:SetScript("OnHide", function()
        if editing then StopEditing() end
        frame.box:ClearFocus()
    end)
    return frame
end

function ns.ToggleWindow()
    window = window or Build()
    window:SetShown(not window:IsShown())
end

-- (the key binding's, Bindings.xml)
function QuietFriends_ToggleWindow()
    ns.ToggleWindow()
end
BINDING_HEADER_QUIETFRIENDS = "Quiet Friends"
BINDING_NAME_QUIETFRIENDS_TOGGLE = "Open / close the Quiet Friends list"
