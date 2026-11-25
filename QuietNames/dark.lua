local addonName, privateTable = ...

-- No names outside a fight (this was No Names): /dark, its key or its macro turns off every name and nameplate in the
-- world while you're out of combat. A fight brings them all back as you had them, and they go again when it ends.
-- /dark again, and everything stays as it was. In a dungeon or raid the enemies' names and nameplates can stay, so
-- you see the next pack before you pull it. Nameplates can't be changed during a fight, only as it starts (the game
-- still allows it at that moment) and after it.
-- While it's on, your own settings are kept in QuietNamesDB.saved and put back as the game closes (then hidden again
-- as it starts), so the game's settings file always holds your names: turning Quiet Names off, or removing it, leaves
-- them as you had them.

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
local GetCVarDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
local issecretvalue = issecretvalue or function() return false end

local ICON = "Interface\\Icons\\Ability_Stealth"
privateTable.DARK_ICON = ICON

-- Settings the game doesn't have are skipped ("Hostle" is the game's own spelling)
local CVARS = {
    "UnitNameOwn", "UnitNameNPC", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
    "UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName",
    "UnitNameFriendlyTotemName", "UnitNameEnemyTotemName", "UnitNamePlayerGuild", "UnitNamePlayerPVPTitle",
    "UnitNameNonCombatCreatureName", "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
    "nameplateShowFriends", "nameplateShowEnemies", "nameplateShowAll",
    -- (Forever's friendly plates: the friendly players' names are drawn on these, so they go too)
    "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs",
}

-- What stays as you had it in a dungeon or raid, by the choice on the settings page ("all": everything stays)
local KEEP = {
    hide = {},
    enemies = {
        nameplateShowEnemies = true, nameplateShowAll = true,
        UnitNameHostleNPC = true, UnitNameEnemyPlayerName = true, UnitNameEnemyPetName = true,
    },
}

privateTable.INSTANCE_CHOICES = {
    { value = "enemies", name = "Keep enemies" },
    { value = "all", name = "Keep every name" },
    { value = "hide", name = "Hide them too" },
}

local function DB()
    return QuietNamesDB
end

local function Get(cvar)
    local ok, value = pcall(GetCVar, cvar)
    if not ok or issecretvalue(value) then return nil end
    return value
end

local function Set(cvar, value)
    pcall(SetCVar, cvar, value)
end

-- Your settings as they are now
local function Capture()
    local saved = {}
    for _, cvar in ipairs(CVARS) do
        local value = Get(cvar)
        if value ~= nil then saved[cvar] = value end
    end
    return saved
end

function privateTable.InstanceChoice()
    return DB().instances or "enemies"
end

-- What to leave as you had it here: nil (nothing), a set, or true (everything)
local function Kept()
    local inside, kind = IsInInstance()
    if issecretvalue(inside) or not inside or kind == "none" then return nil end
    local choice = privateTable.InstanceChoice()
    if choice == "all" then return true end
    return KEEP[choice]
end

-- Names off (but for what stays in a dungeon or raid)
local function Hide()
    local saved = DB().saved
    if InCombatLockdown() or not saved then return end
    local keep = Kept()
    for cvar, value in pairs(saved) do
        Set(cvar, (keep == true or (keep and keep[cvar])) and value or "0")
    end
end

-- Back to what you had. Nameplates only while the game allows it: changing them in a fight is Blizzard's alone, and
-- trying gets the addon blocked, so if the fight has already locked them they stay off until it ends.
local function Show()
    local locked = InCombatLockdown()
    for cvar, value in pairs(DB().saved or {}) do
        if not (locked and cvar:find("^nameplate")) then Set(cvar, value) end
    end
end

-- As the game starts, your settings are back (put back as it closed): take them as they are now. A "0" keeps the one
-- kept, in case the game didn't close properly and left them off.
local function Recapture()
    local saved = DB().saved
    for cvar, value in pairs(Capture()) do
        if value ~= "0" or saved[cvar] == nil then saved[cvar] = value end
    end
end

--- Names off outside a fight (true), or on as you had them (false). Says how it went in a note.
function privateTable.SetDark(on)
    local db = DB()
    if (on and true or false) == (db.dark and true or false) then return end
    if on then
        -- (still held from a /dark off in a fight: those are yours, the settings may not be yet)
        if not db.saved then db.saved = Capture() end
        db.dark = true
        if InCombatLockdown() then
            QuietKit.Toast("Names go when this fight ends.", ICON)
        else
            Hide()
            QuietKit.Toast("No names outside a fight. /dark brings them back.", ICON)
        end
    else
        db.dark = false
        Show() -- (in a fight: the names now, the nameplates when it ends)
        if not InCombatLockdown() then db.saved = nil end
        QuietKit.Toast("Names stay on.", ICON)
    end
end

function privateTable.ToggleDark()
    privateTable.SetDark(not DB().dark)
end

