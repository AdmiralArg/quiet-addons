-- The Quiet Auctions window: your profit, what's found, and the buttons. /qah opens and closes it (or a key:
-- Key Bindings, AddOns). On a character with the Auctions role it opens by itself where there's work: at the auction
-- house, at a mailbox with auction mail in it, and at a vendor when there's something bought to sell (the settings,
-- or /qah autoopen off, stop that). In the shared Quiet look (QuietKit.UI).
--
-- Seven tabs: Buy (what's under vendor price, what's bought and where it is now, and, folded away unless resale is
-- on, what's under its usual auction price), Post (what Post puts up, in order), Prices (what sells well, what's
-- rarely listed), Crafting (recipes that pay), Crates (the cheapest bundle to fill each profession crate: Crates.lua),
-- Plan (what you want, and what to fetch, make and buy for it: Plan.lua) and Settings (each setting as a sentence, with buttons to change it:
-- the same as on the settings page, kept here so they can be changed at the auction house without leaving it).
-- At the bottom only the buttons that work where you stand, each labelled with what one press does now:
--   at the auction house: Scan, Buy (with Skip this one beside it), Post (and Take down auctions others
--   list for less, when you have auctions up)
--   at a vendor: Sell;  at a mailbox: Collect;  anywhere else: a line saying where to go next.
--
-- A line about an item (most lines in the lists) is a button: at the auction house a click opens that item's
-- listings on the game's own buy page (AH.lua), with how many filled in where the line says how many.
--
-- Made for the gamepad cursor as well as the mouse: ordinary frames (the game's gamepad frames are closed to addons),
-- big buttons, and nothing that needs a hover or a right-click: every explanation is written out.
local _, ns = ...

local UI = QuietKit.UI
local C = UI.C

local WIDTH, HEIGHT = 640, 660
local ROWS = 12
local ROW_HEIGHT = 22
local LIST_TOP = -122
local BUTTON_HEIGHT = 34
local BUTTON_GAP = 6
local KEEP_WIDTH = 170
local SMALL = 26
local SETTING_HEIGHT = 29
local ACTION_WIDTH = 46

local window
local tab = "buy"
local page = 1
local openedBy -- (the place that opened it, so leaving there closes it)

local function Button(parent, text, width, height, onClick, primary)
    local button = UI.Button(parent, text, onClick, width, primary)
    button:SetHeight(height or SMALL)
    return button
end

local function Fill(texture, c, alpha)
    texture:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function Text(parent, role, justify)
    local text = UI.Text(parent, role or "body", "OVERLAY")
    text:SetJustifyH(justify or "LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    return text
end

-- A text in a role's font and colour (a row is used for headers and plain lines in turn)
local FONTS = {
    heading = { "GameFontNormal", C.accent },
    body = { "GameFontHighlight", C.text },
    small = { "GameFontHighlightSmall", C.muted },
}
local function SetRole(text, role)
    local f = FONTS[role]
    text:SetFontObject(f[1])
    text:SetTextColor(f[2][1], f[2][2], f[2][3])
end

-- ---------- the tabs' rows ----------
local function BuyRows()
    local rows = {}
    local list = ns.candidates
    rows[#rows + 1] = { header = "Under vendor price on the auction house: Buy gets these, top first ("
        .. #list .. ")" }
    for i = 1, math.min(#list, 60) do
        local c = list[i]
        local vendor = (ns.SellPrice(c.id) or 0) * c.qty
        rows[#rows + 1] = { c.qty .. " " .. ns.ItemName(c.id) .. (ns.Skipped(c.id) and " (skipped)" or ""),
            "costs " .. (c.estimate and "from " or "")
            .. ns.Money(c.cost) .. ", a vendor pays " .. ns.Money(vendor) .. ": +" .. (c.estimate and "at least " or "")
            .. ns.Money(c.profit), id = c.id, count = c.qty }
    end
    if #list == 0 then
        rows[#rows + 1] = { ns.at.auction and "Nothing yet: Scan reads the auction house."
            or "Open the auction house to scan it." }
    end
    for _, r in ipairs(ns.BoughtRows()) do rows[#rows + 1] = r end
    return rows
end

local function TabRows()
    local rows
    if tab == "buy" then
        rows = BuyRows()
        for _, r in ipairs(ns.ResaleRows()) do rows[#rows + 1] = r end
    elseif tab == "post" then
        rows = ns.BoERows()
        for _, r in ipairs(ns.PostRows()) do rows[#rows + 1] = r end
    elseif tab == "prices" then
        rows = ns.PriceRows()
    elseif tab == "crates" then
        rows = ns.CrateRows()
    elseif tab == "plan" then
        rows = ns.PlanRows()
    else
        rows = ns.CraftRows()
    end
    -- (a row's small second line, as a row of its own)
    local shown = {}
    for _, r in ipairs(rows) do
        shown[#shown + 1] = r
        if r.sub then shown[#shown + 1] = { "      " .. r.sub, small = true, id = r.id, count = r.count } end
    end
    return shown
end

-- ---------- the Settings tab ----------
-- The next value up (dir 1) or down (-1) a list of steps
local function Step(steps, now, dir)
    if dir > 0 then
        for _, v in ipairs(steps) do
            if v > now then return v end
        end
        return steps[#steps]
    end
    for i = #steps, 1, -1 do
        if steps[i] < now then return steps[i] end
    end
    return steps[1]
end

local function Stepper(key, steps)
    return function(dir) ns.SetSetting(key, Step(steps, ns.Setting(key), dir)) end
end

local HOURS = { 12, 24, 48 }
-- (the settings page offers the same steps: Options.lua)
ns.PROFIT_STEPS = { 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 5000, 10000 }
ns.STACK_STEPS = { 1, 2, 4, 6, 8, 12, 16, 24, 36 }

-- Each: its sentence, and either change(dir) for Less / More, or toggle (a setting that's on or off)
local SETTINGS = {
    { text = function()
        return "Only buy when it's at least " .. ns.Setting("margin") .. "% under what a vendor pays"
    end,
        change = function(dir) ns.SetSetting("margin", math.max(0, math.min(90, ns.Setting("margin") + dir))) end },
    { text = function() return "...and only when one press makes at least " .. ns.Money(ns.Setting("minProfit")) end,
        change = Stepper("minProfit", ns.PROFIT_STEPS) },
    { text = function()
        return "One press buys at most " .. ns.Setting("stacks") .. " stacks of ore, cloth and such"
    end,
        change = Stepper("stacks", ns.STACK_STEPS) },
    { text = function() return "Never post a stack below vendor price + " .. ns.Setting("floor") .. "%" end,
        change = function(dir) ns.SetSetting("floor", math.max(0, math.min(500, ns.Setting("floor") + 5 * dir))) end },
    { text = function() return "Auctions last " .. HOURS[ns.Setting("duration")] .. " hours" end,
        change = function(dir) ns.SetSetting("duration", math.max(1, math.min(3, ns.Setting("duration") + dir))) end },
    { toggle = "posting", text = "Post sells stacks from your bags too (BoEs it always posts)" },
    { toggle = "resale", text = "Buy also gets gear under its usual auction price, to resell (risky)" },
    { toggle = "watch", text = "Between full scans, keep checking the items that pay" },
    { toggle = "autoScan", text = "Scan by itself at the auction house when a full scan is allowed" },
    { toggle = "autoOpen", text = "Open this window by itself where there's work: auction house, mailbox, vendor" },
    { toggle = "minimap", text = "A button on the minimap opens and closes this window" },
}

local function DrawSettings()
    for _, s in ipairs(window.settingRows) do
        local def = s.def
        if def.toggle then
            local on = ns.Setting(def.toggle)
            s.text:SetText(def.text .. ": " .. (on and "on" or "off"))
            s.toggle:SetText(on and "Turn off" or "Turn on")
        else
            s.text:SetText(def.text())
        end
    end
end

-- ---------- what it shows ----------
local function SetAction(button, label, enabled)
    button:SetText(label or "")
    button:SetEnabled(enabled and true or false)
end

-- The buttons for where you stand, placed from the bottom up; the rest hidden
local function PlaceActions(shown)
    for _, b in pairs(window.actions) do b:Hide() end
    local y = 12
    for i = #shown, 1, -1 do
        local b = shown[i]
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", 16, y)
        b:Show()
        y = y + BUTTON_HEIGHT + BUTTON_GAP
    end
    window.message:ClearAllPoints()
    window.message:SetPoint("BOTTOMLEFT", 16, math.max(y, 12 + 2 * (BUTTON_HEIGHT + BUTTON_GAP)) + 4)
    window.message:SetPoint("RIGHT", -16, 0)
end

-- Where to go next, or, on a character that doesn't do the auction work, why there are no buttons
local function Away()
    if ns.Does("auctions") then return ns.WhereNext() end
    return "This character " .. (ns.Does("crafting") and "crafts" or "rests") .. ": buying, selling and posting are "
        .. "for a character with the Auctions role. Roles: Options, AddOns, Quiet (/qah settings)."
end

-- The lines and buttons at the top and bottom: cheap, so drawn each second while open (timers, scan progress)
local function DrawTop()
    if not window or not window:IsShown() then return end
    local status = ns.at.auction and (ns.ScanStatus() .. " " .. ns.WatchStatus()) or ""
    local asking = ns.ItemsToAsk()
    if asking > 0 then status = status .. "  Learning " .. asking .. " items..." end
    window.status:SetText(status)
    local _, waiting = ns.Totals()
    window.totals:SetText(ns.ProfitLine() .. ". Still to come from what's bought: +" .. ns.Money(waiting) .. ".")

    local shown = {}
    window.whereNext:SetText("")
    local onDuty = ns.Does("auctions")
    if onDuty and ns.at.auction then
        SetAction(window.scanButton, ns.ScanLabel())
        SetAction(window.buyButton, ns.BuyQueueLabel())
        SetAction(window.postButton, ns.PostQueueLabel())
        shown = { window.scanButton, window.buyButton, window.postButton }
        if ns.HasAuctions() then
            SetAction(window.takeDownButton, ns.CancelLabel())
            shown[#shown + 1] = window.takeDownButton
        end
    elseif onDuty and ns.at.merchant then
        SetAction(window.sellButton, ns.SellLabel())
        shown = { window.sellButton }
    elseif onDuty and ns.at.mail then
        SetAction(window.collectButton, ns.CollectLabel())
        shown = { window.collectButton }
    else
        window.whereNext:SetText(Away())
    end
    PlaceActions(shown)
    -- (beside Buy: "Skip this one", while Buy's next is from the list under vendor price)
    local skip = onDuty and ns.CanSkip() and true or false
    window.skipButton:SetShown(skip)
    window.buyButton:SetWidth(WIDTH - 32 - (skip and (KEEP_WIDTH + BUTTON_GAP) or 0))
    -- (beside Post: "Never post this one", only while Post's next is a BoE of your own)
    local top = onDuty and ns.at.auction and ns.BoETop()
    local keep = top and not top.bought
    window.keepButton:SetShown(keep and true or false)
    window.postButton:SetWidth(WIDTH - 32 - (keep and (KEEP_WIDTH + BUTTON_GAP) or 0))
end

-- The chosen tab in the accent, the others plain
local function MarkTab(button, on)
    Fill(button.bg, on and C.accent or C.raised, on and 0.22 or nil)
end

-- Everything, the list too: when something has happened (ns.Refresh), or a tab or page is chosen
local function Draw()
    if not window or not window:IsShown() then return end
    DrawTop()
    for key, button in pairs(window.tabs) do MarkTab(button, key == tab) end
    local settings = tab == "settings"
    window.settingsPanel:SetShown(settings)
    window.pager:SetShown(not settings)
    if settings then
        for _, line in ipairs(window.rows) do line:Hide() end
        DrawSettings()
        return
    end

    local rows = TabRows()
    local pages = math.max(1, math.ceil(#rows / ROWS))
    page = math.max(1, math.min(page, pages))
    for r, line in ipairs(window.rows) do
        local row = rows[(page - 1) * ROWS + r]
        line:SetShown(row ~= nil)
        line.item, line.count = row and row.id, row and row.count
        line:EnableMouse(line.item ~= nil)
        -- (its buttons, the last at the right end, and the right-hand text left of them)
        local actions = row and not row.header and row.actions or {}
        local first = 3 - #actions
        for i, b in ipairs(line.buttons) do
            local action = i >= first and actions[i - first + 1]
            b:SetShown(action and true or false)
            if action then
                b:SetText(action[1])
                b.run = action[2]
            end
        end
        line.right:ClearAllPoints()
        line.right:SetPoint("RIGHT", -8 - #actions * (ACTION_WIDTH + 4), 0)
        if row then
            if row.header then
                SetRole(line.left, "heading")
                line.left:SetText(row.header)
                line.right:SetText("")
                line.shade:Hide()
            else
                SetRole(line.left, row.small and "small" or "body")
                line.left:SetText(row[1] or "")
                line.right:SetText(row[2] or "")
                -- (the right-hand text at most 60% of the line, cut short with "...", so a long one never runs out of
                -- the window or hides the left)
                local most = (WIDTH - 48 - #actions * (ACTION_WIDTH + 4)) * 0.6
                line.right:SetWidth(0)
                if line.right:GetStringWidth() > most then line.right:SetWidth(most) end
                line.shade:Show()
            end
        end
    end
    window.pageText:SetText("Page " .. page .. " of " .. pages)
    window.prev:SetEnabled(page > 1)
    window.next:SetEnabled(page < pages)
end

-- (many events can ask in one moment: drawn once, a frame later)
local queued = false
function ns.Refresh()
    if not window or not window:IsShown() or queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Draw()
    end)
end

-- The last thing said, above the buttons. true: shown there (so not in a note).
function ns.OnMessage(msg)
    if not window or not window:IsShown() then return false end
    window.message:SetText(msg)
    ns.Refresh()
    return true
end

-- The tab shown, or nil while the window is closed (BoE.lua looks up the next BoE while it's the Post tab; AH.lua
-- looks things up by itself while it's open)
function ns.WindowTab()
    return window and window:IsShown() and tab or nil
end

function ns.ShowTab(key)
    window = window or ns.BuildWindow()
    tab, page = key, 1
    ns.Changed()
    window:Show()
    Draw()
end

function ns.HideWindow()
    if window then window:Hide() end
end

-- ---------- the window ----------
-- A click on a line about an item: its listings on the game's own buy page, at the auction house
local function LookUp(row)
    if not row.item then return end
    -- (ShowAtAuction says whether the auction house is open: on a character without the Auctions role too)
    if not ns.ShowAtAuction(row.item, row.count) then
        ns.Say("At the auction house, a click here opens " .. ns.ItemName(row.item) .. "'s listings.")
    end
end

local function Row(parent, r)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 32, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, LIST_TOP - (r - 1) * ROW_HEIGHT)
    row.shade = row:CreateTexture(nil, "BACKGROUND")
    Fill(row.shade, C.raised, r % 2 == 0 and 0.05 or 0.02)
    row.shade:SetAllPoints()
    -- (lit while the mouse or the gamepad cursor is on a line that can be clicked)
    local lit = row:CreateTexture(nil, "HIGHLIGHT")
    Fill(lit, C.accent, 0.12)
    lit:SetAllPoints()
    row:SetScript("OnClick", LookUp)
    -- (up to two small buttons at the right end, for a line that has them: Plan, or - and +)
    row.buttons = {}
    for i = 1, 2 do
        local b = Button(row, "", ACTION_WIDTH, ROW_HEIGHT - 2, function(self) if self.run then self.run() end end)
        b:SetPoint("RIGHT", -2 - (2 - i) * (ACTION_WIDTH + 4), 0)
        b:Hide()
        row.buttons[i] = b
    end
    row.right = Text(row, "small", "RIGHT")
    row.right:SetPoint("RIGHT", -8, 0)
    row.right:SetTextColor(C.text[1], C.text[2], C.text[3])
    row.left = Text(row)
    row.left:SetPoint("LEFT", 8, 0)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -12, 0)
    return row
end

local function SettingRow(parent, i, def)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 32, SETTING_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * SETTING_HEIGHT)
    local shade = row:CreateTexture(nil, "BACKGROUND")
    Fill(shade, C.raised, i % 2 == 0 and 0.05 or 0.02)
    shade:SetAllPoints()
    local s = { def = def }
    local right
    if def.toggle then
        s.toggle = Button(row, "Turn on", 100, SMALL - 2, function()
            ns.SetSetting(def.toggle, not ns.Setting(def.toggle))
            ns.Changed()
            Draw()
        end)
        s.toggle:SetPoint("RIGHT", -2, 0)
        right = s.toggle
    else
        local more = Button(row, "More", 64, SMALL - 2, function()
            def.change(1)
            Draw()
        end)
        more:SetPoint("RIGHT", -2, 0)
        local less = Button(row, "Less", 64, SMALL - 2, function()
            def.change(-1)
            Draw()
        end)
        less:SetPoint("RIGHT", more, "LEFT", -4, 0)
        right = less
    end
    s.text = Text(row)
    s.text:SetPoint("LEFT", 8, 0)
    s.text:SetPoint("RIGHT", right, "LEFT", -8, 0)
    return s
end

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then ns.DB().window = { point = point, relativePoint = relativePoint, x = x, y = y } end
end

function ns.BuildWindow()
    -- (the glass, the title, the close button, dragging and Escape: QuietKit's window)
    local frame = UI.Window("QuietAuctionsWindow", "Quiet Auctions", WIDTH, HEIGHT)
    frame:ClearAllPoints()
    local saved = ns.DB().window
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        -- (beside the auction house window, not on top of it)
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    end
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- (the place is ours to keep, in QuietAuctionsDB, not the game's layout cache)
        self:SetUserPlaced(false)
        SavePosition(self)
    end)

    -- The scan's progress (at the auction house), and the profit (two lines if it needs them)
    frame.status = Text(frame, "muted")
    frame.status:SetPoint("TOPLEFT", 16, -40)
    frame.status:SetPoint("RIGHT", -16, 0)
    frame.totals = Text(frame, "small")
    frame.totals:SetPoint("TOPLEFT", 16, -56)
    frame.totals:SetPoint("RIGHT", -16, 0)
    frame.totals:SetJustifyV("TOP")
    frame.totals:SetWordWrap(true)
    frame.totals:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    -- The tabs
    frame.tabs = {}
    local previous
    for _, t in ipairs({ { "buy", "Buy" }, { "post", "Post" }, { "prices", "Prices" }, { "craft", "Crafting" },
        { "crates", "Crates" }, { "plan", "Plan" }, { "settings", "Settings" } }) do
        local button = Button(frame, t[2], 81, 28, function()
            tab, page = t[1], 1
            ns.Changed() -- (its list worked out afresh: names learned since)
            Draw()
        end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", 16, -84)
        end
        frame.tabs[t[1]] = button
        previous = button
    end

    -- The list, a page at a time
    frame.rows = {}
    for r = 1, ROWS do frame.rows[r] = Row(frame, r) end
    local listBottom = LIST_TOP - ROWS * ROW_HEIGHT - 6
    frame.pager = CreateFrame("Frame", nil, frame)
    frame.pager:SetPoint("TOPLEFT", 16, listBottom)
    frame.pager:SetSize(WIDTH - 32, SMALL)
    frame.next = Button(frame.pager, "Next page", 100, SMALL, function()
        page = page + 1
        Draw()
    end)
    frame.next:SetPoint("RIGHT")
    frame.pageText = Text(frame.pager, "muted")
    frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.prev = Button(frame.pager, "Previous page", 120, SMALL, function()
        page = page - 1
        Draw()
    end)
    frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -8, 0)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        page = page - delta
        Draw()
    end)

    -- The Settings tab, in the list's place, and a line saying where the rest is (roles, macros)
    frame.settingsPanel = CreateFrame("Frame", nil, frame)
    frame.settingsPanel:SetPoint("TOPLEFT", 16, LIST_TOP)
    frame.settingsPanel:SetSize(WIDTH - 32, (#SETTINGS + 1) * SETTING_HEIGHT + 8)
    frame.settingRows = {}
    for i, def in ipairs(SETTINGS) do frame.settingRows[i] = SettingRow(frame.settingsPanel, i, def) end
    local more = Text(frame.settingsPanel, "muted")
    more:SetPoint("TOPLEFT", 8, -#SETTINGS * SETTING_HEIGHT - 10)
    more:SetPoint("RIGHT", -130, 0)
    more:SetText("Which character does what, and the macros: the settings page.")
    local open = Button(frame.settingsPanel, "Settings page", 120, SMALL - 2, function() ns.OpenSettings() end)
    open:SetPoint("TOPRIGHT", -2, -#SETTINGS * SETTING_HEIGHT - 4)
    frame.settingsPanel:Hide()

    -- The message line (the last thing said), placed above the buttons shown
    frame.message = UI.Text(frame, "body", "OVERLAY")
    -- Away from the auction house, a vendor and a mailbox: where to go next, in the buttons' place
    frame.whereNext = UI.Text(frame, "heading", "OVERLAY")
    frame.whereNext:SetFontObject("GameFontNormalLarge")
    frame.whereNext:SetTextColor(C.title[1], C.title[2], C.title[3])
    frame.whereNext:SetPoint("BOTTOMLEFT", 16, 24)
    frame.whereNext:SetPoint("RIGHT", -16, 0)
    frame.whereNext:SetJustifyV("BOTTOM")

    -- The buttons: each the width of the window, its label what one press does now (the ones that spend or earn
    -- in the accent)
    local function Big(onClick, primary)
        local b = Button(frame, "", WIDTH - 32, BUTTON_HEIGHT, onClick, primary)
        local label = b:GetFontString()
        label:SetFontObject("GameFontHighlight")
        label:SetTextColor(C.title[1], C.title[2], C.title[3])
        label:ClearAllPoints()
        label:SetPoint("LEFT", 12, 0)
        label:SetPoint("RIGHT", -12, 0)
        label:SetWordWrap(false)
        return b
    end
    frame.scanButton = Big(function() ns.Scan(true) end)
    frame.buyButton = Big(function() ns.BuyPress() end, true)
    frame.postButton = Big(function() ns.PostPress() end, true)
    frame.takeDownButton = Big(function() ns.CancelNext() end)
    frame.sellButton = Big(function() ns.Sell() end, true)
    frame.collectButton = Big(function() ns.Collect() end, true)
    frame.actions = { frame.scanButton, frame.buyButton, frame.postButton, frame.takeDownButton, frame.sellButton,
        frame.collectButton }
    frame.keepButton = Button(frame, "Never post this one", KEEP_WIDTH, BUTTON_HEIGHT, function() ns.KeepBoE() end)
    frame.keepButton:SetPoint("LEFT", frame.postButton, "RIGHT", BUTTON_GAP, 0)
    frame.keepButton:Hide()
    frame.skipButton = Button(frame, "Skip this one", KEEP_WIDTH, BUTTON_HEIGHT, function() ns.SkipTop() end)
    frame.skipButton:SetPoint("LEFT", frame.buyButton, "RIGHT", BUTTON_GAP, 0)
    frame.skipButton:Hide()

    -- Timers and scan progress move on by themselves: drawn again each second while open
    local ticker
    frame:SetScript("OnShow", function()
        frame.message:SetText("")
        Draw()
        if C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, DrawTop) end
    end)
    frame:SetScript("OnHide", function()
        if ticker then ticker:Cancel() end
        ticker = nil
        openedBy = nil
    end)
    return frame
end

function ns.ToggleWindow()
    window = window or ns.BuildWindow()
    window:SetShown(not window:IsShown())
end

-- ---------- opening by itself ----------
-- Only on a character with the Auctions role, and only with the setting on (the callers say when there's work: the
-- auction house always, a mailbox with auction mail, a vendor with something bought to sell)
function ns.OnPlaceOpened(place)
    if not ns.Does("auctions") or not ns.Setting("autoOpen") then return end
    window = window or ns.BuildWindow()
    if window:IsShown() then
        Draw()
        return
    end
    tab, page = "buy", 1
    window:Show()
    openedBy = place
end

function ns.OnPlaceClosed(place)
    if window and window:IsShown() and openedBy == place and not (ns.at.auction or ns.at.merchant or ns.at.mail) then
        window:Hide()
    end
end
