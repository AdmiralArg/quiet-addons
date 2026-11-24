-- The plan: things you want (20 Copper Bar for a crate, 5 Bolt of Silk Cloth...), and what that takes:
--  * what you have already, on any of your characters on this realm and side: their bags, bank and mail as Quiet Bags
--    last saw them (QuietBagsDB; without Quiet Bags, only this character's bags and bank), and mail you've sent
--    them that their mailbox hasn't been seen with since
--  * for the rest, make or buy, whichever is cheaper at today's prices: made when a character with the Crafting role
--    knows a recipe for it and its materials cost less than buying it (or it isn't for sale), and then the same for
--    those materials (ore for the bars), a few steps deep
--  * and who does what: a recipe is made by a character that knows it (this one if it does), buying is done by the
--    character with the Auctions role (this one if it has it), and what you want ends up with the character that
--    put it in the plan. So the send list: what each character mails to which, out of its bank or mailbox first
--    where that's where it is.
-- Prices as everywhere here: the last scan's cheapest for one, or what a vendor sells it for.
-- Kept for the whole account (QuietAuctionsDB.plan = { { id, n, step, who } }, in the order added), so the crafter and
-- the bank alt see one plan. Added from "Plan this" under the profession window (PlanButton.lua), the Plan buttons in
-- the Crafting and Crates tabs, or /qah plan <item link> 20. Once it's all in the bags of the character it's for, it's
-- off the plan by itself.
local _, ns = ...

local DEPTH = 4 -- (how many steps of making-from-materials it follows: thorium bars from ore is one)
local SENT_DAYS = 30 -- (mail comes back after this long: forgotten then)
local REMIND_SHOWN = 3

-- (the newer clients have only C_Item's: the old name is gone)
local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local function Plan()
    local db = ns.DB()
    db.plan = db.plan or {}
    return db.plan
end

local function MyName()
    return UnitName("player") or "?"
end

local function Find(id)
    for i, goal in ipairs(Plan()) do
        if goal.id == id then return goal, i end
    end
end

-- Done: what this character wanted is all in its bags now, so it's off the plan (its bank or mail don't count: it's
-- there once it's in the bags). Checked as the bags change, and when the plan does.
local function TakeDone()
    local me, plan, gone = MyName(), Plan(), {}
    for i = #plan, 1, -1 do
        local goal = plan[i]
        if (goal.who or me) == me and (ItemCount(goal.id) or 0) >= goal.n then
            table.remove(plan, i)
            table.insert(gone, 1, goal.n .. " " .. ns.ItemName(goal.id))
        end
    end
    if #gone == 0 then return false end
    ns.Changed()
    ns.Refresh()
    ns.Say(table.concat(gone, ", ") .. (#gone > 1 and " are" or " is") .. " in your bags: off the plan.")
    return true
end

-- More of it in the plan: n (and n is its step for the + and - buttons, the first time). It's for this character.
function ns.PlanAdd(id, n)
    n = math.max(1, math.ceil(n or 1))
    local goal = Find(id)
    if goal then
        goal.n = goal.n + n
    else
        goal = { id = id, n = n, step = n, who = MyName() }
        table.insert(Plan(), goal)
    end
    -- (all in your bags already: nothing to plan)
    if (goal.who or MyName()) == MyName() and (ItemCount(id) or 0) >= goal.n then
        local _, i = Find(id)
        table.remove(Plan(), i)
        ns.Say("You have " .. (ItemCount(id) or 0) .. " " .. ns.ItemName(id) .. " in your bags already: not planned.")
    end
    ns.Changed()
    ns.Refresh()
    if not Find(id) then return end
    ns.Say(goal.n .. " " .. ns.ItemName(id) .. " in the plan (the Plan tab).")
end

-- One step more (dir 1) or less (-1); none left: out of the plan
function ns.PlanStep(id, dir)
    local goal, i = Find(id)
    if not goal then return end
    goal.n = goal.n + dir * (goal.step or 1)
    if goal.n <= 0 then table.remove(Plan(), i) end
    ns.Changed()
    ns.Refresh()
    TakeDone()
end

function ns.PlanClear()
    ns.DB().plan = {}
    ns.Changed()
    ns.Refresh()
end

-- ---------- your characters ----------
-- Quiet Bags' saved characters on this realm and side: { [key "Name-Realm"] = entry }, or nil without Quiet Bags
local function BagChars()
    -- (the shared count: QuietKit.Stock, kept on every character with any Quiet addon on, Quiet Bags or not)
    local qb = QuietKit.Stock and QuietKit.Stock.Chars()
    if not qb then return nil end
    local list, myRealm, myFaction = {}, ns.Realm(), UnitFactionGroup("player")
    for key, char in pairs(qb) do
        if type(char) == "table" and char.realm == myRealm
            and (not char.faction or not myFaction or char.faction == myFaction) then
            list[key] = char
        end
    end
    return list
end

local function NameOf(key, char)
    return char.name or key:match("^[^-]+") or key
end

-- One of your characters on this realm by name, any case ("mia" is Mia): its name as written, or nil
local function OwnName(text)
    text = type(text) == "string" and text:match("^[^-]+") or nil
    if not text or text == "" then return nil end
    local lower = text:lower()
    for key, char in pairs(BagChars() or {}) do
        local name = NameOf(key, char)
        if name:lower() == lower then return name end
    end
    for _, c in ipairs(ns.Characters()) do
        if (not c.realm or c.realm == ns.Realm()) and c.name and c.name:lower() == lower then return c.name end
    end
    return nil
end

-- ---------- mail on its way ----------
-- Mail to your own characters is remembered (QuietAuctionsDB.sent = { { to, at, items = { [itemID] = n } } }) and
-- counted as in the recipient's mailbox until Quiet Bags has seen that mailbox since: so the plan doesn't take what you
-- sent for gone.
local function Sent()
    local db = ns.DB()
    db.sent = db.sent or {}
    return db.sent
end

-- When Quiet Bags last saw that character's mailbox (0: never)
local function MailSeen(name)
    for key, char in pairs(BagChars() or {}) do
        if NameOf(key, char) == name then return char.mail and char.mail.at or 0 end
    end
    return 0
end

local function OnItsWay(s)
    return time() - s.at < SENT_DAYS * 86400 and MailSeen(s.to) < s.at
end

local outgoing -- (what the mail being sent carries: kept when the game says it went)

local function NoteSending(to)
    outgoing = nil
    local name = OwnName(ns.Plain(to))
    if not name or name == MyName() then return end
    local items, any = {}, false
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        local ok, _, itemID, _, count = pcall(GetSendMailItem, i)
        if ok and itemID then
            items[itemID] = (items[itemID] or 0) + (count or 1)
            any = true
        end
    end
    if any then outgoing = { to = name, items = items } end
end

if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", function(to) pcall(NoteSending, to) end)
end

-- (on every character, a role or not: the bank alt sends without one)
local mailEvents = CreateFrame("Frame")
mailEvents:RegisterEvent("MAIL_SEND_SUCCESS")
mailEvents:RegisterEvent("MAIL_FAILED")
mailEvents:RegisterEvent("PLAYER_LOGIN")
mailEvents:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SEND_SUCCESS" then
        if outgoing then
            outgoing.at = time()
            table.insert(Sent(), outgoing)
            outgoing = nil
            ns.Changed()
            ns.Refresh()
        end
    elseif event == "MAIL_FAILED" then
        outgoing = nil
    else
        -- (what has arrived, or is long gone, forgotten)
        local kept = {}
        for _, s in ipairs(Sent()) do
            if OnItsWay(s) then kept[#kept + 1] = s end
        end
        ns.DB().sent = kept
    end
end)

-- ---------- what you have ----------
local PLACES = { "bags", "bank", "mail" }

-- Every place it is: { { who, where ("bags", "bank", "mail"), count } }, this character's bags first, then its bank
-- and mail, then the others'. This character's bags as they are now; the rest as last seen; and mail on its way as in
-- the recipient's mailbox.
local function Places(id)
    local me = MyName()
    local mine, others = {}, {}
    local bags = ItemCount(id) or 0
    if bags > 0 then mine[1] = { who = me, where = "bags", count = bags } end
    local chars = BagChars()
    if not chars then
        local bank = (ItemCount(id, true) or 0) - bags
        if bank > 0 then mine[#mine + 1] = { who = me, where = "bank", count = bank } end
    end
    for key, char in pairs(chars or {}) do
        local name = NameOf(key, char)
        for _, where in ipairs(PLACES) do
            local item = not (name == me and where == "bags") and type(char[where]) == "table"
                and type(char[where].items) == "table" and char[where].items[id]
            if item and (item.count or 0) > 0 then
                local place = { who = name, where = where, count = item.count }
                if name == me then mine[#mine + 1] = place else others[#others + 1] = place end
            end
        end
    end
    for _, s in ipairs(Sent()) do
        local n = s.items[id]
        if n and OnItsWay(s) then
            local place = { who = s.to, where = "mail", count = n }
            if s.to == me then mine[#mine + 1] = place else others[#others + 1] = place end
        end
    end
    table.sort(others, function(a, b) return a.who < b.who end)
    for _, p in ipairs(others) do mine[#mine + 1] = p end
    return mine
end

local function PlaceText(p)
    if p.who == MyName() then return p.where == "bags" and "your bags" or ("your " .. p.where) end
    return p.who .. "'s " .. p.where
end

-- ---------- who does what ----------
-- Who makes a recipe: this character if it knows it, else the first crafter (by name) that does
local function Maker(rec)
    local me = MyName()
    if rec.by and rec.by[me] then return me end
    local crafters, names = ns.Crafters(), {}
    for name in pairs(rec.by or {}) do
        if crafters[name] then names[#names + 1] = name end
    end
    table.sort(names)
    return names[1] or me
end

-- Who buys at the auction house: this character if it has the Auctions role, else the first (by name) that has
local function Buyer()
    for _, c in ipairs(ns.Characters()) do -- (this character first)
        if c.auctions and (not c.realm or c.realm == ns.Realm()) then return c.name end
    end
    return MyName()
end

-- ---------- working it out ----------
-- { goals = { { goal, have, make, buy, from = { place texts } } },
--   moves = { { id, count, from, to, where ("bank", "mail", "bought", "made"; "bags" only between characters) } },
--   make = { { rec, batches, maker } } (materials first), buy = { { id, count, each, via } }, buyer, total, unpriced }
local function Solve()
    local me, buyer = MyName(), Buyer()
    local pools = {} -- [id] = { places, each with what's left }
    local moves, moveIndex, makeList, makeIndex, buyList, buyIndex = {}, {}, {}, {}, {}, {}

    -- Something has to go from one character to another, or out of a bank or mailbox
    local function Move(id, count, from, to, where)
        if from == to and where ~= "bank" and where ~= "mail" then return end
        local key = id .. ":" .. from .. ":" .. to .. ":" .. where
        local e = moveIndex[key]
        if not e then
            e = { id = id, count = 0, from = from, to = to, where = where }
            moveIndex[key] = e
            moves[#moves + 1] = e
        end
        e.count = e.count + count
    end

    -- Take up to n from what you have, for the character `to`
    local function Take(id, n, to)
        local pool = pools[id]
        if not pool then
            pool = Places(id)
            pools[id] = pool
        end
        local taken, from = 0, {}
        for _, p in ipairs(pool) do
            if taken >= n then break end
            local use = math.min(p.count, n - taken)
            if use > 0 then
                p.count = p.count - use
                taken = taken + use
                from[#from + 1] = use .. " in " .. PlaceText(p)
                Move(id, use, p.who, to, p.where)
            end
        end
        return taken, from
    end

    local function Buy(id, n, to)
        local e = buyIndex[id]
        if not e then
            local each, via = ns.UnitCost(id)
            e = { id = id, count = 0, each = each, via = via }
            buyIndex[id] = e
            buyList[#buyList + 1] = e
        end
        e.count = e.count + n
        -- (what a vendor sells, the one who needs it buys)
        if e.via ~= "vendor" then Move(id, n, buyer, to, "bought") end
    end

    local Need
    -- Make n for `to`: the recipe's batches, its materials needed first (so they come first in the list)
    local function Make(rec, n, depth, to)
        local maker = Maker(rec)
        local batches = math.ceil(n / math.max(rec.n or 1, 0.01))
        for i = 1, #rec.r, 2 do Need(rec.r[i], rec.r[i + 1] * batches, depth + 1, maker) end
        local e = makeIndex[rec]
        if not e then
            e = { rec = rec, batches = 0, maker = maker }
            makeIndex[rec] = e
            makeList[#makeList + 1] = e
        end
        e.batches = e.batches + batches
        Move(rec.out, n, maker, to, "made")
    end

    -- Have it, make it or buy it, for the character `to`: how many of each
    function Need(id, n, depth, to)
        local have, from = Take(id, n, to)
        local rest = n - have
        if rest <= 0 then return have, 0, 0, from end
        local buyEach = ns.UnitCost(id)
        local craftEach, rec = ns.CraftCost(id)
        if not rec then rec = ns.RecipeFor(id) end
        local make = rec and depth < DEPTH and (not buyEach or (craftEach and craftEach < buyEach))
        if make then
            Make(rec, rest, depth, to)
            return have, rest, 0, from
        end
        Buy(id, rest, to)
        return have, 0, rest, from
    end

    local result = { goals = {}, moves = moves, make = makeList, buy = buyList, buyer = buyer, total = 0, unpriced = 0 }
    for _, goal in ipairs(Plan()) do
        local have, make, buy, from = Need(goal.id, goal.n, 0, goal.who or me)
        result.goals[#result.goals + 1] = { goal = goal, have = have, make = make, buy = buy, from = from }
    end
    for _, e in ipairs(buyList) do
        if e.each then
            result.total = result.total + e.each * e.count
        else
            result.unpriced = result.unpriced + 1
        end
    end
    return result
end

-- ---------- for the window ----------
local function GoalStatus(g)
    local parts = {}
    if g.have > 0 then parts[#parts + 1] = (g.have >= g.goal.n and "have all " or "have ") .. g.have end
    if g.make > 0 then parts[#parts + 1] = "make " .. g.make end
    if g.buy > 0 then parts[#parts + 1] = "buy " .. g.buy end
    return table.concat(parts, ", ")
end

local function BuyText(e)
    if not e.each then return "no price yet" end
    return ns.Money(e.each * e.count) .. (e.via == "vendor" and " at a vendor" or "") .. " (" .. ns.Money(e.each)
        .. " each)"
end

local function Materials(rec, batches)
    local parts = {}
    for i = 1, #rec.r, 2 do parts[#parts + 1] = (rec.r[i + 1] * batches) .. " " .. ns.ItemName(rec.r[i]) end
    return table.concat(parts, ", ")
end

-- "to Jon, out of the bank first" / "to Jon, once bought"
local FIRST = { bank = ", out of the bank first", mail = ", out of the mailbox first", bought = ", once bought",
    made = ", once made", bags = "" }

-- What to mail, by sender: { { from, list = { moves } } }, senders by name (this character first); and what to take
-- out of a bank or mailbox for the same character: { moves }
local function Sending(moves)
    local me, bySender, senders, fetch = MyName(), {}, {}, {}
    for _, m in ipairs(moves) do
        if m.from == m.to then
            fetch[#fetch + 1] = m
        else
            local s = bySender[m.from]
            if not s then
                s = { from = m.from, list = {} }
                bySender[m.from] = s
                senders[#senders + 1] = s
            end
            s.list[#s.list + 1] = m
        end
    end
    table.sort(senders, function(a, b)
        if (a.from == me) ~= (b.from == me) then return a.from == me end
        return a.from < b.from
    end)
    return senders, fetch
end

local function Rows(plan)
    local rows = {}
    local s = Solve()
    local me = MyName()

    rows[#rows + 1] = { header = "What you want (" .. #plan .. "): - and + change how many" }
    for _, g in ipairs(s.goals) do
        local id = g.goal.id
        local who = g.goal.who and g.goal.who ~= me and (", for " .. g.goal.who) or ""
        rows[#rows + 1] = { g.goal.n .. " " .. ns.ItemName(id) .. who, GoalStatus(g), id = id,
            count = g.buy > 0 and g.buy or nil, sub = #g.from > 0 and table.concat(g.from, ", ") or nil,
            actions = { { "-", function() ns.PlanStep(id, -1) end }, { "+", function() ns.PlanStep(id, 1) end } } }
    end

    local senders, fetch = Sending(s.moves)
    for _, sender in ipairs(senders) do
        rows[#rows + 1] = { header = (sender.from == me and "You send" or (sender.from .. " sends")) .. " by mail ("
            .. #sender.list .. ")" }
        for _, m in ipairs(sender.list) do
            rows[#rows + 1] = { m.count .. " " .. ns.ItemName(m.id), "to " .. m.to .. FIRST[m.where], id = m.id }
        end
    end
    if #fetch > 0 then
        rows[#rows + 1] = { header = "Take out of the bank or mailbox (" .. #fetch .. ")" }
        for _, m in ipairs(fetch) do
            rows[#rows + 1] = { m.count .. " " .. ns.ItemName(m.id), (m.from == me and "you" or m.from) .. ": the "
                .. (m.where == "bank" and "bank" or "mailbox"), id = m.id }
        end
    end

    if #s.make > 0 then
        rows[#rows + 1] = { header = "Make, in this order (" .. #s.make .. ")" }
        for _, m in ipairs(s.make) do
            local rec = m.rec
            local out = math.floor(m.batches * (rec.n or 1) + 0.5)
            rows[#rows + 1] = { out .. " " .. ns.ItemName(rec.out) .. (m.batches ~= out and (" (" .. m.batches .. " crafts)")
                or ""), m.maker == me and "you" or m.maker, id = rec.out, sub = "from " .. Materials(rec, m.batches) }
        end
    end

    if #s.buy > 0 then
        rows[#rows + 1] = { header = "Buy (" .. #s.buy .. ", " .. (s.buyer == me and "you" or s.buyer) .. " at the auction "
            .. "house): " .. ns.Money(s.total) .. (s.unpriced > 0 and (", and " .. s.unpriced .. " with no price yet") or "") }
        for _, e in ipairs(s.buy) do
            rows[#rows + 1] = { e.count .. " " .. ns.ItemName(e.id), BuyText(e), id = e.id, count = e.count }
        end
    else
        rows[#rows + 1] = { header = "Nothing to buy: you have it all, or make it" }
    end
    rows[#rows + 1] = { "Other characters' bags, bank and mail as Quiet Bags last saw them; mail you send is counted." }
    rows[#rows + 1] = { "Prices from the last scan. Start again: /qah plan clear." }
    return rows
end

-- For the window (kept until something changes). A mistake in working it out is shown, not a blank page.
local cache = { key = nil }
function ns.PlanRows()
    local key = ns.version .. ":" .. ns.bagVersion
    if cache.key == key then return cache.rows end
    local rows
    local plan = Plan()
    if #plan == 0 then
        rows = {
            { header = "Your plan is empty" },
            { "Add what you want: \"Plan this\" under a profession window adds the recipe you're looking at;" },
            { "or the Plan buttons in the Crafting and Crates tabs, or /qah plan <item link> 20." },
            { "It then says what you have on which character, what to send, make and buy." },
        }
    else
        local ok, got = pcall(Rows, plan)
        rows = ok and got or {
            { header = "Something went wrong working out the plan" },
            { tostring(got) },
            { "(please pass this line on; /qah plan clear starts again)" },
        }
    end
    cache.key, cache.rows = key, rows
    return rows
end

-- At a mailbox: what this character sends, said once as it opens
function ns.PlanMailReminder()
    if #Plan() == 0 then return end
    local me = MyName()
    local senders = Sending(Solve().moves)
    local mine = senders[1] and senders[1].from == me and senders[1].list
    if not mine then return end
    local parts = {}
    for i = 1, math.min(#mine, REMIND_SHOWN) do
        local m = mine[i]
        parts[#parts + 1] = m.count .. " " .. ns.ItemName(m.id) .. " to " .. m.to
    end
    local more = #mine - REMIND_SHOWN
    ns.Say("To send from here: " .. table.concat(parts, ", ") .. (more > 0 and (", and " .. more .. " more") or "")
        .. " (the Plan tab).")
end

ns.Listen("any", { "MAIL_SHOW" }, function()
    C_Timer.After(1, function() pcall(ns.PlanMailReminder) end)
end)

-- ---------- a price, asked ----------
-- "6c each at the last scan (12 min ago, 140 listed); usually 7c; a vendor sells it for 5c", or nil if nothing is known
function ns.PriceText(id)
    local market = ns.Market()
    local parts = {}
    local price, qty, scan = ns.Latest(id)
    if price then
        local at = market.scanAt[scan]
        local when
        if scan == market.scanNo then
            when = "the last scan"
        else
            when = "a scan " .. (market.scanNo - scan) .. " scans back"
        end
        local ago = at and math.max(0, time() - at)
        local agoText = ago and (ago < 5400 and (math.floor(ago / 60 + 0.5) .. " min ago")
            or (ago < 129600 and (math.floor(ago / 3600 + 0.5) .. " h ago")
            or (math.floor(ago / 86400 + 0.5) .. " days ago")))
        parts[#parts + 1] = ns.Money(price) .. " each at " .. when .. " (" .. (agoText and (agoText .. ", ") or "")
            .. (qty or 0) .. " listed)"
        local usual, scans = ns.Usual(id)
        if usual and scans >= 3 and usual ~= price then parts[#parts + 1] = "usually " .. ns.Money(usual) end
    end
    local vendor = ns.DB().vendorBuy[id]
    if vendor then parts[#parts + 1] = "a vendor sells it for " .. ns.Money(vendor) end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
end

-- /qah price <item link>
function ns.PrintPrice(id)
    ns.Print(ns.ItemName(id) .. ": " .. (ns.PriceText(id) or "not seen at the auction house lately."))
end

-- /qah plan ...
function ns.PlanCommand(rest)
    local id = tonumber(rest:match("item:(%d+)"))
    if rest == "clear" then
        ns.PlanClear()
        ns.Print("the plan is empty.")
    elseif id then
        local n = tonumber(rest:match("|r%s+(%d+)%s*$") or rest:match("%]%s+(%d+)%s*$")) or 1
        ns.PlanAdd(id, n)
    elseif rest ~= "" then
        ns.Print("/qah plan <item link> 20 adds 20 of it (shift-click the item into the chat line); /qah plan clear.")
    end
end

-- Bags changed: what's arrived off the plan; and while the Plan tab is up, worked out again
ns.Listen("any", { "BAG_UPDATE_DELAYED" }, function()
    if TakeDone() then return end
    if ns.WindowTab and ns.WindowTab() == "plan" then
        ns.Changed()
        ns.Refresh()
    end
end)

-- ---------- item tooltips: the price ----------
local tooltipShown = setmetatable({}, { __mode = "k" })

local function AddLine(tooltip, id)
    id = ns.Plain(id)
    if type(id) ~= "number" or tooltipShown[tooltip] == id then return end
    if not ns.Does("any") or not ns.Setting("tooltip") then return end
    tooltipShown[tooltip] = id
    local text = ns.PriceText(id)
    if not text then return end
    tooltip:AddLine("Auction: " .. text, 1, 0.82, 0, true)
    tooltip:Show()
end

local function OnTooltip(tooltip, id)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    pcall(AddLine, tooltip, id)
end

local function HookTooltips()
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) tooltipShown[self] = nil end)
        end
    end
    local processor = TooltipDataProcessor
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if processor and processor.AddTooltipPostCall and itemType then
        processor.AddTooltipPostCall(itemType, function(tooltip, data)
            data = ns.Plain(data)
            if type(data) ~= "table" then return end
            OnTooltip(tooltip, data.id)
        end)
        return
    end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
                local ok, _, link = pcall(self.GetItem, self)
                link = ok and ns.Plain(link)
                if type(link) ~= "string" then return end
                OnTooltip(self, tonumber(link:match("item:(%d+)")))
            end)
        end
    end
end
HookTooltips()
