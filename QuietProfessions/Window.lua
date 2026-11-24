-- The Quiet Professions window: the route (what to make from which skill to which), what to buy for it, and the
-- gear worth making on the way (for a cook: the food that suits your class). /qprof opens and closes it (or a key: Key Bindings, AddOns; or the macro from its
-- settings, for the crossbar). In the look every Quiet addon shares (QuietKit.UI).
--
-- Made for the gamepad cursor as well as the mouse: ordinary frames, big buttons, nothing that needs a right-click.
-- A line's details (every material, the chance of a point) are in its tooltip.
local _, ns = ...

local UI = QuietKit.UI
local C = UI.C

local WIDTH, HEIGHT = 680, 676
local ROWS = 9 -- (lines on a page; Prev and Next, or the mouse wheel, for more)
local ROW_HEIGHT = 44
local ROW_TOP = -254
local NOTES = 3 -- (lines under the sums, one thing said on each)
-- (Mail is only there on a character another of yours waits for things from)
local TABS = { { key = "route", text = "Route" }, { key = "buy", text = "To buy" }, { key = "gear", text = "Gear" },
    { key = "plans", text = "Plans" }, { key = "sell", text = "Sell" }, { key = "mail", text = "Mail" } }
-- What the sum at the right of each line is, by tab
local CAPTIONS = {
    route = "to buy and learn for the step",
    buy = "to pay", gear = "to make it", food = "to make one", smelt = "what it earns",
    plans = "what it would save",
    sell = "what one making earns",
    mail = "what your other characters' planned steps need, from here or bought here, and for whom",
}
local SELL_LEAST = 100 -- (a profit under a silver isn't worth a line)
local WORTH_SHOWN = 36 -- (plans worth getting listed, the most worth first)
local WORTH_LEAST = 100 -- (a saving under a silver isn't worth a line)

local window
local tab, page = "route", 1
local mailShown = false -- (the Mail tab has been opened to once: after that the window opens where you left it)

local function Fill(parent, layer, c, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
    return texture
end

-- A button shown as the chosen one (in the accent), or not
local function Chosen(button, on)
    if on then
        button.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
    else
        button.bg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], C.raised[4] or 1)
    end
end

-- ---------- words ----------
local function Made(r)
    return r.item ~= 0 and not r.aux and ns.ItemName(r.item) or r.name
end

-- "84 Iron Bar, 14 Green Dye", the most first
local function MatsText(mats)
    local list = {}
    for item, n in pairs(mats) do list[#list + 1] = { item = item, n = n } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.item < b.item
    end)
    local parts = {}
    for i, each in ipairs(list) do parts[i] = ns.Whole(each.n) .. " " .. ns.PlainName(each.item) end
    return table.concat(parts, ", ")
end

local function Ago(at)
    local seconds = math.max(0, time() - at)
    if seconds < 5400 then return math.max(1, math.floor(seconds / 60)) .. " min" end
    if seconds < 36 * 3600 then return math.floor(seconds / 3600 + 0.5) .. " hours" end
    return math.floor(seconds / 86400 + 0.5) .. " days"
end

local function InTen(chance)
    return math.max(1, math.floor(chance * 10 + 0.5))
end

-- ---------- the route ----------
local function LearnText(r, fee)
    return "learn it from " .. (r.learnHow or "the trainer") .. (fee > 0 and (" (" .. ns.Money(fee) .. ")") or "")
end

local function MakesText(makes)
    local parts = {}
    for i, m in ipairs(makes) do parts[i] = m.crafts .. " x " .. m.r.name end
    return table.concat(parts, ", ")
end

-- "10 Smoked Bear Meat": what a step of food comes to (its makings, and what they make)
local function Batch(step)
    local crafts = step.crafts or 1
    return (crafts * math.max(1, step.r.n)) .. " " .. ns.ItemName(step.r.item)
        .. (step.r.n > 1 and (" (" .. crafts .. (crafts == 1 and " making)" or " makings)")) or "")
end

-- entry: the step in whole numbers (ns.Resolve): what its makings take, what's made first, what's to buy
local function StepTip(step, entry)
    local r = step.r
    local tip = {}
    if step.tool then
        -- (a tool: got once, and there for every step after)
        tip[#tip + 1] = "A tool. The steps after this one need it to hand, and it isn't used up: "
            .. (step.how == "make" and "made once." or step.how == "buy" and "bought once."
                or "you made some at an earlier step, so keep one of those and don't sell it.")
        if step.how == "make" then
            tip[#tip + 1] = step.gain >= 0.999 and "Making it gives a point too: the route goes on from there."
                or step.gain > 0 and ("A point too, " .. InTen(step.gain) .. " times in 10: counted when that's more "
                    .. "likely than not.")
                or "No point for making it at this skill."
        end
    elseif step.kind == "level" then
        if step.chance >= 0.999 and step.chanceEnd >= 0.999 then
            tip[#tip + 1] = "A point with every making."
        else
            tip[#tip + 1] = "A point in " .. InTen(step.chance) .. " of 10 makings at first, " .. InTen(step.chanceEnd)
                .. " of 10 by the end: about " .. ns.Makings(step) .. (ns.Makings(step) == 1 and " making" or " makings")
                .. ", give or take."
        end
    elseif step.food then
        local points = math.floor(step.gain + 0.5)
        tip[#tip + 1] = "Made to eat: " .. Batch(step) .. ", as you asked on the Food tab."
            .. (points >= 1 and (" About " .. points .. (points == 1 and " point" or " points") .. " come with it.")
                or "")
    elseif step.gain >= 0.999 then
        tip[#tip + 1] = "Made once, to wear. It gives a point too: the route goes on from there."
    elseif step.gain > 0 then
        tip[#tip + 1] = "Made once, to wear. A point too, " .. InTen(step.gain) .. " times in 10: counted when that's "
            .. "more likely than not."
    else
        tip[#tip + 1] = "Made once, to wear. No point: the recipe is grey at this skill."
    end
    -- (not for a tool that's bought or kept: nothing is made)
    if not r.stub then tip[#tip + 1] = "Yellow at " .. r.yellow .. ", grey at " .. r.grey .. "." end
    tip[#tip + 1] = " "
    -- (what the makings shown take, and what you have: here, and with your other characters)
    local list = {}
    for item, n in pairs(entry.mats) do list[#list + 1] = { item = item, n = n } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.item < b.item
    end)
    for _, each in ipairs(list) do
        local total, have = ns.Have(each.item)
        local here = have.bags + have.bank + have.mail + have.pending
        local others = {}
        for _, alt in ipairs(have.alts) do others[#others + 1] = alt.name .. " " .. alt.n end
        tip[#tip + 1] = each.n .. " x " .. ns.ItemName(each.item)
            .. (total > 0 and ("  (you have " .. here .. (#others > 0 and ("; " .. table.concat(others, ", ")) or "") .. ")")
                or "")
    end
    if #entry.makes > 0 then tip[#tip + 1] = "Make first: " .. MakesText(entry.makes) .. "." end
    if step.fee then tip[#tip + 1] = "First " .. LearnText(r, step.fee) .. "." end
    tip[#tip + 1] = " "
    if next(entry.buy) then
        tip[#tip + 1] = "To buy for it: " .. MatsText(entry.buy) .. " (about " .. ns.Money(entry.cost) .. ")."
    else
        tip[#tip + 1] = "Nothing to buy for it: you have it all"
            .. (#entry.makes > 0 and ", once that's made." or ".")
    end
    if step.kind == "level" and step.back >= 1 then
        tip[#tip + 1] = "What's made might bring back about " .. ns.Money(step.back)
            .. ((step.hoped or 0) >= 1 and (", " .. ns.Money(step.hoped) .. " of it only if it sells at auction.") or ".")
    end
    return tip
end

local function RouteRows(plan)
    local out, rows = plan.out, {}
    local me = ns.Me()
    local resolved = ns.Resolve(plan)
    for i, step in ipairs(out.steps) do
        local r = step.r
        local entry = resolved[step]
        local sub = MatsText(entry.mats)
        if #entry.makes > 0 then sub = sub .. "; make first: " .. MakesText(entry.makes) end
        if step.fee then sub = LearnText(r, step.fee) .. "; " .. sub end
        local row = { item = r.item ~= 0 and r.item or nil, sub = sub, tip = StepTip(step, entry) }
        if step.kind == "level" then
            row.title = "|cffffd100" .. step.from .. " - " .. step.to .. "|r   " .. ns.Makings(step) .. " x " .. Made(r)
            -- (a food: what it gives, bright if your class eats for that)
            local food = ns.foods[r.item]
            if food and food.text ~= "" then
                row.title = row.title .. (ns.FoodSuits(r.item, me and me.class) and "  |cffffffff+" or "  |cff999999+")
                    .. food.text .. "|r"
            end
            -- (green: a point less than every other making. Said on the line, not only in its tooltip)
            if step.chance <= 0.5 then
                row.title = row.title .. "  |cff40bf40green: a point in " .. InTen(step.chanceEnd) .. " of 10|r"
            elseif step.chanceEnd <= 0.5 then
                row.title = row.title .. "  |cff40bf40turns green on the way|r"
            end
        elseif step.tool then
            -- (a tool: what to do about it, and that it's the once. Made: its materials, as any step's. Bought:
            -- where. Kept: of those an earlier step made)
            row.item = step.tool
            row.title = "|cffffd100At " .. step.at .. "|r   "
                .. (step.how == "make" and "Make" or step.how == "buy" and "Buy" or "Keep") .. " 1 "
                .. ns.ItemName(step.tool) .. "  |cff999999needed once, for the steps after it|r"
            if step.how == "make" then
                if step.gain >= 0.999 then row.sub = row.sub .. "; it gives a point" end
            elseif step.how == "buy" then
                local vendor = ns.VendorPrice(step.tool)
                row.sub = next(entry.buy) == nil and "another of your characters has one (the To buy tab)"
                    or vendor and ("from a vendor (" .. ns.Money(vendor) .. ")") or "at auction"
            else
                row.sub = "one of those you made earlier: don't sell it"
            end
        elseif step.food then
            row.title = "|cffffd100At " .. step.at .. "|r   " .. (step.crafts or 1) .. " x " .. Made(r)
                .. "  |cff999999to eat, for " .. step.who .. "|r"
        else
            row.title = "|cffffd100At " .. step.at .. "|r   " .. Made(r) .. " for " .. step.who
            -- (the point it gives, which the next step counts on)
            row.title = row.title .. (step.gain >= 0.999 and "  |cff999999gives a point|r"
                or step.gain > 0 and ("  |cff999999a point " .. InTen(step.gain) .. " times in 10|r")
                or "  |cff999999no point: grey|r")
            -- (a piece made ahead: when it can be put on)
            for _, g in ipairs(plan.meta.gear or {}) do
                if g.needLevel and g.r.id == r.id and g.who == step.who then
                    row.title = row.title .. "  |cff999999to wear at level " .. g.needLevel .. "|r"
                    break
                end
            end
        end
        -- (what's to buy for it, and to learn: nothing taken off for what the things made might sell for)
        local pay = entry.cost + (step.fee or 0)
        row.right = pay >= 1 and ns.Money(pay) or "|cff80ff80you have it|r"
        -- (Plan: this step and every one before it; the To buy tab lists what the route needs that far, and your
        -- other characters are told what to mail)
        local planned = ns.IsPlanned(step)
        local after = out.steps[i + 1]
        local last = planned and not (after and ns.IsPlanned(after))
        local pos = ns.StepPos(step)
        if planned then row.title = "|cff80ff80Planned|r  " .. row.title end
        row.button = { text = last and "Unplan" or "Plan", primary = not planned,
            fn = function() ns.SetPlanTo(not last and pos or nil) end }
        row.tip[#row.tip + 1] = " "
        row.tip[#row.tip + 1] = last and "Planned up to here, and kept: these steps stay as they are whatever "
            .. "prices do. Unplan: nothing is planned, and the whole route follows the prices again."
            or planned and "Planned, and kept as it is whatever prices do. Plan here: only up to this step."
            or "Plan: this step and every one before it (they come first anyway). They're then kept as they are, "
            .. "whatever prices do, and the To buy tab lists what the route needs that far, not to its end: what to "
            .. "take out of the bank, what your other characters mail you, what to buy."
        rows[#rows + 1] = row
    end
    if out.stuck then
        local names = {}
        for i = 1, math.min(4, #out.blocked) do names[i] = out.blocked[i].name end
        rows[#rows + 1] = {
            title = "|cffff9040Stuck at " .. out.stuck .. "|r   nothing you can learn gives points here",
            sub = #names > 0 and ("These would, with their " .. ns.Paper(plan.prof) .. "s (the "
                    .. ns.Papers(plan.prof) .. " tab): " .. table.concat(names, ", "))
                or "No recipe gives points at this skill (a gathering skill goes on by gathering).",
            tip = { "The route stops here. A " .. ns.Paper(plan.prof)
                .. " found, bought at auction or already in your bags is counted as soon as "
                .. "it's seen: look the prices up again at the auction house." },
        }
    end
    for _, later in ipairs(out.later) do
        rows[#rows + 1] = {
            item = later.r.item ~= 0 and later.r.item or nil,
            title = "|cff999999Not on this route:|r " .. Made(later.r) .. " for " .. later.who,
            sub = later.why == "skill" and ("needs skill " .. later.r.learn .. ", past the goal")
                or later.why == "tool" and "needs a tool that isn't to be had at this skill"
                or "its recipe isn't to be had now",
        }
    end
    return rows
end

-- ---------- what to get ----------
local function ListText(list)
    local parts = {}
    for i, each in ipairs(list) do parts[i] = each.n .. " " .. ns.PlainName(each.id) end
    return table.concat(parts, ", ")
end

-- "137 - 142: 15 for 5 x Heavy Grinding Stone"
local function UseText(use)
    local step = use.step
    -- (a tool bought: it's what the step is)
    if step.tool and step.r.stub then return "At " .. step.at .. ": " .. ns.Whole(use.n) .. ", a tool needed once" end
    return (step.kind == "gear" and ("At " .. step.at) or (step.from .. " - " .. step.to)) .. ": " .. ns.Whole(use.n)
        .. " for " .. (step.kind == "level" and (ns.Makings(step) .. " x ")
            or step.food and ((step.crafts or 1) .. " x ") or "") .. Made(step.r)
end

-- What the planned steps need (the whole route's, if none is planned), in the order to go about it: how far it
-- reaches (Less and More move that), what your other characters mail, what's in your bank and mailbox, what to
-- learn, then what to buy, the dearest first. A line to buy says how many to BUY, not how many are needed.
local function BuyRows(plan)
    local needs = ns.Needs(plan)
    local rows = {}
    local atAuction = ns.AtAuction()

    -- How far the list reaches
    local steps, k = plan.out.steps, needs.planned
    if #steps > 0 and needs.last then
        local last = needs.last
        local to = last.kind == "gear" and last.at or last.to
        local part = k > 0 and k < #steps
        local row = {
            title = part and ("|cffffd100" .. (to > plan.input.skill and ("For skill " .. plan.input.skill .. " to " .. to)
                    or ("At skill " .. to)) .. "|r   the first " .. (k > 1 and (k .. " ") or "") .. "of the route's "
                    .. #steps .. " steps")
                or ("|cffffd100For the whole route|r   skill " .. plan.input.skill .. " to " .. to .. ", all " .. #steps
                    .. (#steps == 1 and " step" or " steps")),
            sub = part and "Kept as they are, whatever prices do. More: a step further. Less: one fewer."
                or k > 0 and "All of it planned, and kept as it is whatever prices do. Less: one step fewer."
                or "Not planned: it follows the prices, so it changes with them. Less (or Plan on the Route tab) "
                    .. "keeps the first steps as they are.",
            tip = { "How far ahead this list buys for. The route is done a step at a time, and prices move: what a "
                .. "later step needs can wait until you're there.",
                "What's planned keeps its recipes: new prices, or another character's visit to the auction house, "
                .. "don't change what it makes, only what the materials cost. The rest of the route is reckoned "
                .. "again round it.",
                "Plan on a step of the Route tab does the same: the list then reaches to that step.",
                k > 0 and "Your other characters have what these steps need from them on their Mail tab."
                    or "Nothing is planned: your other characters aren't asked for anything yet." },
        }
        local less = (k == 0 and #steps > 1 or k > 1)
            and { text = "Less", fn = function() ns.PlanMove(plan.out, -1) end } or nil
        local more = part and { text = "More", fn = function() ns.PlanMove(plan.out, 1) end } or nil
        row.button, row.button2 = more or less, more and less or nil
        rows[#rows + 1] = row
    end
    local head = #rows

    local names = {}
    for name in pairs(needs.sends) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local list = needs.sends[name]
        rows[#rows + 1] = {
            title = "|cff80c0ff" .. name .. " mails you|r   " .. #list .. (#list == 1 and " thing" or " things"),
            sub = ListText(list), right = "|cff999999yours|r",
            tip = { ListText(list) .. ".", needs.planned > 0 and (name .. " has the list: the Mail tab of this window "
                .. "there, and a note on logging in and at a mailbox (Quiet Professions on there too). What "
                .. "it mails you counts as on its way.")
                or "Plan the steps you mean to do, and " .. name .. " gets a list of what to send (its Mail tab).",
                "As that character's bags, bank and mail were last seen." },
        }
    end
    if #needs.bank > 0 then
        rows[#rows + 1] = { title = "|cff80c0ffOut of your bank|r   " .. #needs.bank
            .. (#needs.bank == 1 and " thing" or " things"), sub = ListText(needs.bank), right = "|cff999999yours|r",
            tip = { ListText(needs.bank) .. "." } }
    end
    if #needs.mail > 0 then
        rows[#rows + 1] = { title = "|cff80c0ffOut of your mailbox|r   " .. #needs.mail
            .. (#needs.mail == 1 and " thing" or " things"), sub = ListText(needs.mail), right = "|cff999999yours|r",
            tip = { ListText(needs.mail) .. "." } }
    end

    for _, fee in ipairs(needs.fees) do
        local r = fee.r
        local plans = r.plan ~= 0 and (r.learnHow or ""):find("auction") and r.plan or nil
        if plans then
            -- (a plan at auction: something to buy, said so)
            rows[#rows + 1] = {
                item = plans,
                title = "|cffffd100Buy 1|r " .. ns.ItemName(plans),
                sub = "at auction: to learn " .. Made(r) .. " from, at skill " .. r.learn,
                right = ns.Money(fee.fee),
                tip = { "A " .. ns.Paper(plan.prof)
                    .. " isn't bought by a press here: Find opens its listings on the game's own auction page.",
                    needs.planned > 0 and "Any other character of yours can buy it instead and mail it: it's on its "
                        .. "Mail tab." or nil },
                button = atAuction and { text = "Find", fn = function() ns.ShowAtAuction(plans, 1) end } or nil,
            }
        else
            rows[#rows + 1] = {
                item = r.plan ~= 0 and r.plan or (r.item ~= 0 and r.item or nil),
                title = "Learn " .. Made(r) .. (r.plan ~= 0 and ("  (" .. ns.PlainName(r.plan) .. ")") or ""),
                sub = "from " .. (r.learnHow or "the trainer") .. ", at skill " .. r.learn,
                right = fee.fee >= 1 and ns.Money(fee.fee) or "|cff999999yours|r",
            }
        end
    end

    for _, e in ipairs(needs.items) do
        local id = e.id
        local buy = e.auction + e.vendor + e.beyond + e.guess
        if buy > 0 then
            local own = {}
            if e.bags > 0 then own[#own + 1] = "bags " .. e.bags end
            if e.pending > 0 then own[#own + 1] = "on its way " .. e.pending end
            if e.bank > 0 then own[#own + 1] = "bank " .. e.bank end
            if e.mail > 0 then own[#own + 1] = "mail " .. e.mail end
            for _, alt in ipairs(e.alts) do own[#own + 1] = alt.name .. " " .. alt.n end
            -- (where the ones to buy are: a number only where there's more than one place)
            local function Of(n) return n == buy and "" or (n .. " ") end
            local parts = {}
            if e.auction > 0 then parts[#parts + 1] = Of(e.auction) .. "at auction" end
            if e.vendor > 0 then
                parts[#parts + 1] = Of(e.vendor) .. "from a vendor (" .. ns.Money(ns.VendorPrice(id) or 0) .. " each)"
            end
            if e.beyond > 0 then parts[#parts + 1] = "|cffff9040" .. e.beyond .. " more than is listed|r" end
            if e.guess > 0 then parts[#parts + 1] = "|cffff9040" .. Of(e.guess) .. "no price known|r" end
            local sub = table.concat(parts, ", ")
            if #own > 0 then sub = sub .. "; the other " .. (e.need - buy) .. " you have: " .. table.concat(own, ", ") end
            local first = e.uses[1] and e.uses[1].step
            if first and #e.uses > 1 then
                sub = sub .. "; for " .. #e.uses .. " steps, from skill " .. (first.kind == "gear" and first.at or first.from)
            end
            local price = plan.meta.price[id]
            local tip = {}
            if #e.uses > 0 then
                tip[#tip + 1] = "What they're for (" .. e.need .. " in all" .. (e.need > buy and (", " .. (e.need - buy)
                    .. " of them yours already") or "") .. "):"
                for i = 1, math.min(8, #e.uses) do tip[#tip + 1] = "  " .. UseText(e.uses[i]) end
                if #e.uses > 8 then tip[#tip + 1] = "  and " .. (#e.uses - 8) .. " more steps" end
                tip[#tip + 1] = " "
            end
            if price and price.at then
                -- (looked up and none listed: its source is then "guess", with when it was looked up)
                tip[#tip + 1] = (price.source == "scan" and "From Quiet Auctions' scan " or "Looked up ") .. Ago(price.at)
                    .. " ago" .. (price.rows[1] and (": from " .. ns.Money(price.rows[1]) .. " each.") or ": none listed.")
            elseif not ns.VendorPrice(id) then
                tip[#tip + 1] = "No price known: a guess from what a vendor pays. Check prices at the auction house."
            end
            local market = e.auction + e.beyond + e.guess
            local row = { item = id, title = "|cffffd100Buy " .. buy .. "|r " .. ns.ItemName(id), sub = sub,
                tip = tip, right = ns.Money(e.cost) }
            if market > 0 and needs.planned > 0 then
                tip[#tip + 1] = "Any other character of yours can buy these instead and mail them: they're on its Mail "
                    .. "tab, with a Buy of their own."
            end
            if market > 0 and atAuction then
                if ns.CanQuickBuy(id) then
                    -- (two presses: the first asks the auction house what they cost, the second pays that)
                    local each = e.auction > 0 and e.auctionCost / e.auction or nil
                    local text, primary, note = ns.QuickBuyButton(id, each)
                    row.button = { text = text, primary = primary, fn = function() ns.QuickBuy(id, market, each) end }
                    if note then row.sub = note end
                    tip[#tip + 1] = "Buy: a press asks the auction house what " .. market .. " cost now (that buys "
                        .. "nothing), a second press, on Pay, pays the total it showed. They come by mail."
                else
                    row.button = { text = "Find", fn = function() ns.ShowAtAuction(id, market) end }
                    tip[#tip + 1] = "Find opens its listings on the game's own auction page: the buying is there."
                end
            end
            rows[#rows + 1] = row
        end
    end
    if #rows == head and head > 0 then
        rows[#rows + 1] = { title = "Nothing to fetch or buy for " .. (k > 0 and "these steps" or "it"),
            sub = "It's in your bags, or on its way by mail." }
    end
    return rows
end

-- ---------- gear ----------
local function GearRows(plan)
    local rows = {}
    for _, entry in ipairs(plan.meta.gear) do
        local r = entry.r
        local copy = plan.meta.byId[r.id]
        local wanted = ns.Wanted(entry)
        local parts = {}
        if entry.gain then
            local worn = entry.worn and entry.worn:match("%[(.-)%]") or "what's worn"
            parts[#parts + 1] = "+" .. math.floor(entry.gain + 0.5) .. "% over " .. worn
        else
            parts[#parts + 1] = "nothing worn there"
        end
        if entry.needLevel then parts[#parts + 1] = "at level " .. entry.needLevel end
        parts[#parts + 1] = "skill " .. r.learn
        if not copy.known then parts[#parts + 1] = "learn it from " .. (copy.learnHow or "?") end
        if entry.bound then parts[#parts + 1] = "binds when made" end
        local cost, fee = ns.Solver.CraftCost(plan.input, copy)
        rows[#rows + 1] = {
            item = entry.item,
            title = (wanted and "|cff80ff80Make|r  " or "") .. ns.ItemName(entry.item) .. "  for " .. entry.who .. " ("
                .. entry.slot .. ")",
            sub = table.concat(parts, ", "),
            right = ns.Money(cost + fee),
            tip = { "About " .. ns.Money(cost) .. " in materials at today's prices"
                .. (fee > 0 and (", and " .. ns.Money(fee) .. " to learn it") or "") .. ".",
                wanted and "It's on the route: made once, as soon as the skill is there."
                    or "Make puts it on the route: made once, as soon as the skill is there.",
                entry.needLevel and ("It can't be worn before level " .. entry.needLevel
                    .. ": Skip leaves the gold for later.") or nil,
                "Weighed by its stats for the class: a rule of thumb, so look before you make it." },
            button = { text = wanted and "Skip" or "Make", primary = not wanted,
                fn = function() ns.SetWanted(entry, not wanted) end },
        }
    end
    return rows
end

-- ---------- food ----------
-- The food that suits each of your characters' class: what it gives, what one costs to make, and how many you've
-- asked for (those are on the route). Nothing is asked for until you press.
local function FoodRows(plan)
    local rows = {}
    -- (what the route's levelling makes of each anyway)
    local anyway = {}
    for _, step in ipairs(plan.out.steps) do
        if step.kind == "level" and step.r.item ~= 0 then
            anyway[step.r.item] = (anyway[step.r.item] or 0) + ns.Makings(step) * step.r.n
        end
    end
    local skill = ns.Skill(plan.prof)
    for _, entry in ipairs(plan.meta.food or {}) do
        local r, food = entry.r, entry.food
        local copy = plan.meta.byId[r.id]
        local wanted = ns.FoodWanted(entry)
        local parts = {}
        parts[#parts + 1] = "restores " .. (food.health > 0 and (food.health .. " health") or (food.mana .. " mana"))
        if entry.needLevel then parts[#parts + 1] = "|cffff9040from level " .. entry.needLevel .. "|r" end
        if r.learn > skill then parts[#parts + 1] = "skill " .. r.learn end
        if not copy.known then parts[#parts + 1] = "learn it from " .. (copy.learnHow or "?") end
        local have = ns.Have(entry.item)
        if have > 0 then parts[#parts + 1] = "you have " .. have end
        if anyway[entry.item] then parts[#parts + 1] = "the route makes " .. anyway[entry.item] .. " anyway" end
        local cost, fee = ns.Solver.CraftCost(plan.input, copy)
        local each = cost / math.max(1, r.n)
        local tip = { "Well fed: " .. food.text .. " for " .. food.minutes .. " min.",
            "The best " .. entry.kind .. " food " .. entry.who .. " can eat "
                .. (entry.needLevel and ("at level " .. entry.needLevel) or "now")
                .. ", of what " .. ns.professions[plan.prof].name .. " makes up to skill " .. plan.goal .. ".",
            "One costs about " .. ns.Money(each) .. " in materials at today's prices"
                .. (r.n > 1 and (" (a making gives " .. r.n .. ")") or "")
                .. (fee > 0 and (", and " .. ns.Money(fee) .. " once to learn it") or "") .. ".",
            wanted > 0 and (wanted .. " are on the route: made as soon as the skill is there, their materials on "
                .. "the To buy tab. More and Fewer change it by " .. ns.FOOD_BATCH .. ".")
                or ("Make " .. ns.FOOD_BATCH .. " puts " .. ns.FOOD_BATCH .. " on the route: made as soon as the skill "
                .. "is there, their materials on the To buy tab.") }
        if entry.from then
            table.insert(tip, 2, "Counted as " .. ("%g"):format(entry.amount) .. " " .. entry.kind .. ": " .. entry.from
                .. " stands in for it.")
        end
        if anyway[entry.item] then
            tip[#tip + 1] = "The route makes " .. anyway[entry.item] .. " of these for skill points already: what "
                .. "you ask for here comes on top of those."
        end
        local row = {
            item = entry.item,
            title = (wanted > 0 and ("|cff80ff80Make " .. wanted .. "|r  ") or "") .. ns.ItemName(entry.item)
                .. "  |cffffffff+" .. food.text .. "|r" .. (entry.mine and "" or ("  for " .. entry.who)),
            sub = table.concat(parts, ", "),
            right = ns.Money(each),
            tip = tip,
        }
        if wanted > 0 then
            row.button = { text = "More", fn = function() ns.FoodMore(entry, 1) end }
            row.button2 = { text = "Fewer", fn = function() ns.FoodMore(entry, -1) end }
        else
            row.button = { text = "Make " .. ns.FOOD_BATCH, primary = true, fn = function() ns.FoodMore(entry, 1) end }
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- ---------- smelting for money ----------
-- A miner's third tab (Smelt.lua): what you hold, smelted or sold as it is; and what's listed that would earn
-- bought, smelted and sold. A line says what to do with how many, and the prices it stands on.
local function Plus(parts)
    return table.concat(parts, " + ")
end

local function SmeltRows(plan)
    local rows = {}
    local own, buy = ns.Smelting(plan)
    local atAuction = ns.AtAuction()
    for _, e in ipairs(own) do
        local r = e.r
        local mats, prices, where = {}, {}, {}
        for _, m in ipairs(e.mats) do
            mats[#mats + 1] = m.n .. " " .. ns.PlainName(m.id)
            prices[#prices + 1] = ns.PlainName(m.id) .. " " .. ns.Money(m.each) .. " each"
                .. (m.auction and "" or " at a vendor (none at auction)")
            if m.where ~= "" then where[#where + 1] = ns.PlainName(m.id) .. ": " .. m.where end
        end
        local made = e.makes .. " " .. ns.PlainName(r.item)
        local brings = ns.PlainName(r.item) .. " brings " .. ns.Money(e.each) .. " each"
            .. (e.auction and (" (" .. (e.listed or 0) .. " listed)") or " at a vendor")
        local parts = { brings, table.concat(prices, ", ") }
        for _, v in ipairs(e.vendor) do
            parts[#parts + 1] = "buy " .. v.n .. " " .. ns.PlainName(v.id) .. " from a vendor (" .. ns.Money(v.cost) .. ")"
        end
        if #where > 0 then parts[#parts + 1] = table.concat(where, "; ") end
        if e.fee then table.insert(parts, 1, "learn it from the trainer first (" .. ns.Money(e.fee) .. ")") end
        local row = { item = r.item, tip = {
            table.concat(parts, "; ") .. ".",
            "What you have of it, on this character and (if they count) your others: " .. Plus(mats) .. ".",
            "Sold means at auction, just under the cheapest listed and less the house's cut; or to a vendor, where "
                .. "that pays more.",
            "These prices move by the hour: look at the listings before you smelt a bank's worth." } }
        if e.unpriced then
            row.title = Plus(mats) .. ": |cffff9040no auction price for " .. ns.PlainName(r.item) .. "|r"
            row.sub = (atAuction and "Press Check prices" or "Check prices at the auction house")
                .. ": then this says whether to smelt it or sell it as it is."
        elseif e.gain >= SELL_LEAST then
            row.title = "|cff80ff80Smelt|r " .. Plus(mats) .. ", sell " .. made
            row.right = "|cff80ff80+" .. ns.Money(e.gain) .. "|r"
            row.sub = table.concat(parts, "; ")
            row.tip[#row.tip + 1] = "+" .. ns.Money(e.gain) .. ": what the " .. made .. " bring over selling the "
                .. Plus(mats) .. " as they are."
        elseif e.gain <= -SELL_LEAST then
            row.title = "|cffffd100Sell|r " .. Plus(mats) .. " as " .. (#e.mats > 1 and "they are" or "it is")
            row.right = "|cffff9040smelting loses " .. ns.Money(-e.gain) .. "|r"
            row.sub = table.concat(parts, "; ")
        else
            row.title = Plus(mats) .. ": smelted or not, it brings the same"
            row.sub = table.concat(parts, "; ")
        end
        if atAuction then row.button = { text = "Find", fn = function() ns.ShowAtAuction(r.item, 1) end } end
        rows[#rows + 1] = row
    end
    for _, e in ipairs(buy) do
        local r = e.r
        local mats, most, first = {}, {}, nil
        for _, m in ipairs(e.mats) do
            mats[#mats + 1] = m.n .. " " .. ns.PlainName(m.id)
            if m.vendor then
                most[#most + 1] = ns.PlainName(m.id) .. " from a vendor"
            else
                most[#most + 1] = "pay up to " .. ns.Money(m.most) .. " a " .. ns.PlainName(m.id)
                first = first or m
            end
        end
        local parts = { table.concat(most, ", ") .. " (" .. ns.Money(e.cost) .. " in all)",
            ns.PlainName(r.item) .. " brings " .. ns.Money(e.each) .. " each, " .. (e.listed or 0) .. " listed" }
        if e.fee then table.insert(parts, 1, "learn it from the trainer first (" .. ns.Money(e.fee) .. ")") end
        if e.scan then parts[#parts + 1] = "|cffff9040only the cheapest price is known: Check prices|r" end
        rows[#rows + 1] = {
            item = r.item,
            title = "|cffffd100Buy|r " .. Plus(mats) .. ", smelt, sell " .. e.makes .. " " .. ns.PlainName(r.item),
            right = "|cff80ff80earns " .. ns.Money(e.profit - (e.fee or 0)) .. "|r",
            sub = table.concat(parts, "; "),
            tip = { table.concat(parts, "; ") .. ".",
                "The listings from the cheapest up, making by making: it stops where the next making's materials "
                .. "cost more than what it makes brings.",
                "Sells for about " .. ns.Money(e.sells) .. " after the house's cut, just under the cheapest listed. "
                .. "A deposit for listing, if the house takes one, isn't counted.",
                "A price asked isn't a sale: " .. e.makes .. " more on top of the " .. (e.listed or 0) .. " listed may "
                .. "sit, or push the price down. Start with a part of it." },
            button = atAuction and first and { text = "Find", fn = function() ns.ShowAtAuction(first.id, first.n) end }
                or nil,
        }
    end
    return rows
end

-- ---------- plans worth getting ----------
-- The recipes you can't learn now that would give points on this route for less than it pays now: what each
-- would save, and what stands in the way
local function WorthRows(plan)
    local rows = {}
    local atAuction = ns.AtAuction()
    for _, w in ipairs(plan.out.worth or {}) do
        if #rows >= WORTH_SHOWN then break end
        if w.reach > 0 or w.saving >= WORTH_LEAST then
            local r = w.r
            local planItem = r.plan ~= 0 and r.plan or nil
            local last = math.min(plan.goal, r.grey)
            local tip = { "For skill " .. math.max(plan.input.skill, r.learn) .. " to " .. last .. ": one making costs about "
                .. ns.Money(math.max(0, w.each)) .. " more than it sells for." }
            if w.reach > 0 then
                tip[#tip + 1] = "The route is stuck at " .. plan.out.stuck .. ": this would carry it " .. w.reach
                    .. " points further."
            end
            if w.saving >= 1 then
                tip[#tip + 1] = "Against what the route makes at those points now, about " .. ns.Money(w.saving)
                    .. " less (before its own price: reckoned at today's first prices, so roughly)."
            end
            tip[#tip + 1] = "Each " .. ns.Paper(plan.prof)
                .. " is weighed on its own: two that cover the same points don't both save this."
            tip[#tip + 1] = "Once its " .. ns.Paper(plan.prof)
                .. " is in your bags, or listed at auction and looked up, the route counts it."
            rows[#rows + 1] = {
                item = planItem or (r.item ~= 0 and r.item or nil),
                title = planItem and ns.ItemName(planItem) or r.name,
                sub = (w.why or ""):gsub("^%l", string.upper),
                right = w.reach > 0 and ("|cff80ff80+" .. w.reach .. " points|r") or ("saves " .. ns.Money(w.saving)),
                tip = tip,
                button = planItem and atAuction
                    and { text = "Find", fn = function() ns.ShowAtAuction(planItem, 1) end } or nil,
            }
        end
    end
    return rows
end

-- ---------- what sells ----------
-- What you can make now that the auction house pays more for than its materials cost
local function SellRows(plan)
    local rows = {}
    local atAuction = ns.AtAuction()
    for _, p in ipairs(plan.out.profits or {}) do
        if #rows >= WORTH_SHOWN then break end
        if p.profit >= SELL_LEAST then
            local r = p.r
            local sale = plan.meta.sale[r.item]
            local parts = { "sells for about " .. ns.Money(p.sells) .. (sale and (" (" .. sale.listed .. " listed)") or ""),
                "materials " .. ns.Money(p.cost) }
            if p.fee > 0 then parts[#parts + 1] = LearnText(r, p.fee) end
            if ns.Solver.Chance(r, plan.input.skill) > 0 then parts[#parts + 1] = "gives points" end
            if p.unsure then parts[#parts + 1] = "|cffff9040a material has no price|r" end
            local tip = { "One making: its materials at what they cost to buy today (your own too: they could be sold "
                .. "instead), sold just under the cheapest listed, less the auction house's cut.",
                "A price asked isn't a sale. With many listed it may sit; with one, the price may be a wish: look "
                .. "before you make more than one." }
            if sale and sale.at then
                tip[#tip + 1] = "Its price is " .. Ago(sale.at) .. " old ("
                    .. (sale.source == "looked" and "looked up" or "Quiet Auctions' scan") .. ")."
            end
            rows[#rows + 1] = {
                item = r.item,
                title = ns.ItemName(r.item) .. (r.n > 1 and ("  x " .. r.n) or ""),
                sub = table.concat(parts, ", "),
                right = "|cff80ff80earns " .. ns.Money(p.profit) .. "|r",
                tip = tip,
                button = atAuction and { text = "Find", fn = function() ns.ShowAtAuction(r.item, 1) end } or nil,
            }
        end
    end
    return rows
end

-- ---------- what to mail from here ----------
-- What another of your characters planned and needs from this one: a line a thing, with where it is now. What that
-- character would have to buy is here too, to buy for it: Buy at the auction house, as on the To buy tab. Mailed
-- to that character a thing comes off by itself; Sent takes it off by hand.
local function MailRows()
    local rows = {}
    local atAuction = ns.AtAuction()
    for _, send in ipairs(ns.SendsFromMe()) do
        for _, each in ipairs(send.items) do
            local id = each.id
            local where = {}
            if each.bags > 0 then where[#where + 1] = each.bags .. " in your bags" end
            if each.mail > 0 then where[#where + 1] = each.mail .. " in your mailbox" end
            if each.pending > 0 then where[#where + 1] = each.pending .. " bought, coming to your mailbox" end
            if each.bank > 0 then where[#where + 1] = "|cffff9040" .. each.bank .. " in the bank|r" end
            local tip = { send.to .. " planned a step that needs " .. (each.n + each.buy) .. " of these"
                .. (each.buy > 0 and (", " .. each.buy .. " of them to be bought: here, or there.") or " from here."),
                "Mailed to " .. send.to .. ", they come off this list by themselves, and count there as on their "
                .. "way. Sent takes off what's here by hand." }
            local title = each.buy > 0 and ("|cffffd100Buy " .. each.buy .. "|r " .. ns.ItemName(id)
                    .. (each.n > 0 and ("  |cff999999and mail it with the " .. each.n .. " here|r") or ""))
                or ("Mail " .. each.n .. " " .. ns.ItemName(id))
            local row = { item = id, title = title,
                right = "|cff80c0ffto " .. send.to .. "|r", tip = tip }
            if each.buy > 0 then
                local cost, one, short = ns.MarketCost(id, each.buy)
                where[#where + 1] = each.buy .. " to buy"
                    .. (cost > 0 and (": about " .. ns.Money(cost) .. (short > 0 and ", not all listed" or ""))
                        or ": no price known (Check prices)")
                if atAuction then
                    if ns.CanQuickBuy(id) then
                        local text, primary, note = ns.QuickBuyButton(id, one)
                        row.button = { text = text, primary = primary, fn = function() ns.QuickBuy(id, each.buy, one) end }
                        if note then where = { note } end
                        tip[#tip + 1] = "Buy: a press asks the auction house what " .. each.buy .. " cost now (that buys "
                            .. "nothing), a second press, on Pay, pays the total it showed. They come by mail."
                    else
                        row.button = { text = "Find", fn = function() ns.ShowAtAuction(id, each.buy) end }
                    end
                end
            end
            if not row.button and each.n > 0 then
                row.button = { text = "Sent", fn = function() ns.NoteMailed(send.key, id, each.n, true) end }
            end
            row.sub = table.concat(where, ", ")
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- ---------- what it shows ----------
-- The heading, the sums under it, what else there is to say (the most pressing first, a line each) and, small at
-- the right, how old the prices are
local function Summary(plan)
    local prof = ns.professions[plan.prof]
    local skill, has = ns.Skill(plan.prof)
    local out = plan.out
    if plan.error then return "The route couldn't be reckoned.", "", { plan.error }, "" end
    if not out then return prof.name .. ": reckoning the route...", "", {}, "" end
    -- (what's to buy, by the same whole-number count as the To buy tab's list for the whole route)
    local toBuy = ns.Resolve(plan).cost
    local head = prof.name .. " " .. skill .. " to " .. out.reached .. ": about |cffffffff"
        .. ns.Money(toBuy + out.feeTotal) .. "|r to pay"
    local sums, notes = "", {}
    if #out.steps == 0 then
        head = prof.name .. " " .. skill .. ": no route from here"
    else
        -- (what's made brings two sums where the route counts on sales at auction: a vendor's, which is sure,
        -- and the auction house's, which moves from hour to hour)
        local hoped = out.hoped or 0
        sums = "To buy |cffffffff" .. ns.Money(toBuy) .. "|r    To learn |cffffffff" .. ns.Money(out.feeTotal) .. "|r"
        -- (nothing said of selling where nothing made sells: an enchanter's enchantments are no item)
        if out.back >= 1 then
            sums = sums .. "    What's made sells for |cffffffff" .. ns.Money(out.back - hoped) .. "|r at a vendor"
                .. (hoped >= 1 and (", |cffffffff" .. ns.Money(out.back) .. "|r at auction") or "")
        end
    end
    -- (how good the prices are)
    local guessed, oldest = 0, nil
    for id, t in pairs(out.items) do
        if (t.guess or 0) > 0.01 then guessed = guessed + 1 end
        local price = plan.meta.price[id]
        if price and price.at and ((t.auction or 0) + (t.beyond or 0)) > 0.01 and (not oldest or price.at < oldest) then
            oldest = price.at
        end
    end
    -- (a cook's route makes the food your class eats where it can: what that costs over the cheapest route)
    local eats
    local me = ns.Me()
    local order = me and ns.FoodOrder(me.class)
    if out.preferred and order then
        eats = "The food a " .. me.class:lower() .. " eats is made first (" .. order .. ")"
        local plain = out.plain
        if plain and plain.reached == out.reached then
            local more = toBuy + out.feeTotal - ns.Resolve({ out = plain, meta = plan.meta }).cost - plain.feeTotal
            eats = eats .. (more >= 1 and (": |cffffffff" .. ns.Money(more) .. "|r more to pay than the cheapest route.")
                or ": no dearer than the cheapest route.")
        else
            eats = eats .. "."
        end
    end
    -- (what the gear and the food asked for add)
    local gear, eat = 0, 0
    for _, step in ipairs(out.steps) do
        if step.kind == "gear" and step.food then
            eat = eat + step.cost + (step.fee or 0)
        elseif step.kind == "gear" and not step.tool then
            gear = gear + step.cost + (step.fee or 0)
        end
    end

    -- (what another of your characters has planned and waits for from this one)
    local things, toBuy, names = 0, 0, {}
    for _, send in ipairs(ns.SendsFromMe()) do
        names[#names + 1] = send.to
        for _, each in ipairs(send.items) do
            things = things + 1
            if each.buy > 0 then toBuy = toBuy + 1 end
        end
    end
    if things > 0 then
        notes[#notes + 1] = "|cff80c0ffFor " .. table.concat(names, " and ") .. ":|r " .. things
            .. (things == 1 and " thing" or " things") .. " to mail"
            .. (toBuy == 0 and "" or toBuy < things and (", " .. toBuy .. " of them to buy first")
                or things == 1 and ", to buy first" or ", all to buy first")
            .. " (the Mail tab)."
    end
    if guessed > 0 then
        notes[#notes + 1] = "|cffff9040" .. guessed .. (guessed == 1 and " material has" or " materials have")
            .. " no price yet:|r "
            .. (ns.AtAuction() and "press Check prices." or "Check prices at the auction house.")
    end
    if not has then
        notes[#notes + 1] = "You haven't learned " .. prof.name .. ": this is the route from the start."
    elseif not plan.meta.opened then
        notes[#notes + 1] = "|cffff9040Open your " .. prof.name .. " window once:|r then I know which recipes you have."
    end
    if eats then notes[#notes + 1] = eats end
    if gear >= 1 then notes[#notes + 1] = "Gear to wear is " .. ns.Money(gear) .. " of it (the Gear tab)." end
    if eat >= 1 then notes[#notes + 1] = "Food to eat is " .. ns.Money(eat) .. " of it (the Food tab)." end
    if out.spend - out.paid > 1 then
        notes[#notes + 1] = "Your own materials go into it too: worth " .. ns.Money(out.spend - out.paid) .. "."
    end
    if plan.meta.waiting then notes[#notes + 1] = "Still asking the game about some gear." end
    local age = plan.working and "reckoning again..." or (oldest and guessed == 0 and ("prices up to " .. Ago(oldest)
        .. " old")) or ""
    return head, sums, notes, age
end

local function Refresh()
    if not window or not window:IsShown() then return end
    local plan = ns.Plan()
    if not plan then
        window.head:SetText("One moment: the game doesn't know who you are yet.")
        window.sums:SetText("")
        window.age:SetText("")
        for _, line in ipairs(window.notes) do line:SetText("") end
        for _, row in ipairs(window.rows) do row:Hide() end
        return
    end
    local me = ns.Me()
    -- (a button for each profession you have; the ones you haven't learned share one, which steps through them:
    -- there's a row's room, and data for more professions than fit it)
    local shown, others = {}, 0
    for _, b in ipairs(window.profs) do
        local skill, has = ns.Skill(b.id)
        b:SetShown(has)
        if has then
            b:SetText(ns.professions[b.id].name .. " " .. skill)
            Chosen(b, b.id == plan.prof)
            shown[#shown + 1] = b
        else
            others = others + 1
        end
    end
    window.others:SetShown(others > 0)
    if others > 0 then
        local mine = select(2, ns.Skill(plan.prof))
        window.others:SetText(mine and "Others" or ns.professions[plan.prof].name)
        Chosen(window.others, not mine)
        shown[#shown + 1] = window.others
    end
    local width = math.min(150, math.floor((WIDTH - 32 - (#shown - 1) * 6) / math.max(1, #shown)))
    for i, b in ipairs(shown) do
        b:SetWidth(width)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 16 + (i - 1) * (width + 6), -46)
    end
    for _, b in ipairs(window.goals) do
        Chosen(b, b.goal == plan.goal)
        b:SetEnabled(b.goal > ns.Skill(plan.prof))
    end
    local head, sums, notes, age = Summary(plan)
    window.head:SetText(head)
    window.sums:SetText(sums)
    window.age:SetText(age)
    for i, line in ipairs(window.notes) do line:SetText(notes[i] or "") end

    local running, done, total = ns.LookupState()
    window.prices:SetText(running and ("Stop (" .. done .. " of " .. total .. ")") or "Check prices")
    window.prices:SetEnabled(ns.AtAuction())

    -- (a cook's third tab is the food that suits your class, a miner's what smelting earns; the others' is gear)
    local cook = ns.professions[plan.prof].food and true or false
    local smelt = ns.Smelts(plan.prof)
    local smeltRows = smelt and plan.out and SmeltRows(plan) or {}
    -- (what this character is to mail: its tab is there only while there's something)
    local mail = MailRows()
    if tab == "mail" and #mail == 0 then tab, page = "route", 1 end
    -- (the plans worth getting and what sells are counted on their tabs, so those two lists are always made)
    local worthRows = plan.out and WorthRows(plan) or {}
    local sellRows = plan.out and SellRows(plan) or {}
    local worth, sells = #worthRows, #sellRows
    local rows = {}
    if tab == "mail" then
        rows = mail
    elseif plan.out then
        if tab == "route" then
            rows = RouteRows(plan)
        elseif tab == "buy" then
            rows = BuyRows(plan)
        elseif tab == "gear" then
            rows = smelt and smeltRows or cook and FoodRows(plan) or GearRows(plan)
        elseif tab == "plans" then
            rows = worthRows
        else
            rows = sellRows
        end
    end
    local caption = CAPTIONS[tab == "gear" and (smelt and "smelt" or cook and "food") or tab]
    window.caption:SetText(#rows > 0 and caption or "")
    local wanted, eaten = 0, 0
    for _, entry in ipairs(plan.meta.gear) do
        if ns.Wanted(entry) then wanted = wanted + 1 end
    end
    for _, entry in ipairs(plan.meta.food or {}) do
        if ns.FoodWanted(entry) > 0 then eaten = eaten + 1 end
    end
    for _, b in ipairs(window.tabs) do
        Chosen(b, b.key == tab)
        if b.key == "mail" then
            b:SetShown(#mail > 0)
            b:SetText("Mail (" .. #mail .. ")")
        elseif b.key == "gear" and smelt then
            b:SetText(#smeltRows > 0 and ("Smelt (" .. #smeltRows .. ")") or "Smelt")
        elseif b.key == "gear" and cook then
            local n = #(plan.meta.food or {})
            b:SetText(n > 0 and ("Food (" .. eaten .. "/" .. n .. ")") or "Food")
        elseif b.key == "gear" then
            b:SetText(#plan.meta.gear > 0 and ("Gear (" .. wanted .. "/" .. #plan.meta.gear .. ")") or "Gear")
        elseif b.key == "plans" then
            -- (a smith's plans, a cook's recipes, a tailor's patterns)
            local papers = ns.Papers(plan.prof)
            b:SetText(worth > 0 and (papers .. " (" .. worth .. ")") or papers)
        elseif b.key == "sell" then
            b:SetText(sells > 0 and ("Sell (" .. sells .. ")") or "Sell")
        end
    end

    local pages = math.max(1, math.ceil(#rows / ROWS))
    page = math.max(1, math.min(page, pages))
    window.pageText:SetText(page .. " / " .. pages)
    window.prev:SetEnabled(page > 1)
    window.next:SetEnabled(page < pages)
    for _, part in ipairs({ window.prev, window.next, window.pageText }) do part:SetShown(pages > 1) end
    for i, row in ipairs(window.rows) do
        local data = rows[(page - 1) * ROWS + i]
        row.data = data
        row:SetShown(data ~= nil)
        if data then
            row.title:SetText(data.title or "")
            row.sub:SetText(data.sub or "")
            row.right:SetText(data.right or "")
            row.button:SetShown(data.button ~= nil)
            if data.button then
                row.button:SetText(data.button.text)
                Chosen(row.button, data.button.primary)
            end
            row.button2:SetShown(data.button2 ~= nil)
            -- (the sum and the small line end left of the buttons: further left when there are two)
            local inset = data.button2 and -148 or -78
            row.right:SetPoint("TOPRIGHT", inset, -7)
            row.sub:SetPoint("RIGHT", row, "RIGHT", inset, 0)
            if data.button2 then
                row.button2:SetText(data.button2.text)
                Chosen(row.button2, data.button2.primary)
            end
        end
    end
    window.empty:SetShown(#rows == 0)
    if not plan.out then
        window.empty:SetText("Reckoning...")
    elseif tab == "gear" and smelt then
        window.empty:SetText("Nothing to smelt for money by the prices known: you hold no ore or bars a recipe of "
            .. "yours takes, and no ore listed is cheap enough to buy, smelt and sell. (Check prices at the auction "
            .. "house looks up your ores and bars.)")
    elseif tab == "gear" and cook then
        window.empty:SetText("No food " .. ns.professions[plan.prof].name .. " makes up to skill " .. plan.goal
            .. " suits " .. (me and me.name or "your character") .. " yet: the recipes for it can't be learned now, or "
            .. "it's above your level. (The food is chosen for the class: strength and attack power for a warrior, "
            .. "not spirit.)")
    elseif tab == "gear" then
        window.empty:SetText("Nothing " .. ns.professions[plan.prof].name .. " makes up to skill " .. plan.goal
            .. " beats what your characters wear. (Each character is known once it has logged in with this on"
            .. (me and (", as " .. me.name .. " now") or "") .. ".)")
    elseif tab == "sell" then
        window.empty:SetText("Nothing you can make now sells at auction for more than its materials cost, by the "
            .. "prices known. (What's made is priced by Quiet Auctions' scans, or by Check prices at the auction "
            .. "house: the things you can make now come last in it.)")
    elseif tab == "buy" then
        window.empty:SetText("Nothing to fetch or buy: it's in your bags, or on its way by mail.")
    elseif tab == "plans" then
        window.empty:SetText(cook and ("No recipe you lack would make this route cheaper. (Recipes that only the "
            .. "other side's vendors sell, that come from a quest, or that aren't at auction now are weighed here; the "
            .. "ones you can simply buy are in the route already.)")
            or ("No " .. ns.Paper(plan.prof) .. " you lack would make this route cheaper. (" .. ns.Papers(plan.prof)
                .. " that need a reputation you don't have, that only the other side's vendors sell, or that aren't "
                .. "at auction now are weighed here; the ones you can simply buy are in the route already.)"))
    else
        window.empty:SetText("No route from here.")
    end
end
ns.RefreshWindow = Refresh
ns.OnChanged = Refresh

-- ---------- the window ----------
local function ShowTip(row)
    local data = row.data
    if not data then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = data.item and pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. data.item)
    if not shown then GameTooltip:AddLine((data.title or ""), 1, 1, 1, true) end
    if data.tip and #data.tip > 0 then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(data.tip) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
    end
    GameTooltip:Show()
end

local function Row(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 32, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, ROW_TOP - (i - 1) * (ROW_HEIGHT + 2))
    Fill(row, "BACKGROUND", C.raised):SetAllPoints()

    row.button = UI.Button(row, "", function()
        if row.data and row.data.button then row.data.button.fn() end
    end, 64)
    row.button:SetPoint("RIGHT", -6, 0)
    -- (a second one, for the line that has two: Less and More)
    row.button2 = UI.Button(row, "", function()
        if row.data and row.data.button2 then row.data.button2.fn() end
    end, 64)
    row.button2:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
    row.right = UI.Text(row, "body")
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)
    row.right:SetPoint("TOPRIGHT", -78, -7)
    row.right:SetWidth(120)
    row.title = UI.Text(row, "body")
    row.title:SetPoint("TOPLEFT", 10, -7)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.title:SetWordWrap(false)
    row.sub = UI.Text(row, "muted")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -78, 0)
    row.sub:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowTip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- The next profession you haven't learned after the one shown; the first of them while one of yours is shown
local function NextOther()
    local now = ns.Profession()
    local list, at = {}, 0
    for _, id in ipairs(ns.professionOrder) do
        if not select(2, ns.Skill(id)) then
            list[#list + 1] = id
            if id == now then at = #list end
        end
    end
    return list[at % math.max(1, #list) + 1] or now
end

local function Build()
    -- (the glass, the title, the close button, Escape, dragging and the saved place are QuietKit's)
    local frame = UI.Window("QuietProfessionsWindow", "Quiet Professions", WIDTH, HEIGHT, function()
        return ns.DB().window
    end)

    -- Which profession: a button for each one you have, and one for the rest (Refresh shows and places them)
    frame.profs = {}
    for i, id in ipairs(ns.professionOrder) do
        local b = UI.Button(frame, ns.professions[id].name, function()
            page = 1
            ns.SetProfession(id)
        end, 150)
        b.id = id
        b:SetPoint("TOPLEFT", 16 + (i - 1) * 156, -46)
        frame.profs[i] = b
    end
    frame.others = UI.Button(frame, "Others", function()
        page = 1
        ns.SetProfession(NextOther())
    end, 150)
    frame.others:SetPoint("TOPLEFT", 16, -46)
    frame.others:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Other professions")
        GameTooltip:AddLine("The route from the start for a profession you haven't learned. Each press shows the "
            .. "next one.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    frame.others:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- To what skill, and the prices
    local goalLabel = UI.Text(frame, "heading")
    goalLabel:SetPoint("TOPLEFT", 16, -84)
    goalLabel:SetText("Plan to")
    frame.goals = {}
    for i, goal in ipairs(ns.GoalChoices()) do
        local b = UI.Button(frame, tostring(goal), function()
            page = 1
            ns.SetGoal(goal)
        end, 56)
        b.goal = goal
        b:SetPoint("TOPLEFT", 80 + (i - 1) * 62, -78)
        frame.goals[i] = b
    end
    frame.prices = UI.Button(frame, "Check prices", function() ns.CheckPrices() end, 150, true)
    frame.prices:SetPoint("TOPRIGHT", -16, -78)
    frame.prices:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Check prices")
        GameTooltip:AddLine("At the auction house: looks up every material the route could use, about one a second, "
            .. "the route's own first. It only looks; nothing is bought. A press while it runs stops it.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    frame.prices:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The sum
    frame.head = UI.Text(frame, "heading")
    frame.head:SetPoint("TOPLEFT", 16, -114)
    frame.head:SetPoint("RIGHT", -16, 0)
    frame.head:SetWordWrap(false)
    -- (how old the prices are: small, at the right of the heading, under Check prices)
    frame.age = UI.Text(frame, "muted")
    frame.age:SetJustifyH("RIGHT")
    frame.age:SetWordWrap(false)
    frame.age:SetPoint("TOPRIGHT", -16, -116)
    frame.age:SetWidth(200)
    frame.head:SetPoint("RIGHT", frame.age, "LEFT", -8, 0)
    -- (the sums on a line of their own, then what else there is to say: a line each, nothing run together)
    frame.sums = UI.Text(frame, "body")
    frame.sums:SetPoint("TOPLEFT", 16, -136)
    frame.sums:SetPoint("RIGHT", -16, 0)
    frame.sums:SetWordWrap(false)
    frame.notes = {}
    for i = 1, NOTES do
        local line = UI.Text(frame, "small")
        line:SetPoint("TOPLEFT", 16, -158 - (i - 1) * 15)
        line:SetPoint("RIGHT", -16, 0)
        line:SetWordWrap(false)
        frame.notes[i] = line
    end

    -- The lists
    frame.tabs = {}
    for i, t in ipairs(TABS) do
        local b = UI.Button(frame, t.text, function()
            tab, page = t.key, 1
            Refresh()
        end, 78)
        b.key = t.key
        b:SetPoint("TOPLEFT", 16 + (i - 1) * 82, -208)
        frame.tabs[i] = b
    end
    frame.next = UI.Button(frame, "Next", function()
        page = page + 1
        Refresh()
    end, 48)
    frame.next:SetPoint("TOPRIGHT", -16, -208)
    frame.pageText = UI.Text(frame, "muted")
    frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.pageText:SetWidth(40)
    frame.pageText:SetJustifyH("CENTER")
    frame.pageText:SetWordWrap(false)
    frame.prev = UI.Button(frame, "Prev", function()
        page = page - 1
        Refresh()
    end, 48)
    frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -8, 0)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        page = page - delta
        Refresh()
    end)

    -- (what the sums down the right are)
    frame.caption = UI.Text(frame, "muted")
    frame.caption:SetJustifyH("RIGHT")
    frame.caption:SetWordWrap(false)
    frame.caption:SetPoint("TOPRIGHT", -94, -238)
    frame.caption:SetPoint("LEFT", 16, 0)

    frame.rows = {}
    for i = 1, ROWS do frame.rows[i] = Row(frame, i) end
    frame.empty = UI.Text(frame, "muted")
    frame.empty:SetPoint("TOPLEFT", 16, ROW_TOP - 8)
    frame.empty:SetPoint("RIGHT", -16, 0)

    -- (while prices are looked up, the button counts)
    local since = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.5 then return end
        since = 0
        local running, done, total = ns.LookupState()
        if running then frame.prices:SetText("Stop (" .. done .. " of " .. total .. ")") end
    end)
    frame:SetScript("OnShow", function()
        ns.ReadSkills()
        Refresh()
    end)
    return frame
end

function ns.ToggleWindow()
    window = window or Build()
    -- (on a character with things to mail, it opens on that list the first time)
    if not window:IsShown() and not mailShown then
        local me, here = ns.Me(), false
        for _, send in ipairs(ns.SendsFromMe()) do
            -- (what's only to buy shows on every character: it opens to it only where there's no profession to plan)
            if ns.SendText(send) or not (me and next(me.skills)) then here = true end
        end
        if here then tab, page, mailShown = "mail", 1, true end
    end
    window:SetShown(not window:IsShown())
end

-- (the key binding's, Bindings.xml)
function QuietProfessions_ToggleWindow()
    ns.ToggleWindow()
end
BINDING_HEADER_QUIETPROFESSIONS = "Quiet Professions"
BINDING_NAME_QUIETPROFESSIONS_TOGGLE = "Open / close the Quiet Professions route"
