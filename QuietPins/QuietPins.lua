-- Quiet Pins: map notes for the game's own map pin. A note is a place (map, x, y) with a few words; any one of them
-- can be put on the map as the game's pin, which the game then tracks (the arrow and distance on screen).
--
-- What WoW Forever allows:
--  * the game has one pin of its own (C_Map.SetUserWaypoint), not many: the notes are kept here, and one at a time
--    goes on the map. No pins of our own are drawn.
--  * no protected calls: every command works from a macro, so a note can sit on a crossbar ("/qpin next").
--  * values can be secret in combat: anything read then goes through issecretvalue first.
--
-- The notes are kept for the whole account (QuietPinsDB): a place is the same place for every character.
--  * each note has a number of its own that never changes (a deleted note's isn't given again), so a "/qpin 3" on a
--    bar stays on the same note. A note can be named by its words too: /qpin Goldshire.
--  * /way only pins (a guide's steps would fill the list otherwise): the last one is remembered, and Keep (the
--    window, /qpin keep) saves it. A note saved where one already is joins that one.
local _, ns = ...

local MAX_TEXT = 120
local SAME_PLACE = 0.0005 -- (the game rounds a pin's coordinates a little when read back)
local NEAR = 0.0015 -- (a new note this close to one joins it: 0.15 on the map's 0 to 100 scale, as guides round to 0.1)

-- An answer to a command: said in chat, and in the window when it's open (Window.lua sets ns.OnMessage)
local function Print(msg)
    QuietKit.Print("Quiet Pins", msg)
    if ns.OnMessage then ns.OnMessage(msg) end
end

local issecret = issecretvalue or function() return false end

-- nil for a value the game keeps secret (in combat)
local function Plain(value)
    if issecret(value) then return nil end
    return value
end

-- ---------- notes ----------
-- QuietPinsDB: { notes = { { id, map, x, y, text }, ... }, nextID, last (the id "next" pinned last), way = { map, x, y,
-- text } (the last /way: pinned, not saved), wayNotes (true: every /way is saved, as before 0.3.0), wayTold (the note
-- that another addon has /way was shown), pos (the window's place, QuietKit's) }
local migrated -- (the saved table brought up to date)

local function DB()
    QuietPinsDB = QuietPinsDB or {}
    local db = QuietPinsDB
    if migrated ~= db then
        migrated = db
        db.notes = db.notes or {}
        -- Notes from before 0.3.0 had no number of their own: each gets the one it was shown with, so a "/qpin 3"
        -- made then still pins the same note (and "last", a place in the list then, is that note's number now)
        local top = 0
        for i, note in ipairs(db.notes) do
            note.id = note.id or i
            top = math.max(top, note.id)
        end
        db.nextID = math.max(db.nextID or 1, top + 1)
        -- (the window's place is QuietKit's to keep now, as pos)
        if type(db.window) == "table" and db.window.point and not db.pos then
            db.pos = { db.window.point, db.window.x or 0, db.window.y or 0 }
        end
        db.window = nil
    end
    return db
end

local function Notes()
    return DB().notes
end
ns.DB, ns.Notes = DB, Notes

-- A note by its number: the note and its place in the list
local function ByID(id)
    for i, note in ipairs(Notes()) do
        if note.id == id then return note, i end
    end
end
ns.ByID = ByID

-- A note by its number, or by its words (any case): the note and its place in the list
local function Find(ref)
    ref = strtrim(tostring(ref or ""))
    if ref == "" then return nil end
    local id = tonumber(ref)
    if id then return ByID(id) end
    ref = ref:lower()
    for i, note in ipairs(Notes()) do
        if note.text ~= "" and note.text:lower() == ref then return note, i end
    end
end

local function MapName(mapID)
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        local name = ok and Plain(info) and Plain(info.name)
        if type(name) == "string" and name ~= "" then return name end
    end
    return "map " .. tostring(mapID)
end

local function Coords(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- A place as it's written: Elwynn Forest (42.0, 65.0)  Goldshire
local function PlaceText(place)
    local text = (place.text or "") ~= "" and ("  " .. place.text) or ""
    return MapName(place.map) .. " (" .. Coords(place.x, place.y) .. ")" .. text
end

local function Describe(note)
    return note.id .. ". " .. PlaceText(note)
end

-- x, y of a map position (a vector), or nil
local function XY(position)
    if not Plain(position) then return nil end
    local ok, x, y = pcall(function()
        if type(position.GetXY) == "function" then return position:GetXY() end
        return position.x, position.y
    end)
    x, y = ok and Plain(x), ok and Plain(y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

-- The map the player is on, or nil
local function CurrentMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and Plain(mapID)
    if type(mapID) ~= "number" then return nil end
    return mapID
end

-- Where the player stands: map, x, y; nil where the game won't say (an instance, or secret in combat)
local function Here()
    local mapID = CurrentMap()
    if not mapID or not C_Map.GetPlayerMapPosition then return nil end
    local got, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y = XY(got and position)
    if not x or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return mapID, x, y
end

local function CleanText(text)
    text = strtrim(text or "")
    if #text > MAX_TEXT then text = text:sub(1, MAX_TEXT) end
    return text
end

-- The note at a place (as near as NEAR), or nil
local function NoteAt(mapID, x, y)
    for _, note in ipairs(Notes()) do
        if note.map == mapID and math.abs(note.x - x) <= NEAR and math.abs(note.y - y) <= NEAR then return note end
    end
end

-- ---------- the game's pin ----------
local function CanPin()
    return C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and true or false
end

-- The game's pin now: map, x, y, or nil if there's none
local function Pin()
    if not (C_Map and C_Map.GetUserWaypoint) then return nil end
    if C_Map.HasUserWaypoint then
        local ok, has = pcall(C_Map.HasUserWaypoint)
        if ok and Plain(has) == false then return nil end
    end
    local got, point = pcall(C_Map.GetUserWaypoint)
    point = got and Plain(point)
    if not point then return nil end
    local mapID = Plain(point.uiMapID)
    local x, y = XY(point.position)
    if type(mapID) ~= "number" or not x then return nil end
    return mapID, x, y
end

-- Is the game's pin on this place (a note, or the last /way)? (A pin set on a zone reads back on that zone; one set on
-- a city inside it may not, so the pin is also asked for its place on the note's map.)
local function Pinned(place)
    local mapID, x, y = Pin()
    if not mapID then return false end
    if mapID ~= place.map and C_Map.GetUserWaypointPositionForMap then
        local ok, position = pcall(C_Map.GetUserWaypointPositionForMap, place.map)
        x, y = XY(ok and position)
        if not x then return false end
    elseif mapID ~= place.map then
        return false
    end
    return math.abs(x - place.x) <= SAME_PLACE and math.abs(y - place.y) <= SAME_PLACE
end

-- The last /way, while the pin is still on it (else nil)
local function WayPinned()
    local way = DB().way
    if way and Pinned(way) then return way end
end
ns.WayPinned = WayPinned

local function NoNote(ref)
    if ref and strtrim(tostring(ref)) ~= "" then
        Print('there\'s no note "' .. strtrim(tostring(ref)) .. '". /qpin list shows them.')
    else
        Print("which note? Give its number from /qpin list, as in /qpin remove 3.")
    end
end

-- Puts a place on the map as the game's pin, and has the game track it. True if it did.
local function SetPin(mapID, x, y)
    if not CanPin() then
        Print("this client has no map pin to set.")
        return false
    end
    if C_Map.CanSetUserWaypointOnMap then
        local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        if ok and Plain(can) == false then
            Print("the game allows no pin on " .. MapName(mapID) .. ".")
            return false
        end
    end
    local ok, err = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    end)
    if not ok then
        Print("the game wouldn't set the pin: " .. tostring(err))
        return false
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

local function PinNote(note)
    if not note then
        NoNote()
        return false
    end
    if not SetPin(note.map, note.x, note.y) then return false end
    DB().last = note.id
    Print("pinned " .. Describe(note))
    return true
end

-- /qpin 3, /qpin pin Goldshire
local function PinRef(ref)
    local note = Find(ref)
    if not note then
        NoNote(ref)
        return false
    end
    return PinNote(note)
end

local function ClearPin()
    if not (C_Map and C_Map.ClearUserWaypoint) then
        Print("this client has no map pin to clear.")
        return
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
    end
    local ok, err = pcall(C_Map.ClearUserWaypoint)
    if ok then
        Print("pin cleared.")
    else
        Print("the game wouldn't clear the pin: " .. tostring(err))
    end
end

-- ---------- saving ----------
-- Saves a note, or joins the one already there (its words kept, the new ones added). The note, and true if it joined.
local function Add(mapID, x, y, text, quiet)
    text = CleanText(text)
    local note = NoteAt(mapID, x, y)
    if note then
        if text ~= "" and not note.text:lower():find(text:lower(), 1, true) then
            note.text = CleanText(note.text == "" and text or (note.text .. "; " .. text))
        end
        if not quiet then Print("there's a note there already: " .. Describe(note)) end
        return note, true
    end
    local db = DB()
    note = { id = db.nextID, map = mapID, x = x, y = y, text = text }
    db.nextID = db.nextID + 1
    db.notes[#db.notes + 1] = note
    if not quiet then Print("saved " .. Describe(note)) end
    return note, false
end

-- A note where the player stands
local function AddHere(text)
    local mapID, x, y = Here()
    if not mapID then
        Print("the game won't say where you are here (an instance, or in a fight). Try again in the open.")
        return
    end
    Add(mapID, x, y, text)
end

-- A note of the pin on the map now (the last /way, one put there on the map, or one from another addon). The last
-- /way's words come with it unless new ones are given.
local function Keep(text)
    local mapID, x, y = Pin()
    if not mapID then
        Print("there's no pin on the map to keep.")
        return
    end
    local way = WayPinned()
    if way then
        if strtrim(text or "") == "" then text = way.text end
        mapID, x, y = way.map, way.x, way.y
        DB().way = nil
    end
    local note = Add(mapID, x, y, text)
    DB().last = note.id
end

-- ---------- pasted coordinates ----------
-- Coordinates as guides and other addons write them, on the map's 0 to 100 scale: "45.2 63.8", "45.2, 63.8",
-- "45,63", "(45.2, 63.8)", "/way 45.2 63.8 Name", "/way Elwynn Forest 45 63 words", and "45,2 63,8" (decimal commas).
local MAP_SCAN = 3000 -- (map IDs looked through for a zone's name)
local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local mapsByName -- lowercased name -> { id, type }, filled the first time a zone is named

-- A map by its name ("Elwynn Forest", any case) or TomTom's "#1429" (its ID); nil if the game knows none
local function FindMap(name)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local id = tonumber(name:match("^#(%d+)$"))
    if id then
        local ok, info = pcall(C_Map.GetMapInfo, id)
        return ok and Plain(info) and id or nil
    end
    -- (the game can't look a map up by name: every map is asked its name once)
    if not mapsByName then
        mapsByName = {}
        for mapID = 1, MAP_SCAN do
            local ok, info = pcall(C_Map.GetMapInfo, mapID)
            info = ok and Plain(info)
            local mapName = info and Plain(info.name)
            if type(mapName) == "string" and mapName ~= "" then
                local key, mapType = mapName:lower(), Plain(info.mapType)
                local known = mapsByName[key]
                -- (a zone wins over a dungeon floor or a city part of the same name)
                if not known or (mapType == ZONE and known.type ~= ZONE) then
                    mapsByName[key] = { id = mapID, type = mapType }
                end
            end
        end
    end
    local found = mapsByName[name:lower()]
    return found and found.id
end

-- x, y (0 to 100, unchecked), what came before them (a zone's name, or ""), and what came after (the note's words);
-- nil if there's no pair of numbers
local function ParseCoords(text)
    text = strtrim(text or "")
    text = text:gsub("^/[Tt]?[Ww][Aa][Yy]%s*", ""):gsub("^[Aa][Tt]%s+", "")
    local s, e, x, y
    local x1, x2, y1, y2
    s, e, x1, x2, y1, y2 = text:find("(%d+),(%d+)%s+(%d+),(%d+)")
    if s then
        x, y = tonumber(x1 .. "." .. x2), tonumber(y1 .. "." .. y2)
    else
        s, e, x, y = text:find("(%-?%d+%.?%d*)%s*[,%s]%s*(%-?%d+%.?%d*)")
        x, y = tonumber(x), tonumber(y)
    end
    if not s or not x or not y then return nil end
    local zone = strtrim((text:sub(1, s - 1):gsub("[%(%[,:]", " ")))
    local words = strtrim((text:sub(e + 1):gsub("^%s*[%)%],]*", "")))
    return x, y, zone, words
end

-- Pasted coordinates as a place: map, x, y (0 to 1), words; nil (and why, said) if they won't do
local function Locate(text)
    local x, y, zone, words = ParseCoords(text)
    if not x then
        Print("no coordinates there. Like this: /qpin 45.2 63.8 <words>, or /qpin at Elwynn Forest 45 63 <words>.")
        return nil
    end
    if x < 0 or x > 100 or y < 0 or y > 100 then
        Print("coordinates go from 0 to 100, so " .. x .. ", " .. y .. " is off the map.")
        return nil
    end
    local mapID
    if zone ~= "" then
        mapID = FindMap(zone)
        if not mapID then Print('no map named "' .. zone .. '": it goes on the map you\'re on.') end
    end
    mapID = mapID or CurrentMap()
    if not mapID then
        Print("the game won't say which map you're on here. Name the zone first, as in /qpin at Elwynn Forest 45 63.")
        return nil
    end
    return mapID, x / 100, y / 100, words
end

-- A note at pasted coordinates (or the one already there), pinned at once: coordinates from a guide are somewhere to
-- go. True if it was saved.
local function AddAt(text)
    local mapID, x, y, words = Locate(text)
    if not mapID then return end
    local note, joined = Add(mapID, x, y, words, true)
    if joined then Print("there's a note there already: " .. Describe(note)) end
    if not PinNote(note) and not joined then Print("saved " .. Describe(note)) end
    return true
end

-- /way: pins the place without saving it, remembered as the last /way (Keep saves it). A note already there is
-- pinned instead. (With "save every /way" on, it's saved, as before 0.3.0.) True if it pinned.
local function WayAt(text)
    if DB().wayNotes then return AddAt(text) end
    local mapID, x, y, words = Locate(text)
    if not mapID then return end
    local note = NoteAt(mapID, x, y)
    if note then return PinNote(note) end
    if not SetPin(mapID, x, y) then return end
    local way = { map = mapID, x = x, y = y, text = CleanText(words) }
    DB().way = way
    Print("pinned " .. PlaceText(way) .. ". Not saved: Keep in the window (or /qpin keep) saves it.")
    return true
end

local function List()
    local notes = Notes()
    local way = WayPinned()
    if #notes == 0 then
        Print("no notes yet. /qpin add <words> saves one where you stand.")
    else
        Print(#notes .. (#notes == 1 and " note" or " notes") .. " (/qpin <number> pins one):")
        for _, note in ipairs(notes) do
            print("  " .. Describe(note) .. (Pinned(note) and "  |cff66ccff<- pinned|r" or ""))
        end
    end
    if way then print("  pinned from /way, not saved: " .. PlaceText(way) .. "  (/qpin keep saves it)") end
end

-- The note after the one pinned last, round again after the last note: one macro button walks through them all
local function Next()
    local notes = Notes()
    if #notes == 0 then
        Print("no notes yet. /qpin add <words> saves one where you stand.")
        return
    end
    local last = DB().last or 0
    for _, note in ipairs(notes) do
        if note.id > last then return PinNote(note) end
    end
    PinNote(notes[1])
end

local function Remove(ref)
    local note, i = Find(ref)
    if not note then
        NoNote(ref)
        return
    end
    -- (its pin goes with it, so no pin is left on the map for a note that's gone)
    if Pinned(note) then ClearPin() end
    table.remove(Notes(), i)
    Print("removed " .. Describe(note) .. ".")
end

local function Rename(id, text)
    local note = ByID(id)
    if not note then
        NoNote(id)
        return
    end
    note.text = CleanText(text)
    Print("now " .. Describe(note))
end

-- ---------- /way ----------
-- Ours unless another addon (TomTom) has it: then /qpin way does the same. Known at login, once every addon has
-- loaded.
local wayIsOurs = false

-- Where the pin is now, and which note it's on
local function ShowPin()
    local mapID, x, y = Pin()
    if not mapID then
        Print("there's no pin on the map. " .. (wayIsOurs and "/way" or "/qpin way") .. " 45.2 63.8 <words> pins a place.")
        return
    end
    for _, note in ipairs(Notes()) do
        if Pinned(note) then
            Print("pinned: " .. Describe(note))
            return
        end
    end
    local way = WayPinned()
    if way then
        Print("pinned from /way, not saved: " .. PlaceText(way) .. ". /qpin keep saves it.")
    else
        Print("pinned: " .. MapName(mapID) .. " (" .. Coords(x, y) .. "), not one of your notes. /qpin keep <words> saves it.")
    end
end

-- /way with nothing after it shows the pin; with coordinates, it pins them
local function Way(text)
    if strtrim(text or "") == "" then
        ShowPin()
    else
        WayAt(text)
    end
end

-- Takes /way if no other addon has it (a slash command's names are its SLASH_<NAME>1, 2, ... globals). If one has,
-- that's said once, in a note.
local function ClaimWay()
    for name in pairs(SlashCmdList) do
        if name ~= "QUIETPINSWAY" then
            for i = 1, 10 do
                local alias = _G["SLASH_" .. name .. i]
                if type(alias) ~= "string" then break end
                if alias:lower() == "/way" then
                    if not DB().wayTold then
                        DB().wayTold = true
                        -- (after the loading screen and the Quiet welcome)
                        C_Timer.After(8, function()
                            QuietKit.Toast("Another addon has /way, so Quiet Pins leaves it alone: /qpin way 45.2 63.8 "
                                .. "pins a place instead.", "Interface\\Icons\\INV_Misc_Map_01")
                        end)
                    end
                    return
                end
            end
        end
    end
    SLASH_QUIETPINSWAY1 = "/way"
    SlashCmdList.QUIETPINSWAY = Way
    wayIsOurs = true
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", ClaimWay)

local function Help()
    Print("every command (each one works in a macro too):")
    print("  /qpin  opens or closes the window (a key for it: Key Bindings, AddOns, Quiet Pins)")
    print("  /qpin list  lists your notes in chat")
    print("  /qpin add <words>  saves a note where you stand (the words are optional)")
    print("  /qpin at 45.2 63.8 <words>  saves a note at those coordinates on the map you're on, and pins it.")
    print("    A zone first puts it on that zone's map: /qpin at Elwynn Forest 45 63. The \"at\" can be left out,")
    print("    and pasted forms work too: 45,63  (45.2, 63.8)  /way 45.2 63.8 Name  /way Elwynn Forest 45 63")
    if wayIsOurs then
        print("  /way 45.2 63.8 <words>  pins a place without saving it, as guides write it: paste the line into chat.")
        print("    /way alone shows the pin.")
    else
        print("  /qpin way 45.2 63.8 <words>  pins a place without saving it (another addon has /way itself)")
    end
    print("  /qpin keep <words>  saves the pin on the map now as a note (the last /way's words if you give none)")
    print("  /qpin 3  puts note 3 on the map as the game's pin, and tracks it. Its words work too: /qpin Goldshire")
    print("  /qpin next  pins the next note (round again after the last)")
    print("  /qpin clear  takes the pin off the map")
    print("  /qpin remove 3  deletes note 3 (the others keep their numbers)")
    print("  /qpin rename 3 <words>  new words for note 3")
end

-- (for the window, Window.lua)
ns.Pin, ns.Pinned, ns.Describe, ns.MapName, ns.Coords, ns.PlaceText = Pin, Pinned, Describe, MapName, Coords, PlaceText
ns.PinNote, ns.Next, ns.ClearPin, ns.Keep = PinNote, Next, ClearPin, Keep
ns.AddHere, ns.AddAt, ns.Remove, ns.Rename = AddHere, AddAt, Remove, Rename

SLASH_QUIETPINS1 = "/qpin"
SLASH_QUIETPINS2 = "/quietpins"
SlashCmdList.QUIETPINS = function(msg)
    -- (only the command is lowercased: a note keeps its words as typed)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" and ns.ToggleWindow then
        ns.ToggleWindow()
    elseif cmd == "" or cmd == "list" then
        List()
    elseif cmd == "at" then
        AddAt(rest)
    elseif cmd == "way" or cmd == "/way" or cmd == "/tway" then
        Way(rest)
    elseif cmd == "pin" then
        PinRef(rest)
    elseif cmd == "add" then
        AddHere(rest)
    elseif cmd == "keep" then
        Keep(rest)
    elseif cmd == "next" then
        Next()
    elseif cmd == "clear" or cmd == "unpin" then
        ClearPin()
    elseif cmd == "remove" or cmd == "delete" or cmd == "del" then
        Remove(rest)
    elseif cmd == "rename" then
        local id, text = rest:match("^(%d+)%s*(.-)$")
        Rename(tonumber(id), text)
    elseif ParseCoords(msg) then
        -- (two numbers are coordinates, pasted as they were: "/qpin 45.2 63.8"; one alone is a note's number)
        AddAt(msg)
    elseif tonumber(cmd) then
        PinRef(cmd)
    elseif Find(msg) then
        PinRef(msg)
    else
        Help()
    end
end

-- ---------- the settings, for QuietKit (QuietKit.lua): Options > AddOns > Quiet, and Improved Forever's Quiet tab ----------
local MACRO = { name = "Quiet Pins", icon = "INV_Misc_Map_01", body = "/qpin", account = true }

QuietKit.Register({
    key = "quietpins",
    saved = "QuietPinsDB",
    title = "Quiet Pins",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    about = "Map notes for the game's own map pin: save a place, pin it later, and the game shows the way. "
        .. "/way lines from guides pin a place without filling your notes.",
    how = function()
        return "/qpin opens the window (or its macro below, or a key: Key Bindings, AddOns). "
            .. (wayIsOurs and "Paste a guide's /way line into chat to pin it." or "/qpin way 45 63 pins a place.")
    end,
    command = "/qpin",
    db = DB,
    news = {
        version = "0.3.0",
        text = "/way only pins now: Keep in the window (or /qpin keep) saves it, so guides no longer fill your notes. "
            .. "A note keeps its number when another is deleted, so /qpin 3 on a bar stays on the same note. A note "
            .. "saved where one already is joins it. The window can go on a bar (its settings), for the controller.",
    },
    items = {
        {
            label = "The window, on a bar",
            tip = 'Drag "' .. MACRO.name .. '" onto a bar, or "Put on my bar" (with a controller: onto your crossbar '
                .. "from /macro). A press opens or closes the window. For the keyboard there's also a key: Key "
                .. "Bindings, AddOns, Quiet Pins.",
            macro = MACRO,
            use = function() if ns.ToggleWindow then ns.ToggleWindow() end end,
        },
        {
            label = "Save every /way as a note",
            tip = "Off: /way pins the place and remembers it, and Keep (the window, or /qpin keep) saves it. "
                .. "On: every /way is saved as a note too, as before.",
            get = function() return DB().wayNotes == true end,
            set = function(on) DB().wayNotes = on or nil end,
        },
    },
})
