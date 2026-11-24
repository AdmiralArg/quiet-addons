-- The two queues behind the Buy and Post buttons (and the QA Buy and QA Post macros). Each press still does exactly
-- one thing, the first in its queue:
--   Buy:  what's listed under vendor price (Buy.lua), then, only with resale on, gear under its usual auction price
--         to resell (Resale.lua, risky). With nothing under vendor price, a press scans, as it always did.
--   Post: your unbound BoEs and the bought things that pay more at auction (BoE.lua), then, only with posting
--         stacks on, the stacks in your bags that sell well (Post.lua).
-- Each also says what a press does now, as a sentence for the button.
local _, ns = ...

-- ---------- Buy ----------
local function BuyResaleNext()
    return not ns.candidates[1] and ns.ResaleTop() ~= nil
end

function ns.BuyQueueLabel()
    if BuyResaleNext() then return ns.ResaleLabel() end
    return ns.BuyLabel()
end

function ns.BuyPress()
    if BuyResaleNext() then ns.BuyResale() else ns.Next() end
end

-- ---------- Post ----------
function ns.PostQueueLabel()
    if not ns.at.auction then return "Post: at the auction house", false end
    local label, on = ns.BoELabel(ns.BoETop())
    if label then return label, on end
    label, on = ns.PostLabel()
    if label then return label, on end
    if ns.Setting("posting") then return "Nothing in your bags is worth posting", false end
    return "No BoEs to post (posting stacks is off: the Settings tab)", false
end

function ns.PostPress()
    if ns.BoEBusy() or ns.BoETop() then
        ns.PostBoE()
    elseif ns.Setting("posting") then
        ns.Post()
    else
        if not ns.Press("post") then return end
        ns.Say("Nothing to post: no unbound BoEs in your bags, and posting stacks is off (the Settings tab).")
    end
end

-- ---------- where to go next (away from the auction house, a vendor and a mailbox) ----------
function ns.WhereNext()
    local _, away, toSell = ns.BoughtCounts()
    local parts = {}
    if toSell > 0 then
        parts[#parts + 1] = toSell .. " bought item" .. (toSell > 1 and "s" or "") .. " to sell: visit a vendor"
    end
    if away > 0 then
        parts[#parts + 1] = away .. " bought item" .. (away > 1 and "s" or "") .. " in the mail: visit a mailbox"
    end
    local boes = ns.BoECount()
    if boes > 0 then
        parts[#parts + 1] = boes .. " thing" .. (boes > 1 and "s" or "") .. " to post: visit the auction house"
    end
    if #parts == 0 then return "Nothing waiting: visit the auction house to look for bargains." end
    return table.concat(parts, ". ") .. "."
end
