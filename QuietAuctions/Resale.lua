-- Buy for resale: gear listed well under what it usually sells for at auction, bought to put up again (Post).
-- This carries risk, unlike Next's buys under vendor price: the usual price is a guess from the scans, a piece can
-- come with a different suffix or item level than the ones remembered, and it may not sell. So it's a list and a
-- list of its own, off until you turn it on (Settings tab, or /qah resale on), and then last in the Buy queue
-- (Queues.lua), after everything under vendor price. Only with:
--   * at least 4 scans that saw the item, so one odd listing doesn't make a usual price
--   * a buyout at most 70% of what it usually brings after the cut and a deposit, and more than a vendor pays for it
--   * a profit, if it sells, of at least 50c (or your minimum, if more)
-- One press looks it up (the top is looked up by itself while the Buy tab is shown, and it may look by itself:
-- AH.lua), the next buys one auction.
-- Bought ones go on the bought list marked for resale: Post puts them up, and only if one comes back unsold
-- twice does Sell take it to a vendor (Ledger.lua).
local _, ns = ...

local AH = C_AuctionHouse
local SIGHTINGS = 4
local UNDER = 0.7
local LEAST = 50
local GEAR = { [2] = true, [4] = true } -- (weapons, armour)
local STALE = 60
local BUSY_TIMEOUT = 10
local LOOK_EVERY = 1
local SHOWN = 15

local list, builtVersion, builtAt = {}, -1, 0
local buy -- { id, step, at, row, money, counted }
local failed = {} -- [itemID] = when its look found nothing (left alone a while)

local function ForResale()
    local char = ns.Char()
    char.forResale = char.forResale or {}
    return char.forResale
end

-- What one usually brings at auction, after the cut and a deposit (nil: not seen often enough)
local function Brings(id)
    local usual, seen = ns.Usual(id)
    if not usual or seen < SIGHTINGS then return nil end
    return usual * ns.CUT - ns.DepositGuess(id)
end
-- The most to pay for one: nil if it isn't worth buying for resale at all
local function Ceiling(id)
    local back = Brings(id)
    local vendor = ns.SellPrice(id) or 0
    if not back or back <= vendor then return nil end
    return math.min(back * UNDER, back - math.max(LEAST, ns.Setting("minProfit"))), back
end

