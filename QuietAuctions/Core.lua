-- Quiet Auctions: steady gold from the auction house, made for a bank alt. The servers are full, gatherers flood
-- the market and plenty sells for less than a vendor pays. So it buys what's listed under vendor price and sells it to
-- a vendor; it remembers prices scan after scan; it shows which recipes pay; it posts and cancels, carefully.
--
-- What WoW Forever allows (client 1.60.1 has the newer auction house, C_AuctionHouse, not Classic's old one):
--  * buying, posting and cancelling need a press of yours, and each press does exactly ONE of them. Nothing here
--    buys, posts or cancels from a timer or an event. Looking things up (a scan, a search) may happen by itself.
--  * the full scan (C_AuctionHouse.ReplicateItems) is allowed once every 15 minutes; between them, or if it doesn't
--    answer, the scan reads the browse pages instead, one page at a gentle pace.
--  * a press can come from the window, a key (Key Bindings, AddOns), or the character macros "QA Buy", "QA Post",
--    "QA Sell" and "QA Collect" on the crossbar (Macros.lua: made from the settings page, when you ask). (QA Skip too:
--    not a purchase, only the list's order.)
--  * values can be secret in combat: anything that could be goes through issecretvalue first.
--
-- It works only on the characters you choose (roles, below): the rest of your characters don't hear from it at all.
-- And it looks things up by itself only while you're using it, never while you use the game's own auction pages
-- (AH.lua: ns.LookByItself).
local _, ns = ...

-- ---------- talking ----------
-- An answer to a command: in chat
function ns.Print(msg)
    QuietKit.Print("Quiet Auctions", msg)
end

-- Anything else: in the window's message line when it's open (Window.lua sets ns.OnMessage), else a small note that
-- fades (QuietKit.Toast), not chat
local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
ns.ICON = ICON

function ns.Say(msg)
    if ns.OnMessage and ns.OnMessage(msg) then return end
    QuietKit.Toast(msg, ICON)
end

local issecret = issecretvalue or function() return false end

-- nil for a value the game keeps secret (in combat)
function ns.Plain(value)
    if issecret(value) then return nil end
    return value
end

-- The window shows the change (Window.lua replaces this)
function ns.Refresh() end

-- Something the long lists are worked out from has changed (a scan, recipes, vendor prices, a tab chosen): they're
-- worked out again when next shown, not before
ns.version = 0
function ns.Changed()
    ns.version = ns.version + 1
end

-- ---------- settings and memory ----------
-- QuietAuctionsDB (the whole account):
--   settings: margin (% under vendor price to buy at), stacks (most stacks a press buys), floor (% over vendor price
--     the lowest post), duration (1, 2, 3: 12, 24, 48 hours), minProfit (copper: less isn't worth a press),
--     watch (Watch.lua), posting (off: Post puts up only BoEs until turned on), resale (off: Buy gets only what's
--     under vendor price until turned on), autoScan, autoOpen
--   markets = { ["realm-faction"] = { prices, scanNo, scanAt, lastFull, posted } } (Scan.lua; prices packed while
--     saved, below)
--   recipes = { [recipeID] = { name, out, n, r = { item, count, ... }, prof, by = { [name] = true } } } (Craft.lua)
--   vendorBuy = { [itemID] = what a vendor sells one for } (Vendor.lua)
--   paid = { [itemID] = what a vendor was seen to pay for one } (Vendor.lua)
--   keep = { [itemID] = true: never posted by Post } (BoE.lua)
--   chars = { ["name-realm"] = { name, realm, auctions, crafting } }: every character's roles, for the settings page
--   kit = QuietKit's marks (the welcome, what's new)
--   sell, stack, class = { [itemID] = what a vendor pays for one }, { [itemID] = stack size, if over 1 },
--     { [itemID] = item class } (below)
--   window = its place
-- QuietAuctionsCharDB (this character): roles = { auctions, crafting }, bought = { [itemID] = { n, cost, at (when
--   last bought) } }, totals, skipped (Scan.lua), and auctions, repost, vendorIt, itemProfit (Ledger.lua), mailSeen,
--   limbo (Whereabouts.lua), log (below)
local DEFAULTS = { margin = 5, stacks = 12, floor = 25, duration = 2, minProfit = 5, watch = true, posting = false,
    resale = false, autoScan = true, autoOpen = true, minimap = true, tooltip = true }

function ns.DB()
    QuietAuctionsDB = QuietAuctionsDB or {}
    local db = QuietAuctionsDB
    db.settings = db.settings or {}
    db.markets = db.markets or {}
    db.recipes = db.recipes or {}
    db.vendorBuy = db.vendorBuy or {}
    db.sell = db.sell or {}
    db.stack = db.stack or {}
    db.class = db.class or {}
    db.paid = db.paid or {}
    db.chars = db.chars or {}
    return db
end

function ns.Char()
    QuietAuctionsCharDB = QuietAuctionsCharDB or {}
    local char = QuietAuctionsCharDB
    char.bought = char.bought or {}
    char.totals = char.totals or { spent = 0, vendored = 0, profit = 0, auctionSales = 0 }
    return char
end

-- ---------- the log ----------
-- Every buy, sale and post, with what was expected and what your gold actually did (QuietAuctionsCharDB.log, the
-- last 200): so where the gold went can be read back as fact. /qah log shows it. An auction sale also has its profit
-- (what came in less what the item cost and its deposits), and a name when the item isn't known (Ledger.lua).
local LOG_SIZE = 200

local function Round(n)
    return n and math.floor(n + 0.5) or nil
end

function ns.Log(kind, id, qty, expected, change, profit, name)
    local char = ns.Char()
    char.log = char.log or {}
    local log = char.log
    log[#log + 1] = { t = time(), kind = kind, id = id, qty = qty, expected = Round(expected or 0),
        change = Round(change or 0), profit = Round(profit), name = name }
    while #log > LOG_SIZE do table.remove(log, 1) end
end

local function PrintLog()
    local log = ns.Char().log or {}
    if #log == 0 then
        ns.Print("nothing logged yet.")
        return
    end
    local sums = {}
    for _, e in ipairs(log) do sums[e.kind] = (sums[e.kind] or 0) + e.change end
    ns.Print("the last " .. math.min(#log, 15) .. " of " .. #log .. " logged (what was expected, what your gold did):")
    for i = math.max(1, #log - 14), #log do
        local e = log[i]
        print("  " .. date("%d %b %H:%M", e.t) .. "  " .. e.kind .. " " .. (e.qty or "") .. " "
            .. (e.id and ns.ItemName(e.id) or e.name or "?") .. ":  expected " .. ns.Money(e.expected) .. ", gold "
            .. ns.Money(e.change) .. (e.profit and (", profit " .. ns.Money(e.profit)) or ""))
    end
    local parts = {}
    for kind, sum in pairs(sums) do parts[#parts + 1] = kind .. " " .. ns.Money(sum) end
    print("  In all: " .. table.concat(parts, ",  "))
    if ns.ProfitLine then print("  " .. ns.ProfitLine()) end
    -- (profit per item, the best and the worst)
    local items = {}
    for id, p in pairs(ns.Char().itemProfit or {}) do items[#items + 1] = { id = id, sum = p.v + p.a, v = p.v, a = p.a } end
    table.sort(items, function(a, b) return a.sum > b.sum end)
    if #items > 0 then
        print("  Profit per item (vendor + auction):")
        for i = 1, #items do
            if i <= 6 or i > #items - 3 then
                local p = items[i]
                print("    " .. ns.ItemName(p.id) .. ": " .. ns.Money(p.sum) .. "  (" .. ns.Money(p.v) .. " + "
                    .. ns.Money(p.a) .. ")")
            end
        end
    end
end

function ns.Setting(key)
    local value = ns.DB().settings[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

function ns.SetSetting(key, value)
    ns.DB().settings[key] = value
    -- (a new margin or stack count changes what's worth buying: the list follows at once, Buy.lua)
    if (key == "margin" or key == "stacks" or key == "minProfit") and ns.BuyRulesChanged then
        ns.BuyRulesChanged()
    end
    if key == "minimap" and ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    ns.Refresh()
end

-- ---------- the price memory, packed ----------
-- Saved, each item's memory is one short line of numbers in base 36: the scan it was first seen in, then scan,
-- cheapest for one and quantity for each scan remembered ("f s p q s p q ..."). As tables of tables, ~6,000 items made
-- the saved file over a megabyte, and every character read and wrote it at every login and logout; as lines it's
-- about half that, and a character that doesn't use the memory never unpacks it. Unpacked on first use (at login, on
-- a character with a role), packed again at logout.
-- Forgotten when unpacked: an item not seen in the last FORGET_SCANS scans, or in FORGET_DAYS days.
local FORGET_SCANS = 100
local FORGET_DAYS = 30
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
ns.SCANS_KEPT = FORGET_SCANS -- (scanAt keeps as many, Scan.lua)
ns.HISTORY = 8 -- (scans remembered per item, Scan.lua)

local function Base36(n)
    n = math.floor(n or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    end
    return s
end

local function PackOne(p)
    local words = { Base36(p.f or 1) }
    for i, v in ipairs(p.h) do words[i + 1] = Base36(v) end
    return table.concat(words, " ")
end

local function UnpackOne(line)
    local p = { h = {} }
    local h = p.h
    for word in line:gmatch("%w+") do
        if not p.f then p.f = tonumber(word, 36) else h[#h + 1] = tonumber(word, 36) end
    end
    return p
end

local unpacked = {} -- [market] = true: its prices are tables now (this session)

local function UnpackMarket(market)
    unpacked[market] = true
    local prices, now, last = market.prices, time(), market.scanNo or 0
    local gone = {}
    for id, p in pairs(prices) do
        if type(p) == "string" then
            p = UnpackOne(p)
            prices[id] = p
        end
        local h = p.h
        local seen = #h >= 3 and h[#h - 2] or 0
        local at = market.scanAt[seen]
        if #h < 3 or last - seen > FORGET_SCANS or (at and now - at > FORGET_DAYS * 24 * 3600) then
            gone[#gone + 1] = id
        end
    end
    for _, id in ipairs(gone) do prices[id] = nil end
    return #gone
end

-- What the game told about an item is kept only for items still remembered somewhere (it's asked again if needed)
local function ForgetItemData()
    local db = ns.DB()
    local wanted = {}
    for _, market in pairs(db.markets) do
        for id in pairs(market.prices) do wanted[id] = true end
    end
    for id in pairs(db.sell) do
        if not wanted[id] and not ns.Char().bought[id] then db.sell[id], db.stack[id], db.class[id] = nil, nil, nil end
    end
    for id in pairs(db.class) do
        if not db.sell[id] then db.class[id] = nil end
    end
end

-- At logout: back into lines
local function PackMarkets()
    for market in pairs(unpacked) do
        for id, p in pairs(market.prices) do
            if type(p) == "table" then market.prices[id] = PackOne(p) end
        end
    end
end

-- Two memories of one market: the realm had no name for a while (QuietKit.Realm), so a second memory began beside
-- the first. One again: the one scanned last follows the other, its scans numbered on from the other's last.
local function JoinMarkets(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return b end
    local function LastScan(market)
        return type(market.scanAt) == "table" and tonumber(market.scanAt[market.scanNo or 0]) or 0
    end
    local first, second = a, b
    if LastScan(a) > LastScan(b) then first, second = b, a end
    for _, market in ipairs({ first, second }) do
        market.prices, market.scanAt, market.posted = market.prices or {}, market.scanAt or {}, market.posted or {}
        market.scanNo = market.scanNo or 0
    end
    local by = first.scanNo
    for id, p in pairs(second.prices) do
        if type(p) == "string" then p = UnpackOne(p) end
        p.f = (p.f or 1) + by
        for i = 1, #p.h, 3 do p.h[i] = p.h[i] + by end
        local old = first.prices[id]
        if type(old) == "string" then old = UnpackOne(old) end
        if old then
            local h = old.h
            for _, v in ipairs(p.h) do h[#h + 1] = v end
            local kept = {}
            for i = math.max(1, #h - ns.HISTORY * 3 + 1), #h do kept[#kept + 1] = h[i] end
            p.f, p.h = old.f or 1, kept
        end
        first.prices[id] = PackOne(p)
    end
    for s, at in pairs(second.scanAt) do first.scanAt[s + by] = at end
    first.scanNo = by + second.scanNo
    for s in pairs(first.scanAt) do
        if s <= first.scanNo - FORGET_SCANS then first.scanAt[s] = nil end
    end
    first.lastFull = math.max(first.lastFull or 0, second.lastFull or 0)
    for arg, unit in pairs(second.posted) do first.posted[arg] = unit end
    -- (lines and tables side by side now: unpacked anew when it's next asked for)
    unpacked[first], unpacked[second] = nil, nil
    return first
end

-- This realm's name as every Quiet addon knows it (never the game's own GetRealmName: it can be empty)
function ns.Realm()
    return QuietKit.Realm()
end

-- This realm and side's market (each auction house has its own prices), its memory unpacked. (Asked for thousands of
-- times while a list is worked out: found once a session.)
local current
function ns.Market()
    if current then return current end
    local db = ns.DB()
    local key = ns.Realm() .. "-" .. (UnitFactionGroup and UnitFactionGroup("player") or "?")
    local market = db.markets[key]
    if not market then
        market = { prices = {}, scanNo = 0, scanAt = {}, lastFull = 0, posted = {} }
        db.markets[key] = market
    end
    if not unpacked[market] then
        if UnpackMarket(market) > 0 then ForgetItemData() end
    end
    current = market
    return market
end

-- ---------- money ----------
local GOLD, SILVER, COPPER = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"

function ns.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. GOLD end
    if s > 0 then parts[#parts + 1] = s .. SILVER end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER end
    return sign .. table.concat(parts, " ")
end

-- ---------- items ----------
-- A scan lists thousands of different items, and the game knows few of them until asked. So:
--  * what's learned is kept: this session everything (known), and for good what a vendor pays and the stack size
--    (QuietAuctionsDB.sell, .stack): they never change, so each item is asked about once, ever
--  * the asking is gentle: a few dozen items a quarter second, never thousands at once (that flood made the game
--    drop what it had just loaded, and ask again, round and round)
--  * an answer is passed on to ns.OnItemData(id) (Scan.lua adds the item to the list)
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RequestLoad = (C_Item and C_Item.RequestLoadItemDataByID) or function() end
local ASK_EVERY, ASK_AT_ONCE = 0.25, 30

local known = {} -- [id] = { name, link, quality, stack, sell, equipLoc, classID }
local asked = {} -- [id] = true: asked about this session (not again)
local toAsk = {}

local asker = CreateFrame("Frame")
asker:Hide()
local sinceAsk = 0
asker:SetScript("OnUpdate", function(self, elapsed)
    sinceAsk = sinceAsk + elapsed
    if sinceAsk < ASK_EVERY then return end
    sinceAsk = 0
    for _ = 1, ASK_AT_ONCE do
        local id = table.remove(toAsk)
        if not id then
            self:Hide()
            return
        end
        pcall(RequestLoad, id)
    end
end)

local function Ask(id)
    if asked[id] then return end
    asked[id] = true
    toAsk[#toAsk + 1] = id
    asker:Show()
end

-- Items still waiting to be asked about (the window says so while there are many)
function ns.ItemsToAsk()
    return #toAsk
end

local function Read(id)
    local ok, name, link, quality, level, _, _, _, stack, equipLoc, _, sellPrice, classID = pcall(GetInfo, id)
    if not ok or not name then return nil end
    local info = { name = name, link = link, quality = quality, stack = math.max(1, stack or 1), sell = sellPrice or 0,
        equipLoc = equipLoc or "", classID = classID, level = level }
    known[id] = info
    local db = ns.DB()
    db.sell[id] = info.sell
    if info.stack > 1 then db.stack[id] = info.stack end
    if classID then db.class[id] = classID end
    return info
end

-- name, link, quality, stack size, vendor price, where it's worn ("" for nothing), item class, item level. nil while
-- the game hasn't the item's data yet (asked for: ns.OnItemData follows).
function ns.ItemInfo(id)
    if not id then return nil end
    local info = known[id] or Read(id)
    if not info then
        Ask(id)
        return nil
    end
    return info.name, info.link, info.quality, info.stack, info.sell, info.equipLoc, info.classID, info.level
end

-- What a vendor pays for one, or nil while unknown
-- (what a vendor was seen to pay for one when Sell sold it wins over the game's item data: Vendor.lua)
function ns.SellPrice(id)
    local db = ns.DB()
    if db.paid[id] then return db.paid[id] end
    local kept = db.sell[id]
    if kept then return kept end
    local name, _, _, _, sellPrice = ns.ItemInfo(id)
    if not name then return nil end
    return sellPrice
end

-- Its item class (7 trade goods, 2 weapon...), or nil while unknown
function ns.ItemClass(id)
    local kept = ns.DB().class[id]
    if kept then return kept end
    local name, _, _, _, _, _, classID = ns.ItemInfo(id)
    return name and classID or nil
end

function ns.StackSize(id)
    local db = ns.DB()
    if db.sell[id] then return db.stack[id] or 1 end
    local name, _, _, stack = ns.ItemInfo(id)
    return name and stack or 1
end

local itemEvents = CreateFrame("Frame")
itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemEvents:SetScript("OnEvent", function(_, _, id, success)
    -- (only ours; the game answers for every tooltip and bag too)
    if not id or not asked[id] or known[id] or success == false then return end
    if Read(id) and ns.OnItemData then ns.OnItemData(id) end
end)

-- The name in its quality's colour
function ns.ItemName(id)
    local name, _, quality = ns.ItemInfo(id)
    if not name then return "item " .. tostring(id) end
    local colour = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if colour and colour.hex then return colour.hex .. name .. "|r" end
    return name
end

-- ---------- bags ----------
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local NumFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local SlotInfo = C_Container and C_Container.GetContainerItemInfo

-- Goes up each time the bags change (lists worked out from the bags are kept until then: BoE.lua, Post.lua)
ns.bagVersion = 0

-- What's in a bag slot: { itemID, stackCount, isLocked, isBound, hasNoValue, hyperlink } or nil
function ns.Slot(bag, slot)
    if not SlotInfo then return nil end
    local ok, info = pcall(SlotInfo, bag, slot)
    if not ok or type(info) ~= "table" or not info.itemID then return nil end
    return info
end

-- fn(bag, slot, info) for every filled slot in the backpack and bags
function ns.EachSlot(fn)
    -- (the reagent bag too: QuietKit.Stock knows which containers are bags)
    local bags = QuietKit.Stock and QuietKit.Stock.BagIDs()
    if not bags then
        bags = {}
        for bag = 0, NUM_BAG_SLOTS or 4 do bags[#bags + 1] = bag end
    end
    for _, bag in ipairs(bags) do
        for slot = 1, (NumSlots and NumSlots(bag)) or 0 do
            local info = ns.Slot(bag, slot)
            if info then fn(bag, slot, info) end
        end
    end
end

-- Empty slots in ordinary bags (not a herb or mining bag)
function ns.FreeSlots()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n, family = 0, 0
        if NumFree then n, family = NumFree(bag) end
        if (family or 0) == 0 then free = free + (n or 0) end
    end
    return free
end

-- ---------- a long job a little each frame ----------
-- fn(i) for i = first .. last, perFrame at a time, then done(): a full scan of tens of thousands of auctions
-- doesn't freeze the game. (The frames that do it are used again, not made anew for each job.)
local idleRunners = {}
function ns.Chunks(first, last, perFrame, fn, done)
    local runner = table.remove(idleRunners) or CreateFrame("Frame")
    local i = first
    runner:SetScript("OnUpdate", function(self)
        local stop = math.min(last, i + perFrame - 1)
        for k = i, stop do fn(k) end
        i = stop + 1
        if i > last then
            self:SetScript("OnUpdate", nil)
            idleRunners[#idleRunners + 1] = self
            done()
        end
    end)
end

-- ---------- presses ----------
-- A macro's /click can arrive on both edges of a key: one press, one action. The last press also says you're using
-- Quiet Auctions now (AH.lua: it looks things up by itself a while after one, even with its window closed).
local lastPress = {}
ns.pressedAt = 0
function ns.Press(kind)
    local now = GetTime()
    if lastPress[kind] and now - lastPress[kind] < 0.25 then return false end
    lastPress[kind] = now
    ns.pressedAt = now
    return true
end

-- ---------- where we are ----------
-- Set by the open and close events (AH.lua, Vendor.lua, Mail.lua)
ns.at = { auction = false, merchant = false, mail = false }

-- A mail subject the game words from a format ("Auction expired: %s") as a pattern that matches it, the item's name
-- captured; nil for no format
function ns.MailPattern(format)
    if type(format) ~= "string" then return nil end
    local escaped = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

-- ---------- roles ----------
-- Each character does what you choose on its settings page (Options.lua), kept for the character
-- (QuietAuctionsCharDB.roles) and in a list for the whole account (QuietAuctionsDB.chars), so the page can say which of
-- your characters does what:
--   auctions: it buys, sells, posts and collects the mail. At the auction house it scans and watches (while you use
--     it: AH.lua), its window opens by itself where there's work, and the presses (macros, keys) work.
--   crafting: the recipes in its profession windows count in the Crafting tab and in Prices ("you craft it")
--   neither: Quiet Auctions rests. It listens to nothing, opens nothing, searches nothing and says nothing.
-- A character that had used Quiet Auctions before roles came starts with auctions (and crafting, if its recipes were
-- noted), so nothing changes for it. A new character starts with neither.
local roles = {}

-- role: "auctions", "crafting", or "any" (either)
function ns.Does(role)
    if role == "any" then return (roles.auctions or roles.crafting) and true or false end
    return roles[role] and true or false
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. ns.Realm()
end

-- This character's line in the account's list (written at login, once the realm's name is settled, and when its
-- roles change)
local function Roster()
    local db = ns.DB()
    db.chars[CharKey()] = { name = UnitName("player"), realm = ns.Realm(), auctions = roles.auctions,
        crafting = roles.crafting }
end

-- Every character's roles: { { name, realm, auctions, crafting, me } }, this one first, then by name
function ns.Characters()
    local list, me = {}, CharKey()
    for key, c in pairs(ns.DB().chars) do
        list[#list + 1] = { name = c.name or key, realm = c.realm, auctions = c.auctions, crafting = c.crafting,
            me = key == me }
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        return a.name < b.name
    end)
    return list
end

-- The names of the characters that craft (their recipes count): { [name] = true }
function ns.Crafters()
    local names = {}
    for _, c in pairs(ns.DB().chars) do
        if c.crafting and c.name then names[c.name] = true end
    end
    return names
end

-- Every event frame of ours, with the role it works for: it hears its events only on a character with that role
local listeners = {}

function ns.Listen(role, events, handler)
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", handler)
    listeners[#listeners + 1] = { frame = frame, role = role, events = events }
    return frame
end

local function Tune()
    for _, l in ipairs(listeners) do
        local on = ns.Does(l.role)
        for _, event in ipairs(l.events) do
            if on then
                pcall(l.frame.RegisterEvent, l.frame, event)
            else
                pcall(l.frame.UnregisterEvent, l.frame, event)
            end
        end
    end
end

-- From the settings page. (Takes hold at once; at an auction house, vendor or mailbox already open, from the next
-- visit.)
function ns.SetRoles(auctions, crafting)
    roles.auctions, roles.crafting = auctions or nil, crafting or nil
    ns.Char().roles = { auctions = roles.auctions, crafting = roles.crafting }
    Roster()
    Tune()
    ns.Changed()
    if not roles.auctions then
        ns.at.auction, ns.at.merchant, ns.at.mail = false, false, false
        if ns.HideWindow then ns.HideWindow() end
    end
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    ns.Refresh()
end

-- The presses (macros, keys, commands) do auction work only on an auctions character; elsewhere one says so
function ns.OnDuty()
    if roles.auctions then return true end
    ns.Say("This character doesn't do the auction work: give it the Auctions role on Quiet Auctions' settings page "
        .. "(/qah settings).")
    return false
end

-- What it did before there were roles: anything kept for this character (its bought list, its log, its macros...)
local function UsedBefore(char)
    if type(char) ~= "table" then return false end
    for key in pairs(char) do
        if key ~= "roles" then return true end
    end
    return false
end

-- Recipes noted with who = a name (before roles): by = { [name] = true }, as a recipe can be known by several
local function MoveRecipes()
    for _, rec in pairs(ns.DB().recipes) do
        if rec.who then
            rec.by = rec.by or {}
            rec.by[rec.who] = true
            rec.who = nil
        end
    end
end

local function FirstRoles(char)
    local me = UnitName("player")
    local first = { auctions = UsedBefore(char) or nil }
    for _, rec in pairs(ns.DB().recipes) do
        if rec.by and me and rec.by[me] then first.crafting = true end
    end
    return first
end

-- ---------- /qah ----------
local function Help()
    ns.Print("every command (the window has the same buttons; its settings, this character's role and the macros are "
        .. "on its page in Options, AddOns, Quiet: /qah settings):")
    print("  /qah  opens or closes the window;  /qah settings  its settings page")
    print("  /qah scan  reads the auction house (a full scan when allowed, else the pages)")
    print("  /qah buy  does what the Buy button says: buys the top of the Buy queue (looked up ahead, so a press buys)")
    print("  /qah skip  what Skip this one does: Buy's next item to the bottom until you log out;  /qah unskip")
    print("  /qah post  does what the Post button says: puts up the top of the Post queue (BoEs first)")
    print("  /qah sell  at a vendor: sells what was bought for vendoring (never anything else)")
    print("  /qah collect  at a mailbox: takes gold and items until the bags are full (again stops it)")
    print("  /qah takedown  checks whether anyone lists your auctions for less; again takes one down (deposit lost)")
    print("  /qah keep  what Post never puts up;  /qah keep <item link>  keeps it or forgets it;  /qah keep clear")
    print("  /qah vendor <item link>  sell it to a vendor, not at auction (again: back to the auction house)")
    print("  /qah resale on | off  Buy also gets gear under its usual auction price, to resell (risky; off)")
    print("  /qah prices  what's selling, what pays over vendor price, what's rare;  /qah craft  recipes that pay")
    print("  /qah crates  the cheapest bundle to fill each profession crate (Waylaid Crate) at today's prices")
    print("  /qah price <item link>  its price at the last scan (item tooltips say it too: /qah tooltip on | off)")
    print("  /qah plan <item link> 20  adds 20 of it to the plan (the Plan tab: have, make, buy);  /qah plan clear")
    print("  /qah margin 5  buy only at least 5% under vendor price")
    print("  /qah stacks 12  the most stacks one press buys")
    print("  /qah minprofit 5  buy only when a purchase makes at least 5 copper")
    print("  /qah watch on | off  between full scans, keep looking at the items that pay (on)")
    print("  /qah floor 25  never post under vendor price + 25%")
    print("  /qah duration 12 | 24 | 48  hours an auction runs")
    print("  /qah autoscan on | off  full scans by themselves at the auction house, every 15 minutes (on)")
    print("  /qah autoopen on | off  open the window where there's work: auction house, mailbox, vendor (on)")
    print("  /qah minimap on | off  the button on the minimap that opens and closes the window (on)")
    print("  /qah macros  makes the macros QA Buy, QA Skip, QA Post, QA Sell and QA Collect (or drag them from the page)")
    print("  /qah log  every buy, sale, post and auction sale: what was expected, what your gold did, profit per item")
    print("  /qah posting on | off  Post puts up stacks from your bags too, not only BoEs (off)")
    print("  /qah forget  clears the list of what was bought for vendoring, and the profit totals")
    print("  /qah trace  says in chat what's asked of the auction house and what it answers (again: off)")
end

local function Number(msg, word, low, high)
    local n = tonumber(msg:match("^" .. word .. "%s+(%d+)$"))
    if not n then return nil end
    return math.max(low, math.min(high, n))
end

function ns.OpenSettings()
    if not QuietKit.Open("quietauctions") then
        ns.Print("its settings: Options, AddOns, Quiet, Quiet Auctions" .. (QuietKit.PadMode() and
            " (or Improved Forever's Quiet tab)." or "."))
    end
end

-- The commands that do auction work: only on an auctions character
local DUTY = { scan = true, buy = true, next = true, skip = true, unskip = true, sell = true, collect = true,
    post = true, boe = true, boes = true, takedown = true, cancel = true }

SLASH_QUIETAUCTIONS1 = "/qah"
SLASH_QUIETAUCTIONS2 = "/quietauctions"
SlashCmdList.QUIETAUCTIONS = function(msg)
    msg = strtrim((msg or ""):lower())
    local n
    if DUTY[msg] and not roles.auctions then
        ns.Print("this character doesn't do the auction work. Its role is on the settings page: /qah settings.")
        return
    end
    if msg == "" then
        if not ns.Does("any") then
            ns.Print("rests on this character. Choose what it does (Auctions, Crafting) on the settings page.")
            ns.OpenSettings()
        elseif ns.ToggleWindow then
            ns.ToggleWindow()
        end
    elseif msg == "scan" then
        ns.Scan(true)
    elseif msg == "buy" or msg == "next" then
        ns.BuyPress()
    elseif msg == "skip" then
        ns.SkipTop()
    elseif msg == "unskip" then
        local n = ns.UnskipAll()
        ns.SortCandidates()
        ns.Print(n > 0 and (n .. " skipped item" .. (n > 1 and "s are" or " is") .. " back in place on the list.")
            or "nothing was skipped.")
        ns.Refresh()
        if ns.Prepare then C_Timer.After(0.5, ns.Prepare) end
    elseif msg == "sell" then
        ns.Sell()
    elseif msg == "collect" then
        ns.Collect()
    elseif msg == "post" or msg == "boe" or msg == "boes" then
        ns.PostPress()
    elseif msg == "takedown" or msg == "cancel" then
        ns.CancelNext()
    elseif msg == "settings" or msg == "options" or msg == "config" then
        ns.OpenSettings()
    elseif msg:match("^resale") then
        local word = msg:match("%s+(%a+)$")
        if word == "on" or word == "off" then
            ns.SetSetting("resale", word == "on")
            ns.Changed()
        end
        ns.Print("buying to resell (risky) is " .. (ns.Setting("resale") and "on" or "off") .. ".")
    elseif msg:match("^vendor") then
        local id = tonumber(msg:match("item:(%d+)"))
        if id then
            local now = not ns.Char().vendorIt or not ns.Char().vendorIt[id]
            ns.VendorIt(id, now)
            ns.Print(ns.ItemName(id) .. (now and " goes to a vendor (Sell), not the auction house."
                or " may go to the auction house again when it pays more there."))
        else
            ns.Print("/qah vendor <item link> (shift-click the item into the chat line).")
        end
    elseif msg:match("^keep") then
        ns.KeepCommand(strtrim(msg:sub(5)))
        if ns.ShowTab and ns.Does("any") then ns.ShowTab("post") end
    elseif msg == "prices" then
        ns.PrintPrices()
        if ns.ShowTab and ns.Does("any") then ns.ShowTab("prices") end
    elseif msg == "craft" or msg == "crafting" then
        ns.PrintCrafting()
        if ns.ShowTab and ns.Does("any") then ns.ShowTab("craft") end
    elseif msg:match("^minimap") then
        local word = msg:match("%s+(%a+)$")
        if word == "on" or word == "off" then
            ns.SetSetting("minimap", word == "on")
        elseif msg == "minimap" then
            ns.SetSetting("minimap", not ns.Setting("minimap"))
        end
        ns.Print("the minimap button is " .. (ns.Setting("minimap") and "on" or "off")
            .. (ns.Does("any") and "." or " (shown only on a character with a role)."))
    elseif msg:match("^price") then
        local id = tonumber(msg:match("item:(%d+)"))
        if id then ns.PrintPrice(id) else ns.Print("/qah price <item link> (shift-click the item into the chat line).") end
    elseif msg:match("^tooltip") then
        local word = msg:match("%s+(%a+)$")
        if word == "on" or word == "off" then ns.SetSetting("tooltip", word == "on") end
        ns.Print("prices in item tooltips are " .. (ns.Setting("tooltip") and "on" or "off") .. ".")
    elseif msg:match("^plan") then
        ns.PlanCommand(strtrim(msg:sub(5)))
        if ns.ShowTab and ns.Does("any") then ns.ShowTab("plan") end
    elseif msg == "crates" or msg == "crate" then
        ns.PrintCrates()
        if ns.ShowTab and ns.Does("any") then ns.ShowTab("crates") end
    elseif msg == "macros" or msg == "macro" then
        ns.MakeMacros()
    elseif msg == "log" then
        PrintLog()
    elseif msg:match("^posting") then
        local word = msg:match("%s+(%a+)$")
        if word == "on" or word == "off" then ns.SetSetting("posting", word == "on") end
        ns.Print("posting is " .. (ns.Setting("posting") and "on" or "off") .. ".")
    elseif msg == "forget" then
        -- (the bought list and the totals from scratch: for counts that went wrong)
        local char = ns.Char()
        char.bought = {}
        char.limbo = nil
        char.totals = { spent = 0, vendored = 0, profit = 0, auctionSales = 0 }
        char.itemProfit = {}
        ns.Print("forgot what was bought and the totals. Sell won't sell anything until Buy buys again.")
        ns.Refresh()
    elseif msg == "trace" then
        ns.DB().trace = not ns.DB().trace or nil
        ns.Print("trace " .. (ns.DB().trace and "on: look-ups are told in chat." or "off."))
    elseif msg:match("^margin") then
        n = Number(msg, "margin", 0, 90)
        if n then ns.SetSetting("margin", n) end
        ns.Print("buys only at least " .. ns.Setting("margin") .. "% under what a vendor pays.")
    elseif msg:match("^stacks") then
        n = Number(msg, "stacks", 1, 100)
        if n then ns.SetSetting("stacks", n) end
        ns.Print("one press buys at most " .. ns.Setting("stacks") .. " stacks.")
    elseif msg:match("^minprofit") then
        n = Number(msg, "minprofit", 1, 1000000)
        if n then ns.SetSetting("minProfit", n) end
        ns.Print("buys only when a purchase makes at least " .. ns.Money(ns.Setting("minProfit")) .. ".")
    elseif msg:match("^watch") then
        local word = msg:match("%s+(%a+)$")
        if word == "on" or word == "off" then ns.SetSetting("watch", word == "on") end
        ns.Print("the watch is " .. (ns.Setting("watch") and "on" or "off") .. ".")
    elseif msg:match("^floor") then
        n = Number(msg, "floor", 0, 500)
        if n then ns.SetSetting("floor", n) end
        ns.Print("never posts under vendor price + " .. ns.Setting("floor") .. "%.")
    elseif msg:match("^duration") then
        n = tonumber(msg:match("^duration%s+(%d+)$"))
        local d = ({ [12] = 1, [24] = 2, [48] = 3 })[n or 0]
        if d then ns.SetSetting("duration", d) end
        ns.Print("auctions run " .. ({ 12, 24, 48 })[ns.Setting("duration")] .. " hours.")
    elseif msg:match("^autoscan") or msg:match("^autoopen") then
        local key = msg:match("^autoscan") and "autoScan" or "autoOpen"
        local word = msg:match("%s+(%a+)$")
        if word == "on" or word == "off" then ns.SetSetting(key, word == "on") end
        ns.Print(key .. " is " .. (ns.Setting(key) and "on" or "off") .. ".")
    else
        Help()
    end
end

-- ---------- loading and leaving ----------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "QuietAuctions" then return end
        self:UnregisterEvent("ADDON_LOADED")
        -- (a fresh install: nothing saved yet, so QuietKit says hello rather than what's new)
        local fresh = QuietAuctionsDB == nil
        local db = ns.DB()
        if not db.kit then db.kit = fresh and {} or { quietWelcomed = true } end
        MoveRecipes()
        -- (worked out before ns.Char() adds its empty lists, which would look like use)
        local first = not (QuietAuctionsCharDB and QuietAuctionsCharDB.roles) and FirstRoles(QuietAuctionsCharDB)
        local char = ns.Char()
        if first then char.roles = first end
        roles.auctions, roles.crafting = char.roles.auctions, char.roles.crafting
        Tune()
        if ns.RegisterPage then ns.RegisterPage() end
    elseif event == "PLAYER_LOGIN" then
        -- (what was kept while the realm had no name is this realm's: the characters, and the two price memories
        -- made one)
        local db = ns.DB()
        QuietKit.RealmFold(db.chars)
        if QuietKit.RealmFold(db.markets, true, JoinMarkets) > 0 then current = nil end
        Roster()
        -- (the price memory unpacked while the loading screen is still up, on a character that uses it)
        if ns.Does("any") then ns.Market() end
    elseif event == "PLAYER_LOGOUT" then
        PackMarkets()
    end
end)

-- The bags changed (on a character that does the auction work: its lists are the ones read from the bags)
ns.Listen("auctions", { "BAG_UPDATE_DELAYED" }, function()
    ns.bagVersion = ns.bagVersion + 1
end)
