-- The presses for a gamepad: character macros of ours, "QA Buy", "QA Skip", "QA Post", "QA Sell" and "QA Collect", to
-- put on the crossbar (each does what its button in the window says). They're made only when you ask: from the
-- settings page (drag one to a bar, or "Put on my bar": Options.lua), or /qah macros. Each one /clicks a plain button
-- of ours, and the button does the press (a macro's /click comes from your key, so the game takes it as your press).
-- (A secure button clicked by a macro didn't work on WoW Forever, Quiet Fishing found: so plain buttons.) "QA Next"
-- and "QA BoE", their old names, still work where they are: their buttons are here too.
-- Also the key bindings (Bindings.xml: Key Bindings, AddOns, Quiet Auctions).
-- On a character without the Auctions role a press only says so (ns.OnDuty).
local _, ns = ...

-- Only on a character that does the auction work
local function Duty(press)
    return function()
        if ns.OnDuty() then press() end
    end
end

ns.MACROS = {
    { name = "QA Buy", button = "QuietAuctionsBuyPress", icon = "INV_Misc_Coin_01", label = "Buy",
        tip = "At the auction house: what the window's Buy button says. A press looks the top of the list up, the "
            .. "next buys it.",
        press = function() ns.BuyPress() end },
    { name = "QA Skip", button = "QuietAuctionsSkipPress", icon = "Ability_Rogue_Sprint", label = "Skip this one",
        tip = "At the auction house: the item Buy would buy next goes to the bottom of the list until you log out.",
        press = function() ns.SkipTop() end },
    { name = "QA Post", button = "QuietAuctionsPostPress", icon = "INV_Sword_04", label = "Post",
        tip = "At the auction house: what the window's Post button says (your unbound BoEs first), one auction a "
            .. "press.",
        press = function() ns.PostPress() end },
    { name = "QA Sell", button = "QuietAuctionsSellPress", icon = "INV_Misc_Bag_10", label = "Sell",
        tip = "At a vendor: sells what Buy bought for vendoring, and nothing else.",
        press = function() ns.Sell() end },
    { name = "QA Collect", button = "QuietAuctionsCollectPress", icon = "INV_Letter_15", label = "Collect",
        tip = "At a mailbox: takes the gold and the items from your mail until your bags are full.",
        press = function() ns.Collect() end },
}

-- The plain buttons the macros click. (A /click can come on either edge of the key: both are taken, and ns.Press
-- lets one through.) The old macros' buttons too, doing the new presses.
local function PressButton(name, press)
    local button = CreateFrame("Button", name, UIParent)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetScript("OnClick", Duty(press))
end
for _, m in ipairs(ns.MACROS) do
    m.body = "/click " .. m.button
    PressButton(m.button, m.press)
end
PressButton("QuietAuctionsNextPress", function() ns.BuyPress() end)
PressButton("QuietAuctionsBoEPress", function() ns.PostPress() end)

-- /qah macros: makes the ones missing and puts right any that were changed, and says how it went
function ns.MakeMacros()
    local made, failed = {}, nil
    for _, m in ipairs(ns.MACROS) do
        local ok, why = QuietKit.MacroReady(m)
        if ok then made[#made + 1] = '"' .. m.name .. '"' else failed = why end
    end
    if failed then
        ns.Print(failed)
        return
    end
    ns.Print(table.concat(made, ", ") .. " are ready: drag them from the settings page (/qah settings) or /macro, "
        .. "character macros, onto your bar or crossbar.")
end

-- ---------- key bindings (Bindings.xml) ----------
BINDING_HEADER_QUIETAUCTIONS = "Quiet Auctions"
BINDING_NAME_QUIETAUCTIONS_TOGGLE = "Open / close the Quiet Auctions window"
BINDING_NAME_QUIETAUCTIONS_NEXT = "Buy (what the Buy button says)"
BINDING_NAME_QUIETAUCTIONS_SKIP = "Skip this one (the item Buy would buy next)"
BINDING_NAME_QUIETAUCTIONS_POST = "Post (what the Post button says)"
BINDING_NAME_QUIETAUCTIONS_SELL = "Sell what was bought for vendoring"
BINDING_NAME_QUIETAUCTIONS_COLLECT = "Collect the mail"
BINDING_NAME_QUIETAUCTIONS_CANCEL = "Take down auctions others list for less"

function QuietAuctions_Toggle() SlashCmdList.QUIETAUCTIONS("") end
QuietAuctions_Next = Duty(function() ns.BuyPress() end)
QuietAuctions_Skip = Duty(function() ns.SkipTop() end)
QuietAuctions_Sell = Duty(function() ns.Sell() end)
QuietAuctions_Collect = Duty(function() ns.Collect() end)
QuietAuctions_Post = Duty(function() ns.PostPress() end)
QuietAuctions_Cancel = Duty(function() ns.CancelNext() end)
