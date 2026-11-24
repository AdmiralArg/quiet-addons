local addonName, privateTable = ...
local Utils = privateTable.Utils

-- Fallback for client environments without secret value protection
local issecretvalue = issecretvalue or function() return false end

local activeFades = {}
local currentTargetAlphas = {}
local fadeUntil = {}
local lastActiveAlpha = {}
local pollTicker = nil

-- Timestamps for taint-free out-of-combat health/mana regeneration tracking
local lastHealthTick = 0
local lastManaTick = 0
local REGEN_TICK_WINDOW = 2.2 -- Slightly above WoW's 2.0s natural health regen tick

-- Separate event frame to track regeneration ticks without reading secret values
local regenTracker = CreateFrame("Frame")
regenTracker:RegisterUnitEvent("UNIT_HEALTH", "player")
regenTracker:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")

regenTracker:SetScript("OnEvent", function(self, event, _, powerToken)
    -- Only record clean timestamps; never read UnitHealth/UnitPower or call SetAlpha here
    if event == "UNIT_HEALTH" then
        lastHealthTick = GetTime()
    elseif event == "UNIT_POWER_FREQUENT" then
        if not issecretvalue(powerToken) and powerToken == "MANA" then
            lastManaTick = GetTime()
        end
    end
end)

-- Controller input tracking: which input is in use (hover only means something with a cursor),
-- and the keys that reveal frames with a Pad Alpha. Read with IsKeyDown each tick, so nothing
-- here takes or blocks the controller's buttons.
local PAD_DPAD_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }
local padActive = false
local padModifierKeys = nil

local inputTracker = CreateFrame("Frame")
pcall(inputTracker.RegisterEvent, inputTracker, "GAME_PAD_ACTIVE_CHANGED")
inputTracker:RegisterEvent("UPDATE_BINDINGS")

inputTracker:SetScript("OnEvent", function(self, event, isActive)
    if event == "GAME_PAD_ACTIVE_CHANGED" then
        padActive = isActive and true or false
    elseif event == "UPDATE_BINDINGS" then
        padModifierKeys = nil
    end
end)

-- The keys bound to the crossbar's modifiers (L2 / R2 by default)
local function GetPadModifierKeys()
    if padModifierKeys then return padModifierKeys end
    padModifierKeys = {}
    for _, action in ipairs({ "GAMEPADLEFTMOD", "GAMEPADRIGHTMOD" }) do
        for _, key in ipairs({ GetBindingKey(action) }) do
            table.insert(padModifierKeys, key)
        end
    end
    if #padModifierKeys == 0 then
        padModifierKeys = { "PADLTRIGGER", "PADRTRIGGER" }
    end
    return padModifierKeys
end

