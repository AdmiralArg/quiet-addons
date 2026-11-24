-- Where what was bought is: in your bags, in the mail, or up at auction. The bought list (QuietAuctionsCharDB.bought)
-- is kept to what's really there, so it never lists something sold or gone:
--  * the bags are counted as they are; the mail as it was when the mailbox was last open (anything bought since is
--    counted as on its way there); what's up at auction is in the ledger (Ledger.lua), off the bought list
--  * a bought thing seen leaving your bags while a vendor's window is open counts as sold there, for what your gold
--    went up by (at most what a vendor pays for it); one seen leaving them while the auction house is open counts as
--    posted, so its "Auction successful" mail counts as a resale. Only what's seen to leave the bags there: being at
--    a vendor while something is missing (in the mail all along, say) is no sale.
--  * anything else gone (mailed away, destroyed, sold before this was here) is dropped, logged "gone", no profit, and
--    kept aside a week (QuietAuctionsCharDB.limbo): if it turns up in the mail or among your auctions, it's back
--  * a hand sale counted wrongly (the thing turns up in the mail afterwards) is undone: back on the list, the sale
--    taken off the totals
-- The check runs a few seconds after the bags or the mail settle, never while Sell, Collect or a post is under way.
-- Once, on the first login with this: what the bought list held but your bags didn't is dropped, kept aside a week
-- (QuietAuctionsCharDB.limbo): if it turns up in the mail or among your auctions, it goes back on the list.
local _, ns = ...

local SETTLE = 3
local AFTER_POST = 3
local LIMBO_DAYS = 7
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

local gen, pending = 0, false
local lastBags -- (the bags at the last change, to see what left them)
-- What of each bought thing left the bags since the last check, by where you were: { [itemID] = { merchant = n,
-- auction = n, mail = n, other = n } }
local left = {}
local purse = { gain = 0, loss = 0 } -- (what your gold did since the last check, up and down apart)
local lastMoney
local created = 0 -- (when the auction house last said a post went up)
local inboxLoaded = false

local function InBags()
    local have, filled = {}, 0
    ns.EachSlot(function(_, _, info)
        have[info.itemID] = (have[info.itemID] or 0) + (info.stackCount or 1)
        filled = filled + 1
    end)
    return have, filled
end

-- The inbox's attachments, by item. "all": every mail was shown (over 50, the rest wait on the server).
local function ReadMail()
    if not ns.at.mail or not inboxLoaded then return end
    local ok, shown, total = pcall(GetInboxNumItems)
    if not ok then return end
    shown = shown or 0
    local items = {}
    for i = 1, shown do
        local got, _, _, _, _, _, _, _, itemCount = pcall(GetInboxHeaderInfo, i)
        if got and (itemCount or 0) > 0 then
            for a = 1, ATTACHMENTS do
                local had, _, id, _, count = pcall(GetInboxItem, i, a)
                -- (the link as well, should the id not come)
                if had and type(id) ~= "number" then
                    local linked, link = pcall(GetInboxItemLink, i, a)
                    id = linked and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
                end
                if had and id then items[id] = (items[id] or 0) + (count or 1) end
            end
        end
    end
    local char = ns.Char()
    char.mailSeen = { at = time(), items = items, all = (total or 0) <= shown }
    -- (dropped at the cleanup, but here after all: back on the list)
    for id, l in pairs(char.limbo or {}) do
        local n = math.min(l.n, items[id] or 0)
        if n > 0 then
            local cost = l.cost * n / l.n
            ns.RecordBuy(id, n, cost, true)
            l.n, l.cost = l.n - n, l.cost - cost
            if l.n <= 0 then char.limbo[id] = nil end
            ns.Say(n .. " " .. ns.ItemName(id) .. " is in your mail after all: back on the bought list.")
        end
    end
    -- (counted as sold to a vendor by hand, but in the mail now, beyond what the bought list has away from the bags:
    -- that sale didn't happen, so it's undone)
    local bags = InBags()
    local week = time() - LIMBO_DAYS * 24 * 3600
    for _, e in ipairs(char.log or {}) do
        local b = e.id and char.bought[e.id]
        local away = b and math.max(0, b.n - (bags[e.id] or 0)) or 0
        local extra = e.id and (items[e.id] or 0) - away or 0
        if e.kind == "sold by hand" and not e.undone and e.t > week and extra > 0 and (e.qty or 0) > 0 then
            local n = math.min(extra, e.qty)
            local got = (e.change or 0) * n / e.qty
            local profit = (e.profit or 0) * n / e.qty
            ns.RecordBuy(e.id, n, got - profit, true)
            char.totals.vendored = (char.totals.vendored or 0) - got
            ns.AddProfit(e.id, "vendor", -profit)
            e.undone = true
            ns.Log("not sold after all", e.id, n, 0, 0)
            ns.Say(n .. " " .. ns.ItemName(e.id) .. " is in your mail, so it wasn't sold to a vendor after all: back "
                .. "on the bought list, and that sale is off the totals.")
        end
    end
