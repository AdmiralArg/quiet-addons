local _, ns = ...

-- A louder splash: while the line is out, sound effects are on and a step louder, so the bite is easy to hear; after,
-- each goes back to what it was, unless it was changed meanwhile. What was there is kept in QuietFishingDB.soundWas
-- too, so a reload mid-cast still gives it back. /qfish sound on | off.
-- The step: half as loud again, at least 10 points, never past 80% and never quieter than you had it. 20% becomes
-- 30%, 50% becomes 75%, 80% and over stay as they are. (It used to be full volume: a blast at 20%.)
local SFX_ON, SFX_VOLUME = "Sound_EnableSFX", "Sound_SFXVolume"
local MIN_STEP, CEILING = 0.1, 0.8

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

local function Enabled()
    return ns.DB().sound ~= false
end

-- What a setting goes to while the line is out, or nil to leave it
local function Raised(name, current)
    if name == SFX_ON then return current ~= "1" and "1" or nil end
    local volume = tonumber(current)
    if not volume then return nil end
    local louder = math.min(CEILING, math.max(volume * 1.5, volume + MIN_STEP))
    if louder <= volume then return nil end
    return string.format("%.2f", louder)
end

-- soundWas: { [cvar] = { was = its value before, ours = ours as the game keeps it } }
local function Raise()
    if not Enabled() then return end
    local kept = ns.DB().soundWas or {}
    for _, name in ipairs({ SFX_ON, SFX_VOLUME }) do
        local current = GetCVar(name)
        local value = current ~= nil and not kept[name] and Raised(name, current)
        if value then
            SetCVar(name, value)
            kept[name] = { was = current, ours = GetCVar(name) }
        end
    end
    ns.DB().soundWas = kept
end

local function Lower()
    local kept = ns.DB().soundWas
    if not kept then return end
    for name, lease in pairs(kept) do
        if GetCVar(name) == lease.ours then SetCVar(name, lease.was) end
    end
    ns.DB().soundWas = nil
end

-- On or off (the settings panels, /qfish sound)
function ns.SetSound(on)
    ns.DB().sound = (not on) and false or nil
    if not on then Lower() end
end

function ns.SoundOn()
    return Enabled()
end

function ns.SoundCommand(arg)
    if arg == "on" or arg == "off" then
        ns.SetSound(arg == "on")
    elseif arg ~= "" then
        ns.Print("/qfish sound on or off.")
        return
    end
    ns.Print("the splash is " .. (Enabled() and "louder while your line is out (half as loud again, up to 80%)."
        or "left as it is (sound off)."))
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED" }) do
    events:RegisterEvent(event)
end
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:SetScript("OnEvent", function(_, event)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- (only Fishing's line; out of combat, where the channel's name isn't secret)
        if InCombatLockdown() then return end
        local name = UnitChannelInfo("player")
        if name and not (issecretvalue and issecretvalue(name)) and name == ns.FishingName() then Raise() end
    else
        Lower()
    end
end)
