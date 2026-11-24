-- Posting and cancelling, a press at a time, and only where the price memory says it pays.
--
-- Post: the stacks in your bags whose item sells well (Prices.lua: listed in most scans, usually well over vendor
-- price). Never gear or bags (nothing you could wear), never soulbound things. A press looks the item up, the next
-- posts one stack at the cheapest listing's price (not under it: of the ones at the same price, the auction house
-- sells the newest first, so a match puts yours at the front), but never under the floor:
--   vendor price + the floor setting (25%), allowing for the 5% cut, and never under 70% of its usual price.
-- If the cheapest is under the floor, or the deposit (the game works it out from the vendor price) would eat what
-- posting gains over selling to a vendor, it says so and leaves that item alone this session.
--
-- Cancel: reads your auctions, looks each one up in turn, and a press cancels one that someone lists for less than
-- yours (the same price doesn't count: reposting at it gains nothing). The deposit is lost, the item comes back by
-- mail.
local _, ns = ...

local AH = C_AuctionHouse
local STALE = 60
local BUSY_TIMEOUT = 10
local USUAL_FLOOR = 0.7

local post -- { bag, slot, id, count, commodity, key, step, at, unit, deposit }
local held = {} -- [itemID] = why it isn't posted (this session)

-- ---------- what to post ----------
local function Floor(id, usual)
    local vendor = ns.SellPrice(id) or 0
    local overVendor = math.ceil(vendor * (1 + ns.Setting("floor") / 100) / ns.CUT)
    return math.max(overVendor, math.floor(usual * USUAL_FLOOR), 1)
end

-- The game would take it at the auction house (BoE.lua asks too)
function ns.CanSell(bag, slot)
    if not (AH and AH.IsSellItemValid and ItemLocation) then return false end
    local ok, valid = pcall(function()
        return AH.IsSellItemValid(ItemLocation:CreateFromBagAndSlot(bag, slot), false)
    end)
    return ok and valid
end

-- The stacks to post, the most valuable first: { { bag, slot, id, count, usual } } (the window asks each second:
-- kept until the bags or the price memory change, or a few seconds pass)
local KEEP_FOR = 5
local found = { at = 0 }
local function ToPost()
    local key = ns.bagVersion .. ":" .. ns.version .. ":" .. tostring(ns.at.auction)
    if found.key == key and GetTime() - found.at < KEEP_FOR then return found.list end
    local worth = {}
    for _, e in ipairs(ns.SellsWell()) do worth[e.id] = e.usual end
    local list = {}
    ns.EachSlot(function(bag, slot, info)
        local id = info.itemID
        local usual = worth[id]
        if not usual or held[id] or info.isBound then return end
        local name, _, _, _, _, equipLoc = ns.ItemInfo(id)
        if not name or (equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE") then return end
        if not ns.CanSell(bag, slot) then return end
        list[#list + 1] = { bag = bag, slot = slot, id = id, count = info.stackCount or 1, usual = usual }
    end)
    table.sort(list, function(a, b) return a.usual * a.count > b.usual * b.count end)
    found.key, found.at, found.list = key, GetTime(), list
    return list
end

function ns.PostRows()
    local rows = {}
    local list = ToPost()
    rows[#rows + 1] = { header = ns.Setting("posting") and ("Then these stacks, top first (" .. #list .. ")")
        or ("Stacks worth posting (" .. #list .. "): posting stacks is off, the Settings tab turns it on") }
    for i = 1, math.min(#list, 30) do
        local e = list[i]
        rows[#rows + 1] = { e.count .. " " .. ns.ItemName(e.id) .. " (in your bags)", "about " .. ns.Money(e.usual)
            .. " each, never under " .. ns.Money(Floor(e.id, e.usual)), id = e.id }
    end
    if #list == 0 then
        rows[#rows + 1] = { "Nothing in your bags sells well enough yet (the Prices tab shows what does)." }
    end
    local any = false
    for id, why in pairs(held) do
        if not any then
            rows[#rows + 1] = { header = "Left alone this session" }
            any = true
        end
        rows[#rows + 1] = { ns.ItemName(id), "not posted", sub = why, id = id }
    end
    return rows
end

-- ---------- Post ----------
local function Busy()
    return post and (post.step == "searching" or post.step == "posting") and GetTime() - post.at < BUSY_TIMEOUT
end

function ns.PostBusy()
    return Busy() and true or false
end

local function Hold(id, why)
    held[id] = why
    post = nil
    found.key = nil
    ns.Say(ns.ItemName(id) .. ": " .. why .. " Left alone this session.")
end

local function Deposit(p)
    local duration = ns.Setting("duration")
    local ok, deposit
    if p.commodity then
        ok, deposit = pcall(AH.CalculateCommodityDeposit, p.id, duration, p.count)
    else
        ok, deposit = pcall(AH.CalculateItemDeposit, ItemLocation:CreateFromBagAndSlot(p.bag, p.slot), duration, p.count)
    end
    return ok and deposit or 0
end

local function OnLookedUp(ok, commodity, key)
    if not post or post.step ~= "searching" then return end
    local p = post
    if not ok then
        post = nil
        ns.Say("The auction house didn't answer; press Post to try again (/qah trace says more).")
        ns.Refresh()
        return
    end
    -- (posted as what the auction house answered it is: a commodity, or a plain item under that key)
    p.commodity, p.key = commodity, key
    local floor = Floor(p.id, p.usual)
    local cheapest = ns.CheapestOther(p.id, p.commodity, p.key)
    -- (the cheapest's own price: the newest at a price sells first, so it needn't be beaten)
    local unit = cheapest and math.floor(cheapest) or p.usual
    if unit < floor then
        Hold(p.id, "the cheapest is " .. ns.Money(cheapest or 0) .. ", under your floor of " .. ns.Money(floor) .. ".")
        ns.Refresh()
        return
    end
    p.unit = unit
    p.deposit = Deposit(p)
    local gain = (unit * ns.CUT - (ns.SellPrice(p.id) or 0)) * p.count
    if p.deposit >= gain then
        Hold(p.id, "the deposit (" .. ns.Money(p.deposit) .. ") would eat the gain over a vendor ("
            .. ns.Money(gain) .. ").")
        ns.Refresh()
        return
    end
    p.step, p.at = "ready", GetTime()
    ns.Say("Press Post again: " .. p.count .. " " .. ns.ItemName(p.id) .. " at " .. ns.Money(unit) .. " each"
        .. (cheapest and "" or " (nobody else lists it)") .. ", deposit " .. ns.Money(p.deposit) .. ".")
    ns.Refresh()
end

-- What a press does now, as a sentence; nil with nothing to post (or posting stacks off)
function ns.PostLabel()
    if not ns.Setting("posting") then return nil end
    if Busy() then return "Getting " .. ns.ItemName(post.id) .. " ready...", false end
    if post and post.step == "ready" then
        return "Post " .. post.count .. " " .. ns.ItemName(post.id) .. " at " .. ns.Money(post.unit) .. " each", true
    end
    local top = ToPost()[1]
    if not top then return nil end
    return "Look up the price of " .. top.count .. " " .. ns.ItemName(top.id) .. " (the next press posts them)", true
end

function ns.Post()
    if not ns.Press("post") then return end
    -- (off until asked for: a post costs a deposit, lost if it doesn't sell)
    if not ns.Setting("posting") then
        ns.Say("Posting stacks is off (the Settings tab turns it on).")
        return
    end
    if not ns.at.auction then
        ns.Say("Post works at the auction house.")
        return
    end
    if Busy() or ns.Searching() or ns.Scanning() or ns.BoEBusy() then
        ns.Say("Waiting for the auction house...")
        return
    end
    local list = ToPost()
    local top = list[1]
    if not top then
        ns.Say("Nothing in your bags is worth posting yet (the Prices tab shows what sells well).")
        return
    end
    local same = post and post.bag == top.bag and post.slot == top.slot and post.id == top.id
        and post.count == top.count
    if not same or post.step ~= "ready" or GetTime() - post.at > STALE then
        -- a look first (nothing posted yet), by the stack's own key
        local ok, key = pcall(AH.GetItemKeyFromItem, ItemLocation:CreateFromBagAndSlot(top.bag, top.slot))
        post = { bag = top.bag, slot = top.slot, id = top.id, count = top.count, usual = top.usual,
            step = "searching", at = GetTime() }
        if not ns.Search(top.id, ok and key or nil, OnLookedUp) then
            post = nil
            ns.Say("The auction house is busy; press Post again in a moment.")
        end
        ns.Refresh()
        return
    end
    -- the post itself (the deposit is logged as what actually left your purse)
    local location = ItemLocation:CreateFromBagAndSlot(post.bag, post.slot)
    local duration = ns.Setting("duration")
    post.money = GetMoney()
    local ok
    if post.commodity then
        ok = ns.Ours(AH.PostCommodity, location, duration, post.count, post.unit)
    else
        ok = ns.Ours(AH.PostItem, location, duration, post.count, nil, post.unit * post.count)
    end
    if ok then
        post.step, post.at = "posting", GetTime()
    else
        post = nil
        ns.Say("The auction house wouldn't take that post.")
    end
    ns.Refresh()
end

-- ---------- Cancel ----------
-- { list = { { auctionID, id, unit, commodity, key } }, at, checked = { [auctionID] = true }, undercut, step }
local cancel

local function Owned()
    local list = {}
    local ok, n = pcall(AH.GetNumOwnedAuctions)
    local posted = ns.Market().posted
    -- (what each was posted at is kept only while it's up: the rest, sold or gone, forgotten)
    local up = {}
    for i = 1, (ok and n) or 0 do
        local got, a = pcall(AH.GetOwnedAuctionInfo, i)
        if got and type(a) == "table" and a.auctionID then up[a.auctionID] = true end
    end
    if ok and type(n) == "number" then
        for auctionID in pairs(posted) do
            if not up[auctionID] then posted[auctionID] = nil end
        end
    end
    for i = 1, (ok and n) or 0 do
        local got, a = pcall(AH.GetOwnedAuctionInfo, i)
        if got and type(a) == "table" and a.status == 0 and a.auctionID and a.itemKey and (a.buyoutAmount or 0) > 0 then
            local id = a.itemKey.itemID
            local commodity = ns.IsCommodity(id)
            local qty = math.max(1, a.quantity or 1)
            -- (the price for one: as posted here, else a commodity's is for one already, an item's for the lot)
            local unit = posted[a.auctionID] or (commodity and a.buyoutAmount or a.buyoutAmount / qty)
            list[#list + 1] = { auctionID = a.auctionID, id = id, unit = unit, commodity = commodity and true or false,
                key = a.itemKey, qty = qty }
        end
    end
    return list
end

-- Looks up the next of your auctions not checked yet (only a look); stops at one someone lists for less
local function CheckNext()
    if not cancel or cancel.undercut or not ns.at.auction then return end
    local a
    for _, e in ipairs(cancel.list) do
        if not cancel.checked[e.auctionID] then
            a = e
            break
        end
    end
    if not a then
        cancel.step = "done"
        ns.Say("Nobody lists for less than any of your " .. #cancel.list .. " auctions.")
        ns.Refresh()
        return
    end
    -- (an item looked up a moment ago for another auction of yours: its answer stands)
    cancel.step = "searching"
    local started = ns.Search(a.id, a.key, function(ok, commodity, key)
        if not cancel then return end
        cancel.step = nil
        for _, e in ipairs(cancel.list) do
            if e.id == a.id then
                cancel.checked[e.auctionID] = true
                local cheapest = ok and ns.CheapestOther(e.id, commodity, key)
                if cheapest and cheapest < e.unit and not cancel.undercut then
                    e.cheapest = cheapest
                    cancel.undercut = e
                end
            end
        end
        if cancel.undercut then
            local u = cancel.undercut
            ns.Say("Someone lists " .. ns.ItemName(u.id) .. " for less: yours " .. ns.Money(u.unit) .. ", theirs "
                .. ns.Money(u.cheapest) .. ". Press again to take yours down (the deposit is lost).")
            ns.Refresh()
        else
            C_Timer.After(1, CheckNext)
        end
    end)
    if not started then
        cancel.step = nil
        C_Timer.After(1, CheckNext)
    end
    ns.Refresh()
end

-- What a press of "Take down auctions listed for less" does now, as a sentence
function ns.CancelLabel()
    if not ns.at.auction then return "Take down auctions others list for less: at the auction house", false end
    if cancel and cancel.undercut then
        local u = cancel.undercut
        return "Take down " .. ns.ItemName(u.id) .. " (yours " .. ns.Money(u.unit) .. ", theirs "
            .. ns.Money(u.cheapest) .. "; the deposit is lost)", true
    end
    if cancel and (cancel.step == "owned" or cancel.step == "searching") then
        return "Checking whether anyone lists your auctions for less...", false
    end
    if cancel and cancel.step == "done" then
        return "Nobody lists for less than your auctions (press to check again)", true
    end
    return "Check whether anyone lists your auctions for less (the next press takes one down)", true
end

-- Worth showing that button: you have auctions up (that we know of), or a check is under way
function ns.HasAuctions()
    if cancel then return true end
    if #(ns.Char().auctions or {}) > 0 then return true end
    local ok, n = pcall(AH.GetNumOwnedAuctions)
    return ok and type(n) == "number" and n > 0
end

function ns.CancelNext()
    if not ns.Press("cancel") then return end
    if not ns.at.auction then
        ns.Say("Cancel works at the auction house.")
        return
    end
    if cancel and cancel.step == "cancelling" and GetTime() - cancel.at < BUSY_TIMEOUT then
        ns.Say("Cancelling...")
        return
    end
    if cancel and cancel.undercut then
        local u = cancel.undercut
        cancel.money = GetMoney()
        if ns.Ours(AH.CancelAuction, u.auctionID) then
            cancel.step, cancel.at = "cancelling", GetTime()
        else
            ns.Say("The auction house wouldn't cancel that.")
        end
        ns.Refresh()
        return
    end
    if cancel and (cancel.step == "owned" or cancel.step == "searching") and GetTime() - cancel.at < BUSY_TIMEOUT then
        ns.Say("Checking your auctions...")
        return
    end
    -- (a look at your auctions; the check of each follows by itself)
    cancel = { list = {}, checked = {}, step = "owned", at = GetTime() }
    if not ns.Ours(AH.QueryOwnedAuctions, {}) then
        cancel = nil
        ns.Say("The auction house wouldn't show your auctions.")
    end
    ns.Refresh()
end

-- ---------- answers ----------
ns.Listen("auctions", { "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_SHOW_ERROR", "OWNED_AUCTIONS_UPDATED",
    "AUCTION_CANCELED", "AUCTION_HOUSE_CLOSED" },
function(_, event, arg)
    if event == "AUCTION_HOUSE_CLOSED" then
        post, cancel = nil, nil
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" and post and post.step == "posting" then
        if arg then ns.Market().posted[arg] = post.unit end
        local p = post
        C_Timer.After(1, function()
            local paid = p.money - GetMoney()
            ns.Log("post", p.id, p.count, -(p.deposit or 0), -paid)
            ns.NotePost(p.id, p.count, p.unit, paid > 0 and paid or (p.deposit or 0), arg)
        end)
        ns.Say("Posted " .. post.count .. " " .. ns.ItemName(post.id) .. " at " .. ns.Money(post.unit) .. " each.")
        post = nil
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and post and post.step == "posting" then
        post = nil
        ns.Say("The post didn't go through.")
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and cancel and cancel.step == "cancelling" then
        cancel.step = nil
        ns.Say("That auction didn't come down; press again to try again.")
    elseif event == "OWNED_AUCTIONS_UPDATED" and cancel and cancel.step == "owned" then
        cancel.list, cancel.step = Owned(), nil
        if #cancel.list == 0 then
            cancel.step = "done"
            ns.Say("You have no auctions up.")
        else
            C_Timer.After(0.5, CheckNext)
        end
    elseif event == "AUCTION_CANCELED" and cancel and cancel.undercut and arg == cancel.undercut.auctionID then
        local u, money = cancel.undercut, cancel.money or GetMoney()
        C_Timer.After(1, function() ns.Log("cancel", u.id, u.qty, 0, GetMoney() - money) end)
        ns.NoteCancel(arg)
        ns.Say("Took down " .. ns.ItemName(cancel.undercut.id) .. "; it comes back by mail. Checking the rest...")
        ns.Market().posted[arg] = nil
        cancel.undercut, cancel.step = nil, nil
        C_Timer.After(1, CheckNext)
    end
    ns.Refresh()
end)
