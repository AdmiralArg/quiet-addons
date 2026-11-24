local addonName, privateTable = ...

-- The settings, once, for QuietKit (QuietKit.lua): it shows them in Options > AddOns > Quiet and, with a controller,
-- on Improved Forever's Quiet tab, and says hello in a small window the first time. Which frames fade, and how much,
-- is a list of its own: a window (frames.lua) the page has a button for.

local function Print(msg)
    QuietKit.Print("Quiet HUD", msg)
end

-- (whole slider steps to and from the stored values: utils.lua)
local ToSteps, FromSteps = privateTable.ToSteps, privateTable.FromSteps

local function Seconds(steps)
    return string.format("%.1f s", steps / 10)
end

local function Get(key, fallback)
    local value = QuietHUDDB and QuietHUDDB[key]
    if value == nil then return fallback end
    return value
end

local function Set(key, value)
    if QuietHUDDB then
        QuietHUDDB[key] = value
    end
end

-- Improved Forever's panel, closed if it's open: what a button there starts (the picker, a window, a question) is
-- under it otherwise
function privateTable.CloseControllerPanel()
    local IF = _G.ImprovedForever
    local menu = IF and IF.Menu
    if menu and menu.IsOpen and menu.Close and menu.IsOpen() then
        pcall(menu.Close)
    end
end

--- Every setting back to its default, without a reload
local function ResetAllToDefaults()
    if not privateTable.DefaultConfig then return end

    -- Picked frames stay in the list, with their settings back to the defaults
    local pickedFrames = {}
    for frameName, cfg in pairs((QuietHUDDB and QuietHUDDB.frames) or {}) do
        if cfg.custom then
            table.insert(pickedFrames, frameName)
        end
    end

    -- Controller presses (improvedforever.lua) are bindings, not settings: they stay too, and so do the welcome's
    -- marks and which settings were already brought up to date (core.lua)
    local old = QuietHUDDB or {}
    QuietHUDDB = { padBinds = old.padBinds, welcome = old.welcome, settingsVersion = old.settingsVersion }

    for key, value in pairs(privateTable.DefaultConfig) do
        if key ~= "frames" then
            QuietHUDDB[key] = value
        end
    end

    QuietHUDDB.frames = {}
    for frameName, defaultFrameConfig in pairs(privateTable.DefaultConfig.frames or {}) do
        QuietHUDDB.frames[frameName] = {}
        for k, v in pairs(defaultFrameConfig) do
            QuietHUDDB.frames[frameName][k] = v
        end
        privateTable.ResetFrame(frameName)
    end
    for _, frameName in ipairs(pickedFrames) do
        QuietHUDDB.frames[frameName] = privateTable.NewCustomFrameConfig()
    end

    privateTable.RestartTicker()
    if privateTable.ApplyChatStyle then privateTable.ApplyChatStyle() end
    for _, listener in ipairs(privateTable.frameListListeners or {}) do
        listener()
    end
end
privateTable.ResetAllToDefaults = ResetAllToDefaults

