local addonName, privateTable = ...
local Utils = privateTable.Utils

local issecretvalue = issecretvalue or function() return false end

local SEARCH_DEPTH = 5       -- How deep under UIParent named frames are looked for
local MAX_SCREEN_SHARE = 0.5 -- Frames covering more of the screen than this are containers, not HUD elements
local LOOK_EVERY = 0.1

local function Print(msg)
    QuietKit.Print("Quiet HUD", msg)
end

-- Calls what shows the frame list to draw it again (the Frames window, frames.lua)
privateTable.frameListListeners = privateTable.frameListListeners or {}

local function FrameListChanged()
    for _, listener in ipairs(privateTable.frameListListeners) do
        listener()
    end
end

--- Starts fading a frame by its global name or path ("Parent.Key"). Returns true if it was added (or re-enabled).
function privateTable.AddCustomFrame(frameName)
    if not QuietHUDDB or not QuietHUDDB.frames then return false end
    local existing = QuietHUDDB.frames[frameName]
    if existing then
        existing.enabled = true
        Print(privateTable.GetFrameLabel(frameName) .. " is already in the list; it is now fading.")
        FrameListChanged()
        return true
    end

    local frame = privateTable.ResolveFrame(frameName)
    if not frame then
        Print("No frame named " .. frameName .. " right now. Added anyway; it fades once it exists.")
    elseif not Utils.IsFrameAccessible(frame) then
        Print(frameName .. " can't be faded (it is protected or not a frame).")
        return false
    end

    QuietHUDDB.frames[frameName] = privateTable.NewCustomFrameConfig()
    Print("Added " .. frameName .. ". Its settings: the Frames window (/qhud frames), under Picked.")
    FrameListChanged()
    return true
end

--- Stops fading a picked frame and forgets it. Default frames can only be switched off.
function privateTable.RemoveCustomFrame(frameName)
    local config = QuietHUDDB and QuietHUDDB.frames and QuietHUDDB.frames[frameName]
    if not config then
        Print("No frame named " .. frameName .. " in the list.")
        return false
    end
    if not config.custom then
        Print(privateTable.GetFrameLabel(frameName) .. " is a built-in frame; switch it off in the Frames window instead (/qhud frames).")
        return false
    end
    privateTable.ResetFrame(frameName)
    QuietHUDDB.frames[frameName] = nil
    Print("Removed " .. frameName .. ".")
    FrameListChanged()
    return true
end

