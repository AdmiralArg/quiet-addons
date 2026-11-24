local _, ns = ...

-- The settings page, for QuietKit (QuietKit.lua): Options > AddOns > Quiet, and with a controller Improved Forever's
-- Quiet tab. First what this character does (its role) and who else does what, then the macros for your bars, then
-- the settings (the window's Settings tab has the same ones, for changing them at the auction house). Registered
-- once the saved settings are in (Core.lua calls this), so the page can name your characters.

local ROLE_CHOICES = {
    { value = "none", name = "Nothing" },
    { value = "auctions", name = "Auctions" },
    { value = "crafting", name = "Crafting" },
    { value = "both", name = "Auctions and crafting" },
}

local function RoleNow()
    local auctions, crafting = ns.Does("auctions"), ns.Does("crafting")
    if auctions and crafting then return "both" end
    return auctions and "auctions" or crafting and "crafting" or "none"
end

local function RoleWords(c)
    if c.auctions and c.crafting then return "auctions and crafting" end
    return c.auctions and "auctions" or c.crafting and "crafting" or "nothing"
end

-- Your other characters and what each does: "Mia: auctions and crafting.  Jon: nothing."
local function Others()
    local here = ns.Realm()
    local parts = {}
    for _, c in ipairs(ns.Characters()) do
        if not c.me then
            local name = c.name .. ((c.realm and c.realm ~= here) and (" (" .. c.realm .. ")") or "")
            parts[#parts + 1] = name .. ": " .. RoleWords(c)
        end
    end
    if #parts == 0 then return "Your other characters show here once they've logged in with Quiet Auctions on." end
    return "Your other characters: " .. table.concat(parts, ".  ") .. "."
end

local function Toggle(key, label, tip, section)
    return {
        section = section, label = label, tip = tip,
        get = function() return ns.Setting(key) end,
        set = function(on)
            ns.SetSetting(key, on)
            ns.Changed()
        end,
    }
end

local function Steps(steps, words)
    local list = {}
    for _, v in ipairs(steps) do list[#list + 1] = { value = v, name = words(v) } end
    return list
end

function ns.RegisterPage()
    local me = UnitName("player") or "This character"
    local items = {
        {
            section = "What " .. me .. " does",
            label = "Role",
            tip = "Auctions: this character buys, sells, posts and collects the mail. At the auction house it scans and "
                .. "watches while its window is open, and waits while you use the game's own auction pages; its "
                .. "window opens by itself where there's work. Crafting: its recipes count in the Crafting tab (open "
                .. "its profession windows once). Nothing: Quiet Auctions rests on this character.\n" .. Others(),
            options = ROLE_CHOICES,
            get = RoleNow,
            set = function(value)
                ns.SetRoles(value == "auctions" or value == "both", value == "crafting" or value == "both")
            end,
        },
    }

    -- The macros, made only from here (or /qah macros)
    for i, m in ipairs(ns.MACROS) do
        items[#items + 1] = {
            section = i == 1 and "Macros for your bars (for the Auctions character)" or nil,
            label = m.label .. ' ("' .. m.name .. '")',
            tip = m.tip,
            macro = m,
        }
    end

    local function Add(item) items[#items + 1] = item end
    Add({
        section = "Buying",
        label = "Under vendor price by at least",
        tip = "Buy only what's listed at least this far under what a vendor pays for it.",
        min = 0, max = 90, step = 1,
        get = function() return ns.Setting("margin") end,
        set = function(v) ns.SetSetting("margin", v) end,
        format = function(v) return v .. "%" end,
    })
    Add({
        label = "Least profit for a press",
        tip = "A purchase that would make less than this isn't worth a press.",
        options = function() return Steps(ns.PROFIT_STEPS, ns.Money) end,
        get = function() return ns.Setting("minProfit") end,
        set = function(v) ns.SetSetting("minProfit", v) end,
    })
    Add({
        label = "Most stacks one press buys",
        tip = "Of ore, cloth, herbs and such (bought by the stack).",
        options = function() return Steps(ns.STACK_STEPS, function(v) return v .. (v == 1 and " stack" or " stacks") end) end,
        get = function() return ns.Setting("stacks") end,
        set = function(v) ns.SetSetting("stacks", v) end,
    })
    Add(Toggle("resale", "Also buy gear to resell (risky)",
        "Gear listed well under its usual auction price, bought last, after everything under vendor price. It may "
            .. "not sell."))
    Add({
        section = "Posting",
        label = "Never post under vendor price plus",
        tip = "After the auction house's cut. Post leaves alone anything that would sell for less.",
        min = 0, max = 500, step = 5,
        get = function() return ns.Setting("floor") end,
        set = function(v) ns.SetSetting("floor", v) end,
        format = function(v) return v .. "%" end,
    })
    Add({
        label = "Auctions last",
        options = { { value = 1, name = "12 hours" }, { value = 2, name = "24 hours" }, { value = 3, name = "48 hours" } },
        get = function() return ns.Setting("duration") end,
        set = function(v) ns.SetSetting("duration", v) end,
    })
    Add(Toggle("posting", "Post stacks from your bags too",
        "Materials and such that sell well over vendor price. Your unbound BoEs are always posted first."))
    Add(Toggle("watch", "Watch the items that pay", "Between full scans, look again and again at the items that "
        .. "often dip under vendor price, so a new bargain is seen within moments.", "At the auction house"))
    Add(Toggle("autoScan", "Scan by itself", "A full scan whenever one is allowed (every 15 minutes) while its "
        .. "window is open."))
    Add(Toggle("autoOpen", "Open the window where there's work", "At the auction house; at a mailbox with auction "
        .. "mail in it; at a vendor when there's something bought to sell. Only on an Auctions character."))
    Add(Toggle("tooltip", "Prices in item tooltips", "Any item's tooltip says its price at the last scan, how many "
        .. "were listed, its usual price, and what a vendor sells it for."))
    Add(Toggle("minimap", "Minimap button", "A button on the minimap's edge: a click opens or closes the window, a "
        .. "right-click opens this page. Drag it round the edge to move it."))
    Add({
        label = "The window",
        tip = "Your profit, what's found, and a button for each press.",
        text = "Open it",
        run = function() SlashCmdList.QUIETAUCTIONS("") end,
    })

    QuietKit.Register({
        key = "quietauctions",
        title = "Quiet Auctions",
        icon = ns.ICON,
        about = "Steady gold for a bank alt: it lists what sells for less than a vendor pays, buys it a press at a "
            .. "time, sells it on at a vendor, posts your BoEs, and shows which recipes pay. It works only on the "
            .. "characters you choose.",
        how = function()
            if ns.Does("auctions") then
                return "Visit the auction house: the window opens there. Each button says what one press does."
            end
            return "Choose what " .. me .. " does below: Auctions for the character that trades, Crafting for one "
                .. "with professions."
        end,
        command = "/qah",
        db = function() return ns.DB().kit end,
        news = { version = "0.3.0", text = "A new Crates tab (or /qah crates): for every profession crate (Waylaid "
            .. "Crate), the bundles that fill it, cheapest first at today's auction prices, with what crafting it "
            .. "would cost where you know the recipe. Crates in your bags come first, with every bundle. And a "
            .. "button on the minimap opens and closes the window (turn it off on the settings page). At the "
            .. "auction house, a click on a line in its lists opens that item's listings. Item tooltips show the "
            .. "last scan's price. And a Plan tab: add what you want (\"Plan this\" under a profession window, or "
            .. "the Plan buttons in Crafting and Crates), and it says what you have on which character, what to make, "
            .. "and what to buy." },
        items = items,
    })
end
