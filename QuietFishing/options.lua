local _, ns = ...

-- The settings, once, for QuietKit (QuietKit.lua): it shows them in Options > AddOns > Quiet and, with a controller,
-- on Improved Forever's Quiet tab, and says hello in a small window the first time. The fishing macro is made here
-- (its icon dragged to a bar, or "Put on my bar") or by /qfish macro, never by itself.
local REEL = "once for the pole, again to cast, again when it splashes to reel in."

QuietKit.Register({
    key = "quietfishing",
    saved = "QuietFishingDB",
    title = "Quiet Fishing",
    icon = "Interface\\Icons\\Trade_Fishing",
    about = "One button for fishing: it takes out your fishing pole, casts, and the same key reels in. "
        .. "A few seconds after, your weapons go back on.",
    how = function()
        if ns.PadBindKey and ns.PadBindKey() then
            return "Press your Fish button (Improved Forever's Bindings tab) by water: " .. REEL
        elseif QuietKit.MacroSlot(ns.MACRO) then
            return 'Press "' .. ns.MACRO .. '" on your bar by water: ' .. REEL
        elseif QuietKit.PadMode() then
            if ns.HasPadPress then
                return 'With a controller: give "Fish" a button in Improved Forever\'s Bindings tab (/if), or put '
                    .. "the fishing macro (its settings, or /qfish macro) on your crossbar. Then by water: " .. REEL
            end
            return "Make the fishing macro (its settings, or /qfish macro) and put it on your crossbar from /macro. "
                .. "Then by water: " .. REEL
        end
        return "Put the fishing macro on a bar: drag it from its settings, or /qfish macro. Then by water: " .. REEL
    end,
    command = "/qfish",
    db = function() return ns.DB() end,
    news = {
        version = "0.5.0",
        text = "The fishing macro is made only when you ask for it (its settings, or /qfish macro): a character "
            .. "that doesn't fish no longer gets one. Yours stays where it is. The louder splash is gentler: half as "
            .. "loud again, up to 80%, instead of full volume.",
    },
    items = {
        {
            label = "The fishing button",
            tip = 'Drag "' .. ns.MACRO .. '" onto a bar, or "Put on my bar". By water: ' .. REEL
                .. " It keeps itself up to date as your pole and weapons change."
                .. (ns.HasPadPress and " With a controller, Improved Forever's Bindings tab has a Fish press too." or ""),
            macro = ns.MacroSpec,
        },
        {
            label = "Louder splash while your line is out",
            tip = "Sound effects a step louder while you fish (half as loud again, up to 80%), so the bite is easy to "
                .. "hear; they go back after.",
            get = function() return ns.SoundOn() end, set = function(on) ns.SetSound(on) end,
        },
        {
            label = "The key you fish with also reels in",
            tip = "While the line is out, the key (or controller button) you cast with reels it in. A mouse click "
                .. "can't: right-click the bobber.",
            get = function() return ns.CatchOn() end, set = function(on) ns.SetCatch(on) end,
        },
        {
            label = "Loot catches at once",
            tip = "Whatever you catch goes straight into your bags. Other loot is left as it is.",
            get = function() return ns.LootOn() end, set = function(on) ns.SetLoot(on) end,
        },
        {
            label = "Fishing button on screen",
            tip = "A small button while you fish with no controller connected, for the mouse. Shift-drag it to move it.",
            get = function() return ns.ButtonOn() end, set = function(on) ns.SetButton(on) end,
        },
        {
            label = "Weapons back after",
            tip = "How long your fishing pole stays out after your last cast (with no line in the water) before what "
                .. "it replaced (your weapon, shield or off-hand) goes back on.",
            min = 3, max = 60, step = 1,
            get = function() return ns.Delay() end, set = function(v) ns.SetDelay(v) end,
            format = function(v) return v .. " s" end,
        },
    },
})

-- /qfish options
function ns.OpenOptions()
    if not QuietKit.Open("quietfishing") then
        ns.Print("Options, AddOns, Quiet, Quiet Fishing" .. (ns.PadConnected() and " (or the /qfish commands)." or "."))
    end
end