end

-- Your auctions, as the auction house lists them: one dropped at the cleanup but up there goes in the ledger
local function ReadAuctions()
    local char = ns.Char()
    if not char.limbo or not next(char.limbo) then return end
    local AH = C_AuctionHouse
    local ok, count = pcall(AH.GetNumOwnedAuctions)
    local up = {}
    for i = 1, (ok and count) or 0 do
        local got, a = pcall(AH.GetOwnedAuctionInfo, i)
        if got and type(a) == "table" and a.status == 0 and a.itemKey then
            local id = a.itemKey.itemID
            up[id] = (up[id] or 0) + math.max(1, a.quantity or 1)
        end
    end
    for _, a in ipairs(char.auctions or {}) do
        if up[a.id] then up[a.id] = up[a.id] - a.qty end
    end
    for id, l in pairs(char.limbo) do
        local n = math.min(l.n, up[id] or 0)
        if n > 0 then
            local cost = l.cost * n / l.n
            ns.RecordBuy(id, n, cost, true)
            ns.NotePost(id, n, nil, 0, nil)
            l.n, l.cost = l.n - n, l.cost - cost
            if l.n <= 0 then char.limbo[id] = nil end
            ns.Say(n .. " " .. ns.ItemName(id) .. " is up at auction: its sale will count as a resale.")
        end
    end
end

-- ---------- the check ----------
local function Busy()
    return (ns.Collecting and ns.Collecting()) or (ns.Selling and ns.Selling()) or (ns.PostBusy and ns.PostBusy())
        or (ns.BoEBusy and ns.BoEBusy()) or GetTime() - created < AFTER_POST
end

