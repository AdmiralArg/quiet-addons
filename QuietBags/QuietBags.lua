-- Quiet Bags: what your other characters carry, so the bank alt's bags can be looked through from your main.
--
-- How it works:
--  * every character with this on writes down what's in its bags (at login, whenever the bags settle, at logout),
--    what's in its bank (whenever the bank is open) and what's in its mailbox (whenever that's open). Bags, bank
--    and mail are kept apart, each with when it was last seen: the bank is only known as it was at the last visit.
--  * it's kept for the whole account (QuietBagsDB), by name and realm, so any character can read any other's.
--  * /qbags opens a small window to look through it (Window.lua); item tooltips get a line per character.
--  * nothing is moved, sorted or replaced: the game's own bags stay as they are.
--
-- Values can be secret in combat: anything read then goes through issecretvalue first.
local _, ns = ...

local LOGIN_DELAY = 2
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
local PLACES = { "bank", "bags", "mail" } -- (the order they're named in: "bank 8, bags 4")

local function Print(msg)
    QuietKit.Print("Quiet Bags", msg)
end
ns.Print = Print

local issecret = issecretvalue or function() return false end

-- nil for a value the game keeps secret (in combat)
local function Plain(value)
    if issecret(value) then return nil end
    return value
end

-- ---------- what's kept ----------
-- QuietBagsDB: { chars = { ["Name-Realm"] = { name, realm, class, faction, bags, bank, mail } }, selected, pos,
-- tooltips, bagButton (false: off), welcome (QuietKit's marks) }
-- bags, bank and mail each: { at = time(), items = { [itemID] = { link, count, icon } } }
local function DB()
    QuietBagsDB = QuietBagsDB or {}
    QuietBagsDB.chars = QuietBagsDB.chars or {}
    return QuietBagsDB
end
ns.DB = DB

-- QuietKit's welcome keeps its marks in a table of their own (options.lua): the bags written down a moment after a
-- first login would make a new player look like one who had Quiet Bags before. had: one who did (what's new, not
-- the welcome), known by a saved table there as it loads.
function ns.WelcomeDB()
    local db = DB()
    db.welcome = db.welcome or {}
    return db.welcome
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "QuietBags" then return end
    self:UnregisterEvent("ADDON_LOADED")
    if QuietBagsDB and type(QuietBagsDB.welcome) ~= "table" then QuietBagsDB.welcome = { had = true } end
end)

-- This character's "Name-Realm", as every Quiet addon knows it (QuietKit.Stock); nil before the game knows who you are
function ns.MyKey()
    return QuietKit.Stock.MyKey()
end

-- This character's entry, made the first time; nil before the game knows who you are
local function Me()
    local myKey = ns.MyKey()
    if not myKey then return nil end
    local chars = DB().chars
    local char = chars[myKey] or {}
    chars[myKey] = char
    char.name, char.realm = myKey:match("^(.-)%-(.*)$")
    local _, class = UnitClass("player")
    char.class = Plain(class) or char.class
    local faction = Plain(UnitFactionGroup("player"))
    if type(faction) == "string" and faction ~= "Neutral" then char.faction = faction end
    return char
end

-- ---------- reading the bags and the bank ----------
-- (which containers are the bags and which the bank: QuietKit.Stock's lists, the reagent bag among the bags)
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local SlotInfo = C_Container and C_Container.GetContainerItemInfo
local IconOf = (C_Item and C_Item.GetItemIconByID) or GetItemIconByID
local function BagIDs() return QuietKit.Stock.BagIDs() end
local function BankIDs() return QuietKit.Stock.BankIDs() end

local function Add(items, id, count, link, icon)
    local item = items[id]
    if item then
        item.count = item.count + count
        item.link = item.link or link
    else
        items[id] = { link = link, count = count, icon = icon }
    end
end

-- What's in some containers, combined per item; nil when the game shows no slots at all (not ready yet, or the
-- bank already closed), so what was kept before isn't wiped by an empty read
local function Read(containers)
    if not (NumSlots and SlotInfo) then return nil end
    local items, slots = {}, 0
    for _, bag in ipairs(containers) do
        local ok, n = pcall(NumSlots, bag)
        n = ok and Plain(n)
        if type(n) == "number" and n > 0 then
            slots = slots + n
            for slot = 1, n do
                local got, info = pcall(SlotInfo, bag, slot)
                info = got and Plain(info)
                local id = type(info) == "table" and Plain(info.itemID)
                if type(id) == "number" then
                    local count = Plain(info.stackCount)
                    Add(items, id, type(count) == "number" and count or 1, Plain(info.hyperlink), Plain(info.iconFileID))
                end
            end
        end
    end
    if slots == 0 then return nil end
    return items, slots
end

local function Keep(where, items, slots)
    local char = Me()
    if not char or not items then return end
    char[where] = { at = time(), items = items, slots = slots }
    QuietKit.Stock.Touch()
    if ns.RefreshWindow then ns.RefreshWindow() end
end

local bankOpen, mailOpen = false, false

local function ReadBags()
    Keep("bags", Read(BagIDs()))
end

local function ReadBank()
    if not bankOpen then return end
    Keep("bank", Read(BankIDs()))
end

-- Away from the bank, a moment after login: some clients already know what's in it. Only taken when it shows
-- something, and at least as many slots as at the last visit (so bank bags the game hasn't loaded yet aren't
-- taken as empty); else what was seen at the bank stays.
local function ReadBankAway()
    if bankOpen then return end
    local items, slots = Read(BankIDs())
    local char = Me()
    if not (items and char and next(items)) then return end
    if char.bank and (char.bank.slots or math.huge) > slots then return end
    Keep("bank", items, slots)
end

-- /qbags bank: what it reads as the bank, to see why the bank isn't showing
function ns.BankReport()
    local parts = {}
    for _, bag in ipairs(BankIDs()) do
        local ok, n = pcall(NumSlots or function() return 0 end, bag)
        parts[#parts + 1] = bag .. ":" .. tostring(ok and Plain(n))
    end
    local char = Me()
    local bank = char and char.bank
    local kinds = 0
    for _ in pairs(bank and bank.items or {}) do kinds = kinds + 1 end
    Print("bank " .. (bankOpen and "open" or "closed") .. "; bank containers (id:slots) " .. table.concat(parts, " ")
        .. "; kept " .. kinds .. " kinds of item, " .. (ns.Ago(bank and bank.at) or "never seen") .. ".")
end

-- The mailbox's attachments, as far as the game shows them (it shows at most 50 mails at a time)
local function ReadMail()
    if not mailOpen or not GetInboxNumItems then return end
    local ok, shown = pcall(GetInboxNumItems)
    shown = ok and Plain(shown)
    if type(shown) ~= "number" then return end
    local items = {}
    for i = 1, shown do
        local got, _, _, _, _, _, _, _, itemCount = pcall(GetInboxHeaderInfo, i)
        itemCount = got and Plain(itemCount)
        if type(itemCount) == "number" and itemCount > 0 then
            for a = 1, ATTACHMENTS do
                local had, _, id, icon, count = pcall(GetInboxItem, i, a)
                id = had and Plain(id)
                if type(id) == "number" then
                    local linked, link = pcall(GetInboxItemLink, i, a)
                    count = Plain(count)
                    Add(items, id, type(count) == "number" and count or 1, linked and Plain(link) or nil, Plain(icon))
                end
            end
        end
    end
    Keep("mail", items)
end

-- ---------- reading what's kept ----------
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function ItemName(id, link)
    local name = type(link) == "string" and link:match("%[(.-)%]")
    if name and name ~= "" then return name end
    local ok, info = pcall(GetInfo or error, id)
    if ok and type(info) == "string" then return info end
    return "item " .. id
end

-- A character's name as shown: without the realm when it's yours
function ns.Label(key, char)
    local _, myRealm = (ns.MyKey() or ""):match("^(.-)%-(.*)$")
    if char.name and char.realm == myRealm then return char.name end
    return key
end

-- Every character known: the shared count (QuietKit.Stock), which has this addon's own records in it and, for a
-- character where Quiet Bags is off, what any other Quiet addon wrote down there
function ns.Chars()
    return QuietKit.Stock.Chars()
end

-- Every kept character but this one (all of them with includeMe), sorted by name: { key, char, label }.
-- Only those on this realm and of this faction: the only ones that can mail or trade things to each other.
-- (One kept before factions were written down shows until it logs in once and gets its faction.)
function ns.Characters(includeMe)
    local me = ns.MyKey()
    local all = ns.Chars()
    local mine = me and all[me] or {}
    local list = {}
    for key, char in pairs(all) do
        local sameSide = char.realm == mine.realm and (not char.faction or not mine.faction or char.faction == mine.faction)
        if sameSide and (includeMe or key ~= me) then
            list[#list + 1] = { key = key, char = char, label = ns.Label(key, char) }
        end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return list
end

-- "bank 8, bags 4" for one item, from its counts by place
function ns.Where(counts)
    local parts = {}
    for _, where in ipairs(PLACES) do
        if (counts[where] or 0) > 0 then parts[#parts + 1] = where .. " " .. counts[where] end
    end
    if #parts == 1 then return (parts[1]:match("^%a+")) end
    return table.concat(parts, ", ")
end

-- One kept item as the window shows it: { id, link, count, name, icon, quality, classID, subclassID }
local InfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
function ns.Describe(id, item)
    local row = { id = id, link = item.link, count = item.count, name = ItemName(id, item.link), icon = item.icon }
    if not row.icon and IconOf then
        local ok, icon = pcall(IconOf, id)
        row.icon = ok and icon or nil
    end
    -- (its kind, to put like with like: class and subclass, as the game files it)
    local ok, _, _, _, _, _, classID, subclassID = pcall(InfoInstant or error, id)
    row.classID = ok and type(classID) == "number" and classID or 99
    row.subclassID = ok and type(subclassID) == "number" and subclassID or 0
    -- (its quality: in the link, the newer way "|cnIQ3:" or the older colour; else from the game)
    local link = type(item.link) == "string" and item.link or ""
    row.quality = tonumber(link:match("|cnIQ(%d+):"))
    if not row.quality then
        for quality, colour in pairs(ITEM_QUALITY_COLORS or {}) do
            if type(colour) == "table" and colour.hex and link:find(colour.hex, 1, true) then row.quality = quality end
        end
    end
    if not row.quality then
        local got, _, _, quality = pcall(GetInfo or error, id)
        row.quality = got and type(quality) == "number" and quality or nil
    end
    return row
end

-- How long ago something was seen, in plain words
function ns.Ago(at)
    if not at then return nil end
    local seconds = math.max(0, time() - at)
    if seconds < 90 then return "just now" end
    if seconds < 90 * 60 then return math.floor(seconds / 60 + 0.5) .. " min ago" end
    if seconds < 36 * 3600 then return math.floor(seconds / 3600 + 0.5) .. " h ago" end
    local days = math.floor(seconds / 86400 + 0.5)
    return days .. (days == 1 and " day ago" or " days ago")
end

-- ---------- item tooltips: "Jon-Realm: 12 (bank 8, bags 4)" ----------
local tooltipShown = setmetatable({}, { __mode = "k" }) -- (the item each tooltip has its lines for already)

local function AddLines(tooltip, id)
    id = Plain(id)
    if type(id) ~= "number" or tooltipShown[tooltip] == id or DB().tooltips == false then return end
    tooltipShown[tooltip] = id
    local added = false
    for _, entry in ipairs(ns.Characters(true)) do
        local counts, total = {}, 0
        for _, where in ipairs(PLACES) do
            local section = entry.char[where]
            local item = section and section.items and section.items[id]
            if item then
                counts[where] = item.count
                total = total + item.count
            end
        end
        if total > 0 then
            tooltip:AddLine(entry.label .. ": " .. total .. " (" .. ns.Where(counts) .. ")", 0.55, 0.75, 1)
            added = true
        end
    end
    if added then tooltip:Show() end
end

local function OnTooltip(tooltip, id)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    pcall(AddLines, tooltip, id)
end

local function HookTooltips()
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) tooltipShown[self] = nil end)
        end
    end
    -- The newer way: the game hands over the item's ID
    local processor = TooltipDataProcessor
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if processor and processor.AddTooltipPostCall and itemType then
        processor.AddTooltipPostCall(itemType, function(tooltip, data)
            if issecret(data) or type(data) ~= "table" then return end
            OnTooltip(tooltip, data.id)
        end)
        return
    end
    -- The older way: the item's link, read from the tooltip
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
                local ok, _, link = pcall(self.GetItem, self)
                link = ok and Plain(link)
                if type(link) ~= "string" then return end
                OnTooltip(self, tonumber(link:match("item:(%d+)")))
            end)
        end
    end
end
HookTooltips()

-- ---------- events ----------
local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
local MAILBOX = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo

local function OpenBank()
    bankOpen = true
    ReadBank()
    -- (and again a moment later, in case the bank's slots fill in after the window opens)
    C_Timer.After(1, ReadBank)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LOGOUT", "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
    -- (pcall: a client that doesn't know an event refuses it)
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(LOGIN_DELAY, function()
            ReadBags()
            ReadBankAway()
        end)
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LOGOUT" then
        -- (bank bags changing while the bank is open come through here too)
        ReadBags()
        ReadBank()
    elseif event == "BANKFRAME_OPENED" then
        OpenBank()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        ReadBank()
    elseif event == "MAIL_SHOW" then
        mailOpen = true
    elseif event == "MAIL_INBOX_UPDATE" then
        ReadMail()
    elseif event == "MAIL_CLOSED" then
        mailOpen = false
    else
        -- The newer way the game says a bank or mailbox opened or closed
        local kind = Plain(arg)
        local shown = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        if kind == nil then return end
        if BANKER and kind == BANKER then
            if shown and not bankOpen then OpenBank() elseif not shown then bankOpen = false end
        elseif MAILBOX and kind == MAILBOX then
            mailOpen = shown
        end
    end
end)

-- And the game's bank window itself showing, in case this client says it neither of the ways above
if BankFrame and BankFrame.HookScript then
    pcall(BankFrame.HookScript, BankFrame, "OnShow", function()
        if not bankOpen then OpenBank() end
    end)
    pcall(BankFrame.HookScript, BankFrame, "OnHide", function() bankOpen = false end)
end

-- ---------- /qbags ----------
local function Forget(name)
    name = strtrim(name or ""):lower()
    if name == "" then
        Print("say whose, like /qbags forget Mia.")
        return
    end
    -- (from here and from the shared count, where another Quiet addon may have written it down)
    local me, gone = ns.MyKey(), 0
    for key, char in pairs(ns.Chars()) do
        if key ~= me and (key:lower() == name or (char.name or ""):lower() == name) then
            DB().chars[key] = nil
            QuietKit.Stock.Forget(key)
            gone = gone + 1
        end
    end
    Print(gone > 0 and ("forgot " .. gone .. " character" .. (gone == 1 and "." or "s.")) or "no one by that name.")
    if ns.RefreshWindow then ns.RefreshWindow() end
end

SLASH_QUIETBAGS1 = "/qbags"
SlashCmdList.QUIETBAGS = function(msg)
    msg = strtrim(msg or "")
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()
    if command == "" then
        ns.ToggleWindow()
    elseif command == "help" then
        Print("the commands:")
        print("  /qbags  opens and closes the window;  /qbags <name>  opens it on that character")
        print("  /qbags options  the settings, and a macro that opens the window, for your bar or crossbar")
        print("  /qbags forget <name>  drops a character you deleted;  /qbags bank  what it reads as your bank")
    elseif command == "options" or command == "settings" then
        if not QuietKit.Open("quietbags") then
            Print("the settings are in Options, AddOns, Quiet, Quiet Bags.")
        end
    elseif command == "bank" then
        ns.BankReport()
    elseif command == "forget" then
        Forget(rest)
    else
        ns.ShowCharacter(msg)
    end
end
