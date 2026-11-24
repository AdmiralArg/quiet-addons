-- Gear worth making on the way: what the profession makes that one of your characters could wear and that beats
-- what it wears now.
--
-- For every character that has logged in with this on (its class, level and worn gear are kept), each weapon and
-- piece of armour the recipes make is weighed against what's worn in that slot:
--  * only what the class wears (its armour, mail before 40 and plate after for a warrior; its weapons) and is, or
--    within a few levels will be, high enough to wear;
--  * the heavier armour a class gets at 40 (plate for a warrior and a paladin, mail for a hunter and a shaman,
--    whatever the profession) is looked at from further off, from level 30: what can be worn the day you turn 40
--    is listed "at level 40", next to what you can wear now, and your own best such piece for a slot is made
--    ready like the best you can wear now;
--  * by its stats, weighed for the class (a plain rule of thumb for leveling, not a simulation: strength for a
--    warrior, intellect for a mage, a weapon's damage most of all). The window shows the gain and you decide.
-- What's chosen (your own best pieces by themselves: the best to wear now and the best that comes with the heavier
-- armour; anything else with its Make button) is put into the route as one making each, as soon as the skill is there.
-- Forever has changed some classes: if a weapon or armour kind is wrong for yours, Skip is one press.
local _, ns = ...

local Plain, Call = ns.Plain, ns.Call

local AHEAD = 3     -- levels above the character's that still count ("soon")
local BEHIND = 14   -- gear this far under its level is never an upgrade: not looked at
local PER_SLOT = 2  -- pieces shown for one character's slot
local CLEARLY = 1.05

-- The data's slot numbers (the game's inventory types): { worn in, called }
local SLOTS = {
    [1] = { 1, "head" }, [2] = { 2, "neck" }, [3] = { 3, "shoulders" }, [5] = { 5, "chest" }, [20] = { 5, "chest" },
    [6] = { 6, "waist" }, [7] = { 7, "legs" }, [8] = { 8, "feet" }, [9] = { 9, "wrists" }, [10] = { 10, "hands" },
    [16] = { 15, "back" }, [13] = { 16, "one hand" }, [21] = { 16, "main hand" }, [17] = { 16, "two hands" },
    [22] = { 17, "off hand" }, [14] = { 17, "shield" }, [23] = { 17, "off hand" }, [15] = { 18, "ranged" },
    [26] = { 18, "ranged" }, [25] = { 18, "thrown" },
}
local TWO_HAND, OFF_HAND = 17, { [22] = true, [14] = true, [23] = true }

