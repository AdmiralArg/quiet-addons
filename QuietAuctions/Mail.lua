-- At a mailbox: Collect takes the gold and the items from your mail, one thing every half second, waiting for the
-- game to finish each before the next (as the game's own "open all mail" does). It stops when your bags are full,
-- when the mail is empty, when the mailbox closes, or when Collect is pressed again. Mail with a cash-on-delivery
-- price is left alone. (What a sold auction brought is counted by Ledger.lua, however the mail is taken.)
-- The window opens by itself at a mailbox only when there's auction mail in it (below).
local _, ns = ...

local PACE = 0.5
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
local TRIES = 4

-- { money, items, skip = { [what] = true }, lastState, lastWhat, strikes } while collecting
local collecting

local function CommandPending()
    if C_Mail and C_Mail.IsCommandPending then
        local ok, pending = pcall(C_Mail.IsCommandPending)
        return ok and pending
    end
    return false
end

function ns.Collecting()
    return collecting ~= nil
end

local function Stop(why)
    local c = collecting
    collecting = nil
    if c then
        ns.Say("Collected " .. ns.Money(c.money) .. " and " .. c.items .. " items. " .. (why or ""))
    end
    ns.Refresh()
end

-- The inbox in a few numbers: what changes when something is taken
local function InboxState(shown)
    local items, money = 0, 0
    for i = 1, shown do
        local _, _, _, _, m, _, _, n = GetInboxHeaderInfo(i)
        items, money = items + (n or 0), money + (m or 0)
    end
    return shown .. ":" .. items .. ":" .. money
end

local function Step()
    local c = collecting
    if not c then return end
    if not ns.at.mail then
        Stop("The mailbox closed.")
        return
    end
    if CommandPending() then
        C_Timer.After(PACE, Step)
        return
    end
    local shown, total = GetInboxNumItems()
    shown = shown or 0
    -- Nothing changed since the last take, a few times running (a unique item you have already): that one is left
    local state = InboxState(shown)
    if c.lastWhat and state == c.lastState then
        c.strikes = c.strikes + 1
        if c.strikes >= TRIES then
            c.skip[c.lastWhat] = true
            c.strikes = 0
        end
    else
        c.strikes = 0
    end
    c.lastState = state

    for i = 1, shown do
        local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(i)
        local mail = tostring(sender) .. "|" .. tostring(subject)
        if (cod or 0) == 0 then
            if (money or 0) > 0 and not c.skip[mail .. "|money"] then
                if c.strikes == 0 then c.money = c.money + money end
                c.lastWhat = mail .. "|money"
                TakeInboxMoney(i)
                C_Timer.After(PACE, Step)
                return
            end
            for a = 1, ((itemCount or 0) > 0 and ATTACHMENTS or 0) do
                local name, _, _, count = GetInboxItem(i, a)
                local what = mail .. "|" .. tostring(name)
                if name and not c.skip[what] then
                    if ns.FreeSlots() == 0 then
                        Stop("Your bags are full.")
                        return
                    end
                    if c.strikes == 0 then c.items = c.items + (count or 1) end
                    c.lastWhat = what
                    TakeInboxItem(i, a)
                    C_Timer.After(PACE, Step)
                    return
                end
            end
        end
    end
    Stop((total or 0) > shown and "More mail is waiting: close the mailbox and open it again." or "The mail is empty.")
end

-- What a press of Collect does now, as a sentence
function ns.CollectLabel()
    if collecting then
        return "Stop collecting (" .. collecting.items .. " items and " .. ns.Money(collecting.money) .. " so far)",
            true
    end
    if not ns.at.mail then return "Collect: at a mailbox", false end
    local ok, shown = pcall(GetInboxNumItems)
    local mails, money = 0, 0
    for i = 1, (ok and shown) or 0 do
        local _, _, _, _, m, cod, _, itemCount = GetInboxHeaderInfo(i)
        if (cod or 0) == 0 and ((m or 0) > 0 or (itemCount or 0) > 0) then
            mails, money = mails + 1, money + (m or 0)
        end
    end
    if mails == 0 then return "Nothing to collect in the mail", false end
    return "Collect " .. mails .. " mail" .. (mails > 1 and "s" or "") .. (money > 0 and (" (" .. ns.Money(money)
        .. " in gold)") or ""), true
end

-- The press. Again while collecting: stops.
function ns.Collect()
    if not ns.Press("collect") then return end
    if collecting then
        Stop("Stopped.")
        return
    end
    if not ns.at.mail then
        ns.Say("Collect works at a mailbox.")
        return
    end
    collecting = { money = 0, items = 0, skip = {}, strikes = 0 }
    ns.Refresh()
    Step()
end

-- ---------- opening the window by itself ----------
-- Only with auction mail to collect: an auction's gold, something bought, or an auction come back (not letters from
-- friends, nor a mail with a cash-on-delivery price). The inbox is read once the game has it (MAIL_INBOX_UPDATE).
local SUBJECTS = {}
for _, format in ipairs({ AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s", AUCTION_WON_MAIL_SUBJECT
    or "Auction won: %s", AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s", AUCTION_REMOVED_MAIL_SUBJECT
    or "Auction cancelled: %s" }) do
    SUBJECTS[#SUBJECTS + 1] = ns.MailPattern(format)
end

local function AuctionMail()
    local ok, shown = pcall(GetInboxNumItems)
    for i = 1, (ok and shown) or 0 do
        local got, _, _, _, subject, money, cod, _, itemCount = pcall(GetInboxHeaderInfo, i)
        if got and (cod or 0) == 0 and ((money or 0) > 0 or (itemCount or 0) > 0) then
            local okInvoice, kind = pcall(GetInboxInvoiceInfo, i)
            if okInvoice and kind then return true end
            for _, pattern in ipairs(SUBJECTS) do
                if type(subject) == "string" and subject:match(pattern) then return true end
            end
        end
    end
    return false
end

local opened = false -- (opened for auction mail this visit: not again, if you close it)

ns.Listen("auctions", { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE" }, function(_, event)
    if event == "MAIL_SHOW" then
        ns.at.mail, opened = true, false
    elseif event == "MAIL_CLOSED" then
        ns.at.mail = false
        if ns.OnPlaceClosed then ns.OnPlaceClosed("mail") end
    elseif event == "MAIL_INBOX_UPDATE" and ns.at.mail and not opened and AuctionMail() then
        opened = true
        if ns.OnPlaceOpened then ns.OnPlaceOpened("mail") end
    end
    ns.Refresh()
end)