local function Build()
    local found = {}
    local money = GetMoney()
    local class = ns.DB().class
    for id, r in pairs(ns.LastRows and ns.LastRows() or {}) do
        if GEAR[class[id] or 0] and not (failed[id] and GetTime() - failed[id] < 300) then
            local ceiling, back = Ceiling(id)
            if ceiling then
                local best
                for i = 1, #r.counts do
                    local buyout = r.buyouts[i]
                    if r.counts[i] == 1 and buyout <= ceiling and buyout <= money and (not best or buyout < best) then
                        best = buyout
                    end
                end
                if best then found[#found + 1] = { id = id, cost = best, back = back, profit = back - best } end
            end
        end
    end
    table.sort(found, function(a, b) return a.profit > b.profit end)
    list, builtVersion, builtAt = found, ns.version, GetTime()
end

local function List()
    if builtVersion ~= ns.version or GetTime() - builtAt > 60 then Build() end
    return list
end

local function Drop(id)
    for i, c in ipairs(list) do
        if c.id == id then
            table.remove(list, i)
            return
        end
    end
end

local function Busy()
    return buy and (buy.step == "searching" or buy.step == "buying") and GetTime() - buy.at < BUSY_TIMEOUT
end

local function Ready(c)
    return buy and c and buy.id == c.id and buy.step == "ready" and GetTime() - buy.at <= STALE
end

function ns.ResaleOn()
    return ns.Setting("resale") and true or false
end

function ns.ResaleTop()
    return ns.ResaleOn() and List()[1] or nil
end

-- Off: the heading alone (the list folded away, so it's never mistaken for the safe buys)
function ns.ResaleRows()
    local rows = {}
    if not ns.ResaleOn() then
        rows[#rows + 1] = { header = "To resell, risky: off (the Settings tab turns it on)" }
        return rows
    end
    local shown = List()
    rows[#rows + 1] = { header = "To resell, risky: Buy gets these last (" .. #shown .. ")" }
    for i = 1, math.min(#shown, SHOWN) do
        local c = shown[i]
        local r = Ready(c) and buy.row
        local cost = r and r.buyout or c.cost
        rows[#rows + 1] = { ns.ItemName(c.id) .. " (auction house)", "costs " .. ns.Money(cost) .. ", sells for ~"
            .. ns.Money(ns.Usual(c.id) or 0) .. ": +" .. ns.Money(c.back - cost) .. " if it sells", id = c.id }
    end
    if #shown == 0 then
        rows[#rows + 1] = { "Nothing listed well under its usual price (it needs 4 scans that saw the item)." }
    end
    return rows
end

-- ---------- the look ----------
local function OnLookedUp(ok, _, key)
    if not buy or buy.step ~= "searching" then return end
    local id = buy.id
    local ceiling = Ceiling(id)
    local row
    if ok and ceiling then
        for _, r in ipairs(ns.ItemRows(key)) do
            if not r.own and r.qty == 1 and r.buyout <= ceiling and r.buyout <= GetMoney() then
                row = r
                break
            end
        end
    end
    if not row then
        failed[id] = GetTime()
        Drop(id)
        buy = nil
        ns.Say(ns.ItemName(id) .. ": " .. (ok and "none listed under the resale price now." or "no answer.")
            .. " Off the resale list a while.")
        ns.Refresh()
        return
    end
    buy.step, buy.row, buy.at = "ready", row, GetTime()
    ns.Refresh()
end

local function LookUp(c)
    if ns.Searching() or ns.Scanning() or ns.BuyBusy() or (ns.PostBusy and ns.PostBusy())
        or (ns.BoEBusy and ns.BoEBusy()) then
        return false
    end
    buy = { id = c.id, step = "searching", at = GetTime() }
    if not ns.Search(c.id, nil, OnLookedUp) then
        buy = nil
        return false
    end
    ns.Refresh()
    return true
end

-- By itself while the Buy tab is shown at the auction house: the top looked up, so a press buys
local function Tick()
    if not ns.ResaleOn() then return end
    if not ns.LookByItself() or Busy() or ns.Searching() or ns.Scanning() then return end
    if not (ns.WindowTab and ns.WindowTab() == "buy") then return end
    local top = List()[1]
    if top and not Ready(top) then LookUp(top) end
end

-- ---------- the press ----------
-- What a press does now, as a sentence
function ns.ResaleLabel()
    if not ns.at.auction then return "Buy: at the auction house", false end
    local top = List()[1]
    if not top then return "Nothing to resell", false end
    local name = ns.ItemName(top.id)
    if Busy() then return "Getting " .. name .. " ready...", false end
    local usual = " (usually sells for ~" .. ns.Money(ns.Usual(top.id) or 0) .. ")"
    if Ready(top) then
        return "Buy " .. name .. " for " .. ns.Money(buy.row.buyout) .. " to resell, risky" .. usual, true
    end
    return "Look up " .. name .. " to resell, risky" .. usual, true
end

function ns.BuyResale()
    if not ns.Press("resale") then return end
    if not ns.ResaleOn() then
        ns.Say("Buying to resell is off (the Settings tab turns it on).")
        return
    end
    if not ns.at.auction then
        ns.Say("Buy works at the auction house.")
        return
    end
    if Busy() or ns.BuyBusy() then
        ns.Say("Waiting for the auction house...")
        return
    end
    local top = List()[1]
    if not top then
        ns.Say("Nothing on the resale list.")
        return
    end
    if not Ready(top) then
        if LookUp(top) then
            ns.Say("Looking up " .. ns.ItemName(top.id) .. "...")
        else
            ns.Say("The auction house is busy; press again in a moment.")
        end
        return
    end
    -- (the price checked once more, then one auction bought at its buyout)
    local r = buy.row
    local ceiling = Ceiling(top.id)
    if not ceiling or r.buyout > ceiling or r.buyout > GetMoney() then
        buy = nil
        ns.Say("That price no longer pays; looking again.")
        ns.Refresh()
        return
    end
    buy.step, buy.at, buy.money = "buying", GetTime(), GetMoney()
    if not ns.Ours(AH.PlaceBid, r.auctionID, r.buyout) then
        buy = nil
        ns.Say("The purchase didn't go through.")
    end
    ns.Refresh()
end

-- ---------- answers ----------
-- Counted by what left your purse, as Next's buys are (Buy.lua)
local function Through(spent)
    if not buy or buy.step ~= "buying" or buy.counted then return end
    buy.counted = true
    local id, r = buy.id, buy.row
    ns.RecordBuy(id, 1, spent)
    ForResale()[id] = true
    ns.Log("buy resale", id, 1, -r.buyout, -spent)
    ns.Say("Bought " .. ns.ItemName(id) .. " for resale: " .. ns.Money(spent) .. " (usually brings "
        .. ns.Money(Brings(id) or 0) .. " after fees). It comes by mail; Post puts it up.")
    Drop(id)
    buy = nil
end

local function Spent()
    return buy and buy.money and math.max(0, buy.money - GetMoney()) or 0
end

local ticker
ns.Listen("auctions", { "PLAYER_MONEY", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        if not ticker and C_Timer.NewTicker then ticker = C_Timer.NewTicker(LOOK_EVERY, Tick) end
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if ticker then ticker:Cancel() end
        ticker, buy = nil, nil
        return
    end
    if not buy or buy.step ~= "buying" then return end
    if event == "PLAYER_MONEY" then
        if Spent() > 0 then Through(Spent()) end
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" and buy.row and arg == buy.row.auctionID then
        local mine = buy
        C_Timer.After(3, function()
            if buy == mine and not buy.counted then Through(Spent() > 0 and Spent() or buy.row.buyout) end
        end)
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if Spent() > 0 then
            Through(Spent())
        else
            buy = nil
            ns.Say("Someone was quicker.")
        end
    end
    ns.Refresh()
end)