-- n of a bought thing no longer anywhere: what became of it, by where you were when it was seen to leave the bags
-- (out: { merchant = n, auction = n, mail = n, other = n }, or nil: never seen to leave them)
local function Gone(id, n, out)
    local char = ns.Char()
    out = out or {}
    local sold = math.min(n, out.merchant or 0)
    local worth = (ns.SellPrice(id) or 0) * sold
    local got = math.min(purse.gain, worth)
    if sold > 0 and got > 0 then
        purse.gain = purse.gain - got
        local share = ns.TakeBought(id, sold)
        char.totals.vendored = (char.totals.vendored or 0) + got
        ns.AddProfit(id, "vendor", got - share)
        ns.Log("sold by hand", id, sold, worth, got, got - share)
        ns.Say("Sold " .. sold .. " " .. ns.ItemName(id) .. " to the vendor by hand: " .. ns.Money(got)
            .. " (it cost " .. ns.Money(share) .. ").")
        n = n - sold
    end
    local posted = math.min(n, out.auction or 0)
    if posted > 0 then
        -- (the deposit: what your gold went down by, if it's no more than a deposit could be; else a guess)
        local guess = ns.DepositGuess(id) * posted
        local paid = purse.loss > 0 and purse.loss <= (ns.SellPrice(id) or 0) * posted and purse.loss or guess
        purse.loss = math.max(0, purse.loss - paid)
        ns.NotePost(id, posted, nil, paid, nil)
        ns.Log("posted by hand", id, posted, -guess, -paid)
        ns.Say("Posted " .. posted .. " " .. ns.ItemName(id) .. " by hand: in the ledger, so its sale counts as a "
            .. "resale.")
        n = n - posted
    end
    if n <= 0 then return end
    -- (the rest: off the list, kept aside a week in case it turns up in the mail or at auction)
    local share = ns.TakeBought(id, n)
    char.limbo = char.limbo or {}
    local l = char.limbo[id] or { n = 0, cost = 0 }
    l.n, l.cost = l.n + n, l.cost + share
    char.limbo[id] = l
    char.limboUntil = time() + LIMBO_DAYS * 24 * 3600
    ns.Log("gone", id, n, 0, 0)
    ns.Say(n .. " " .. ns.ItemName(id) .. " bought earlier " .. ((out.mail or 0) > 0 and "was sent off by mail"
        or "is no longer in your bags or mail") .. ": off the bought list (back on it if it turns up in your mail).")
end

-- Once: the bought list cut to what's in your bags (the mail and the auctions checked later, against the limbo)
local function Cleanup(char, bags)
    char.limbo = char.limbo or {}
    local names = {}
    for id, b in pairs(char.bought) do
        local n = b.n - (bags[id] or 0)
        if n > 0 then
            local share = ns.TakeBought(id, n)
            local l = char.limbo[id] or { n = 0, cost = 0 }
            l.n, l.cost = l.n + n, l.cost + share
            char.limbo[id] = l
            ns.Log("gone", id, n, 0, 0)
            names[#names + 1] = n .. " " .. ns.ItemName(id)
        end
    end
    char.limboUntil = time() + LIMBO_DAYS * 24 * 3600
    char.cleaned = 1
    if #names > 0 then
        ns.Say("The bought list held things not in your bags: " .. table.concat(names, ", ") .. ". Dropped, not "
            .. "tracked; any still in your mail or up at auction go back on the list when seen there.")
    end
end

local function Settle()
    local char = ns.Char()
    local bags, filled = InBags()
    -- (the bags not read yet, at login: nothing is judged on that)
    if filled == 0 then return end
    ReadMail()
    if not char.cleaned then Cleanup(char, bags) end
    if char.limbo and time() > (char.limboUntil or 0) then char.limbo = nil end
    local mail = char.mailSeen
    for id, b in pairs(char.bought) do
        -- (only against a mailbox read in full after it was bought: else it may be on its way)
        if mail and mail.all and (b.at or 0) < mail.at then
            local n = b.n - (bags[id] or 0) - (mail.items[id] or 0)
            if n > 0 then Gone(id, n, left[id]) end
        end
    end
    left, purse.gain, purse.loss = {}, 0, 0
    -- (nothing worked out from the price memory depends on this: only the window's rows, drawn afresh)
    ns.Refresh()
end

local function Later(delay)
    gen = gen + 1
    local mine = gen
    pending = true
    C_Timer.After(delay or SETTLE, function()
        if mine ~= gen then return end
        if Busy() then
            Later()
            return
        end
        pending = false
        Settle()
    end)
end

-- ---------- what the window shows ----------
local function Where(b, here, inMail, mail)
    here = math.min(here, b.n)
    inMail = math.min(inMail, b.n - here)
    local rest = b.n - here - inMail
    local parts = {}
    if here > 0 then parts[#parts + 1] = here == b.n and "in your bags" or (here .. " in your bags") end
    if inMail > 0 then parts[#parts + 1] = inMail == b.n and "in the mail" or (inMail .. " in the mail") end
    if rest > 0 then
        local coming = not mail or not mail.all or (b.at or 0) >= mail.at
        parts[#parts + 1] = (rest == b.n and "" or (rest .. " "))
            .. (coming and "on its way by mail" or "being checked")
    end
    return table.concat(parts, ", ")
end

-- Each: what it is and where (left), what happens to it next and the profit (right)
function ns.BoughtRows()
    local rows = {}
    local char = ns.Char()
    local bags = InBags()
    local mail = char.mailSeen
    for id, b in pairs(char.bought) do
        local vendor = (ns.SellPrice(id) or 0) * b.n
        local plan
        if ns.RepostPays(id, b.n) then
            local _, price = ns.AuctionReturn(id)
            plan = "Post puts it up at ~" .. ns.Money(price * b.n) .. " (cost " .. ns.Money(b.cost) .. ")"
        else
            plan = "Sell: a vendor pays " .. ns.Money(vendor) .. ", cost " .. ns.Money(b.cost) .. ": +"
                .. ns.Money(vendor - b.cost)
        end
        rows[#rows + 1] = { b.n .. " " .. ns.ItemName(id) .. " (" .. Where(b, bags[id] or 0, mail and mail.items[id]
            or 0, mail) .. ")", plan, id = id }
    end
    for _, a in ipairs(char.auctions or {}) do
        if not a.own then
            -- (roughly: the last deposit comes back with the sale, the earlier ones of a repost don't)
            local back = a.unit and (a.unit * a.qty * ns.CUT - a.cost)
            rows[#rows + 1] = { a.qty .. " " .. ns.ItemName(a.id) .. " (up at auction)", (a.unit and ("listed at "
                .. ns.Money(a.unit * a.qty) .. ": +" .. ns.Money(back) .. " if it sells") or "listed by hand")
                .. ((a.deposits or 0) > 0 and (", deposit " .. ns.Money(a.deposits)) or ""), id = a.id }
        end
    end
    if #rows > 0 then
        table.insert(rows, 1, { header = "Bought, not sold yet: where each is and what happens next ("
            .. #rows .. ")" })
    end
    return rows
end

-- How many bought things are in your bags, and how many in the mail or on their way (for "where to go next")
function ns.BoughtCounts()
    local char = ns.Char()
    local bags = InBags()
    local here, away, toSell = 0, 0, 0
    for id, b in pairs(char.bought) do
        local n = math.min(bags[id] or 0, b.n)
        here, away = here + n, away + b.n - n
        if n > 0 and not ns.RepostPays(id, n) then toSell = toSell + n end
    end
    return here, away, toSell
end

-- ---------- events ----------
-- (on a character that does the auction work only: the others have no bought list to keep)
ns.Listen("auctions", { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "MAIL_SHOW", "MAIL_CLOSED",
    "MAIL_INBOX_UPDATE", "MERCHANT_SHOW", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_AUCTION_CREATED",
    "OWNED_AUCTIONS_UPDATED" },
function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        lastMoney = GetMoney()
        Later(5)
    elseif event == "PLAYER_MONEY" then
        local money = GetMoney()
        local change = money - (lastMoney or money)
        lastMoney = money
        if change > 0 then purse.gain = purse.gain + change else purse.loss = purse.loss - change end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- (what of each bought thing left the bags just now, and where you were: only that counts as sold or posted)
        local bags, filled = InBags()
        if filled > 0 then
            if lastBags then
                local where = (ns.at.merchant and "merchant") or (ns.at.auction and "auction")
                    or (ns.at.mail and "mail") or "other"
                for id in pairs(ns.Char().bought) do
                    local drop = (lastBags[id] or 0) - (bags[id] or 0)
                    if drop > 0 then
                        left[id] = left[id] or {}
                        left[id][where] = (left[id][where] or 0) + drop
                    end
                end
            end
            lastBags = bags
        end
        Later()
    elseif event == "MAIL_SHOW" or event == "MAIL_CLOSED" then
        -- (the inbox isn't read until the game has it: MAIL_INBOX_UPDATE)
        inboxLoaded = false
    elseif event == "MAIL_INBOX_UPDATE" then
        inboxLoaded = true
        ReadMail()
        Later()
    elseif event == "MERCHANT_SHOW" or event == "AUCTION_HOUSE_SHOW" then
        -- (gold that moved before, with no check waiting, is nothing sold or posted here)
        if not pending then purse.gain, purse.loss = 0, 0 end
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        created = GetTime()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        ReadAuctions()
    end
end)
