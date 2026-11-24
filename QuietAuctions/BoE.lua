-- Posting BoEs: the Bind on Equip things in your bags that aren't bound yet, put up one at a press. They come first
-- in the Post queue (Queues.lua). Never anything soulbound, never a quest item, never what you've kept ("Never post
-- this one", or /qah keep <item link>).
-- Also what Next bought that brings clearly more at auction than from a vendor (Ledger.lua: ns.RepostPays), so it's
-- resold rather than vendored; Sell leaves those. Each post goes in the ledger with what the item cost you.
--
-- Its price, for one:
--   the cheapest price someone else lists it for now (matched, not beaten: buyers take the cheapest first, and the
--   newest of the ones at a price, so a copper less would only give gold away);
--   with nobody listing it, its price from the scans (Prices.lua);
--   with no price remembered, a guess: a few times what a vendor pays (3x for green, 5x for blue). An epic is never
--   guessed at: price that one by hand.
-- Only above vendor price: after the auction house's cut, and with the deposit counted as lost, a sale must bring
-- more than a vendor pays. One that wouldn't is left alone, with a word: sell it to a vendor instead (a bought one
-- goes back on the Sell list; your own, by hand).
--
-- The Post tab lists what it will post and at what price before you press. At the auction house the next one is
-- looked up by itself (only a look) while the Post tab is shown or once you've posted one, so a press posts it.
-- Posting is a press of yours, one auction a press, as everywhere here. BoEs are posted while /qah posting is off:
-- that setting is for the stacks that come after them in the Post queue.
local _, ns = ...

local AH = C_AuctionHouse
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local BIND_ON_EQUIP = 2
local QUEST = 12
local STALE = 60
local BUSY_TIMEOUT = 10
local LOOK_EVERY = 1
local RETRY_AFTER = 30
local GUESS = { [0] = 2, [1] = 2, [2] = 3, [3] = 5 } -- (times vendor price, by quality, with nothing to go by)

