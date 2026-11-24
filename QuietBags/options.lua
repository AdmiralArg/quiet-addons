local _, ns = ...

-- The settings, once, for QuietKit (QuietKit.lua): it shows them in Options > AddOns > Quiet and, with a controller,
-- on Improved Forever's Quiet tab, and says hello in a small window the first time.
local MACRO = "Quiet Bags"

QuietKit.Register({
    key = "quietbags",
    title = "Quiet Bags",
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    about = "What your other characters carry, in their bags, bank and mail: a window to look through them, with a "
        .. "search box, and a line in item tooltips for who has how many. Turn it on for every character, the bank alt "
        .. "too, and log in once on each.",
    how = function()
        if QuietKit.PadMode() then
            return 'Put the "' .. MACRO .. '" macro (below) on your crossbar: it opens the window.'
        end
        return "/qbags or the round button on your bag window opens it; the macro below puts it on a bar."
    end,
    command = "/qbags",
    db = function() return ns.WelcomeDB() end,
    news = {
        version = "0.2.0",
        text = 'A settings page (Options, AddOns, Quiet), and a "' .. MACRO .. '" macro there that opens the window: '
            .. "put it on your crossbar. The window wears the Quiet look now.",
    },
    items = {
        {
            label = "Open the window",
            tip = 'A macro, "' .. MACRO .. '", that opens and closes the window: on your crossbar it\'s the '
                .. "controller's way in. Click its icon to open the window now, or drag it onto a bar.",
            macro = { name = MACRO, icon = "INV_Misc_Bag_08", body = "/qbags", account = true },
            use = function()
                -- (from Improved Forever's panel: closed first, or the window would open under it)
                local menu = _G.ImprovedForever and _G.ImprovedForever.Menu
                if menu and menu.IsOpen and menu.Close and menu.IsOpen() then pcall(menu.Close) end
                ns.ToggleWindow()
            end,
        },
        {
            label = "Who has it, in item tooltips",
            tip = 'A line under an item for each of your characters that has it: "Mia: 12 (bank 8, bags 4)".',
            get = function() return ns.DB().tooltips ~= false end,
            set = function(on) ns.DB().tooltips = on and true or false end,
        },
        {
            label = "A button on your bag window",
            tip = "A small round button on the game's bag window, by its search box, that opens the window.",
            get = function() return ns.DB().bagButton ~= false end,
            set = function(on)
                ns.DB().bagButton = on and true or false
                if ns.UpdateBagButtons then ns.UpdateBagButtons() end
            end,
        },
    },
})
