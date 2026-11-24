-- Crafting hints: which of your recipes pay. Opening a profession window on a character with the Crafting role
-- notes its learned recipes, for the whole account: what each makes, from what, and who knows it. Only the recipes
-- of characters that have the role now count (give it to a character, or take it away, on the settings page). Then,
-- at today's prices:
--   the materials: each at its cheapest, the last scan's auction price or what a vendor sells it for (noted at
--     vendors, Vendor.lua)
--   the result: what a vendor pays, or its usual auction price after the 5% cut, whichever is more
-- and the recipes where the result is worth more than the materials, the biggest gain first. Smelting cheap ore into
-- bars a vendor pays more for shows up here.
local _, ns = ...

local SHOW = 12

-- ---------- noting recipes ----------
local function ProfessionName()
    local ui = C_TradeSkillUI
    if ui and ui.GetBaseProfessionInfo then
        local ok, info = pcall(ui.GetBaseProfessionInfo)
        if ok and type(info) == "table" and info.professionName then return info.professionName end
    end
    return nil
end

local function NoteRecipes()
    local ui = C_TradeSkillUI
    if not (ui and ui.GetAllRecipeIDs and ui.GetRecipeSchematic and ui.GetRecipeInfo) then return end
    if ui.IsTradeSkillReady then
        local ok, ready = pcall(ui.IsTradeSkillReady)
        if ok and ready == false then return end
    end
    local ok, ids = pcall(ui.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return end
    local recipes = ns.DB().recipes
    local prof, who = ProfessionName(), UnitName("player")
    local noted = 0
    for _, rid in ipairs(ids) do
        local okInfo, info = pcall(ui.GetRecipeInfo, rid)
        if okInfo and type(info) == "table" and info.learned then
            local okS, s = pcall(ui.GetRecipeSchematic, rid, false)
            if okS and type(s) == "table" and (s.outputItemID or 0) > 0 then
                local r = {}
                for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                    local first = slot.reagents and slot.reagents[1]
                    if first and first.itemID and slot.required ~= false then
                        r[#r + 1] = first.itemID
                        r[#r + 1] = slot.quantityRequired or 1
                    end
                end
                local low = s.quantityMin or 1
                local high = s.quantityMax or low
                -- (who knows it: everyone who noted it, kept)
                local by = recipes[rid] and recipes[rid].by or {}
                if who then by[who] = true end
                recipes[rid] = { name = s.name or info.name, out = s.outputItemID, n = (low + high) / 2, r = r,
                    prof = prof, by = by }
                noted = noted + 1
            end
        end
    end
    if noted > 0 then
        ns.Changed()
        ns.Refresh()
    end
end

-- ---------- the hints ----------
-- One of an item at its cheapest now: price, and where ("auction" or "vendor"); nil if neither is known
local function UnitCost(id)
    local ah = ns.Latest(id)
    local vendor = ns.DB().vendorBuy[id]
    if ah and vendor then
        if vendor <= ah then return vendor, "vendor" end
        return ah, "auction"
    end
    if ah then return ah, "auction" end
    if vendor then return vendor, "vendor" end
    return nil
end

-- Known by a character that crafts now
local function Counts(rec, crafters)
    for name in pairs(rec.by or {}) do
        if crafters[name] then return true end
    end
    return false
end

-- The recipes that count: { recipe, ... } (worked out again only when something has changed)
local counting = { version = -1 }
local function Recipes()
    if counting.version == ns.version then return counting.list end
    local crafters, list = ns.Crafters(), {}
    for _, rec in pairs(ns.DB().recipes) do
        if Counts(rec, crafters) then list[#list + 1] = rec end
    end
    counting.version, counting.list = ns.version, list
    return list
end

-- (Crates.lua prices crate bundles the same way)
ns.UnitCost = UnitCost

-- One of an item made by the crafters' recipes, at its materials' cheapest now: cost each, and the recipe; nil when
-- no crafter's recipe makes it or a material has no price yet (Crates.lua: bars from ore, bolts from cloth)
function ns.CraftCost(id)
    local best, bestRec
    for _, rec in ipairs(Recipes()) do
        if rec.out == id and (rec.n or 0) > 0 then
            local cost = 0
            for i = 1, #rec.r, 2 do
                local each = UnitCost(rec.r[i])
                if not each then
                    cost = nil
                    break
                end
                cost = cost + each * rec.r[i + 1]
            end
            if cost and (not best or cost / rec.n < best) then best, bestRec = cost / rec.n, rec end
        end
    end
    return best, bestRec
end

-- A crafter's recipe that makes it, priced or not (Plan.lua: made when it isn't for sale), or nil
function ns.RecipeFor(id)
    for _, rec in ipairs(Recipes()) do
        if rec.out == id then return rec end
    end
end

-- What the crafters' recipes make: { [itemID] = true } (Prices.lua marks them "you craft it")
function ns.Crafted()
    local made = {}
    for _, rec in ipairs(Recipes()) do made[rec.out] = true end
    return made
end

-- Who knows it, for the list ("Mia, Jon")
local function Who(rec)
    local names = {}
    for name in pairs(rec.by or {}) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ", ")
end

-- { { recipe, cost, value, via ("vendor" or "auction"), gain } }, biggest gain first; and how many were left out
-- because a material has no price yet
function ns.CraftHints()
    local list, unpriced = {}, 0
    for _, rec in ipairs(Recipes()) do
        local cost, known = 0, true
        for i = 1, #rec.r, 2 do
            local each = UnitCost(rec.r[i])
            if not each then
                known = false
                break
            end
            cost = cost + each * rec.r[i + 1]
        end
        if not known then
            unpriced = unpriced + 1
        else
            local vendorValue = (ns.SellPrice(rec.out) or 0) * rec.n
            local usual = ns.Usual(rec.out)
            local ahValue = usual and usual * ns.CUT * rec.n or 0
            local value, via = vendorValue, "vendor"
            if ahValue > vendorValue then value, via = ahValue, "auction" end
            if value - cost > 0 then
                list[#list + 1] = { recipe = rec, cost = cost, value = value, via = via, gain = value - cost }
            end
        end
    end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    return list, unpriced
end

local function Materials(rec)
    local parts = {}
    for i = 1, #rec.r, 2 do
        parts[#parts + 1] = rec.r[i + 1] .. " " .. ns.ItemName(rec.r[i])
    end
    return table.concat(parts, ", ")
end

local function Describe(e)
    local rec = e.recipe
    return ns.ItemName(rec.out) .. (rec.n ~= 1 and (" x" .. rec.n) or "") .. " from " .. Materials(rec),
        "+" .. ns.Money(e.gain) .. " (" .. e.via .. ")"
end

-- For the window: { { left, right } or { header } } (worked out again only when something has changed)
local cache = { version = -1 }
function ns.CraftRows()
    if cache.version == ns.version then return cache.rows end
    local rows = {}
    cache.version, cache.rows = ns.version, rows
    if next(ns.Crafters()) == nil then
        rows[1] = { "No character crafts yet: give one the Crafting role (Quiet Auctions' settings page, on that" }
        rows[2] = { "character), then open its profession windows." }
        return rows
    end
    if #Recipes() == 0 then
        rows[1] = { "No recipes noted yet: open a profession window (the one Smelting is in, say) on a character" }
        rows[2] = { "with the Crafting role." }
        return rows
    end
    local list, unpriced = ns.CraftHints()
    rows[#rows + 1] = { header = "Recipes that pay at today's prices (" .. #list .. ")" }
    for i = 1, math.min(#list, 60) do
        local left, right = Describe(list[i])
        local rec = list[i].recipe
        local who = Who(rec)
        local out, n = rec.out, math.max(1, math.floor((rec.n or 1) + 0.5))
        rows[#rows + 1] = { left, right, id = out, actions = { { "Plan", function() ns.PlanAdd(out, n) end } },
            sub = (rec.prof or "") .. (who ~= "" and (", " .. who) or "")
            .. ": materials " .. ns.Money(list[i].cost) .. ", worth " .. ns.Money(list[i].value) }
    end
    if #list == 0 then rows[#rows + 1] = { "None pays at today's prices." } end
    if unpriced > 0 then
        rows[#rows + 1] = { unpriced .. " recipes left out: a material has no price yet (scan, or visit the vendor "
            .. "that sells it)." }
    end
    return rows
end

-- /qah craft
function ns.PrintCrafting()
    if #Recipes() == 0 then
        ns.Print("no recipes noted yet: open a profession window on a character with the Crafting role (its role is "
            .. "on the settings page, /qah settings).")
        return
    end
    local list, unpriced = ns.CraftHints()
    ns.Print("recipes that pay at today's prices:")
    for i = 1, math.min(#list, SHOW) do
        local left, right = Describe(list[i])
        print("  " .. left .. ":  " .. right)
    end
    if #list == 0 then print("  none.") end
    if unpriced > 0 then print("  (" .. unpriced .. " left out: a material has no price yet)") end
end

local queued = false
ns.Listen("crafting", { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }, function()
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        NoteRecipes()
    end)
end)
