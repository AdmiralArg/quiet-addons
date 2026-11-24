local addonName, privateTable = ...

-- The settings, once, for QuietKit (QuietKit.lua): it shows them in Options > AddOns > Quiet and, with a controller,
-- on Improved Forever's Quiet tab, and says hello in a small window the first time.

local MACRO = { name = "Hide Names", icon = "Ability_Stealth", body = "/dark", account = true }

QuietKit.Register({
    key = "quietnames",
    saved = "QuietNamesDB",
    title = "Quiet Names",
    icon = privateTable.ICON,
    about = "Softer names over characters' heads, in a font you pick from the game's own or your other addons'; "
        .. "and, if you wish, no names or nameplates at all outside a fight.",
    how = "Pick a font here (it shows after you restart the game), or /dark to hide the names.",
    command = "/qnames",
    db = function() return QuietNamesDB end,
    news = {
        version = "0.3.0",
        text = "No Names is part of Quiet Names now: /dark, its key or the Hide Names macro, and in dungeons the "
            .. "enemies' names can stay. The fonts 0.2 carried couldn't be shared, so names are in the game's own "
            .. "until you pick a font: the game's, or one your other addons add.",
    },
    items = {
        {
            section = "Names over heads",
            label = "Font",
            tip = "The font of the names over characters' heads: the game's own fonts, then any your other addons add. "
                .. "It shows after you exit and start the game again (a /reload isn't enough).",
            options = function()
                local list = {}
                for _, font in ipairs(privateTable.Fonts()) do
                    list[#list + 1] = { value = font.key, name = font.label }
                end
                return list
            end,
            get = function() return (privateTable.Chosen()) end,
            set = function(key) privateTable.SetFont(key) end,
        },
        {
            label = "Every font, side by side",
            tip = "A window with each font written in itself, and names as they'd look in the one you pick.",
            text = "Preview the fonts",
            run = function() privateTable.ToggleWindow() end,
        },
        {
            section = "No names outside a fight",
            label = "Hide names outside a fight",
            tip = "Every name and nameplate goes while you're out of combat; a fight brings them back as you had them. "
                .. "Also /dark. Your settings are put back as the game closes, so nothing stays hidden without it.",
            get = function() return privateTable.DarkOn() end,
            set = function(on) privateTable.SetDark(on) end,
        },
        {
            label = "In dungeons and raids",
            tip = "Keep enemies: their names and nameplates stay, so you see the next pack before you pull it.",
            options = privateTable.INSTANCE_CHOICES,
            get = function() return privateTable.InstanceChoice() end,
            set = function(value) privateTable.SetInstanceChoice(value) end,
        },
        {
            label = "Hide or show the names",
            tip = 'Click the icon to hide or show them now, or drag it onto an action bar: the "' .. MACRO.name
                .. '" macro runs /dark. A key for it is in Key Bindings, under Quiet Names.',
            macro = MACRO,
            use = function() privateTable.ToggleDark() end,
        },
        {
            label = "Names left off",
            tip = "Every name and nameplate setting back to the game's own, if something else left them off.",
            text = "Bring back the names",
            run = function()
                local count = privateTable.GameNames()
                QuietKit.Toast(count == nil and "After the fight, please."
                    or count == 0 and "The game can't say what its own are: set them in Options, Interface, Names."
                    or "Every name and nameplate is back as the game has them.", privateTable.DARK_ICON)
            end,
        },
    },
})
