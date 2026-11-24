-- The route: from the skill you have to the one you want, which recipe to make at each point so the whole costs least.
-- Plain Lua, nothing of the game's in it (Plan.lua hands it tables and gets tables back), so it can be run and tested
-- outside the game (tools\profession-data\test-solver.lua).
--
-- How it reckons:
--  * a recipe gives a point for sure until it turns yellow, then less and less until it's grey:
--    chance = (grey - skill) / (grey - yellow). A point costs one making divided by that chance.
--  * what a making costs is what its materials cost NOW, from what's there: first what you have (free, or what it
--    would sell for: your choice), then the auction house's listings from the cheapest up, each only as many as are
--    listed (so 200 iron bars don't cost 200 times the cheapest one), then a vendor. A material you could make
--    yourself (a grinding stone, a bar) is made when that's cheaper than buying it.
--  * what's made is worth something: what a vendor pays, and for the first one or few of a thing what the auction
--    house would bring, if you ask for that (input.sale: nobody buys forty of the same leggings). Unless a later
--    step needs it (the grinding stones made for points at 75 are the ones used at 100: they're counted once).
--  * a recipe still to be learned costs its price once (the trainer's, a vendor's or the auction house's plans):
--    it's taken only if what it saves is more than that.
--  * gear you asked for (Gear.lua) is made once, as soon as the skill is there, and its points are counted: an
--    orange one gives a point for sure, a yellow one is counted when it's more likely than not (what's counted
--    too much or too little that way is carried to the next piece). Of several made at the same skill, the one
--    nearest grey first, while it still gives something. Food you asked for (Food.lua) the same, as many
--    makings as you asked.
--  * food that suits your class (input.prefer) is made where it gives points, the most wanted kind first and of
--    a kind the one that gives the most, even when another recipe is cheaper: what you level on is then food you
--    can eat, and the route doesn't go back to a worse one. Among those that stand the same, the cheapest.
--  * a tool a recipe needs (a smith's hammer, an enchanter's runed rod, an engineer's spanner) is needed once, not
--    for every making: one you hold costs nothing; one you lack is got once, at the first step that needs it, and
--    is there for every step after. Made where a recipe of yours makes it (its own step, its materials priced as
--    any other's, the point it may give counted), bought where a vendor or the auction house has it, whichever is
--    cheaper; or kept, of those an earlier step made for points. A recipe is weighed with what its tool costs
--    spread over the points still to go; one whose tool can't be had at this skill is passed over. The basic
--    tools (BASIC_TOOLS, below: a few copper at any trade vendor) count as yours always: never a step.
-- Point by point the cheapest recipe is taken ("greedy"), then the whole is run again a few times to settle what a
-- learned recipe really saved and which made things are used later. Not proven the very cheapest, but close, and
-- from today's prices rather than a guide's.
--
-- input = {
--   skill, target,
--   recipes = { { id, name, item, n (made each time), learn, yellow, grey, reagents = { item, qty, ... },
--                 known (true: learned), learnCost (nil: can't be learned now), how (text: where it's learned),
--                 aux (true: of another profession: makes materials, gives no points), usable (aux: can be made),
--                 tools = { { item, another that does for it, ... }, ... } or nil (each needed once) } },
--   supply = { [item] = { stock, stockPrice, rows = { price, qty, ... }, vendor, guess } },
--   value = { [item] = what one brings from a vendor },
--   sale = { [item] = { price (one at auction, the house's cut off), units (how many are counted on) } } or nil,
--   held = { [item] = true },        the tools you hold (yours, here: nothing to get), or nil
--   must = { { recipe, who, crafts (makings: 1 if nil), food (true: to eat, not to wear) } },
--                                    gear and food to make along the way
--   fixed = { [skill] = recipe },    points whose recipe is settled (planned): made with it, not weighed
--   prefer = { [recipe] = number },  recipes made before any cheaper one while they give points (the lowest
--                                    number first; the cheapest of those with the same), or nil
--   minChance,                       a recipe less likely than this to give a point is passed over while another will
--   tick = function() end,           called at every point (the game's side rests there when a frame runs long)
-- }
-- Solve(input) -> {
--   steps = { { kind = "level", r, from, to, crafts, cost, back, mats = { [item] = n }, subs = { [recipe] = crafts },
--               fee, chance, chanceEnd }
--           | { kind = "gear", r, who, at, crafts, food, cost, fee, gain, mats, subs }
--           | the same with tool = item and how = "make" (r: the recipe that makes it), "buy" or "keep" (one of
--             those an earlier step made; for both r is a stand-in that makes nothing and mats is the tool itself):
--             a tool got once, for the steps after it. No who. },
--   items = { [item] = { stock, auction, vendor, beyond, guess, made, pool, cost, paid } },   what's used, from where
--   fees = { { r, fee } }, reached, stuck (a skill: nothing gives points there), blocked = { recipes that would },
--   later = { { r, who, why } }, spend, paid, feeTotal, back, hoped (the part of back that counts on sales at
--   auction), total,
--   points = { [skill] = what that point cost }
-- }
local _, ns = ...

local Solver = {}
ns.Solver = Solver

local EPS = 1e-7
local MAX_DEPTH = 3      -- a material made of a material made of a material
local MIN_CHANCE = 0.25  -- a recipe nearer grey than this (a point in four) is left alone...
local LAST_CHANCE = 0.1  -- ...unless nothing else gives points at all
local STICK = 0.03       -- the recipe being made stays unless another is this much cheaper (no hopping to and fro)
local BEYOND = 1.3       -- more than is listed: reckoned at the dearest listing and this much more
local SHORT = 6          -- the recipes weighed at every point; all of them every FULL_EVERY points
local FULL_EVERY = 5
local PREFER_CHANCE = 0.5 -- a preferred recipe (input.prefer) goes first only while it gives a point every other making
local NO_TIER = 1e9
local HUGE = math.huge

-- The chance of a point from recipe r at this skill
local function Chance(r, skill)
    if skill < r.learn or skill >= r.grey then return 0 end
    if skill < r.yellow then return 1 end
    local span = r.grey - r.yellow
    if span <= 0 then return 0 end
    return (r.grey - skill) / span
end
Solver.Chance = Chance

-- ---------- what can be undone ----------
-- Every change to the state goes through Set, which notes the old value: a recipe is tried (what would it cost
-- now?) and then undone again.
local function Set(st, tbl, key, value)
    local j = st.journal
    local n = #j
    local old = tbl[key]
    -- (a list can't hold nil: "there was nothing" is noted as st.NIL)
    if old == nil then old = st.NIL end
    j[n + 1], j[n + 2], j[n + 3] = tbl, key, old
    tbl[key] = value
end

local function Add(st, tbl, key, amount)
    Set(st, tbl, key, (tbl[key] or 0) + amount)
end

local function Rollback(st, mark)
    local j = st.journal
    for n = #j, mark + 1, -3 do
        local tbl, key, old = j[n - 2], j[n - 1], j[n]
        if old == st.NIL then old = nil end
        tbl[key] = old
        j[n], j[n - 1], j[n - 2] = nil, nil, nil
    end
end

-- ---------- what there is of an item ----------
-- Its sources from the cheapest up: { price, qty, kind }, the last one without end (a vendor, or a guess)
local function NewSupply(src, noStock)
    src = src or {}
    local segs = {}
    local rows = src.rows or {}
    for i = 1, #rows, 2 do
        if rows[i + 1] > 0 and (not src.vendor or rows[i] < src.vendor) then
            segs[#segs + 1] = { price = rows[i], qty = rows[i + 1], kind = "auction" }
        end
    end
    table.sort(segs, function(a, b) return a.price < b.price end)
    if src.vendor then
        segs[#segs + 1] = { price = src.vendor, qty = HUGE, kind = "vendor" }
    elseif #segs > 0 then
        segs[#segs + 1] = { price = segs[#segs].price * BEYOND, qty = HUGE, kind = "beyond" }
    else
        segs[#segs + 1] = { price = src.guess or 0, qty = HUGE, kind = "guess" }
    end
    if (src.stock or 0) > 0 and not noStock then
        -- (your own first: never dearer than the cheapest other way)
        local price = math.min(src.stockPrice or 0, segs[1].price)
        table.insert(segs, 1, { price = price, qty = src.stock, kind = "stock" })
    end
    return { segs = segs, i = 1, used = 0 }
end

local function SupplyOf(st, item)
    local sup = st.supply[item]
    if not sup then
        sup = NewSupply(st.input.supply[item], st.noStock)
        st.supply[item] = sup
    end
    return sup
end

local function TakeOf(st, item)
    local t = st.items[item]
    if not t then
        t = {}
        st.items[item] = t
    end
    return t
end

-- The recipe that makes an item, if one can be used now
local function MakerFor(st, item)
    local list = st.makers[item]
    if not list then return nil end
    for _, r in ipairs(list) do
        if not st.banned[r.id] and (st.learned[r] or r.learnCost) then
            if r.aux then
                if r.usable then return r end
            elseif r.learn <= st.skill then
                return r
            end
        end
    end
end

local Craft, Tools

-- What a recipe still to be learned costs, paid now (0 if it's known)
local function PayFee(st, r)
    if st.learned[r] then return 0 end
    Set(st, st.learned, r, true)
    local fee = r.learnCost or 0
    Set(st, st.fees, #st.fees + 1, { r = r, fee = fee })
    return fee
end

-- n of an item for a making: what it costs, taken from the cheapest places (and noted where from)
local function Acquire(st, item, n, depth)
    local sup = SupplyOf(st, item)
    local pool = st.pool[item]
    local t = TakeOf(st, item)
    local maker = depth < MAX_DEPTH and not st.busy[item] and MakerFor(st, item) or nil
    local unitCraft
    if maker then
        -- (what one would cost made now: tried, then undone. A tool it needs and you lack counts with it, as the
        -- price of learning it does; one that can't be had now rules it out)
        st.busy[item] = true
        local mark = #st.journal
        local kit = Tools(st, maker, depth + 1)
        if kit then
            local fee = st.learned[maker] and 0 or (maker.learnCost or 0)
            unitCraft = (Craft(st, maker, 1 / maker.n, depth + 1)) + (fee + kit) / math.max(n, 1)
        end
        Rollback(st, mark)
        st.busy[item] = nil
        if not kit then maker = nil end
    end
    local cost, left, bought, boughtCost = 0, n, 0, 0
    while left > EPS do
        local seg = sup.segs[sup.i]
        local segPrice = seg and seg.price or HUGE
        local poolPrice = pool and pool.qty > EPS and (pool.value / pool.qty) or nil
        local fromPool = poolPrice ~= nil and poolPrice <= segPrice
        if unitCraft and unitCraft < (fromPool and poolPrice or segPrice) then break end
        if fromPool then
            local take = math.min(left, pool.qty)
            local share = take / pool.qty
            Set(st, pool, "base", pool.base - pool.base * share)
            Set(st, pool, "value", pool.value - take * poolPrice)
            Set(st, pool, "qty", pool.qty - take)
            cost = cost + take * poolPrice
            Add(st, t, "pool", take)
            left = left - take
        else
            if not seg then break end
            local take = math.min(left, seg.qty - sup.used)
            cost = cost + take * seg.price
            Add(st, t, seg.kind, take)
            Add(st, t, "cost", take * seg.price)
            if seg.kind ~= "stock" then Add(st, t, "paid", take * seg.price) end
            if seg.kind == "guess" then Add(st, st, "guessed", take) end
            bought, boughtCost = bought + take, boughtCost + take * seg.price
            left = left - take
            if seg.qty ~= HUGE and sup.used + take >= seg.qty - EPS then
                Set(st, sup, "i", sup.i + 1)
                Set(st, sup, "used", 0)
            else
                Set(st, sup, "used", sup.used + take)
            end
        end
    end
    if left > EPS and maker then
        st.busy[item] = true
        local crafts = left / maker.n
        -- (its tools are got here and are steps of their own: their cost isn't this material's)
        Tools(st, maker, depth + 1)
        local made = PayFee(st, maker) + Craft(st, maker, crafts, depth + 1)
        cost = cost + made
        Add(st, st.subs, maker, crafts)
        Add(st, t, "made", left)
        bought, boughtCost = bought + left, boughtCost + made
        st.busy[item] = nil
    end
    -- (for the next run: how much of it is used as a material, and what one costs when it isn't one made earlier)
    Add(st, st.demand, item, n)
    if bought > EPS then
        Add(st, st.replQty, item, bought)
        Add(st, st.replCost, item, boughtCost)
    end
    return cost
end

-- The materials for so many makings of r
function Craft(st, r, crafts, depth)
    local cost = 0
    local reagents = r.reagents
    for i = 1, #reagents, 2 do
        cost = cost + Acquire(st, reagents[i], reagents[i + 1] * crafts, depth)
    end
    return cost
end

-- ---------- tools ----------
-- A recipe's tools (r.tools) are needed once each, not for every making. st.tools holds the ones there are: yours
-- from the start (input.held), and each one got on the way. Every one got is noted in st.toolLog, for the route to
-- show as a step of its own: { item, how ("make", "buy", "keep"), cost, r, fee, subs (when made) }.
local function HasTool(st, kind)
    for _, item in ipairs(kind) do
        if st.tools[item] then return true end
    end
    return false
end

local function GotTool(st, entry)
    Set(st, st.tools, entry.item, true)
    Set(st, st.toolLog, #st.toolLog + 1, entry)
    -- (what tools cost since a mark: a recipe being weighed is charged for the ones it brought on)
    Add(st, st, "toolSpent", entry.cost + (entry.fee or 0))
end

-- One kind of tool, got for good: what that costs (0: it's there), or nil if there's no way to it at this skill.
-- The item the kind is named for is the one got (kind[1]); the others only count when held.
local function GetTool(st, kind, depth)
    if HasTool(st, kind) then return 0 end
    local item = kind[1]
    -- (being made further up: a tool can't need itself)
    if st.busyTool[item] then return nil end
    -- One an earlier step made, for points: kept, so not sold
    local pool = st.pool[item]
    if pool and pool.qty >= 1 - EPS then
        local each = pool.value / pool.qty
        Set(st, pool, "base", pool.base - pool.base / pool.qty)
        Set(st, pool, "value", pool.value - each)
        Set(st, pool, "qty", pool.qty - 1)
        GotTool(st, { item = item, how = "keep", cost = each })
        return each
    end
    -- Bought: only where there's one to buy (a listing, a vendor, one another character of yours can mail), never
    -- at a guessed price: a runed rod binds to its maker and is nowhere for sale
    local sup = SupplyOf(st, item)
    local seg = sup.segs[sup.i]
    if seg and not (seg.kind == "stock" or seg.kind == "auction" or seg.kind == "vendor") then seg = nil end
    -- Made: one making of the recipe that makes it, if that can be made now (its own tools first)
    local maker = depth < MAX_DEPTH and MakerFor(st, item) or nil
    local makeCost
    if maker then
        st.busyTool[item] = true
        local mark = #st.journal
        local kit = Tools(st, maker, depth + 1)
        if kit then
            makeCost = kit + (st.learned[maker] and 0 or (maker.learnCost or 0)) + Craft(st, maker, 1, depth + 1)
        end
        Rollback(st, mark)
        st.busyTool[item] = nil
    end
    if makeCost and (not seg or makeCost < seg.price) then
        st.busyTool[item] = true
        -- (what's made first for the tool is its own step's, not the step's that was being reckoned)
        local outer = st.subs
        st.subs = {}
        local kit = Tools(st, maker, depth + 1) or 0
        local fee = PayFee(st, maker)
        local cost = Craft(st, maker, 1, depth + 1)
        local subs = st.subs
        st.subs = outer
        st.busyTool[item] = nil
        GotTool(st, { item = item, how = "make", cost = cost, r = maker, fee = fee, subs = subs })
        return kit + fee + cost
    elseif seg then
        local cost = Acquire(st, item, 1, MAX_DEPTH)
        GotTool(st, { item = item, how = "buy", cost = cost })
        return cost
    end
    return nil
end

-- Every tool r needs and you lack, got: what they cost together, or nil if one can't be had now
function Tools(st, r, depth)
    local kinds = r.tools
    if not kinds then return 0 end
    local cost = 0
    for _, kind in ipairs(kinds) do
        local each = GetTool(st, kind, depth)
        if not each then return nil end
        cost = cost + each
    end
    return cost
end

-- What so many of an item bring when sold
-- (at auction only as many as are counted on, the ones made first; the rest to a vendor)
local function Salvage(st, item, units)
    local value = st.input.value[item] or 0
    local sale = st.input.sale and st.input.sale[item]
    if not sale or sale.price <= value then return units * value end
    local atAuction = math.max(0, math.min(units, sale.units - (st.produced[item] or 0)))
    return atAuction * sale.price + (units - atAuction) * value
end

-- What so many makings of r leave you with: counted as money back, and kept for a later step that needs them
local function Credit(st, r, crafts)
    local item = r.item
    if not item or item == 0 or (r.n or 0) <= 0 then return 0 end
    local units = crafts * r.n
    local base = Salvage(st, item, units)
    local credit = base
    local future = st.future[item]
    if future then
        local done = st.produced[item] or 0
        local wanted = math.max(0, math.min(units, future.need - done))
        if wanted > 0 and future.value * wanted > base * wanted / units then
            credit = base * (units - wanted) / units + future.value * wanted
        end
    end
    local pool = st.pool[item]
    if not pool then
        pool = { qty = 0, value = 0, base = 0 }
        st.pool[item] = pool
    end
    Set(st, pool, "qty", pool.qty + units)
    Set(st, pool, "value", pool.value + credit)
    Set(st, pool, "base", pool.base + base)
    Add(st, st.produced, item, units)
    return credit
end

local function MergeInto(into, from, scale)
    for key, amount in pairs(from) do into[key] = (into[key] or 0) + amount * (scale or 1) end
end

local function DirectMats(r, crafts, mats)
    local reagents = r.reagents
    for i = 1, #reagents, 2 do
        mats[reagents[i]] = (mats[reagents[i]] or 0) + reagents[i + 1] * crafts
    end
end

-- ---------- one run ----------
-- Tools sold for a few copper by any trade vendor, counted as held: Blacksmith Hammer, Flint and Tinder, Skinning
-- Knife, Mining Pick, Fishing Pole
local BASIC_TOOLS = { 5956, 4471, 7005, 2901, 6256 }
Solver.BASIC_TOOLS = BASIC_TOOLS

-- Where a reckoning starts: nothing used yet, the known recipes learned, and which recipe makes which item
local function NewState(input, banned, future)
    local st = {
        input = input, banned = banned, future = future, NIL = {},
        journal = {}, supply = {}, pool = {}, items = {}, learned = {}, fees = {}, subs = {}, busy = {},
        demand = {}, replQty = {}, replCost = {}, produced = {}, makers = {}, skill = input.skill,
        tools = {}, toolLog = {}, busyTool = {},
    }
    for _, item in ipairs(BASIC_TOOLS) do st.tools[item] = true end
    for item, held in pairs(input.held or {}) do
        if held then st.tools[item] = true end
    end
    for _, r in ipairs(input.recipes) do
        if r.known then st.learned[r] = true end
        if r.item and r.item ~= 0 and (r.n or 0) > 0 then
            local list = st.makers[r.item] or {}
            st.makers[r.item] = list
            -- (a known one first)
            if r.known then table.insert(list, 1, r) else list[#list + 1] = r end
        end
    end
    return st
end

local function Run(input, banned, future)
    local st = NewState(input, banned, future)
    local candidates = {}
    for _, r in ipairs(input.recipes) do
        if not r.aux and not banned[r.id] and (r.known or r.learnCost) then candidates[#candidates + 1] = r end
    end

    local out = { steps = {}, later = {}, blocked = {}, benefit = {}, feeOf = {}, points = {} }
    local steps = out.steps
    local pending = {}
    for _, m in ipairs(input.must or {}) do
        local r = m.recipe
        if not (r.known or r.learnCost) then
            out.later[#out.later + 1] = { r = r, who = m.who, why = "recipe" }
        elseif r.learn > input.target and r.learn > input.skill then
            out.later[#out.later + 1] = { r = r, who = m.who, why = "skill" }
        else
            pending[#pending + 1] = m
        end
    end

    local skill, target = input.skill, math.max(input.target, input.skill)
    local carry, last = 0, nil
    local hopedTotal = 0
    -- Every recipe is weighed where something changes (one can be learned, gear was made) and every few points;
    -- in between only the few that came out best then (most of the reckoning, for nothing, otherwise).
    local opensAt = {}
    for _, r in ipairs(candidates) do opensAt[r.learn] = true end
    local short, shortAt

    -- The points counted from one-off makings (gear, a tool) are had before what's made next
    local function Carry()
        local moved = false
        while carry >= 0.5 and skill < target do
            skill, carry, moved = skill + 1, carry - 1, true
        end
        st.skill = skill
        return moved
    end

    -- The tools got since (st.toolLog, from there on) as steps of their own, before the step that needed them:
    -- made (its materials, the point it may give), bought, or kept of what an earlier step made
    local function ToolSteps(from)
        for i = from + 1, #st.toolLog do
            local e = st.toolLog[i]
            local r = e.r
            local gain = 0
            if r and not r.aux then gain = math.min(Chance(r, skill), math.max(0, r.grey - skill)) end
            local step = { kind = "gear", tool = e.item, how = e.how, at = skill, crafts = 1, cost = e.cost,
                fee = e.fee and e.fee > 0 and e.fee or nil, gain = gain, mats = {}, subs = {},
                -- (bought or kept: nothing is made. A stand-in, so a step always has a recipe)
                r = r or { id = 0, name = "", item = e.item, n = 1, learn = skill, yellow = skill, grey = skill,
                    reagents = {}, known = true, stub = true } }
            if r then
                DirectMats(r, 1, step.mats)
                MergeInto(step.subs, e.subs)
                if step.fee then out.feeOf[r] = step.fee end
                out.benefit[r] = HUGE
            else
                step.mats[e.item] = 1
            end
            steps[#steps + 1] = step
            carry = carry + gain
        end
    end

    -- Gear that can be made now is made now, and the points it gives are had before the next piece is made
    local function MakeGear()
        local at = skill
        local now = {}
        for i = #pending, 1, -1 do
            if pending[i].recipe.learn <= at then now[#now + 1] = table.remove(pending, i) end
        end
        table.sort(now, function(a, b)
            if a.recipe.grey ~= b.recipe.grey then return a.recipe.grey < b.recipe.grey end
            if a.recipe.id ~= b.recipe.id then return a.recipe.id < b.recipe.id end
            return tostring(a.who) < tostring(b.who)
        end)
        for _, m in ipairs(now) do
            local r = m.recipe
            -- (a tool it needs that can't be had at this skill: not on this route)
            local mark = #st.journal
            local kit = Tools(st, r, 0)
            Rollback(st, mark)
            if not kit then
                out.later[#out.later + 1] = { r = r, who = m.who, why = "tool" }
            else
                -- (its tools first: each a step of its own before it)
                local logged = #st.toolLog
                Tools(st, r, 0)
                ToolSteps(logged)
                Carry()
                st.subs = {}
                local fee = PayFee(st, r)
                local crafts = m.crafts or 1
                logged = #st.toolLog
                local cost = Craft(st, r, crafts, 0)
                ToolSteps(logged)
                -- (the points so many makings give, about: each as likely as the first, and none past grey)
                local gain = math.min(Chance(r, skill) * crafts, math.max(0, r.grey - skill))
                local step = { kind = "gear", r = r, who = m.who, at = at, crafts = crafts, food = m.food,
                    cost = cost, fee = fee > 0 and fee or nil, gain = gain, mats = {}, subs = {} }
                DirectMats(r, crafts, step.mats)
                MergeInto(step.subs, st.subs)
                steps[#steps + 1] = step
                if fee > 0 then out.feeOf[r] = fee end
                out.benefit[r] = HUGE
                carry = carry + step.gain
                while carry >= 0.5 and skill < target do
                    skill, carry = skill + 1, carry - 1
                end
                st.skill = skill
                last, short = nil, nil
            end
        end
    end

    while true do
        st.skill = skill
        MakeGear()
        if skill >= target then break end
        if input.tick then input.tick() end

        -- The cheapest point here: among all the recipes, or only the few that came out best last time
        local best, bestEff, bestNet, bestCost, bestCredit, bestChance, second, bestTier
        local prefer = input.prefer
        local function Weigh(full, floor)
            best, bestEff, second, bestTier = nil, nil, nil, NO_TIER
            local ranked = full and {} or nil
            for _, r in ipairs(full and candidates or short) do
                local chance = Chance(r, skill)
                if chance >= floor then
                    local per = 1 / chance
                    local mark = #st.journal
                    -- (the tools it needs and you lack: got in this try, as its materials are)
                    local spent = st.toolSpent or 0
                    local kit = Tools(st, r, 0)
                    local cost = kit and Craft(st, r, per, 0)
                    local credit = kit and Credit(st, r, per)
                    local tools = (st.toolSpent or 0) - spent
                    Rollback(st, mark)
                    -- (a tool that can't be had at this skill: the recipe is passed over for now)
                    if kit then
                        local net = cost - credit
                        local fee = st.learned[r] and 0 or r.learnCost
                        -- (its price spread over the points it's good for; a tool's over all the points still to
                        -- go: it's there for every recipe after this one too)
                        local span = math.max(1, math.min(r.yellow + (r.grey - r.yellow) * 0.5, target) - skill)
                        local eff = net + fee / span + tools / math.max(1, target - skill)
                        local judged = eff
                        if r == last then judged = eff - math.abs(eff) * STICK - 0.001 end
                        -- (food you'd eat comes before anything cheaper, the most wanted kind first)
                        local tier = prefer and chance >= PREFER_CHANCE and prefer[r] or NO_TIER
                        if ranked then ranked[#ranked + 1] = { r = r, judged = judged, tier = tier } end
                        if not bestEff or tier < bestTier or (tier == bestTier and judged < bestEff) then
                            second = bestEff
                            best, bestEff, bestNet, bestCost, bestCredit, bestChance = r, judged, net, cost, credit, chance
                            bestTier = tier
                        elseif not second or judged < second then
                            second = judged
                        end
                    end
                end
            end
            if ranked then
                table.sort(ranked, function(x, y)
                    if x.tier ~= y.tier then return x.tier < y.tier end
                    return x.judged < y.judged
                end)
                short, shortAt = {}, skill
                for i = 1, math.min(SHORT, #ranked) do short[i] = ranked[i].r end
            end
        end
        -- A point you planned keeps its recipe, whatever prices do now (input.fixed), while it can still be made
        local kept = input.fixed and input.fixed[skill]
        local keptCost, keptCredit
        if kept and (kept.known or kept.learnCost) and Chance(kept, skill) >= LAST_CHANCE then
            local mark = #st.journal
            -- (and while its tools can be had)
            if Tools(st, kept, 0) then
                keptCost = Craft(st, kept, 1 / Chance(kept, skill), 0)
                keptCredit = Credit(st, kept, 1 / Chance(kept, skill))
            end
            Rollback(st, mark)
        end
        if keptCost then
            best, bestNet, bestCost, bestCredit, bestChance, second = kept, keptCost - keptCredit, keptCost, keptCredit,
                Chance(kept, skill), nil
            bestTier = NO_TIER
        else
            kept = nil
            -- (input.minChance: no green recipes, say, while anything better gives points)
            local floor = math.max(MIN_CHANCE, input.minChance or 0)
            local full = not short or opensAt[skill] or skill - shortAt >= FULL_EVERY
            Weigh(full, floor)
            -- (none of the few gives points any more: all of them, then; then the green ones; then the nearly grey)
            if not best and not full then Weigh(true, floor) end
            if not best and floor > MIN_CHANCE then Weigh(true, MIN_CHANCE) end
            if not best then Weigh(true, LAST_CHANCE) end
        end
        if not best then
            out.stuck = skill
            for _, r in ipairs(input.recipes) do
                if not r.aux and not (r.known or r.learnCost) and Chance(r, skill) >= LAST_CHANCE then
                    out.blocked[#out.blocked + 1] = r
                end
            end
            break
        end

        -- Its tools first: each got once, a step of its own before this one
        local toolsFrom = #st.toolLog
        Tools(st, best, 0)
        ToolSteps(toolsFrom)
        if Carry() then
            -- (making the tool gave a point: what's cheapest at the next one is weighed anew)
            last, short = nil, nil
        else
            -- Made, for real this time
            local per = 1 / bestChance
            st.subs = {}
            local fee = PayFee(st, best)
            local logged = #st.toolLog
            Craft(st, best, per, 0)
            -- (a tool something made first for it needed: its step comes before this one)
            ToolSteps(logged)
            -- (how much of what it leaves counts on a sale at auction, over a vendor's price)
            local hoped = 0
            if best.item and best.item ~= 0 and (best.n or 0) > 0 then
                local units = per * best.n
                hoped = Salvage(st, best.item, units) - units * (input.value[best.item] or 0)
            end
            Credit(st, best, per)
            if fee > 0 then out.feeOf[best] = fee end
            -- (a recipe made because you'd eat what it makes isn't weighed against its price afterwards)
            out.benefit[best] = (out.benefit[best] or 0) + (second and bestTier == NO_TIER and (second - bestNet) or HUGE)
            if bestTier ~= NO_TIER then out.preferred = (out.preferred or 0) + 1 end
            out.points[skill] = bestNet

            local step = steps[#steps]
            -- (a kept stretch ends where it was planned to: what follows it is a step of its own, even of the same
            -- recipe)
            local fixed = kept and true or false
            if not (step and step.kind == "level" and step.r == best and step.to == skill and step.fixed == fixed) then
                step = { kind = "level", r = best, from = skill, to = skill, crafts = 0, cost = 0, back = 0, mats = {},
                    subs = {}, chance = bestChance, fixed = fixed }
                steps[#steps + 1] = step
            end
            step.to = skill + 1
            step.crafts = step.crafts + per
            step.cost = step.cost + bestCost
            step.back = step.back + bestCredit
            step.chanceEnd = bestChance
            step.hoped = (step.hoped or 0) + hoped
            hopedTotal = hopedTotal + hoped
            if fee > 0 then step.fee = (step.fee or 0) + fee end
            DirectMats(best, per, step.mats)
            MergeInto(step.subs, st.subs)
            last = best
            skill = skill + 1
            Carry()
        end
    end
    st.skill = skill
    MakeGear()
    for _, m in ipairs(pending) do out.later[#out.later + 1] = { r = m.recipe, who = m.who, why = "skill" } end

    -- The sums
    out.reached = skill
    out.items = st.items
    out.fees = st.fees
    local spend, paid, feeTotal, back = 0, 0, 0, 0
    for _, t in pairs(st.items) do
        spend = spend + (t.cost or 0)
        paid = paid + (t.paid or 0)
    end
    for _, f in ipairs(st.fees) do feeTotal = feeTotal + f.fee end
    -- (what's left of the things made, at what they sell for)
    for _, pool in pairs(st.pool) do back = back + math.max(0, pool.base) end
    -- (spend: with your own things at what you count them for; paid: only what's bought)
    out.spend, out.paid, out.feeTotal, out.back = spend, paid, feeTotal, back
    out.total = spend + feeTotal - back
    -- (hoped: the part of "back" that needs things to sell at auction)
    out.hoped = math.min(back, hopedTotal)
    -- (for the next run)
    out.demand, out.replQty, out.replCost = st.demand, st.replQty, st.replCost
    return out
end

local function Better(a, b)
    if a.reached ~= b.reached then return a.reached > b.reached end
    return a.total < b.total - 0.5
end

-- What made things are worth to later steps, from a run: { [item] = { need, value } }, or nil if nothing new
local function FutureFrom(input, out, old)
    local makes = {}
    for _, r in ipairs(input.recipes) do
        if not r.aux and r.item and r.item ~= 0 then makes[r.item] = true end
    end
    local future, changed = {}, false
    for item in pairs(makes) do
        local need = out.demand[item] or 0
        local before = old[item]
        local value = before and before.value or 0
        if (out.replQty[item] or 0) > EPS then value = math.max(value, out.replCost[item] / out.replQty[item]) end
        if need > EPS and value > 0 then
            future[item] = { need = need, value = value }
            if not before or math.abs(before.need - need) > 0.5 then changed = true end
        elseif before then
            changed = true
        end
    end
    return changed and future or nil
end

-- A learned recipe that saved less than it cost (the worst such), or nil
local function WorstBuy(out, keep)
    local worst, worstLoss
    for r, fee in pairs(out.feeOf) do
        local loss = fee - (out.benefit[r] or 0)
        if not keep[r.id] and loss > 0 and (not worstLoss or loss > worstLoss) then worst, worstLoss = r, loss end
    end
    return worst
end

function Solver.Solve(input)
    local banned, keep, future = {}, {}, {}
    local best = Run(input, banned, future)
    local futureTries = 0
    for _ = 1, 10 do
        local newFuture = futureTries < 3 and FutureFrom(input, best, future) or nil
        if newFuture then
            futureTries = futureTries + 1
            local out = Run(input, banned, newFuture)
            if Better(out, best) then
                best, future = out, newFuture
            else
                futureTries = 3
            end
        else
            local r = WorstBuy(best, keep)
            if not r then break end
            banned[r.id] = true
            local out = Run(input, banned, future)
            if Better(out, best) then
                best = out
            else
                banned[r.id] = nil
                keep[r.id] = true
            end
        end
    end
    return best
end

-- What one making of r costs now (materials, and its price if it's still to be learned): cost, fee
function Solver.CraftCost(input, r)
    local st = NewState(input, {}, {})
    st.skill = math.max(input.skill, r.learn)
    local fee = PayFee(st, r)
    return Craft(st, r, 1, 0), fee
end

-- Recipes that can't be learned now: what each would save on this route if it could, to tell which plans are
-- worth getting. missing = { { r, why } }; out: the route as it is.
-- -> { { r, why, saving (about: its points against the route's own, at today's first prices), reach (points it
--        would give past where the route is stuck), each (what one making costs, less what it sells for) } },
--    the most worth first
function Solver.Worth(input, out, missing)
    local st = NewState(input, {}, {})
    local worth = {}
    for _, m in ipairs(missing or {}) do
        local r = m.r
        local first = math.max(input.skill, r.learn)
        st.skill = first
        local mark = #st.journal
        local each = Craft(st, r, 1, 0) - Credit(st, r, 1)
        Rollback(st, mark)
        local saving, reach = 0, 0
        for skill = first, math.min(input.target, r.grey) - 1 do
            local chance = Chance(r, skill)
            if chance >= MIN_CHANCE then
                local now = out.points[skill]
                if now then
                    saving = saving + math.max(0, now - each / chance)
                elseif skill >= out.reached then
                    reach = reach + 1
                end
            end
        end
        if saving > 0 or reach > 0 then
            worth[#worth + 1] = { r = r, why = m.why, saving = saving, reach = reach, each = each }
        end
    end
    table.sort(worth, function(a, b)
        if a.reach ~= b.reach then return a.reach > b.reach end
        if a.saving ~= b.saving then return a.saving > b.saving end
        return a.r.name < b.r.name
    end)
    return worth
end

-- What could be made now and sold at auction for more than its materials cost: for the Sell tab.
-- sale = { [item] = { price, units, listed } } (every product's, whether or not the route counts on sales).
-- Materials are reckoned at what they cost to buy today, your own too: a thing made of bars you could have sold
-- isn't free. -> { { r, cost, sells, profit, fee, unsure (a material's price was a guess) } }, the best first
function Solver.Profits(input, sale)
    local st = NewState(input, {}, {})
    st.noStock = true
    local list = {}
    for _, r in ipairs(input.recipes) do
        local s = not r.aux and r.item and r.item ~= 0 and (r.n or 0) > 0 and sale[r.item]
        if s and r.learn <= input.skill and (r.known or r.learnCost) then
            st.skill = input.skill
            local mark = #st.journal
            local cost = Craft(st, r, 1, 0)
            local unsure = (st.guessed or 0) > EPS
            Rollback(st, mark)
            local sells = s.price * r.n
            if sells > cost then
                list[#list + 1] = { r = r, cost = cost, sells = sells, profit = sells - cost,
                    fee = not r.known and r.learnCost or 0, unsure = unsure }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.r.name < b.r.name
    end)
    return list
end
