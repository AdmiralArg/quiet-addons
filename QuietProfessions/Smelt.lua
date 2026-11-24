-- Smelting for money: not for points. Mining's third tab (where a smith has Gear and a cook has Food).
--
-- Two questions, answered from the auction house's prices:
--  * what you have (bags, bank, mail, your other characters): is the ore worth more smelted? "Smelt 87 Iron Ore,
--    sell 87 Iron Bar: 3g more than selling the ore", or "Sell 87 Iron Ore as it is: smelting loses 1g". The bars
--    you hold are weighed the same way against what they make (bronze of copper and tin, steel of iron).
--  * what's listed: is there ore to buy, smelt and sell at a gain? The listings are taken from the cheapest up,
--    making by making, and it stops where the next making's materials cost more than what it makes brings: "Buy 140
--    Iron Ore, sell 140 Iron Bar: earns 2g 30s", and the most to pay for one.
-- What a thing brings is what Prices.lua says a sale brings: just under the cheapest listed, never over what it's
-- usually listed for, less the house's cut; or what a vendor pays, where that's more. A price asked isn't a sale,
-- and these prices move by the hour: every line says the prices it stands on, so it can be checked before buying.
-- Only what the recipe itself takes is weighed (bronze of bars, not of ore): smelt the ore, and the next look
-- weighs the bars.
local _, ns = ...

local MINING = 186
local MOST = 500   -- makings of bought materials weighed for one recipe, at most
local LEAST = 100  -- an earning under a silver isn't worth a line

function ns.Smelts(profID)
    return profID == MINING
end

-- The recipes that can be made now: learned (as the Mining window last told), or the trainer's up to your skill.
-- Then what it costs to learn first, where it's known not to be learned yet (before the window was ever opened
-- nothing is known of that, and nothing is said).
local function Usable(known, skill, r)
    if known and known[r.id] then return true end
    if r.learn > skill or not (r.how == "T" or r.how == "") then return false end
    return true, known and r.how == "T" and r.cost > 0 and r.cost or nil
end

