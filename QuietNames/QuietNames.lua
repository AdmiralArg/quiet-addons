local addonName, privateTable = ...

-- The names over characters' heads are drawn by the game itself, not by the interface: an addon can't color, fade
-- or size them, but it chooses their font. The game reads UNIT_NAME_FONT once, the first time the world loads after
-- it starts (it keeps it in Fonts\override_*.slug), so a new choice shows after the game is started again; a /reload
-- doesn't change it.
-- Up to 0.2 the addon carried its own lighter fonts, scaled down inside the file (the game draws these names at its
-- own size, so a font drawn smaller was the only way to smaller names). They were Microsoft's and can't be shared, so
-- they're gone: the choice is now the game's own fonts and any font your other addons add (LibSharedMedia). Nothing
-- changes until you pick one.

local TITLE = "Quiet Names"
privateTable.TITLE = TITLE
privateTable.ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- The game's own name font, as the interface set it before this file ran
local GAME_NAME_FONT = UNIT_NAME_FONT_ROMAN or UNIT_NAME_FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- The game's fonts a client may carry. One this client doesn't have is left out (Exists, below).
local GAME_CHOICES = {
    { key = "friz", label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", label = "Skurri", path = "Fonts\\SKURRI.TTF" },
    { key = "nimrod", label = "Nimrod", path = "Fonts\\NIM_____.ttf" },
    { key = "2002", label = "2002", path = "Fonts\\2002.TTF" },
    { key = "2002b", label = "2002 Bold", path = "Fonts\\2002B.TTF" },
}

-- The fonts 0.2 carried (and the name it gave the game's own), to clear from an older saved choice
local OLD_KEYS = {
    palatino = true, bookantiqua = true, georgia = true, corbel = true, candara = true, calibri = true,
    segoe = true, default = true,
}

local function Print(msg)
    QuietKit.Print(TITLE, msg)
end
privateTable.Print = Print

---------------------------------------------------------------------------
-- The fonts
---------------------------------------------------------------------------
local probe
local known = {}

-- Whether this client can draw with a font file: the game says no (false) when it has no such file
local function Exists(path)
    if not path then return false end
    local key = path:lower()
    if known[key] == nil then
        probe = probe or UIParent:CreateFontString(nil, "ARTWORK")
        local ok, set = pcall(probe.SetFont, probe, path, 12, "")
        known[key] = ok and set ~= false
        if known[key] and C_UIFileAsset and C_UIFileAsset.IsKnownFile then
            local asked, isKnown = pcall(C_UIFileAsset.IsKnownFile, path)
            if asked and isKnown == false then known[key] = false end
        end
    end
    return known[key]
end

local function SharedMedia()
    local stub = LibStub
    if not stub then return nil end
    local ok, lsm = pcall(stub, "LibSharedMedia-3.0", true)
    return ok and lsm or nil
end

--- Every font you can pick, in order: { key, label, path, from = "game" or "addons" }. The game's own first ("game"),
--- then the game's other fonts, then the ones your other addons add, each once.
function privateTable.Fonts()
    local list = { { key = "game", label = "The game's own", path = GAME_NAME_FONT, from = "game" } }
    local seenPath, seenLabel = { [GAME_NAME_FONT:lower()] = true }, {}
    for _, font in ipairs(GAME_CHOICES) do
        seenLabel[font.label:lower()] = true
        if font.path:lower() == GAME_NAME_FONT:lower() then
            list[1].label = "The game's own (" .. font.label .. ")"
        elseif Exists(font.path) and not seenPath[font.path:lower()] then
            seenPath[font.path:lower()] = true
            list[#list + 1] = { key = font.key, label = font.label, path = font.path, from = "game" }
        end
    end
    local lsm = SharedMedia()
    if lsm then
        -- (it lists the game's fonts too, some under a name of its own: "Friz Quadrata TT", "Morpheus"; any it has
        -- that aren't above go with the game's, before the addons')
        local addons = {}
        local ok, names = pcall(lsm.List, lsm, "font")
        for _, name in ipairs(ok and names or {}) do
            local path = lsm:Fetch("font", name, true)
            local label = name:gsub(" TT$", "")
            if type(path) == "string" and not seenPath[path:lower()] and not seenLabel[label:lower()]
                and Exists(path) then
                seenPath[path:lower()] = true
                seenLabel[label:lower()] = true
                local game = path:lower():find("^fonts[\\/]") ~= nil
                local font = { key = "lsm:" .. name, label = label, path = path, from = game and "game" or "addons" }
                if game then list[#list + 1] = font else addons[#addons + 1] = font end
            end
        end
        for _, font in ipairs(addons) do list[#list + 1] = font end
    end
    -- The one picked, though the addon that added it hasn't (yet) this time
    local db = QuietNamesDB
    if db and db.font and db.fontPath then
        for _, font in ipairs(list) do
            if font.key == db.font then return list end
        end
        list[#list + 1] = { key = db.font, label = db.fontLabel or db.font, path = db.fontPath, from = "addons" }
    end
    return list
end

function privateTable.FindFont(key)
    for _, font in ipairs(privateTable.Fonts()) do
        if font.key == key then return font end
    end
end

--- The font names are in now, as picked ("game" for the game's own): the key, then its name
function privateTable.Chosen()
    local db = QuietNamesDB
    if db and db.font then return db.font, db.fontLabel or db.font end
    return "game", privateTable.Fonts()[1].label
end

--- The file to preview a font key with
function privateTable.PathOf(key)
    local db = QuietNamesDB
    if key == "game" then return GAME_NAME_FONT end
    if db and key == db.font and db.fontPath then return db.fontPath end
    local font = privateTable.FindFont(key)
    return font and font.path or GAME_NAME_FONT
end

-- The window (window.lua) redraws on every change, wherever it came from
local function Changed()
    if privateTable.RefreshWindow then privateTable.RefreshWindow() end
end

--- Picks the font for names over heads. It's kept with its file, so the next start doesn't need the addon that
--- added it to have loaded first.
function privateTable.SetFont(key)
    local font = privateTable.FindFont(key)
    if not font then return false end
    local db = QuietNamesDB
    if font.key == "game" then
        db.font, db.fontPath, db.fontLabel = nil, nil, nil
    else
        db.font, db.fontPath, db.fontLabel = font.key, font.path, font.label
    end
    privateTable.changed = font.key ~= privateTable.inUse
    Changed()
    if privateTable.changed then
        QuietKit.Toast("Names in " .. font.label .. " after you restart the game.", privateTable.ICON)
    else
        QuietKit.Toast("Names stay in " .. font.label .. ".", privateTable.ICON)
    end
    return true
end

-- Points the game's name font at the chosen file (Latin letters only, so the Cyrillic and Asian name fonts are left
-- alone). Nothing is touched while the choice is the game's own.
local function ApplyFont()
    local db = QuietNamesDB
    privateTable.inUse = "game"
    if not db.font then return end
    if not db.fontPath or not Exists(db.fontPath) then
        -- (the addon that added it is gone)
        privateTable.lostFont = db.fontLabel or db.font
        db.font, db.fontPath, db.fontLabel = nil, nil, nil
        return
    end
    UNIT_NAME_FONT = db.fontPath
    UNIT_NAME_FONT_ROMAN = db.fontPath
    privateTable.inUse = db.font
end

---------------------------------------------------------------------------
-- Notes the player didn't ask for: a little after the world is in, and after the welcome window if it's up
---------------------------------------------------------------------------
local notes = {}
local waitingForWelcome = false

local function ShowNotes()
    if #notes == 0 then return end
    local welcome = QuietKit.welcome
    if welcome and welcome:IsShown() then
        if not waitingForWelcome then
            waitingForWelcome = true
            welcome:HookScript("OnHide", function() C_Timer.After(1, ShowNotes) end)
        end
        return
    end
    local note = table.remove(notes, 1)
    QuietKit.Toast(note.text, note.icon)
    -- (remembered as it's shown, not before: the welcome window reads a saved table with nothing in it as new)
    if note.once then QuietNamesDB[note.once] = true end
    if #notes > 0 then C_Timer.After(4.5, ShowNotes) end
end

--- A note to show once the world is in. once: a key to remember in the saved table once it's shown.
function privateTable.Note(text, icon, once)
    notes[#notes + 1] = { text = text, icon = icon or privateTable.ICON, once = once }
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event, loadedAddonName)
    if event == "ADDON_LOADED" then
        if loadedAddonName ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        QuietNamesDB = QuietNamesDB or {}
        local db = QuietNamesDB
        -- (0.2's own fonts are gone, and its size went with them; 0.1.0's distant-names setting before that)
        if OLD_KEYS[db.font] then db.font = nil end
        db.size, db.distantSize, db.gameDistantSize = nil, nil, nil
        ApplyFont()
        db.toldNoNames = nil -- (No Names is gone: its note is no longer needed)
    elseif event == "PLAYER_LOGIN" then
        -- A font an addon added may have moved since: keep its file up to date for the next start
        local db = QuietNamesDB
        local lsm = db.font and db.font:find("^lsm:") and SharedMedia()
        if lsm then
            local path = lsm:Fetch("font", db.font:sub(5), true)
            if type(path) == "string" and path ~= db.fontPath and Exists(path) then db.fontPath = path end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if privateTable.lostFont then
            privateTable.Note("The font for names (" .. privateTable.lostFont .. ") is gone with the addon that "
                .. "added it: names are in the game's own.")
        end
        C_Timer.After(6, ShowNotes)
    end
end)

---------------------------------------------------------------------------
-- /qnames
---------------------------------------------------------------------------
local RESTART_NOTE = "Exit the game and start it again to see it (a /reload isn't enough)."

local function Status()
    local _, label = privateTable.Chosen()
    Print("names in " .. label .. (privateTable.changed and " from your next start of the game" or "") .. "; "
        .. (QuietNamesDB.dark and "no names outside a fight (/dark brings them back)." or "names stay on."))
end

local function Usage()
    Print("/qnames  the settings;  /qnames fonts  the fonts, each written in itself;  /qnames font <name>")
    print("  /dark  (or /qnames dark)  no names or nameplates outside a fight, or back again")
    print("  /qnames names  every name and nameplate back to the game's own settings;  /qnames status")
end

-- A font by its key or the start of its name
local function MatchFont(text)
    local fonts = privateTable.Fonts()
    for _, font in ipairs(fonts) do
        if font.key == text then return font end
    end
    for _, font in ipairs(fonts) do
        if font.label:lower():sub(1, #text) == text then return font end
    end
end

SLASH_QUIETNAMES1 = "/qnames"
SLASH_QUIETNAMES2 = "/quietnames"
SlashCmdList["QUIETNAMES"] = function(msg)
    local command, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if command == "" or command == "options" then
        if not QuietKit.Open("quietnames") then privateTable.ToggleWindow() end
    elseif command == "fonts" or command == "window" then
        privateTable.ToggleWindow()
    elseif command == "font" and arg ~= "" then
        local font = MatchFont(arg)
        if font then
            privateTable.SetFont(font.key)
            Print("names in " .. font.label .. ". " .. (privateTable.changed and RESTART_NOTE or ""))
        else
            local labels = {}
            for _, each in ipairs(privateTable.Fonts()) do labels[#labels + 1] = each.label end
            Print("no font by that name. There's " .. table.concat(labels, ", ") .. ".")
        end
    elseif command == "dark" or command == "hide" then
        privateTable.ToggleDark()
    elseif command == "names" then
        local count = privateTable.GameNames()
        if count == nil then
            Print("after the fight, please.")
        elseif count == 0 then
            Print("this client can't say what its own settings are: set the names in Options, Interface, Names.")
        else
            Print("every name and nameplate is back to the game's own settings.")
        end
    elseif command == "status" then
        Status()
    else
        Usage()
    end
end
