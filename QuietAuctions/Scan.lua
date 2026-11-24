-- Reading the whole auction house, and what's learned from it:
--  * the full scan (C_AuctionHouse.ReplicateItems) every auction at once, allowed once per 15 minutes. Read a
--    little each frame, so the game doesn't stall on tens of thousands of auctions.
--  * between full scans, or if one doesn't answer: the browse pages (the cheapest of each item), a page at a time
--    with a pause between pages.
--  * the price memory: each scan, every item's cheapest buyout for one, and how many were listed (Prices.lua reads it)
--  * the list to buy from: everything listed for less than a vendor pays, by total profit (Buy.lua works it)
local _, ns = ...

local AH = C_AuctionHouse
local FULL_SCAN_EVERY = 15 * 60
local FULL_SCAN_TIMEOUT = 90
local PAGE_PAUSE = 1.5
local PAGE_TIMEOUT = 20
local HISTORY = ns.HISTORY -- (scans remembered per item)
local PER_FRAME = 600

local scan -- { kind = "full" | "browse", at, ... } while one runs
-- The last scan's auctions per item, to build the list from: { [itemID] = { counts = {}, buyouts = {} } }
local lastRows
local rowsEstimate = false -- (from the browse pages: only the cheapest of each item is known)
local fullFailed = false -- (this session: the full scan didn't answer, so pages only)

ns.candidates = {}

function ns.Scanning()
    return scan ~= nil
end

-- The last scan's auctions per item (Resale.lua looks for gear well under its usual price in them), or nil
function ns.LastRows()
    return lastRows
end

-- Seconds until a full scan is allowed again (0: now)
function ns.FullScanWait()
    local wait = (ns.Market().lastFull or 0) + FULL_SCAN_EVERY - time()
    return math.max(0, wait)
end

function ns.ScanStatus()
    if scan then
        if scan.kind == "full" then
            return scan.reading and ("Reading the full scan: " .. scan.read .. " / " .. scan.total .. " auctions...")
                or "Full scan asked for; waiting for the auction house..."
        end
        return "Reading the auction house, page " .. (scan.pages or 1) .. "..."
    end
    local market = ns.Market()
    local last = market.scanAt[market.scanNo]
    local text = last and ("Last scan " .. math.floor((time() - last) / 60) .. " min ago.") or "No scan yet."
    local wait = ns.FullScanWait()
    if fullFailed then
        text = text .. " Full scan unavailable: pages instead."
    elseif wait > 0 then
        text = text .. " Full scan again in " .. math.ceil(wait / 60) .. " min."
    else
        text = text .. " A full scan is ready."
    end
    return text
end

-- ---------- price memory ----------
-- market.prices[itemID] = { f = first scan seen in, h = { scan, cheapest for one, quantity, scan, ... } } (packed
-- into a line while saved, and items not seen in a long while forgotten: Core.lua)
local function Remember(mins, qtys)
    local market = ns.Market()
    market.scanNo = (market.scanNo or 0) + 1
    local s = market.scanNo
    market.scanAt[s] = time()
    for old in pairs(market.scanAt) do
        if old <= s - ns.SCANS_KEPT then market.scanAt[old] = nil end
    end
    for id, cheapest in pairs(mins) do
        local p = market.prices[id]
        if not p then
            p = { f = s, h = {} }
            market.prices[id] = p
        end
        local h = p.h
        h[#h + 1] = s
        h[#h + 1] = math.floor(cheapest + 0.5)
        h[#h + 1] = qtys[id] or 0
        while #h > HISTORY * 3 do
            table.remove(h, 1)
            table.remove(h, 1)
            table.remove(h, 1)
        end
    end
    ns.Changed()
end

-- ---------- the list to buy from ----------
-- The most to pay for one: the vendor's price less the margin (nil: unknown, or a vendor pays nothing)
function ns.MaxUnit(id)
    local vendor = ns.SellPrice(id)
    if not vendor or vendor <= 0 then return nil end
    return math.floor(vendor * (1 - ns.Setting("margin") / 100))
end

local function AddRow(rows, id, count, buyout)
    local r = rows[id]
    if not r then
        r = { counts = {}, buyouts = {} }
        rows[id] = r
    end
    local n = #r.counts + 1
    r.counts[n], r.buyouts[n] = count, buyout
end

-- One item's place on the list (how many under vendor price, what they cost, what a vendor pays over that), or nil.
-- An item the game hasn't described yet is asked about (Core.lua) and comes in by ns.OnItemData.
local function Candidate(id, r)
    local vendor = ns.SellPrice(id)
    local maxUnit = ns.MaxUnit(id)
    if not vendor or not maxUnit then return nil end
    local c
    local money = GetMoney()
    for i = 1, #r.counts do
        -- (never more in one auction than one stack holds: a count that says otherwise isn't believed)
        local count, buyout = math.min(r.counts[i], ns.StackSize(id)), r.buyouts[i]
        -- (and only what you could pay for now: a whole plain auction, or one of a commodity)
        if buyout / count <= maxUnit and (buyout <= money or (count > 1 and buyout / count <= money)) then
            c = c or { id = id, qty = 0, cost = 0, profit = 0, estimate = rowsEstimate }
            c.qty, c.cost = c.qty + count, c.cost + buyout
            c.profit = c.profit + vendor * count - buyout
        end
    end
    -- (not worth a press under the minimum profit: /qah minprofit, 5c by default)
    if c and c.profit < ns.Setting("minProfit") then return nil end
    return c
end

-- Skipped items (Skip this one, Buy.lua): kept at the bottom of the list until you log out, in the order skipped, so
-- skipping again when only skipped ones are left goes round them. Kept over a /reload (QuietAuctionsCharDB.skipped =
-- { [itemID] = order }); a new login starts without them.
local function Skips()
    local char = ns.Char()
    char.skipped = char.skipped or {}
    return char.skipped
end

function ns.SkipCandidate(id)
    local skipped, last = Skips(), 0
    for _, order in pairs(skipped) do last = math.max(last, order) end
    skipped[id] = last + 1
end

function ns.Skipped(id)
    local skipped = ns.Char().skipped
    return skipped ~= nil and skipped[id] ~= nil
end

function ns.UnskipAll()
    local n = 0
    for _ in pairs(Skips()) do n = n + 1 end
    ns.Char().skipped = nil
    return n
end

-- Biggest profit first; skipped ones last
local function SortCandidates()
    local skipped = ns.Char().skipped or {}
    table.sort(ns.candidates, function(a, b)
        local sa, sb = skipped[a.id], skipped[b.id]
        if sa or sb then
            if sa and sb then return sa < sb end
            return sb ~= nil
        end
        return a.profit > b.profit
    end)
end
ns.SortCandidates = SortCandidates

-- After a reload the scan's auctions are gone (too many to keep): the price memory stands in, the last scan's cheapest
-- of each item, counted one each until a look-up tells more (as from the browse pages). Not if that scan is old.
local MEMORY_FRESH = 60 * 60
local function RowsFromMemory()
    local market = ns.Market()
    local s = market.scanNo
    if s == 0 or time() - (market.scanAt[s] or 0) > MEMORY_FRESH then return nil end
    local rows = {}
    for id, p in pairs(market.prices) do
        local h = p.h
        if #h >= 3 and h[#h - 2] == s then AddRow(rows, id, 1, h[#h - 1]) end
    end
    return rows
end

-- The whole list from the last scan's auctions, biggest profit first (after a scan, or a new margin)
function ns.BuildCandidates()
    if not lastRows then
        lastRows, rowsEstimate = RowsFromMemory(), true
        if not lastRows then return end
    end
    local list = {}
    for id, r in pairs(lastRows) do
        local c = Candidate(id, r)
        if c then list[#list + 1] = c end
    end
    ns.candidates = list
    SortCandidates()
    ns.Refresh()
end

-- Items described at last: added to the list, a couple of seconds' worth at a time
local arrived, addQueued = {}, false
function ns.OnItemData(id)
    if not lastRows or not lastRows[id] then return end
    arrived[#arrived + 1] = id
    if addQueued then return end
    addQueued = true
    C_Timer.After(2, function()
        addQueued = false
        local added = false
        for _, newID in ipairs(arrived) do
            local r = lastRows and lastRows[newID]
            local present = false
            for _, c in ipairs(ns.candidates) do
                if c.id == newID then present = true end
            end
            local c = r and not present and Candidate(newID, r)
            if c then
                ns.candidates[#ns.candidates + 1] = c
                added = true
            end
        end
        arrived = {}
        if added then
            SortCandidates()
            ns.Refresh()
        end
    end)
end

function ns.DropCandidate(id)
    for i, c in ipairs(ns.candidates) do
        if c.id == id then
            table.remove(ns.candidates, i)
            break
        end
    end
    -- (and out of the scan's rows, so a rebuild doesn't bring it back)
    if lastRows then lastRows[id] = nil end
    ns.Refresh()
end

local function Done(kind, auctions, items)
    scan = nil
    ns.BuildCandidates()
    local top = ns.candidates[1]
    ns.Say((kind == "full" and "Full scan" or "Scan") .. " done: " .. auctions .. " auctions, " .. items
        .. " items. " .. (#ns.candidates > 0 and (#ns.candidates .. " under vendor price, best " .. ns.ItemName(top.id)
        .. " (" .. ns.Money(top.profit) .. ").") or "Nothing under vendor price."))
    if ns.Prepare then C_Timer.After(1, ns.Prepare) end
end

-- ---------- the full scan ----------
local function ReplicateRow(i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = AH.GetReplicateItemInfo(i)
    return itemID, count, buyout, owner
end

local StartBrowse

local function ReadFull()
    local ok, total = pcall(AH.GetNumReplicateItems)
    total = ok and total or 0
    if total == 0 then
        fullFailed = true
        ns.Say("The full scan came back empty; reading the pages instead.")
        StartBrowse()
        return
    end
    local me = UnitName("player")
    local mins, qtys, items = {}, {}, 0
    local rows = {}
    scan.reading, scan.read, scan.total = true, 0, total
    -- (0-based in the newer client; one past the end too, in case this one counts from 1: a missing row is skipped)
    ns.Chunks(0, total, PER_FRAME, function(i)
        local got, id, count, buyout, owner = pcall(ReplicateRow, i)
        scan.read = i
        if not got or not id or not count or count <= 0 or not buyout or buyout <= 0 then return end
        if owner == me then return end
        local unit = buyout / count
        if not mins[id] then items = items + 1 end
        if not mins[id] or unit < mins[id] then mins[id] = unit end
        qtys[id] = (qtys[id] or 0) + count
        AddRow(rows, id, count, buyout)
    end, function()
        Remember(mins, qtys)
        lastRows, rowsEstimate = rows, false
        Done("full", total, items)
    end)
end

local function StartFull()
    scan = { kind = "full", at = GetTime() }
    local ok = pcall(AH.ReplicateItems)
    if not ok then
        fullFailed = true
        StartBrowse()
        return
    end
    ns.Market().lastFull = time()
    local mine = scan
    C_Timer.After(FULL_SCAN_TIMEOUT, function()
        if scan == mine and not scan.reading then
            fullFailed = true
            ns.Say("The full scan didn't answer; reading the pages instead.")
            StartBrowse()
        end
    end)
end

-- ---------- the browse pages ----------
local function FinishBrowse()
    local ok, results = pcall(AH.GetBrowseResults)
    results = ok and type(results) == "table" and results or {}
    local mins, qtys = {}, {}
    local rows = {}
    local items = 0
    for _, r in ipairs(results) do
        local id = r.itemKey and r.itemKey.itemID
        if id and r.minPrice and r.minPrice > 0 then
            if not mins[id] then items = items + 1 end
            if not mins[id] or r.minPrice < mins[id] then mins[id] = r.minPrice end
            qtys[id] = (qtys[id] or 0) + (r.totalQuantity or 0)
            -- (a page tells only the cheapest one: the list counts one each until a search tells more)
            AddRow(rows, id, 1, r.minPrice)
        end
    end
    if items > 0 then
        Remember(mins, qtys)
        lastRows, rowsEstimate = rows, true
    end
    Done("browse", #results, items)
end

local function NextPage()
    if not scan or scan.kind ~= "browse" or scan.asked then return end
    local ok, full = pcall(AH.HasFullBrowseResults)
    -- (you've searched the game's browse list yourself, or turned to its other pages: what's read so far is used,
    -- and the list is yours)
    if (ok and full) or not ns.at.auction or ns.YoursSince(scan.at) then
        FinishBrowse()
        return
    end
    if not ns.Ready() then
        C_Timer.After(0.5, NextPage)
        return
    end
    scan.asked = true
    scan.pages = (scan.pages or 1) + 1
    scan.lastPage = GetTime()
    if not ns.Ours(AH.RequestMoreBrowseResults) then FinishBrowse() end
end

function StartBrowse()
    scan = { kind = "browse", at = GetTime(), pages = 1, asked = true, lastPage = GetTime() }
    local query = { searchString = "", sorts = ns.SORT_BY_PRICE, filters = {}, itemClassFilters = {} }
    if not ns.Ours(AH.SendBrowseQuery, query) then
        scan = nil
        ns.Say("The auction house wouldn't take the search.")
        return
    end
    -- (a page that never comes: what's read so far is used)
    local mine = scan
    local function Watch()
        if scan ~= mine then return end
        if GetTime() - scan.lastPage > PAGE_TIMEOUT then
            FinishBrowse()
        else
            C_Timer.After(2, Watch)
        end
    end
    C_Timer.After(2, Watch)
end

local function OnPage()
    if not scan or scan.kind ~= "browse" then return end
    scan.asked = false
    scan.lastPage = GetTime()
    ns.Refresh()
    C_Timer.After(PAGE_PAUSE, NextPage)
end

-- ---------- starting one ----------
-- A full scan is allowed now (and this client answers them)
function ns.FullScanReady()
    return not fullFailed and not scan and ns.FullScanWait() == 0 and AH ~= nil and AH.ReplicateItems ~= nil
end

-- A full scan when it's allowed, else the pages. manual: asked for (says why not, if not). By itself (the watch,
-- Watch.lua) only when ns.LookByItself says so.
function ns.Scan(manual)
    if not ns.at.auction then
        if manual then ns.Say("Open the auction house first.") end
        return
    end
    if not ns.HasAuctionAPI() then
        ns.Say("This client's auction house isn't the one Quiet Auctions knows.")
        return
    end
    if scan then
        if manual then ns.Say(ns.ScanStatus()) end
        return
    end
    if not fullFailed and ns.FullScanWait() == 0 and AH.ReplicateItems then
        StartFull()
    elseif manual or (ns.Market().scanNo == 0 and ns.LookByItself(true)) then
        -- (the pages are slow, and the browse list is the one you browse: read by themselves only when there's no
        -- price memory yet, and long after a search of yours; else the watch, Watch.lua, covers the time until the
        -- next full scan)
        StartBrowse()
    else
        return
    end
    ns.Refresh()
end

-- What a press of Scan does now, as a sentence
function ns.ScanLabel()
    if scan then return ns.ScanStatus(), false end
    local wait = ns.FullScanWait()
    if not fullFailed and wait == 0 then return "Scan the whole auction house (a full scan)", true end
    return "Scan the auction house page by page" .. (fullFailed and "" or (" (a full scan in "
        .. math.ceil(wait / 60) .. " min)")), true
end

-- A page scan under way: it uses the auction house's browse list, so nothing else may search meanwhile. (A full
-- scan doesn't stop searches: while the auction house prepares it, looking up and buying go on.)
function ns.Browsing()
    return scan ~= nil and scan.kind == "browse"
end

-- ---------- events ----------
ns.Listen("auctions", { "PLAYER_ENTERING_WORLD", "AUCTION_HOUSE_SHOW", "REPLICATE_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_CLOSED" },
function(_, event, initialLogin)
    if event == "PLAYER_ENTERING_WORLD" then
        -- (a new login: what was skipped is back in place; a /reload keeps it)
        if initialLogin then ns.Char().skipped = nil end
    elseif event == "AUCTION_HOUSE_SHOW" then
        -- (the list from the price memory until a scan brings a new one; the scan by itself comes from the watch,
        -- Watch.lua, once you're using Quiet Auctions and not the game's own pages)
        if not lastRows then ns.BuildCandidates() end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scan and scan.kind == "full" and not scan.reading then
            scan.reading, scan.read, scan.total = true, 0, 0
            -- (a moment for the list to settle)
            C_Timer.After(1, ReadFull)
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        OnPage()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- (a full scan already handed over is read to the end; a page scan stops)
        if scan and scan.kind == "browse" then scan = nil end
        if scan and scan.kind == "full" and not scan.reading then scan = nil end
    end
end)