-- What one of a thing brings, sold: the most of the auction house (after its cut) and a vendor.
-- -> each, at auction (false: a vendor's price), listed (how many are at auction now; nil: no auction price known)
local function Brings(id)
    local sale = ns.SaleOf(id)
    local vendor = ns.SellValue(id)
    if sale and sale.price > vendor then return sale.price, true, sale.listed end
    return vendor, false, sale and sale.listed or nil
end

-- "40 in your bags, 47 in the bank, Jon 12": where it is, when not all of it is in your bags
local function Where(have)
    local parts = {}
    if have.total == have.bags then return "" end
    if have.bags > 0 then parts[#parts + 1] = have.bags .. " in your bags" end
    if have.bank > 0 then parts[#parts + 1] = have.bank .. " in the bank" end
    if have.mail > 0 then parts[#parts + 1] = have.mail .. " in the mail" end
    if (have.pending or 0) > 0 then parts[#parts + 1] = have.pending .. " on their way" end
    for _, alt in ipairs(have.alts) do parts[#parts + 1] = alt.name .. " " .. alt.n end
    return table.concat(parts, ", ")
end

-- What smelting earns, for the profession the plan is of:
-- own = { { r, makings, makes (how many it makes), mats = { { id, n, each, auction, where } } (what goes into it of
--           yours, and what one would bring sold as it is), vendor = { { id, n, cost } } (to buy from a vendor for
--           it), each (what one made brings), auction, listed, gain (what smelting brings over selling the
--           materials; under 0: sell them as they are), unpriced (true: what's made has no auction price),
--           fee (to learn it first) } }
-- buy = { { r, makings, makes, mats = { { id, n, most (the dearest one bought), cost, vendor (true: a vendor's) } },
--           cost, each, listed, sells, profit, scan (true: a material's listings are only Quiet Auctions' cheapest
--           price), fee (to learn it first) } }
-- Both the most worth first.
function ns.Smelting(plan)
    local own, buy = {}, {}
    local prof = ns.professions[plan.prof]
    if not prof or not ns.Smelts(plan.prof) then return own, buy end
    local me = ns.Me()
    local known, skill = me and me.known[plan.prof], plan.input.skill
    for _, r in ipairs(prof.recipes) do
        local item = r.item ~= 0 and r.item or nil
        local usable, fee = Usable(known, skill, r)
        if item and (r.n or 0) > 0 and #r.reagents > 0 and usable then
            local each, auction, listed = Brings(item)

            -- (of what you have)
            local makings = math.huge
            local held = {}
            for i = 1, #r.reagents, 2 do
                local id, qty = r.reagents[i], r.reagents[i + 1]
                local total, have = ns.Have(id)
                held[id] = { total = total, have = have }
                if not ns.VendorPrice(id) then makings = math.min(makings, math.floor(total / qty)) end
            end
            -- (not what brings nothing sold: a lodestone, a rock garden)
            if makings ~= math.huge and makings >= 1 and each > 0 then
                local entry = { r = r, makings = makings, makes = makings * r.n, mats = {}, vendor = {}, each = each,
                    auction = auction, listed = listed, unpriced = listed == nil, fee = fee }
                local raw, bought = 0, 0
                for i = 1, #r.reagents, 2 do
                    local id, n = r.reagents[i], r.reagents[i + 1] * makings
                    local vendor = ns.VendorPrice(id)
                    if vendor then
                        local short = math.max(0, n - held[id].total)
                        if short > 0 then
                            entry.vendor[#entry.vendor + 1] = { id = id, n = short, cost = short * vendor }
                            bought = bought + short * vendor
                        end
                    else
                        local matEach, matAuction = Brings(id)
                        entry.mats[#entry.mats + 1] = { id = id, n = n, each = matEach, auction = matAuction,
                            where = Where(held[id].have) }
                        raw = raw + n * matEach
                    end
                end
                entry.gain = entry.makes * each - bought - raw
                own[#own + 1] = entry
            end

            -- (of what's listed: making by making from the cheapest, while a making earns)
            if auction and each > 0 then
                local cursors = {}
                local scan = false
                for i = 1, #r.reagents, 2 do
                    local id = r.reagents[i]
                    local price = plan.meta.price[id] or ns.PriceOf(id)
                    cursors[#cursors + 1] = { id = id, qty = r.reagents[i + 1], rows = price.rows, vendor = price.vendor,
                        i = 1, used = 0, n = 0, cost = 0, most = 0 }
                    if not price.vendor and price.source == "scan" then scan = true end
                end
                local revenue = r.n * each
                local count, cost = 0, 0
                while count < MOST do
                    -- (what the next making's materials cost: tried on copies of the places in the listings)
                    local nextCost, ok = 0, true
                    local tried = {}
                    for k, c in ipairs(cursors) do
                        local i, used, left, most = c.i, c.used, c.qty, c.most
                        local sum = 0
                        while left > 0 do
                            local rowPrice, rowQty = c.rows[i], c.rows[i + 1]
                            if c.vendor and (not rowPrice or rowPrice >= c.vendor) then
                                sum, most, left = sum + left * c.vendor, math.max(most, c.vendor), 0
                            elseif not rowPrice then
                                ok = false
                                break
                            else
                                local take = math.min(left, rowQty - used)
                                sum, left, used = sum + take * rowPrice, left - take, used + take
                                if take > 0 then most = rowPrice end
                                if used >= rowQty then i, used = i + 2, 0 end
                            end
                        end
                        if not ok then break end
                        tried[k] = { i = i, used = used, sum = sum, most = most }
                        nextCost = nextCost + sum
                    end
                    if not ok or nextCost >= revenue then break end
                    for k, c in ipairs(cursors) do
                        local t = tried[k]
                        c.i, c.used, c.most = t.i, t.used, t.most
                        c.n, c.cost = c.n + c.qty, c.cost + t.sum
                    end
                    count, cost = count + 1, cost + nextCost
                end
                local profit = count * revenue - cost
                if count >= 1 and profit >= LEAST then
                    local entry = { r = r, makings = count, makes = count * r.n, mats = {}, cost = cost, each = each,
                        listed = listed, sells = count * revenue, profit = profit, scan = scan, fee = fee }
                    for _, c in ipairs(cursors) do
                        entry.mats[#entry.mats + 1] = { id = c.id, n = c.n, most = c.most, cost = c.cost,
                            vendor = c.vendor ~= nil and c.most == c.vendor }
                    end
                    buy[#buy + 1] = entry
                end
            end
        end
    end
    table.sort(own, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.r.name < b.r.name
    end)
    table.sort(buy, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.r.name < b.r.name
    end)
    return own, buy
end

-- What to look up at the auction house for it: every material and everything made, of the recipes to be made now
function ns.SmeltItems(profID)
    local list = {}
    local prof = ns.professions[profID]
    local me = ns.Me()
    if not prof or not me or not ns.Smelts(profID) then return list end
    local known, skill = me.known[profID], ns.Skill(profID)
    for _, r in ipairs(prof.recipes) do
        if r.item ~= 0 and Usable(known, skill, r) then
            for i = 1, #r.reagents, 2 do list[#list + 1] = r.reagents[i] end
            list[#list + 1] = r.item
        end
    end
    return list
end
