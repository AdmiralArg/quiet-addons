-- Quiet Professions: the cheapest way to level a profession from where you are, reckoned from today's prices, what
-- you already have and what you could wear.
--
-- The guides everyone follows name the same materials, and those are the ones that cost most. This looks at every
-- recipe of the profession instead (Data\, from Wowhead's WoW Forever pages) and at:
--  * what's in your bags and bank, and your other characters' (QuietKit.Stock: the count all Quiet addons share);
--  * what the auction house asks, listing by listing (Check prices at the auction house; Quiet Auctions' scans
--    too, if it's on), and what vendors sell;
--  * which recipes you know, and what the ones you don't would cost to learn;
--  * what of it your characters could wear: gear worth making on the way is put into the route;
--  * and, for a cook, what of it suits your class to eat (Food.lua): strength for a warrior, not spirit.
-- and works out which recipe to make at each skill point (Solver.lua). /qprof opens the window.
--
-- Besides the route: the plans you lack that would make it cheaper (Plans), what you could make now and sell for
-- more than it costs (Sell), and, for the steps you mark with Plan, what to fetch from the bank, what your other
-- characters should mail you (each has a Mail tab listing it, and is told when it logs in and at a mailbox) and
-- what to buy.
-- It makes nothing, and buys only on your press: Buy on a material asks the auction house its price, and a second
-- press, on Pay, pays the total it showed (Buy.lua). "Find" opens an item on the game's own auction page instead.
--
-- This file: what's kept, the data's shape, this character's skills, known recipes and gear, and /qprof.
-- Values can be secret in combat: anything read from the game goes through Plain first.
local ADDON, ns = ...

local issecret = issecretvalue or function() return false end

-- nil for a value the game keeps secret (in combat)
local function Plain(value)
    if issecret(value) then return nil end
    return value
end
ns.Plain = Plain

-- fn(...)'s answers, or nothing when it's missing or fails
local function Answers(ok, ...)
    if ok then return ... end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Answers(pcall(fn, ...))
end
ns.Call = Call

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end
ns.After = After

function ns.Say(msg)
    QuietKit.Print("Quiet Professions", msg)
end

-- ---------- what's kept ----------
-- QuietProfessionsDB = {
--   chars = { ["Name-Realm"] = { name, realm, faction, class, level,
--               skills = { [profession] = { level, max } }, known = { [profession] = { [spell] = true } },
--               gear = { [slot] = link }, make = { [spell:who] = true / false (gear asked for, or turned down),
--                 or a number (so many of a food to make) },
--               planTo = { [profession] = place on the route } (how far you mean to go now: Plan.lua),
--               kept = { [profession] = { [skill] = spell } } (the recipe each planned point keeps),
--               pending = { [item] = { n, at } } (bought here, or mailed here by another of your characters, and
--                 not seen at a mailbox yet),
--               goal = { [profession] = skill }, profession (the one shown) } },
--   markets = { ["Realm-Faction"] = { looked = { [item] = { at, r = { price, qty, ... } } } } },
--   vendor = { [item] = price } (seen at a vendor, always in stock),
--   sends = { ["Name-Realm" (who wants them)] = { to, realm, faction, at, from = { [sender] = { [item] = n } },
--               buy = { [item] = n } (what it would buy at auction: another character can, and mail it) } }
--     (what a character's planned steps need from your other characters: their Mail tab lists it, and what they
--     mail comes off it),
--   settings = { ownFree, alts, sellAuction }, window = { pos }, welcome
-- }
function ns.DB()
    QuietProfessionsDB = QuietProfessionsDB or {}
    local db = QuietProfessionsDB
    db.chars = db.chars or {}
    db.markets = db.markets or {}
    db.vendor = db.vendor or {}
    db.settings = db.settings or {}
    db.window = db.window or {}
    db.sends = db.sends or {}
    return db
end

local DEFAULTS = {
    ownFree = true,       -- what you have counts as free (off: as what it would sell for)
    alts = true,          -- your other characters' bags, bank and mail count too
    sellAuction = true,   -- the first of each thing you make is sold at auction (off: all of it to a vendor)
    greens = false,       -- green recipes are on the route where they're cheapest per point (off: only for want of others)
    eat = true,           -- a cook's route makes the food your class eats where it gives points (off: the cheapest)
}

function ns.Setting(key)
    local value = ns.DB().settings[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

function ns.SetSetting(key, value)
    ns.DB().settings[key] = value
    ns.Changed()
end

-- ---------- when something changed ----------
-- ns.version goes up with everything a route depends on; the window and the plan follow (Plan.lua, Window.lua)
ns.version = 0
ns.bagVersion = 0
local pending = false

function ns.Changed()
    ns.version = ns.version + 1
    if pending then return end
    pending = true
    After(0.3, function()
        pending = false
        if ns.OnChanged then ns.OnChanged() end
    end)
end

-- ---------- the data ----------
-- ns.professions[id] = { id, name, recipes = { r }, bySpell = { [spell] = r }, paper (what its recipes are learned
--   from is called: "plan", "pattern", "recipe"...) }
--   r = { id (its spell), name, item, n, learn, yellow, grey, how, cost, spec, plan, reagents = { item, qty, ... },
--         tools = { { item, another that does for it, ... }, ... } or nil (what it needs to hand, once: a hammer,
--         a runed rod; the solver gets each once for the whole route) }
-- ns.items[item] = { name, quality, buy, sell, kind (2 weapon, 4 armour, 0), sub, slot, level, ilvl }
-- ns.plans[plan item] = { faction, standing (needed to learn it; 0: none), vendors = { { name, zone, side (1 Alliance,
--   2 Horde, 3 both, 0 unknown), limited } }, quest (its name, or ""), dropped ("who, where", or "") }
-- ns.foods[item] = { health, mana (what eating it restores), minutes (of well fed), text (what that gives, in
--   words), stats = { str = 20, ... } }
ns.professions = {}
ns.items = {}
ns.plans = {}
ns.foods = {}
ns.professionOrder = {}

-- What a profession's recipes are learned from is called, from what most of those things are named in the data:
-- "Plans: Copper Mace" makes it a smith's "plan", "Pattern: Red Linen Robe" a tailor's "pattern"
local function PaperWord(prof, items)
    local count, best = {}, nil
    for _, r in ipairs(prof.recipes) do
        local it = r.plan ~= 0 and items[r.plan]
        local word = it and it[1]:match("^(%a+):")
        if word then count[word] = (count[word] or 0) + 1 end
    end
    for word, n in pairs(count) do
        if not best or n > count[best] or (n == count[best] and word < best) then best = word end
    end
    return best and (best:lower():gsub("s$", "")) or "plan"
end

function ns.AddProfession(id, name, rows, items, plans, foods)
    for item, p in pairs(plans or {}) do
        local info = { faction = p[1], standing = p[2], vendors = {}, quest = p[4] or "", dropped = p[5] or "" }
        for i = 1, #p[3], 4 do
            info.vendors[#info.vendors + 1] = { name = p[3][i], zone = p[3][i + 1], side = p[3][i + 2],
                limited = p[3][i + 3] == 1 }
        end
        ns.plans[item] = info
    end
    local prof = { id = id, name = name, recipes = {}, bySpell = {} }
    for _, row in ipairs(rows) do
        local r = { id = row[1], name = row[2], item = row[3], n = row[4], learn = row[5], yellow = row[6],
            grey = row[7], how = row[8], cost = row[9], spec = row[10], plan = row[11], reagents = {}, prof = id,
            tools = row.tools }
        for i = 12, #row do r.reagents[#r.reagents + 1] = row[i] end
        prof.recipes[#prof.recipes + 1] = r
        prof.bySpell[r.id] = r
    end
    prof.paper = PaperWord(prof, items)
    for item, it in pairs(items) do
        ns.items[item] = { name = it[1], quality = it[2], buy = it[3], sell = it[4], kind = it[5], sub = it[6],
            slot = it[7], level = it[8], ilvl = it[9] }
    end
    for item, f in pairs(foods or {}) do
        local food = { health = f[1], mana = f[2], minutes = f[3], text = f[4], stats = {} }
        for i = 5, #f, 2 do food.stats[f[i]] = f[i + 1] end
        ns.foods[item] = food
        prof.food = true -- (it makes things to eat: its window has a Food list where the others have Gear)
    end
    ns.professions[id] = prof
    ns.professionOrder[#ns.professionOrder + 1] = id
end

-- What the thing a recipe is learned from is called in a profession: a smith's "plan", a cook's "recipe", a
-- tailor's "pattern"
function ns.Paper(profID)
    local prof = ns.professions[profID]
    return prof and prof.paper or "plan"
end

-- ...and many of them, as the name of their tab: "Plans", "Recipes", "Patterns"
function ns.Papers(profID)
    local word = ns.Paper(profID)
    return word:sub(1, 1):upper() .. word:sub(2) .. "s"
end

-- ---------- money and names ----------
local GOLD, SILVER, COPPER = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"

function ns.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. GOLD end
    if s > 0 then parts[#parts + 1] = s .. SILVER end
    -- (no coppers on a sum in gold: they only make it longer)
    if (c > 0 and g == 0) or #parts == 0 then parts[#parts + 1] = c .. COPPER end
    return sign .. table.concat(parts, " ")
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- An item's plain name: the data's, else the game's
function ns.PlainName(id)
    local it = ns.items[id]
    if it and it.name ~= "" then return it.name end
    local name = Plain(Call(GetInfo, id))
    return type(name) == "string" and name or ("item " .. tostring(id))
end

-- The name in its quality's colour
function ns.ItemName(id)
    local it = ns.items[id]
    local name, quality = ns.PlainName(id), it and it.quality
    if not it then quality = Plain(select(3, Call(GetInfo, id))) end
    local colour = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if colour and colour.hex then return colour.hex .. name .. "|r" end
    return name
end

-- A count for showing: 13.2 makings are 14
function ns.Whole(n)
    return math.ceil((n or 0) - 1e-6)
end

-- ---------- this character ----------
local myKey
local settled = false

-- Two lists of looked-up prices for one market (below): each item as it was looked up last
local function JoinLooked(named, nameless)
    if type(named) ~= "table" or type(nameless) ~= "table" then return nameless end
    nameless.looked = nameless.looked or {}
    for id, look in pairs(named.looked or {}) do
        local other = nameless.looked[id]
        if not other or (tonumber(look.at) or 0) > (tonumber(other.at) or 0) then nameless.looked[id] = look end
    end
    return nameless
end

-- This realm's name, as every Quiet addon knows it (QuietKit.Realm: never the game's own GetRealmName, which can be
-- empty). The first time it's asked for once the game has logged the character in, what was kept while the realm had
-- no name is moved under its name.
function ns.Realm()
    if not settled and QuietKit.Stock.MyKey() then
        settled = true
        local db = ns.DB()
        QuietKit.RealmFold(db.chars)
        QuietKit.RealmFold(db.sends)
        QuietKit.RealmFold(db.markets, true, JoinLooked)
        -- (and who each thing asked for is for: make["spell:Name-"] is "spell:Name-Realm")
        local realm = QuietKit.Realm()
        for _, char in pairs(realm ~= "" and db.chars or {}) do
            local make, nameless = type(char) == "table" and char.make, {}
            for key in pairs(type(make) == "table" and make or {}) do
                if type(key) == "string" and key:match(":.+%-$") then nameless[#nameless + 1] = key end
            end
            for _, key in ipairs(nameless) do
                make[key .. realm], make[key] = make[key], nil
            end
        end
    end
    return QuietKit.Realm()
end

function ns.Me()
    if not myKey then
        -- (the same "Name-Realm" as the shared count's, QuietKit.Stock; nil until the game has logged it in)
        myKey = QuietKit.Stock.MyKey()
        if not myKey then return nil end
        ns.Realm()
    end
    local chars = ns.DB().chars
    local me = chars[myKey] or {}
    chars[myKey] = me
    me.name, me.realm = myKey:match("^(.-)%-(.*)$")
    local _, class = UnitClass("player")
    me.class = Plain(class) or me.class
    me.level = tonumber(Plain(UnitLevel("player"))) or me.level or 1
    local faction = Plain(UnitFactionGroup("player"))
    if type(faction) == "string" and faction ~= "Neutral" then me.faction = faction end
    me.skills = me.skills or {}
    me.known = me.known or {}
    me.gear = me.gear or {}
    me.make = me.make or {}
    me.goal = me.goal or {}
    return me
end

function ns.MyKey()
    ns.Me()
    return myKey
end

-- Your characters on this realm and side that have been logged in with this on: { [key] = char }
function ns.MyChars()
    local list, me = {}, ns.Me()
    if not me then return list end
    for key, char in pairs(ns.DB().chars) do
        if type(char) == "table" and char.realm == me.realm and (not char.faction or not me.faction
            or char.faction == me.faction) then
            list[key] = char
        end
    end
    return list
end

-- ---------- its standing with a faction ----------
-- (some plans can only be learned by a friend of the Thorium Brotherhood, the Argent Dawn...)
local FACTIONS = {
    [59] = "the Thorium Brotherhood", [270] = "the Zandalar Tribe", [529] = "the Argent Dawn",
    [576] = "Timbermaw Hold", [609] = "the Cenarion Circle", [749] = "the Hydraxian Waterlords",
}
local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- Your standing with a faction (4 neutral ... 8 exalted) and its name; nil while the game doesn't say (a faction
-- you haven't met)
function ns.Standing(faction)
    local data = C_Reputation and Call(C_Reputation.GetFactionDataByID, faction)
    if type(data) ~= "table" then return nil, FACTIONS[faction] end
    local name = Plain(data.name)
    return tonumber(Plain(data.reaction)), FACTIONS[faction] or (type(name) == "string" and name) or nil
end

function ns.StandingName(standing)
    return _G["FACTION_STANDING_LABEL" .. tostring(standing)] or STANDINGS[standing] or tostring(standing)
end

-- ---------- its skills ----------
-- Forever numbers some professions' skill lines anew (2946 is Mining): by number where it's the old one, by name
-- otherwise
local ALIAS = { [2946] = 186, [2939] = 185 }

local function ProfessionFor(line, name)
    line = tonumber(line)
    if line then
        line = ALIAS[line] or line
        if ns.professions[line] then return line end
    end
    if type(name) == "string" then
        for id, prof in pairs(ns.professions) do
            if name:find(prof.name, 1, true) then return id end
        end
    end
    return nil
end
local function NoteSkill(me, id, level, max)
    level, max = tonumber(level), tonumber(max)
    if not id or not level or level <= 0 then return false end
    local s = me.skills[id] or {}
    me.skills[id] = s
    local changed = s.level ~= level or (max and max > 0 and s.max ~= max)
    s.level = level
    if max and max > 0 then s.max = max end
    return changed and true or false
end

-- The professions' skill, from whichever of the game's lists this client has
function ns.ReadSkills()
    local me = ns.Me()
    if not me then return end
    local changed, seen, listed = false, {}, false
    if GetProfessions and GetProfessionInfo then
        local list = { pcall(GetProfessions) }
        if list[1] then
            for i = 2, 7 do
                local index = Plain(list[i])
                if index then
                    listed = true
                    local name, _, level, max, _, _, line = Call(GetProfessionInfo, index)
                    local id = ProfessionFor(Plain(line), Plain(name))
                    if id then
                        seen[id] = true
                        changed = NoteSkill(me, id, Plain(level), Plain(max)) or changed
                    end
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, tonumber(Plain(Call(GetNumSkillLines))) or 0 do
            local name, header, _, level, _, _, max = Call(GetSkillLineInfo, i)
            if Plain(name) and not Plain(header) then
                local id = ProfessionFor(nil, Plain(name))
                if id then
                    seen[id], listed = true, true
                    changed = NoteSkill(me, id, Plain(level), Plain(max)) or changed
                end
            end
        end
    end
    local ui = C_TradeSkillUI
    if ui and ui.GetProfessionInfoBySkillLineID then
        for id in pairs(ns.professions) do
            if not seen[id] then
                local info = Call(ui.GetProfessionInfoBySkillLineID, id)
                if type(info) == "table" and (tonumber(Plain(info.skillLevel)) or 0) > 0 then
                    seen[id] = true
                    changed = NoteSkill(me, id, Plain(info.skillLevel), Plain(info.maxSkillLevel)) or changed
                end
            end
        end
    end
    -- (a profession given up: gone from the game's list, so from ours)
    if listed then
        for id in pairs(me.skills) do
            if not seen[id] then
                me.skills[id], changed = nil, true
            end
        end
    end
    if changed then ns.Changed() end
end

-- ---------- the recipes it knows ----------
-- Read while the profession's own window is open: the game tells what's learned only there
local ui = C_TradeSkillUI

-- Someone else's window (a linked or guild profession, an NPC's)
local function Viewing()
    if not ui then return true end
    return Plain(Call(ui.IsTradeSkillLinked)) or Plain(Call(ui.IsTradeSkillGuild)) or Plain(Call(ui.IsNPCCrafting))
end

function ns.ReadRecipes()
    local me = ns.Me()
    if not me or not (ui and ui.GetAllRecipeIDs and ui.GetRecipeInfo) or Viewing() then return end
    if Plain(Call(ui.IsTradeSkillReady)) == false then return end
    local base = Call(ui.GetBaseProfessionInfo)
    if type(base) ~= "table" then return end
    local id = ProfessionFor(Plain(base.professionID), Plain(base.professionName))
        or ProfessionFor(Plain(base.parentProfessionID), Plain(base.parentProfessionName))
    if not id then return end
    local changed = NoteSkill(me, id, Plain(base.skillLevel), Plain(base.maxSkillLevel))
    local prof, known, count = ns.professions[id], {}, 0
    for _, rid in pairs(Call(ui.GetAllRecipeIDs) or {}) do
        rid = Plain(rid)
        local info = rid and Call(ui.GetRecipeInfo, rid)
        -- (only this profession's: Forever shows a few of another's in the same window)
        if type(info) == "table" and Plain(info.learned) and prof.bySpell[rid] then
            known[rid] = true
            count = count + 1
        end
    end
    if count == 0 then return end
    local old = me.known[id] or {}
    for rid in pairs(known) do
        if not old[rid] then changed = true end
    end
    for rid in pairs(old) do
        if not known[rid] then changed = true end
    end
    me.known[id] = known
    if changed then ns.Changed() end
end

-- ---------- what it wears ----------
function ns.ReadGear()
    local me = ns.Me()
    if not me or not GetInventoryItemLink then return end
    local changed = false
    for slot = 1, 18 do
        local link = Plain(Call(GetInventoryItemLink, "player", slot)) or false
        if (me.gear[slot] or false) ~= link then
            me.gear[slot] = link or nil
            changed = true
        end
    end
    if changed then ns.Changed() end
end

-- ---------- events ----------
local soon = {}

-- fn once, a moment after the last of a burst of events
local function Soon(key, seconds, fn)
    if soon[key] then return end
    soon[key] = true
    After(seconds, function()
        soon[key] = nil
        fn()
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "MAIL_SHOW" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- (a moment for the game to know the character)
        After(2, function()
            ns.ReadSkills()
            ns.ReadGear()
        end)
        -- (and, once, what another of your characters is waiting for from this one)
        After(8, function()
            if ns.SendReminder then ns.SendReminder(true) end
        end)
    elseif event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
        ns.bagVersion = ns.bagVersion + 1
        ns.Changed()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        Soon("gear", 0.5, ns.ReadGear)
    elseif event == "PLAYER_LEVEL_UP" then
        Soon("skills", 1, function()
            ns.ReadSkills()
            ns.Changed()
        end)
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        Soon("skills", 0.5, ns.ReadSkills)
    elseif event == "MAIL_SHOW" then
        -- (what another of your characters is waiting for from this one)
        After(1, function()
            if ns.SendReminder then ns.SendReminder() end
        end)
    else
        Soon("recipes", 0.7, function()
            ns.ReadRecipes()
            ns.ReadSkills()
        end)
    end
end)

-- ---------- /qprof ----------
-- What each of the game's lists says about your professions (when the window shows the wrong skill)
local function Debug()
    local me = ns.Me()
    local lines = {}
    for id, s in pairs(me and me.skills or {}) do
        local known = 0
        for _ in pairs(me.known[id] or {}) do known = known + 1 end
        lines[#lines + 1] = ns.professions[id].name .. " " .. tostring(s.level) .. "/" .. tostring(s.max) .. ", "
            .. known .. " recipes known"
    end
    ns.Say("kept: " .. (#lines > 0 and table.concat(lines, "; ") or "no profession seen yet") .. ".")
    if GetProfessions and GetProfessionInfo then
        local list = { pcall(GetProfessions) }
        for i = 2, 7 do
            if list[i] then
                local name, _, level, max, _, _, line = Call(GetProfessionInfo, list[i])
                ns.Say("GetProfessionInfo: " .. tostring(name) .. " " .. tostring(level) .. "/" .. tostring(max)
                    .. ", line " .. tostring(line))
            end
        end
    else
        ns.Say("no GetProfessions here.")
    end
    local base = ui and Call(ui.GetBaseProfessionInfo)
    if type(base) == "table" then
        ns.Say("open window: " .. tostring(base.professionName) .. " (" .. tostring(base.professionID) .. ") "
            .. tostring(base.skillLevel) .. "/" .. tostring(base.maxSkillLevel))
    end
end

SLASH_QUIETPROFESSIONS1 = "/qprof"
SLASH_QUIETPROFESSIONS2 = "/quietprofessions"
SlashCmdList.QUIETPROFESSIONS = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.ToggleWindow()
    elseif cmd == "prices" or cmd == "scan" then
        ns.CheckPrices()
    elseif cmd == "goal" then
        local goal = tonumber(rest)
        if goal and ns.SetGoal then ns.SetGoal(goal) else ns.Say("/qprof goal 225: the skill to plan to.") end
    elseif cmd == "debug" then
        Debug()
    elseif cmd == "options" or cmd == "settings" then
        if not QuietKit.Open("quietprofessions") then ns.Say("its settings are in Options, AddOns, Quiet.") end
    else
        ns.Say("/qprof opens the route; /qprof prices looks up prices (at the auction house); /qprof goal 225 sets "
            .. "the skill to plan to; /qprof options for its settings; /qprof debug says what the game tells about "
            .. "your professions.")
    end
end

ns.ADDON = ADDON
