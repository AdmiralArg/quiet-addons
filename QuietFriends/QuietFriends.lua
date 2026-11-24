-- Quiet Friends: your friends' full character names, to put in a letter's To box without remembering them.
--
-- On WoW Forever every character has a first name and a surname, "Ana Smith" (the game's
-- Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR, a space, between them). Two characters can
-- share a first name, so mail needs both. UnitName(unit) gives the two as separate returns (where other clients give
-- the realm second); chat senders read "Ana Smith".
--
-- The list is kept for the whole account (QuietFriendsDB): a friend is a friend for every character. Each name can
-- have a note, who the friend is ("Mia", "Mia's priest"), and the list is looked through by either.
--  * the window (Window.lua, /qfriends): add, change a note, delete, and put a name in To.
--  * beside the mail (Mail.lua): while you write a letter, your friends are listed by what you've typed in To; a
--    click puts the name there. A name typed in To that isn't on the list can be saved from there.
local _, ns = ...

local MAX_NAME = 48
local MAX_NOTE = 80
local ICON = "Interface\\Icons\\INV_Letter_15"

-- An answer to a command: said in chat, and in the window when it's open (Window.lua sets ns.OnMessage)
local function Print(msg)
    QuietKit.Print("Quiet Friends", msg)
    if ns.OnMessage then ns.OnMessage(msg) end
end

local issecret = issecretvalue or function() return false end

-- nil for a value the game keeps secret (in combat)
local function Plain(value)
    if issecret(value) then return nil end
    return value
end

-- ---------- the list ----------
-- QuietFriendsDB: { friends = { { name = "Ana Smith", note = "Mia", realm, faction }, ... } (sorted by name),
-- mailPanel (false: not beside the mail), pos (the window's place, QuietKit's) }
--
-- Mail only goes to characters on your own server and faction, so each friend is saved with the server and faction
-- of the character who saved them, and a character sees only the friends of its own server and faction. (One table
-- for the account, not one per character: your other characters there share the list.)
local function DB()
    QuietFriendsDB = QuietFriendsDB or {}
    local db = QuietFriendsDB
    db.friends = db.friends or {}
    return db
end