StaticPopupDialogs["QUIETHUD_RESET_CONFIRM"] = {
    text = "Put every Quiet HUD setting back to its default, for every frame?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        ResetAllToDefaults()
        QuietKit.Toast("Quiet HUD's settings are back to their defaults.", "Interface\\Icons\\Spell_Holy_Silence")
        -- (the page shows what it read as it opened: drawn again, with the mouse; Improved Forever's reads as it draws)
        if _G.SettingsPanel and _G.SettingsPanel:IsShown() and not QuietKit.PadMode() then
            QuietKit.Open("quiethud")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

QuietKit.Register({
    key = "quiethud",
    title = "Quiet HUD",
    icon = "Interface\\Icons\\Spell_Holy_Silence",
    about = "Fades the HUD while you explore; a fight, a target or the mouse brings it back. The map, the quest list "
        .. "and the chat stay, quietly: faint, at full strength when they have something to say.",
    how = "Nothing to set up. To see everything for a moment, bind \"Show faded frames\" on Improved Forever's "
        .. "Bindings tab, or in Key Bindings, AddOns.",
    command = "/qhud",
    db = function() return QuietHUDDB and QuietHUDDB.welcome end,
    news = {
        version = "0.3.0",
        text = "One switch at the top of its settings turns all of Quiet HUD off, and on again, without a reload: "
            .. "every frame in full, the chat and minimap as the game has them. Or /qhud off, /qhud on.",
    },
    items = {
        {
            label = "Quiet HUD on",
            tip = "Off: nothing of Quiet HUD is left. Every frame shows in full, and the chat and the minimap are as the "
                .. "game has them. On again, the fading takes up where it was. No reload either way. (/qhud off, "
                .. "/qhud on)",
            get = function() return privateTable.IsOn() end,
            set = function(on) privateTable.SetOn(on) end,
        },
        {
            section = "Fading",
            label = "Reveal with the controller",
            tip = "Holding L2 / R2 (the crossbar's modifiers) or pressing the D-pad shows the frames that have a "
                .. "Controller alpha, the crossbar by default. They fade again after the fade delay.",
            get = function() return Get("padReveal", true) end,
            set = function(on) Set("padReveal", on) end,
        },
        {
            label = "Show more on keyboard and mouse",
            tip = "While you play with keyboard and mouse (Alt+Z hides the HUD then), frames with a Mouse alpha use it "
                .. "in place of their Explore alpha: the action bars, unit frames, buffs, minimap, quest list and XP "
                .. "bar stay shown. The controller brings the quiet back.",
            get = function() return Get("mouseShowsMore", true) end,
            set = function(on) Set("mouseShowsMore", on) end,
        },
        {
            label = "Fade time",
            tip = "How long a fade in or out takes, unless a frame has its own.",
            min = 0, max = 20, step = 1,
            get = function() return ToSteps(Get("globalFadeTime", 0.3), 10) end,
            set = function(v) Set("globalFadeTime", FromSteps(v, 10)) end,
            format = Seconds,
        },
        {
            label = "Fade delay",
            tip = "How long a frame stays after what showed it ends (combat, the target, the controller), before it "
                .. "fades.",
            min = 0, max = 100, step = 5,
            get = function() return ToSteps(Get("fadeDelay", 2.0), 10) end,
            set = function(v) Set("fadeDelay", FromSteps(v, 10)) end,
            format = Seconds,
        },
        {
            label = "Show on activity for",
            tip = "How long something that happens shows its part of the HUD: the chat after a message, the quest list "
                .. "after quest progress, the minimap in a new zone, the buffs on a new buff, and your player frame and "
                .. "XP bar when you start or stop resting or level up.",
            min = 10, max = 300, step = 5,
            get = function() return ToSteps(Get("activityTime", 6.0), 10) end,
            set = function(v) Set("activityTime", FromSteps(v, 10)) end,
            format = Seconds,
        },
        {
            label = "Polling rate",
            tip = "How often the frames are looked at. Lower reacts faster and costs a little more.",
            min = 1, max = 50, step = 1,
            get = function() return ToSteps(Get("pollRate", 0.05), 100) end,
            set = function(v)
                Set("pollRate", FromSteps(v, 100))
                privateTable.RestartTicker()
            end,
            format = function(steps) return string.format("%.2f s", steps / 100) end,
        },
        {
            section = "Map and chat",
            label = "Zoom the minimap in indoors",
            tip = "In caves the game's minimap only shows where the cave is mapped, and reads best zoomed all the way "
                .. "in. On, it's kept zoomed in while you're indoors; outdoors your zoom is left alone.",
            get = function() return Get("indoorZoom", true) end,
            set = function(on) Set("indoorZoom", on) end,
        },
        {
            label = "Keep the minimap from going black",
            tip = "When the minimap is shown again after being hidden (Dialogue UI hides the interface while you talk "
                .. "to an NPC; so do Alt+Z and loading screens), the game leaves it a black disc until its zoom "
                .. "changes. On, the zoom is stepped once and put back each time, so it's drawn again.",
            get = function() return Get("minimapRedraw", true) end,
            set = function(on) Set("minimapRedraw", on) end,
        },
        {
            label = "Chat background",
            tip = "How dark the box behind the chat is. 0% shows just its lines; the game's own is 25%.",
            min = 0, max = 100, step = 5,
            get = function() return ToSteps(Get("chatBackground", 0), 100) end,
            set = function(v)
                Set("chatBackground", FromSteps(v, 100))
                if privateTable.ApplyChatStyle then privateTable.ApplyChatStyle() end
            end,
            format = function(v) return v .. "%" end,
        },
        {
            label = "Chat lines fade after",
            tip = "How long a chat line stays before it fades away, so the chat empties itself when nobody talks. The "
                .. "game's own is 2 minutes.",
            min = 5, max = 120, step = 5,
            get = function() return Get("chatLineTime", 30) end,
            set = function(v)
                Set("chatLineTime", v)
                if privateTable.ApplyChatStyle then privateTable.ApplyChatStyle() end
            end,
            format = function(v) return v .. " s" end,
        },
        {
            section = "Frames",
            label = "Which frames fade, and how much",
            tip = "A window with every frame Quiet HUD can fade: switch each on or off, and set how much of it shows "
                .. "while you explore, fight, have a target, point at it or hold the controller's triggers.",
            text = "Frames",
            run = function()
                privateTable.CloseControllerPanel()
                privateTable.ShowFramesWindow()
            end,
        },
        {
            label = "Pick a frame on screen",
            tip = "Outlines the element under the cursor: click it (with the mouse, or the controller's cursor) to fade "
                .. "it too; right-click cancels. With the options open, picking waits until they're closed. It shows up "
                .. "under Picked in the Frames window.",
            text = "Pick",
            run = function()
                privateTable.CloseControllerPanel()
                privateTable.StartPicker()
            end,
        },
        {
            label = "Reset all settings",
            tip = "Puts every Quiet HUD setting back to its default, for every frame (it asks first). Frames you picked "
                .. "stay in the list.",
            text = "Reset",
            run = function()
                privateTable.CloseControllerPanel()
                StaticPopup_Show("QUIETHUD_RESET_CONFIRM")
            end,
        },
    },
})

-- (Quiet HUD off: its other settings are left out of the page, only the switch stays)
for i, item in ipairs(QuietKit.pages.quiethud.items) do
    if i > 1 then item.hidden = function() return not privateTable.IsOn() end end
end

--- Key Bindings (Bindings.xml)
BINDING_HEADER_QUIETHUD = "Quiet HUD"
BINDING_NAME_QUIETHUD_PEEK = "Show faded frames (hold)"
BINDING_NAME_QUIETHUD_TOGGLE = "Show / hide faded frames"

--- Slash Commands
SLASH_QUIETHUD1 = "/qhud"
SLASH_QUIETHUD2 = "/quiethud"
SlashCmdList["QUIETHUD"] = function(msg)
    local command, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()
    if command == "off" or command == "on" then
        privateTable.SetOn(command == "on")
        Print(command == "on" and "on: the HUD fades while you explore again."
            or "off: every frame shows in full, the chat and minimap as the game has them. /qhud on brings it back.")
    elseif command == "pick" then
        privateTable.StartPicker()
    elseif command == "frames" then
        privateTable.ShowFramesWindow()
    elseif command == "scan" then
        local ok, err = pcall(privateTable.ScanFrames)
        if not ok then
            Print("the scan stopped by an error: " .. tostring(err))
        end
    elseif command == "add" or command == "remove" then
        if rest == "" then
            Print("/qhud " .. command .. " <FrameName> (/fstack shows a frame's name)")
        elseif command == "add" then
            privateTable.AddCustomFrame(rest)
        else
            privateTable.RemoveCustomFrame(rest)
        end
    elseif command == "help" then
        Print("the commands:")
        print("  /qhud  the settings;  /qhud off, /qhud on  all of Quiet HUD;  /qhud frames  which frames fade, and how much")
        print("  /qhud pick  click an element on screen to fade it (right-click cancels)")
        print("  /qhud add <FrameName>;  /qhud remove <FrameName>  (/fstack shows a frame's name)")
        print("  /qhud scan  list what's on screen (saved with the settings on the next /reload)")
    elseif not QuietKit.Open("quiethud") then
        -- (gamepad mode without Improved Forever: the game's options can't be opened from addon code then)
        Print("the settings are in Options, AddOns, Quiet, Quiet HUD. /qhud help lists the commands.")
    end
end
