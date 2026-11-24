-- Profession crates (WoW Forever): the cheapest way to fill each one at today's prices.
--
-- How the crates work (Forever 1.60, Nov 2026): a Waylaid Crate (dropped by mobs, chests and dungeon bosses, and sold
-- on the auction house) asks for ONE bundle out of a short list: "20 Peacebloom, or 20 Silverleaf, or 10 Earthroot...".
-- Use the crate, pick the bundle, click the materials in your bags (the whole amount from one stack). Filled, it
-- becomes a soulbound Sealed <tier> Crate for the quest "A Sealed Crate": Dokimi just west of the Crossroads (Horde,
-- Durotar Supply and Logistics) or Marcy Baker at Three Corners, Redridge (Alliance, Azeroth Commerce Authority), for
-- Merchant's Favor. Raw-material crates (herbs, ore, textiles, curiosities) seal white; crafted-goods crates (fabrics,
-- ingots, parts) seal green and pay double.
-- The bundles below are from the community guides (zockify.com, theforeverguides.com, wowforeverbuilds.com, which
-- agree); the crate and item ids from the game's own item data. The game doesn't let an addon read a crate's list, so
-- a list that changes in a patch is changed here.
--
-- For each bundle the cost is its materials at the cheapest now (the last scan's cheapest auction for one, or what a
-- vendor sells it for: the same as the Crafting tab), times how many. Where a character with the Crafting role knows a
-- recipe for it (bars from ore, bolts from cloth, parts), the materials for that are priced too, and the cheaper way
-- is said. Shown in the window's Crates tab and by /qah crates: crates in your bags first with every bundle, then every
-- crate with its best bundle and the next ones on a line under it.
local _, ns = ...

local SHOW = 6

-- The tiers, in order, and the level a crate of each needs
local TIERS = {
    { key = "Apprentice", level = 10 },
    { key = "Journeyman", level = 10 },
    { key = "Expert", level = 20 },
    { key = "Artisan", level = 35 },
}

-- { id (the empty crate), tier, name (after the tier), bundles = { itemID, how many, itemID, how many, ... } }
local CRATES = {
    -- Apprentice
    { id = 248682, tier = "Apprentice", name = "Herbs", bundles = { 2447, 20, 765, 20, 2449, 10, 785, 10, 2450, 10 } },
    { id = 248683, tier = "Apprentice", name = "Ore", bundles = { 2770, 20, 2771, 20 } },
    { id = 248684, tier = "Apprentice", name = "Textiles", bundles = { 2589, 40, 2318, 20 } },
    { id = 248685, tier = "Apprentice", name = "Curiosities", bundles = { 10940, 20, 10939, 4, 10978, 6, 11084, 2 } },
    { id = 248702, tier = "Apprentice", name = "Fabrics", bundles = { 4231, 2, 2996, 20 } },
    { id = 248703, tier = "Apprentice", name = "Ingots", bundles = { 2840, 20, 3576, 20, 2841, 10 } },
    { id = 248704, tier = "Apprentice", name = "Parts", bundles = { 4359, 16, 4361, 16, 4363, 4 } },
    -- Journeyman
    { id = 248686, tier = "Journeyman", name = "Herbs", bundles = { 3820, 10, 2453, 10, 3355, 10, 3369, 10, 3356, 10 } },
    { id = 248687, tier = "Journeyman", name = "Ore", bundles = { 2775, 10, 2772, 20 } },
    { id = 248688, tier = "Journeyman", name = "Textiles", bundles = { 2592, 20, 4306, 40, 2319, 20 } },
    { id = 248689, tier = "Journeyman", name = "Curiosities", bundles = { 11083, 20, 11082, 4, 11138, 6, 11139, 2 } },
    { id = 248705, tier = "Journeyman", name = "Fabrics", bundles = { 2997, 6, 4305, 10, 4233, 2 } },
    { id = 248706, tier = "Journeyman", name = "Ingots", bundles = { 2842, 10, 3575, 20 } },
    -- (45 Gold Power Core is what every guide says; it may be a misprint for 4 or 5)
    { id = 248707, tier = "Journeyman", name = "Parts", bundles = { 4371, 8, 4375, 7, 4382, 4, 10558, 45 } },
    -- Expert
    { id = 248690, tier = "Expert", name = "Earthly Herbs", bundles = { 3357, 20, 3818, 10, 3821, 10, 3358, 10 } },
    { id = 248691, tier = "Expert", name = "Flowering Herbs", bundles = { 3819, 10, 4625, 10, 8831, 20, 8836, 10 } },
    { id = 248692, tier = "Expert", name = "Ore", bundles = { 2776, 10, 3858, 20 } },
    { id = 248693, tier = "Expert", name = "Textiles", bundles = { 4338, 40, 4234, 20 } },
    { id = 248694, tier = "Expert", name = "Curiosities", bundles = { 11137, 20, 11135, 4, 11177, 6, 11178, 2 } },
    { id = 248708, tier = "Expert", name = "Fabrics", bundles = { 4339, 8, 4236, 2 } },
    { id = 248709, tier = "Expert", name = "Ingots", bundles = { 3860, 20, 3859, 15, 3577, 10 } },
    { id = 248710, tier = "Expert", name = "Parts", bundles = { 4387, 8, 10559, 5, 10560, 12, 10561, 5 } },
    -- Artisan
    { id = 248695, tier = "Artisan", name = "Earthly Herbs",
        bundles = { 13464, 10, 8838, 20, 8839, 10, 8845, 10, 8846, 10 } },
    { id = 248696, tier = "Artisan", name = "Flowering Herbs", bundles = { 13463, 20, 13465, 20, 13466, 20, 13467, 20 } },
    { id = 248697, tier = "Artisan", name = "Ore", bundles = { 7911, 10, 10620, 20, 11370, 20 } },
    { id = 248698, tier = "Artisan", name = "Textiles", bundles = { 14047, 40, 4304, 20, 8170, 20 } },
    { id = 248699, tier = "Artisan", name = "Curiosities", bundles = { 11176, 20, 11175, 4, 14343, 6, 14344, 2 } },
    { id = 248711, tier = "Artisan", name = "Fabrics", bundles = { 14048, 8, 8172, 2 } },
    { id = 248712, tier = "Artisan", name = "Ingots", bundles = { 11371, 2, 6037, 10, 12359, 20 } },
    { id = 248713, tier = "Artisan", name = "Parts", bundles = { 15994, 5, 18631, 5, 16000, 2 } },
}

