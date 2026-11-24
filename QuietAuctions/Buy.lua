-- Buy (the press; once called Next): buys the top item on the list (Scan.lua). Everything that only looks is done
-- ahead, by itself, so that a press buys at once:
--   1. the top item is looked up (its listings now), and again when the look is a minute old
--   2. a commodity (ore, cloth, herbs...): the auction house is asked for the exact total of the ones under vendor
--      price (a price quote, which buys nothing; asked again when it runs out)
--   3. the press buys: the commodities at that total, or one plain auction at its buyout
-- A press while 1 or 2 is still under way does nothing but say so: a purchase only ever comes from a press, never
-- from a timer. If the game won't let an addon ask for a quote by itself, the press asks, and the next one buys.
-- The price is checked again at every step: if it has gone over what a vendor pays (less the margin), or the
-- profit is under the minimum (5c by default), nothing is bought. An item that can't be looked up goes to the bottom
-- of the list and the next one is looked up. The watch (Watch.lua) puts fresh finds on the list between scans.
-- What's bought is kept count of (QuietAuctionsCharDB.bought), so Sell (Vendor.lua) sells only that.
local _, ns = ...

local AH = C_AuctionHouse
local STALE = 60 -- (seconds before a look-up is old)
local BUSY_TIMEOUT = 15
local REQUOTES = 3 -- (quotes asked again by themselves when one runs out, before waiting for a press)