-- Each class's armour (cloth 1, leather 2, mail 3, plate 4): its first, then from level 40 the heavier one
local CLASS_ARMOR = {
    WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, ROGUE = { 2 }, DRUID = { 2 },
    MAGE = { 1 }, PRIEST = { 1 }, WARLOCK = { 1 },
}
local HEAVIER_AT = 40     -- the level the second armour comes at
local HEAVIER_AHEAD = 10  -- ...and how many levels before it its first pieces are listed
local SHIELD = 6
local CLASS_SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- Weapon kinds (the game's numbers) and the classes that use them
local WEAPONS = {
    [0] = "WARRIOR PALADIN HUNTER SHAMAN",                          -- one-hand axes
    [1] = "WARRIOR PALADIN HUNTER SHAMAN",                          -- two-hand axes
    [4] = "WARRIOR PALADIN SHAMAN ROGUE PRIEST DRUID",              -- one-hand maces
    [5] = "WARRIOR PALADIN SHAMAN DRUID",                           -- two-hand maces
    [6] = "WARRIOR PALADIN HUNTER",                                 -- polearms
    [7] = "WARRIOR PALADIN HUNTER ROGUE MAGE WARLOCK",              -- one-hand swords
    [8] = "WARRIOR PALADIN HUNTER",                                 -- two-hand swords
    [10] = "WARRIOR HUNTER SHAMAN DRUID MAGE PRIEST WARLOCK",       -- staves
    [13] = "WARRIOR HUNTER ROGUE SHAMAN DRUID",                     -- fist weapons
    [15] = "WARRIOR HUNTER ROGUE SHAMAN DRUID MAGE PRIEST WARLOCK", -- daggers
    [16] = "WARRIOR HUNTER ROGUE",                                  -- thrown
}

-- What the game calls each stat in an item's list
local STAT = {
    str = { "ITEM_MOD_STRENGTH_SHORT" }, agi = { "ITEM_MOD_AGILITY_SHORT" }, sta = { "ITEM_MOD_STAMINA_SHORT" },
    int = { "ITEM_MOD_INTELLECT_SHORT" }, spi = { "ITEM_MOD_SPIRIT_SHORT" },
    ap = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" },
    rap = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    sp = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    armor = { "RESISTANCE0_NAME" },
    dps = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
}
-- What a point of each is worth to a class while leveling
local WEIGHTS = {
    WARRIOR = { dps = 3, str = 1, agi = 0.6, sta = 0.6, ap = 0.5, armor = 0.02 },
    PALADIN = { dps = 2.5, str = 1, sta = 0.6, int = 0.4, agi = 0.3, ap = 0.5, sp = 0.3, armor = 0.02 },
    HUNTER = { dps = 0.5, agi = 1, sta = 0.5, int = 0.3, ap = 0.5, rap = 0.5, armor = 0.01 },
    ROGUE = { dps = 3, agi = 1, str = 0.5, sta = 0.5, ap = 0.5, armor = 0.01 },
    SHAMAN = { dps = 2, str = 0.7, agi = 0.6, int = 0.6, sta = 0.5, ap = 0.4, sp = 0.5, armor = 0.01 },
    DRUID = { str = 0.8, agi = 0.8, sta = 0.6, int = 0.5, ap = 0.4, sp = 0.4, armor = 0.01 },
    MAGE = { int = 1, sp = 1, sta = 0.5, spi = 0.4 },
    PRIEST = { int = 1, sp = 0.9, spi = 0.8, sta = 0.5 },
    WARLOCK = { sp = 1, sta = 0.8, int = 0.8, spi = 0.3 },
}

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID
local BIND_PICKUP = (Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire) or 1

-- ---------- items the game hasn't told about yet ----------
local asked, waiting = {}, false

local function Ask(item)
    local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
    if not id then return end
    waiting = true
    if asked[id] then return end
    asked[id] = true
    Call(RequestLoad, id)
end

local loader = CreateFrame("Frame")
pcall(loader.RegisterEvent, loader, "GET_ITEM_INFO_RECEIVED")
loader:SetScript("OnEvent", function(_, _, id)
    -- (only ours: the game answers for every tooltip and bag too)
    if not asked[Plain(id) or 0] then return end
    asked[id] = nil
    ns.Changed()
end)

-- An item's score for a class; nil while the game hasn't its data (asked for)
local function Score(item, class)
    if not item then return 0 end
    if not Plain(Call(GetInfo, item)) then
        Ask(item)
        return nil
    end
    -- (the game answers for a link, or "item:<number>": for a bare number it gives nothing, and every piece
    -- the profession makes then scored 0 and never beat what's worn)
    local stats = Call(GetStats, type(item) == "number" and ("item:" .. item) or item)
    if type(stats) ~= "table" then return 0 end
    local score = 0
    for key, weight in pairs(WEIGHTS[class] or {}) do
        for _, name in ipairs(STAT[key]) do
            score = score + (tonumber(Plain(stats[name])) or 0) * weight
        end
    end
    return score
end

-- Can this class wear it (at the level it's worn at)?
local function Wears(class, level, it)
    if it.kind == 4 then
        if it.sub == SHIELD then return CLASS_SHIELD[class] or false end
        local list = CLASS_ARMOR[class]
        if not list then return false end
        if it.sub < 1 or it.sub > 4 then return true end -- (a cloak, a ring: anyone)
        local best = (#list > 1 and level >= HEAVIER_AT) and list[2] or list[1]
        return it.sub >= list[1] and it.sub <= best
    end
    local classes = WEAPONS[it.sub]
    return classes ~= nil and classes:find(class, 1, true) ~= nil
end

-- Is it a piece of the heavier armour the class is about to get: wearable the day it comes, by a character that's
-- within sight of it?
local function ComesWithArmor(class, level, it)
    local list = CLASS_ARMOR[class]
    return it.kind == 4 and list ~= nil and list[2] == it.sub and level < HEAVIER_AT
        and level >= HEAVIER_AT - HEAVIER_AHEAD and it.level <= HEAVIER_AT
end

local function EquipLoc(link)
    return link and Plain(select(4, Call(GetInstant, link))) or nil
end

-- What a piece would take the place of on a character: its score, and the item (nil: nothing worn)
local function Worn(char, it)
    local slot = SLOTS[it.slot][1]
    local worn = char.gear[slot]
    local old = Score(worn, char.class)
    if old == nil then return nil end
    local main = char.gear[16]
    if it.slot == TWO_HAND then
        -- (both hands' worth)
        local off = Score(char.gear[17], char.class)
        if off == nil then return nil end
        old = old + off
    elseif OFF_HAND[it.slot] and EquipLoc(main) == "INVTYPE_2HWEAPON" then
        -- (a two-hand weapon is worn: a shield has to beat it whole)
        old = Score(main, char.class)
        worn = main
    end
    return old, worn
end

-- ---------- the list ----------
-- Every piece worth making for this profession, for every character:
-- { r, item, who, key, mine, slot (its name), gain (percent; nil: nothing worn there), worn (link), needLevel,
--   score, best (the best for that slot that's wearable now), ahead (the best for that slot of the heavier armour
--   the class is about to get, if that beats the best wearable now), bound (true: only the maker can wear it) }
-- usable(r): the recipe is known or can be learned. upTo: only recipes learned by that skill.
-- Then: whether some items' data was still on its way (the list is redone when it comes).
function ns.GearFor(profID, usable, upTo)
    waiting = false
    local prof = ns.professions[profID]
    local list = {}
    if not prof then return list, false end
    local myKey = ns.MyKey()
    for key, char in pairs(ns.MyChars()) do
        local class, level = char.class, char.level or 1
        local bySlot = {}
        if class and WEIGHTS[class] and type(char.gear) == "table" then
            for _, r in ipairs(prof.recipes) do
                local it = r.item ~= 0 and ns.items[r.item]
                if it and (it.kind == 2 or it.kind == 4) and SLOTS[it.slot] and r.learn <= upTo and usable(r)
                    and (it.level <= level + AHEAD or ComesWithArmor(class, level, it)) and it.level >= level - BEHIND
                    and Wears(class, math.max(level, it.level), it) then
                    local new = Score(r.item, class)
                    local old, worn = Worn(char, it)
                    local bound = Plain(select(14, Call(GetInfo, r.item))) == BIND_PICKUP
                    if new and old and new > old * CLEARLY + 0.5 and (key == myKey or not bound) then
                        local where = SLOTS[it.slot]
                        local entry = { r = r, item = r.item, who = char.name, key = key, mine = key == myKey,
                            slot = where[2], gain = old > 0 and (new - old) / old * 100 or nil, worn = worn,
                            needLevel = it.level > level and it.level or nil, score = new, bound = bound,
                            heavier = ComesWithArmor(class, level, it) }
                        bySlot[where[1]] = bySlot[where[1]] or {}
                        table.insert(bySlot[where[1]], entry)
                    end
                end
            end
        end
        for _, entries in pairs(bySlot) do
            table.sort(entries, function(a, b) return a.score > b.score end)
            -- (the best to wear now is always among them, and the best of the armour that's about to come, if
            -- that's the better one; then the next best, whenever they can be worn)
            local now, ahead
            for _, entry in ipairs(entries) do
                if not entry.needLevel then
                    now = now or entry
                elseif entry.heavier then
                    ahead = ahead or entry
                end
            end
            if ahead and now and ahead.score <= now.score then ahead = nil end
            local shown = {}
            if now then
                now.best = true
                shown[#shown + 1] = now
            end
            if ahead then
                ahead.ahead = true
                shown[#shown + 1] = ahead
            end
            for _, entry in ipairs(entries) do
                if #shown >= PER_SLOT then break end
                if entry ~= now and entry ~= ahead then shown[#shown + 1] = entry end
            end
            for _, entry in ipairs(shown) do list[#list + 1] = entry end
        end
    end
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.who ~= b.who then return a.who < b.who end
        if a.r.learn ~= b.r.learn then return a.r.learn < b.r.learn end
        return a.r.name < b.r.name
    end)
    return list, waiting
end

-- Is this piece to be made? What you pressed; else your own best piece for a slot (to wear now, and of the armour
-- that's about to come), if its recipe needs no hunting (known, or a trainer's)
function ns.Wanted(entry)
    local me = ns.Me()
    local chosen = me and me.make[entry.r.id .. ":" .. entry.key]
    if chosen ~= nil then return chosen end
    return entry.mine and (entry.best or entry.ahead) and (ns.Knows(entry.r) or entry.r.how == "T") or false
end

function ns.SetWanted(entry, on)
    local me = ns.Me()
    if not me then return end
    me.make[entry.r.id .. ":" .. entry.key] = on and true or false
    ns.Changed()
end
