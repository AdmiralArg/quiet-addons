-- Zone Levels: when you point at a zone on the world map, its level range shows small next to the name the map
-- puts up ("Westfall  10-20"), coloured as quests are for your level. Nothing else.
--
-- WoW Forever's ranges (Mobalytics' zone map, Gamer Guides and Icy Veins, Nov 2026). Shen'dralas and Moonglade
-- have none there yet, so they get no note. Each zone by its map ID (Forever's own, as Questie's Forever data has
-- them): the name the map shows is asked of the game, so it works in any language. The English name is kept beside
-- it, for a map the game can't name.
local ZONES = {
    -- Starting zones
    [1429] = { 1, 10, "Elwynn Forest" }, [1426] = { 1, 10, "Dun Morogh" }, [1438] = { 1, 10, "Teldrassil" },
    [1420] = { 1, 10, "Tirisfal Glades" }, [1411] = { 1, 10, "Durotar" }, [1412] = { 1, 10, "Mulgore" },
    [2521] = { 1, 12, "Zephras Isle" },
    -- 10 to 30
    [1439] = { 10, 20, "Darkshore" }, [1432] = { 10, 20, "Loch Modan" }, [1436] = { 10, 20, "Westfall" },
    [1421] = { 10, 20, "Silverpine Forest" }, [1413] = { 10, 25, "The Barrens" },
    [1433] = { 15, 25, "Redridge Mountains" }, [1442] = { 15, 27, "Stonetalon Mountains" },
    [1440] = { 18, 30, "Ashenvale" }, [1431] = { 18, 30, "Duskwood" }, [1437] = { 20, 30, "Wetlands" },
    [1424] = { 20, 30, "Hillsbrad Foothills" },
    -- 25 to 45
    [1441] = { 25, 35, "Thousand Needles" }, [1416] = { 30, 40, "Alterac Mountains" }, [1443] = { 30, 40, "Desolace" },
    [1417] = { 30, 40, "Arathi Highlands" }, [1434] = { 30, 45, "Stranglethorn Vale" },
    [2548] = { 35, 45, "Riverglades" }, [1418] = { 35, 45, "Badlands" }, [1435] = { 35, 45, "Swamp of Sorrows" },
    [1445] = { 35, 45, "Dustwallow Marsh" },
    -- 40 to 60
    [1444] = { 40, 50, "Feralas" }, [1446] = { 40, 50, "Tanaris" }, [1425] = { 40, 50, "The Hinterlands" },
    [1427] = { 43, 50, "Searing Gorge" }, [1447] = { 45, 55, "Azshara" }, [1419] = { 45, 55, "Blasted Lands" },
    [1449] = { 48, 55, "Un'Goro Crater" }, [1448] = { 48, 55, "Felwood" }, [1428] = { 50, 58, "Burning Steppes" },
    [1422] = { 51, 58, "Western Plaguelands" }, [1423] = { 53, 60, "Eastern Plaguelands" },
    [1451] = { 55, 60, "Silithus" }, [1430] = { 55, 60, "Deadwind Pass" }, [1452] = { 55, 60, "Winterspring" },
    [2482] = { 60, 60, "Mount Hyjal", "Hyjal" },
}

-- The name the map shows -> its zone's levels: the game's own name for each map ID (this client's language), and
-- the English ones. Made the first time the map is open (the game knows its maps by then).
local byName
local function Levels(text)
    if not byName then
        byName = {}
        local MapInfo = C_Map and C_Map.GetMapInfo
        for id, zone in pairs(ZONES) do
            for i = 3, #zone do byName[zone[i]] = zone end
            local ok, info = pcall(MapInfo or error, id)
            local name = ok and type(info) == "table" and info.name
            if type(name) == "string" and name ~= "" then byName[name] = zone end
        end
    end
    return byName[text]
end
local SIZE = 0.6 -- of the zone name's font
local EVERY = 0.05 -- seconds between looks at the map while it's open

-- Nothing of ours goes in the map, and none of its frames or functions are hooked: under the gamepad UI the
-- Forever client takes what's inside the open map into its own navigation, and an addon's part there taints it
-- (closing the map is then blocked; Spoken Places found the same). The note is UIParent's, laid over the map, and
-- only reads the map's zone name.
local frame = CreateFrame("Frame", nil, UIParent)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetSize(1, 1)
frame:SetPoint("CENTER")
local note = frame:CreateFontString(nil, "OVERLAY")
note:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
note:Hide()

local function Range(levels)
    return levels[1] == levels[2] and tostring(levels[1]) or (levels[1] .. "-" .. levels[2])
end

-- Quest colours, worked out here for the middle of the range: red well above you, orange and yellow near you,
-- green easy, grey long past.
local function Colour(levels)
    local gap = math.floor((levels[1] + levels[2]) / 2) - (UnitLevel("player") or 1)
    if gap >= 5 then return 1, 0.1, 0.1 end
    if gap >= 3 then return 1, 0.5, 0.25 end
    if gap >= -2 then return 1, 0.82, 0 end
    if gap >= -8 then return 0.25, 0.75, 0.25 end
    return 0.6, 0.6, 0.6
end

-- The map's zone name: the label its area label provider puts up while you point at a zone (read only)
local name
local function FindName()
    local map = _G.WorldMapFrame
    if not (map and map.dataProviders) then return nil end
    for provider in pairs(map.dataProviders) do
        local label = type(provider) == "table" and provider.Label
        local text = type(label) == "table" and label.Name
        if type(text) == "table" and text.GetText and text.GetStringWidth then return text end
    end
end

-- Just right of the name's text. The map is scaled apart from UIParent: its sizes and places are turned into ours.
local function Place()
    local x, y = name:GetCenter()
    if not x then return false end
    local scale = name:GetEffectiveScale() / frame:GetEffectiveScale()
    local font, size, flags = name:GetFont()
    if font then note:SetFont(font, math.max(9, (size or 20) * SIZE * scale), flags) end
    local width, justify = name:GetStringWidth(), name.GetJustifyH and name:GetJustifyH()
    local right = x + width / 2
    if justify == "LEFT" then
        right = name:GetLeft() + width
    elseif justify == "RIGHT" then
        right = name:GetRight()
    end
    note:ClearAllPoints()
    note:SetPoint("LEFT", UIParent, "BOTTOMLEFT", right * scale + 6, y * scale)
    return true
end

local function Update()
    local map = _G.WorldMapFrame
    if not (map and map:IsVisible()) then return note:Hide() end
    name = name or FindName()
    if not (name and name:IsVisible()) then return note:Hide() end
    local text = name:GetText()
    local plain = type(text) == "string" and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or nil
    local levels = plain and Levels(plain)
    if not levels then return note:Hide() end
    note:SetText(Range(levels))
    note:SetTextColor(Colour(levels))
    if not Place() then return note:Hide() end
    frame:SetAlpha(name.GetEffectiveAlpha and name:GetEffectiveAlpha() or 1)
    note:Show()
end

local waited = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + elapsed
    if waited < EVERY then return end
    waited = 0
    Update()
end)
