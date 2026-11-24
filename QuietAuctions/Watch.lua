-- The watch: a full scan is allowed only once every 15 minutes, and the pages are slow, so between full scans a short
-- list of items is looked at again and again instead, one quick search a second. A new listing under vendor price is
-- seen within moments, goes on the list with its real numbers, and if it's the best one it's made ready (priced, if a
-- commodity): a press of Buy buys it. The watch only looks; buying is still a press.
--
-- Which items (from the price memory, worked out again after each scan): ones you could afford one of now, that
--  * were under vendor price (less the margin) in a recent scan, by enough for the minimum profit, or
--  * usually sell for barely more than a vendor pays and are listed in most scans: they dip under often.
-- The likeliest and biggest first, WATCH_SIZE at most. An item that can't be looked up twice is left out.
-- /qah watch on | off.
--
-- This is also the one heartbeat at the auction house for everything looked up by itself: the full scan when it's
-- allowed again (/qah autoscan), and the top of the Buy list kept ready (Buy.lua). It beats only while the auction
-- house is open, and does nothing unless ns.LookByItself (AH.lua) says so: on an auctions character, while you use
-- Quiet Auctions, never while you use the game's own auction pages.
local _, ns = ...

local WATCH_SIZE = 25
local BEAT = 0.25 -- (seconds between beats)
local PAUSE = 1 -- (seconds between one look and the next)
local NEAR = 1.25 -- (usually at most this many times the vendor's price: it dips under often)
local REBUILD = 120 -- (seconds: worked out again this often anyway, as your gold changes)
local GIVE_UP = 2

local list, builtVersion, builtAt = {}, -1, 0
local index = 0
local looking -- the item being looked at
local lastLook = 0
local fails = {} -- [itemID] = looks that got no answer (this session)
local pagesRead = false -- (the pages read by themselves this visit: once at most)

local function Build()
    local money = GetMoney()
    local margin = 1 - ns.Setting("margin") / 100
    local least = ns.Setting("minProfit")
    local sell = ns.DB().sell
    local found = {}
    for id, p in pairs(ns.Market().prices) do
        -- (only items whose vendor price is known already: nothing is asked of the game for this)
        local vendor = sell[id]
        if vendor and vendor > 0 and (fails[id] or 0) < GIVE_UP then
            local h = p.h
            local under, cheapest, size = 0, nil, 0
            for i = 1, #h, 3 do
                local m, q = h[i + 1], h[i + 2]
                if m <= vendor * margin and (vendor - m) * math.max(1, q) >= least then under = under + 1 end
                if not cheapest or m < cheapest then cheapest = m end
                size = math.max(size, q)
            end
            local usual = ns.Usual(id)
            local near = usual and usual <= vendor * NEAR and ns.Presence(id) >= 0.5
                and vendor * size * (1 - margin) >= least
            if (under > 0 or near) and cheapest and cheapest <= money then
                local score = (under + (near and 1 or 0)) * vendor * math.min(math.max(size, 1), 200)
                found[#found + 1] = { id = id, score = score }
            end
        end
    end
    table.sort(found, function(a, b) return a.score > b.score end)
    list = {}
    for i = 1, math.min(#found, WATCH_SIZE) do list[i] = found[i].id end
    builtVersion, builtAt = ns.version, GetTime()
    if index > #list then index = 0 end
end

function ns.WatchStatus()
    if not ns.Setting("watch") then return "Watch off." end
    if ns.at.auction and not ns.LookByItself() then
        return ns.YoursNow() and "Waiting while you use the auction house's own pages." or ""
    end
    if #list == 0 then return ns.Market().scanNo > 0 and "Nothing to watch yet." or "" end
    return "Watching " .. #list .. " items" .. (looking and (", now " .. ns.ItemName(looking)) or "") .. "."
end

local function Look()
    if not ns.LookByItself() or ns.Browsing() or ns.Searching() or ns.BuyBusy() then return end
    if GetTime() - lastLook < PAUSE then return end
    -- (a full scan whenever it's allowed, every 15 minutes: fresh prices, and what's selling needs scans close
    -- together. With no price memory yet and no full scan, the pages, once a visit. Only a look; /qah autoscan off
    -- stops it.)
    if ns.Setting("autoScan") and not ns.Scanning()
        and (ns.FullScanReady() or (not pagesRead and ns.Market().scanNo == 0)) then
        ns.Scan(false)
        if ns.Browsing() then pagesRead = true end
        if ns.Scanning() then return end
    end
    -- (the top of the list comes first: kept ready to buy, Buy.lua)
    ns.Prepare()
    if not ns.Setting("watch") or ns.Searching() or ns.BuyBusy() then return end
    if builtVersion ~= ns.version or GetTime() - builtAt > REBUILD then Build() end
    if #list == 0 then return end
    index = index % #list + 1
    local id = list[index]
    looking, lastLook = id, GetTime()
    local started = ns.Search(id, nil, function(ok, commodity, key)
        lastLook = GetTime()
        if ok then
            fails[id] = nil
            ns.TakeLookup(id, commodity, key)
        else
            fails[id] = (fails[id] or 0) + 1
            if fails[id] >= GIVE_UP then builtVersion = -1 end
        end
    end)
    if not started then looking = nil end
end

-- (a ticker while the auction house is open, none otherwise: nothing runs every frame)
local ticker
ns.Listen("auctions", { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }, function(_, event)
    if ticker then ticker:Cancel() end
    ticker, looking, pagesRead = nil, nil, false
    if event == "AUCTION_HOUSE_SHOW" and C_Timer.NewTicker then ticker = C_Timer.NewTicker(BEAT, Look) end
end)
