-- The auction house's plumbing: is it open, is an item a commodity (one shared price list, bought by quantity) or a
-- plain item (each auction bought on its own), and one search at a time for an item's current listings.
-- A search only looks: buying, posting and cancelling are in Buy.lua and Post.lua, each on a press.
-- And when it may look by itself: not while you use the game's own auction pages (ns.LookByItself).
local _, ns = ...

local AH = C_AuctionHouse
local COMMODITY = (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity) or 2
local UNKNOWN = (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Unknown) or 0
local SORT_PRICE = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0

local THROTTLE_WAIT = 15

ns.SORT_BY_PRICE = { { sortOrder = SORT_PRICE, reverseSort = false } }

function ns.HasAuctionAPI()
    return type(AH) == "table" and type(AH.SendSearchQuery) == "function"
end

-- The auction house will take a query now (it throttles them)
function ns.Ready()
    if not (AH and AH.IsThrottledMessageSystemReady) then return true end
    local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
    return not ok or ready ~= false
end

-- true (commodity), false (an item), or nil while the game doesn't know yet (asked for; try again in a moment)
function ns.IsCommodity(id)
    if not (AH and AH.GetItemCommodityStatus) then return false end
    local ok, status = pcall(AH.GetItemCommodityStatus, id)
    if not ok then return false end
    if status == nil or status == UNKNOWN then
        ns.ItemInfo(id) -- (asks the game for the item's data)
        return nil
    end
    return status == COMMODITY
end

-- Could it be a commodity at all? Never if it doesn't stack (a pattern, a bag, gear: each is an auction of its own),
-- nor while its stack size isn't known, nor if the game says it's a plain item. (Taking a pattern for a commodity
-- once made one bought pattern count as thousands, and bought it at a loss.)
function ns.MayBeCommodity(id)
    return ns.StackSize(id) > 1 and ns.IsCommodity(id) ~= false
end

-- ---------- your own use of the auction house ----------
-- While you use the game's own auction pages (a search of yours, selling, your auctions, buying there), nothing here
-- looks anything up by itself: its searches would replace what you're looking at, the one list the game keeps. A
-- moment after you stop (RESUME), it carries on. Seen two ways:
--  * the page shown: anything but the plain browse page (the sell pages, your auctions, an item's listings, a
--    purchase) is yours while it's up
--  * the auction house's calls (a search, a post, a purchase...) not made by us: ours go through ns.Ours
local RESUME = 10
local PAGES_RESUME = 45 -- (the browse list is read page by page by itself only this long after a search of yours)
local yoursAt = -1000 -- (when you last did something on the game's pages)
local ours = false -- (a call of ours under way: not yours)

local function Yours()
    if not ours then yoursAt = GetTime() end
end

local function Ended(...)
    ours = false
    return ...
end

-- pcall(fn, ...) for a call of ours to the auction house: so it isn't taken for yours
function ns.Ours(fn, ...)
    ours = true
    return Ended(pcall(fn, ...))
end

-- (not "more of the browse list": the game's list asks that by itself as it shows the pages a page scan of ours read)
for _, name in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "RefreshCommoditySearchResults",
    "RefreshItemSearchResults", "StartCommoditiesPurchase", "PlaceBid", "PostItem", "PostCommodity", "CancelAuction",
    "QueryOwnedAuctions", "QueryBids" }) do
    if AH and type(AH[name]) == "function" and hooksecurefunc then pcall(hooksecurefunc, AH, name, Yours) end
end

-- (the auction house's own window is made the first time it opens: its pages are watched from then)
local hookedFrame = false
local function WatchGamePages()
    local frame = AuctionHouseFrame
    if hookedFrame or not frame or type(frame.SetDisplayMode) ~= "function" then return end
    hookedFrame = true
    hooksecurefunc(frame, "SetDisplayMode", Yours)
end

-- The game's window shows something other than its browse page now
local function OnGamePage()
    WatchGamePages()
    local frame, modes = AuctionHouseFrame, AuctionHouseFrameDisplayMode
    if not frame or not modes or not frame:IsShown() then return false end
    local mode = frame.displayMode
    if mode == nil and frame.GetDisplayMode then
        local ok, got = pcall(frame.GetDisplayMode, frame)
        mode = ok and got or nil
    end
    return mode ~= nil and mode ~= modes.Buy
end

-- You're using the game's own pages now, or did a moment ago (wait: how long a moment, RESUME by default)
function ns.YoursNow(wait)
    return OnGamePage() or GetTime() - yoursAt < (wait or RESUME)
end

-- You've used them since then (a GetTime()), or are now
function ns.YoursSince(since)
    return OnGamePage() or yoursAt > since
end

-- Looking things up by itself (the watch, a full scan every 15 minutes, the next buy made ready, a BoE priced ahead):
-- only on an auctions character at the auction house, while you use Quiet Auctions (its window is open, or you
-- pressed one of its presses in the last minute), and never while the game's own pages are yours. pages: for reading
-- the browse list page by page, which replaces the list you browse: only long after a search of yours.
local IN_USE = 60
function ns.LookByItself(pages)
    if not ns.Does("auctions") or not ns.at.auction then return false end
    local inUse = (ns.WindowTab and ns.WindowTab() ~= nil) or GetTime() - (ns.pressedAt or 0) < IN_USE
    return inUse and not ns.YoursNow(pages and PAGES_RESUME or nil)
end

-- ---------- tracing ----------
-- /qah trace: what's asked of the auction house and what it answers, in chat (to find out why a look-up fails)
function ns.Trace(msg)
    if ns.DB().trace then print("|cff888888Quiet Auctions trace:|r " .. msg) end
end

local function KeyText(key)
    if type(key) ~= "table" then return "no key" end
    return "item " .. tostring(key.itemID) .. ", level " .. tostring(key.itemLevel) .. ", suffix "
        .. tostring(key.itemSuffix)
end

-- ---------- one search at a time ----------
-- An item's listings, asked for by its key. The key must be the one the auction house files the item under, and a
-- plain item's holds its item level, which its ID alone doesn't give. So a search tries, a few seconds each:
--   1. the key it was given, else one made from the ID
--   2. one made from the ID and the item's own level
--   3. a browse by the item's name: its answer carries the exact key, which is then searched for
-- and takes whichever answer comes, a plain item's, or a commodity's for an item that can be one (MayBeCommodity).
local ATTEMPT_TIMEOUT = 3
local POLL = 0.25

local search -- { id, key, given, attempt, token, browsing, at, done = fn(ok, commodity, key) }

function ns.Searching()
    return search ~= nil
end

local function Finish(ok, commodity, key)
    local s = search
    search = nil
    if not s then return end
    ns.Trace((ok and "answered: " or "no answer: ") .. ns.ItemName(s.id) .. (ok and (commodity and " (commodity)"
        or " (" .. KeyText(key) .. ")") or ""))
    s.done(ok, commodity, key)
end

local NextAttempt

-- Waits for the attempt's answer: its event (below), or seen here, in case the event doesn't come
local function Wait(s)
    local token = s.token
    local function Poll()
        if search ~= s or s.token ~= token then return end
        if s.browsing then
            local ok, results = pcall(AH.GetBrowseResults)
            for _, r in ipairs(ok and type(results) == "table" and results or {}) do
                if r.itemKey and r.itemKey.itemID == s.id then
                    s.browsing = false
                    ns.Trace("its key, from the browse: " .. KeyText(r.itemKey))
                    ns.SendKey(s, r.itemKey)
                    return
                end
            end
        else
            local okC, fullC = pcall(AH.HasFullCommoditySearchResults, s.id)
            if okC and fullC and ns.MayBeCommodity(s.id) then
                Finish(true, true, s.key)
                return
            end
            local okI, fullI = pcall(AH.HasFullItemSearchResults, s.key)
            if okI and fullI then
                Finish(true, false, s.key)
                return
            end
        end
        if GetTime() - s.at > ATTEMPT_TIMEOUT then
            NextAttempt(s)
        else
            C_Timer.After(POLL, Poll)
        end
    end
    C_Timer.After(POLL, Poll)
end

-- One attempt: a search for this key (once the auction house takes queries again)
function ns.SendKey(s, key)
    s.key, s.token, s.at = key, s.token + 1, GetTime()
    local token, started = s.token, GetTime()
    local function Send()
        if search ~= s or s.token ~= token then return end
        if not ns.Ready() and GetTime() - started < THROTTLE_WAIT then
            C_Timer.After(0.1, Send)
            return
        end
        ns.Trace("search " .. KeyText(key) .. (ns.Ready() and "" or " (the auction house said it was busy)"))
        if not ns.Ours(AH.SendSearchQuery, key, ns.SORT_BY_PRICE, true) then
            NextAttempt(s)
            return
        end
        s.at = GetTime()
        Wait(s)
    end
    Send()
end

function NextAttempt(s)
    if search ~= s then return end
    s.attempt = s.attempt + 1
    if s.attempt == 2 then
        local level = select(8, ns.ItemInfo(s.id))
        if not s.given and level and level > 0 then
            local ok, key = pcall(AH.MakeItemKey, s.id, level)
            if ok and key then
                ns.SendKey(s, key)
                return
            end
        end
        s.attempt = 3
    end
    if s.attempt == 3 then
        local name = ns.ItemInfo(s.id)
        local query = name and { searchString = name, sorts = ns.SORT_BY_PRICE, filters = {}, itemClassFilters = {} }
        if query and ns.Ours(AH.SendBrowseQuery, query) then
            ns.Trace("browse by name: " .. name)
            s.browsing, s.token, s.at = true, s.token + 1, GetTime()
            Wait(s)
            return
        end
    end
    Finish(false)
end

-- Reads an item's listings: done(true, commodity, key) once they're in (read them with CommodityRows(id) or
-- ItemRows(key)), done(false) if no answer came. key: the item's key if known (a bag item's, an owned auction's).
-- false if a search or a scan is under way already.
function ns.Search(id, key, done)
    if search or ns.Browsing() or not ns.at.auction or not ns.HasAuctionAPI() then return false end
    local given = key ~= nil
    if not key then
        local ok, made = pcall(AH.MakeItemKey, id)
        key = ok and made or nil
        if not key then return false end
    end
    search = { id = id, given = given, attempt = 1, token = 0, done = done, at = GetTime() }
    ns.SendKey(search, key)
    return true
end

-- A commodity's listings, cheapest first: { { unit, qty, own (how many are yours) }, ... }
function ns.CommodityRows(id)
    local rows = {}
    if not (AH and AH.GetNumCommoditySearchResults) then return rows end
    local ok, n = pcall(AH.GetNumCommoditySearchResults, id)
    for i = 1, (ok and n) or 0 do
        local got, r = pcall(AH.GetCommoditySearchResultInfo, id, i)
        if got and r and r.unitPrice and r.quantity then
            rows[#rows + 1] = { unit = r.unitPrice, qty = r.quantity, own = r.numOwnerItems or 0 }
        end
    end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    return rows
end

-- A plain item's listings with a buyout: { { auctionID, buyout (the whole auction), qty, unit, own }, ... }
function ns.ItemRows(key)
    local rows = {}
    if not (AH and AH.GetNumItemSearchResults and key) then return rows end
    local ok, n = pcall(AH.GetNumItemSearchResults, key)
    for i = 1, (ok and n) or 0 do
        local got, r = pcall(AH.GetItemSearchResultInfo, key, i)
        if got and r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 then
            local qty = math.max(1, math.min(r.quantity or 1, ns.StackSize(key.itemID)))
            rows[#rows + 1] = { auctionID = r.auctionID, buyout = r.buyoutAmount, qty = qty,
                unit = r.buyoutAmount / qty, own = r.containsOwnerItem and true or false }
        end
    end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    return rows
end

-- The cheapest someone else asks for one, from the search just read (nil: nobody else lists it)
function ns.CheapestOther(id, commodity, key)
    if commodity then
        for _, r in ipairs(ns.CommodityRows(id)) do
            if r.qty - r.own > 0 then return r.unit end
        end
    else
        for _, r in ipairs(ns.ItemRows(key)) do
            if not r.own then return r.unit end
        end
    end
    return nil
end

-- ---------- an item looked up on the game's own pages ----------
-- A click on a line of the window at the auction house opens that item's listings on the game's own buy page, as a
-- click on it in the game's browse list does, and for ore, herbs and such fills in how many (count). Buying stays the
-- game's Buy Now, your own click. (It's a search of yours: the looking-by-itself waits, as after any search of yours.)
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

-- true: asked for (the auction house's window is open and can show it)
function ns.ShowAtAuction(id, count)
    local frame = AuctionHouseFrame
    if not (id and frame and frame:IsShown() and frame.SelectBrowseResult and AH and AH.MakeItemKey
        and AH.GetItemKeyInfo) then
        return false
    end
    showing = { id = id, count = count }
    local ok = pcall(OpenListings, id)
    return ok
end

ns.Listen("any", { "ITEM_KEY_ITEM_INFO_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_CLOSED" }, function(_, event, arg)
    if event == "AUCTION_HOUSE_CLOSED" then
        showing, keyWait = nil, nil
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        if keyWait and ns.Plain(arg) == keyWait and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            pcall(OpenListings, keyWait)
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local want = showing and ns.Plain(arg) == showing.id and showing.count
        if not (showing and ns.Plain(arg) == showing.id) then return end
        showing = nil
        -- (the game's buy page and its list both take the count from the window's own event, a frame later)
        local frame, mixin = AuctionHouseFrame, AuctionHouseFrameMixin
        local quantityEvent = mixin and mixin.Event and mixin.Event.CommoditiesQuantitySelectionChanged
        if want and want > 1 and quantityEvent and frame and frame.TriggerEvent then
            C_Timer.After(0, function()
                if frame:IsShown() then pcall(frame.TriggerEvent, frame, quantityEvent, want) end
            end)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local id = type(arg) == "table" and ns.Plain(arg.itemID)
        if showing and id == showing.id then showing = nil end
    end
end)

-- ---------- events ----------
ns.Listen("auctions", { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_SHOW_ERROR" },
function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        ns.at.auction = true
        -- (the window has just opened on its browse page: a moment before anything is looked up by itself)
        yoursAt = GetTime()
        WatchGamePages()
        if ns.OnPlaceOpened then ns.OnPlaceOpened("auction") end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns.at.auction = false
        search = nil
        if ns.OnPlaceClosed then ns.OnPlaceClosed("auction") end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if search and not search.browsing and arg == search.id and ns.MayBeCommodity(arg) then
            Finish(true, true, search.key)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        -- (the key in the answer is the very one its listings are filed under)
        local id = type(arg) == "table" and arg.itemID
        if search and not search.browsing and id == search.id then Finish(true, false, arg) end
    else
        ns.Trace(event .. " " .. tostring(arg))
    end
    ns.Refresh()
end)
