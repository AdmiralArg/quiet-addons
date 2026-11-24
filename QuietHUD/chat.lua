local addonName, privateTable = ...

-- The calm chat's look beyond fading (config.lua's Chat entries fade it): a fainter background box,
-- and lines that fade sooner, so the chat empties itself when nobody talks. Set on the chat's
-- textures and line timing directly: nothing is written into the chat's own Lua fields or saved
-- settings (that would taint the game's chat code, which handles secret messages), and without
-- Quiet HUD the chat is as it was.

-- The chat window's background pieces (FloatingChatFrame's CHAT_FRAME_TEXTURES)
local BACKGROUND_TEXTURES = CHAT_FRAME_TEXTURES or {
    "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}
-- (the game fades the background back in on mouseover, then out over a moment: ours again after)
local REAPPLY_AFTER_FADE = 1.0

local function ChatFrames()
    local frames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then table.insert(frames, frame) end
    end
    return frames
end

-- The box: every texture of the chat window itself (its lines are in a child frame, untouched),
-- and the named pieces in case some sit elsewhere
-- (Quiet HUD switched off: the game's own, as the chat window's settings have it)
local GAME_LINE_TIME = 120
local function GameAlpha(frame)
    local id = frame.GetID and frame:GetID()
    if GetChatWindowInfo and id then
        local ok, _, _, _, _, _, alpha = pcall(GetChatWindowInfo, id)
        if ok and type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) then return alpha end
    end
    return DEFAULT_CHATFRAME_ALPHA or 0.25
end

local function ApplyBackground(frame)
    local alpha = QuietHUDDB and QuietHUDDB.chatBackground or 0
    if QuietHUDDB and QuietHUDDB.off then alpha = GameAlpha(frame) end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetAlpha(alpha)
        end
    end
    local name = frame:GetName()
    for _, piece in ipairs(BACKGROUND_TEXTURES) do
        local texture = name and _G[name .. piece]
        if texture and texture.SetAlpha then
            texture:SetAlpha(alpha)
        end
    end
end

function privateTable.ApplyChatStyle()
    if not QuietHUDDB then return end
    local lineTime = QuietHUDDB.off and GAME_LINE_TIME or QuietHUDDB.chatLineTime or 30
    for _, frame in ipairs(ChatFrames()) do
        ApplyBackground(frame)
        if frame.SetTimeVisible and frame.SetFading then
            frame:SetFading(true)
            frame:SetTimeVisible(lineTime)
        end
    end
end

-- The chat windows are set up (again) as the world loads and when their settings change
local styler = CreateFrame("Frame")
styler:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(styler.RegisterEvent, styler, "UPDATE_CHAT_WINDOWS")
styler:SetScript("OnEvent", function()
    -- (a moment later: after the game's own chat setup for the same event)
    C_Timer.After(0.5, privateTable.ApplyChatStyle)
end)

-- When the shown chat last got a line: once its lines have faded the chat is empty, and fades
-- away whole (core.lua asks privateTable.IsEntryEmpty). Only the time is kept: the message itself
-- (which may be secret) isn't touched.
local LINE_FADE_DURATION = 4 -- The game's own fade-out of an old line, plus a little
local lastChatLine = GetTime()

for _, frame in ipairs(ChatFrames()) do
    hooksecurefunc(frame, "AddMessage", function(self)
        if self:IsShown() then
            lastChatLine = GetTime()
        end
    end)
end

function privateTable.IsEntryEmpty(entryName, now)
    if entryName ~= "Chat" then return false end
    local lineTime = QuietHUDDB and QuietHUDDB.chatLineTime or 30
    return now - lastChatLine > lineTime + LINE_FADE_DURATION
end

-- Threat Plates' debug lines ("TP - DEBUG: ..."): some of its releases ship with debugging on, and its switch is
-- inside the addon, out of reach. They're dropped on the way to the chat, through the game's own print handler
-- (nothing of the chat frames is changed), so they stay out after Threat Plates updates. Its warnings, errors and
-- other lines still show.
local TP_DEBUG = "|cff89F559TP|r - |cff0000ffDEBUG|r:"
local issecretvalue = issecretvalue or function() return false end
if getprinthandler and setprinthandler then
    local previous = getprinthandler()
    if previous then
        setprinthandler(function(first, ...)
            if not issecretvalue(first) and first == TP_DEBUG then return end
            return previous(first, ...)
        end)
    end
end

-- The game sets the chat's background from its saved settings (after login, as they load, and
-- when changed): ours again right after
if FCF_SetWindowAlpha then
    hooksecurefunc("FCF_SetWindowAlpha", function(frame)
        if frame and frame.GetRegions then ApplyBackground(frame) end
    end)
end

if FCF_FadeOutChatFrame then
    hooksecurefunc("FCF_FadeOutChatFrame", function(frame)
        C_Timer.After(REAPPLY_AFTER_FADE, function()
            if frame then ApplyBackground(frame) end
        end)
    end)
end
