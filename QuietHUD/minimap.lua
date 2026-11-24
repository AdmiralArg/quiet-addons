local addonName, privateTable = ...

-- Caves: the game's indoor minimap is drawn only where the cave has map data (the cross-hatched
-- ring is the rest), and reads best zoomed all the way in; the game puts its own zoom back as you
-- move about indoors. While indoors, the minimap is kept zoomed in (QuietHUDDB.indoorZoom).
-- Outdoors the zoom is left alone. So are cities and inns (resting): a city's buildings and arches
-- count as indoors but most have no indoor map, and zoomed in there the minimap is only black.
-- Zoom out by hand indoors and it's left alone until you're outdoors again.

local issecretvalue = issecretvalue or function() return false end

local LOOK_EVERY = 0.5

local zoomedOut = false -- zoomed out by hand since going indoors

local function KeepZoomedIn()
    if not QuietHUDDB or QuietHUDDB.off or QuietHUDDB.indoorZoom == false then return end
    if not (IsIndoors and Minimap and Minimap.GetZoomLevels and Minimap.SetZoom) then return end
    local indoors = IsIndoors()
    if issecretvalue(indoors) then return end
    if not indoors then
        zoomedOut = false
        return
    end
    if zoomedOut or (IsResting and IsResting()) then return end
    local maxZoom = Minimap:GetZoomLevels() - 1
    if Minimap:GetZoom() ~= maxZoom then
        Minimap:SetZoom(maxZoom)
    end
end

-- The minimap's minus button (either name the client has) and the mouse wheel down over it
local zoomOut = (Minimap and Minimap.ZoomOut) or _G.MinimapZoomOut
if zoomOut and zoomOut.HookScript then
    zoomOut:HookScript("OnClick", function() zoomedOut = true end)
end
if Minimap and Minimap.HookScript then
    Minimap:HookScript("OnMouseWheel", function(_, delta)
        if delta < 0 then zoomedOut = true end
    end)
end

-- The black minimap: when the minimap is hidden and shown again, the game shows it without its picture, a black
-- disc with the arrow and blips on it, until the zoom changes. Dialogue UI hides the whole interface, the minimap
-- with it, for every conversation with an NPC (its Hide UI setting), so after talking to quest-givers (Stormwind
-- Keep) the minimap came back black. Hiding the interface (Alt+Z / Ctrl+Z) and loading screens do the same.
-- So each time the minimap is shown again, its zoom is stepped one level and put back (QuietHUDDB.minimapRedraw),
-- which draws the picture again. (The game's own minimap redraw can't be called from an addon.)
local REDRAW_AFTER = 0.1
local STEP_BACK_AFTER = 0.1
local redrawing = false

local function Redraw()
    if redrawing or not QuietHUDDB or QuietHUDDB.off or QuietHUDDB.minimapRedraw == false then return end
    if not (Minimap and Minimap.GetZoom and Minimap.SetZoom and Minimap.GetZoomLevels) then return end
    if not Minimap:IsVisible() then return end
    local zoom, levels = Minimap:GetZoom(), Minimap:GetZoomLevels()
    if issecretvalue(zoom) or issecretvalue(levels) or type(zoom) ~= "number" or type(levels) ~= "number"
        or levels < 2 then
        return
    end
    local step = zoom > 0 and zoom - 1 or zoom + 1
    redrawing = true
    Minimap:SetZoom(step)
    C_Timer.After(STEP_BACK_AFTER, function()
        redrawing = false
        -- (unless something else changed the zoom meanwhile)
        if Minimap:GetZoom() == step then
            Minimap:SetZoom(zoom)
        end
    end)
end

-- (OnShow comes for the minimap itself, and when a frame above it, the whole interface, is shown again)
if Minimap and Minimap.HookScript then
    Minimap:HookScript("OnShow", function()
        C_Timer.After(REDRAW_AFTER, Redraw)
    end)
end
local redrawer = CreateFrame("Frame")
redrawer:RegisterEvent("PLAYER_ENTERING_WORLD")
redrawer:SetScript("OnEvent", function()
    C_Timer.After(1, Redraw)
end)

local watcher = CreateFrame("Frame")
local wait = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    wait = wait - elapsed
    if wait > 0 then return end
    wait = LOOK_EVERY
    KeepZoomedIn()
end)
