-- Quiet Fishing: one button for fishing. A press takes out your fishing pole (the one you used last, else the first
-- in your bags); the next press casts Fishing. Leave it a few seconds (8 by default, /qfish delay) with no line in the
-- water and what it took the place of goes back on: the weapon in your main hand, and your off hand's (a shield, a
-- second weapon, a held item), the very items you had on.
--
-- What WoW Forever allows:
--  * casting and equipping need a press: the button is a character macro of ours, "Quiet Fishing", on your bar or
--    crossbar. It's made only when you ask (its settings page, /qfish macro, or a Fish press set on Improved
--    Forever's Bindings tab), never by itself: a character that doesn't fish never gets one. Once it's there, its
--    lines (/equip, /cast) are rewritten out of combat whenever what it should do changes. (A secure button of ours
--    clicked by a macro didn't work: the click came on an edge the game's template let go.)
--  * its first line clicks a plain button of ours, so the addon knows of the press (and what the hands held before).
--  * equipping from addon code is blocked in a fight: the swap back waits for the fight to end. In a fight, a press
--    of the macro puts your weapons back at once (a macro may swap weapons in combat).
--  * values can be secret in combat: anything read then goes through issecretvalue first.
local _, ns = ...

local MACRO = "Quiet Fishing"
local PRESS = "QuietFishingPress"
local ICON = "Trade_Fishing"
local DEFAULT_DELAY = 8
local MAIN_HAND, OFF_HAND = 16, 17
local WEAPON, FISHING_POLE = 2, 20 -- item class and subclass
local FISHING_SPELLS = { 7620, 7731, 7732, 18248 } -- Fishing, every rank (any one gives the name)
local MACRO_LENGTH = 255

ns.MACRO = MACRO
ns.HOW = 'Press "' .. MACRO .. '" by water: once for the pole, again to cast, again when it splashes to reel in.'

-- An answer to a command, in chat
local function Print(msg)
    QuietKit.Print("Quiet Fishing", msg)
end
ns.Print = Print

-- Anything the player didn't ask for: a small note that fades
local function Toast(msg)
    QuietKit.Toast(msg, "Interface\\Icons\\" .. ICON)
end
ns.Toast = Toast

-- nil for a value the game keeps secret (in combat)
local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

-- ---------- settings ----------
-- QuietFishingDB: { delay, padBind, button, buttonPos, catch, softWas, sound, soundWas, loot }
-- QuietFishingCharDB: { rod, gear = { mh, oh (item IDs), mhLink, ohLink (the very items) } }
local function DB()
    QuietFishingDB = QuietFishingDB or {}
    return QuietFishingDB
end

local function Char()
    QuietFishingCharDB = QuietFishingCharDB or {}
    return QuietFishingCharDB
end
ns.DB, ns.Char = DB, Char

function ns.Delay()
    return DB().delay or DEFAULT_DELAY
end

function ns.SetDelay(seconds)
    DB().delay = math.max(3, math.min(60, math.floor(seconds + 0.5)))
end

-- ---------- items ----------
local InfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local NameOf = (C_Item and C_Item.GetItemNameByID) or GetItemInfo
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local SlotItem = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local SlotLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
local PickupSlot = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

local function IsPole(id)
    if not id then return false end
    local _, _, _, _, _, class, subclass = InfoInstant(id)
    return class == WEAPON and subclass == FISHING_POLE
end

local function Equipped(slot)
    return Plain(GetInventoryItemID("player", slot))
end

-- The fishing pole in hand now
function ns.PoleOut()
    return IsPole(Equipped(MAIN_HAND))
end

local function Have(id)
    return id ~= nil and (ItemCount(id) or 0) > 0
end

-- Where an item is in the bags (bag, slot): the very one (its link) if it's there, else the first of its kind
local function InBags(id, link)
    if not id then return nil end
    local kindBag, kindSlot
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, NumSlots(bag) or 0 do
            if SlotItem(bag, slot) == id then
                if not link or SlotLink(bag, slot) == link then return bag, slot end
                kindBag, kindSlot = kindBag or bag, kindSlot or slot
            end
        end
    end
    return kindBag, kindSlot
end

-- What a macro line names an item by: its name (/equip takes names), else its item string
local function MacroName(id)
    return NameOf(id) or ("item:" .. id)
end

-- The pole to take out: the one in hand, the last one used, else the first in the bags
local function FindRod()
    local mh = Equipped(MAIN_HAND)
    if IsPole(mh) then return mh end
    local last = Char().rod
    if Have(last) then return last end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, NumSlots(bag) or 0 do
            local id = SlotItem(bag, slot)
            if IsPole(id) then return id end
        end
    end