---------------------------------------------------------------------------
-- Picking a frame on screen: the named HUD element under the cursor (the mouse or
-- the controller's cursor) is outlined; a left-click adds it, a right-click cancels
---------------------------------------------------------------------------
local highlight = CreateFrame("Frame", nil, UIParent)
highlight:SetFrameStrata("TOOLTIP")
highlight:EnableMouse(false)
highlight:Hide()

local EDGE = 2
local edges = {}
for i = 1, 4 do
    local tex = highlight:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(0.2, 0.8, 1.0, 0.9)
    edges[i] = tex
end
edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(EDGE)
edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(EDGE)
edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(EDGE)
edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(EDGE)

local fill = highlight:CreateTexture(nil, "ARTWORK")
fill:SetAllPoints()
fill:SetColorTexture(0.2, 0.8, 1.0, 0.15)

local label = highlight:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("BOTTOMLEFT", highlight, "TOPLEFT", 0, 4)

local hint = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
hint:SetPoint("TOP", UIParent, "TOP", 0, -120)
hint:SetText("Quiet HUD: click an element to fade it. Right-click to cancel.")
hint:Hide()

-- A frame's rectangle in UIParent's coordinates, or nil if it can't be read
local function GetUIRect(frame)
    local left, bottom, width, height = frame:GetRect()
    if issecretvalue(left) or issecretvalue(bottom) or issecretvalue(width) or issecretvalue(height) or not left then
        return nil
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * scale, bottom * scale, width * scale, height * scale
end

-- Shown and not see-through (a bar already faded out isn't what the cursor points at)
local function IsVisibleSafe(frame)
    local visible = frame:IsVisible()
    if issecretvalue(visible) or not visible then return false end
    local alpha = frame:GetEffectiveAlpha()
    return issecretvalue(alpha) or alpha > 0.05
end

-- A name a frame can be found by again: its global name, else a path from its nearest named
-- ancestor through the keys its parents hold it under ("GamepadHUD.Hints.Panel"), or nil
local MAX_PATH_KEYS = 4

local function GetFramePath(frame)
    local name = frame:GetName()
    if type(name) == "string" and _G[name] == frame then
        return name
    end
    local keys = {}
    local current = frame
    while #keys < MAX_PATH_KEYS do
        local parent = current:GetParent()
        if not parent or parent:IsForbidden() then return nil end
        local key
        for k, v in pairs(parent) do
            if v == current and type(k) == "string" and k:match("^[%a_][%w_]*$") then
                key = k
                break
            end
        end
        if not key then return nil end
        table.insert(keys, 1, key)
        local parentName = parent:GetName()
        if type(parentName) == "string" and _G[parentName] == parent then
            return parentName .. "." .. table.concat(keys, ".")
        end
        current = parent
    end
    return nil
end

local function IsPickable(frame)
    return frame ~= highlight and not frame:IsForbidden()
end

-- Where to look: UIParent, and the other frames without a parent (some of the game's own HUD,
-- like the controller's, may not sit under UIParent). WorldFrame holds the nameplates: left out.
local function GetRoots()
    local roots = { UIParent }
    local frame = EnumerateFrames and EnumerateFrames()
    while frame do
        if not frame:IsForbidden() and frame ~= UIParent and frame ~= WorldFrame and frame:GetParent() == nil
            and IsVisibleSafe(frame) then
            table.insert(roots, frame)
        end
        frame = EnumerateFrames(frame)
    end
    return roots
end

-- Calls fn(frame, depth) for every visible frame under the roots, SEARCH_DEPTH levels deep
local function VisitVisibleFrames(roots, fn)
    local function Visit(frame, depth)
        -- (forbidden first: any other call on a forbidden frame is an error)
        if frame:IsForbidden() or not IsVisibleSafe(frame) then return end
        fn(frame, depth)
        if depth < SEARCH_DEPTH then
            for _, child in ipairs({ frame:GetChildren() }) do
                Visit(child, depth + 1)
            end
        end
    end
    for _, root in ipairs(roots) do
        if root == UIParent then
            for _, child in ipairs({ UIParent:GetChildren() }) do
                Visit(child, 1)
            end
        else
            Visit(root, 1)
        end
    end
end

-- Every visible frame under the cursor that can be named and is smaller than a screen container,
-- largest first (the whole HUD element before its parts)
local function FramesUnderCursor(roots)
    local x, y = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    x, y = x / uiScale, y / uiScale
    local screenArea = UIParent:GetWidth() * UIParent:GetHeight()
    local found = {}

    VisitVisibleFrames(roots, function(frame)
        local left, bottom, width, height = GetUIRect(frame)
        if left and IsPickable(frame) and width * height < screenArea * MAX_SCREEN_SHARE
            and x >= left and x <= left + width and y >= bottom and y <= bottom + height then
            local path = GetFramePath(frame)
            if path and not path:find("^QuietHUD") then
                table.insert(found, { frame = frame, path = path, area = width * height })
            end
        end
    end)
    table.sort(found, function(a, b) return a.area > b.area end)
    return found
end

local picking = false
local candidates = {}
local wait = 0
local roots = {}
local rootsAge = 0
local ROOTS_EVERY = 2 -- Frames without a parent are listed again this often (every frame is walked for them)
local PICK_TIMEOUT = 60 -- Picking stops by itself after this long
local pickStarted = 0

-- An options window over the screen (or Quiet HUD's Frames window): picking waits until it's closed
local function IsOptionsOpen()
    if privateTable.FramesWindowShown and privateTable.FramesWindowShown() then return true end
    for _, window in ipairs({ _G.SettingsPanel, _G.InterfaceOptionsFrame, _G.ImprovedForeverConfigFrame }) do
        if window and window:IsShown() then return true end
    end
    return false
end

local function StopPicking()
    picking = false
    highlight:Hide()
    hint:Hide()
    highlight:SetScript("OnUpdate", nil)
end

local function ShowCandidate()
    local candidate = candidates[1] and candidates[1].frame
    if not candidate then
        highlight:SetAlpha(0)
        return
    end
    local left, bottom, width, height = GetUIRect(candidate)
    -- (it can have moved or gone since it was found)
    if not left then
        highlight:SetAlpha(0)
        return
    end
    highlight:ClearAllPoints()
    highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    highlight:SetSize(math.max(width, 1), math.max(height, 1))
    label:SetText(candidates[1].path)
    highlight:SetAlpha(1)
end

local function OnUpdate(self, elapsed)
    wait = wait - elapsed
    if wait > 0 then return end
    wait = LOOK_EVERY
    rootsAge = rootsAge + LOOK_EVERY
    if rootsAge >= ROOTS_EVERY then
        roots = GetRoots()
        rootsAge = 0
    end
    if GetTime() - pickStarted > PICK_TIMEOUT then
        privateTable.CancelPicker("Picking stopped (nothing picked in " .. PICK_TIMEOUT .. " seconds).")
        return
    end
    if IsOptionsOpen() then
        hint:SetText("Quiet HUD: close the options, then click an element to fade it.")
        candidates = {}
    else
        hint:SetText("Quiet HUD: click an element to fade it. Right-click to cancel.")
        -- (an error here must not leave the picker stuck on screen)
        local ok, found = pcall(FramesUnderCursor, roots)
        if not ok then
            privateTable.CancelPicker("Picking stopped by an error: " .. tostring(found))
            return
        end
        candidates = found
    end
    ShowCandidate()
end

local clickWatcher = CreateFrame("Frame")
clickWatcher:SetScript("OnEvent", function(self, event, button)
    if not picking or IsOptionsOpen() then return end
    if button == "RightButton" then
        privateTable.CancelPicker("Picking cancelled.")
        return
    end

    -- Stopped before anything else, so an error below can't leave it running
    privateTable.CancelPicker()
    local ok, found = pcall(FramesUnderCursor, roots)
    if not ok then
        Print("Couldn't read what's under the cursor: " .. tostring(found))
        return
    end
    candidates = found
    local picked = candidates[1]
    if not picked then
        Print("Nothing that can be named there. Try its edge, or /qhud scan.")
        return
    end
    privateTable.AddCustomFrame(picked.path)

    -- The smaller parts under the cursor, in case only one of them should fade
    if #candidates > 1 then
        local others = {}
        for i = 2, math.min(#candidates, 6) do
            table.insert(others, candidates[i].path)
        end
        Print("Inside it: " .. table.concat(others, ", ") .. ". Use /qhud add <name> for just one of those.")
    end
end)

--- Outlines the element under the cursor until a click picks it (or a right-click cancels)
function privateTable.CancelPicker(message)
    StopPicking()
    clickWatcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    if message then Print(message) end
end

function privateTable.StartPicker()
    if picking then
        privateTable.CancelPicker("Picking cancelled.")
        return
    end
    picking = true
    wait = 0
    pickStarted = GetTime()
    roots = GetRoots()
    rootsAge = 0
    hint:Show()
    highlight:SetAlpha(0)
    highlight:Show()
    highlight:SetScript("OnUpdate", OnUpdate)
    -- Registered a moment later, so the click that started picking (a button) doesn't end it
    C_Timer.After(0.2, function()
        if picking then clickWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN") end
    end)
    Print("Picking: click an element to fade it (the mouse, or the controller's cursor). Right-click cancels.")
end

---------------------------------------------------------------------------
-- /qhud scan: every visible element that can be named, written to the SavedVariables on the
-- next /reload (QuietHUDDB.scan), to find what a HUD element is called
---------------------------------------------------------------------------
local MAX_SCAN_ENTRIES = 3000

-- The first text shown in a frame's own font strings, cut short
local function SampleText(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsVisible() then
            local text = region:GetText()
            if type(text) == "string" and not issecretvalue(text) and text ~= "" then
                return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\r\n]+", " "):sub(1, 50))
            end
        end
    end
    return ""
end

function privateTable.ScanFrames()
    if not QuietHUDDB then return end
    local screenArea = UIParent:GetWidth() * UIParent:GetHeight()
    local lines = {}
    VisitVisibleFrames(GetRoots(), function(frame, depth)
        if #lines >= MAX_SCAN_ENTRIES then return end
        local left, bottom, width, height = GetUIRect(frame)
        if not left or width * height >= screenArea * MAX_SCREEN_SHARE or width < 2 or height < 2 then return end
        local path = GetFramePath(frame)
        if not path or path:find("^QuietHUD") then return end
        table.insert(lines, string.format("%s | x=%d y=%d w=%d h=%d | %s | %s",
            path, left, bottom, width, height, frame:GetFrameStrata() or "", SampleText(frame)))
    end)
    table.sort(lines)
    QuietHUDDB.scan = lines
    Print("Scanned " .. #lines .. " visible elements. /reload to save the list (QuietHUD.lua in SavedVariables).")
end