local IS_CRATE = {}
for _, crate in ipairs(CRATES) do IS_CRATE[crate.id] = crate end

-- The crates in your bags: { [crateID] = how many } (kept until the bags or the lists change; a crafting-only
-- character doesn't count bag changes, so the list changing, a tab chosen say, reads them again too)
local inBags, inBagsKey = {}, nil
local function CratesInBags()
    local key = ns.version .. ":" .. ns.bagVersion
    if inBagsKey == key then return inBags end
    inBags, inBagsKey = {}, key
    ns.EachSlot(function(_, _, info)
        if IS_CRATE[info.itemID] then
            inBags[info.itemID] = (inBags[info.itemID] or 0) + (info.stackCount or 1)
        end
    end)
    return inBags
end

-- One bundle priced: { id, qty, cost (nil: no price yet), each, via ("auction", "vendor" or "craft"), notes = {} }
local function PriceBundle(id, qty)
    local e = { id = id, qty = qty, notes = {} }
    local each, via = ns.UnitCost(id)
    local craftEach, recipe = ns.CraftCost(id)
    if craftEach and (not each or craftEach < each) then
        if each then
            e.notes[#e.notes + 1] = "craft it: " .. ns.Money(craftEach * qty) .. " in materials ("
                .. (recipe.name or "a recipe you know") .. "), buying it " .. ns.Money(each * qty)
        else
            e.notes[#e.notes + 1] = "not on sale: crafting it costs " .. ns.Money(craftEach * qty) .. " in materials"
        end
        each, via = craftEach, "craft"
    end
    if each then
        e.each, e.via, e.cost = each, via, each * qty
    end
    if via == "auction" then
        local _, listed, scan = ns.Latest(id)
        if scan and scan < ns.Market().scanNo then
            e.notes[#e.notes + 1] = "not listed in the last scan (that price is older)"
        elseif listed and listed < qty then
            e.notes[#e.notes + 1] = "only " .. listed .. " listed"
        end
    end
    -- (the crate takes the whole amount from one stack)
    local stack = ns.StackSize(id)
    if stack > 1 and stack < qty then
        e.short = true
        e.notes[#e.notes + 1] = "stacks only to " .. stack .. ": the crate takes one stack, so this may not do"
    end
    return e
end

-- Cheapest first; ones that may not fit in one stack after the rest, and unpriced ones last
local function Cheaper(a, b)
    if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
    if (a.short or false) ~= (b.short or false) then return not a.short end
    if a.cost and b.cost and a.cost ~= b.cost then return a.cost < b.cost end
    return a.id < b.id
end

-- Every crate with its bundles, cheapest first: { { crate, bundles = { priced bundle, ... }, cratePrice } }
-- (worked out again only when something has changed)
local cache = { version = -1 }
function ns.CrateComparison()
    if cache.version == ns.version then return cache.list end
    local list = {}
    for _, crate in ipairs(CRATES) do
        local bundles = {}
        for i = 1, #crate.bundles, 2 do bundles[#bundles + 1] = PriceBundle(crate.bundles[i], crate.bundles[i + 1]) end
        table.sort(bundles, Cheaper)
        list[#list + 1] = { crate = crate, bundles = bundles, cratePrice = ns.Latest(crate.id) }
    end
    cache.version, cache.list = ns.version, list
    return list
end

local function CrateName(crate)
    return crate.tier .. " " .. crate.name
end

local function Bundle(e)
    return e.qty .. " " .. ns.ItemName(e.id)
end

local function Cost(e)
    if not e.cost then return "no price yet" end
    local how = e.via == "vendor" and " at a vendor" or (e.via == "craft" and " to craft" or "")
    return ns.Money(e.cost) .. how .. " (" .. ns.Money(e.each) .. " each)"
end

-- The next bundles after the best, short: "then 10 Briarthorn 1g 40s; 20 Silverleaf 2g"
local function Rest(bundles)
    local parts = {}
    for i = 2, math.min(#bundles, 4) do
        local e = bundles[i]
        parts[#parts + 1] = Bundle(e) .. " " .. (e.cost and ns.Money(e.cost) or "(no price)")
    end
    return #parts > 0 and ("then " .. table.concat(parts, "; ")) or nil
end

-- For the window: { { left, right, sub } or { header } } rows
local rowCache = { key = nil }
function ns.CrateRows()
    local key = ns.version .. ":" .. ns.bagVersion
    if rowCache.key == key then return rowCache.rows end
    local rows = {}
    local list, bags = ns.CrateComparison(), CratesInBags()
    if ns.Market().scanNo == 0 then
        rows[#rows + 1] = { "No scans yet: scan at the auction house, and this fills with today's prices." }
    end

    -- Crates you carry: every bundle
    for _, c in ipairs(list) do
        local n = bags[c.crate.id]
        if n then
            rows[#rows + 1] = { header = "In your bags: " .. CrateName(c.crate) .. " crate" .. (n > 1 and (" x" .. n) or "")
                .. " (one bundle fills it)" }
            for _, e in ipairs(c.bundles) do
                rows[#rows + 1] = { Bundle(e), Cost(e), sub = #e.notes > 0 and table.concat(e.notes, "; ") or nil,
                    id = e.id, count = e.qty, actions = { { "Plan", function() ns.PlanAdd(e.id, e.qty) end } } }
            end
        end
    end

    -- Every crate: the best bundle, the next ones under it
    for _, tier in ipairs(TIERS) do
        rows[#rows + 1] = { header = tier.key .. " crates (level " .. tier.level .. "): cheapest bundle to fill one" }
        for _, c in ipairs(list) do
            if c.crate.tier == tier.key then
                local best = c.bundles[1]
                local right = best.cost and (Bundle(best) .. ": " .. ns.Money(best.cost)
                    .. (best.via == "craft" and " to craft" or (best.via == "vendor" and " at a vendor" or "")))
                    or "no prices yet"
                local sub = {}
                local rest = best.cost and Rest(c.bundles)
                if rest then sub[#sub + 1] = rest end
                if c.cratePrice then sub[#sub + 1] = "the empty crate " .. ns.Money(c.cratePrice) .. " on the AH" end
                rows[#rows + 1] = { CrateName(c.crate), right, sub = #sub > 0 and table.concat(sub, "; ") or nil,
                    id = best.id, count = best.qty,
                    actions = { { "Plan", function() ns.PlanAdd(best.id, best.qty) end } } }
            end
        end
    end
    rows[#rows + 1] = { "At the auction house, click a line to look its item up there (the best bundle, for a crate)." }
    rows[#rows + 1] = { "Plan puts the bundle in the Plan tab: what you have, what to make, what to buy." }
    rows[#rows + 1] = { "Costs are from the cheapest listing: buying many, dearer listings push them up a little." }
    rows[#rows + 1] = { "Use the crate, pick the bundle, click it in your bags: the whole amount from one stack." }
    rows[#rows + 1] = { "Sealed, it goes to Dokimi (west of the Crossroads) or Marcy Baker (Three Corners, Redridge)." }
    rowCache.key, rowCache.rows = key, rows
    return rows
end

-- /qah crates
function ns.PrintCrates()
    if ns.Market().scanNo == 0 then
        ns.Print("no scans yet: scan at the auction house (/qah scan), then /qah crates shows the cheapest bundles.")
        return
    end
    local list, bags = ns.CrateComparison(), CratesInBags()
    local any = false
    for _, c in ipairs(list) do
        if bags[c.crate.id] then
            any = true
            ns.Print(CrateName(c.crate) .. " crate (in your bags), cheapest bundles:")
            for i = 1, math.min(#c.bundles, SHOW) do
                print("  " .. Bundle(c.bundles[i]) .. ":  " .. Cost(c.bundles[i]))
            end
        end
    end
    if not any then
        ns.Print("no Waylaid Crate in your bags. The cheapest bundle for each crate is in the window's Crates tab.")
    end
end

-- A crate looted or filled while the Crates tab is up: shown at once
ns.Listen("any", { "BAG_UPDATE_DELAYED" }, function()
    if ns.WindowTab and ns.WindowTab() == "crates" then
        ns.Changed()
        ns.Refresh()
    end
end)
