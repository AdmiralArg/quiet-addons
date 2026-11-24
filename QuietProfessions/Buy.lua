-- Quick buying: a material on the To buy list bought with two presses, without leaving the window.
--
-- Only for what the auction house sells by quantity (ore, bars, stone, cloth: "commodities"), and only ever from a
-- press of yours:
--   1. the first press looks the item up (its listings now) and asks the auction house what exactly that many
--      would cost. Asking buys nothing. The button then reads Pay, with the house's own total beside it.
--   2. the second press pays that total. If the game won't let an addon ask for the price by itself, a press in
--      between asks (the button reads Price).
-- What can't go wrong by itself:
--  * never an item that doesn't stack, or that the auction house doesn't itself call a commodity (a plan, a piece
--    of gear: those are opened on the game's own page instead, as Find does). Taking a plan for a commodity once
--    bought one at a thousand times its price, in another addon: so both are checked, every time.
--  * the house's total must be what its listings just read add up to (within a twentieth), and its price for one
--    times the count must be that same total: if it isn't the quantity we think, nothing is bought.
--  * never more than three times what the route reckoned; over a quarter more, the line says so before you pay.
--  * a purchase is counted by the gold that left your purse, and what's bought counts as yours (on its way by
--    mail) until you've been to a mailbox, so it isn't bought twice.
local _, ns = ...

local AH = C_AuctionHouse
local Plain, Call = ns.Plain, ns.Call

