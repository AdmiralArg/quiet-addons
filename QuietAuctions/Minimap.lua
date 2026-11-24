-- A button on the minimap's edge: a click opens or closes the window (as /qah does), a right-click opens the settings
-- page; drag it round the edge to move it. Where it sits is kept for the whole account (QuietAuctionsDB.minimapAngle,
-- degrees, 0 = right, counter-clockwise). Shown only on a character with a role, and only while the setting is on
-- (the window's Settings tab, the settings page, or /qah minimap on | off).
local _, ns = ...

local SIZE = 31
local DEFAULT_ANGLE = 200 -- (lower left, clear of the game's own buttons)

local button

local function Angle()
    return ns.DB().minimapAngle or DEFAULT_ANGLE
end

-- On the edge at the saved angle; a square minimap (some layouts) puts it on the square's edge
local function Place()
    local rad = math.rad(Angle())
    local x, y = math.cos(rad), math.sin(rad)
    local radius = (Minimap:GetWidth() / 2) + 10
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local diagonal = math.sqrt(2) * radius
        x = math.max(-radius, math.min(x * diagonal, radius))
        y = math.max(-radius, math.min(y * diagonal, radius))
    else
        x, y = x * radius, y * radius
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: the angle from the minimap's middle to the cursor
local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    ns.DB().minimapAngle = math.floor(math.deg(math.atan2(py - my, px - mx)) % 360 + 0.5)
    Place()
end

local function Build()
    local b = CreateFrame("Button", "QuietAuctionsMinimapButton", Minimap)
    b:SetSize(SIZE, SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.OpenSettings()
        else
            SlashCmdList.QUIETAUCTIONS("")
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", FollowCursor)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Quiet Auctions")
        GameTooltip:AddLine("Click: open or close the window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move round the minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Shown or hidden to match the setting and this character's role (Core.lua calls this when either changes)
function ns.UpdateMinimapButton()
    if not Minimap then return end
    local show = ns.Setting("minimap") and ns.Does("any")
    if not show then
        if button then button:Hide() end
        return
    end
    button = button or Build()
    Place()
    button:Show()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    ns.UpdateMinimapButton()
end)
