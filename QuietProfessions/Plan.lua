-- The plan: what the solver is told (your skill, your recipes, what you have, today's prices, the gear you want)
-- and its answer, kept until something changes.
--
-- The reckoning is long (hundreds of recipes weighed at each of up to 300 points, several times over), so it's done
-- a few milliseconds a frame: the window shows the last route until the new one is ready.
local _, ns = ...

local Plain, Call = ns.Plain, ns.Call

local BUDGET = 6          -- milliseconds of reckoning a frame
local TIERS = { 75, 150, 225, 300 }
local RELOOK = 20 * 60    -- a price looked up this lately isn't looked up again
local SELL_BACK = 75      -- what's made by recipes learned up to this far under your skill is priced for selling

-- ---------- what you have ----------
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local SlotInfo = C_Container and C_Container.GetContainerItemInfo
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local bags, bagsAt

-- This character's bags as they are now (the reagent bag too: QuietKit.Stock knows which containers are bags)
local function Bags()
    if bags and bagsAt == ns.bagVersion then return bags end
    bags, bagsAt = {}, ns.bagVersion
    for _, bag in ipairs(QuietKit.Stock.BagIDs()) do
        for slot = 1, tonumber(Call(NumSlots, bag)) or 0 do
            local info = Call(SlotInfo, bag, slot)
            local id = type(info) == "table" and Plain(info.itemID)
            if id then bags[id] = (bags[id] or 0) + (Plain(info.stackCount) or 1) end
        end
    end
    return bags
end

-- The shared count of an item in one of a character's places
local function Kept(char, place, id)
    local there = type(char[place]) == "table" and type(char[place].items) == "table" and char[place].items[id]
    return type(there) == "table" and tonumber(there.count) or 0
end

local haveCache, haveStamp = {}, nil

-- How many of an item you have, and where: total, { bags, bank, mail, pending, alts = { { name, n } } }
-- Your bags as they are. Your bank and mailbox, and every other character, from QuietKit.Stock: the one count all
-- Quiet addons share, kept on every character with any Quiet addon on (so none of it depends on Quiet Bags being
-- on somewhere). Before the bank was ever seen, the bank as the game counts it.
function ns.Have(id)
    local stamp = ns.bagVersion .. (ns.Setting("alts") and "a" or "") .. ":" .. (ns.pendingVersion or 0) .. ":"
        .. QuietKit.Stock.version
    if haveStamp ~= stamp then haveCache, haveStamp = {}, stamp end
    local have = haveCache[id]
    if have then return have.total, have end
    have = { bags = Bags()[id] or 0, bank = 0, mail = 0, alts = {} }
    local chars = QuietKit.Stock.Chars()
    local myKey, me = ns.MyKey(), ns.Me()
    local mine = type(chars[myKey]) == "table" and chars[myKey] or nil
    if mine and type(mine.bank) == "table" then
        have.bank = Kept(mine, "bank", id)
    else
        local all, carried = tonumber(Plain(Call(GetCount, id, true))), tonumber(Plain(Call(GetCount, id)))
        if all and carried then have.bank = math.max(0, all - carried) end
    end
    if mine then have.mail = Kept(mine, "mail", id) end
    -- (bought with Buy, or mailed by another of your characters, and on its way: yours already)
    have.pending = ns.OnItsWay and ns.OnItsWay(id) or 0
    have.total = have.bags + have.bank + have.mail + have.pending
    if me and ns.Setting("alts") then
        for key, char in pairs(chars) do
            if key ~= myKey and type(char) == "table" and char.realm == me.realm
                and (not char.faction or not me.faction or char.faction == me.faction) then
                local n = Kept(char, "bags", id) + Kept(char, "bank", id) + Kept(char, "mail", id)
                if n > 0 then
                    have.alts[#have.alts + 1] = { name = char.name or key, n = n }
                    have.total = have.total + n
                end
            end
        end
        table.sort(have.alts, function(a, b) return tostring(a.name) < tostring(b.name) end)
    end
    haveCache[id] = have
    return have.total, have
end

-- ---------- which profession, to what skill ----------
-- The one shown: the one you chose, else the first you have, else the first there's data for
function ns.Profession()
    local me = ns.Me()
    if not me then return nil end
    if me.profession and ns.professions[me.profession] then return me.profession end
    for _, id in ipairs(ns.professionOrder) do
        if me.skills[id] then return id end
    end
    return ns.professionOrder[1]
end

function ns.SetProfession(id)
    local me = ns.Me()
    if not me or not ns.professions[id] then return end
    me.profession = id
    ns.Changed()
end

-- Your skill in it now (1 if you haven't learned it: the route from the start), and whether you have it
function ns.Skill(id)
    local me = ns.Me()
    local s = me and me.skills[id]
    if s then return s.level, true end
    return 1, false
end

function ns.GoalChoices()
    return TIERS
end

-- The skill planned to: the one you chose, else the next of 75, 150, 225, 300
function ns.Goal(id)
    local me = ns.Me()
    local skill = ns.Skill(id)
    local goal = me and me.goal[id]
    if goal and goal > skill then return goal end
    for _, tier in ipairs(TIERS) do
        if tier > skill then return tier end
    end
    return TIERS[#TIERS]
end

function ns.SetGoal(goal)
    local me, id = ns.Me(), ns.Profession()
    if not me or not id then return end
    me.goal[id] = math.max(2, math.min(TIERS[#TIERS], math.floor(goal)))
    ns.Changed()
end

-- ---------- your recipes ----------
-- Learned? As the profession's window last told; before it was ever opened, only the ones known from the start.
function ns.Knows(r)
    local me = ns.Me()
    local known = me and me.known[r.prof]
    if known then return known[r.id] and true or false end
    return r.how == "" and r.learn == 1
end

-- The vendor that sells a plan to your side: "Jutak (Stranglethorn Vale, few in stock)". Then: whether any vendor
-- is known for it at all, and the vendors that sell only to the other side ("Harggan (The Hinterlands)").
local function PlanVendor(plan)
    local info, me = ns.plans[plan], ns.Me()
    if not info or #info.vendors == 0 then return nil, false end
    local mine = me and me.faction == "Alliance" and 1 or 2
    local theirs
    for _, v in ipairs(info.vendors) do
        local where = v.name .. (v.zone ~= "" and (" (" .. v.zone .. (v.limited and ", few in stock" or "") .. ")") or "")
        if v.side == 0 or v.side == 3 or v.side == mine then return where, true end
        theirs = theirs or where
    end
    return nil, true, theirs
end

-- What learning a recipe costs, and where from. nil if it can't be learned now, and then why (the third answer):
-- a reputation it needs, a plan that isn't for sale, a vendor of the other side's.
function ns.LearnCost(r)
    -- (an armorsmith's or weaponsmith's own: only if known already)
    if r.spec ~= 0 then return nil, nil, "only for its specialization" end
    if r.plan == 0 then
        if r.how == "T" then return r.cost, "the trainer" end
        return nil, nil, "no source known for it"
    end
    local info = ns.plans[r.plan]
    local paper = "its " .. ns.Paper(r.prof)
    -- (a plan that asks for a reputation can't be learned without it, wherever it came from)
    if info and info.faction ~= 0 then
        local have, name = ns.Standing(info.faction)
        if not have or have < info.standing then
            return nil, nil, "needs " .. (name or "a faction") .. ": " .. ns.StandingName(info.standing)
                .. (have and (" (you: " .. ns.StandingName(have) .. ")") or "")
        end
    end
    if ns.Have(r.plan) > 0 then return 0, paper .. ", which you have" end
    local best, how, why
    if r.how == "V" and r.cost > 0 then
        local vendor, known, theirs = PlanVendor(r.plan)
        if vendor then
            best, how = r.cost, paper .. " from " .. vendor
        elseif not known then
            best, how = r.cost, paper .. " from a vendor"
        else
            why = "sold only to the other side, by " .. theirs
        end
    end
    local auction = ns.PriceOf(r.plan).rows[1]
    if auction and (not best or auction < best) then best, how = auction, paper .. " at auction" end
    if best then return best, how end
    if not why then
        if info and info.quest ~= "" then
            why = "from the quest " .. info.quest
        elseif info and info.dropped ~= "" then
            why = "dropped by " .. info.dropped
        elseif r.how == "D" then
            why = "a drop"
        elseif r.how == "Q" then
            why = "from a quest"
        else
            why = "no source known for " .. paper
        end
    end
    return nil, nil, why .. ": none at auction now"
end

-- ---------- what the solver is told ----------
local function Copy(r)
    return { id = r.id, name = r.name, item = r.item, n = r.n, learn = r.learn, yellow = r.yellow, grey = r.grey,
        how = r.how, plan = r.plan, reagents = r.reagents, tools = r.tools, prof = r.prof, data = r }
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local BIND_PICKUP = (Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire) or 1

local function BuildInput(profID, goal)
    local me, prof = ns.Me(), ns.professions[profID]
    local skill = ns.Skill(profID)
    local input = { skill = skill, target = goal, recipes = {}, supply = {}, value = {}, must = {} }
    local meta = { byId = {}, price = {}, missing = {}, opened = me.known[profID] ~= nil }
    local ownFree = ns.Setting("ownFree")
    -- (what each thing made could bring at auction: for the Sell tab always, for the route if you asked)
    meta.sale = {}
    if ns.Setting("sellAuction") then input.sale = meta.sale end

    local function Item(id)
        if input.supply[id] then return end
        local price = ns.PriceOf(id)
        local stock = ns.Have(id)
        local stockPrice = 0
        if not ownFree then stockPrice = math.max(ns.SellValue(id), ns.AuctionValue(id) or 0) end
        input.supply[id] = { stock = stock, stockPrice = stockPrice, rows = price.rows, vendor = price.vendor,
            guess = price.guess }
        meta.price[id] = price
    end

    -- The tools a recipe needs (a hammer, a runed rod): needed once, so one you hold (in your bags, bank or mail)
    -- is nothing to get. Any item of the tool's kind does; the one it's named for is the one the route gets.
    -- (the basic tools, a few copper at any trade vendor, count as yours always: Solver.lua)
    input.held = {}
    local function Tools(r)
        for _, kind in ipairs(r.tools or {}) do
            for i, id in ipairs(kind) do
                if input.held[id] == nil then
                    local _, have = ns.Have(id)
                    local own = have.bags + have.bank + have.mail + (have.pending or 0)
                    input.held[id] = own >= 1
                    if i == 1 then
                        Item(id)
                        -- (one that binds when picked up, a runed rod, can't be mailed over: another character's
                        -- is no use to this one)
                        if Plain(select(14, Call(GetInfo, id))) == BIND_PICKUP then input.supply[id].stock = own end
                    end
                end
            end
        end
    end

    for _, r in ipairs(prof.recipes) do
        local copy = Copy(r)
        copy.known = ns.Knows(r)
        if not copy.known then
            local why
            copy.learnCost, copy.learnHow, why = ns.LearnCost(r)
            -- (out of reach now, but it would give points on this route: is it worth getting? Solver.Worth says)
            if not copy.learnCost and r.spec == 0 and r.grey > skill and r.learn < goal then
                meta.missing[#meta.missing + 1] = { r = copy, why = why }
            end
        end
        input.recipes[#input.recipes + 1] = copy
        meta.byId[r.id] = copy
        for i = 1, #r.reagents, 2 do Item(r.reagents[i]) end
        Tools(r)
        if r.item ~= 0 then
            input.value[r.item] = ns.SellValue(r.item)
            meta.sale[r.item] = meta.sale[r.item] or ns.SaleOf(r.item)
        end
    end
    -- Your other professions' recipes make materials (a miner smelts the bars)
    for id, other in pairs(ns.professions) do
        local s = id ~= profID and me.skills[id]
        if s then
            for _, r in ipairs(other.recipes) do
                local copy = Copy(r)
                local usable
                if me.known[id] then
                    usable = me.known[id][r.id] and true or false
                else
                    usable = r.learn <= s.level and (r.how == "T" or r.how == "")
                end
                copy.aux, copy.usable, copy.known = true, usable, usable
                input.recipes[#input.recipes + 1] = copy
                if usable then
                    for i = 1, #r.reagents, 2 do Item(r.reagents[i]) end
                    Tools(r)
                end
            end
        end
    end

    -- Gear to make on the way
    meta.gear, meta.waiting = ns.GearFor(profID, function(r)
        local copy = meta.byId[r.id]
        return copy.known or copy.learnCost ~= nil
    end, math.max(goal, skill))
    for _, entry in ipairs(meta.gear) do
        if ns.Wanted(entry) then
            input.must[#input.must + 1] = { recipe = meta.byId[entry.r.id], who = entry.who }
        end
    end
    -- Food to cook on the way: as many as you asked for (Food.lua)
    meta.food = ns.FoodFor(profID, function(r)
        local copy = meta.byId[r.id]
        return copy.known or copy.learnCost ~= nil
    end, math.max(goal, skill))
    for _, entry in ipairs(meta.food) do
        local n = ns.FoodWanted(entry)
        if n > 0 then
            input.must[#input.must + 1] = { recipe = meta.byId[entry.r.id], who = entry.who, food = true,
                crafts = math.ceil(n / math.max(1, entry.r.n) - 1e-6) }
        end
    end
    -- The food your class eats is made where it gives points, the most wanted kind first and of a kind the one
    -- that gives the most (Food.lua): a warrior levels on the best strength food, then stamina food, not on
    -- what's cheapest and feeds a mage
    if prof.food and ns.Setting("eat") then
        local prefer
        for _, r in ipairs(prof.recipes) do
            local tier = r.item ~= 0 and ns.FoodTier(r.item, me.class, me.level)
            if tier then
                prefer = prefer or {}
                prefer[meta.byId[r.id]] = tier
            end
        end
        input.prefer = prefer
    end
    -- Green recipes (a point less than every other making) are passed over while a yellow or orange one gives
    -- points: cheaper on average, by the sums, but a run of bad luck eats the materials bought for it
    if not ns.Setting("greens") then input.minChance = 0.5 + 1e-6 end
    -- The points you planned keep the recipe they had then: new prices don't move them (me.kept, set by Plan)
    local kept = type(me.kept) == "table" and me.kept[profID]
    if type(kept) == "table" then
        input.fixed = {}
        for at, id in pairs(kept) do
            if at >= skill and meta.byId[id] then input.fixed[at] = meta.byId[id] end
        end
    end
    return input, meta
end

-- ---------- the plan ----------
-- { prof, goal, input, meta, out (the route; the last one while a new one is reckoned), working, error }
local plan = { version = -1 }
local job
local sliceStart = 0

local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
    if not job then
        self:Hide()
        return
    end
    sliceStart = debugprofilestop()
    local ok, result = coroutine.resume(job.co)
    if not ok then
        job.plan.error, job.plan.working = tostring(result), false
        job = nil
        self:Hide()
        if ns.RefreshWindow then ns.RefreshWindow() end
    elseif coroutine.status(job.co) == "dead" then
        job.plan.out, job.plan.working = result, false
        job = nil
        self:Hide()
        if ns.RefreshWindow then ns.RefreshWindow() end
    end
end)

-- The plan for the profession shown, started anew if anything changed since. nil before the game knows who you are.
function ns.Plan()
    local me, profID = ns.Me(), ns.Profession()
    if not me or not profID then return nil end
    local goal = ns.Goal(profID)
    if plan.version ~= ns.version or plan.prof ~= profID or plan.goal ~= goal then
        local input, meta = BuildInput(profID, goal)
        local same = plan.prof == profID
        plan = { version = ns.version, prof = profID, goal = goal, input = input, meta = meta, working = true,
            out = same and plan.out or nil }
        -- (the last route's own input and gear stay with it while it's the one shown)
        input.tick = function()
            if debugprofilestop() - sliceStart > BUDGET then coroutine.yield() end
        end
        job = { plan = plan, co = coroutine.create(function()
            local out = ns.Solver.Solve(input)
            -- (the cheapest route too, where this one makes food to eat instead: to say what that costs)
            if out.preferred then
                out.plain = ns.Solver.Solve(setmetatable({ prefer = false }, { __index = input }))
            end
            out.worth = ns.Solver.Worth(input, out, meta.missing)
            out.profits = ns.Solver.Profits(input, meta.sale)
            return out
        end) }
        runner:Show()
    end
    return plan
end

-- ---------- what to look up at the auction house ----------
-- The route's own materials first (it firms up soonest), then every material and plan a recipe between your skill
-- and the goal could use; not what only a vendor sells, nor what was looked up minutes ago
function ns.ItemsToPrice()
    local profID = ns.Profession()
    local list, seen = {}, {}
    if not profID then return list end
    local looked, now = ns.Market().looked, time()
    local function Want(id)
        if seen[id] or not id or id == 0 then return end
        seen[id] = true
        local it = ns.items[id]
        if it and it.buy > 0 then return end
        if looked[id] and now - looked[id].at < RELOOK then return end
        list[#list + 1] = id
    end
    -- (first of all, what this character is to buy for another)
    for _, send in ipairs(ns.SendsFromMe()) do
        for _, each in ipairs(send.items) do
            if each.buy > 0 then Want(each.id) end
        end
    end
    -- (a miner's ore and bars: what smelting for money is reckoned from, Smelt.lua)
    for _, id in ipairs(ns.SmeltItems(profID)) do Want(id) end
    if plan.prof == profID and plan.out then
        local first = {}
        for id, t in pairs(plan.out.items) do first[#first + 1] = { id = id, cost = t.cost or 0 } end
        table.sort(first, function(a, b) return a.cost > b.cost end)
        for _, each in ipairs(first) do Want(each.id) end
        for _, fee in ipairs(plan.out.fees) do Want(fee.r.plan) end
    end
    local skill, goal = ns.Skill(profID), ns.Goal(profID)
    local me = ns.Me()
    local made = {}
    local function Recipes(prof, all)
        for _, r in ipairs(prof.recipes) do
            if all or (r.learn < goal and r.grey > skill and r.spec == 0) then
                for i = 1, #r.reagents, 2 do Want(r.reagents[i]) end
                -- (and a tool it needs: a spanner may be listed for less than its bars)
                for _, kind in ipairs(r.tools or {}) do Want(kind[1]) end
                if not all and r.plan ~= 0 and not ns.Knows(r) then Want(r.plan) end
                -- (what's made, for what it would sell for: the things you can make now or soon)
                if not all and r.item ~= 0 and r.learn >= skill - SELL_BACK then made[#made + 1] = r.item end
            end
        end
    end
    Recipes(ns.professions[profID], false)
    for id, other in pairs(ns.professions) do
        if id ~= profID and me and me.skills[id] then Recipes(other, true) end
    end
    -- (last, and not what Quiet Auctions' scan has a price for already)
    for _, id in ipairs(made) do
        if not seen[id] and ns.PriceOf(id).source ~= "scan" then Want(id) end
    end
    return list
end

-- ---------- how far you mean to go now ----------
-- "Plan" on a step of the route plans it and every step before it (they come first anyway: a step needs the skill
-- the ones before it give). The To buy tab then lists what the route needs that far, not to its end: what's in
-- your bags, what to take out of the bank, what each of your other characters mails you, and what to buy. Less and
-- More there move it a step.
-- What's planned is also KEPT: its recipes stay the ones the route had when you planned it, whatever prices do
-- afterwards. Only what isn't planned follows the prices.
ns.plannedVersion = 0

-- Where a step stands on the route: a piece of gear at its skill, a levelling step at its last point (so what's
-- left of a planned step is still planned when your skill is halfway through it)
function ns.StepPos(step)
    return step.kind == "gear" and step.at or step.to - 0.5
end

-- How far it's planned (a place on the route), or nil
function ns.PlanTo()
    local me, profID = ns.Me(), ns.Profession()
    return me and profID and type(me.planTo) == "table" and me.planTo[profID] or nil
end

function ns.SetPlanTo(pos)
    local me, profID = ns.Me(), ns.Profession()
    if not me or not profID then return end
    me.planTo = type(me.planTo) == "table" and me.planTo or {}
    me.planTo[profID] = pos
    me.planned = nil -- (the marks of an earlier version, a step at a time)
    -- What's planned is kept as it is now: each of its points with the recipe the route has for it today
    -- (me.kept[profession] = { [skill] = recipe }). The route is reckoned round it from then on, so its materials
    -- stay the same list when prices change or another character has been to the auction house.
    me.kept = type(me.kept) == "table" and me.kept or {}
    local kept
    if pos and plan.prof == profID and plan.out then
        kept = {}
        for _, step in ipairs(plan.out.steps) do
            if step.kind == "level" and ns.StepPos(step) <= pos then
                for at = step.from, step.to - 1 do kept[at] = step.r.id end
            end
        end
    end
    me.kept[profID] = kept
    ns.plannedVersion = ns.plannedVersion + 1
    -- (the list for your other characters is written by ns.Needs: at once, whichever tab is showing)
    if plan.prof == profID and plan.out then ns.Needs(plan) end
    -- (nothing is kept any more: the whole route follows the prices again)
    if not pos then ns.Changed() end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.IsPlanned(step)
    local to = ns.PlanTo()
    return to ~= nil and ns.StepPos(step) <= to
end

-- A step further (dir 1) or one less (-1). With nothing planned the lists are the whole route's: one less from
-- there is all but its last step.
function ns.PlanMove(out, dir)
    local steps = out.steps
    if #steps == 0 then return end
    local to, cur, best = ns.PlanTo(), nil, nil
    for _, step in ipairs(steps) do
        local pos = ns.StepPos(step)
        if to and pos <= to and (not cur or pos > cur) then cur = pos end
    end
    if dir < 0 then
        local limit = cur or ns.StepPos(steps[#steps])
        for _, step in ipairs(steps) do
            local pos = ns.StepPos(step)
            if pos < limit and (not best or pos > best) then best = pos end
        end
        best = best or limit -- (there's only the one step)
    else
        if not cur then return end
        for _, step in ipairs(steps) do
            local pos = ns.StepPos(step)
            if pos > cur and (not best or pos < best) then best = pos end
        end
        if not best then return end
    end
    ns.SetPlanTo(best)
end

-- How many makings to reckon with for a step: the average, rounded up unless it's only a little over (a point
-- that comes 8 times in 10 is one making, not two; one that comes 6 times in 10 is two)
function ns.Makings(step)
    return math.max(1, math.ceil((step.crafts or 1) - 0.25))
end

-- A step is made a whole number of times: the 1.8 makings a point comes to on average are 2 makings' materials.
-- What to multiply a levelling step's (average) amounts by to get the amounts for the makings the route shows.
function ns.StepFactor(step)
    if step.kind ~= "level" or (step.crafts or 0) <= 0 then return 1 end
    return ns.Makings(step) / step.crafts
end

local SEND_DAYS = 7 -- (a list for your other characters older than this is forgotten)
local BEYOND = 1.3  -- (more than is listed: reckoned at the dearest listing and this much more, as the solver does)

-- What so many of an item cost to buy: the listings known, cheapest first, up to a vendor's price; then a vendor,
-- or (more than is listed) the dearest listing and a bit, or a guess. { auction, auctionCost, vendor, beyond,
-- guess, cost }
function ns.CostOf(id, n, price)
    price = price or ns.PriceOf(id)
    local rows, vendor = price.rows, price.vendor
    local e = { auction = 0, auctionCost = 0, vendor = 0, beyond = 0, guess = 0, cost = 0 }
    local left = n
    for i = 1, #rows, 2 do
        if left <= 0 or (vendor and rows[i] >= vendor) then break end
        local use = math.min(left, rows[i + 1])
        left = left - use
        e.auction, e.auctionCost = e.auction + use, e.auctionCost + use * rows[i]
    end
    if left > 0 then
        if vendor then
            e.vendor, e.cost = left, left * vendor
        elseif #rows > 0 then
            e.beyond, e.cost = left, left * rows[#rows - 1] * BEYOND
        else
            e.guess, e.cost = left, left * (price.guess or 0)
        end
    end
    e.cost = e.cost + e.auctionCost
    return e
end

-- ---------- the route in whole numbers ----------
-- The solver reckons in averages (1.8 makings, 0.9 of a smelting). What you do is whole, and every number shown
-- comes from here: each step with the makings the route shows, what those take, what's made first for them, what
-- of it comes out of what you have (your things are used up in the route's order) and what's left to buy.
-- { [step] = { mats = { [item] = n }, makes = { { r, crafts } } (in the order to make them),
--              take = { [item] = n } (yours), buy = { [item] = n }, cost (to buy them) },
--   buy = { [item] = n } (the whole route's), cost }
-- (kept for each route there is: the one shown, and the cheapest one it's held against)
local resolveCache = setmetatable({}, { __mode = "k" })

function ns.Resolve(plan)
    local out = plan.out
    local key = table.concat({ ns.bagVersion, ns.pendingVersion or 0, ns.version }, ":")
    local cached = resolveCache[out]
    if cached and cached.key == key then return cached.res end
    local res = { buy = {}, cost = 0 }
    local stock, made = {}, {} -- (what's left of what you have; what the steps so far made and left over)
    local function Stock(id)
        if stock[id] == nil then stock[id] = (ns.Have(id)) end
        return stock[id]
    end
    for _, step in ipairs(out.steps) do
        local f = ns.StepFactor(step)
        local entry = { mats = {}, makes = {}, take = {}, buy = {}, cost = 0 }
        local need, avg = {}, {}
        for item, n in pairs(step.mats) do
            local whole = math.floor(n * f + 0.5)
            entry.mats[item] = whole
            need[item], avg[item] = whole, n
        end
        -- What's made first for it (a miner's bars, the grinding stones). One whose product goes into another is
        -- reckoned after that other, so all that's wanted of it is known.
        local subs = {}
        for r, crafts in pairs(step.subs) do subs[#subs + 1] = { r = r, crafts = crafts } end
        table.sort(subs, function(a, b) return a.r.id < b.r.id end)
        for _ = 1, #subs do
            local pick
            for _, s in ipairs(subs) do
                if not s.done and not pick then
                    local feeds = false
                    for _, o in ipairs(subs) do
                        if o ~= s and not o.done then
                            for i = 1, #o.r.reagents, 2 do
                                if o.r.reagents[i] == s.r.item then feeds = true end
                            end
                        end
                    end
                    if not feeds then pick = s end
                end
            end
            if not pick then
                for _, s in ipairs(subs) do
                    if not s.done then pick = pick or s end
                end
            end
            pick.done = true
            local r, p = pick.r, pick.r.item
            local want, avgWant = need[p] or 0, avg[p] or 0
            local have = Stock(p) + (made[p] or 0)
            local rest = math.max(0, want - have)
            -- (the solver made some and may have bought the rest: the same share of what's really short)
            local avgRest = math.max(0, avgWant - have)
            local share = avgRest > 0.01 and math.min(1, pick.crafts * r.n / avgRest) or 1
            local crafts = rest > 0 and math.ceil(rest * share / r.n - 1e-6) or 0
            if crafts > 0 then
                table.insert(entry.makes, 1, { r = r, crafts = crafts })
                local produced = crafts * r.n
                local cover = math.min(rest, produced)
                need[p] = want - cover
                if produced > cover then made[p] = (made[p] or 0) + produced - cover end
                for i = 1, #r.reagents, 2 do
                    need[r.reagents[i]] = (need[r.reagents[i]] or 0) + r.reagents[i + 1] * crafts
                end
            end
            for i = 1, #r.reagents, 2 do
                avg[r.reagents[i]] = (avg[r.reagents[i]] or 0) + r.reagents[i + 1] * pick.crafts
            end
        end
        -- Out of what you have first, then what an earlier step left over, and the rest is to buy
        for item, n in pairs(need) do
            if n > 0 then
                local take = math.min(n, Stock(item))
                stock[item] = stock[item] - take
                local left = n - take
                local leftover = math.min(left, made[item] or 0)
                if leftover > 0 then made[item] = made[item] - leftover end
                left = left - leftover
                if take > 0 then entry.take[item] = take end
                if left > 0 then
                    entry.buy[item] = left
                    res.buy[item] = (res.buy[item] or 0) + left
                    entry.cost = entry.cost + ns.CostOf(item, left, plan.meta.price[item]).cost
                end
            end
        end
        -- (what it makes is there for the steps after it)
        if step.kind == "level" and step.r.item ~= 0 then
            made[step.r.item] = (made[step.r.item] or 0) + ns.Makings(step) * step.r.n
        end
        res[step] = entry
    end
    for item, n in pairs(res.buy) do res.cost = res.cost + ns.CostOf(item, n, plan.meta.price[item]).cost end
    resolveCache[out] = { key = key, res = res }
    return res
end

-- What the planned steps (the whole route, if none is planned) need, and where each thing comes from:
-- { planned (how many steps; 0: the whole route), last (the last of them),
--   items = { { id, need, bags, pending, bank, mail, alts = { { name, n } }, auction, auctionCost, vendor, beyond,
--               guess, cost (what's to pay), uses = { { step, n } } (which steps it's for, in their order) } },
--   fees = { { r, fee } }, sends = { [character] = { { id, n } } }, bank = { { id, n } }, mail = { { id, n } } }
local needsCache = {}

function ns.Needs(plan)
    local out, me = plan.out, ns.Me()
    local key = table.concat({ tostring(out), ns.plannedVersion, ns.bagVersion, ns.pendingVersion or 0, ns.version }, ":")
    if needsCache.key == key then return needsCache.needs end
    local chosen = {}
    for _, step in ipairs(out.steps) do
        if ns.IsPlanned(step) then chosen[#chosen + 1] = step end
    end
    local needs = { planned = #chosen, items = {}, fees = {}, sends = {}, bank = {}, mail = {} }
    local shop = {} -- (what's to buy at auction: another character can do the buying, and mail it)
    if #chosen == 0 then chosen = out.steps end
    needs.last = chosen[#chosen]

    -- What they take and what's to buy for them, in whole numbers (ns.Resolve), and which step uses how much
    local resolved = ns.Resolve(plan)
    local leaf, involved, uses = {}, {}, {}
    for _, step in ipairs(chosen) do
        involved[step.r] = true
        for r in pairs(step.subs) do involved[r] = true end
        local entry = resolved[step]
        local own = {}
        for item, n in pairs(entry.take) do own[item] = (own[item] or 0) + n end
        for item, n in pairs(entry.buy) do own[item] = (own[item] or 0) + n end
        for item, n in pairs(own) do
            leaf[item] = (leaf[item] or 0) + n
            uses[item] = uses[item] or {}
            table.insert(uses[item], { step = step, n = n })
        end
    end
    for _, fee in ipairs(out.fees) do
        if needs.planned == 0 or involved[fee.r] then needs.fees[#needs.fees + 1] = fee end
    end
    -- (a plan to be learned from: another of your characters may have it, or can buy it at auction as well as you)
    for _, fee in ipairs(needs.fees) do
        local r = fee.r
        if r.plan ~= 0 then
            local _, have = ns.Have(r.plan)
            if have.bags + have.bank + have.mail + (have.pending or 0) <= 0 then
                if have.alts[1] then
                    local name = have.alts[1].name
                    needs.sends[name] = needs.sends[name] or {}
                    table.insert(needs.sends[name], { id = r.plan, n = 1 })
                elseif (r.learnHow or ""):find("auction") then
                    shop[r.plan] = 1
                end
            end
        end
    end

    for id, n in pairs(leaf) do
        local need = ns.Whole(n)
        if need > 0 then
            local _, have = ns.Have(id)
            local e = { id = id, need = need, alts = {}, auction = 0, auctionCost = 0, vendor = 0, beyond = 0, guess = 0,
                cost = 0, uses = uses[id] or {} }
            local left = need
            local function Use(n2)
                local use = math.min(left, n2)
                left = left - use
                return use
            end
            e.bags, e.pending, e.bank, e.mail = Use(have.bags), Use(have.pending or 0), Use(have.bank), Use(have.mail)
            if e.bank > 0 then needs.bank[#needs.bank + 1] = { id = id, n = e.bank } end
            if e.mail > 0 then needs.mail[#needs.mail + 1] = { id = id, n = e.mail } end
            for _, alt in ipairs(have.alts) do
                local use = Use(alt.n)
                if use > 0 then
                    e.alts[#e.alts + 1] = { name = alt.name, n = use }
                    needs.sends[alt.name] = needs.sends[alt.name] or {}
                    table.insert(needs.sends[alt.name], { id = id, n = use })
                end
            end
            if left > 0 then
                local c = ns.CostOf(id, left, plan.meta.price[id])
                e.auction, e.auctionCost, e.vendor, e.beyond, e.guess, e.cost = c.auction, c.auctionCost, c.vendor,
                    c.beyond, c.guess, c.cost
                if e.auction + e.beyond + e.guess > 0 then shop[id] = e.auction + e.beyond + e.guess end
            end
            needs.items[#needs.items + 1] = e
        end
    end
    table.sort(needs.items, function(a, b)
        if a.cost ~= b.cost then return a.cost > b.cost end
        return a.id < b.id
    end)

    -- For your other characters: what to mail, and what's to buy (any of them can buy it and mail it), kept where
    -- they'll see it (only for steps you planned: the whole route's would be everything they have)
    local sends = ns.DB().sends
    local myKey = ns.MyKey()
    if needs.planned > 0 and (next(needs.sends) or next(shop)) then
        local from = {}
        for name, list in pairs(needs.sends) do
            from[name] = {}
            for _, each in ipairs(list) do from[name][each.id] = each.n end
        end
        sends[myKey] = { to = me.name, realm = me.realm, faction = me.faction, at = time(), from = from, buy = shop }
    else
        sends[myKey] = nil
    end
    needsCache.key, needsCache.needs = key, needs
    return needs
end

-- What your other characters' planned steps need from this one (the Mail tab's list): what it has that they
-- asked for, and what they'd have to buy, which this character can buy for them instead:
-- { { to, key (whose list it is), items = { { id, n (here, to mail), bags, mail, pending (bought, on its way to
--     the mailbox), bank, buy (still to buy) } } } }
-- What's here is taken from the bags first, then the mailbox, then the bank.
function ns.SendsFromMe()
    local me, myKey = ns.Me(), ns.MyKey()
    local list = {}
    if not me then return list end
    for key, s in pairs(ns.DB().sends) do
        local theirs = key ~= myKey and type(s) == "table" and s.realm == me.realm
            and (not s.faction or not me.faction or s.faction == me.faction)
            and time() - (s.at or 0) < SEND_DAYS * 86400
        if theirs then
            local mine = type(s.from) == "table" and type(s.from[me.name]) == "table" and s.from[me.name] or {}
            local shop = type(s.buy) == "table" and s.buy or {}
            local ids = {}
            for id in pairs(mine) do ids[id] = true end
            for id in pairs(shop) do ids[id] = true end
            local items = {}
            for id in pairs(ids) do
                local _, have = ns.Have(id)
                local toBuy = tonumber(shop[id]) or 0
                local left = (tonumber(mine[id]) or 0) + toBuy
                local function Use(there)
                    local use = math.max(0, math.min(left, there or 0))
                    left = left - use
                    return use
                end
                local e = { id = id }
                e.bags, e.mail, e.pending, e.bank = Use(have.bags), Use(have.mail), Use(have.pending), Use(have.bank)
                e.n = e.bags + e.mail + e.pending + e.bank
                e.buy = math.min(left, toBuy)
                if e.n + e.buy > 0 then items[#items + 1] = e end
            end
            table.sort(items, function(a, b) return a.id < b.id end)
            if #items > 0 then list[#list + 1] = { to = s.to or key, key = key, items = items } end
        end
    end
    table.sort(list, function(a, b) return tostring(a.to) < tostring(b.to) end)
    return list
end

-- What so many would cost at the listings known, what one comes to, and how many more than are listed
function ns.MarketCost(id, n)
    local rows = ns.PriceOf(id).rows
    local left, cost, got = n, 0, 0
    for i = 1, #rows, 2 do
        if left <= 0 then break end
        local use = math.min(left, rows[i + 1])
        cost, got, left = cost + use * rows[i], got + use, left - use
    end
    return cost, got > 0 and cost / got or nil, left
end

-- "8 Silver Bar, 30 Steel Bar and 2 more to Mia" (what's here; nil if all of it is still to buy)
function ns.SendText(send, most)
    local here = {}
    for _, each in ipairs(send.items) do
        if each.n > 0 then here[#here + 1] = each.n .. " " .. ns.PlainName(each.id) end
    end
    if #here == 0 then return nil end
    local parts = {}
    for i = 1, math.min(#here, most or 3) do parts[i] = here[i] end
    local more = #here - #parts
    return table.concat(parts, ", ") .. (more > 0 and (" and " .. more .. " more") or "") .. " to " .. send.to
end

-- Said at a mailbox as it opens, and once when you log in (login: only if it hasn't been said yet). Only of what's
-- here to be mailed: what's still to buy is in the window, on every other character, and isn't called out.
local reminded = false

function ns.SendReminder(login)
    if login and reminded then return end
    reminded = true
    for _, send in ipairs(ns.SendsFromMe()) do
        local text = ns.SendText(send, 6)
        -- (a note, not a chat line: nobody asked)
        if text then QuietKit.Toast("To mail from here: " .. text .. ". /qprof has the list.",
            "Interface\\Icons\\INV_Letter_15") end
    end
end

-- ---------- mailed ----------
-- n of an item went from here to the character whose list it was on: off the list (first what was asked of this
-- character, then what was to be bought), and counted there as on its way (as what it bought at auction is) until
-- it has been to a mailbox. (whole: what was asked of this character goes, however many: the Sent button's.)
function ns.NoteMailed(key, id, n, whole)
    local db, me = ns.DB(), ns.Me()
    local s = db.sends[key]
    n = tonumber(n) or 0
    if not me or type(s) ~= "table" or n <= 0 then return end
    s.from = type(s.from) == "table" and s.from or {}
    s.buy = type(s.buy) == "table" and s.buy or {}
    local mine = s.from[me.name]
    local asked, toBuy = type(mine) == "table" and tonumber(mine[id]) or 0, tonumber(s.buy[id]) or 0
    if asked + toBuy <= 0 then return end
    local off = math.min(n, asked)
    if type(mine) == "table" then
        mine[id] = asked - off
        if whole or mine[id] <= 0 then mine[id] = nil end
        if not next(mine) then s.from[me.name] = nil end
    end
    if toBuy > 0 then
        s.buy[id] = toBuy - (n - off)
        if s.buy[id] <= 0 then s.buy[id] = nil end
    end
    if not next(s.from) and not next(s.buy) then db.sends[key] = nil end
    local char = db.chars[key]
    if type(char) == "table" then
        char.pending = char.pending or {}
        local p = char.pending[id] or { n = 0 }
        p.n, p.at = (p.n or 0) + n, time()
        char.pending[id] = p
    end
    ns.Changed()
    if ns.RefreshWindow then ns.RefreshWindow() end
end

-- What the mail being sent carries, if it's to a character with a list here: counted when the game says it went.
-- (On Forever a name has a surname after it: "Mia Smith" is Mia.)
local outgoing

local function NoteSending(to)
    outgoing = nil
    to = Plain(to)
    if type(to) ~= "string" then return end
    to = strtrim(to):lower()
    for _, send in ipairs(ns.SendsFromMe()) do
        local name = tostring(send.to):lower()
        local after = to:sub(#name + 1, #name + 1)
        if to:sub(1, #name) == name and (after == "" or after == " " or after == "-") then
            local items = {}
            for i = 1, ATTACHMENTS_MAX_SEND or 12 do
                local _, id, _, count = Call(GetSendMailItem, i)
                id = tonumber(Plain(id))
                if id then items[id] = (items[id] or 0) + (tonumber(Plain(count)) or 1) end
            end
            outgoing = { key = send.key, items = items }
            return
        end
    end
end

if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", function(to) pcall(NoteSending, to) end)
end

local mailEvents = CreateFrame("Frame")
pcall(mailEvents.RegisterEvent, mailEvents, "MAIL_SEND_SUCCESS")
pcall(mailEvents.RegisterEvent, mailEvents, "MAIL_FAILED")
mailEvents:SetScript("OnEvent", function(_, event)
    local sent = outgoing
    outgoing = nil
    if event == "MAIL_SEND_SUCCESS" and sent then
        for id, n in pairs(sent.items) do ns.NoteMailed(sent.key, id, n) end
    end
end)