local buy -- { id, commodity, key, step, at, qty, cost, quote, list, bidding, requotes }
local autoQuote = true -- (false once the game has blocked a quote that wasn't from a press)

local function Reset(msg)
    buy = nil
    if msg then ns.Say(msg) end
    ns.Refresh()
end

local function Busy()
    return buy and (buy.step == "searching" or buy.step == "quoting" or buy.step == "buying")
        and GetTime() - buy.at < BUSY_TIMEOUT
end

-- ---------- what was bought ----------
-- returned: an auction of it came back unsold (Ledger.lua): on the list again, but no new spending
function ns.RecordBuy(id, qty, cost, returned)
    local char = ns.Char()
    local b = char.bought[id] or { n = 0, cost = 0 }
    b.n, b.cost = b.n + qty, b.cost + cost
    char.bought[id] = b
    -- (when: till the mailbox is next read, it's counted as on its way there; Whereabouts.lua)
    if not returned then
        b.at = time()
        char.totals.spent = (char.totals.spent or 0) + cost
    end
end

-- ---------- step 2: the price quote ----------
-- Asks the auction house for the exact total (buys nothing). byPress: from a press of Next.
local function Quote(byPress)
    if not buy or buy.step ~= "quote" then return end
    -- (by itself only when it may look by itself: a quote opens the auction house's purchase, which is yours to use)
    if not byPress and (not autoQuote or not ns.LookByItself()) then return end
    buy.step, buy.at = "quoting", GetTime()
    if not ns.Ours(AH.StartCommoditiesPurchase, buy.id, buy.qty) then
        buy.step = "quote"
        if byPress then ns.Say("The auction house wouldn't price " .. ns.ItemName(buy.id) .. ".") end
    end
    ns.Refresh()
end

-- ---------- step 1: look it up ----------
local Lookup

-- An item that couldn't be looked up: to the bottom of the list (pressing Next on it later tries again)
local function Skip(id, why)
    for i, c in ipairs(ns.candidates) do
        if c.id == id then
            table.remove(ns.candidates, i)
            c.failed = true
            ns.candidates[#ns.candidates + 1] = c
            break
        end
    end
    Reset(ns.ItemName(id) .. ": " .. why)
    C_Timer.After(0.5, ns.Prepare)
end

-- What could be bought now from the listings just read, under the price, within your gold, and worth it (at least
-- the minimum profit, /qah minprofit, 5c by default): a commodity's quantity and cost; a plain item's auctions, each
-- worth it on its own, best first. qty 0: nothing.
local function Buyable(id, commodity, key)
    local maxUnit = ns.MaxUnit(id)
    local vendor = ns.SellPrice(id) or 0
    local money = GetMoney()
    local least = ns.Setting("minProfit")
    if not maxUnit then return 0, 0 end
    if commodity then
        local cap = ns.Setting("stacks") * ns.StackSize(id)
        local qty, cost = 0, 0
        for _, r in ipairs(ns.CommodityRows(id)) do
            if r.unit > maxUnit or qty >= cap then break end
            local take = math.min(r.qty - r.own, cap - qty)
            if take > 0 and cost + take * r.unit > money then take = math.floor((money - cost) / r.unit) end
            if take <= 0 then break end
            qty, cost = qty + take, cost + take * r.unit
        end
        if vendor * qty - cost < least then return 0, 0 end
        return qty, cost
    end
    local list, qty, cost = {}, 0, 0
    for _, r in ipairs(ns.ItemRows(key)) do
        r.profit = vendor * r.qty - r.buyout
        if not r.own and r.unit <= maxUnit and r.buyout <= money and r.profit >= least then
            list[#list + 1] = r
            qty, cost = qty + r.qty, cost + r.buyout
        end
    end
    table.sort(list, function(a, b) return a.profit > b.profit end)
    return qty, cost, list
end

-- Its place on the list, with the numbers now known (put in where it belongs if it's new: the watch finds them)
local function SetCandidate(id, qty, cost, sort)
    local vendor = ns.SellPrice(id) or 0
    local c
    for _, e in ipairs(ns.candidates) do
        if e.id == id then c = e end
    end
    local new = c == nil
    if new then
        c = { id = id }
        ns.candidates[#ns.candidates + 1] = c
    end
    c.qty, c.cost, c.profit, c.estimate, c.failed = qty, cost, vendor * qty - cost, false, nil
    if sort then ns.SortCandidates() end
    return c, new
end

-- The look-up's answer: how many under the price now, what they cost
local function OnLookedUp(ok, commodity, key)
    if not buy or buy.step ~= "searching" then return end
    local id = buy.id
    if not ok then
        Skip(id, "the auction house didn't answer; on to the next (/qah trace says more).")
        return
    end
    commodity = commodity and ns.MayBeCommodity(id)
    buy.commodity, buy.key, buy.at = commodity, key, GetTime()
    local qty, cost, list = Buyable(id, commodity, key)
    if qty == 0 then
        ns.DropCandidate(id)
        Reset(ns.ItemName(id) .. ": nothing worth buying any more.")
        C_Timer.After(0.5, ns.Prepare)
        return
    end
    if commodity then
        buy.step, buy.qty, buy.cost, buy.requotes = "quote", qty, cost, 0
    else
        buy.step, buy.list = "ready", list
    end
    -- (the list's numbers, now that they're known; not sorted again, so this stays the top)
    SetCandidate(id, qty, cost, false)
    if commodity then Quote(false) end
    ns.Refresh()
end

-- A watch look (Watch.lua) at an item: on the list if it's worth buying now, off it if not. If it's the top of the
-- list now and nothing is under way, it's made ready to buy at once (priced, if a commodity).
function ns.TakeLookup(id, commodity, key)
    if buy and buy.id == id then return end -- (being got ready or bought: its own look stands)
    commodity = commodity and ns.MayBeCommodity(id)
    local qty, cost = Buyable(id, commodity, key)
    if qty == 0 then
        for _, c in ipairs(ns.candidates) do
            if c.id == id then
                ns.DropCandidate(id)
                break
            end
        end
        return
    end
    local before
    for _, c in ipairs(ns.candidates) do
        if c.id == id then before = c.profit end
    end
    local c = SetCandidate(id, qty, cost, true)
    if not before or c.profit > before then
        ns.Say("New under vendor price: " .. qty .. " " .. ns.ItemName(id) .. ", profit " .. ns.Money(c.profit) .. ".")
    end
    if ns.candidates[1] == c and not Busy() then
        if buy and buy.step == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
        buy = { id = id, step = "searching", at = GetTime() }
        OnLookedUp(true, commodity, key)
    end
    ns.Refresh()
end

function ns.BuyBusy()
    return Busy() and true or false
end

function Lookup(c)
    buy = { id = c.id, step = "searching", at = GetTime() }
    if not ns.Search(c.id, nil, OnLookedUp) then
        buy = nil
        return false
    end
    ns.Refresh()
    return true
end

-- The top of the list made ready ahead of the press (only looks: nothing is bought). Again when it's old. Kept so
-- by the watch's heartbeat (Watch.lua), and after each press; only when it may look by itself (AH.lua).
function ns.Prepare()
    if not ns.LookByItself() or Busy() or ns.Searching() or ns.Browsing() then return end
    local top = ns.candidates[1]
    -- (only skipped ones left: not looked up until a press asks)
    if not top or top.failed or ns.Skipped(top.id) then return end
    if buy and buy.id == top.id and GetTime() - buy.at < STALE then return end
    if buy and buy.step == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
    Lookup(top)
end

-- The margin or the stacks changed: the list again, and what was looked up under the old rules let go (a price
-- asked for too). The new top is looked up once the presses of Margin + / - have stopped for a moment.
local rulesTimer
function ns.BuyRulesChanged()
    if buy and (buy.step == "quoting" or buy.step == "confirm") then pcall(AH.CancelCommoditiesPurchase) end
    if buy and buy.step ~= "buying" then buy = nil end
    ns.BuildCandidates()
    if rulesTimer then rulesTimer:Cancel() end
    rulesTimer = C_Timer.NewTimer and C_Timer.NewTimer(1.5, ns.Prepare)
end

-- ---------- what a press of Buy does now ----------
-- As a sentence for the button, and whether a press does anything
local function Some(qty, name)
    return (qty > 1 and (qty .. " ") or "") .. name
end

function ns.BuyLabel()
    if not ns.at.auction then return "Buy: at the auction house", false end
    local top = ns.candidates[1]
    if not top then
        if ns.Scanning() then return "Scanning the auction house...", false end
        if ns.Market().scanNo > 0 then return "Nothing under vendor price right now (still watching)", false end
        return "Scan the auction house first", true
    end
    if ns.Browsing() then return "Reading the auction house's pages...", false end
    local name = ns.ItemName(top.id)
    local vendor = ns.SellPrice(top.id) or 0
    if buy and buy.id == top.id then
        if buy.step == "confirm" then
            return "Buy " .. Some(buy.qty, name) .. " for " .. ns.Money(buy.quote) .. " (a vendor pays "
                .. ns.Money(vendor * buy.qty) .. ")", true
        elseif buy.step == "ready" then
            local r = buy.list[1]
            return "Buy " .. Some(r.qty, name) .. " for " .. ns.Money(r.buyout) .. " (a vendor pays "
                .. ns.Money(vendor * r.qty) .. ")", true
        elseif buy.step == "quote" then
            return "Ask the price of " .. Some(buy.qty, name) .. " (the next press buys)", true
        elseif Busy() then
            return "Getting " .. name .. " ready...", false
        end
    end
    return "Look up " .. name .. (ns.Skipped(top.id) and " (skipped before; the next press buys)"
        or " (the next press buys)"), true
end

-- ---------- Skip this one ----------
-- The top of the list to the bottom until you log out or /reload, and the next one made ready. Buys nothing; a
-- price asked for it is let go. Not while a purchase is going through.
function ns.CanSkip()
    return ns.at.auction and ns.candidates[1] ~= nil and not ns.Browsing()
end

function ns.SkipTop()
    if not ns.Press("skip") then return end
    local top = ns.candidates[1]
    if not ns.at.auction or not top then
        ns.Say("Nothing to skip.")
        return
    end
    if buy and buy.step == "buying" and Busy() then
        ns.Say("Buying " .. ns.ItemName(buy.id) .. "; skip once it's through.")
        return
    end
    if buy and (buy.step == "quoting" or buy.step == "confirm") then pcall(AH.CancelCommoditiesPurchase) end
    buy = nil
    ns.SkipCandidate(top.id)
    ns.SortCandidates()
    local nextOne = ns.candidates[1]
    ns.Say("Skipped " .. ns.ItemName(top.id) .. " (until you log out; /qah unskip brings it back)."
        .. (nextOne and nextOne ~= top and (" Next: " .. ns.ItemName(nextOne.id) .. ".") or ""))
    ns.Refresh()
    C_Timer.After(0.5, ns.Prepare)
end

-- ---------- the press ----------
function ns.Next()
    if not ns.Press("next") then return end
    if not ns.at.auction then
        ns.Say("Buy works at the auction house.")
        return
    end
    local top = ns.candidates[1]
    if not top or ns.Browsing() then
        -- (nothing to buy: a full scan if it's allowed, else the watch keeps looking)
        if ns.Scanning() or ns.FullScanWait() > 0 and ns.Market().scanNo > 0 then
            ns.Say(ns.ScanStatus() .. (ns.WatchStatus and (" " .. ns.WatchStatus()) or ""))
        else
            ns.Scan(true)
        end
        return
    end
    local id = top.id
    if Busy() then
        ns.Say(buy.id == id and ("Getting " .. ns.ItemName(id) .. " ready; press again in a moment.")
            or "Waiting for the auction house...")
        return
    end
    local maxUnit = ns.MaxUnit(id)
    local ready = buy and buy.id == id and GetTime() - buy.at <= STALE
    if ready and buy.step == "confirm" then
        -- a commodity: buy at the total just quoted
        local left = AH.GetQuoteDurationRemaining and select(2, pcall(AH.GetQuoteDurationRemaining))
        if type(left) == "number" and left <= 0 then
            buy.step, buy.requotes = "quote", 0
            Quote(true)
            ns.Say("That price ran out; asking again. Press once more.")
        elseif buy.quote > GetMoney() then
            Reset("Not enough gold for that.")
        else
            buy.step, buy.at, buy.money = "buying", GetTime(), GetMoney()
            if not pcall(AH.ConfirmCommoditiesPurchase, id, buy.qty) then Reset("The purchase didn't go through.") end
        end
    elseif ready and buy.step == "ready" then
        -- a plain item: buy the best auction at its buyout
        local r = buy.list[1]
        if not maxUnit or r.unit > maxUnit or r.buyout > GetMoney() or r.profit < ns.Setting("minProfit") then
            Reset("The price no longer pays; looking again.")
            C_Timer.After(0.5, ns.Prepare)
            return
        end
        buy.step, buy.at, buy.bidding, buy.money = "buying", GetTime(), r, GetMoney()
        if not ns.Ours(AH.PlaceBid, r.auctionID, r.buyout) then Reset("The purchase didn't go through.") end
    elseif ready and buy.step == "quote" then
        -- (the game wouldn't let the quote be asked for by itself: this press asks, the next buys)
        Quote(true)
    else
        -- nothing ready (old, or never looked up): a look now; a press buys once it's in
        if buy and buy.step == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
        top.failed = nil
        if Lookup(top) then
            ns.Say("Looking up " .. ns.ItemName(id) .. "...")
        else
            ns.Say("The auction house is busy; press again in a moment.")
        end
    end
    ns.Refresh()
end

-- ---------- answers ----------
-- A purchase is counted by what actually left your purse (the gold before the press against the gold after), not
-- by the price we expected or by the auction house's events, which may not come: so the bought list and the totals
-- are real, and a purchase whose event never came is still counted (and sold on later). Logged (/qah log).
local function Bought(qty, spent, expected)
    local id = buy.id
    local vendor = ns.SellPrice(id) or 0
    ns.RecordBuy(id, qty, spent)
    ns.Log("buy", id, qty, -expected, -spent)
    ns.Say("Bought " .. qty .. " " .. ns.ItemName(id) .. " for " .. ns.Money(spent) .. " (a vendor pays "
        .. ns.Money(vendor * qty) .. "). It comes by mail."
        .. (spent > expected + 1 and (" It cost " .. ns.Money(spent - expected) .. " more than quoted!") or ""))
end

-- The purchase has gone through: counted, and the next made ready
local function Through(spent)
    if not buy or buy.step ~= "buying" or buy.counted then return end
    buy.counted = true
    if buy.commodity then
        Bought(buy.qty, spent, buy.quote)
        ns.DropCandidate(buy.id)
        Reset()
        C_Timer.After(0.5, ns.Prepare)
        return
    end
    local r = buy.bidding
    Bought(r.qty, spent, r.buyout)
    table.remove(buy.list, 1)
    buy.bidding, buy.counted = nil, nil
    for _, c in ipairs(ns.candidates) do
        if c.id == buy.id then
            c.qty, c.cost, c.profit = c.qty - r.qty, c.cost - r.buyout, c.profit - r.profit
        end
    end
    if #buy.list == 0 then
        ns.DropCandidate(buy.id)
        Reset()
        C_Timer.After(0.5, ns.Prepare)
    else
        buy.step, buy.at = "ready", GetTime()
    end
end

-- What left the purse since the press (0: nothing yet)
local function Spent()
    return buy and buy.money and math.max(0, buy.money - GetMoney()) or 0
end

-- The auction house says it went through: counted once the gold has left (a few seconds at most; if it never
-- does, at the price expected, and said so)
local function Succeeded()
    if not buy or buy.step ~= "buying" then return end
    if Spent() > 0 then
        Through(Spent())
        return
    end
    local mine = buy
    C_Timer.After(3, function()
        if buy == mine and buy.step == "buying" and not buy.counted then
            local expected = buy.commodity and buy.quote or (buy.bidding and buy.bidding.buyout) or 0
            ns.Say("The auction house said bought, but no gold has left your purse yet; counted at the price expected.")
            Through(Spent() > 0 and Spent() or expected)
        end
    end)
end

ns.Listen("auctions", { "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_CLOSED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_MONEY" },
function(_, event, a, b)
    if event == "AUCTION_HOUSE_CLOSED" then
        buy = nil
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- (the quote asked for by itself was refused: from now on a press asks for it)
        if a == "QuietAuctions" and tostring(b):find("StartCommoditiesPurchase") then
            autoQuote = false
            if buy and buy.step == "quoting" then buy.step = "quote" end
        end
        return
    end
    if not buy then return end
    if event == "COMMODITY_PRICE_UPDATED" and buy.step == "quoting" then
        -- The server's own price for one and for the lot must both pay, and the lot must cost what the listings
        -- said (within a tenth): a total far from that means it isn't the quantity we think, so nothing is bought.
        local unit, total = a or 0, b or 0
        local maxUnit = ns.MaxUnit(buy.id)
        local profit = (ns.SellPrice(buy.id) or 0) * buy.qty - total
        if maxUnit and unit > 0 and unit <= maxUnit and total > 0 and total <= buy.qty * maxUnit
            and math.abs(total - unit * buy.qty) <= buy.qty and math.abs(total - buy.cost) <= buy.cost * 0.1
            and total <= GetMoney() and profit >= ns.Setting("minProfit") then
            buy.step, buy.quote, buy.at = "confirm", total, GetTime()
            -- (asked again by itself when it runs out, a few times, so a press still buys at once)
            local left = AH.GetQuoteDurationRemaining and select(2, pcall(AH.GetQuoteDurationRemaining))
            local mine = buy
            if type(left) == "number" and left > 1 then
                C_Timer.After(left - 0.5, function()
                    if buy == mine and buy.step == "confirm" and (buy.requotes or 0) < REQUOTES then
                        buy.requotes = (buy.requotes or 0) + 1
                        buy.step = "quote"
                        Quote(false)
                    end
                end)
            end
        else
            pcall(AH.CancelCommoditiesPurchase)
            Reset("The price no longer pays; looking again.")
            C_Timer.After(0.5, ns.Prepare)
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" and buy.step == "quoting" then
        Reset("Those are gone; looking again.")
        C_Timer.After(0.5, ns.Prepare)
    elseif event == "PLAYER_MONEY" and buy.step == "buying" then
        -- (gold left the purse after a press: that's the purchase, whatever the events say)
        if Spent() > 0 then Through(Spent()) end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and buy.step == "buying" then
        Succeeded()
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" and buy.bidding and a == buy.bidding.auctionID then
        Succeeded()
    elseif (event == "COMMODITY_PURCHASE_FAILED" or event == "AUCTION_HOUSE_SHOW_ERROR") and buy.step == "buying" then
        if Spent() > 0 then
            Through(Spent()) -- (it said no, but the gold went: counted, so it's sold on later)
        else
            Reset("Someone was quicker; looking again.")
            C_Timer.After(0.5, ns.Prepare)
        end
    end
    ns.Refresh()
end)
