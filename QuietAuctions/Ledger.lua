-- The ledger: what was put up on the auction house and what became of it, in real gold.
--  * each post is kept (QuietAuctionsCharDB.auctions) with what the item cost you (its share of what Next paid; 0 for
--    your own things, marked "own") and every deposit paid on it
--  * a sale counts when its "Auction successful" mail's money is taken (by Collect or by hand): that money, after the
--    cut and with the last deposit back, less what the item cost and every deposit paid on it, is its profit
--  * an auction that comes back (expired, or cancelled) brings its deposits back with it to the bag: they count
--    against it next time. A bought item that comes back unsold twice goes back on the Sell list (vendorIt).
-- Profit is kept apart: from vendors, from reselling what was bought, and from your own things (QuietAuctionsCharDB
-- .totals, and per item in .itemProfit). /qah log shows each sale and the profit per item.
local _, ns = ...

local MAX_TRIES = 2
local REPOST_OVER = 1.25 -- (an auction must bring this many times what a vendor pays, after fees, to be worth it)
local REPOST_LEAST = 20 -- (and this much more in copper, for the lot)
local DEPOSIT_RATE = { 0.15, 0.3, 0.6 } -- (of vendor price, by duration: a guess until the auction house says)

local function Book()
    local char = ns.Char()
    char.auctions = char.auctions or {}
    char.repost = char.repost or {} -- [itemID] = { tries, deposits }: came back unsold
    char.vendorIt = char.vendorIt or {} -- [itemID] = true: to a vendor, not the auction house
    char.itemProfit = char.itemProfit or {} -- [itemID] = { v = vendor profit, a = auction profit }
    return char
end

local function PlainName(id)
    local name = ns.ItemInfo(id)
    return name
end

-- ---------- profit ----------
-- kind: "vendor", "auction" (a bought thing resold) or "own"
function ns.AddProfit(id, kind, amount)
    local char = Book()
    local totals = char.totals
    if kind == "vendor" then
        totals.profit = (totals.profit or 0) + amount
    elseif kind == "auction" then
        totals.auctionProfit = (totals.auctionProfit or 0) + amount
    else
        totals.ownSales = (totals.ownSales or 0) + amount
    end
    if id then
        local p = char.itemProfit[id] or { v = 0, a = 0 }
        if kind == "vendor" then p.v = p.v + amount else p.a = p.a + amount end
        char.itemProfit[id] = p
    end
end

function ns.ProfitLine()
    local totals = ns.Char().totals
    return "Profit so far: " .. ns.Money(totals.profit or 0) .. " from vendors, " .. ns.Money(totals.auctionProfit or 0)
        .. " from reselling, " .. ns.Money(totals.ownSales or 0) .. " from your own things at auction"
end

-- ---------- repost or vendor ----------
function ns.DepositGuess(id)
    return (ns.SellPrice(id) or 0) * DEPOSIT_RATE[ns.Setting("duration")]
end

