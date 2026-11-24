-- Beside the mail: while you write a letter (the Send Mail tab), your friends are listed to the right of the mailbox,
-- narrowed by what you type in To (a name, or a note: "kari"). A click puts the full name in To and the cursor goes
-- on to the subject. A name typed in To that isn't on your list can be saved from here.
--
-- The panel is a child of the game's SendMailFrame, so it comes and goes with the Send Mail tab. Nothing of the
-- game's is changed: the To box is only read, hooked (HookScript) and filled with SetText, as typing would.
local _, ns = ...

local UI = QuietKit.UI
local C = UI.C

local WIDTH = 230
local ROWS = 10
local ROW_HEIGHT = 32
local TOP = -34

local panel
local page = 1

local function Fill(parent, layer, c, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
    return texture
end

local function Typed()
    local box = SendMailNameEditBox
    return box and strtrim(box:GetText() or "") or ""
end

local function Refresh()
    if not panel then return end
    panel:SetShown(ns.DB().mailPanel ~= false)
    if not panel:IsVisible() then return end
    local typed = Typed()
    local all = ns.Friends()
    local friends = ns.Matching(typed)
    -- (a name already complete in To still shows everyone it matches; nothing matching shows them all again)
    local narrowed = typed ~= "" and #friends > 0
    if typed ~= "" and #friends == 0 then friends = all end
    local pages = math.max(1, math.ceil(#friends / ROWS))
    page = math.max(1, math.min(page, pages))

    panel.title:SetText(narrowed and #friends < #all and ("Friends (" .. #friends .. " of " .. #all .. ")")
        or "Friends")
    panel.empty:SetShown(#all == 0)
    local current = ns.ByName(typed)
    for r, row in ipairs(panel.rows) do
        local friend = friends[(page - 1) * ROWS + r]
        row:SetShown(friend ~= nil)
        if friend then
            row.friend = friend
            row.name:SetText(friend.name)
            row.note:SetText(friend.note)
            local on = friend == current
            row.shade:SetShown(on)
            local c = on and C.accent or C.text
            row.name:SetTextColor(c[1], c[2], c[3])
        end
    end

    panel.pageText:SetText(page .. " / " .. pages)
    panel.prev:SetEnabled(page > 1)
    panel.next:SetEnabled(page < pages)
    for _, part in ipairs({ panel.prev, panel.next, panel.pageText }) do part:SetShown(pages > 1) end

    -- A full name in To (both parts: not a few letters typed to look a friend up) that isn't a friend yet can be kept
    local name = ns.CleanName(typed)
    local canSave = name:find(" ", 1, true) ~= nil and not current
    panel.save:SetShown(canSave)
    if canSave then panel.save:SetText("Save " .. name) end
end
ns.RefreshMail = Refresh

local function Row(parent, r)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 20, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10, TOP - (r - 1) * (ROW_HEIGHT + 2))
    Fill(row, "BACKGROUND", C.raised):SetAllPoints()
    row.shade = Fill(row, "BORDER", C.accent, 0.14)
    row.shade:SetAllPoints()
    Fill(row, "HIGHLIGHT", C.hover):SetAllPoints()
    row.name = UI.Text(row, "small")
    row.name:SetPoint("TOPLEFT", 8, -4)
    row.name:SetPoint("RIGHT", -8, 0)
    row.name:SetWordWrap(false)
    row.note = UI.Text(row, "muted")
    row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.note:SetPoint("RIGHT", -8, 0)
    row.note:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.friend then ns.MailTo(self.friend) end
        Refresh()
    end)
    return row
end

local function Build()
    local parent = SendMailFrame or MailFrame
    if not (parent and MailFrame and SendMailNameEditBox) then return nil end
    local frame = CreateFrame("Frame", "QuietFriendsMailPanel", parent)
    frame:SetSize(WIDTH, -TOP + ROWS * (ROW_HEIGHT + 2) + 40)
    frame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
    frame:SetFrameStrata(MailFrame:GetFrameStrata())
    frame:EnableMouse(true)
    UI.Panel(frame)

    frame.title = UI.Text(frame, "heading")
    frame.title:SetPoint("TOPLEFT", 10, -12)
    frame.title:SetWordWrap(false)
    local list = UI.Button(frame, "List", function()
        if ns.ToggleWindow then ns.ToggleWindow() end
    end, 56)
    list:SetHeight(20)
    list:SetPoint("TOPRIGHT", -10, -8)
    frame.title:SetPoint("RIGHT", list, "LEFT", -6, 0)

    frame.rows = {}
    for r = 1, ROWS do frame.rows[r] = Row(frame, r) end
    frame.empty = UI.Text(frame, "muted")
    frame.empty:SetPoint("TOPLEFT", 10, TOP - 4)
    frame.empty:SetPoint("RIGHT", -10, 0)
    frame.empty:SetText("No friends saved yet. Type a full name in To (Ana Smith) and press Save below, "
        .. "or /qfriends.")

    frame.save = UI.Button(frame, "Save", function()
        if ns.Add(Typed(), "") then Refresh() end
    end, WIDTH - 20, true)
    frame.save:SetPoint("BOTTOMLEFT", 10, 10)
    frame.save:GetFontString():SetWidth(WIDTH - 36)
    frame.save:GetFontString():SetWordWrap(false)

    frame.next = UI.Button(frame, ">", function()
        page = page + 1
        Refresh()
    end, 32)
    frame.next:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.pageText = UI.Text(frame, "muted")
    frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.pageText:SetWordWrap(false)
    frame.prev = UI.Button(frame, "<", function()
        page = page - 1
        Refresh()
    end, 32)
    frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -8, 0)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        page = page - delta
        Refresh()
    end)

    -- (the Save button and the pages share the bottom: with a name to save, the pages move above it)
    frame.save:HookScript("OnShow", function()
        frame.next:ClearAllPoints()
        frame.next:SetPoint("BOTTOMRIGHT", frame.save, "TOPRIGHT", 0, 4)
    end)
    frame.save:HookScript("OnHide", function()
        frame.next:ClearAllPoints()
        frame.next:SetPoint("BOTTOMRIGHT", -10, 10)
    end)

    frame:SetScript("OnShow", function()
        page = 1
        Refresh()
    end)
    SendMailNameEditBox:HookScript("OnTextChanged", function()
        page = 1
        Refresh()
    end)
    -- (the window's Mail buttons work only on the Send Mail tab)
    if SendMailFrame then
        SendMailFrame:HookScript("OnShow", function() if ns.RefreshWindow then ns.RefreshWindow() end end)
        SendMailFrame:HookScript("OnHide", function() if ns.RefreshWindow then ns.RefreshWindow() end end)
    end
    return frame
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:SetScript("OnEvent", function()
    panel = panel or Build()
    Refresh()
end)