-- This character's server and faction ("Alliance", "Horde"); either nil while the game doesn't say yet
local function Here()
    -- (the realm as every Quiet addon knows it: the game's own name can be empty)
    local realm = QuietKit.Realm()
    local faction = UnitFactionGroup and Plain((UnitFactionGroup("player")))
    if realm == "" then realm = nil end
    if faction ~= "Alliance" and faction ~= "Horde" then faction = nil end
    return realm, faction
end

-- Is this friend on this character's server and faction? A friend saved before either was known takes this
-- character's, the first time one that knows them sees it.
local function IsHere(friend, realm, faction)
    if realm and not friend.realm then friend.realm = realm end
    if faction and not friend.faction then friend.faction = faction end
    return (not realm or friend.realm == realm) and (not faction or friend.faction == faction)
end

-- The friends on this character's server and faction (sorted by name)
local function Friends()
    local realm, faction = Here()
    local here = {}
    for _, friend in ipairs(DB().friends) do
        if IsHere(friend, realm, faction) then here[#here + 1] = friend end
    end
    return here
end
ns.DB, ns.Friends = DB, Friends

local function Separator()
    local c = Constants and Constants.CharacterNameSeparatorConsts
    local sep = c and Plain(c.CHARACTERNAME_SURNAME_SEPARATOR)
    return type(sep) == "string" and sep ~= "" and sep or " "
end

-- A name as the game writes it: "ana  smith-Realm" -> "Ana Smith". Each part starts with a capital (an accented
-- first letter is left as typed: Lua's upper() only knows a to z).
local function CleanName(name)
    name = strtrim(tostring(name or "")):gsub("%-.*$", ""):gsub("%s+", " ")
    name = strtrim(name):gsub("(%S)(%S*)", function(first, rest) return first:upper() .. rest end)
    if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
    return name
end
ns.CleanName = CleanName

local function CleanNote(note)
    note = strtrim(tostring(note or "")):gsub("%s+", " ")
    if #note > MAX_NOTE then note = note:sub(1, MAX_NOTE) end
    return note
end

-- A friend by full name (any case), and their place in the list
local function ByName(name)
    local key = CleanName(name):lower()
    if key == "" then return nil end
    for i, friend in ipairs(Friends()) do
        if friend.name:lower() == key then return friend, i end
    end
end
ns.ByName = ByName

-- A friend by their number in the list, their full name, or their note (any case)
local function Find(ref)
    ref = strtrim(tostring(ref or ""))
    if ref == "" then return nil end
    local i = tonumber(ref)
    if i then return Friends()[i], Friends()[i] and i end
    local friend, at = ByName(ref)
    if friend then return friend, at end
    ref = ref:lower()
    for n, f in ipairs(Friends()) do
        if f.note ~= "" and f.note:lower() == ref then return f, n end
    end
end

-- The friends whose name or note has these letters in it (any case); all of them for nothing typed
local function Matching(text)
    text = strtrim(tostring(text or "")):lower()
    if text == "" then return Friends() end
    local found = {}
    for _, friend in ipairs(Friends()) do
        if friend.name:lower():find(text, 1, true) or friend.note:lower():find(text, 1, true) then
            found[#found + 1] = friend
        end
    end
    return found
end
ns.Matching = Matching

-- "Ana Smith (Mia)"
local function Describe(friend)
    return friend.name .. (friend.note ~= "" and (" (" .. friend.note .. ")") or "")
end

local function Sort()
    table.sort(DB().friends, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- Saves a friend, or gives one already saved a new note. The friend, or nil (and why, said).
local function Add(name, note)
    name, note = CleanName(name), CleanNote(note)
    if name == "" then
        Print("whose name? Like this: /qfriends add Ana Smith, Mia (the note after the comma is optional).")
        return nil
    end
    local friend = ByName(name)
    if friend then
        local renoted = note ~= "" and note ~= friend.note
        if renoted then friend.note = note end
        Print((renoted and "new note: " or "already on your list: ") .. Describe(friend))
        if renoted and ns.RefreshAll then ns.RefreshAll() end
        return friend
    end
    if not name:find(Separator(), 1, true) then
        Print("saved, but " .. name .. " has no surname: on WoW Forever a letter needs both names, as in Ana Smith.")
    end
    local realm, faction = Here()
    friend = { name = name, note = note, realm = realm, faction = faction }
    local friends = DB().friends
    friends[#friends + 1] = friend
    Sort()
    Print("saved " .. Describe(friend))
    if ns.RefreshAll then ns.RefreshAll() end
    return friend
end
ns.Add = Add

local function SetNote(friend, note)
    friend.note = CleanNote(note)
    Print(friend.note == "" and ("no note for " .. friend.name .. " now.") or ("now " .. Describe(friend)))
    if ns.RefreshAll then ns.RefreshAll() end
end
ns.SetNote = SetNote

local function Remove(friend)
    for i, f in ipairs(DB().friends) do
        if f == friend then
            table.remove(DB().friends, i)
            Print("removed " .. Describe(friend) .. ".")
            if ns.RefreshAll then ns.RefreshAll() end
            return
        end
    end
end
ns.Remove = Remove

-- ---------- names from the game ----------
-- A player's full name ("Ana Smith"), or nil: not a player, or the game won't say (secret in combat)
local function UnitFull(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then return nil end
    local name, second = UnitName(unit)
    name, second = Plain(name), Plain(second)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    local sep = Separator()
    -- (already complete, as the player's own name can be)
    if name:find(sep, 1, true) then return CleanName(name) end
    if type(second) == "string" and second ~= "" then return CleanName(name .. sep .. second) end
    return CleanName(name)
end
ns.UnitFull = UnitFull

-- Saves the player you have targeted
local function AddTarget(note)
    local name = UnitFull("target")
    if not name then
        Print("target a player first (or give a name: /qfriends add Ana Smith, Mia).")
        return nil
    end
    return Add(name, note)
end
ns.AddTarget = AddTarget

-- ---------- the mail ----------
-- The To box of a letter, while the letter is open (else nil)
local function ToBox()
    local box = SendMailNameEditBox
    if box and box:IsVisible() then return box end
end
ns.ToBox = ToBox

-- Puts a friend's name in To; the cursor goes on to the subject. True if it did.
local function MailTo(friend)
    local box = ToBox()
    if not box then
        Print("open a mailbox and its Send Mail tab first: then " .. friend.name .. " goes in To.")
        return false
    end
    box:SetText(friend.name)
    box:SetCursorPosition(#friend.name)
    if SendMailSubjectEditBox and SendMailSubjectEditBox:IsVisible() then
        SendMailSubjectEditBox:SetFocus()
    else
        box:ClearFocus()
    end
    return true
end
ns.MailTo = MailTo

-- ---------- commands ----------
-- "Ana Smith, Mia" -> "Ana Smith", "Mia"
local function NameAndNote(text)
    local name, note = tostring(text or ""):match("^([^,]*),?(.*)$")
    return strtrim(name or ""), strtrim(note or "")
end

local function NoFriend(ref)
    if ref and strtrim(tostring(ref)) ~= "" then
        Print('there\'s no "' .. strtrim(tostring(ref)) .. '" on your list. /qfriends list shows it.')
    else
        Print("which friend? Their name, or their number from /qfriends list.")
    end
end

local function List(text)
    local friends = Matching(text)
    if #Friends() == 0 then
        Print("no friends saved yet. /qfriends add Ana Smith, Mia saves one (or target them and /qfriends add).")
        return
    end
    if #friends == 0 then
        Print('no name or note has "' .. strtrim(text) .. '" in it.')
        return
    end
    Print(#friends .. (#friends == 1 and " friend:" or " friends:"))
    for _, friend in ipairs(friends) do
        local _, i = ByName(friend.name)
        print("  " .. i .. ". " .. friend.name .. (friend.note ~= "" and ("  |cff8f8f94" .. friend.note .. "|r") or ""))
    end
end

local function Help()
    Print("every command:")
    print("  /qfriends  opens or closes the list (a key for it: Key Bindings, AddOns, Quiet Friends)")
    print("  /qfriends add Ana Smith, Mia  saves a friend; the note after the comma (who it is) is optional")
    print("  /qfriends add  saves the player you have targeted (/qfriends add , Mia with a note)")
    print("  /qfriends note Ana Smith, Mia's priest  a new note (nothing after the comma clears it)")
    print("  /qfriends remove Ana Smith  deletes a friend (or their number from the list)")
    print("  /qfriends list mia  lists your friends in chat, only those with \"mia\" in name or note")
    print("  /qfriends mail mia  puts that friend's name in To, with a letter open")
    print("  Beside the mail, your friends are listed: a click puts the name in To. Typing in To narrows the list.")
end

SLASH_QUIETFRIENDS1 = "/qfriends"
SLASH_QUIETFRIENDS2 = "/quietfriends"
SlashCmdList.QUIETFRIENDS = function(msg)
    -- (only the command is lowercased: names and notes keep what was typed)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" and ns.ToggleWindow then
        ns.ToggleWindow()
    elseif cmd == "list" or cmd == "" then
        List(rest)
    elseif cmd == "add" then
        local name, note = NameAndNote(rest)
        if name == "" then AddTarget(note) else Add(name, note) end
    elseif cmd == "note" then
        local name, note = NameAndNote(rest)
        local friend = Find(name)
        if friend then SetNote(friend, note) else NoFriend(name) end
    elseif cmd == "remove" or cmd == "delete" or cmd == "del" then
        local friend = Find(rest)
        if friend then Remove(friend) else NoFriend(rest) end
    elseif cmd == "mail" or cmd == "to" then
        local friend = Find(rest)
        if not friend then
            local found = Matching(rest)
            friend = #found == 1 and found[1] or nil
        end
        if friend then MailTo(friend) else NoFriend(rest) end
    else
        Help()
    end
end

-- ---------- the settings, for QuietKit (QuietKit.lua): Options > AddOns > Quiet, and Improved Forever's Quiet tab ----------
local MACRO = { name = "Quiet Friends", icon = "INV_Letter_15", body = "/qfriends", account = true }

QuietKit.Register({
    key = "quietfriends",
    saved = "QuietFriendsDB",
    title = "Quiet Friends",
    icon = ICON,
    about = "Your friends' full character names, first name and surname, with a note on who each one is. "
        .. "When you write a letter they're listed beside it: a click puts the name in To. Each character sees "
        .. "the friends saved on its own server and faction, the ones mail can reach.",
    how = "/qfriends opens the list: add a name there, or target a friend and press Add my target. "
        .. "At a mailbox, open Send Mail.",
    command = "/qfriends",
    db = DB,
    items = {
        {
            label = "The list, on a bar",
            tip = 'Drag "' .. MACRO.name .. '" onto a bar, or "Put on my bar" (with a controller: onto your crossbar '
                .. "from /macro). A press opens or closes the list. For the keyboard there's also a key: Key "
                .. "Bindings, AddOns, Quiet Friends.",
            macro = MACRO,
            use = function() if ns.ToggleWindow then ns.ToggleWindow() end end,
        },
        {
            label = "Friends beside the mail",
            tip = "On: while you write a letter, your friends are listed beside it, narrowed by what you type in To. "
                .. "A click puts the name in To.",
            get = function() return DB().mailPanel ~= false end,
            set = function(on)
                DB().mailPanel = on and true or false
                if ns.RefreshMail then ns.RefreshMail() end
            end,
        },
    },
})
