-- The price memory read back (Scan.lua writes it: each scan, every item's cheapest for one and how many were listed;
-- the last 8 scans kept). Three lists from it, of things you can gather, craft or buy to sell again only: trade goods,
-- reagents, consumables and gems (and bags and ammo in the first). (Gear and recipes sell over vendor price because
-- they're rare drops: nothing to plan around, so they're left out.)
--  * what's selling: how many seem to sell an hour, and the gold that is. Guessed from listings that are gone by the
--    next scan (scans up to half an hour apart), so cancelled and expired auctions count too: a rough guide to what
--    players buy, not an exact one. The most gold an hour first.
--  * worth more than vendor price: listed in most scans, usually for well over what a vendor pays (after the auction
--    house's 5% cut). Ranked by the gain over vendoring each times how many are usually listed: where real gold
--    moves, not one dear item. Post.lua posts only these. Marked "you craft it" where a noted recipe makes it.
--  * rarely listed: seen in few of the scans since it was first seen. A shortage: worth crafting or gathering for.
local _, ns = ...

local CUT = 0.95 -- (what a sale brings after the auction house's cut)
local WELL_OVER = 1.5 -- (usual price after the cut at least this many times the vendor's)
local OFTEN = 0.6
local RARELY = 0.35
local MIN_SCANS = 3
local SHOW = 12
-- Item classes worth planning around: consumable, gem, reagent, trade goods
local TRADE_CLASSES = { [0] = true, [3] = true, [5] = true, [7] = true }
-- ...and for what's selling also bags and ammo, which low levels buy plenty of
local SELLING_CLASSES = { [0] = true, [1] = true, [3] = true, [5] = true, [6] = true, [7] = true }
local GAP = 30 * 60 -- (scans further apart than this tell little about what sold between them)
local MIN_GAPS = 2

ns.CUT = CUT

local function History(id)
    local p = ns.Market().prices[id]
    return p and p.h or nil, p
end

-- The cheapest for one in the last scan it was listed in: price, quantity, scan number
function ns.Latest(id)
    local h = History(id)
    if not h or #h < 3 then return nil end
    return h[#h - 1], h[#h], h[#h - 2]
end

-- Its usual price: the middle of its remembered cheapest prices, how many scans that's from, and how many are
-- usually listed. (Asked for thousands of items at a time by the lists: worked out once until the memory changes.)
local usual, usualVersion = {}, -1
function ns.Usual(id)
    if usualVersion ~= ns.version then usual, usualVersion = {}, ns.version end
    local kept = usual[id]
    if kept then return kept[1], kept[2], kept[3] end
    local h = History(id)
    if not h or #h < 3 then return nil, 0 end
    local prices, quantities = {}, {}
    for i = 1, #h, 3 do
        prices[#prices + 1] = h[i + 1]
        quantities[#quantities + 1] = h[i + 2]
    end
    table.sort(prices)
    table.sort(quantities)
    local middle = math.floor((#prices + 1) / 2)
    usual[id] = { prices[middle], #prices, quantities[middle] }
    return prices[middle], #prices, quantities[middle]
end

-- The share of recent scans (the last 8, since it was first seen) it was listed in, and how many scans that's of
function ns.Presence(id)
    local h, p = History(id)
    local market = ns.Market()
    if not h then return 0, 0 end
    local from = math.max(p.f or 1, market.scanNo - 7)
    local possible = market.scanNo - from + 1
    if possible <= 0 then return 0, 0 end
    local seen = 0
    for i = 1, #h, 3 do
        if h[i] >= from then seen = seen + 1 end
    end
    return math.min(1, seen / possible), possible
end

-- A trade good, reagent, consumable or gem (false while the game hasn't described it yet: asked for)
local function Tradeable(id)
    return TRADE_CLASSES[ns.ItemClass(id) or -1] == true
end

-- What's selling (see the top): { { id, perHour, goldPerHour, usual, qty, crafted } }, the most gold an hour first.
-- (Not ns.Selling: that's Sell's, Vendor.lua, which once took this one's place and broke the Prices tab.)
local sellingCache = { version = -1 }
function ns.WhatSells()
    if sellingCache.version == ns.version then return sellingCache.list end
    local list = {}
    sellingCache.version, sellingCache.list = ns.version, list
    local scanAt = ns.Market().scanAt
    local made = ns.Crafted()
    for id, p in pairs(ns.Market().prices) do
        local h = p.h
        if #h >= 6 and SELLING_CLASSES[ns.ItemClass(id) or -1] then
            local gone, gold, seconds, gaps = 0, 0, 0, 0
            for i = 4, #h, 3 do
                -- (two scans in a row, close enough together: what was listed before and isn't now)
                local before, after = scanAt[h[i - 3]], scanAt[h[i]]
                if h[i] == h[i - 3] + 1 and before and after and after > before and after - before <= GAP then
                    local drop = math.max(0, h[i - 1] - h[i + 2])
                    gone, gold = gone + drop, gold + drop * h[i - 2]
                    seconds, gaps = seconds + (after - before), gaps + 1
                end
            end
            if gaps >= MIN_GAPS and gone > 0 then
                local usual, _, qty = ns.Usual(id)
                list[#list + 1] = { id = id, perHour = gone * 3600 / seconds, goldPerHour = gold * 3600 / seconds,
                    usual = usual, qty = qty or 0, crafted = made[id] }
            end
        end
    end
    table.sort(list, function(a, b) return a.goldPerHour > b.goldPerHour end)
    return list
end

-- Worth more than vendor price (see the top): { { id, usual, vendor, gain (each), presence, qty, crafted } }, the
-- most gold moving first. (Thousands of items: worked out again only when something has changed, ns.Changed. An item
-- the game hasn't described yet is left out until then.)
local wellCache = { version = -1 }
function ns.SellsWell()
    if wellCache.version == ns.version then return wellCache.list end
    local list = {}
    wellCache.version, wellCache.list = ns.version, list
    local made = ns.Crafted()
    for id in pairs(ns.Market().prices) do
        local usual, scans, qty = ns.Usual(id)
        local presence = ns.Presence(id)
        local vendor = usual and scans >= MIN_SCANS and presence >= OFTEN and Tradeable(id) and ns.SellPrice(id)
        if vendor then
            local gain = usual * CUT - vendor
            if usual * CUT >= vendor * WELL_OVER and gain >= 10 then
                list[#list + 1] = { id = id, usual = usual, vendor = vendor, gain = gain, presence = presence,
                    qty = qty or 0, crafted = made[id], moving = gain * math.max(1, qty or 0) }
            end
        end
    end
    table.sort(list, function(a, b) return a.moving > b.moving end)
    return list
end

-- Rarely listed: { { id, usual, presence, scans, crafted } }, the ones you craft first, then dearest first
function ns.RarelyListed()
    local list = {}
    local made = ns.Crafted()
    for id in pairs(ns.Market().prices) do
        local presence, scans = ns.Presence(id)
        if scans >= 4 and presence <= RARELY and Tradeable(id) then
            local usual = ns.Usual(id)
            if usual then
                list[#list + 1] = { id = id, usual = usual, presence = presence, scans = scans, crafted = made[id] }
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.crafted or false) ~= (b.crafted or false) then return a.crafted == true end
        return a.usual > b.usual
    end)
    return list
end

local function Percent(x)
    return math.floor(x * 100 + 0.5) .. "%"
end

local function Name(e)
    return ns.ItemName(e.id) .. (e.crafted and "  |cff66ccff(you craft it)|r" or "")
end

local function WellText(e)
    return "usually " .. ns.Money(e.usual) .. ", vendor " .. ns.Money(e.vendor) .. ", ~" .. e.qty .. " listed"
end

local function RareText(e)
    return "usually " .. ns.Money(e.usual) .. ", in " .. Percent(e.presence) .. " of " .. e.scans .. " scans"
end

local function SellingText(e)
    return "~" .. math.floor(e.perHour + 0.5) .. " an hour at " .. ns.Money(e.usual or 0) .. ", "
        .. ns.Money(e.goldPerHour) .. "/h, ~" .. e.qty .. " listed"
end

local NO_SELLING = "Nothing yet: it needs a few scans up to half an hour apart."

-- For the window: { { left, right } or { header } } rows (worked out again only when something has changed)
local cache = { version = -1 }
function ns.PriceRows()
    local market = ns.Market()
    if cache.version == ns.version then return cache.rows end
    local rows = {}
    cache.version, cache.rows = ns.version, rows
    if market.scanNo == 0 then
        rows[1] = { "No scans yet: the price memory fills with each scan at the auction house." }
        return rows
    end
    local selling = ns.WhatSells()
    rows[#rows + 1] = { header = "What's selling, roughly (gone between scans; " .. #selling .. ")" }
    for i = 1, math.min(#selling, 40) do rows[#rows + 1] = { Name(selling[i]), SellingText(selling[i]), id = selling[i].id } end
    if #selling == 0 then rows[#rows + 1] = { NO_SELLING } end
    local well = ns.SellsWell()
    rows[#rows + 1] = { header = "Materials and consumables worth more than vendor price (" .. #well .. ")" }
    for i = 1, math.min(#well, 40) do rows[#rows + 1] = { Name(well[i]), WellText(well[i]), id = well[i].id } end
    if #well == 0 then rows[#rows + 1] = { "Nothing yet: it needs " .. MIN_SCANS .. " scans or more." } end
    local rare = ns.RarelyListed()
    rows[#rows + 1] = { header = "Rarely listed: worth crafting or gathering (" .. #rare .. ")" }
    for i = 1, math.min(#rare, 40) do rows[#rows + 1] = { Name(rare[i]), RareText(rare[i]), id = rare[i].id } end
    if #rare == 0 then rows[#rows + 1] = { "Nothing yet: it needs 4 scans or more." } end
    return rows
end

-- /qah prices
function ns.PrintPrices()
    local market = ns.Market()
    if market.scanNo == 0 then
        ns.Print("no scans yet: scan at the auction house (/qah scan) a few times over a few days.")
        return
    end
    local selling, well, rare = ns.WhatSells(), ns.SellsWell(), ns.RarelyListed()
    ns.Print("from " .. market.scanNo .. " scans. What's selling, roughly (listings gone between scans):")
    for i = 1, math.min(#selling, SHOW) do print("  " .. Name(selling[i]) .. "  " .. SellingText(selling[i])) end
    if #selling == 0 then print("  " .. NO_SELLING:lower()) end
    print("  Materials and consumables worth more than vendor price:")
    for i = 1, math.min(#well, SHOW) do print("  " .. Name(well[i]) .. "  " .. WellText(well[i])) end
    if #well == 0 then print("  nothing yet (it needs " .. MIN_SCANS .. " scans or more).") end
    print("  Rarely listed (worth crafting or gathering):")
    for i = 1, math.min(#rare, SHOW) do print("  " .. Name(rare[i]) .. "  " .. RareText(rare[i])) end
    if #rare == 0 then print("  nothing yet (it needs 4 scans or more).") end
end
