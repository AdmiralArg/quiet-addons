-- At a vendor: Sell sells what Buy bought for vendoring, and only that. Each slot is sold only while the count
-- bought (QuietAuctionsCharDB.bought) covers its whole stack, so your own things, your gear or a stack that is
-- partly yours, are never sold. One press sells the lot, a slot every quarter second (as the game's own "sell all
-- junk" does); closing the vendor stops it at once, so nothing is ever used instead of sold.
-- Bought things that bring clearly more at auction (Ledger.lua) are left for Post instead; a second press of
-- Sell within a few seconds sells them too.
-- It also notes what vendors sell their goods for (thread, vials, flux...): Craft.lua prices recipes with them.
local _, ns = ...

local PACE = 0.25
local ANYWAY = 8 -- (seconds for the second press that sells what pays more at auction too)
local Use = (C_Container and C_Container.UseContainerItem) or UseContainerItem

local selling -- { queue = { { bag, slot, id, count } }, slots, cost (of what's sold), earned (real gold) }
local askedAt = 0 -- (when Sell last said some things pay more at auction)

-- The profit made so far, for the window: profit, vendored, spent, and what the goods still held should bring
function ns.Totals()
    local char = ns.Char()
    local waiting = 0
    for id, b in pairs(char.bought) do
        local vendor = ns.SellPrice(id)
        if vendor then waiting = waiting + vendor * b.n - b.cost end
    end
    return char.totals, waiting
end

-- n of a bought item gone (sold, or put up at auction): off the count. Its share of what they cost, and how many
-- of the n were bought (returned).
function ns.TakeBought(id, n)
    local char = ns.Char()
    local b = char.bought[id]
    if not b or b.n <= 0 then return 0, 0 end
    n = math.min(n, b.n)
    local share = b.cost * n / b.n
    b.n, b.cost = b.n - n, b.cost - share
    if b.n <= 0 then char.bought[id] = nil end
    return share, n
end

-- The bag slots that are wholly bought goods, and how many of those pay more at auction (left out unless anyway)
local function ToSell(anyway)
    local left = {}
    for id, b in pairs(ns.Char().bought) do left[id] = b.n end
    local queue, better = {}, 0
    ns.EachSlot(function(bag, slot, info)
        local id, count = info.itemID, info.stackCount or 1
        if left[id] and left[id] >= count and not info.isLocked and not info.hasNoValue then
            left[id] = left[id] - count
            if not anyway and ns.RepostPays(id, count) then
                better = better + 1
            else
                queue[#queue + 1] = { bag = bag, slot = slot, id = id, count = count }
            end
        end
    end)
    return queue, better
end

function ns.Selling()
    return selling ~= nil
end

-- What a press of Sell does now, as a sentence (what a vendor pays for the lot)
function ns.SellLabel()
    if selling then return "Stop selling (" .. selling.slots .. " stacks sold so far)", true end
    local queue, better = ToSell(GetTime() - askedAt < ANYWAY)
    if #queue == 0 then
        if better > 0 then
            return better .. " bought stacks pay more at auction: press twice to sell them here anyway", true
        end
        return "Nothing bought to sell here", false
    end
    local worth = 0
    for _, item in ipairs(queue) do worth = worth + (ns.SellPrice(item.id) or 0) * item.count end
    return "Sell " .. #queue .. " bought stack" .. (#queue > 1 and "s" or "") .. " at the vendor (+" .. ns.Money(worth)
        .. ")", true
end

-- Done selling: what it came to, in real gold
local function Stop(msg)
    local s = selling
    selling = nil
    if s and s.better > 0 then
        askedAt = GetTime()
        msg = (msg and (msg .. " ") or "") .. s.better .. " stacks that bring more at auction were kept: press Sell "
            .. "again to sell them too."
    end
    if s and s.slots > 0 then
        ns.Say("Sold " .. s.slots .. " stacks for " .. ns.Money(s.earned) .. " (they cost " .. ns.Money(s.cost)
            .. "): " .. ns.Money(s.earned - s.cost) .. "." .. (msg and (" " .. msg) or ""))
    elseif msg then
        ns.Say(msg)
    end
    ns.Refresh()
end

-- Each slot is sold, then checked: it counts as sold only once the stack has left the slot, and what it brought is
-- what your gold actually went up by (waited for, a few seconds at most). The price a vendor really paid for one is
-- kept (QuietAuctionsDB.paid) and used from then on. A stack still there after that wasn't taken: it stays on the
-- bought list, and selling stops, so you can see why.
local Step

local function Check(item, before, tries)
    if not selling then return end
    local info = ns.Slot(item.bag, item.slot)
    local gone = not info or info.itemID ~= item.id or (info.stackCount or 1) ~= item.count
    local gained = GetMoney() - before
    if gone and (gained > 0 or tries >= 15) then
        local share = ns.TakeBought(item.id, item.count)
        local expected = (ns.SellPrice(item.id) or 0) * item.count
        if gained > 0 then
            local each = math.floor(gained / item.count + 0.5)
            if math.abs(each * item.count - expected) > item.count then ns.DB().paid[item.id] = each end
        end
        ns.Log("sell", item.id, item.count, expected, gained)
        local totals = ns.Char().totals
        totals.vendored = (totals.vendored or 0) + math.max(0, gained)
        ns.AddProfit(item.id, "vendor", math.max(0, gained) - share)
        selling.slots, selling.cost, selling.earned = selling.slots + 1, selling.cost + share,
            selling.earned + math.max(0, gained)
        if gained <= 0 then
            Stop("The vendor took " .. ns.ItemName(item.id) .. " but no gold came in for it.")
            return
        end
        C_Timer.After(PACE, Step)
    elseif tries >= 15 then
        Stop("The vendor didn't take " .. ns.ItemName(item.id) .. "; it's still in your bags. Sell it by hand.")
    else
        C_Timer.After(0.2, function() Check(item, before, tries + 1) end)
    end
end

function Step()
    if not selling then return end
    if not ns.at.merchant then
        Stop("The vendor closed; stopped.")
        return
    end
    local item = table.remove(selling.queue, 1)
    if not item then
        Stop()
        return
    end
    -- (still the same stack in that slot?)
    local info = ns.Slot(item.bag, item.slot)
    if info and info.itemID == item.id and (info.stackCount or 1) == item.count and not info.isLocked then
        local before = GetMoney()
        if pcall(Use, item.bag, item.slot) then
            C_Timer.After(0.2, function() Check(item, before, 1) end)
            return
        end
    end
    C_Timer.After(PACE, Step)
end

-- The press. Again while selling: stops.
function ns.Sell()
    if not ns.Press("sell") then return end
    if selling then
        Stop("Stopped.")
        return
    end
    if not ns.at.merchant then
        ns.Say("Sell works at a vendor.")
        return
    end
    -- (a second press soon after Sell said some pay more at auction: those too)
    local anyway = GetTime() - askedAt < ANYWAY
    local queue, better = ToSell(anyway)
    if better > 0 then askedAt = GetTime() end
    if #queue == 0 then
        if better > 0 then
            ns.Say(better .. " stacks bought for vendoring bring more at auction (Post puts them up). "
                .. "Press Sell again to sell them to the vendor anyway.")
        else
            ns.Say("Nothing bought for vendoring in your bags (bought goods come by mail: Collect at a mailbox).")
        end
        return
    end
    selling = { queue = queue, slots = 0, cost = 0, earned = 0, better = better }
    Step()
end

-- What vendors sell things for (only plain gold prices)
local function NoteVendorPrices()
    if not (GetMerchantNumItems and GetMerchantItemID and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return end
    local buyPrices = ns.DB().vendorBuy
    for i = 1, GetMerchantNumItems() or 0 do
        local id = GetMerchantItemID(i)
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if id and ok and type(info) == "table" and info.price and info.price > 0 and not info.hasExtendedCost then
            local each = info.price / math.max(1, info.stackCount or 1)
            if buyPrices[id] ~= each then
                buyPrices[id] = each
                ns.Changed()
            end
        end
    end
end

-- (on any character with a role: an auctions one sells, and a crafting one notes what its materials cost)
ns.Listen("any", { "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE" }, function(_, event)
    if event == "MERCHANT_SHOW" then
        ns.at.merchant = true
        NoteVendorPrices()
        -- (the window by itself only with something bought here to sell)
        if ns.OnPlaceOpened and ns.Does("auctions") and #ToSell() > 0 then ns.OnPlaceOpened("merchant") end
    elseif event == "MERCHANT_CLOSED" then
        ns.at.merchant = false
        if ns.OnPlaceClosed then ns.OnPlaceClosed("merchant") end
    else
        NoteVendorPrices()
    end
    ns.Refresh()
end)