local LOOK_WAIT, QUOTE_WAIT, BUY_WAIT = 5, 8, 15 -- seconds for each answer
local MATCH = 0.05      -- the house's total against its listings: this close, or nothing is bought
local DEARER = 1.25     -- over the route's reckoning by this much: said before you pay
local REFUSE = 3        -- over it by this much: not bought here at all
local PENDING_DAYS = 2  -- a purchase not seen at a mailbox by then is forgotten

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local buy -- { id, qty, each (the route's price for one), step, at, expected, unit, total, money }
local blocked = false -- (true once the game refused a price asked without a press)

ns.pendingVersion = 0

local function Refresh()
    if ns.RefreshWindow then ns.RefreshWindow() end
end

local function Reset(msg)
    if buy and (buy.step == "confirm" or buy.step == "quoting") then pcall(AH.CancelCommoditiesPurchase) end
    buy = nil
    if msg then QuietKit.Toast("Quiet Professions: " .. msg) end
    Refresh()
end

-- ---------- what's bought and on its way ----------
-- (On a character buying for another of yours it's the same: what's bought counts as here, and the Mail tab says
-- it's coming to the mailbox.)
local function Pending()
    local me = ns.Me()
    if not me then return {} end
    me.pending = me.pending or {}
    return me.pending
end

-- How many of an item were bought here and haven't been seen at a mailbox yet
function ns.OnItsWay(id)
    local p = Pending()[id]
    if not p then return 0 end
    if time() - p.at > PENDING_DAYS * 86400 then
        Pending()[id] = nil
        return 0
    end
    return p.n
end

local function NoteBought(id, qty)
    local pending = Pending()
    local p = pending[id] or { n = 0 }
    p.n, p.at = p.n + qty, time()
    pending[id] = p
    -- (and the listings bought are gone from the ones remembered)
    local looked = ns.Market().looked[id]
    local left = qty
    while looked and left > 0 and #looked.r >= 2 do
        local take = math.min(left, looked.r[2])
        looked.r[2], left = looked.r[2] - take, left - take
        if looked.r[2] <= 0 then
            table.remove(looked.r, 1)
            table.remove(looked.r, 1)
        end
    end
    ns.pendingVersion = ns.pendingVersion + 1
    ns.Changed()
end

-- At a mailbox: what was bought is there to be taken (Quiet Bags counts the mailbox from now)
local function SeenMailbox()
    local pending, any = Pending(), false
    for id, p in pairs(pending) do
        if time() - p.at > 10 then
            pending[id], any = nil, true
        end
    end
    if any then
        ns.pendingVersion = ns.pendingVersion + 1
        ns.Changed()
    end
end

-- ---------- may it be bought by a press? ----------
-- Only what stacks and the auction house doesn't call a plain item; at the auction house, out of a fight
function ns.CanQuickBuy(id)
    if not (AH and AH.StartCommoditiesPurchase and AH.ConfirmCommoditiesPurchase and AH.SendSearchQuery) then return false end
    if not ns.AtAuction() then return false end
    local stack = tonumber(Plain(select(8, Call(GetInfo, id))))
    if not stack or stack <= 1 then return false end
    return ns.AuctionKind(id) ~= "item"
end

-- Where a purchase of this item stands: nil, or its step ("looking", "quoting", "quote": a press asks the price,
-- "confirm": a press pays, "buying") and the purchase { qty, unit, total, each }
function ns.QuickBuyState(id)
    if buy and buy.id == id then return buy.step, buy end
    return nil
end

-- ---------- the steps ----------
local function Quote()
    if not buy then return end
    buy.step, buy.at = "quoting", GetTime()
    local mine = buy
    if not pcall(AH.StartCommoditiesPurchase, buy.id, buy.qty) then buy.step = "quote" end
    C_Timer.After(QUOTE_WAIT, function()
        -- (no answer: a press asks again)
        if buy == mine and buy.step == "quoting" then
            buy.step = "quote"
            Refresh()
        end
    end)
    Refresh()
end

-- The listings are in: how many of them, and what they add up to
local function OnListings()
    if not buy or buy.step ~= "looking" then return end
    local id = buy.id
    -- (the auction house itself must call it a commodity by now: else its own page)
    if ns.AuctionKind(id) ~= "commodity" then
        local qty = buy.qty
        Reset()
        ns.ShowAtAuction(id, qty)
        return
    end
    local rows = ns.CommodityRows(id)
    ns.Market().looked[id] = { at = time(), r = rows }
    local left, cost = buy.qty, 0
    for i = 1, #rows, 2 do
        if left <= 0 then break end
        local take = math.min(left, rows[i + 1])
        cost, left = cost + take * rows[i], left - take
    end
    local qty = buy.qty - left
    if qty <= 0 then return Reset("none of it is listed now.") end
    if buy.each and buy.each > 0 and cost > buy.each * qty * REFUSE then
        local each = buy.each
        Reset(ns.PlainName(id) .. " costs " .. ns.Money(cost / qty) .. " each now, against " .. ns.Money(each)
            .. " reckoned: not bought here. Find shows its listings.")
        return
    end
    buy.qty, buy.expected, buy.step = qty, cost, "quote"
    if blocked then Refresh() else Quote() end
end

-- The auction house's own price for the lot
local function OnQuote(unit, total)
    if not buy or buy.step ~= "quoting" then return end
    unit, total = tonumber(Plain(unit)) or 0, tonumber(Plain(total)) or 0
    local qty, expected = buy.qty, buy.expected or 0
    local sound = unit > 0 and total > 0 and ns.AuctionKind(buy.id) == "commodity"
        and math.abs(total - unit * qty) <= qty
        and math.abs(total - expected) <= expected * MATCH + qty
    if not sound then
        return Reset("the auction house's price didn't match its listings: nothing bought. Try again, or Find.")
    end
    buy.step, buy.unit, buy.total, buy.at = "confirm", unit, total, GetTime()
    Refresh()
end

local function Spent()
    return buy and buy.money and math.max(0, buy.money - (tonumber(Plain(GetMoney())) or 0)) or 0
end

local function Done()
    if not buy or buy.step ~= "buying" then return end
    local id, qty, spent = buy.id, buy.qty, Spent()
    if spent <= 0 then spent = buy.total end
    buy = nil
    NoteBought(id, qty)
    QuietKit.Toast("Bought " .. qty .. " " .. ns.PlainName(id) .. " for " .. ns.Money(spent) .. ": it comes by mail.")
    Refresh()
end

-- ---------- the press ----------
-- each: what the route reckoned one would cost (to tell a price gone wild)
function ns.QuickBuy(id, qty, each)
    qty = math.max(1, ns.Whole(qty))
    if InCombatLockdown and InCombatLockdown() then return end
    if not ns.CanQuickBuy(id) then
        ns.ShowAtAuction(id, qty)
        return
    end
    local same = buy and buy.id == id
    if same and (buy.step == "looking" or buy.step == "quoting" or buy.step == "buying")
        and GetTime() - buy.at < BUY_WAIT then
        return -- (its answer is on the way)
    end
    if same and buy.step == "confirm" then
        local left = Call(AH.GetQuoteDurationRemaining)
        if type(left) == "number" and left <= 0 then
            -- (that price ran out: asked again, and a press more pays)
            Quote()
        elseif buy.total > (tonumber(Plain(GetMoney())) or 0) then
            Reset("not enough gold for that.")
        else
            buy.step, buy.at, buy.money = "buying", GetTime(), tonumber(Plain(GetMoney())) or 0
            local mine = buy
            if not pcall(AH.ConfirmCommoditiesPurchase, id, buy.qty) then
                Reset("the purchase didn't go through.")
            else
                C_Timer.After(BUY_WAIT, function()
                    if buy == mine and buy.step == "buying" then
                        if Spent() > 0 then Done() else Reset("no answer from the auction house: nothing bought.") end
                    end
                end)
            end
            Refresh()
        end
        return
    end
    if same and buy.step == "quote" then
        Quote()
        return
    end
    -- A new one: its listings first
    Reset()
    local running = ns.LookupState()
    if running then ns.StopLookups() end
    local key = Call(AH.MakeItemKey, id)
    if not key then return end
    buy = { id = id, qty = qty, each = each, step = "looking", at = GetTime() }
    local mine = buy
    if not pcall(AH.SendSearchQuery, key, ns.SearchSort, false) then
        return Reset("the auction house is busy: press again in a moment.")
    end
    C_Timer.After(LOOK_WAIT, function()
        if buy ~= mine or buy.step ~= "looking" then return end
        -- (no event: the list itself, if it's in)
        if Plain(Call(AH.HasFullCommoditySearchResults, id)) then OnListings() else Reset("no answer: press again.") end
    end)
    Refresh()
end

-- ---------- events ----------
local events = CreateFrame("Frame")
for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_CLOSED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_MONEY", "MAIL_SHOW" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, a, b)
    if event == "MAIL_SHOW" then
        C_Timer.After(2, SeenMailbox)
        return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        buy = nil
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- (a price asked without a press was refused: from now on a press asks)
        if a == ns.ADDON and tostring(b):find("StartCommoditiesPurchase") then
            blocked = true
            if buy and buy.step == "quoting" then
                buy.step = "quote"
                Refresh()
            end
        end
        return
    end
    if not buy then return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if Plain(a) == buy.id then OnListings() end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        OnQuote(a, b)
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if buy.step == "quoting" then Reset("those are gone: press Buy again for the next cheapest.") end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        Done()
    elseif event == "PLAYER_MONEY" then
        -- (gold left the purse after the press: that's the purchase, whatever the events say)
        if buy.step == "buying" and Spent() > 0 then Done() end
    elseif buy.step == "buying" then
        -- (it said no; but if the gold went, it's bought)
        if Spent() > 0 then Done() else Reset("someone was quicker: nothing bought.") end
    end
end)

-- ---------- for the window ----------
-- What the line's button reads and whether it's the one to press, and a line for under it while a purchase is on
function ns.QuickBuyButton(id, each)
    local step, b = ns.QuickBuyState(id)
    if not step then return "Buy", false, nil end
    if step == "confirm" then
        local note = "Pay buys " .. b.qty .. " for " .. ns.Money(b.total) .. " (" .. ns.Money(b.unit) .. " each)"
        if each and each > 0 and b.total > each * b.qty * DEARER then
            note = note .. "; |cffff9040dearer than reckoned (" .. ns.Money(each) .. " each)|r"
        end
        return "Pay", true, note
    elseif step == "quote" then
        return "Price", true, "Press Price: the auction house then says what " .. b.qty .. " cost. Nothing is bought yet."
    end
    return "...", false, step == "buying" and "Buying..." or "Asking the auction house..."
end