-- What one would bring at auction after the cut and the deposit, or nil with nothing to go by: the last scan's
-- cheapest (posts match it), else its usual price. (Bought for resale: its usual price, as when it was bought; the last
-- scan's cheapest was likely the one bought.)
function ns.AuctionReturn(id)
    local forResale = Book().forResale
    local price = forResale and forResale[id] and ns.Usual(id)
    if not price then
        price = ns.Latest(id)
        if price then price = math.floor(price) else price = ns.Usual(id) end
    end
    if not price then return nil end
    return price * ns.CUT - ns.DepositGuess(id), price
end

-- n of a bought item bring clearly more at auction than from a vendor (and it hasn't come back unsold twice).
-- Bought for resale: more at all will do (it was bought well under its usual price).
function ns.RepostPays(id, n)
    local char = Book()
    if char.vendorIt[id] then return false end
    local back = ns.AuctionReturn(id)
    local vendor = ns.SellPrice(id) or 0
    if not back then return false end
    if char.forResale and char.forResale[id] then return back > vendor end
    return back >= vendor * REPOST_OVER and (back - vendor) * (n or 1) >= REPOST_LEAST
end

function ns.VendorIt(id, yes)
    Book().vendorIt[id] = yes or nil
    ns.Changed()
end

-- ---------- posts ----------
-- A post went up: what it cost you comes off the bought list and goes with it (your own things cost nothing)
function ns.NotePost(id, qty, unit, deposit, auctionID)
    local char = Book()
    local share, covered = ns.TakeBought(id, qty)
    local back = char.repost[id]
    local deposits = deposit
    if back and covered == 0 then deposits = deposits + (back.deposits or 0) end
    char.auctions[#char.auctions + 1] = { id = id, name = PlainName(id), qty = qty, unit = unit, cost = share,
        deposits = deposits, own = covered == 0, auctionID = auctionID, at = time(), tries = back and back.tries or 0 }
    char.repost[id] = nil
end

-- Cancelled by you: it comes back, but that's no failed try
function ns.NoteCancel(auctionID)
    for _, a in ipairs(Book().auctions) do
        if a.auctionID == auctionID then a.cancelled = true end
    end
end

-- The oldest open post matching, split if only part of it is meant
local function Take(match, count)
    local list = Book().auctions
    for i, a in ipairs(list) do
        if match(a) then
            count = math.min(count or a.qty, a.qty)
            if count >= a.qty then
                table.remove(list, i)
                return a
            end
            local part = count / a.qty
            local piece = { id = a.id, name = a.name, qty = count, unit = a.unit, cost = a.cost * part,
                deposits = a.deposits * part, own = a.own, tries = a.tries, cancelled = a.cancelled }
            a.qty, a.cost, a.deposits = a.qty - count, a.cost - piece.cost, a.deposits - piece.deposits
            return piece
        end
    end
end

local function OnSale(itemName, count, money)
    local char = Book()
    char.totals.auctionSales = (char.totals.auctionSales or 0) + money
    local a = Take(function(e) return e.name == itemName end, count)
    -- (a post is kept by its plain name; the sale of one with a random suffix says "Pagan Mitts of Spirit")
    a = a or Take(function(e)
        return type(e.name) == "string" and e.name ~= "" and itemName:sub(1, #e.name + 4) == e.name .. " of "
    end, count)
    if not a then
        -- (posted before the ledger, or by hand elsewhere: pure income)
        ns.AddProfit(nil, "own", money)
        ns.Log("own sale", nil, count, 0, money, money, itemName)
        return
    end
    local profit = money - a.cost - a.deposits
    ns.AddProfit(a.id, a.own and "own" or "auction", profit)
    ns.Log(a.own and "own sale" or "resale", a.id, a.qty, -(a.cost + a.deposits), money, profit)
    char.vendorIt[a.id] = nil
    if char.forResale then char.forResale[a.id] = nil end
    ns.Say("Sold " .. a.qty .. " " .. ns.ItemName(a.id) .. " at auction: " .. ns.Money(money) .. " in, profit "
        .. ns.Money(profit) .. (a.own and " (your own)." or "."))
end

local function OnReturned(id, count)
    local char = Book()
    local a = Take(function(e) return e.id == id end, count)
    if not a then return end
    local tries = a.tries + (a.cancelled and 0 or 1)
    if a.own then
        local back = char.repost[id] or { tries = 0, deposits = 0 }
        back.tries, back.deposits = math.max(back.tries, tries), back.deposits + a.deposits
        char.repost[id] = back
    else
        -- (back on the bought list, its deposits now part of what it cost)
        ns.RecordBuy(id, a.qty, a.cost + a.deposits, true)
        char.repost[id] = { tries = tries, deposits = 0 }
    end
    ns.Log(a.cancelled and "cancelled" or "unsold", id, a.qty, 0, 0, -a.deposits)
    if tries >= MAX_TRIES then
        char.vendorIt[id] = true
        ns.Say(ns.ItemName(id) .. " came back unsold " .. tries .. " times: "
            .. (a.own and "Post leaves it alone now." or "it's back on the Sell list."))
    end
    ns.Changed()
end

-- ---------- the mail ----------
-- Seen whether the money or the items are taken by Collect or by hand: the game's own calls, hooked (after them,
-- while the mail is still there to read). Each mail counts once.
local counted = {}

local EXPIRED = ns.MailPattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s")
local CANCELLED = ns.MailPattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s")

local function MailKey(i, what)
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    return tostring(sender) .. "|" .. tostring(subject) .. "|" .. tostring(money) .. "|" .. tostring(daysLeft) .. "|"
        .. what
end

-- (only on a character that does the auction work: the others keep no ledger)
local function TookMoney(i)
    if not ns.Does("auctions") then return end
    local ok, _, _, _, _, money = pcall(GetInboxHeaderInfo, i)
    if not ok or not money or money <= 0 then return end
    local key = MailKey(i, "money")
    if counted[key] then return end
    -- (kind, the item, the buyer, bid, buyout, deposit, the cut, the delay, its hour and minute, then how many)
    local got, kind, itemName, _, _, _, _, _, _, _, _, count = pcall(GetInboxInvoiceInfo, i)
    if got and kind == "seller" and itemName then
        counted[key] = true
        OnSale(itemName, type(count) == "number" and count > 0 and count or nil, money)
        ns.Refresh()
    end
end

local function TookItem(i, a)
    if not ns.Does("auctions") then return end
    local ok, _, _, _, subject = pcall(GetInboxHeaderInfo, i)
    if not ok or type(subject) ~= "string" then return end
    if not ((EXPIRED and subject:match(EXPIRED)) or (CANCELLED and subject:match(CANCELLED))) then return end
    local key = MailKey(i, "item" .. tostring(a))
    if counted[key] then return end
    local got, _, id, _, count = pcall(GetInboxItem, i, a or 1)
    if got and id then
        counted[key] = true
        OnReturned(id, count)
        ns.Refresh()
    end
end

if hooksecurefunc then
    if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", TookMoney) end
    if TakeInboxItem then hooksecurefunc("TakeInboxItem", TookItem) end
    if AutoLootMailItem then
        hooksecurefunc("AutoLootMailItem", function(i)
            TookMoney(i)
            TookItem(i, 1)
        end)
    end
end