local boe -- { bag, slot, id, count, quality, bought, step, at, commodity, key, unit, basis, deposit, money }
local held = {} -- [itemID] = { why = why it's left alone this session, short = what to do instead, in a few words }
local failed = {} -- [itemID] = when its look-up went unanswered (not looked up by itself again for a while)
local active = false -- (a BoE posted this visit: the next is looked up by itself, whatever the tab)

-- What's kept for good: QuietAuctionsDB.keep = { [itemID] = true }
local function Kept()
    local db = ns.DB()
    db.keep = db.keep or {}
    return db.keep
end

-- ---------- what to post ----------
local function IsBoE(bag, slot, info)
    if info.isBound or info.isLocked then return false end
    local ok, name, _, quality, _, _, _, _, _, _, _, _, classID, _, bindType = pcall(GetInfo, info.itemID)
    if not ok or not name then
        ns.ItemInfo(info.itemID) -- (asks the game for it; next time it's known)
        return false
    end
    if bindType ~= BIND_ON_EQUIP or classID == QUEST then return false end
    if C_Item and C_Item.IsBound and ItemLocation then
        local got, bound = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
        if got and bound then return false end
    end
    -- (at the auction house, the game says whether it would take it at all)
    if ns.at.auction and ns.CanSell and not ns.CanSell(bag, slot) then return false end
    return true, quality
end

-- Its price before a look: the last scan's cheapest, else its usual price, else a guess. nil and why for none.
local function Estimate(id, quality)
    local latest = ns.Latest(id)
    if latest then return math.max(1, math.floor(latest)), "the last scan's cheapest" end
    local usual = ns.Usual(id)
    if usual then return usual, "its usual price" end
    local vendor = ns.SellPrice(id) or 0
    local times = GUESS[quality or 2]
    if times and vendor > 0 then return vendor * times, "a guess: " .. times .. "x vendor price" end
    if (quality or 0) >= 4 then return nil, "an epic nobody lists: price it by hand" end
    return nil, "nothing to price it by"
end

-- What to post, the most valuable first: { { bag, slot, id, count, quality, bought, estimate, basis } }. (The window
-- asks several times a second: kept until the bags, the price memory or what's held change, or a few seconds pass,
-- as an item's data may come in meanwhile.)
local KEEP_FOR = 3
local found = { at = 0 }
local function Find()
    local key = ns.bagVersion .. ":" .. ns.version .. ":" .. tostring(ns.at.auction)
    if found.key == key and GetTime() - found.at < KEEP_FOR then return found.list end
    local keep = Kept()
    local vendorIt = ns.Char().vendorIt or {}
    local left = {}
    for id, b in pairs(ns.Char().bought) do left[id] = b.n end
    local list = {}
    ns.EachSlot(function(bag, slot, info)
        local id, count = info.itemID, info.stackCount or 1
        if keep[id] or held[id] or vendorIt[id] or info.isLocked then return end
        if left[id] then
            -- (bought: only a stack wholly bought, and only if it pays more at auction; else it's Sell's)
            if left[id] < count then return end
            left[id] = left[id] - count
            if not ns.RepostPays(id, count) then return end
            if ns.at.auction and ns.CanSell and not ns.CanSell(bag, slot) then return end
            local _, price = ns.AuctionReturn(id)
            local _, _, quality = ns.ItemInfo(id)
            list[#list + 1] = { bag = bag, slot = slot, id = id, count = count, quality = quality, bought = true,
                estimate = price, basis = "bought; pays more at auction" }
            return
        end
        local yes, quality = IsBoE(bag, slot, info)
        if not yes then return end
        local estimate, basis = Estimate(id, quality)
        list[#list + 1] = { bag = bag, slot = slot, id = id, count = count, quality = quality,
            estimate = estimate, basis = basis }
    end)
    table.sort(list, function(a, b) return (a.estimate or 0) * a.count > (b.estimate or 0) * b.count end)
    found.key, found.at, found.list = key, GetTime(), list
    return list
end

local function Matches(e)
    return boe and e and boe.bag == e.bag and boe.slot == e.slot and boe.id == e.id and boe.count == e.count
end

local function Ready(e)
    return Matches(e) and boe.step == "ready" and GetTime() - boe.at <= STALE
end

local function Busy()
    return boe and (boe.step == "searching" or boe.step == "posting") and GetTime() - boe.at < BUSY_TIMEOUT
end

function ns.BoEBusy()
    return Busy() and true or false
end

function ns.BoERows()
    local rows = {}
    local list = Find()
    rows[#rows + 1] = { header = "Post puts these up first, top first: your BoEs, and bought things that pay more "
        .. "at auction (" .. #list .. ")" }
    for i = 1, math.min(#list, 20) do
        local e = list[i]
        local name = (e.count > 1 and (e.count .. " ") or "") .. ns.ItemName(e.id) .. " (in your bags)"
        local vendor = ns.SellPrice(e.id) or 0
        if Ready(e) then
            rows[#rows + 1] = { name, "posts at " .. ns.Money(boe.unit) .. ", a vendor pays " .. ns.Money(vendor),
                sub = boe.basis .. "; deposit " .. ns.Money(boe.deposit), id = e.id }
        elseif e.estimate then
            local under = e.estimate * ns.CUT <= vendor
            rows[#rows + 1] = { name, "about " .. ns.Money(e.estimate) .. (under and ", under vendor price: skipped"
                or (", a vendor pays " .. ns.Money(vendor))), sub = e.basis, id = e.id }
        else
            rows[#rows + 1] = { name, e.basis, id = e.id }
        end
    end
    if #list == 0 then
        rows[#rows + 1] = { "No unbound BoEs in your bags, and nothing bought that pays more at auction." }
    end
    local any = false
    for id, h in pairs(held) do
        if not any then
            rows[#rows + 1] = { header = "BoEs left alone this session" }
            any = true
        end
        -- (the why on its own line under it: too long for the right-hand side)
        rows[#rows + 1] = { ns.ItemName(id), h.short, sub = h.why, id = id }
    end
    return rows
end

-- ---------- the look ----------
local function Hold(id, why, bought, short)
    held[id] = { why = why, short = bought and "back on the Sell list" or short or "not posted" }
    boe = nil
    found.key = nil
    -- (a bought one that doesn't pay at auction after all: back to Sell)
    if bought then ns.VendorIt(id, true) end
    ns.Say(ns.ItemName(id) .. ": " .. why .. (bought and " Back on the Sell list."
        or (" Left alone this session" .. (short and ("; " .. short) or "") .. ".")))
    ns.Changed()
    ns.Refresh()
end

local function Deposit(b)
    local duration = ns.Setting("duration")
    local ok, deposit
    if b.commodity then
        ok, deposit = pcall(AH.CalculateCommodityDeposit, b.id, duration, b.count)
    else
        ok, deposit = pcall(AH.CalculateItemDeposit, ItemLocation:CreateFromBagAndSlot(b.bag, b.slot), duration, b.count)
    end
    return ok and deposit or 0
end

local function OnLookedUp(ok, commodity, key)
    if not boe or boe.step ~= "searching" then return end
    local b = boe
    if not ok then
        failed[b.id] = GetTime()
        boe = nil
        ns.Say("The auction house didn't answer about " .. ns.ItemName(b.id) .. "; press Post to try again.")
        ns.Refresh()
        return
    end
    b.commodity, b.key = commodity, key
    local cheapest = ns.CheapestOther(b.id, commodity, key)
    local unit, basis
    if cheapest then
        unit, basis = math.floor(cheapest), "the same as the cheapest"
    else
        local estimate, why = Estimate(b.id, b.quality)
        if not estimate then
            Hold(b.id, "nobody lists it, and " .. why .. ".")
            return
        end
        unit, basis = estimate, "nobody lists it; " .. why
    end
    b.deposit = Deposit(b)
    local vendor = ns.SellPrice(b.id) or 0
    -- (what comes back, after the cut and with the deposit counted as gone, must be more than a vendor pays)
    local least = math.floor((vendor + b.deposit / b.count) / ns.CUT) + 1
    if unit < least then
        Hold(b.id, "it would sell for " .. ns.Money(unit) .. "; it needs " .. ns.Money(least) .. " to beat a vendor ("
            .. ns.Money(vendor) .. ") after the cut and deposit.", b.bought, "sell it to a vendor")
        return
    end
    b.unit, b.basis, b.step, b.at = unit, basis, "ready", GetTime()
    ns.Say("Press Post: " .. ns.ItemName(b.id) .. " at " .. ns.Money(unit) .. " (" .. basis .. "), deposit "
        .. ns.Money(b.deposit) .. ".")
    ns.Refresh()
end

-- A look at its listings (nothing posted). true: started.
local function LookUp(e)
    if ns.Searching() or ns.Scanning() or (ns.BuyBusy and ns.BuyBusy()) or (ns.PostBusy and ns.PostBusy()) then
        return false
    end
    local ok, key = pcall(AH.GetItemKeyFromItem, ItemLocation:CreateFromBagAndSlot(e.bag, e.slot))
    boe = { bag = e.bag, slot = e.slot, id = e.id, count = e.count, quality = e.quality, bought = e.bought,
        step = "searching", at = GetTime() }
    if not ns.Search(e.id, ok and key or nil, OnLookedUp) then
        boe = nil
        return false
    end
    ns.Refresh()
    return true
end

-- By itself, every few seconds at the auction house: the next one looked up, so a press posts it (only when it may
-- look by itself: AH.lua)
local function Tick()
    if not ns.LookByItself() or Busy() then return end
    if not active and not (ns.WindowTab and ns.WindowTab() == "post") then return end
    if ns.Searching() or ns.Scanning() then return end
    local top = Find()[1]
    if not top or Ready(top) then return end
    if failed[top.id] and GetTime() - failed[top.id] < RETRY_AFTER then return end
    LookUp(top)
end

-- ---------- the presses ----------
-- What Post would put up first, or nil (Queues.lua)
function ns.BoETop()
    return Find()[1]
end

function ns.BoECount()
    return #Find()
end

-- What a press does now for top (ns.BoETop()), as a sentence; nil with no BoE to post
function ns.BoELabel(top)
    if Busy() then return "Getting " .. ns.ItemName(boe.id) .. " ready...", false end
    if not top then return nil end
    local name = (top.count > 1 and (top.count .. " ") or "") .. ns.ItemName(top.id)
    if Ready(top) then
        return "Post " .. name .. " at " .. ns.Money(boe.unit) .. " (a vendor pays "
            .. ns.Money((ns.SellPrice(top.id) or 0) * top.count) .. ")", true
    end
    if not top.estimate then return "Look up the price of " .. name .. " (" .. top.basis .. ")", true end
    return "Look up the price of " .. name .. " (the next press posts it)", true
end

function ns.PostBoE()
    if not ns.Press("boe") then return end
    if not ns.at.auction then
        ns.Say("Post works at the auction house.")
        return
    end
    if Busy() or (ns.PostBusy and ns.PostBusy()) then
        ns.Say("Waiting for the auction house...")
        return
    end
    active = true
    local top = Find()[1]
    if not top then
        ns.Say("No unbound BoEs to post in your bags.")
        return
    end
    if not Ready(top) then
        -- a look first (nothing posted yet)
        if not LookUp(top) then ns.Say("The auction house is busy; press Post again in a moment.") end
        return
    end
    -- the post itself (the deposit is logged as what actually left your purse)
    local location = ItemLocation:CreateFromBagAndSlot(boe.bag, boe.slot)
    local duration = ns.Setting("duration")
    boe.money = GetMoney()
    local ok
    if boe.commodity then
        ok = ns.Ours(AH.PostCommodity, location, duration, boe.count, boe.unit)
    else
        ok = ns.Ours(AH.PostItem, location, duration, boe.count, nil, boe.unit * boe.count)
    end
    if ok then
        boe.step, boe.at = "posting", GetTime()
    else
        boe = nil
        ns.Say("The auction house wouldn't take that post.")
    end
    ns.Refresh()
end

-- Keeps the one Post would post next, for good: it's never posted (/qah keep lists them, /qah keep clear forgets)
function ns.KeepBoE()
    if not ns.Press("keep") then return end
    local top = Find()[1]
    if not top then
        ns.Say("No unbound BoE in your bags to keep.")
        return
    end
    Kept()[top.id] = true
    found.key = nil
    if Matches(top) then boe = nil end
    ns.Say(ns.ItemName(top.id) .. " is kept: Post never puts it up. (/qah keep lists what's kept.)")
    ns.Refresh()
end

-- /qah keep: lists what's kept; /qah keep clear: forgets them all; /qah keep <item link>: keeps it, or forgets it
function ns.KeepCommand(rest)
    local keep = Kept()
    local id = tonumber((rest or ""):match("item:(%d+)"))
    if rest == "clear" then
        ns.DB().keep = {}
        ns.Print("nothing is kept now: Post may post any BoE.")
    elseif id then
        keep[id] = not keep[id] or nil
        ns.Print(ns.ItemName(id) .. (keep[id] and " is kept: Post never puts it up." or " isn't kept any more."))
    else
        local names = {}
        for kept in pairs(keep) do names[#names + 1] = ns.ItemName(kept) end
        ns.Print(#names == 0 and "nothing is kept from Post." or ("kept from Post: " .. table.concat(names, ", ")
            .. ". (/qah keep <item link> forgets one, /qah keep clear all.)"))
    end
    found.key = nil
    ns.Refresh()
end

-- ---------- answers ----------
local ticker
ns.Listen("auctions", { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_SHOW_ERROR" },
function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        if not ticker and C_Timer.NewTicker then ticker = C_Timer.NewTicker(LOOK_EVERY, Tick) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if ticker then ticker:Cancel() end
        ticker, boe, active = nil, nil, false
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" and boe and boe.step == "posting" then
        local b = boe
        if arg then ns.Market().posted[arg] = b.unit end
        C_Timer.After(1, function()
            local paid = b.money - GetMoney()
            ns.Log("post", b.id, b.count, -(b.deposit or 0), -paid)
            ns.NotePost(b.id, b.count, b.unit, paid > 0 and paid or (b.deposit or 0), arg)
        end)
        ns.Say("Posted " .. ns.ItemName(b.id) .. " at " .. ns.Money(b.unit) .. ".")
        boe = nil
        ns.Changed()
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and boe and boe.step == "posting" then
        boe = nil
        ns.Say("The BoE post didn't go through.")
    end
    ns.Refresh()
end)
