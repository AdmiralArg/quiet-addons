local addonName, privateTable = ...

privateTable.DefaultConfig = {

    globalFadeTime = 0.3,
    pollRate = 0.05,
    fadeDelay = 2.0, -- Grace period (in seconds) before fading out
    padReveal = true, -- Holding the crossbar modifiers (L2 / R2) or pressing the D-pad reveals frames with a Pad Alpha
    activityTime = 6.0, -- How long a chat message, quest progress or a new zone shows the frames it concerns
    chatBackground = 0.0, -- The chat window's background (0 = none; the game's own is 0.25)
    chatLineTime = 30, -- Seconds a chat line stays before it fades (the game's own: 120)
    indoorZoom = true, -- Indoors (caves), the minimap is kept zoomed all the way in (minimap.lua)
    minimapRedraw = true, -- Each time the minimap is shown again, its zoom is stepped and put back, so it isn't left black
    mouseShowsMore = true, -- On keyboard and mouse, a frame's Mouse Alpha takes the place of its Explore alpha

    frames = {
        -- WoW Forever's controller crossbar (Blizzard_GamepadActionBars)
        ["GamepadMainActionBarFrame"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            alphaPad = 1.0, -- -1 or nil = controller input doesn't reveal this frame
            hookChildren = true
        },
        -- The controller's button hints (top left: L1 / R1 targeting, ping, auto-run)
        ["GamepadPersistentInputLegend"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 0.0,
            alphaTarget = 0.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        -- The party / raid manager: the drawer at the left edge while in a group
        ["CompactRaidFrameManager"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 0.0,
            alphaTarget = 0.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MainMenuBar"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1, -- -1 = use globalFadeTime
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["PlayerFrame"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            alphaHealthLow = 0.5,
            alphaManaLow = 0.5,
            hookChildren = false
        },
        ["TargetFrame"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = false
        },
        ["CompactPartyFrame"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["FocusFrame"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = false
        },
        ["ObjectiveTrackerFrame"] = {
            -- Calm: readable but quiet; out of the way in combat, full on hover, peek or quest progress
            enabled = true,
            duration = -1,
            alphaExplore = 0.5,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 0.0,
            alphaTarget = 0.5,
            alphaHover = 1.0,
            hookChildren = true
        },
        -- The minimap's decorations (zone bar, clock, calendar, ring, buttons): only on hover, peek or a new zone
        ["MinimapDetails"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 0.0,
            alphaTarget = 0.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        -- The quest list's section headers ("All Objectives", "Quests"): only on hover, peek or quest progress
        ["QuestListHeaders"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 0.0,
            alphaTarget = 0.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        -- Calm chat: its lines soft (loot and notices included), full for a while when you're
        -- whispered or your party, raid or guild talks, and while you type
        ["Chat"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.6,
            alphaCombat = 0.4,
            alphaTarget = 0.6,
            alphaHover = 1.0,
            hookChildren = true
        },
        -- The chat's tabs, input box and buttons: only while you type, hover or peek
        ["ChatDetails"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 0.0,
            alphaTarget = 0.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["BuffFrame"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["PetActionBar"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["StanceBar"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["BagsBar"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MicroMenu"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MainActionBar"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBarBottomRight"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBarBottomLeft"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBar6"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBar5"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBar7"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBarRight"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MultiBarLeft"] = {
            enabled = false, -- action bars stay shown (on here fades them)
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["MainStatusTrackingBarContainer"] = {
            enabled = true,
            duration = -1,
            alphaExplore = 0.0,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 1.0,
            alphaTarget = 1.0,
            alphaHover = 1.0,
            hookChildren = true
        },
        ["Minimap"] = {
            -- Calm: the map itself stays faintly visible; full on hover, peek or a new zone
            enabled = true,
            duration = -1,
            alphaExplore = 0.6,
            alphaMouse = 1.0, -- on keyboard and mouse, in place of Explore (-1 or nil = as Explore)
            alphaCombat = 0.25,
            alphaTarget = 0.6,
            alphaHover = 1.0,
            hookChildren = true
        }
    }
}

-- Option groups (shared by the Blizzard options panel and the Improved Forever tab)
privateTable.GroupOrder = { "Gamepad", "Action Bars", "Unit Frames", "Map & Quests", "Chat & Buffs", "Menus & Bags", "HUD & Trackers", "Picked", "Other" }

privateTable.FrameGroups = {
    ["GamepadMainActionBarFrame"] = "Gamepad",
    ["GamepadPersistentInputLegend"] = "Gamepad",
    ["CompactRaidFrameManager"] = "Unit Frames",
    ["MainMenuBar"] = "Action Bars",
    ["MainActionBar"] = "Action Bars",
    ["PetActionBar"] = "Action Bars",
    ["MultiBarBottomLeft"] = "Action Bars",
    ["MultiBarBottomRight"] = "Action Bars",
    ["MultiBarLeft"] = "Action Bars",
    ["MultiBarRight"] = "Action Bars",
    ["MultiBar5"] = "Action Bars",
    ["MultiBar6"] = "Action Bars",
    ["MultiBar7"] = "Action Bars",
    ["StanceBar"] = "Action Bars",
    ["PlayerFrame"] = "Unit Frames",
    ["TargetFrame"] = "Unit Frames",
    ["FocusFrame"] = "Unit Frames",
    ["CompactPartyFrame"] = "Unit Frames",
    ["BagsBar"] = "Menus & Bags",
    ["MicroMenu"] = "Menus & Bags",
    ["ObjectiveTrackerFrame"] = "Map & Quests",
    ["QuestListHeaders"] = "Map & Quests",
    ["Minimap"] = "Map & Quests",
    ["MinimapDetails"] = "Map & Quests",
    ["Chat"] = "Chat & Buffs",
    ["ChatDetails"] = "Chat & Buffs",
    ["BuffFrame"] = "Chat & Buffs",
    ["MainStatusTrackingBarContainer"] = "HUD & Trackers"
}

-- Readable names for frames whose global name isn't self-explanatory
privateTable.FrameLabels = {
    ["GamepadMainActionBarFrame"] = "Controller Action Bar",
    ["CompactPartyFrame"] = "Party Frames",
    ["GamepadPersistentInputLegend"] = "Controller Hints",
    ["CompactRaidFrameManager"] = "Party / Raid Manager",
    ["ChatDetails"] = "Chat Tabs & Input",
    ["MicroMenu"] = "Menu Buttons",
    ["BagsBar"] = "Bag Buttons",
    ["MainStatusTrackingBarContainer"] = "XP Bar",
    ["ObjectiveTrackerFrame"] = "Quest List",
    ["QuestListHeaders"] = "Quest List Headers",
    ["MinimapDetails"] = "Minimap Details",
    ["BuffFrame"] = "Buffs"
}

-- Entries that fade several frames under one setting (paths reach into a frame: "MinimapCluster.BorderTop").
-- Names from both the current and older clients; the ones a client doesn't have are skipped.
privateTable.FrameTargets = {
    ["MinimapDetails"] = {
        "MinimapCluster.BorderTop", "MinimapCluster.ZoneTextButton", "MinimapCluster.Tracking",
        "MinimapCluster.IndicatorFrame", "MinimapCluster.InstanceDifficulty", "MinimapCompassTexture",
        "Minimap.ZoomIn", "Minimap.ZoomOut", "GameTimeFrame", "TimeManagerClockButton",
        "AddonCompartmentFrame", "ExpansionLandingPageMinimapButton",
        "MinimapBorder", "MinimapBorderTop", "MinimapZoneTextButton", "MiniMapTracking",
        "MiniMapWorldMapButton", "MinimapZoomIn", "MinimapZoomOut", "MiniMapMailFrame"
    },
    ["QuestListHeaders"] = {
        "ObjectiveTrackerFrame.Header", "QuestObjectiveTracker.Header", "CampaignQuestObjectiveTracker.Header",
        "AchievementObjectiveTracker.Header", "BonusObjectiveTracker.Header", "WorldQuestObjectiveTracker.Header",
        "ProfessionsRecipeTracker.Header", "MonthlyActivitiesObjectiveTracker.Header",
        "AdventureObjectiveTracker.Header", "ObjectiveTrackerBlocksFrame.QuestHeader"
    },
    ["Chat"] = { "ChatFrame1", "ChatFrame2" },
    ["ChatDetails"] = {
        "ChatFrame1EditBox", "GeneralDockManager", "ChatFrame1.FloatingChatFrameinputLegend", "ChatFrame1ButtonFrame",
        "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton", "TextToSpeechButtonFrame"
    },
    -- (the newer names, and WoW Forever's own: PartyFrame, StatusTrackingBarManager, MicroButtonAndBagsBar)
    ["CompactPartyFrame"] = { "CompactPartyFrame", "PartyFrame" },
    ["MainStatusTrackingBarContainer"] = { "MainStatusTrackingBarContainer", "StatusTrackingBarManager" },
    ["MicroMenu"] = { "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar" }
}

-- Entries whose hover is another frame's: hovering the minimap shows its details
privateTable.FrameHover = {
    ["ChatDetails"] = "ChatFrame1",
    ["MinimapDetails"] = "MinimapCluster",
    ["QuestListHeaders"] = "ObjectiveTrackerFrame"
}

-- Entries a moment shows for activityTime (core.lua's REVEAL_EVENTS): at their Hover alpha.
-- A kind, or a list of them.
privateTable.FrameReveals = {
    ["Minimap"] = "zone",
    ["MinimapDetails"] = "zone",
    ["ObjectiveTrackerFrame"] = "quest",
    ["QuestListHeaders"] = "quest",
    ["Chat"] = { "chat", "typing" },
    ["ChatDetails"] = "typing",
    ["BuffFrame"] = "buff",
    ["PlayerFrame"] = { "rest", "level" },
    ["MainStatusTrackingBarContainer"] = { "rest", "level" }
}

--- Returns the default and picked frames grouped as { { name = groupName, frames = { frameName, ... } }, ... }, sorted
function privateTable.GetFrameGroups()
    local result, byName = {}, {}
    for _, groupName in ipairs(privateTable.GroupOrder) do
        local group = { name = groupName, frames = {} }
        table.insert(result, group)
        byName[groupName] = group
    end
    for frameName in pairs(privateTable.DefaultConfig.frames) do
        local group = byName[privateTable.FrameGroups[frameName] or "Other"] or byName["Other"]
        table.insert(group.frames, frameName)
    end
    if QuietHUDDB and QuietHUDDB.frames then
        for frameName, config in pairs(QuietHUDDB.frames) do
            if config.custom and not privateTable.DefaultConfig.frames[frameName] then
                table.insert(byName["Picked"].frames, frameName)
            end
        end
    end
    for _, group in ipairs(result) do
        table.sort(group.frames)
    end
    return result
end

function privateTable.GetFrameLabel(frameName)
    return privateTable.FrameLabels[frameName] or frameName
end


-- Settings for a frame added with /qhud pick or /qhud add
function privateTable.NewCustomFrameConfig()
    return {
        enabled = true,
        custom = true,
        duration = -1,
        alphaExplore = 0.0,
        alphaCombat = 1.0,
        alphaTarget = 1.0,
        alphaHover = 1.0,
        alphaPad = -1,
        hookChildren = true
    }
end
