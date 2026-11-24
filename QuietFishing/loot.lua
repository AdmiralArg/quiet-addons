local _, ns = ...

-- Catches looted at once: when the loot window opens on a catch (IsFishingLoot), every slot is taken, as the
-- game's own auto loot would (which, when on, has done it already). Other loot is left alone. A slot that can't be
-- taken (full bags, an item that asks first) stays in the window. /qfish loot on | off.
local function Enabled()
    return ns.DB().loot ~= false
end

function ns.LootOn()
    return Enabled()
end

function ns.SetLoot(on)
    ns.DB().loot = (not on) and false or nil
end

function ns.LootCommand(arg)
    if arg == "on" or arg == "off" then
        ns.SetLoot(arg == "on")
    elseif arg ~= "" then
        ns.Print("/qfish loot on or off.")
        return
    end
    ns.Print("catches are " .. (Enabled() and "looted at once." or "left in the loot window (loot off)."))
end

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local events = CreateFrame("Frame")
events:RegisterEvent("LOOT_OPENED")
events:SetScript("OnEvent", function(_, _, autoLoot)
    if Plain(autoLoot) or not Enabled() then return end
    if not (IsFishingLoot and Plain(IsFishingLoot())) then return end
    for slot = (Plain(GetNumLootItems()) or 0), 1, -1 do
        pcall(LootSlot, slot)
    end
end)
