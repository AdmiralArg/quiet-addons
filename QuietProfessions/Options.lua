local _, ns = ...

-- The settings, once, for QuietKit (QuietKit.lua): it shows them in Options > AddOns > Quiet and, with a controller,
-- on Improved Forever's Quiet tab, and says hello in a small window the first time.
local MACRO = "Quiet Professions"

QuietKit.Register({
    key = "quietprofessions",
    title = "Quiet Professions",
    icon = "Interface\\Icons\\Trade_BlackSmithing",
    about = "The cheapest way to level a profession from where you are: reckoned from what you have in bags and bank, "
        .. "what the auction house asks today and which recipes you know, with the gear worth making for your "
        .. "characters put in on the way. It also says which plans are worth getting, what sells for more than it "
        .. "costs to make, and for the steps you plan, what your other characters should mail you and what to buy "
        .. "(two presses at the auction house). A tool a recipe needs (a runed rod, a spanner) is on the route once, "
        .. "before the first step that needs it; the basic ones (a hammer, flint and tinder) count as yours. For Blacksmithing, Tailoring, Leatherworking, Engineering, "
        .. "Enchanting, Alchemy, Mining, Cooking and First Aid.",
    how = function()
        if QuietKit.PadMode() then
            return 'Put the "' .. MACRO .. '" macro (below) on your crossbar: it opens the route. Open your '
                .. "profession's window once, and press Check prices at the auction house."
        end
        return "/qprof opens the route. Open your profession's window once (so it knows your recipes), and press "
            .. "Check prices at the auction house."
    end,
    command = "/qprof",
    db = function() return ns.DB() end,
    saved = "QuietProfessionsDB",
    items = {
        {
            label = "Open the route",
            tip = 'A macro, "' .. MACRO .. '", that opens and closes the window: on your crossbar it\'s the '
                .. "controller's way in. Click its icon to open the window now, or drag it onto a bar.",
            macro = { name = MACRO, icon = "Trade_BlackSmithing", body = "/qprof", account = true },
            use = function()
                -- (from Improved Forever's panel: closed first, or the window would open under it)
                local menu = _G.ImprovedForever and _G.ImprovedForever.Menu
                if menu and menu.IsOpen and menu.Close and menu.IsOpen() then pcall(menu.Close) end
                ns.ToggleWindow()
            end,
        },
        {
            section = "What things are worth",
            label = "What I have is free",
            tip = "On: materials in your bags and bank cost the route nothing, so they're used first. Off: they count "
                .. "for what they would sell for, so rare things aren't burned just because you have them.",
            get = function() return ns.Setting("ownFree") end,
            set = function(on) ns.SetSetting("ownFree", on and true or false) end,
        },
        {
            label = "Count my other characters' things",
            tip = "What your other characters on this realm have in bags, bank and mail counts as yours (to be mailed "
                .. "over). Each is known once it has logged in with any Quiet addon on.",
            get = function() return ns.Setting("alts") end,
            set = function(on) ns.SetSetting("alts", on and true or false) end,
        },
        {
            label = "Sell what I make at auction",
            tip = "On: the first one of each piece of gear you make (the first five of stones, rods and such) is "
                .. "counted at what the auction house would bring, just under the cheapest listed and less the "
                .. "house's cut; the rest at what a vendor pays. The route then leans towards things that sell, "
                .. "and makes one each of many things, with a plan to fetch for each. A price asked isn't a sale "
                .. "and auction prices move, so the window gives two sums: what comes back from a vendor, which "
                .. "is sure, and what comes back if it all sells at auction. Off: everything at a vendor's price; "
                .. "the Sell tab still shows what would sell for more than it costs.",
            get = function() return ns.Setting("sellAuction") end,
            set = function(on) ns.SetSetting("sellAuction", on and true or false) end,
        },
        {
            section = "The route",
            label = "Make green recipes too",
            tip = "Off: the route only makes what's orange or yellow in your profession window, so most makings "
                .. "give a point; a green one is used only where nothing else does. On: green ones too, wherever "
                .. "they come out cheapest per point. On average that costs less, but a green gives a point less "
                .. "than every other time, so a run of bad luck eats the materials you bought.",
            get = function() return ns.Setting("greens") end,
            set = function(on) ns.SetSetting("greens", on and true or false) end,
        },
        {
            label = "Cook what my class eats",
            tip = "On: where a food your class eats gives points, the Cooking route makes that one, even when "
                .. "another recipe is cheaper: for a warrior the strength food that gives the most (attack power "
                .. "counts as strength, two for one), then stamina food. The window says how much more that costs. "
                .. "Off: always the cheapest recipe, whatever it feeds.",
            get = function() return ns.Setting("eat") end,
            set = function(on) ns.SetSetting("eat", on and true or false) end,
        },
    },
})
