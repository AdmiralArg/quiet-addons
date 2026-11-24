-- Food worth cooking: what the profession makes that suits your class to eat.
--
-- In WoW Forever every cooked food makes you "well fed" with one thing (20 Strength, 40 Attack Power, 28 Spell
-- Damage...) for 15 minutes, and what a food gives is in the data (Data\Cooking.lua, from Wowhead's tooltips).
-- Each class has the things it eats for, in order (ORDER below): a warrior strength (attack power counts as
-- strength, two of it for one), then stamina, and nothing else. A food suits a class by the first of those it
-- gives. That order is used twice:
--  * the route (Plan.lua, Solver.lua): where a food that suits you gives points, that one is made, strength before
--    stamina, even when another recipe is cheaper. Of two strength foods the one that gives more, so the route
--    doesn't go from a +5 back to a +3 because the +3 got cheaper; what you can't eat yet at your level comes after
--    what you can. What you level on is then food you can eat. (A setting, on unless you turn it off; the window
--    says what it costs over the cheapest route.)
--  * the Food tab: for each of your characters the best food of each kind it can eat now, and the next better one
--    it's about to grow into, strength first. What you ask for there (Make 5, More) is put into the route as that
--    many, made as soon as the skill is there. Nothing is asked for on your behalf: food costs materials every time.
-- The warrior's order is the one its player gave. The other classes' are a plain rule of thumb, until they're played.
local _, ns = ...

local AHEAD = 3        -- levels above the character's that still count ("soon")
local OTHERS_FROM = 10 -- another of your characters is listed from this level (a bank character doesn't eat)
local BATCH = 5        -- Make and More add this many, Fewer takes them off
local MOST = 40

-- What a class eats for, the most wanted first. Each is a kind: a stat and what a point of it counts for, and any
-- other stat that counts as the same kind (a warrior's attack power is strength: two of it do what one strength does)
local ORDER = {
    WARRIOR = { { "str", 1, "ap", 0.5 }, { "sta", 1 } },
    PALADIN = { { "str", 1, "ap", 0.5 }, { "sta", 1 }, { "int", 1 } },
    ROGUE = { { "agi", 1, "ap", 1 }, { "sta", 1 } },
    HUNTER = { { "agi", 1, "ap", 1 }, { "sta", 1 } },
    SHAMAN = { { "int", 1 }, { "sta", 1 }, { "str", 1 } },
    DRUID = { { "int", 1 }, { "sta", 1 }, { "str", 1 }, { "agi", 1 } },
    MAGE = { { "sp", 1 }, { "int", 1 }, { "sta", 1 } },
    PRIEST = { { "heal", 1 }, { "sp", 1 }, { "int", 1 }, { "spi", 1 }, { "sta", 1 } },
    WARLOCK = { { "sp", 1 }, { "sta", 1 }, { "int", 1 } },
}
local KIND = { str = "strength", agi = "agility", sta = "stamina", int = "intellect", spi = "spirit",
    ap = "attack power", sp = "spell damage", heal = "healing", crit = "critical strike", armor = "armor" }

-- Whether a food suits a class: its place in the class's order (1: the most wanted), what kind that is
-- ("strength"), how much of it the food comes to (20 attack power: 10, for a warrior), and the stat it comes from
-- if that's another than the kind's own ("ap"). nil: it gives nothing the class eats for.
function ns.FoodSuits(item, class)
    local food, order = ns.foods[item], ORDER[class]
    if not food or not order then return nil end
    for rank, kind in ipairs(order) do
        local amount, from, most = 0, nil, 0
        for i = 1, #kind, 2 do
            local worth = (food.stats[kind[i]] or 0) * kind[i + 1]
            amount = amount + worth
            if worth > most then from, most = kind[i], worth end
        end
        if amount > 0 then return rank, KIND[kind[1]], amount, from ~= kind[1] and from or nil end
    end
end

-- Where a food stands for a character of this class and level, to put the foods that give points in order (the
-- lower the sooner made): the kind the class wants most first, there what can be eaten now (or within a few
-- levels) before what can't yet, and of those the one that gives the most. nil: it doesn't suit the class.
function ns.FoodTier(item, class, level)
    local rank, _, amount = ns.FoodSuits(item, class)
    if not rank then return nil end
    local it = ns.items[item]
    local late = it and it.level > (level or 1) + AHEAD
    return rank * 10000 + (late and 5000 or 0) - math.min(4999, amount)
end

-- "strength, then stamina": what a class eats for, in words (nil: no order for it)
function ns.FoodOrder(class)
    local order = ORDER[class]
    if not order then return nil end
    local names = {}
    for i, kind in ipairs(order) do names[i] = KIND[kind[1]] end
    return table.concat(names, ", then ")
end

-- ---------- the list ----------
-- Every food worth cooking in this profession, for every character:
-- { r, item, food, who, key, mine, rank (its place in the class's order), kind (what it's for: "strength"),
--   amount (how much of that it comes to), from (the stat it comes from, if another: "attack power"),
--   needLevel (nil: can eat it now), best (the best of its kind it can eat now) }
-- usable(r): the recipe is known or can be learned. upTo: only recipes learned by that skill.
function ns.FoodFor(profID, usable, upTo)
    local prof = ns.professions[profID]
    local list = {}
    if not prof or not prof.food then return list end
    local myKey = ns.MyKey()
    for key, char in pairs(ns.MyChars()) do
        local class, level = char.class, char.level or 1
        if class and ORDER[class] and (key == myKey or level >= OTHERS_FROM) then
            -- (the best of each kind to eat now, and the best that comes within a few levels)
            local now, soon = {}, {}
            for _, r in ipairs(prof.recipes) do
                local it = ns.items[r.item]
                local rank, kind, amount, from = ns.FoodSuits(r.item, class)
                if rank and it and r.learn <= upTo and it.level <= level + AHEAD and usable(r) then
                    local entry = { r = r, item = r.item, food = ns.foods[r.item], who = char.name, key = key,
                        mine = key == myKey, rank = rank, kind = kind, amount = amount, from = from and KIND[from],
                        needLevel = it.level > level and it.level or nil }
                    local into = entry.needLevel and soon or now
                    local old = into[rank]
                    -- (of two as good, the one that gives the kind's own stat, then the one learned sooner)
                    if not old or amount > old.amount or (amount == old.amount and ((old.from and not from)
                        or ((old.from ~= nil) == (from ~= nil) and r.learn < old.r.learn))) then
                        into[rank] = entry
                    end
                end
            end
            for _, entry in pairs(now) do
                entry.best = true
                list[#list + 1] = entry
            end
            for rank, entry in pairs(soon) do
                if not now[rank] or entry.amount > now[rank].amount then list[#list + 1] = entry end
            end
        end
    end
    -- (yours first; then by what the class wants most, what can be eaten now before what comes with a level)
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.who ~= b.who then return a.who < b.who end
        if a.rank ~= b.rank then return a.rank < b.rank end
        if (a.needLevel ~= nil) ~= (b.needLevel ~= nil) then return b.needLevel ~= nil end
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.r.name < b.r.name
    end)
    return list
end

-- How many of it to make (0: none): what you pressed
function ns.FoodWanted(entry)
    local me = ns.Me()
    local n = me and me.make[entry.r.id .. ":" .. entry.key]
    return type(n) == "number" and n > 0 and n or 0
end

-- More of it (dir 1) or fewer (-1), a handful at a time
function ns.FoodMore(entry, dir)
    local me = ns.Me()
    if not me then return end
    local n = math.max(0, math.min(MOST, ns.FoodWanted(entry) + dir * BATCH))
    me.make[entry.r.id .. ":" .. entry.key] = n > 0 and n or nil
    ns.Changed()
end

ns.FOOD_BATCH, ns.FOOD_MOST = BATCH, MOST
