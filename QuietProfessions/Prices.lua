-- What things cost: the auction house's listings, vendors, and what a vendor pays.
--
-- An item's price isn't one number here but its listings, cheapest first: { price, qty, price, qty, ... }. A route
-- that needs 200 bars pays for the 200 cheapest, not 200 times the cheapest one.
-- Where they come from, the newest winning:
--  * Check prices (the window's button, or /qprof prices, at the auction house): each material of the route is
--    looked up, one search a second or so, and its listings kept (QuietProfessionsDB.markets). Only a look: nothing
--    is bought.
--  * Quiet Auctions' own scans, if that addon is on: the cheapest price and how many were listed, read from its
--    saved table (it has no more than that, so a big order is reckoned dearer beyond what was listed).
--  * no price at all: a guess from what a vendor pays, and the window says so.
-- Vendors: what Data\ says is always in stock (flux, coal, thread...), and what a vendor was seen to sell without
-- a limit while this was on.
local _, ns = ...

local AH = C_AuctionHouse
local Plain, Call = ns.Plain, ns.Call

local LOOKED_DAYS = 3   -- a look-up older than this counts for nothing
local QUIET_DAYS = 7    -- nor a Quiet Auctions scan older than this
local MAX_ROWS = 60     -- listings kept for an item
local GUESS_TIMES = 5   -- no price known: this many times what a vendor pays

-- ---------- this realm's market ----------
local function MarketKey()
    -- (the same key as Quiet Auctions' own, whose scans are read below)
    return ns.Realm() .. "-" .. (Plain(UnitFactionGroup("player")) or "?")
end

function ns.Market()
    local markets = ns.DB().markets
    local key = MarketKey()
    local market = markets[key]
    if not market then
        market = { looked = {} }
        markets[key] = market
    end
    market.looked = market.looked or {}
    return market
end

-- Quiet Auctions' memory of an item: the cheapest for one, how many, when, and whether that was its last scan.
-- (Its saved lines are numbers in base 36, "first scan, then scan price quantity ..."; tables once it unpacked them.)
local function QuietPrice(id)
    local markets = type(QuietAuctionsDB) == "table" and QuietAuctionsDB.markets
    if type(markets) ~= "table" then return nil end
    local market = markets[MarketKey()]
    if type(market) ~= "table" or type(market.prices) ~= "table" then return nil end
    local p = market.prices[id]
    if not p then return nil end
    local scan, price, qty
    if type(p) == "string" then
        local words = {}
        for word in p:gmatch("%w+") do words[#words + 1] = word end
        local n = #words
        if n < 4 then return nil end
        scan, price, qty = tonumber(words[n - 2], 36), tonumber(words[n - 1], 36), tonumber(words[n], 36)
    elseif type(p) == "table" and type(p.h) == "table" then
        local h = p.h
        local n = #h
        if n < 3 then return nil end
        scan, price, qty = h[n - 2], h[n - 1], h[n]
    end
    if not (scan and price and price > 0) then return nil end
    local at = type(market.scanAt) == "table" and market.scanAt[scan] or nil
    return price, qty or 0, at, scan == market.scanNo
end

-- What a vendor sells one for, always in stock (nil: none does)
function ns.VendorPrice(id)
    local seen = ns.DB().vendor[id]
    if seen then return seen end
    local it = ns.items[id]
    if it and it.buy > 0 then return it.buy end
    return nil
end

-- What a vendor pays for one
function ns.SellValue(id)
    local it = ns.items[id]
    if it then return it.sell end
    local price = Plain(select(11, Call((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)))
    return tonumber(price) or 0
end

-- An item's price: { rows = { price, qty, ... }, vendor, guess, at (when seen), source ("looked", "scan", "guess",
-- nil for a vendor's alone) }
function ns.PriceOf(id)
    local price = { rows = {}, vendor = ns.VendorPrice(id) }
    local now = time()
    local looked = ns.Market().looked[id]
    local lookedAt = looked and now - looked.at < LOOKED_DAYS * 86400 and looked.at or nil
    local qPrice, qQty, qAt, qLatest = QuietPrice(id)
    if qAt and now - qAt > QUIET_DAYS * 86400 then qAt = nil end
    if lookedAt and (not qAt or lookedAt >= qAt) then
        price.rows, price.at, price.source = looked.r, lookedAt, "looked"
        price.guess = looked.r[1]
    elseif qAt then
        -- (not in its last scan: none listed then, but its price is the best guess)
        if qLatest and qQty > 0 then price.rows = { qPrice, qQty } end
        price.at, price.source, price.guess = qAt, "scan", qPrice
    end
    if not price.guess then
        price.guess = (looked and looked.r[1]) or qPrice
        if not price.guess then
            price.guess = math.max(1, ns.SellValue(id) * GUESS_TIMES)
            if not price.vendor then price.source = "guess" end
        end
    end
    return price
end

-- What Quiet Auctions' scans usually saw one listed for: the middle of the prices it remembers (nil: never seen)
local function QuietUsual(id)
    local markets = type(QuietAuctionsDB) == "table" and QuietAuctionsDB.markets
    if type(markets) ~= "table" then return nil end
    local market = markets[MarketKey()]
    if type(market) ~= "table" or type(market.prices) ~= "table" then return nil end
    local p = market.prices[id]
    local numbers = {}
    if type(p) == "string" then
        for word in p:gmatch("%w+") do numbers[#numbers + 1] = tonumber(word, 36) end
        table.remove(numbers, 1) -- (the scan it was first seen in)
    elseif type(p) == "table" and type(p.h) == "table" then
        numbers = p.h
    end
    local prices = {}
    for i = 2, #numbers, 3 do prices[#prices + 1] = numbers[i] end
    if #prices == 0 then return nil end
    table.sort(prices)
    return prices[math.ceil(#prices / 2)]
end

-- What one of a thing you made could bring at auction: its price with the house's cut off, how many are listed
-- now, and how many makings may count on it. nil if none is listed (no price to go by).
-- A price asked isn't a sale: so just under the cheapest listed, never over what it's usually listed for, and
-- only the first one of a piece of gear (a few of things sold by the stack).
local CUT = 0.95
function ns.SaleOf(id)
    local price = ns.PriceOf(id)
    local cheapest = price.rows[1]
    if not cheapest then return nil end
    local usual = QuietUsual(id)
    if usual and usual < cheapest then cheapest = usual end
    local listed = 0
    for i = 2, #price.rows, 2 do listed = listed + price.rows[i] end
    local it = ns.items[id]
    local gear = it and (it.kind == 2 or it.kind == 4)
    return { price = math.max(0, cheapest - 1) * CUT, units = gear and 1 or 5, listed = listed, at = price.at,
        source = price.source }
end

-- What one brings at auction after the house's cut, by the last price seen (nil: never seen)
function ns.AuctionValue(id)
    local looked = ns.Market().looked[id]
    local unit = looked and looked.r[1] or QuietPrice(id)
    return unit and unit * 0.95 or nil
end

-- ---------- vendors seen ----------
local function NoteVendor()
    if not (GetMerchantNumItems and GetMerchantItemID and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return end
    local vendor, changed = ns.DB().vendor, false
    for i = 1, tonumber(Plain(Call(GetMerchantNumItems))) or 0 do
        local id = Plain(Call(GetMerchantItemID, i))
        local info = Call(C_MerchantFrame.GetItemInfo, i)
        -- (only what the recipes use, for plain money, and never a few-at-a-time item)
        if id and ns.items[id] and type(info) == "table" and (Plain(info.price) or 0) > 0
            and not Plain(info.hasExtendedCost) and (Plain(info.numAvailable) or -1) < 0 then
            local each = info.price / math.max(1, Plain(info.stackCount) or 1)
            if vendor[id] ~= each then
                vendor[id], changed = each, true
            end
        end
    end
    if changed then ns.Changed() end
end

-- ---------- looking prices up ----------
local SORT = { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0,
    reverseSort = false } }
local STATUS = Enum and Enum.ItemCommodityStatus or {}
local IS_ITEM, IS_COMMODITY = STATUS.Item or 1, STATUS.Commodity or 2
local EVENT_WAIT = 1.5  -- seconds for the answer's event, before the lists are asked themselves
local GIVE_UP = 4       -- seconds for an answer at all

local atAuction = false
local queue, total, done, missed = {}, 0, 0, 0
local cur      -- the item being looked up: { id, key, sent (when), answer ("commodity" / "item"), tries }
local running = false
local chain = 0 -- (a new run's number: a stopped run's last step, still on its way, does nothing)

function ns.AtAuction()
    return atAuction
end

-- running, done, total, missed (no answer came)
function ns.LookupState()
    return running, done, total, missed
end

local function Ready()
    if not (AH and AH.IsThrottledMessageSystemReady) then return true end
    local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
    return not ok or ready ~= false
end

-- "commodity" (bought by quantity), "item" (each auction its own), or nil while the game doesn't know
local function Kind(id)
    local status = Plain(Call(AH and AH.GetItemCommodityStatus, id))
    if status == IS_COMMODITY then return "commodity" end
    if status == IS_ITEM then return "item" end
    return nil
end

local function CommodityRows(id)
    local rows = {}
    for i = 1, tonumber(Plain(Call(AH.GetNumCommoditySearchResults, id))) or 0 do
        local r = Call(AH.GetCommoditySearchResultInfo, id, i)
        if type(r) == "table" and Plain(r.unitPrice) and Plain(r.quantity) then
            local qty = r.quantity - (Plain(r.numOwnerItems) or 0)
            if qty > 0 then
                local n = #rows
                if n > 0 and rows[n - 1] == r.unitPrice then
                    rows[n] = rows[n] + qty
                else
                    rows[n + 1], rows[n + 2] = r.unitPrice, qty
                end
            end
        end
        if #rows >= MAX_ROWS * 2 then break end
    end
    return rows
end

local function ItemRows(key)
    local list = {}
    for i = 1, tonumber(Plain(Call(AH.GetNumItemSearchResults, key))) or 0 do
        local r = Call(AH.GetItemSearchResultInfo, key, i)
        if type(r) == "table" and (Plain(r.buyoutAmount) or 0) > 0 and not Plain(r.containsOwnerItem) then
            local qty = math.max(1, Plain(r.quantity) or 1)
            list[#list + 1] = { unit = r.buyoutAmount / qty, qty = qty }
        end
    end
    table.sort(list, function(a, b) return a.unit < b.unit end)
    local rows = {}
    for i = 1, math.min(#list, MAX_ROWS) do
        rows[#rows + 1], rows[#rows + 2] = list[i].unit, list[i].qty
    end
    return rows
end

-- (Buy.lua's too)
ns.AuctionKind, ns.CommodityRows, ns.SearchSort = Kind, CommodityRows, SORT

local function Stop()
    running, cur, queue = false, nil, {}
    ns.Changed()
end
ns.StopLookups = Stop

local function Next(rows)
    if rows and cur then
        ns.Market().looked[cur.id] = { at = time(), r = rows }
    elseif cur then
        missed = missed + 1
    end
    cur = nil
    done = done + 1
    -- (the route follows now and then, not at every item: it's a long sum)
    if done % 12 == 0 then ns.Changed() end
end

local function Step(token)
    if not running or token ~= chain then return end
    if not atAuction then return Stop() end
    if not cur then
        local id = table.remove(queue, 1)
        if not id then
            Stop()
            local note = missed > 0 and (" (" .. missed .. " gave no answer)") or ""
            QuietKit.Toast("Quiet Professions: prices looked up" .. note .. ".")
            return
        end
        local key = Call(AH.MakeItemKey, id)
        if not key then
            done, missed = done + 1, missed + 1
        else
            cur = { id = id, key = key, tries = 1 }
        end
    elseif not cur.sent then
        if Ready() then
            if pcall(AH.SendSearchQuery, cur.key, SORT, false) then cur.sent = GetTime() else Next(nil) end
        end
    else
        local waited = GetTime() - cur.sent
        if not cur.answer and waited > EVENT_WAIT then
            -- (no event: the lists themselves, each only for the kind of item it is)
            local kind = Kind(cur.id)
            if kind ~= "item" and Plain(Call(AH.HasFullCommoditySearchResults, cur.id)) then
                cur.answer = "commodity"
            elseif kind ~= "commodity" and Plain(Call(AH.HasFullItemSearchResults, cur.key)) then
                cur.answer = "item"
            end
        end
        if cur.answer == "commodity" then
            Next(CommodityRows(cur.id))
        elseif cur.answer == "item" then
            Next(ItemRows(cur.key))
        elseif waited > GIVE_UP then
            -- (gear is filed under its item level too: once more with it)
            local it = ns.items[cur.id]
            local key = cur.tries == 1 and it and it.ilvl > 0 and Call(AH.MakeItemKey, cur.id, it.ilvl)
            if key then
                cur.key, cur.tries, cur.sent = key, 2, nil
            else
                Next(nil)
            end
        end
    end
    C_Timer.After(cur and 0.2 or 0.35, function() Step(token) end)
end

-- Looks these items up, in this order
function ns.StartLookups(ids)
    if not (atAuction and AH and AH.SendSearchQuery and AH.MakeItemKey) then return false end
    queue, total, done, missed, cur = {}, #ids, 0, 0, nil
    for i, id in ipairs(ids) do queue[i] = id end
    if total == 0 then return false end
    running, chain = true, chain + 1
    local token = chain
    C_Timer.After(0, function() Step(token) end)
    ns.Changed()
    return true
end

-- The button's and /qprof prices': the route's materials, looked up
function ns.CheckPrices()
    if running then
        Stop()
        return
    end
    if not atAuction then
        ns.Say("open the auction house first: prices are looked up there.")
        return
    end
    if not ns.StartLookups(ns.ItemsToPrice()) then
        ns.Say(ns.Profession() and "nothing to look up: every price was looked up in the last 20 minutes."
            or "nothing to look up: no profession chosen yet.")
    end
end

-- ---------- an item on the game's own auction page ----------
-- "Find" opens the item's listings as a click in the game's browse list does, with how many filled in for ore and
-- such. The buying is the game's Buy button and your own press.
local showing -- { id, count }: listings asked for, the count to fill in when they come
local keyWait -- an item whose auction key the game is still loading

local function OpenListings(id)
    local key = AH.MakeItemKey(id)
    if not AH.GetItemKeyInfo(key) then
        keyWait = id -- (ITEM_KEY_ITEM_INFO_RECEIVED follows)
        return
    end
    keyWait = nil
    AuctionHouseFrame:SelectBrowseResult({ itemKey = key, minPrice = 0, totalQuantity = 0 })
end

function ns.ShowAtAuction(id, count)
    local frame = AuctionHouseFrame
    if not (id and atAuction and frame and frame:IsShown() and frame.SelectBrowseResult and AH and AH.MakeItemKey
        and AH.GetItemKeyInfo) then
        return false
    end
    if running then Stop() end
    showing = { id = id, count = count }
    return (pcall(OpenListings, id))
end

-- ---------- events ----------
local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED", "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        atAuction = true
        ns.Changed()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        atAuction, showing, keyWait = false, nil, nil
        if running then Stop() else ns.Changed() end
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        if keyWait and Plain(arg) == keyWait and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            pcall(OpenListings, keyWait)
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local id = Plain(arg)
        if cur and cur.sent and id == cur.id and Kind(id) ~= "item" then cur.answer = "commodity" end
        if showing and id == showing.id then
            local want = showing.count
            showing = nil
            -- (the game's buy page takes the count from the window's own event, a frame later)
            local frame, mixin = AuctionHouseFrame, AuctionHouseFrameMixin
            local quantityEvent = mixin and mixin.Event and mixin.Event.CommoditiesQuantitySelectionChanged
            if want and want > 1 and quantityEvent and frame and frame.TriggerEvent then
                C_Timer.After(0, function()
                    if frame:IsShown() then pcall(frame.TriggerEvent, frame, quantityEvent, want) end
                end)
            end
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local id = type(arg) == "table" and Plain(arg.itemID)
        if cur and cur.sent and id == cur.id and Kind(id) ~= "commodity" then
            cur.answer, cur.key = "item", arg
        end
        if showing and id == showing.id then showing = nil end
    else
        NoteVendor()
    end
end)
