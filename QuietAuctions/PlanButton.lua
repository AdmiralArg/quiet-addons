-- "Plan this" under the game's profession window: puts what the chosen recipe makes into the plan (Plan.lua), as
-- many as the window's own "how many" box says (one craft when it has none). Shown on a character with a role.
-- The chosen recipe: from the window's own "recipe selected" event, or read off the window (the newer Professions
-- window, or the older trade skill window, whichever this client has).
local _, ns = ...

local UI = QuietKit.UI

local button
local selected -- (the recipe chosen last, from the window's event)

local function Window()
    return ProfessionsFrame or TradeSkillFrame
end

local function Field(t, ...)
    for _, key in ipairs({ ... }) do
        if type(t) ~= "table" then return nil end
        t = t[key]
    end
    return t
end

-- The recipe the window shows now: its ID, or nil
local function SelectedRecipe()
    local form = Field(ProfessionsFrame, "CraftingPage", "SchematicForm")
    if form then
        if type(form.GetRecipeInfo) == "function" then
            local ok, info = pcall(form.GetRecipeInfo, form)
            if ok and type(info) == "table" and info.recipeID then return info.recipeID end
        end
        local info = form.currentRecipeInfo
        if type(info) == "table" and info.recipeID then return info.recipeID end
    end
    local list = Field(TradeSkillFrame, "RecipeList")
    if list and type(list.GetSelectedRecipeID) == "function" then
        local ok, id = pcall(list.GetSelectedRecipeID, list)
        if ok and id then return id end
    end
    return Field(TradeSkillFrame, "DetailsFrame", "selectedRecipeID") or selected
end

-- How many crafts the window's "how many" box asks for (1 when there's none)
local function Crafts()
    local box = Field(ProfessionsFrame, "CraftingPage", "CreateMultipleInputBox")
        or Field(TradeSkillFrame, "DetailsFrame", "CreateMultipleInputBox")
    if box and type(box.GetValue) == "function" then
        local ok, n = pcall(box.GetValue, box)
        n = ok and tonumber(n)
        if n and n >= 1 then return math.floor(n) end
    end
    return 1
end

local function PlanIt()
    local rid = SelectedRecipe()
    local ui = C_TradeSkillUI
    if not (rid and ui and ui.GetRecipeSchematic) then
        ns.Say("Choose a recipe in the list first.")
        return
    end
    local ok, s = pcall(ui.GetRecipeSchematic, rid, false)
    local out = ok and type(s) == "table" and s.outputItemID
    if not out or out == 0 then
        ns.Say("That recipe doesn't make an item (an enchant, say): nothing to plan.")
        return
    end
    local each = math.max(1, math.floor(((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2 + 0.5))
    ns.PlanAdd(out, each * Crafts())
    if not ns.RecipeFor(out) then
        ns.Say(ns.ItemName(out) .. " is in the plan. Give this character the Crafting role (the settings page) so the "
            .. "plan makes it from its materials rather than buying it.")
    end
end

local function Build(win)
    local b = UI.Button(win, "Plan this (Quiet Auctions)", PlanIt, 190, true)
    b:SetHeight(26)
    return b
end

-- Under the window's left corner (Quiet Smelt's button sits under its right one)
local function Show()
    local win = Window()
    if not (win and win:IsShown() and ns.Does("any")) then
        if button then button:Hide() end
        return
    end
    button = button or Build(win)
    button:SetParent(win)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 12, -4)
    button:SetFrameLevel(win:GetFrameLevel() + 20)
    button:Show()
end

-- The window's own event when a recipe is chosen (the newer window; the older one is read when pressed)
local listening = false
local function ListenForChoice()
    if listening or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    listening = true
    pcall(EventRegistry.RegisterCallback, EventRegistry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected",
        function(_, info)
            if type(info) == "table" and info.recipeID then selected = info.recipeID end
        end, ns)
end

ns.Listen("any", { "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }, function(_, event)
    if event == "TRADE_SKILL_CLOSE" then
        if button then button:Hide() end
        return
    end
    ListenForChoice()
    -- (the window is made, or shown, as the event comes: placed a moment later)
    C_Timer.After(0.1, Show)
end)