function privateTable.DarkOn()
    return DB() ~= nil and DB().dark and true or false
end

function privateTable.SetInstanceChoice(value)
    DB().instances = value
    if DB().dark then Hide() end
end

--- Every name and nameplate setting back to the game's own (for names something else left off). /dark goes off.
--- The number put back, or nil in a fight.
function privateTable.GameNames()
    if InCombatLockdown() then return nil end
    local db = DB()
    db.dark, db.saved = false, nil
    db.plates, db.platesBefore = false, nil
    local count = 0
    for _, cvar in ipairs(CVARS) do
        local ok, value = pcall(GetCVarDefault, cvar)
        if ok and value ~= nil and not issecretvalue(value) then
            Set(cvar, value)
            count = count + 1
        end
    end
    return count
end

-- Nameplates instead of names (QuietNamesDB.plates): enemies get a nameplate whether or not you're fighting them, out
-- to 60 yards, and their bare names, which the game draws only where there's no plate, go. Without it the game shows
-- plates for what you fight and names for the rest, and plates stop at about 40 yards with names beyond.
-- Turning it off puts back what you had (QuietNamesDB.platesBefore). While /dark has the names hidden, the changes
-- go into the settings it keeps, so a fight brings back plates, not names.
local PLATES = {
    nameplateShowAll = "1",
    nameplateShowEnemies = "1",
    nameplateMaxDistance = "60", -- (each character has its own: set again at each login)
    UnitNameHostleNPC = "0",
    UnitNameEnemyPlayerName = "0",
}

-- Into the settings /dark keeps while it has them, or the game's own
local function Write(cvar, value)
    local saved = DB().saved
    if saved and saved[cvar] ~= nil then
        saved[cvar] = value
    else
        Set(cvar, value)
    end
end

local function ApplyPlates(values)
    for cvar, value in pairs(values) do
        Write(cvar, value)
    end
    if DB().dark then Hide() end
end

function privateTable.PlatesOn()
    return DB() ~= nil and DB().plates and true or false
end

--- Nameplates instead of names (true), or back as you had them (false). Not in a fight: false then.
function privateTable.SetPlates(on)
    local db = DB()
    if InCombatLockdown() then return false end
    if (on and true or false) == (db.plates and true or false) then return true end
    if on then
        local before = {}
        for cvar in pairs(PLATES) do
            before[cvar] = (db.saved and db.saved[cvar]) or Get(cvar)
        end
        db.platesBefore = before
        db.plates = true
        ApplyPlates(PLATES)
    else
        db.plates = false
        ApplyPlates(db.platesBefore or {})
        db.platesBefore = nil
    end
    return true
end

-- The key in Key Bindings, under Quiet Names
BINDING_HEADER_QUIETNAMES = "Quiet Names"
BINDING_NAME_QUIETNAMES_DARK = "Hide or show all names outside a fight"
function QuietNames_ToggleDark()
    privateTable.ToggleDark()
end

-- /dark (and /nonames, its old name)
SLASH_QUIETNAMESDARK1 = "/dark"
SLASH_QUIETNAMESDARK2 = "/nonames"
SlashCmdList.QUIETNAMESDARK = function() privateTable.ToggleDark() end

-- Names left off with nothing to bring them back (another addon, removed while it had them off): said once
local function CheckLeftOff()
    local db = DB()
    if db.dark or db.saved or db.toldLeftOff then return end
    local found = 0
    for _, cvar in ipairs(CVARS) do
        local value = Get(cvar)
        if value ~= nil and value ~= "0" then return end
        if value ~= nil then found = found + 1 end
    end
    if found == 0 then return end
    privateTable.Note("Every name and nameplate is off. /qnames names brings back the game's own.", ICON,
        "toldLeftOff")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local started = false

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED") -- the fight starts: names on (still allowed in this moment)
events:RegisterEvent("PLAYER_REGEN_ENABLED") -- the fight is over: names off
events:RegisterEvent("PLAYER_ENTERING_WORLD") -- logging in, a /reload, or into or out of a dungeon
events:RegisterEvent("PLAYER_LOGOUT") -- the game closing (or a /reload): your settings back
events:SetScript("OnEvent", function(_, event)
    local db = DB()
    if not db then return end
    if event == "PLAYER_LOGOUT" then
        if db.saved then
            Show()
            -- (kept while it's on, in case the game doesn't close properly next time)
            if not db.dark and not InCombatLockdown() then db.saved = nil end
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if db.dark then Show() end
        return
    end
    if InCombatLockdown() then return end
    if event == "PLAYER_ENTERING_WORLD" and not started then
        started = true
        if db.dark and db.saved then Recapture() end
        CheckLeftOff()
        if db.plates then ApplyPlates(PLATES) end
    end
    if db.dark then
        Hide()
    elseif db.saved then
        -- (a /dark off from a fight, finished)
        Show()
        db.saved = nil
    end
end)