local function IsKeyDownSafe(key)
    local down = IsKeyDown(key)
    -- (whether it's secret first: even testing a secret value is an error)
    return not issecretvalue(down) and down and true or false
end

-- True while a crossbar modifier is held or the D-pad is pressed
local function IsPadRevealing()
    if not QuietHUDDB.padReveal then return false end
    for _, key in ipairs(GetPadModifierKeys()) do
        if IsKeyDownSafe(key) then return true end
    end
    for _, key in ipairs(PAD_DPAD_KEYS) do
        if IsKeyDownSafe(key) then return true end
    end
    return false
end

-- Hover counts with the mouse, or with the controller's own cursor (cursor mode), never while
-- the controller drives the game (the hidden mouse cursor may rest over a frame)
local function CanHover()
    if IsGamePadCursorControlEnabled and IsGamePadCursorControlEnabled() then
        return true
    end
    local improvedForever = _G.ImprovedForever
    if improvedForever and improvedForever.Input and improvedForever.Input.Pad then
        return not improvedForever.Input.Pad()
    end
    return not padActive
end

-- Keyboard and mouse in hand (Improved Forever's input: the one used last), not the controller.
-- Then Alt+Z is at hand to hide the whole HUD, so frames with a Mouse Alpha show more.
local function UsingMouse()
    local improvedForever = _G.ImprovedForever
    if improvedForever and improvedForever.Input and improvedForever.Input.Pad then
        return not improvedForever.Input.Pad()
    end
    return not padActive
end

-- Peek: a held binding (or a toggle) that shows every faded frame as hovering would, so frames
-- that only show on hover (the quest tracker, the minimap) can be seen without a cursor
local peekHeld = false
local hudToggled = false

function privateTable.SetPeek(down)
    peekHeld = down and true or false
end
_G.QuietHUD_Peek = privateTable.SetPeek

function privateTable.ToggleHud()
    hudToggled = not hudToggled
end
_G.QuietHUD_ToggleHud = privateTable.ToggleHud

-- Custom frame fader to avoid taint from Blizzard's UIFrameFade API
local customFader = CreateFrame("Frame")
customFader:Hide()

customFader:SetScript("OnUpdate", function(self, elapsed)
    local stillFading = false

    for frame, fade in pairs(activeFades) do
        stillFading = true
        fade.timeLeft = fade.timeLeft - elapsed

        if fade.timeLeft <= 0 then
            frame:SetAlpha(fade.targetAlpha)
            activeFades[frame] = nil
        else
            local progress = 1 - (fade.timeLeft / fade.duration)
            local currentAlpha = fade.startAlpha + (fade.alphaDelta * progress)
            frame:SetAlpha(currentAlpha)
        end
    end

    -- Stop OnUpdate script when no frames are actively fading
    if not stillFading then
        self:Hide()
    end
end)

local function FadeFrame(frame, targetAlpha, duration)
    if not frame then return end

    local currentAlpha = frame:GetAlpha()
    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        frame:SetAlpha(targetAlpha)
        activeFades[frame] = nil
        return
    end

    if duration == nil or duration < 0 then
        duration = (QuietHUDDB and QuietHUDDB.globalFadeTime) or 0.3
    end

    -- Apply immediately if fade duration is set to 0
    if duration <= 0 then
        frame:SetAlpha(targetAlpha)
        activeFades[frame] = nil
        return
    end

    activeFades[frame] = {
        targetAlpha = targetAlpha,
        startAlpha = currentAlpha,
        alphaDelta = targetAlpha - currentAlpha,
        duration = duration,
        timeLeft = duration
    }

    customFader:Show()
end

local function IsShownSafe(frame)
    if not frame then return false end
    local shown = frame:IsShown()
    if issecretvalue(shown) then
        return false
    end
    return shown and true or false
end

local function IsMouseOverSafe(frame)
    if not frame then return false end

    local over = false

    if frame.IsMouseOver then
        over = frame:IsMouseOver()
    elseif MouseIsOver then
        over = MouseIsOver(frame)
    end

    -- Fallback to manual cursor coordinate check if the return value is protected
    if issecretvalue(over) then
        local left, bottom, width, height = frame:GetRect()
        local scale = frame:GetEffectiveScale()
        if issecretvalue(left) or issecretvalue(bottom) or issecretvalue(width) or issecretvalue(height)
            or issecretvalue(scale) or not left or not scale or scale == 0 then
            return false
        end
        local x, y = GetCursorPosition()
        x, y = x / scale, y / scale
        return (x >= left and x <= left + width and y >= bottom and y <= bottom + height)
    end

    return over and true or false
end

local function IsMouseOverHierarchy(frame)
    if not IsShownSafe(frame) then
        return false
    end

    if IsMouseOverSafe(frame) then
        return true
    end

    return false
end

local function IsHovered(frame)
    if not frame then return false end
    return IsMouseOverHierarchy(frame)
end

-- A frame by its global name, or a path into one ("MinimapCluster.BorderTop")
local function ResolveFrame(path)
    local frame = _G[path]
    if frame ~= nil or not path:find(".", 1, true) then
        return frame
    end
    for part in path:gmatch("[^%.]+") do
        if frame == nil then
            frame = _G[part]
        elseif type(frame) == "table" then
            frame = frame[part]
        else
            return nil
        end
        if frame == nil then return nil end
    end
    return frame
end

privateTable.ResolveFrame = ResolveFrame

-- The frames an entry fades: its targets (config.lua's FrameTargets: several pieces under one
-- setting, like the chat's), else the frame of its own name
local targetLists = {}

local function GetTargets(entryName)
    local paths = privateTable.FrameTargets[entryName]
    -- (one list per entry, refilled each tick: targets can appear later, as a tracker section does)
    local targets = targetLists[entryName] or {}
    targetLists[entryName] = targets
    wipe(targets)
    for _, path in ipairs(paths or { entryName }) do
        local frame = ResolveFrame(path)
        if frame and (not Utils or not Utils.IsFrameAccessible or Utils.IsFrameAccessible(frame)) then
            table.insert(targets, frame)
        end
    end
    return targets
end

-- Hovering the entry's hover frame (config.lua's FrameHover: the whole minimap for its details),
-- else any of its targets
local function IsEntryHovered(entryName, targets)
    local hoverPath = privateTable.FrameHover[entryName]
    if hoverPath then
        return IsHovered(ResolveFrame(hoverPath))
    end
    for _, frame in ipairs(targets) do
        if IsHovered(frame) then return true end
    end
    return false
end

-- Moments that show some frames for a while (config.lua's FrameReveals): a chat message,
-- quest progress, a new zone, a new buff, starting or stopping resting, a new level. Holds the last
-- time each happened.
local lastActivity = {}

local REVEAL_EVENTS = {
    chat = {
        -- (people talking to you or your group; say, yell and emotes from passers-by stay calm)
        "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    },
    quest = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_WATCH_UPDATE" },
    zone = { "ZONE_CHANGED_NEW_AREA" },
    rest = { "PLAYER_UPDATE_RESTING" },
    level = { "PLAYER_LEVEL_UP" },
}

local activityTracker = CreateFrame("Frame")
local activityOfEvent = {}
for kind, events in pairs(REVEAL_EVENTS) do
    for _, event in ipairs(events) do
        -- (pcall: an event this client doesn't have is skipped)
        if pcall(activityTracker.RegisterEvent, activityTracker, event) then
            activityOfEvent[event] = kind
        end
    end
end

-- A new buff: only an aura added that is helpful (the change list, not a full refresh such as a
-- loading screen's). Not in combat: the client makes the change list secret there, and the buffs
-- show in combat anyway.
pcall(activityTracker.RegisterUnitEvent, activityTracker, "UNIT_AURA", "player")

local function HasNewBuff(updateInfo)
    -- (whether a value is secret is asked before anything else: even testing a secret is an error)
    if InCombatLockdown() or issecretvalue(updateInfo) or type(updateInfo) ~= "table" then
        return false
    end
    local fullUpdate, added = updateInfo.isFullUpdate, updateInfo.addedAuras
    if issecretvalue(fullUpdate) or issecretvalue(added) or fullUpdate or type(added) ~= "table" then
        return false
    end
    for _, aura in ipairs(added) do
        local helpful = type(aura) == "table" and aura.isHelpful
        if not issecretvalue(helpful) and helpful then
            return true
        end
    end
    return false
end

activityTracker:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_AURA" then
        local _, updateInfo = ...
        if HasNewBuff(updateInfo) then
            lastActivity.buff = GetTime()
        end
        return
    end
    local kind = activityOfEvent[event]
    if kind then
        lastActivity[kind] = GetTime()
    end
end)

-- True while one of an entry's moments (a kind, or a list of them) happened within activityTime
local function IsRevealedByActivity(frameName, now)
    local kinds = privateTable.FrameReveals[frameName]
    if not kinds then return false end
    local window = QuietHUDDB.activityTime or 6
    if type(kinds) == "string" then
        return (now - (lastActivity[kinds] or -math.huge)) < window
    end
    for _, kind in ipairs(kinds) do
        if (now - (lastActivity[kind] or -math.huge)) < window then return true end
    end
    return false
end

-- Evaluates the target alpha for a given frame based on priority rules
local function GetDesiredAlpha(frameName, config, now, inCombat, hasTarget, isMouseOver, padRevealing, onMouse)
    if frameName == "TargetFrame" and not hasTarget then
        fadeUntil[frameName] = 0
        return 0.0
    end
    if frameName == "FocusFrame" and not UnitExists("focus") then
        fadeUntil[frameName] = 0
        return 0.0
    end

    local delay = QuietHUDDB.fadeDelay or 1.5
    local baseExplore = config.alphaExplore or 0.0
    if onMouse and config.alphaMouse ~= nil and config.alphaMouse >= 0 then
        baseExplore = config.alphaMouse
    end

    -- An entry with nothing in it (the chat once its lines have faded, chat.lua) shows only while
    -- it's used: hovered, peeked at, typed in or talked to; not just for combat or a target
    local isEmpty = privateTable.IsEntryEmpty and privateTable.IsEntryEmpty(frameName, now)
    if isEmpty then
        baseExplore = 0.0
    end

    local isHovered = peekHeld or hudToggled or isMouseOver
    local isRevealed = IsRevealedByActivity(frameName, now)
    local padAlpha = config.alphaPad
    local isPadRevealed = padRevealing and padAlpha ~= nil and padAlpha >= 0
    local isPlayerFrame = (frameName == "PlayerFrame")
    local playerHealthIsLow = isPlayerFrame and ((now - lastHealthTick) < REGEN_TICK_WINDOW)
    local playerManaIsLow = isPlayerFrame and ((now - lastManaTick) < REGEN_TICK_WINDOW)

    local activeAlpha = nil
    local updateGraceTimer = true

    -- Priority order: Hover > Pad > Activity > Combat > Target > Health Regen > Mana Regen
    if isHovered and (config.alphaHover or 1.0) ~= baseExplore then
        activeAlpha = config.alphaHover or 1.0
    elseif isPadRevealed and padAlpha ~= baseExplore then
        activeAlpha = padAlpha
    elseif isRevealed and (config.alphaHover or 1.0) ~= baseExplore then
        activeAlpha = config.alphaHover or 1.0
    elseif inCombat and not isEmpty and (config.alphaCombat or 1.0) ~= baseExplore then
        activeAlpha = config.alphaCombat or 1.0
    elseif hasTarget and not isEmpty and (config.alphaTarget or config.alphaCombat or 1.0) ~= baseExplore then
        activeAlpha = config.alphaTarget or config.alphaCombat or 1.0
    elseif playerHealthIsLow and (config.alphaHealthLow or 1.0) ~= baseExplore then
        activeAlpha = config.alphaHealthLow or 1.0
        updateGraceTimer = false -- 2.2s regen tick window already acts as grace period
    elseif playerManaIsLow and (config.alphaManaLow or 1.0) ~= baseExplore then
        activeAlpha = config.alphaManaLow or 1.0
        updateGraceTimer = false -- 2.2s regen tick window already acts as grace period
    end

    -- Refresh grace period timer while an active state is triggered
    if activeAlpha then
        if updateGraceTimer then
            fadeUntil[frameName] = now + delay
        end
        lastActiveAlpha[frameName] = activeAlpha
        return activeAlpha
    end

    -- Maintain last active alpha while within the grace period (fadeDelay)
    if (fadeUntil[frameName] or 0) > now then
        return lastActiveAlpha[frameName] or (config.alphaHover or 1.0)
    end

    return baseExplore
end

local function UpdateFrame(frameName, config, now, inCombat, hasTarget, canHover, padRevealing, onMouse)
    local targets = GetTargets(frameName)
    if #targets == 0 then
        return
    end

    local isMouseOver = canHover and IsEntryHovered(frameName, targets)
    local desiredAlpha = GetDesiredAlpha(frameName, config, now, inCombat, hasTarget, isMouseOver, padRevealing,
        onMouse)

    -- Use frame-specific duration if set (>= 0), otherwise fall back to globalFadeTime
    local duration = QuietHUDDB.globalFadeTime or 0.3
    if config.duration ~= nil and config.duration >= 0 then
        duration = config.duration
    end

    -- Tracked per frame: a target that appears later (a tracker section) still gets its alpha
    for _, frame in ipairs(targets) do
        if currentTargetAlphas[frame] ~= desiredAlpha then
            currentTargetAlphas[frame] = desiredAlpha
            FadeFrame(frame, desiredAlpha, duration)
        elseif not activeFades[frame] then
            -- The game's own code set it back (the chat's input box does as it closes): ours again
            local alpha = frame:GetAlpha()
            if not issecretvalue(alpha) and math.abs(alpha - desiredAlpha) > 0.01 then
                frame:SetAlpha(desiredAlpha)
            end
        end
    end
end

local function PollAllFrames()
    if not QuietHUDDB or not QuietHUDDB.frames or QuietHUDDB.off then return end

    -- Query global states once per tick instead of per frame
    local now = GetTime()
    local inCombat = UnitAffectingCombat("player")
    local hasTarget = UnitExists("target")
    local padRevealing = IsPadRevealing()
    if padRevealing then
        padActive = true -- the game may not have said so yet (GAME_PAD_ACTIVE_CHANGED fires on a switch only)
    end
    local canHover = CanHover()
    local onMouse = QuietHUDDB.mouseShowsMore and UsingMouse()

    -- Typing in the chat keeps it and its input shown
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
        lastActivity.typing = now
    end

    for frameName, config in pairs(QuietHUDDB.frames) do
        if config.enabled then
            UpdateFrame(frameName, config, now, inCombat, hasTarget, canHover, padRevealing, onMouse)
        end
    end
end

-- Restarts the polling ticker (e.g. after initialization or when changing pollRate in options)
function privateTable.RestartTicker()
    if pollTicker then
        pollTicker:Cancel()
    end
    local rate = (QuietHUDDB and QuietHUDDB.pollRate) or 0.05
    pollTicker = C_Timer.NewTicker(rate, PollAllFrames)
end
_G.QuietHUD_RestartTicker = privateTable.RestartTicker

-- Cancels active fades and restores full visibility when a frame module is disabled
function privateTable.ResetFrame(frameName)
    fadeUntil[frameName] = nil
    lastActiveAlpha[frameName] = nil

    for _, frame in ipairs(GetTargets(frameName)) do
        currentTargetAlphas[frame] = nil
        activeFades[frame] = nil
        frame:SetAlpha(1.0)
        if frame.customHidden then
            frame:Show()
            frame.customHidden = false
        end
    end
end
_G.QuietHUD_ResetFrame = privateTable.ResetFrame

-- Quiet HUD as a whole, on or off (QuietHUDDB.off; the first switch of its settings, or /qhud off). Off, nothing of
-- it is left: every frame shown in full, the chat and the minimap as the game has them (chat.lua, minimap.lua). On
-- again, the fading takes up where it was, at once. No reload either way.
function privateTable.IsOn()
    return not (QuietHUDDB and QuietHUDDB.off)
end

function privateTable.SetOn(on)
    if not QuietHUDDB then return end
    QuietHUDDB.off = (not on) or nil
    if not on then
        for frameName in pairs(QuietHUDDB.frames or {}) do privateTable.ResetFrame(frameName) end
        customFader:Hide()
    end
    if privateTable.ApplyChatStyle then privateTable.ApplyChatStyle() end
    if QuietKit.Refresh then QuietKit.Refresh("quiethud") end
end

-- A note (QuietKit's, not chat: it's easy to miss there) a few seconds after you're in the world, so the loading
-- screen doesn't hide it; and after QuietKit's welcome window while that's up, as the two would sit in one place
function privateTable.NoteInWorld(text)
    local function Show(tries)
        local welcome = QuietKit.welcome
        if welcome and welcome:IsShown() and tries < 60 then
            C_Timer.After(2, function() Show(tries + 1) end)
            return
        end
        QuietKit.Toast(text, "Interface\\Icons\\Spell_Holy_Silence")
    end
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(6, function() Show(0) end)
    end)
end

-- Addon initialization and SavedVariables synchronization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")

initFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end

    -- QuietKit's welcome keeps its marks in a table of their own (settings.lua): the defaults filled in below would
    -- make a new player look like one who had Quiet HUD before. had: one who did (what's new, not the welcome).
    local had = QuietHUDDB ~= nil
    QuietHUDDB = QuietHUDDB or {}
    if type(QuietHUDDB.welcome) ~= "table" then
        QuietHUDDB.welcome = { had = had or nil }
    end

    -- 0.2: the chat became calm (soft instead of hidden, its tabs and input apart): the old
    -- Chat settings are replaced by the new defaults once
    if (QuietHUDDB.settingsVersion or 1) < 2 then
        if QuietHUDDB.frames then
            QuietHUDDB.frames["Chat"] = nil
        end
        QuietHUDDB.settingsVersion = 2
    end
    -- 3: the action bars (not the controller's crossbar) are left alone: their fading is switched off once
    if QuietHUDDB.settingsVersion < 3 then
        if QuietHUDDB.frames and privateTable.DefaultConfig then
            for frameName, defaults in pairs(privateTable.DefaultConfig.frames) do
                local saved = QuietHUDDB.frames[frameName]
                if defaults.enabled == false and type(saved) == "table" then
                    saved.enabled = false
                end
            end
        end
        QuietHUDDB.settingsVersion = 3
    end

    if privateTable.DefaultConfig then
        -- 1. Sync top-level settings (excluding the frames table)
        for key, value in pairs(privateTable.DefaultConfig) do
            if key ~= "frames" and QuietHUDDB[key] == nil then
                QuietHUDDB[key] = value
            end
        end

        -- 2. Deep-sync frame configurations and any newly added frame keys
        if privateTable.DefaultConfig.frames then
            QuietHUDDB.frames = QuietHUDDB.frames or {}
            for frameName, defaultFrameConfig in pairs(privateTable.DefaultConfig.frames) do
                if type(QuietHUDDB.frames[frameName]) ~= "table" then
                    QuietHUDDB.frames[frameName] = {}
                end
                for k, v in pairs(defaultFrameConfig) do
                    if QuietHUDDB.frames[frameName][k] == nil then
                        QuietHUDDB.frames[frameName][k] = v
                    end
                end
            end
        end
    end

    -- Quiet HUD replaces ImmersiveFade, which it grew from: both would fade the same frames.
    -- It is switched off for the next load, and the player told so in a note while it is still running (once: it
    -- isn't loaded after that).
    local addons = _G.C_AddOns
    local OLD_ADDON = "ImmersiveFade"
    if addons and addons.DoesAddOnExist and addons.DoesAddOnExist(OLD_ADDON) and addons.DisableAddOn then
        local wasLoaded = addons.IsAddOnLoaded and addons.IsAddOnLoaded(OLD_ADDON)
        pcall(addons.DisableAddOn, OLD_ADDON)
        if wasLoaded then
            privateTable.NoteInWorld("ImmersiveFade is off now: Quiet HUD replaces it. /reload to finish.")
        end
    end

    -- Start ticker after SavedVariables are loaded
    privateTable.RestartTicker()

    self:UnregisterEvent("ADDON_LOADED")
end)