end

local function FishingName()
    for _, id in ipairs(FISHING_SPELLS) do
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            name = info and info.name
        elseif GetSpellInfo then
            name = GetSpellInfo(id)
        end
        if name then return name end
    end
    return "Fishing"
end
ns.FishingName = FishingName

-- ---------- the macro ----------
local rodInHand = false
local pending = false

-- What a press does. Pole in hand: cast (in a fight: weapons back on). Else: take the pole out.
-- (Fishing can't be cast in the same press: the pole isn't in hand until the server says so.)
local function Body(byID)
    local function name(id) return byID and ("item:" .. id) or MacroName(id) end
    local lines = { "/click " .. PRESS }
    local mh = Equipped(MAIN_HAND)
    if IsPole(mh) then
        local gear = Char().gear or {}
        if gear.mh then lines[#lines + 1] = "/equipslot [combat] " .. MAIN_HAND .. " " .. name(gear.mh) end
        if gear.oh then lines[#lines + 1] = "/equipslot [combat] " .. OFF_HAND .. " " .. name(gear.oh) end
        lines[#lines + 1] = "/cast [nocombat] " .. FishingName()
    else
        local rod = FindRod()
        if rod then
            lines[#lines + 1] = "/equip [nocombat] " .. name(rod)
        else
            lines[#lines + 1] = "/cast [nocombat] " .. FishingName()
        end
    end
    local body = table.concat(lines, "\n")
    if #body > MACRO_LENGTH and not byID then return Body(true) end
    return body
end

-- What a press should do now (the pole in hand is remembered as the one to take out next time)
local function CurrentBody()
    local mh = Equipped(MAIN_HAND)
    rodInHand = IsPole(mh)
    if rodInHand then Char().rod = mh end
    return Body()
end

-- The macro as QuietKit makes it, a character macro: the settings page's macro item, /qfish macro (QuietKit.lua)
ns.MacroSpec = { name = MACRO, icon = ICON, body = CurrentBody }

-- Rewrites the macro's lines (out of combat), if it's there. Never makes it.
local function Refresh()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local body = CurrentBody()
    if GetMacroIndexByName(MACRO) == 0 then return false end
    local _, icon, current = GetMacroInfo(MACRO)
    if current ~= body then EditMacro(MACRO, MACRO, icon or ICON, body) end
    return true
end

-- Makes the macro if it isn't there (out of combat): true, or false and why
function ns.MakeMacro()
    return QuietKit.MacroReady(ns.MacroSpec)
end

-- ---------- the swap back ----------
-- Armed by a press (the watcher shown): once the pole has been idle for the delay (no cast, no line out, no loot
-- window), the main hand's item goes back on, then the off hand's. A fight starting puts the main hand's on at once
-- (its event comes just before the lockdown, as OneCast does it); the off hand's follows when it's over.
local watcher = CreateFrame("Frame")
watcher:Hide()
local pressedAt, idleSince, returning = 0, 0, nil
local retried = false
local offTry = 0
local looting = false
local warned = 0

-- What keeps the pole out a while longer, or nil
local function Busy()
    -- (a loot window that went without its LOOT_CLOSED doesn't hold it forever)
    if looting and GetNumLootItems and (Plain(GetNumLootItems()) or 0) == 0 then looting = false end
    if looting then return "looting" end
    if UnitChannelInfo and Plain(UnitChannelInfo("player")) then return "fishing" end
    if UnitCastingInfo and Plain(UnitCastingInfo("player")) then return "casting" end
    return nil
end

local function Stop()
    returning, retried = nil, false
    watcher:Hide()
end

-- Puts an item from the bags on a slot: the very one (its link) where it's there, else one of its kind. Taken from
-- its bag slot, so two of the same (a pair of swords) never swap the one in the other hand; by name only when the
-- cursor is busy. True if it tried. A failure is said in a note (once a session).
local EquipByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local equipFailed = false
local function Equip(id, slot, link)
    if not id then return false end
    if Equipped(slot) == id and (not link or Plain(GetInventoryItemLink("player", slot)) == link) then return false end
    local bag, bagSlot = InBags(id, link)
    if not bag then return false end
    local ok, err = false, "this client has no EquipItemByName"
    if PickupSlot and EquipCursorItem and not GetCursorInfo() then
        ok, err = pcall(function()
            PickupSlot(bag, bagSlot)
            EquipCursorItem(slot)
        end)
        if CursorHasItem and CursorHasItem() then ClearCursor() end -- (it didn't go: back to its bag)
    elseif EquipByName then
        ok, err = pcall(EquipByName, id, slot)
    end
    if not ok and not equipFailed then
        equipFailed = true
        Toast("Couldn't put " .. MacroName(id) .. " back on: " .. tostring(err))
    end
    return ok
end

local function Tick()
    if InCombatLockdown() then return end -- (carries on once the fight is over)
    local now = GetTime()
    local gear = Char().gear or {}
    local mh = Equipped(MAIN_HAND)
    if returning then
        -- The main hand's on: now the off hand's. (Still the pole after a while: once more, as the fight may have
        -- stopped it, then leave it.)
        if IsPole(mh) and gear.mh then
            if now - returning > 3 then
                if not retried and Equip(gear.mh, MAIN_HAND, gear.mhLink) then
                    retried, returning = true, now
                else
                    Stop()
                end
            end
            return
        end
        -- Then the off hand's: tried each second until it's on (the main hand's swap may still hold the items),
        -- for a few seconds
        if gear.oh and Equipped(OFF_HAND) ~= gear.oh and InBags(gear.oh, gear.ohLink) and now - returning < 6 then
            if now - offTry >= 1 then
                offTry = now
                Equip(gear.oh, OFF_HAND, gear.ohLink)
            end
            return
        end
        Stop()
        return
    end
    if not IsPole(mh) then
        -- The pole never came out, or was put away by hand
        if now - pressedAt > 3 then Stop() end
        return
    end
    if Busy() then
        idleSince = now
        return
    end
    if now - idleSince < ns.Delay() then return end
    -- The main hand's, then the off hand's (above). Nothing in the main hand before: the off hand's alone (if
    -- any) puts the pole away.
    Equip(gear.mh, MAIN_HAND, gear.mhLink)
    returning, offTry = now, 0
end

local sinceTick = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick < 0.25 then return end
    sinceTick = 0
    Tick()
end)

-- A press: the macro's first line clicks this, before its /equip runs. Remember what the hands hold before the
-- pole, arm the swap back. (A /click sends one click, on either edge: both are taken.)
local press = CreateFrame("Button", PRESS, UIParent)
press:RegisterForClicks("AnyDown", "AnyUp")
press:SetScript("OnClick", function()
    if InCombatLockdown() then return end -- (in a fight the macro itself puts the weapons back)
    local now = GetTime()
    local mh = Equipped(MAIN_HAND)
    if not IsPole(mh) then
        if not FindRod() then
            Toast("No fishing pole in your bags.")
            return
        end
        -- (not again while the pole is on its way: the hands may be half empty. An empty off hand beside the same
        -- main hand as last time keeps the off hand's remembered: a swap back may have missed it.)
        if not (watcher:IsShown() and now - pressedAt < 2) then
            local old = Char().gear or {}
            local gear = { mh = mh, mhLink = Plain(GetInventoryItemLink("player", MAIN_HAND)), oh = Equipped(OFF_HAND),
                ohLink = Plain(GetInventoryItemLink("player", OFF_HAND)) }
            if not gear.oh and mh and mh == old.mh and old.oh and InBags(old.oh, old.ohLink) then
                gear.oh, gear.ohLink = old.oh, old.ohLink
            end
            Char().gear = gear
        end
    end
    pressedAt, idleSince, returning = now, now, nil
    watcher:Show()
end)

-- Puts the weapons back now (/qfish back)
local function BackNow()
    if InCombatLockdown() then
        Print("in a fight: press your fishing button to take your weapons back.")
        return
    end
    if not IsPole(Equipped(MAIN_HAND)) then
        Print("your fishing pole isn't out.")
        return
    end
    pressedAt, idleSince, returning = GetTime(), -math.huge, nil
    watcher:Show()
    Tick()
end

-- ---------- events ----------
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOOT_OPENED", "LOOT_CLOSED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- (only if it's there: it's made when the player asks, and deleting it sticks. The marks the old
        -- first-login macro left are cleared.)
        Char().made, Char().placed = nil, nil
        Refresh()
    elseif event == "LOOT_OPENED" then
        looting = true
    elseif event == "LOOT_CLOSED" then
        looting = false
        idleSince = GetTime()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- A fight with the pole out: the weapon now, the last moment it may be equipped. No weapon to take back:
        -- say how (once a fight).
        if watcher:IsShown() and rodInHand then
            local gear = Char().gear or {}
            if Equip(gear.mh, MAIN_HAND, gear.mhLink) then
                returning, retried = GetTime(), false
            elseif GetTime() - warned > 30 then
                warned = GetTime()
                Toast("Press your fishing button to take your weapons back.")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Refresh() end
    else
        Refresh()
    end
end)

-- ---------- /qfish ----------
local function Status()
    local rod = FindRod()
    local gear = Char().gear or {}
    local back = {}
    if gear.mh then back[#back + 1] = MacroName(gear.mh) end
    if gear.oh then back[#back + 1] = MacroName(gear.oh) end
    print("  pole: " .. (rod and MacroName(rod) or "none in your bags")
        .. ".  Back after " .. ns.Delay() .. " s: " .. (#back > 0 and table.concat(back, ", ") or "nothing yet") .. ".")
    if watcher:IsShown() then
        local busy = Busy()
        local left = math.max(0, math.ceil(ns.Delay() - (GetTime() - idleSince)))
        print("  swap back: " .. (InCombatLockdown() and "after the fight" or busy and ("waiting, you're " .. busy)
            or returning and "under way" or ("in " .. left .. " s")) .. ".")
    else
        print("  swap back: not waiting (press the macro to start it).")
    end
    if ns.CatchStatus then print("  reel in: " .. ns.CatchStatus() .. ".") end
    if ns.CatchDetail then print("  reel in, details: " .. ns.CatchDetail()) end
    if GetMacroIndexByName(MACRO) > 0 then
        local _, _, body = GetMacroInfo(MACRO)
        print("  the next press runs: " .. (body or ""):gsub("^/click [^\n]*\n", ""):gsub("\n", ";  "))
    else
        print('  no "' .. MACRO .. '" macro yet: /qfish macro makes it and puts it on your bar.')
    end
end

SLASH_QUIETFISHING1 = "/qfish"
SlashCmdList.QUIETFISHING = function(msg)
    msg = strtrim((msg or ""):lower())
    local seconds = tonumber(msg:match("^delay%s+(%d+%.?%d*)$"))
    if seconds then
        ns.SetDelay(seconds)
        Print("weapons come back " .. ns.Delay() .. " s after your last cast.")
    elseif msg == "macro" then
        -- (QuietKit says in a note where it went, or why it couldn't)
        if InCombatLockdown() then
            Print("after the fight, please.")
        elseif QuietKit.PlaceMacro(ns.MacroSpec) or GetMacroIndexByName(MACRO) > 0 then
            Print(ns.HOW)
        end
    elseif msg == "back" then
        BackNow()
    elseif msg:match("^button") and ns.ButtonCommand then
        ns.ButtonCommand(strtrim(msg:sub(7)))
    elseif msg:match("^catch") and ns.CatchCommand then
        ns.CatchCommand(strtrim(msg:sub(6)))
    elseif msg:match("^sound") and ns.SoundCommand then
        ns.SoundCommand(strtrim(msg:sub(6)))
    elseif msg:match("^loot") and ns.LootCommand then
        ns.LootCommand(strtrim(msg:sub(5)))
    elseif (msg == "options" or msg == "settings") and ns.OpenOptions then
        ns.OpenOptions()
    elseif msg == "help" then
        Print("every command (the settings are also in /qfish options):")
        print("  /qfish macro  makes the fishing macro (if it isn't there) and puts it on your bar")
        print("  /qfish delay 8  seconds before your weapons come back (3 to 60)")
        print("  /qfish back  puts your weapons back now")
        print("  /qfish button auto | on | off  the fishing button on screen, for the mouse (auto: while your")
        print("    pole is out and no gamepad is connected). Shift-drag it to move it.")
        print("  /qfish catch on | off  the key you fish with also reels the line in (on)")
        print("  /qfish sound on | off  a louder splash while your line is out: half as loud again, up to 80% (on)")
        print("  /qfish loot on | off  catches looted at once (on)")
        print("  /qfish options  the settings (also in Options, AddOns, Quiet)")
    elseif GetMacroIndexByName(MACRO) == 0 then
        Print('first the fishing macro: /qfish macro puts "' .. MACRO .. '" on your bar (or drag it from /qfish '
            .. "options). Then press it by water: once for the pole, again to cast, again when it splashes to reel in.")
        print("  Every command: /qfish help.")
    else
        Print('press "' .. MACRO .. '" on your bar by water: once for the pole, again to cast, again when it '
            .. "splashes to reel in.")
        print("  Settings: /qfish options.  Every command: /qfish help.")
        Status()
    end
end
