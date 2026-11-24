-- Buff Glow (was Battle Shout Glow): while a buff you keep up isn't on you (Battle Shout, a Paladin's aura, blessing
-- or seal, Fortitude...) its button pulses gold, and the moves that open up (Overpower, Revenge, Execute, Hammer of
-- Wrath...) glint blue. A Warrior also gets a rotation light: a slow pale-green ring on the move to press next
-- (/bsg rotation turns it off). For the controller crossbar, which addons may not touch at all, the same shows as
-- icons of our own just above it. What each class keeps up and watches for: CLASSES below.
--
-- What WoW Forever allows (learned the hard way, 2026-11-05):
--  * the controller UI's frames are forbidden to addons: even asking one what it is blocks the addon. So no scanning
--    of frames: only Blizzard's own action buttons, by name, and only when the game says we may touch them.
--  * your buffs are secret in combat: they're read out of combat only, and in a fight a buff counts as up until it
--    was due to run out (or for its time from a cast made in the fight).
--  * nothing of Blizzard's is changed: glows and icons are frames of our own.

-- ---------- what each class keeps up, and what opens up ----------
-- keep: groups of buffs; any one of a group on you counts (a blessing from another paladin too). Spells are given by
--   any rank's ID and matched by name, so every rank counts.
--   duration: seconds a cast lasts (nil: until it's gone, like an aura); combatOnly: only missed in a fight or with an
--   enemy targeted; endedBy: casts that use it up (none now: Judgement did in Classic, not in Forever); onceUsed:
--   only once you've cast it yourself
--   (Righteous Fury: a tank's, not every paladin's); whenUsable: only missed once you could cast it (Battle Shout:
--   with 10 rage, so not out of a fight, when a warrior's rage is gone); weapon: it's put on your weapon, not on
--   you (a shaman's Rockbiter), so it's read from the weapon.
--   The lists are WoW Forever's (wowforevertalents.com, read from the Forever client, build 1.60.1, Nov 2026), not
--   Classic's: there Fortitude, Intellect, Mark of the Wild and the weapon imbues last an hour, Divine Spirit is
--   every priest's at 30, and a hunter has Aspect of the Viper, of the Falcon and Heart of the Lion.
-- react: moves that glint while usable (and off cooldown).
-- rotation: the next move, lit with a steady ring: the first of these you know and can use now, with an enemy
--   targeted. A list per stance (1 Battle, 2 Defensive, 3 Berserker), so the stance you're in picks the spec's way
--   of playing; moves you haven't learned (a talent, a later level) are skipped.
--   wait: still its turn when short of rage (lit dimmer: wait for the rage); quick: a short chance (after a dodge, a
--   block, a kill) that goes first even while a move above waits for rage; opener: only before the fight, and only
--   in range; hurt: only below that share of your health; dot: once per target until it runs out (lasts: so many
--   seconds, where its description doesn't say), not on targets that are nearly dead (bleed: nor on ones that
--   don't bleed); area: a debuff on everything around you, in a fight and in melee range,
--   until it runs out (going by your last cast: enemy debuffs are secret in a fight); notCasters: not against
--   targets with mana (casters, whose hits a shout or a slow doesn't touch); vs: only against these creature types;
--   fastCast: only once a talent has cut its cast time (Slam with Improved Slam); onMe: only while your target is
--   hitting you; tough: only against an elite or a boss; stacks: up to that many on the target (kept topped up);
--   filler: only with that much rage (laterFiller from level 24), and not while already queued; interrupt: only
--   while the target is casting (not a cast the game says can't be interrupted), lit with a quick orange blink.
--   For the other classes (3.7.0): a list for the class ([1]), and for a druid one per form, by the form's spell.
--   again: a buff of your own kept up by your last cast of it (Slice and Dice); combo: only with that many combo
--   points; finish: only once the target is below that share of its health; above: only while it's over it; mana:
--   only with that share of your mana left; powerBelow: only while your energy is under that; minLevel, maxLevel:
--   only at those levels; safe: only while the target isn't hitting you (a long cast); auto: a wand or a bow that
--   goes on by itself, lit only until it does (rest: and while it fires nothing below it is lit: a wand ends
--   the fight); spells and key (in place of spell): one of several moves, the one you used last (a rogue's
--   Sinister Strike or Backstab, a mage's Frostbolt or Fireball: your spec's, without reading talents); ifUsing
--   { key, move }: only while that is the one you use.
--   Each is after its WoW Forever levelling guide on mobalytics.gg (November 2026), named at the list, and the
--   moves are Forever's (Bane of Agony, Wrack, Holy Strike, Shank, Summon Hawk, Rage of the Farseer...). What an
--   addon can't see is left out: how many enemies there are (area moves), procs, your pet, and heals.
local CLASSES = {
    WARRIOR = {
        keep = {
            { key = "shout", spells = { 6673 }, duration = 180, whenUsable = true },  -- Battle Shout
        },
        react = { 7384, 6572, 5308, "Victory Rush" },  -- Overpower, Revenge, Execute, Victory Rush (new in Forever)
        -- After the WoW Forever levelling guide by Ahlaundoh (mobalytics.gg, 6 Nov 2026): Arms (and Fury before 38)
        -- fight in Battle Stance, Protection in Defensive, Fury from 38 in Berserker. Execute is a finisher there, not
        -- a priority ("often a trap"), and Sunder Armor is for bosses (and, by choice, elites). Left out, as an addon
        -- can't count the enemies around you: Cleave and Sweeping Strikes (2+ targets).
        -- Interrupts first in every stance, while the target is casting (interrupt: lit with a quick orange blink);
        -- whichever the stance allows (Shield Bash with a shield in Battle / Defensive, Pummel in Berserker).
        rotation = {
            [1] = {  -- Battle Stance: Arms, and Fury before 38
                { spell = 72, interrupt = true, quick = true },        -- Shield Bash
                { spell = 6552, interrupt = true, quick = true },      -- Pummel
                { spell = 100, opener = true },                        -- Charge
                { spell = "Victory Rush", quick = true, hurt = 0.9 },  -- Victory Rush (new in Forever: heals 10%)
                { spell = 12328 },                                     -- Death Wish (Fury talent: early and often)
                { spell = 7384, quick = true },                        -- Overpower (after a dodge)
                -- Revenge, through your stance macro: the game calls it unusable here, so lit for 5 sec after your
                -- own block, dodge or parry (by choice: you switch stances freely)
                { spell = 6572, quick = true, afterAvoid = true, cost = 5 },
                { spell = 1160, area = true, notCasters = true },      -- Demoralizing Shout
                { spell = 772, dot = true, bleed = true },             -- Rend
                { spell = "Spearing Strike", vs = { Dragonkin = true, Giant = true } },  -- (Arms talent)
                { spell = 12294, wait = true },                        -- Mortal Strike
                { spell = 1464, fastCast = true },                     -- Slam (only with Improved Slam)
                { spell = "Spearing Strike" },                         -- (against anything else)
                { spell = 6343, area = true, notCasters = true },      -- Thunder Clap
                { spell = 5308 },                                      -- Execute (to finish one off)
                { spell = 78, filler = 60, laterFiller = 85 },         -- Heroic Strike
            },
            [2] = {  -- Defensive Stance: Protection
                { spell = 72, interrupt = true, quick = true },        -- Shield Bash
                { spell = 6552, interrupt = true, quick = true },      -- Pummel
                { spell = 100, opener = true },                        -- Charge (with the Vanguard talent)
                { spell = 2565, onMe = true },                         -- Shield Block (on cooldown: opens Revenge)
                { spell = "Victory Rush", quick = true, hurt = 0.9 },  -- Victory Rush
                { spell = 6572, quick = true, wait = true },           -- Revenge (after a block, dodge or parry)
                { spell = 23922, wait = true },                        -- Shield Slam
                { spell = 1160, area = true, notCasters = true },      -- Demoralizing Shout
                { spell = 772, dot = true, bleed = true },             -- Rend
                { spell = 6343, area = true, notCasters = true },      -- Thunder Clap
                { spell = 7386, tough = true, stacks = 5 },            -- Sunder Armor (elites and bosses)
                { spell = 78, filler = 60 },                           -- Heroic Strike
            },
            [3] = {  -- Berserker Stance: Fury from 38
                { spell = 6552, interrupt = true, quick = true },      -- Pummel
                { spell = 72, interrupt = true, quick = true },        -- Shield Bash
                { spell = 20252 },                                     -- Intercept (from range)
                { spell = "Victory Rush", quick = true, hurt = 0.9 },  -- Victory Rush
                { spell = 12328 },                                     -- Death Wish
                { spell = 1160, area = true, notCasters = true },      -- Demoralizing Shout
                { spell = 1680 },                                      -- Whirlwind
                { spell = 23881, wait = true },                        -- Bloodthirst (pool rage for it)
                { spell = 5308 },                                      -- Execute (to finish one off)
                { spell = 78, filler = 60 },                           -- Heroic Strike
            },
        },
        melee = 78,  -- a move whose range is melee range (Heroic Strike): area moves only when it's in range
        mark = 772,  -- Rend: a mark on enemy nameplates in the fight that don't have yours (see "a mark on enemies")
    },
    PALADIN = {
        keep = {
            -- Devotion, Retribution, Concentration, Shadow / Frost / Fire Resistance, Sanctity Aura
            { key = "aura", spells = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },
            -- Blessing of Might, Wisdom, Kings, and their Greater ones (an hour in Forever; Salvation, Light and
            -- Sanctuary are gone)
            { key = "blessing", duration = 3600, spells = { 19740, 19742, 20217, 25782, 25894, 25898 } },
            -- Seal of Righteousness, the Crusader, Command, Wisdom, Light, Justice, Fury (new in Forever). In Forever
            -- Judgement doesn't use the seal up (endedBy would say what does).
            { key = "seal", duration = 30, combatOnly = true,
              spells = { 21084, 21082, 20375, 20166, 20165, 20164, "Seal of Fury" } },
            { key = "fury", spells = { 25780 }, duration = 1800, onceUsed = true },  -- Righteous Fury
        },
        react = { 24275 },  -- Hammer of Wrath
        -- After the Paladin levelling guide by yumytv (12 Nov 2026), Retribution: Exorcism against undead and
        -- demons, then Judgement and Holy Strike whenever they're ready; the seal is the gold pulse above. Left to
        -- you: the opening Seal of the Crusader on long fights, and Consecration (3 enemies or more).
        rotation = {
            [1] = {
                { spell = 879, vs = { Undead = true, Demon = true } },  -- Exorcism
                { spell = 20271 },                                      -- Judgement
                { spell = "Holy Strike" },                              -- (new in Forever)
            },
        },
    },
    PRIEST = {
        keep = {
            { key = "fortitude", spells = { 1243, 21562 }, duration = 3600 },  -- Power Word / Prayer of Fortitude
            { key = "innerfire", spells = { 588 }, duration = 600 },           -- Inner Fire
            { key = "spirit", spells = { 14752, 27681 }, duration = 3600 },    -- Divine Spirit / Prayer of Spirit
        },
        react = {},
        -- After the Priest levelling guide on mobalytics.gg (Nov 2026), Shadow: pull with Mind Blast (Smite before
        -- you have it), Shadow Word: Death below a fifth, Shadow Word: Pain, Devouring Plague, Vampiric Embrace,
        -- Mind Flay while mana lasts, then the wand to the end (casting less lets your mana come back). Left to
        -- you: Power Word: Shield before the pull.
        rotation = {
            [1] = {
                { spell = 15487, interrupt = true, quick = true },  -- Silence (a talent)
                { spell = 8092, opener = true },                    -- Mind Blast
                { spell = 585, opener = true },                     -- Smite
                { spell = "Shadow Word: Death", finish = 0.2 },     -- (new in Forever)
                { spell = 589, dot = true },                        -- Shadow Word: Pain
                { spell = 2944, dot = true },                       -- Devouring Plague
                { spell = 15286, dot = true, lasts = 60 },          -- Vampiric Embrace
                { spell = 15407, mana = 0.4, above = 0.25 },        -- Mind Flay
                { spell = 585, mana = 0.7, above = 0.25 },          -- Smite (with mana to spare)
                { spell = 5019, auto = true, rest = true },         -- Shoot (your wand)
            },
        },
    },
    MAGE = {
        keep = {
            { key = "intellect", spells = { 1459, 23028 }, duration = 3600 },  -- Arcane Intellect / Brilliance
            { key = "armor", spells = { 168, 7302, 6117 }, duration = 1800 },  -- Frost / Ice / Mage Armor
        },
        react = {},
        -- After the Mage levelling guide by Asuna_qt (18 Nov 2026): Arcane Wrath as the first cast and again when
        -- nothing is hitting you, Fire Blast to finish, your spec's main spell between (the one you cast last:
        -- Frostbolt, Fireball, Arcane Blast...), the wand when the mana is gone. Left to you: Arcane Missiles on a
        -- Missile Barrage (a proc), cooldowns, and everything for more than one enemy.
        rotation = {
            [1] = {
                { spell = 2139, interrupt = true, quick = true },   -- Counterspell
                -- Arcane Wrath (new in Forever): an Arcane mage's, so only while Arcane Blast is your main spell
                { spell = "Arcane Wrath", opener = true, ifUsing = { "nuke", "Arcane Blast" } },
                { spell = 2136, finish = 0.15 },                    -- Fire Blast
                { spell = "Arcane Wrath", safe = true, ifUsing = { "nuke", "Arcane Blast" } },
                -- Frostbolt, Fireball, Arcane Blast, Frostfire Bolt, Arcane Missiles
                { spells = { 116, 133, "Arcane Blast", "Frostfire Bolt", 5143 }, key = "nuke" },
                { spell = 5019, auto = true, rest = true },         -- Shoot (your wand)
            },
        },
    },
    DRUID = {
        keep = {
            { key = "mark", spells = { 1126, 21849 }, duration = 3600 },  -- Mark / Gift of the Wild
            { key = "thorns", spells = { 467 }, duration = 600, onceUsed = true },  -- Thorns (not every druid's)
        },
        react = {},
        -- After the Druid levelling guide on mobalytics.gg (Nov 2026), Feral: as a caster Wrath from afar, Moonfire,
        -- Wrath until it reaches you; as a cat Ravage (or Shred) from stealth, Faerie Fire, Rake, Shifting Power,
        -- Claw to 5 points, then Ferocious Bite (sooner if it finishes the enemy); as a bear Enrage, then Maul.
        -- Left to you: Swipe (3 enemies or more) and Demoralizing Roar.
        rotation = {
            [1] = {  -- no form
                { spell = 5176, opener = true },                    -- Wrath
                { spell = 8921, dot = true },                       -- Moonfire
                { spell = 5176, safe = true },                      -- Wrath
            },
            [768] = {  -- Cat Form
                { spell = 6785, opener = true },                    -- Ravage
                { spell = 5221, opener = true },                    -- Shred
                { spell = 16857, dot = true, lasts = 40 },          -- Faerie Fire (Feral)
                { spell = 1822, dot = true, bleed = true },         -- Rake
                { spell = "Shifting Power" },                       -- (new in Forever)
                { spell = 22568, combo = 5 },                       -- Ferocious Bite
                { spell = 22568, combo = 3, finish = 0.25 },        -- Ferocious Bite (to finish one off)
                { spell = 1082, wait = true },                      -- Claw
            },
            [5487] = {  -- Bear Form
                { spell = 5211, interrupt = true, quick = true },   -- Bash
                { spell = 5229 },                                   -- Enrage
                { spell = "Primal Bite" },                          -- (new in Forever)
                { spell = 6807, filler = 15 },                      -- Maul
            },
            [9634] = {  -- Dire Bear Form
                { spell = 5211, interrupt = true, quick = true },   -- Bash
                { spell = 5229 },                                   -- Enrage
                { spell = "Primal Bite" },
                { spell = 6807, filler = 15 },                      -- Maul
            },
        },
    },
    WARLOCK = {
        keep = {
            { key = "armor", spells = { 687, 706 }, duration = 1800 },  -- Demon Skin / Demon Armor
        },
        react = {},
        -- After the Warlock levelling guide by Crix (23 Nov 2026), Affliction: Bane of Agony (Forever's Curse of
        -- Agony), Immolate until level 30, Corruption, Siphon Life, Curse of the Elements on an enemy that will
        -- last, then Wrack; before Wrack the wand (Shadow Bolt without one). Drain Life when you're hurt. Left to
        -- you: your demon, Drain Soul for shards, and Hellfire.
        rotation = {
            [1] = {
                { spell = 689, hurt = 0.4 },                        -- Drain Life
                { spell = "Bane of Agony", dot = true },            -- (new name in Forever)
                { spell = 980, dot = true },                        -- Curse of Agony
                { spell = 348, dot = true, maxLevel = 29 },         -- Immolate
                { spell = 172, dot = true },                        -- Corruption
                { spell = 18265, dot = true },                      -- Siphon Life (a talent)
                { spell = 1490, dot = true, lasts = 300, above = 0.5 },  -- Curse of the Elements
                { spell = "Wrack", mana = 0.15 },                   -- (new in Forever, a talent)
                { spell = 5019, auto = true, rest = true },         -- Shoot (your wand)
                { spell = 686 },                                    -- Shadow Bolt
            },
        },
    },
    HUNTER = {
        keep = {
            -- Aspect of the Hawk, Monkey, Cheetah, Pack, Wild, Beast, and the Viper and the Falcon (new in Forever)
            { key = "aspect", spells = { 13165, 13163, 5118, 13159, 20043, 13161, "Aspect of the Viper",
                "Aspect of the Falcon" } },
            { key = "lion", spells = { "Heart of the Lion" } },           -- (new in Forever: every hunter's, from 1)
            { key = "trueshot", spells = { 19506 }, duration = 1800 },    -- Trueshot Aura (a talent)
        },
        react = { 1495, 19306 },  -- Mongoose Bite, Counterattack
        -- After the Hunter levelling guide by Feor (18 Nov 2026), Beast Mastery: Hunter's Mark, Aimed Shot to open,
        -- the bow firing by itself, Serpent Sting, Summon Hawk (it takes Arcane Shot's place once you have it),
        -- Arcane Shot, Concussive Shot when it comes for you; up close Mongoose Bite, Wing Clip, Raptor Strike (the
        -- shots are out of range there, so the list falls through to them). Left to you: your pet, Multi-Shot.
        rotation = {
            [1] = {
                { spell = 1130, dot = true, lasts = 120 },          -- Hunter's Mark
                { spell = 19434, opener = true },                   -- Aimed Shot
                { spell = 75, auto = true },                        -- Auto Shot
                { spell = 1978, dot = true },                       -- Serpent Sting
                { spell = "Summon Hawk" },                          -- (new in Forever)
                { spell = 3044 },                                   -- Arcane Shot
                { spell = 5116, onMe = true },                      -- Concussive Shot
                { spell = 1495, quick = true },                     -- Mongoose Bite (after a dodge)
                { spell = 2974, dot = true },                       -- Wing Clip
                { spell = 2973 },                                   -- Raptor Strike
            },
        },
    },
    ROGUE = {
        -- (nothing to keep up that an addon can light: poisons are made and put on from the bags, not a spell on a
        -- bar)
        keep = {},
        react = { 14251 },  -- Riposte
        -- After the Rogue levelling guide on mobalytics.gg (Nov 2026), Combat: Kick a cast, Riposte whenever it
        -- opens, Slice and Dice at 2 points or more from level 42 (its second rank), Eviscerate at 5 points or to
        -- finish, Shank under 60 energy, and your builder between (the one you used last: Sinister Strike,
        -- Backstab, Mutilate or Hemorrhage). From stealth, the opener you used last. Left to you: Blade Flurry.
        rotation = {
            [1] = {
                { spell = 1766, interrupt = true, quick = true },   -- Kick
                { spells = { 1833, 8676, 703 }, key = "opener", opener = true },  -- Cheap Shot, Ambush, Garrote
                { spell = 14251, quick = true },                    -- Riposte
                { spell = 5171, combo = 2, again = true, minLevel = 42 },  -- Slice and Dice
                { spell = 2098, combo = 5 },                        -- Eviscerate
                { spell = 2098, combo = 3, finish = 0.35 },         -- Eviscerate (to finish one off)
                { spell = "Shank", powerBelow = 60 },               -- (new in Forever)
                { spells = { 1752, 53, "Mutilate", 16511 }, key = "builder", wait = true },
            },
        },
    },
    SHAMAN = {
        keep = {
            -- Lightning Shield, and Water Shield (in Forever; the one you used last pulses)
            { key = "shield", spells = { 324, "Water Shield" }, duration = 600 },
            -- Rockbiter, Flametongue, Frostbrand, Windfury Weapon (an hour in Forever): on the weapon, and only
            -- once you've used one (a healer may not)
            { key = "imbue", spells = { 8017, 8024, 8033, 8232 }, duration = 3600, weapon = true, onceUsed = true },
        },
        react = {},
        -- After the Shaman levelling guide by Tiqqle (22 Nov 2026), Enhancement: Lightning Bolt to pull, Flame Shock
        -- on an enemy that will last, Rage of the Farseer, Stormstrike, Lightning Bolt once Maelstrom Weapon has
        -- made it near instant, Earth Shock while there's mana and the enemy isn't nearly dead. Left to you: totems.
        rotation = {
            [1] = {
                { spell = 8042, interrupt = true, quick = true },   -- Earth Shock (stops a cast)
                { spell = 403, opener = true },                     -- Lightning Bolt
                { spell = 8050, dot = true },                       -- Flame Shock
                { spell = "Rage of the Farseer" },                  -- (new in Forever)
                { spell = 17364 },                                  -- Stormstrike
                { spell = 403, fastCast = 600 },                    -- Lightning Bolt (Maelstrom Weapon)
                { spell = 8042, mana = 0.3, above = 0.2 },          -- Earth Shock
            },
        },
    },
}

local function nameOf(spell)
    if type(spell) == "string" then return spell end
    if not spell then return nil end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spell) end
    return (GetSpellInfo(spell))
end

local function iconOf(spell)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
    return GetSpellTexture(spell)
end

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

-- (the saved table takes this one's place as the addon loads, when there is one: then you had Buff Glow before)
local unsaved = {}
BattleShoutGlowDB = BattleShoutGlowDB or unsaved

local ICON = "Interface\\Icons\\Ability_Warrior_BattleShout"

-- (chat only for answers to a command; anything else is a note: QuietKit.Toast)
local function Print(msg)
    QuietKit.Print("Buff Glow", msg)
end

-- Filled in for your class at login (setup)
local KEEP = {}       -- the groups: { key, names = { name = true }, first, duration, combatOnly, ends = { name = true } }
local GROUP_OF = {}   -- spell name -> its keep group
local ENDS = {}       -- spell name -> the groups its cast uses up
local REACT = {}      -- spell name -> its id
local ROTATIONS = {}  -- stance (or a form's name) -> its steps in order: { name, id, and the flags of CLASSES }
local BY_FORM = false -- the lists go by the form you're in, not by a warrior's stance number
local ROTATION = {}   -- every stance's steps together (for the buttons and the icon strip)
local ROT = {}        -- spell name -> a rotation step of it
local MELEE           -- name of a move with melee range
local castAt = {}     -- spell name -> when you last cast it (cooldowns are secret in a fight)
local baseCd = {}     -- spell name -> its cooldown in seconds

-- ---------- is a buff on you ----------

-- Learned from your buffs as you play (saved), not guessed: how long a buff really lasts (by name), and whether a
-- cast that should use one up really does (Judgement a seal: kept[group key] true when it doesn't)
local function learnedDuration(name)
    local d = BattleShoutGlowDB.durations
    return d and d[name]
end

local function learnDuration(name, seconds)
    BattleShoutGlowDB.durations = BattleShoutGlowDB.durations or {}
    BattleShoutGlowDB.durations[name] = math.floor(seconds + 0.5)
end

local function endsKept(g)
    return BattleShoutGlowDB.kept and BattleShoutGlowDB.kept[g.key]
end

local function aurasSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, s = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or s then return true end
    end
    return false
end

-- Your buffs by name -> { ends (0: no end), duration }; nil when they're secret (in a fight). partial: some couldn't
-- be read, so a buff not in the list may still be on you.
local function readBuffs()
    if InCombatLockdown() or aurasSecret() then return nil end
    local list, partial = {}, false
    local ok = pcall(function()
        for i = 1, 40 do
            local name, ends, duration
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if secret(a) then partial = true; return end
                if not a then return end
                name, ends, duration = a.name, a.expirationTime, a.duration
            else
                local n, _, _, _, d, e = UnitBuff("player", i)
                if secret(n) then partial = true; return end
                if not n then return end
                name, ends, duration = n, e, d
            end
            if secret(name) then
                partial = true
            elseif name then
                if secret(ends) then ends = nil end
                if secret(duration) then duration = nil end
                list[name] = { ends = ends or 0, duration = duration }
            end
        end
    end)
    return list, partial or not ok
end

-- Out of combat: what's on you, read. In a fight (secret): known stays nil, and upUntil decides.
local imbue = { ends = 0 }  -- (a weapon imbue as readBuffs gives a buff: kept, not made anew each time)
local function refresh()
    local buffs, partial = readBuffs()
    local now = GetTime()
    for _, g in ipairs(KEEP) do
        if buffs then
            local found, foundName
            local unsure = partial
            if g.weapon then
                -- (on the weapon in your main hand, with the milliseconds it has left; not among your buffs)
                local ok, has, left = pcall(GetWeaponEnchantInfo)
                if not ok or secret(has) then
                    unsure = true
                elseif has then
                    imbue.ends = (not secret(left) and type(left) == "number") and now + left / 1000 or 0
                    found = imbue
                end
            else
                for name in pairs(g.names) do
                    if buffs[name] then found, foundName = buffs[name], name; break end
                end
            end
            if found then
                g.known = true
                g.upUntil = found.ends > 0 and found.ends or math.huge
                if found.duration and found.duration > 0 then learnDuration(foundName, found.duration) end
            elseif unsure or now - (g.castAt or -99) < 1.5 then
                g.known = nil  -- can't tell (or cast a moment ago and not on you yet): upUntil decides
            else
                g.known = false
                g.upUntil = 0
            end
            -- After a cast that should use it up (Judgement): still on you, or gone while it should have lasted?
            local j = g.judged
            if j and now - j.at > 2 then
                if found then
                    BattleShoutGlowDB.kept = BattleShoutGlowDB.kept or {}
                    BattleShoutGlowDB.kept[g.key] = true
                    g.judged = nil
                elseif not partial then
                    if j.upUntil > now then
                        BattleShoutGlowDB.kept = BattleShoutGlowDB.kept or {}
                        BattleShoutGlowDB.kept[g.key] = false
                    end
                    g.judged = nil
                end
            end
        else
            g.known = nil
        end
    end
end

local function isUp(g)
    if g.known ~= nil then return g.known end
    return GetTime() < (g.upUntil or 0)
end

-- (the game's functions are pcalled with their arguments, not wrapped in a new function: these run several times a
-- second, and every new function is garbage a moment later)
local function inFight()
    if InCombatLockdown() then return true end
    local ok, exists = pcall(UnitExists, "target")
    if not ok or secret(exists) or not exists then return false end
    local oka, enemy = pcall(UnitCanAttack, "player", "target")
    return oka and not secret(enemy) and enemy and true or false
end

-- Can be cast now (enough rage / mana); true when the game won't say
local function usableNow(name)
    local f = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not f or not name then return true end
    local ok, usable = pcall(f, name)
    if not ok or secret(usable) then return true end
    return usable and true or false
end

local function isMissing(g)
    if g.onceUsed and not (BattleShoutGlowDB.lastUsed and BattleShoutGlowDB.lastUsed[g.key]) then return false end
    if g.combatOnly and not inFight() then return false end
    if g.whenUsable and not usableNow(g.first) then return false end
    return not isUp(g)
end

-- A spell in your spellbook (looked up by name, which finds only the ones you know)
local function knows(name)
    local f = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    local ok, info = pcall(f, name)
    return ok and not secret(info) and info ~= nil
end

-- A spell's cooldown: its start and duration (only ever called inside pcall)
local function readCooldown(name)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(name)
        if cd then return cd.startTime, cd.duration end
        return nil
    end
    return GetSpellCooldown(name)
end

-- On cooldown, beyond the global one (when the game keeps it secret: by your last cast of it)
local function onCooldown(name)
    local okc, start, duration = pcall(readCooldown, name)
    if okc and not secret(start) and not secret(duration) and start and duration then
        return duration > 1.5
    end
    return castAt[name] and baseCd[name] and GetTime() - castAt[name] < baseCd[name] or false
end

-- 1: can be used now; 0.45: its moment is there but not the rage / mana; false: no (or not known)
local function readyLevel(name)
    local f = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not f then return false end
    local ok, usable, short = pcall(f, name)
    if not ok or secret(usable) or secret(short) then return false end
    if not usable and not short then return false end
    if onCooldown(name) then return false end
    return usable and 1 or 0.45
end

-- ---------- the rotation's next move ----------

local NO_BLEED = { Elemental = true, Mechanical = true }
local dots, stacks = {}, {}  -- target -> when your Rend went on it; target -> { n, last } of your Sunders
local areas = {}             -- spell name -> when you last cast it (Thunder Clap, Demoralizing Shout)
local lastAvoid = 0          -- when you last blocked, dodged or parried (Revenge's chance: 5 sec)
local AVOID_WINDOW = 5

local function targetKey()
    local ok, guid = pcall(UnitGUID, "target")
    if ok and not secret(guid) and guid then return guid end
    return "?"  -- (who it is can be secret: then one for whatever you fight)
end

-- Whom a Rend just cast went on: the enemy under your mouse when there is one (a mouseover macro,
-- "/cast [@mouseover,harm,nodead][] Rend", puts it there), else your target
local function dotKey()
    local ok, over = pcall(UnitExists, "mouseover")
    if not ok or secret(over) or not over then return targetKey() end
    local oka, enemy = pcall(UnitCanAttack, "player", "mouseover")
    local okd, dead = pcall(UnitIsDead, "mouseover")
    if not (oka and okd) or secret(enemy) or secret(dead) or not enemy or dead then return targetKey() end
    local okt, same = pcall(UnitIsUnit, "mouseover", "target")
    if okt and not secret(same) and same then return targetKey() end
    local okg, guid = pcall(UnitGUID, "mouseover")
    if okg and not secret(guid) and guid then return guid end
    return "mouseover"  -- (who it is is secret: at least not your target)
end

local function enemyTargeted()
    local ok, exists = pcall(UnitExists, "target")
    if not ok or secret(exists) or not exists then return false end
    local oka, attackable = pcall(UnitCanAttack, "player", "target")
    if not oka or secret(attackable) or not attackable then return false end
    local okd, dead = pcall(UnitIsDead, "target")
    if not okd then return false end
    return secret(dead) or not dead
end

local function healthOf(unit)  -- only ever called inside pcall
    return UnitHealth(unit), UnitHealthMax(unit)
end

-- A unit's health as a share (nil when it can't be read)
local function healthShare(unit)
    local ok, hp, max = pcall(healthOf, unit)
    if not ok or secret(hp) or secret(max) or not hp or not max or max <= 0 then return nil end
    return hp / max
end

-- The target's health as a share (nil when it can't be read)
local function targetHealth()
    return healthShare("target")
end

-- true / false, or nil when the game can't say (no range, or secret)
local function inRange(name)
    local f = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    if not f then return nil end
    local ok, r = pcall(f, name, "target")
    if not ok or secret(r) or r == nil then return nil end
    return r == true or r == 1
end

local function queued(name)
    local f = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
    if not f then return false end
    local ok, on = pcall(f, name)
    return ok and not secret(on) and on and true or false
end

-- How long a move's effect lasts, from its description ("... over 9 sec.", "... for 45 sec."); 15 s if it doesn't
-- say. (Your rank's: cleared when you learn spells.)
local lastsCache = {}
local function readDescription(name)  -- only ever called inside pcall
    return C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(name)
        or GetSpellDescription and GetSpellDescription(name)
end
local function lastsOf(name)
    if lastsCache[name] then return lastsCache[name] end
    local ok, text = pcall(readDescription, name)
    local secs
    if ok and not secret(text) and type(text) == "string" then
        secs = tonumber(text:match("over (%d+) sec") or text:match("for (%d+) sec"))
        local mins = not secs and tonumber(text:match("for (%d+) min") or text:match("[Ll]asts (%d+) min"))
        if mins then secs = mins * 60 end
    end
    if secs then lastsCache[name] = secs end
    return secs or 15
end

-- How long a step's effect lasts: what its list says (lasts), else its description
local function lastsFor(step)
    return step.lasts or lastsOf(step.name)
end

local function rage()
    local ok, r = pcall(UnitPower, "player", Enum and Enum.PowerType and Enum.PowerType.Rage or 1)
    if not ok or secret(r) then return nil end
    return r
end

-- What you fight with right now (mana, energy, rage): how much, and its most; nil when the game won't say
local function powerNow(kind)  -- only ever called inside pcall
    return UnitPower("player", kind), UnitPowerMax("player", kind)
end
local function power(kind)
    local ok, now, most = pcall(powerNow, kind)
    if not ok or secret(now) or secret(most) or type(now) ~= "number" then return nil end
    return now, most
end

-- Your mana as a share (nil when it can't be read, or you have none)
local function manaShare()
    local now, most = power(Enum and Enum.PowerType and Enum.PowerType.Mana or 0)
    if not now or type(most) ~= "number" or most <= 0 then return nil end
    return now / most
end

-- Your combo points on the target (nil when the game won't say)
local function comboPoints()
    if GetComboPoints then
        local ok, n = pcall(GetComboPoints, "player", "target")
        if ok and not secret(n) and type(n) == "number" then return n end
    end
    return (power(Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4))
end

local function myLevel()
    local ok, level = pcall(UnitLevel, "player")
    if not ok or secret(level) or type(level) ~= "number" then return nil end
    return level
end

-- A wand or a bow already firing by itself (Shoot, Auto Shot)
local function repeating(name)
    local f = (C_Spell and C_Spell.IsAutoRepeatSpell) or IsAutoRepeatSpell
    if not f then return false end
    local ok, on = pcall(f, name)
    return ok and not secret(on) and on and true or false
end

local function stance()
    local ok, form = pcall(GetShapeshiftForm)
    if not ok or secret(form) then return nil end
    return form
end

-- Your health as a share (nil when it can't be read)
local function playerHealth()
    return healthShare("player")
end

-- The target's creature type ("Giant", "Elemental"...), or nil
local function creatureType()
    local ok, kind = pcall(UnitCreatureType, "target")
    if not ok or secret(kind) then return nil end
    return kind
end

-- The target fights with mana (a caster); nil when it can't be read
local function targetUsesMana()
    local ok, kind = pcall(UnitPowerType, "target")
    if not ok or secret(kind) or kind == nil then return nil end
    return kind == (Enum and Enum.PowerType and Enum.PowerType.Mana or 0)
end

-- A boss or an elite (the gold dragon on its portrait)
local TOUGH = { worldboss = true, elite = true, rareelite = true }
local function toughTargeted()
    if UnitIsBossMob then
        local ok, isBoss = pcall(UnitIsBossMob, "target")
        if ok and not secret(isBoss) and isBoss then return true end
    end
    local okl, level = pcall(UnitLevel, "target")
    if okl and not secret(level) and level == -1 then return true end  -- (a skull: far above you)
    local okc, class = pcall(UnitClassification, "target")
    return okc and not secret(class) and TOUGH[class or ""] or false
end

-- The target is casting (or channelling): read where the game lets us, else from its cast's events (castSeen: when
-- UNIT_SPELLCAST_START / CHANNEL_START came, cleared when the cast ends or the target changes; a missed end lets go
-- after CAST_LONGEST). Second value: true when the game says the cast can't be interrupted.
local castSeen
local CAST_LONGEST = 12
local function readCast(f, kickAt)
    if not f then return nil end
    local ok, name, _, _, _, _, a, b, c = pcall(f, "target")
    if not ok then return nil end
    if secret(name) then return true end  -- (a cast is there, its details secret)
    if not name then return false end
    local noKick
    if kickAt == 1 then noKick = a elseif kickAt == 2 then noKick = b else noKick = c end
    return true, not secret(noKick) and noKick and true or false
end
local function targetCasting()
    -- (notInterruptible: the 8th value of a cast, the 7th of a channel)
    local casting, noKick = readCast(UnitCastingInfo, 3)
    if casting then return true, noKick end
    local channel, noKickC = readCast(UnitChannelInfo, 2)
    if channel then return true, noKickC end
    return castSeen ~= nil and GetTime() - castSeen < CAST_LONGEST, false
end

-- A spell's cast time in ms, or nil
local function readCastTime(name)  -- only ever called inside pcall
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        return info and info.castTime
    end
    return (select(4, GetSpellInfo(name)))
end
local function castTime(name)
    local ok, ms = pcall(readCastTime, name)
    if not ok or secret(ms) or type(ms) ~= "number" then return nil end
    return ms
end

-- Whether a step's conditions hold now; false and why not
local function fits(step, fighting)
    if step.opener and fighting then return false, "only before a fight" end
    if step.interrupt then
        local casting, noKick = targetCasting()
        if not casting then return false, "target isn't casting" end
        if noKick then return false, "its cast can't be interrupted" end
    end
    if step.filler then
        if queued(step.name) then return false, "already queued" end
        local r = rage()
        local okl, level = pcall(UnitLevel, "player")
        local late = step.laterFiller and okl and not secret(level) and (level or 0) >= 24
        local need = late and step.laterFiller or step.filler
        -- (a rage dump: when your rage can't be read, it waits)
        if not r then return false, "rage can't be read" end
        if r < need then return false, ("rage %d of %d"):format(r, need) end
    end
    if step.hurt then
        local hp = playerHealth()
        if hp and hp >= step.hurt then return false, "health high" end
    end
    if step.vs and not step.vs[creatureType() or ""] then return false, "not that kind of enemy" end
    if step.fastCast then
        -- (true: under 1.4 s, as a talent makes it; a number: under so many ms, as a proc makes it)
        local ms = castTime(step.name)
        if not ms or ms >= (step.fastCast == true and 1400 or step.fastCast) then return false, "cast not quick now" end
    end
    if step.notCasters and targetUsesMana() then return false, "target is a caster" end
    if step.tough and not toughTargeted() then return false, "not an elite or boss" end
    if step.dot then
        if step.bleed and NO_BLEED[creatureType() or ""] then return false, "target doesn't bleed" end
        local hp = targetHealth()
        if hp and hp < 0.3 then return false, "target nearly dead" end
        local t = dots[targetKey() .. step.name]
        if t and GetTime() - t < lastsFor(step) - 1 then return false, "still on the target" end
    end
    if step.again then
        local t = castAt[step.name]
        if t and GetTime() - t < lastsFor(step) - 1 then return false, "still up" end
    end
    if step.combo then
        local points = comboPoints()
        if not points then return false, "combo points can't be read" end
        if points < step.combo then return false, ("combo points %d of %d"):format(points, step.combo) end
    end
    if step.finish then
        local hp = targetHealth()
        if not hp or hp >= step.finish then return false, "target not nearly dead" end
    end
    if step.above then
        local hp = targetHealth()
        if hp and hp < step.above then return false, "target nearly dead" end
    end
    if step.mana then
        local share = manaShare()
        if share and share < step.mana then return false, "saving mana" end
    end
    if step.powerBelow then
        local now = power()
        if now and now >= step.powerBelow then return false, "not needed yet" end
    end
    if step.maxLevel or step.minLevel then
        local level = myLevel()
        if level and step.maxLevel and level > step.maxLevel then return false, "outgrown" end
        if step.minLevel and (not level or level < step.minLevel) then return false, "from a later level" end
    end
    if step.safe then
        local ok, onMe = pcall(UnitIsUnit, "targettarget", "player")
        if ok and not secret(onMe) and onMe then return false, "target is hitting you" end
    end
    if step.auto and repeating(step.name) then return false, "already firing" end
    if step.ifUsing then
        -- (only for the spec that uses it: while the one of several moves you used last is that one)
        local last = BattleShoutGlowDB.lastUsed and BattleShoutGlowDB.lastUsed[step.ifUsing[1]]
        if last ~= step.ifUsing[2] then return false, "not your spec's" end
    end
    if step.stacks then
        local s = stacks[targetKey()]
        if s and s.n >= step.stacks and GetTime() - s.last < 25 then return false, "stacked" end
    end
    if step.area then
        if not fighting then return false, "only in a fight" end
        if MELEE and inRange(MELEE) == false then return false, "not in melee range" end
        local t = areas[step.name]
        if t and GetTime() - t < lastsFor(step) - 1 then return false, "still up" end
    end
    if step.onMe then
        local ok, onMe = pcall(UnitIsUnit, "targettarget", "player")
        -- (can't tell: as if it is)
        if ok and not secret(onMe) and not onMe then return false, "target isn't hitting you" end
    end
    return true
end

-- The list for the stance you're in (Battle Stance's when it can't be read). Other classes: the list of the form
-- you're in, found by the form's own spell (a druid's number for Cat Form depends on which forms it has learned),
-- else the class's first list.
local function currentRotation()
    local form = stance()
    if BY_FORM then
        local list
        if form and form > 0 and GetShapeshiftFormInfo then
            local ok, _, _, _, id = pcall(GetShapeshiftFormInfo, form)
            local name = ok and not secret(id) and id and nameOf(id)
            list = name and ROTATIONS[name]
        end
        return list or ROTATIONS[1]
    end
    return ROTATIONS[form or 1] or ROTATIONS[1]
end

-- A step that is one of several moves (a rogue's Sinister Strike, Backstab or Mutilate; a mage's Frostbolt or
-- Fireball): the one of them you used last, else the first you know
local function chosen(step)
    local last = BattleShoutGlowDB.lastUsed and BattleShoutGlowDB.lastUsed[step.key]
    if last and step.choices[last] and knows(last) then return last end
    for _, name in ipairs(step.order) do
        if knows(name) then return name end
    end
    return step.order[1]
end

-- The next move: its name and how lit (1: now; 0.45: its turn, waiting for rage), or nil; and "kick" for an
-- interrupt (its own look). why (a list, optional) gets a line per move on why it was or wasn't picked (/bsg why).
local function note(why, step, reason)
    if why then why[#why + 1] = step.name .. ": " .. reason end
end
local function pickNext(why)
    if not ROTATION[1] or BattleShoutGlowDB.rotation == false then return nil end
    if UnitIsDeadOrGhost("player") or not enemyTargeted() then return nil end
    local fighting = InCombatLockdown()
    local waiting  -- a move whose turn it is, short of rage: only quick moves still go before it
    for _, step in ipairs(currentRotation() or {}) do
        if step.choices then step.name = chosen(step) end
        -- (a wand already firing: the fight's last word, so nothing below it is lit)
        if step.rest and not waiting and repeating(step.name) then
            note(why, step, "firing: nothing more to press")
            return nil
        end
        if waiting and not step.quick then
            if why then note(why, step, "after " .. waiting) end
        elseif not knows(step.name) then
            note(why, step, "not learned")
        elseif step.afterAvoid then
            -- (from the other stance: by your own blocks, dodges and parries, as the game won't say)
            local r = rage()
            if GetTime() - lastAvoid > AVOID_WINDOW then
                note(why, step, "no block, dodge or parry just now")
            elseif onCooldown(step.name) then
                note(why, step, "on cooldown")
            elseif r and step.cost and r < step.cost then
                note(why, step, "short of rage")
            elseif inRange(step.name) == false then
                note(why, step, "not in range")
            else
                note(why, step, "PICKED (through your stance macro)")
                return step.name, 1
            end
        else
            local ok, reason = fits(step, fighting)
            if not ok then
                note(why, step, reason)
            else
                local lv = readyLevel(step.name)
                local range = inRange(step.name)
                if step.opener then
                    if lv == 1 and range == true then note(why, step, "PICKED"); return step.name, 1 end
                    note(why, step, lv ~= 1 and "not usable now" or "not in range")
                elseif range == false then
                    note(why, step, "not in range")
                elseif lv == 1 then
                    note(why, step, "PICKED")
                    return step.name, 1, step.interrupt and "kick" or nil
                elseif lv and step.wait and not waiting then
                    note(why, step, "waiting for rage")
                    waiting = step.name
                else
                    note(why, step, lv and "short of rage" or "not usable now (or on cooldown)")
                end
            end
        end
    end
    if waiting then return waiting, 0.45 end
    return nil
end

-- ---------- glows on Blizzard's own action buttons (by name only) ----------

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
               "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local function mayTouch(f)
    if not f then return false end
    if CanAccessObject then
        local ok, yes = pcall(CanAccessObject, f)
        if not ok or not yes then return false end
    end
    local ok, forbidden = pcall(function() return f:IsForbidden() end)
    return ok and not forbidden
end

local holding, glows = {}, {}  -- button -> what it shows: { group } or { react = name }
local rotHolding, rings = {}, {}  -- button -> the moves on it ({ name = true }); button -> its next-move ring

-- The moves a macro is for: the /cast spells in it we watch, the first one first. A stance macro ("/cast
-- [nostance:2] Defensive Stance" then "/cast [stance:2] Revenge") is Revenge's button in any stance, not the
-- stance's; one with "Charge; ... Intercept" is the button of both.
local function macroMoves(id)
    local ok, body = pcall(GetMacroBody, id)
    if not ok or secret(body) or type(body) ~= "string" then return nil end
    local first, all
    for line in body:gmatch("[^\r\n]+") do
        local args = line:match("^%s*/cast%s+(.+)") or line:match("^%s*/use%s+(.+)")
        for part in (args or ""):gmatch("[^;]+") do
            local spell = part:gsub("%[.-%]", ""):gsub("%(.-%)", ""):match("^%s*!?%s*(.-)%s*$")
            if spell and (ROT[spell] or GROUP_OF[spell] or REACT[spell]) then
                first = first or spell
                all = all or {}
                all[spell] = true
            end
        end
    end
    return first, all
end

-- The spell on a slot (for a macro: the first move it's for), and all the moves on it
local function spellIn(slot)
    if not slot or not HasAction(slot) then return nil end
    local kind, id, sub = GetActionInfo(slot)
    if kind == "spell" then
        local name = nameOf(id)
        return name, name and { [name] = true }
    end
    if kind == "macro" then
        -- This client gives a macro's slot the spell it shows (sub "spell"), not which macro it is: the macro is
        -- found by its name (the button's text) instead
        local index
        local ok, text = pcall(GetActionText, slot)
        if ok and not secret(text) and type(text) == "string" and text ~= "" then
            index = GetMacroIndexByName(text)
        end
        if (not index or index == 0) and sub ~= "spell" and sub ~= "item" then index = id end
        if index and index > 0 then
            local first, all = macroMoves(index)
            if first then return first, all end
        end
        local name = sub == "spell" and nameOf(id) or (index and index > 0 and nameOf(GetMacroSpell(index)))
        return name or nil, name and { [name] = true }
    end
    return nil
end

local function makeGlow()
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("HIGH")
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    t:SetBlendMode("ADD")
    local pulse = g:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    g.pulse, g.fade, g.tex = pulse, fade, t
    g:Hide()
    return g
end

-- colour, pulse time, how far the pulse fades: a gold pulse (missing buff), a quick blue glint (a move opened up),
-- a slow pale-green breath (the next move), a quick orange blink (interrupt the target's cast now)
local LOOKS = { keep = { 1, 0.8, 0.15, 0.6, 0.3 }, react = { 0.55, 0.85, 1, 0.22, 0.3 },
                next = { 0.75, 1, 0.75, 0.9, 0.65 }, kick = { 1, 0.5, 0.15, 0.16, 0.15 } }
local function dress(g, kind, level)
    if g.kind ~= kind then
        local l = LOOKS[kind]
        g.tex:SetVertexColor(l[1], l[2], l[3])
        g.fade:SetDuration(l[4])
        g.fade:SetToAlpha(l[5])
        g.kind = kind
        if g.pulse:IsPlaying() then g.pulse:Stop(); g.pulse:Play() end  -- (its new pace at once)
    end
    g.tex:SetAlpha(level)  -- the texture: the pulse animates the frame's alpha
end

local function show(g, on)
    if on and not g:IsShown() then g:Show(); g.pulse:Play()
    elseif not on and g:IsShown() then g.pulse:Stop(); g:Hide() end
end

local function slotOf(b)  -- only ever called inside pcall
    local slot = rawget(b, "action")
    if type(slot) ~= "number" and b.GetAttribute then slot = tonumber(b:GetAttribute("action")) end
    return type(slot) == "number" and slot or nil
end

-- The controller crossbar's buttons: looked for under the crossbar's frames by name (Blizzard_GamepadActionBars'
-- main frame holds every bar: PageUnit.actionBars.topBar... ActionButton1-4), read only, each step in pcall so a
-- frame the game keeps to itself is just skipped. Once found they're kept: the buttons stay, only what's on them
-- changes, and that's read at each scan. Looked for again only when the crossbar's frames are new (the addon that
-- makes them loads, or they weren't there yet).
-- (Looking through every global for Gamepad... frames, as before, stuttered at each loading screen and each switch
-- between controller and mouse. It's still done once, as a last resort, when the names below hold no buttons with
-- the controller on: the names it finds are kept in the saved table, for the next session.)
local PAD_ROOTS = { "GamepadMainActionBarFrame" }
local padButtons, padDirty, padStale = {}, true, true
local padRootsSeen = {}       -- root name -> the frame it was when its buttons were found
local searchedGlobals = false -- (the last resort, at most once a session)

local function children(f)  -- only ever called inside pcall
    return { f:GetChildren() }
end

local function walk(f, depth, seen)
    if depth > 6 or seen[f] or not mayTouch(f) then return end
    seen[f] = true
    local ok, slot = pcall(slotOf, f)
    if ok and slot then padButtons[#padButtons + 1] = f end
    local okc, kids = pcall(children, f)
    if okc then for _, k in ipairs(kids) do walk(k, depth + 1, seen) end end
end

local function padOn()
    if C_GamePad and C_GamePad.IsEnabled then
        local ok, on = pcall(C_GamePad.IsEnabled)
        if ok and not secret(on) then return on and true or false end
    end
    return GetCVarBool and GetCVarBool("GamePadEnable") and true or false
end

local function rootNames()
    local names, listed = {}, {}
    for _, name in ipairs(PAD_ROOTS) do names[#names + 1] = name; listed[name] = true end
    for _, name in ipairs(BattleShoutGlowDB.padRoots or {}) do
        if not listed[name] then names[#names + 1] = name; listed[name] = true end
    end
    return names
end

local function findPad()
    padDirty = false
    -- (found already, and the same frames still: nothing to do)
    if not padStale and #padButtons > 0 then
        local same = true
        for name, f in pairs(padRootsSeen) do
            if _G[name] ~= f then same = false end
        end
        if same then return end
    end
    padStale = false
    wipe(padButtons)
    wipe(padRootsSeen)
    local seen = {}
    for _, name in ipairs(rootNames()) do
        local f = _G[name]
        if type(f) == "table" then
            walk(f, 0, seen)
            padRootsSeen[name] = f
        end
    end
    if #padButtons > 0 or searchedGlobals or not padOn() then return end
    searchedGlobals = true
    local found = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and name:find("^Gamepad") and not padRootsSeen[name] then
            local before = #padButtons
            walk(v, 0, seen)
            if #padButtons > before then
                found[#found + 1] = name
                padRootsSeen[name] = v
            end
        end
    end
    if found[1] then BattleShoutGlowDB.padRoots = found end
end

-- The spell of a group you used last (saved), so only its button pulses, not every blessing's
local function lastUsed(g)
    return BattleShoutGlowDB.lastUsed and BattleShoutGlowDB.lastUsed[g.key]
end

local function scan()
    wipe(holding)
    wipe(rotHolding)
    if padDirty and not InCombatLockdown() then findPad() end
    local found, onPad = 0, 0
    local seen, groupButtons, isPadButton = {}, {}, {}  -- group -> { button = its spell }

    local function take(b, what)
        holding[b] = what
        if not glows[b] and not InCombatLockdown() then glows[b] = makeGlow() end
        found = found + 1
        if isPadButton[b] then onPad = onPad + 1 end
    end
    local function look(b, isPad)
        if seen[b] or not mayTouch(b) then return end
        seen[b] = true
        isPadButton[b] = isPad
        -- (a ring for every button, made out of combat: a stance change in a fight puts other moves on them)
        if ROTATION[1] and not rings[b] and not InCombatLockdown() then rings[b] = makeGlow() end
        local ok, slot = pcall(slotOf, b)
        local spell, moves
        if ok and slot then spell, moves = spellIn(slot) end
        if not spell then return end
        rotHolding[b] = moves
        local g = GROUP_OF[spell]
        if g then
            groupButtons[g] = groupButtons[g] or {}
            groupButtons[g][b] = spell
        elseif REACT[spell] then
            take(b, { react = spell })
        end
    end
    for _, bar in ipairs(BARS) do
        for i = 1, 12 do look(_G[bar .. i]) end
    end
    for _, b in ipairs(padButtons) do look(b, true) end

    -- A group's buttons: the one(s) with the spell you used last, else all of them
    for g, buttons in pairs(groupButtons) do
        local last = lastUsed(g)
        local hasLast = false
        for _, spell in pairs(buttons) do
            if spell == last then hasLast = true end
        end
        for b, spell in pairs(buttons) do
            if not hasLast or spell == last then take(b, { group = g }) end
        end
    end
    return found, onPad
end

-- ---------- the icons above the crossbar ----------

local strip = CreateFrame("Frame", nil, UIParent)
strip:SetSize(40, 40)
strip:SetFrameStrata("HIGH")
strip:SetMovable(true)
strip:SetClampedToScreen(true)
strip:RegisterForDrag("LeftButton")
strip:SetScript("OnDragStart", strip.StartMoving)
strip:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    BattleShoutGlowDB.pos = { p, rp, x, y }
end)
strip:EnableMouse(false)
local function place()
    strip:ClearAllPoints()
    local pos = BattleShoutGlowDB.pos
    if pos then strip:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]); return end
    -- under your portrait: where the player frame is now, read once (not anchored to it: nothing of Blizzard's is ours)
    local ok, x, y = pcall(function()
        if not mayTouch(PlayerFrame) then return end
        local cx = PlayerFrame:GetCenter()
        local bottom = PlayerFrame:GetBottom()
        local s = PlayerFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return cx * s, bottom * s
    end)
    if ok and x and y then strip:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, y - 4)
    else strip:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230) end
end
local bg = strip:CreateTexture(nil, "BACKGROUND")  -- shown only while moving it
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.4)
bg:Hide()

local icons = {}
local function iconFrame(kind, group, reactName)
    local f = CreateFrame("Frame", nil, strip)
    f:SetSize(40, 40)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.glow = makeGlow()
    f.glow:SetParent(f)
    f.glow:SetPoint("CENTER")
    f.glow:SetSize(72, 72)
    f.kind, f.group, f.react = kind, group, reactName
    f:Hide()
    icons[#icons + 1] = f
    return f
end

-- ---------- a mark on enemies still without your Rend (their nameplates) ----------
-- In a fight an enemy's debuffs are secret to addons, so they're never read here. Each enemy's nameplate gets a slot
-- of ours (a dim Rend icon in a red frame, breathing), and over it one of Blizzard's own aura displays (an
-- AuraContainer), set to show only your Rend on that enemy. While your Rend is on it, the real icon, its time
-- running down, covers the slot; once it's gone the slot shows again. Only in a fight, only on enemies in it, not
-- on ones that don't bleed.
-- The displays are made out of combat (a pool, at login), and if the game won't make them the mark stays off: a
-- slot without a display over it would always say "missing".
local MARK_RANKS = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }  -- Rend's ranks in Classic (Forever's are learned:
                                                                   -- the one in your spellbook, and each you cast)
local MARK_SIZE, MARK_EDGE, MARK_POOL = 20, 2, 20
local MARK                      -- the move's name (Rend), when your class has one
local markIds = {}              -- its spell IDs: id -> true
local markSlots, markFree, markOn = {}, {}, {}  -- every slot; slots not in use; nameplate unit -> its slot
local markError                 -- why the displays couldn't be made (/bsg says)

local function markWanted()
    return MARK and BattleShoutGlowDB.rendMark ~= false and knows(MARK)
end

-- (a new table each time: Blizzard's display may keep the one it's given)
local function markFilters()
    local ids = {}
    for id in pairs(markIds) do ids[id] = true end
    return { includeSpellIDs = ids }
end

local function markRefilter()
    for _, slot in ipairs(markSlots) do
        pcall(slot.display.SetAuraGroupCandidateFilters, slot.display, "mark", markFilters())
    end
end

-- The IDs to show: Classic's ranks, the rank in your spellbook, and any rank you cast
local function markLearn(id)
    if not MARK then return end
    local added = false
    local function add(i)
        if type(i) == "number" and not markIds[i] then markIds[i] = true; added = true end
    end
    if id then
        add(id)
    else
        for _, i in ipairs(MARK_RANKS) do add(i) end
        local f = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
        local ok, a, _, _, _, _, _, b = pcall(f, MARK)
        if ok and not secret(a) then add(type(a) == "table" and a.spellID or b) end
    end
    if added then markRefilter() end
end

-- What a display's button is made of: the icon and its time (called by Blizzard as each button is made)
-- (Blizzard calls it in a way that swallows errors: a failure is kept for /bsg rend why instead)
-- Its size is set here: Blizzard's buttons start at 0 x 0 (seen 2026-11-20: the icon was there, but no size, so the
-- red mark under it never got covered)
local markButtonError
local function markIcon(button, size)  -- only ever called inside pcall
    button:SetSize(size, size)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
end
local function markTime(button)  -- only ever called inside pcall
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    button:SetDurationCooldown(cd)
end
local function markButtonOf(size)
    return function(button)
        local ok, err = pcall(markIcon, button, size)
        if not ok then markButtonError = "icon: " .. tostring(err) end
        ok, err = pcall(markTime, button)
        if not ok then markButtonError = markButtonError or ("time: " .. tostring(err)) end
    end
end

-- A display's group laid out like Threat Plates does it (in options alone the layout didn't take)
local function layOut(display, key, size)
    pcall(display.SetAuraGroupLayout, display, key, { elementWidth = size, elementHeight = size })
    pcall(display.SetFlowLayoutAnchorPoint, display, "TOPLEFT")
    pcall(display.SetFlowLayoutMaximumLineSize, display, size)
end

local function markSlot()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(MARK_SIZE, MARK_SIZE)
    f:Hide()
    -- the "missing" look, in a frame of its own so its breathing doesn't fade the display over it
    local need = CreateFrame("Frame", nil, f)
    need:SetAllPoints()
    local edge = need:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -MARK_EDGE, MARK_EDGE)
    edge:SetPoint("BOTTOMRIGHT", MARK_EDGE, -MARK_EDGE)
    edge:SetColorTexture(0.85, 0.1, 0.05, 0.95)
    local icon = need:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(iconOf(MARK))
    icon:SetDesaturated(true)
    icon:SetVertexColor(1, 0.55, 0.5)
    local breathe = need:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    local fade = breathe:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.7)
    breathe:Play()
    -- Blizzard's display, a bit bigger than the slot, so your Rend covers its red frame too
    local full = MARK_SIZE + 2 * MARK_EDGE
    local display = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
    display:SetFrameLevel(need:GetFrameLevel() + 5)
    display:SetPoint("TOPLEFT", f, "TOPLEFT", -MARK_EDGE, MARK_EDGE)
    display:SetSize(full, full)
    display:AddAuraGroup("mark", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", {
        maxFrameCount = 1,
        initializeFrame = markButtonOf(full),
        candidateFilters = markFilters(),
        layout = { elementWidth = full, elementHeight = full },
    })
    layOut(display, "mark", full)
    display:SetEnabled(false)
    f.display, f.icon = display, icon
    return f
end

local function plateOf(unit)  -- only ever called inside pcall
    return C_NamePlate.GetNamePlateForUnit(unit)
end

local function markAttach(unit)
    if not markWanted() or not markSlots[1] then return end
    local ok, enemy = pcall(UnitCanAttack, "player", unit)
    if not ok or secret(enemy) or not enemy then return end
    local okp, plate = pcall(plateOf, unit)
    if not okp or not mayTouch(plate) then return end
    local slot = markOn[unit] or table.remove(markFree)
    if not slot then return end
    markOn[unit] = slot
    slot.icon:SetTexture(iconOf(MARK))
    slot:ClearAllPoints()
    local okA = pcall(slot.SetPoint, slot, "RIGHT", plate, "LEFT", -2, 0)
    local okU = okA and pcall(slot.display.SetUnit, slot.display, unit)
    local okE = okU and pcall(slot.display.SetEnabled, slot.display, true)
    if not okE then  -- (the display can't follow this enemy: no mark, rather than one that always says missing)
        markOn[unit] = nil
        slot:Hide()
        markFree[#markFree + 1] = slot
    end
end

local function markDetach(unit)
    local slot = markOn[unit]
    if not slot then return end
    markOn[unit] = nil
    slot:Hide()
    pcall(slot.display.SetEnabled, slot.display, false)
    markFree[#markFree + 1] = slot
end

-- The pool, out of combat (at login, or after the fight you logged in during)
local function markMake()
    if markSlots[1] or markError or InCombatLockdown() or not markWanted() then return end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then markError = "no nameplates API"; return end
    local okT, tmpl = pcall(function()
        return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")
    end)
    if not okT or not tmpl then markError = "this client has no aura displays for addons"; return end
    markLearn()
    for i = 1, MARK_POOL do
        local ok, slot = pcall(markSlot)
        if not ok then
            markError = tostring(slot)
            wipe(markSlots); wipe(markFree)
            return
        end
        markSlots[i], markFree[i] = slot, slot
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        local ok, there = pcall(UnitExists, unit)
        if ok and not secret(there) and there then markAttach(unit) end
    end
end

-- Shown while you're in a fight, on a living enemy that's in it too and bleeds (when the game won't say, shown)
local function markShows(unit)
    if not InCombatLockdown() or not markWanted() then return false end
    local okd, dead = pcall(UnitIsDead, unit)
    if okd and not secret(dead) and dead then return false end
    local okc, fighting = pcall(UnitAffectingCombat, unit)
    if okc and not secret(fighting) and not fighting then return false end
    local okt, kind = pcall(UnitCreatureType, unit)
    if okt and not secret(kind) and NO_BLEED[kind or ""] then return false end
    return true
end

-- ---------- what the Rend marks saw (/bsg rend why; kept in the saved table to look at afterwards) ----------
-- (the marks are new on this client: these notes say where it goes wrong, if it does)
local function probeNote(line)
    local p = BattleShoutGlowDB.markProbe
    if type(p) ~= "table" then p = {}; BattleShoutGlowDB.markProbe = p end
    p[#p + 1] = ("%.1f "):format(GetTime()) .. line
    while #p > 60 do table.remove(p, 1) end
end

-- A value read for the notes: as text, or "secret" / "error"
local function readable(f, ...)
    local ok, v = pcall(f, ...)
    if not ok then return "error(" .. tostring(v) .. ")" end
    if secret(v) then return "secret" end
    return tostring(v)
end

local function centerOf(f)  -- only ever called inside pcall
    local x, y = f:GetCenter()
    return ("%d,%d"):format(x or -1, y or -1)
end

-- What a display shows: enabled, its buttons, the first one's state and place
local function displayState(display, key)
    local parts = { "enabled " .. readable(display.IsEnabled, display),
                    "frames " .. readable(display.GetAuraGroupFrameCount, display, key),
                    "at " .. readable(centerOf, display) }
    local ok, b = pcall(display.GetAuraGroupFrame, display, key, 1)
    if ok and b and not secret(b) then
        parts[#parts + 1] = "button shown " .. readable(b.IsShown, b)
        parts[#parts + 1] = "visible " .. readable(b.IsVisible, b)
        parts[#parts + 1] = "size " .. readable(b.GetWidth, b)
        parts[#parts + 1] = "at " .. readable(centerOf, b)
        parts[#parts + 1] = "alpha " .. readable(b.GetEffectiveAlpha, b)
    else
        parts[#parts + 1] = "no button (" .. tostring(ok and b or "error") .. ")"
    end
    if markButtonError then parts[#parts + 1] = "button error: " .. markButtonError end
    return table.concat(parts, ", ")
end

local function nameOfUnit(unit)
    local ok, there = pcall(UnitExists, unit)
    if not ok or secret(there) then return "?" end
    if not there then return "none" end
    return readable(UnitName, unit)
end

-- Your macros that cast the mark's move (Rend), each with whether it casts on what you hover ("Rend Auto: hover,
-- Rend: target")
local function markMacroState()
    if not MARK then return nil end
    local found = {}
    local general, perChar = 0, 0
    local okN, g, c = pcall(GetNumMacros)
    if okN then general, perChar = g or 0, c or 0 end
    local firstChar = (MAX_ACCOUNT_MACROS or 120) + 1
    local function look(index)
        local ok, name, _, body = pcall(GetMacroInfo, index)
        if not ok or secret(name) or secret(body) or type(body) ~= "string" then return end
        local casts = false
        for line in body:gmatch("[^\r\n]+") do
            local args = line:match("^%s*/cast%s+(.+)")
            for part in (args or ""):gmatch("[^;]+") do
                local spell = part:gsub("%[.-%]", ""):match("^%s*!?%s*(.-)%s*$")
                if spell == MARK then casts = true end
            end
        end
        if casts then
            found[#found + 1] = tostring(name) .. ": " .. (body:find("@mouseover") and "hover" or "target")
        end
    end
    for i = 1, general do look(i) end
    for i = firstChar, firstChar + perChar - 1 do look(i) end
    return found[1] and table.concat(found, ", ") or ("no macro casts " .. MARK)
end

-- Each Rend: where it went (the mouse, your target). (What its mark's display shows can't be read in a fight:
-- Blizzard's buttons and your debuffs are closed to addons then.)
local function probeCast(targetName)
    local over = "-"
    local ok, same = pcall(UnitIsUnit, "mouseover", "target")
    if ok and not secret(same) then over = same and "yes" or "no" end
    probeNote(("%s sent at %s; mouseover %s, target %s, the same one: %s; macros: %s"):format(MARK,
        tostring(targetName), nameOfUnit("mouseover"), nameOfUnit("target"), over, tostring(markMacroState())))
end

-- Out of combat: two displays on you, one for any buff and one for a buff of yours by its ID, to see whether
-- Blizzard's displays and their ID filter work on this client at all. shown: visible on screen for a while.
local tests
local function markSelfTest(shown)
    if InCombatLockdown() then return false end
    local id, name
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local ok, a = pcall(get, "player", i, "HELPFUL")
        if not ok or not a or secret(a) then break end
        if not secret(a.spellId) and not secret(a.name) then id, name = a.spellId, a.name; break end
    end
    if not id then probeNote("self-test: no buff on you to test with"); return false end
    if not tests then
        tests = {}
        for i, key in ipairs({ "any", "ids" }) do
            local f = CreateFrame("Frame", nil, UIParent)
            f:SetSize(40, 40)
            f:SetPoint("CENTER", UIParent, "CENTER", (i - 1.5) * 60, 120)
            local red = f:CreateTexture(nil, "BACKGROUND")
            red:SetAllPoints()
            red:SetColorTexture(0.85, 0.1, 0.05, 0.95)
            local ok, err = pcall(function()
                local d = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
                d:SetFrameLevel(f:GetFrameLevel() + 5)
                d:SetPoint("TOPLEFT", f, "TOPLEFT")
                d:SetSize(40, 40)
                d:AddAuraGroup(key, "HELPFUL", { maxFrameCount = 1, initializeFrame = markButtonOf(40),
                                                 layout = { elementWidth = 40, elementHeight = 40 } })
                layOut(d, key, 40)
                f.display = d
            end)
            if not ok then probeNote("self-test " .. key .. ": couldn't make it: " .. tostring(err)) end
            f.key = key
            tests[i] = f
        end
    end
    for _, f in ipairs(tests) do
        local d = f.display
        if d then
            pcall(d.SetAuraGroupCandidateFilters, d, f.key, f.key == "ids" and { includeSpellIDs = { [id] = true } } or {})
            pcall(d.SetUnit, d, "player")
            pcall(d.SetEnabled, d, true)
        end
        f:SetAlpha(shown and 1 or 0)
        f:Show()
    end
    C_Timer.After(1, function()
        for _, f in ipairs(tests) do
            if f.display then
                probeNote(("self-test %s (%s#%s): %s"):format(f.key, tostring(name), tostring(id),
                    displayState(f.display, f.key)))
            end
        end
        C_Timer.After(shown and 12 or 0, function()
            for _, f in ipairs(tests) do
                if f.display then pcall(f.display.SetEnabled, f.display, false) end
                f:Hide()
            end
        end)
    end)
    return true
end

local plates = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do pcall(plates.RegisterEvent, plates, e) end
pcall(plates.RegisterUnitEvent, plates, "UNIT_SPELLCAST_SENT", "player")
plates:SetScript("OnEvent", function(_, e, unit, targetName, _, spellID)
    if e == "NAME_PLATE_UNIT_ADDED" then markAttach(unit)
    elseif e == "NAME_PLATE_UNIT_REMOVED" then markDetach(unit)
    elseif MARK and not secret(spellID) and nameOf(spellID) == MARK then
        probeCast(secret(targetName) and "?" or targetName)
    end
end)

-- The mark's move as a macro that casts on what you hover (the stance line as in your own macros), named as yours
-- is ("Rend Auto"): made if it's missing, its text put back if it's changed; your plain "Rend" macro is left alone
local MARK_MACRO = "#showtooltip %s\n/cast [stance:3] Defensive Stance\n/cast [nostance:3,@mouseover,harm,nodead][nostance:3] %s"
local function markMacroSpec()
    local move = MARK or "Rend"
    return { name = move .. " Auto", icon = "Ability_Gouge", account = true,
             body = function() return MARK_MACRO:format(move, move) end }
end

-- Shield Slam the same way: on the enemy under your mouse, else your target (it needs no stance in Forever, so no
-- stance line)
local SLAM_MACRO = "#showtooltip %s\n/cast [@mouseover,harm,nodead][] %s"
local function slamMacroSpec()
    local move = nameOf(23922) or "Shield Slam"
    return { name = move .. " Auto", icon = "INV_Shield_05", account = true,
             body = function() return SLAM_MACRO:format(move, move) end }
end

-- Shield Bash too: interrupt the caster under your mouse without leaving your target. It needs Battle or Defensive
-- Stance, so from Berserker Stance it swaps to Defensive first, as your own Shield Bash macro does.
local function bashMacroSpec()
    local move = nameOf(72) or "Shield Bash"
    return { name = move .. " Auto", icon = "Ability_Warrior_ShieldBash", account = true,
             body = function() return MARK_MACRO:format(move, move) end }
end

-- ---------- your class's lists, at login ----------

local function setup()
    if #KEEP > 0 or next(REACT) then return end
    local _, class = UnitClass("player")
    local data = CLASSES[class or ""]
    if not data then return end
    -- (a warrior's lists go by stance number; any other class's by the form's spell, its first list being [1])
    BY_FORM = class ~= "WARRIOR"
    for form, list in pairs(data.rotation or {}) do
        local key = form
        if BY_FORM and form ~= 1 then key = nameOf(form) end
        local steps = {}
        if key then ROTATIONS[key] = steps end
        for _, def in ipairs(list) do
            local step
            if def.spells then
                -- one of several moves: whichever of them you used last (chosen, above)
                step = { choices = {}, order = {} }
                for _, id in ipairs(def.spells) do
                    local n = nameOf(id)
                    if n and not step.choices[n] then
                        step.choices[n] = true
                        step.order[#step.order + 1] = n
                    end
                end
                step.name = step.order[1]
            else
                local n = nameOf(def.spell)
                if n then step = { name = n, id = def.spell } end
            end
            if step and step.name then
                for k, v in pairs(def) do
                    if k ~= "spell" and k ~= "spells" then step[k] = v end
                end
                steps[#steps + 1] = step
                ROTATION[#ROTATION + 1] = step
                for _, n in ipairs(step.order or { step.name }) do ROT[n] = ROT[n] or step end
            end
        end
    end
    MELEE = data.melee and nameOf(data.melee)
    MARK = data.mark and nameOf(data.mark)
    if ROTATION[1] then iconFrame("next") end
    for _, def in ipairs(data.keep) do
        local g = { key = def.key, names = {}, duration = def.duration, combatOnly = def.combatOnly,
                    onceUsed = def.onceUsed, whenUsable = def.whenUsable, weapon = def.weapon, upUntil = 0, ends = {} }
        -- (a weapon imbue on a game that won't say what's on the weapon: left out, rather than lit for ever)
        local spells = (def.weapon and not GetWeaponEnchantInfo) and {} or def.spells
        for _, id in ipairs(spells) do
            local n = nameOf(id)
            if n then
                g.names[n] = true
                g.first = g.first or n
                GROUP_OF[n] = g
            end
        end
        for _, id in ipairs(def.endedBy or {}) do
            local n = nameOf(id)
            if n then
                ENDS[n] = ENDS[n] or {}
                table.insert(ENDS[n], g)
                g.ends[n] = true
            end
        end
        if g.first then
            KEEP[#KEEP + 1] = g
            iconFrame("keep", g)
        end
    end
    for _, id in ipairs(data.react) do
        local n = nameOf(id)
        if n then
            REACT[n] = id
            iconFrame("react", nil, n)
        end
    end
    -- cooldowns, for when the game keeps them secret in a fight
    local function readCd(name, id)
        local ok, ms = pcall(GetSpellBaseCooldown, id)
        if ok and not secret(ms) and type(ms) == "number" and ms > 1500 then baseCd[name] = ms / 1000 end
    end
    for _, step in ipairs(ROTATION) do readCd(step.name, step.id) end
    for name, id in pairs(REACT) do readCd(name, id) end
end

-- ---------- each moment: what's missing, what's up ----------

local lastWhy      -- the rotation's reasons at the last moment of a fight (/bsg why)
local whyAt = 0    -- (when they were last written down: once a second is plenty)
-- These run every 0.15 s: the tables are kept and emptied, not made anew, and nothing makes a new function
local missing, ready, shownIcons = {}, {}, {}

-- A glow over a button, where the button is now (only ever called inside pcall: each button on its own, so one the
-- game won't let us read just stays dark)
local function placeOver(b, glow, kind, lv)
    if not (lv and b:IsVisible() and b:GetEffectiveAlpha() > 0.05) then return false end
    local x, y = b:GetCenter()
    local w, h = b:GetSize()
    if not x or not w or w < 1 then return false end
    local s = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * s, y * s)
    glow:SetSize(w * s * 1.8, h * s * 1.8)
    dress(glow, kind, lv)
    return true
end

local function over(b, glow, kind, lv)
    local ok, on = pcall(placeOver, b, glow, kind, lv)
    show(glow, ok and on)
end

local function update()
    local alive = not UnitIsDeadOrGhost("player")
    wipe(missing)
    wipe(ready)
    for _, g in ipairs(KEEP) do missing[g] = alive and isMissing(g) or nil end
    for name in pairs(REACT) do ready[name] = alive and readyLevel(name) end
    -- (while the rotation light shows a move, the blue glints stay off: the ring already takes them in)
    -- (in a fight with a target, the reasons are kept for /bsg why afterwards: written down once a second)
    local why
    if InCombatLockdown() and GetTime() - whyAt >= 1 and enemyTargeted() then
        why, whyAt = {}, GetTime()
    end
    local nextName, nextLevel, nextKind = pickNext(why)
    if why then lastWhy = why end

    for b, glow in pairs(glows) do
        local what = holding[b]
        local lv, kind
        if what and what.group then lv, kind = missing[what.group] and 1, "keep"
        elseif what and what.react then lv, kind = not nextName and ready[what.react], "react" end
        over(b, glow, kind, lv)
    end
    for b, ring in pairs(rings) do
        over(b, ring, nextKind or "next", nextName and rotHolding[b] and rotHolding[b][nextName] and nextLevel)
    end

    -- the separate icons: only if asked for (/bsg icons, or the settings) and the controller is on, or while moving
    -- them
    local moving = strip:IsMouseEnabled()
    local pad = (BattleShoutGlowDB.icons and padOn()) or moving
    wipe(shownIcons)
    local x = 0
    for _, f in ipairs(icons) do
        local lv
        if f.kind == "next" then
            lv = nextLevel
            f.tex:SetTexture(iconOf(nextName or ROTATION[1].name))
        elseif f.group then
            local spell = lastUsed(f.group) or f.group.first
            lv = missing[f.group] and knows(spell) and 1
            f.tex:SetTexture(iconOf(spell))
        else
            lv = not nextName and ready[f.react] and knows(f.react) and ready[f.react]
            f.tex:SetTexture(iconOf(f.react))
        end
        if moving then lv = 1 end
        if pad and lv then
            shownIcons[#shownIcons + 1] = f
            dress(f.glow, f.kind == "next" and nextKind or f.kind, lv)
            f:SetAlpha(0.5 + lv / 2)
        end
        f:SetShown(pad and lv and true or false)
        show(f.glow, pad and lv)
    end
    local width = #shownIcons * 44 - 4
    for _, f in ipairs(shownIcons) do
        f:ClearAllPoints()
        f:SetPoint("LEFT", strip, "CENTER", -width / 2 + x, 0)
        x = x + 44
    end
    strip:SetWidth(math.max(width, 40))

    -- the Rend marks on enemy nameplates
    for unit, slot in pairs(markOn) do slot:SetShown(markShows(unit)) end
end

local pending = false
local function scanSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = false; scan() end)
end

-- Your own cast: a kept buff is up for its time (even while the buffs are secret), its button becomes the one that
-- pulses; a cast that uses one up (Judgement a seal) takes it down
local function onCast(id)
    if secret(id) then return end
    local name = nameOf(id)
    if not name or secret(name) then return end
    castAt[name] = GetTime()
    if name == MARK then markLearn(id) end
    local step = ROT[name]
    if step and step.dot then dots[dotKey() .. name] = GetTime() end
    if step and step.area then areas[name] = GetTime() end
    if step and step.choices then
        -- (the one of its moves you use: the ring follows it from now on)
        BattleShoutGlowDB.lastUsed = BattleShoutGlowDB.lastUsed or {}
        BattleShoutGlowDB.lastUsed[step.key] = name
    end
    if name == nameOf(6572) then lastAvoid = 0 end  -- (Revenge used: its chance is spent)
    if step and step.stacks then
        local key = targetKey()
        local s = stacks[key]
        if not s or GetTime() - s.last > 30 then s = { n = 0 }; stacks[key] = s end
        s.n, s.last = math.min(s.n + 1, step.stacks), GetTime()
    end
    local g = GROUP_OF[name]
    if g then
        local duration = learnedDuration(name) or g.duration
        g.upUntil = duration and (GetTime() + duration) or math.huge
        g.castAt, g.judged = GetTime(), nil
        BattleShoutGlowDB.lastUsed = BattleShoutGlowDB.lastUsed or {}
        if BattleShoutGlowDB.lastUsed[g.key] ~= name then
            BattleShoutGlowDB.lastUsed[g.key] = name
            scanSoon()
        end
    end
    -- (unless your buffs have shown it doesn't: then the seal just keeps its time. Checked again after each one.)
    for _, used in ipairs(ENDS[name] or {}) do
        if isUp(used) then
            used.judged = { at = GetTime(), upUntil = used.upUntil }
            if not endsKept(used) then
                used.upUntil = 0
                if used.known ~= nil then used.known = false end
            end
        end
    end
    refresh()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
                     "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "UPDATE_MACROS" }) do
    ev:RegisterEvent(e)
end
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
-- The target's casts, for the interrupts (targetCasting): started, and every way one ends
local cast = CreateFrame("Frame")
local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
-- (not SUCCEEDED: a channel sends it as it starts; STOP / CHANNEL_STOP come at every end)
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
                     "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED" }) do
    pcall(cast.RegisterUnitEvent, cast, e, "target")
end
cast:RegisterEvent("PLAYER_TARGET_CHANGED")
cast:SetScript("OnEvent", function(_, e)
    castSeen = CAST_START[e] and GetTime() or nil
end)
pcall(ev.RegisterUnitEvent, ev, "UNIT_COMBAT", "player")
-- What hitting you came to: a block (full, or part of a hit), dodge or parry opens up Revenge
local AVOIDED = { BLOCK = true, DODGE = true, PARRY = true }
ev:SetScript("OnEvent", function(_, e, ...)
    if e == "UNIT_COMBAT" then
        local _, action, flag = ...
        if not secret(action) and AVOIDED[action or ""]
            or not secret(flag) and flag == "BLOCK_REDUCED" then
            lastAvoid = GetTime()
        end
    elseif e == "PLAYER_LOGIN" then
        setup()
        refresh()
        markMake()
        if markSlots[1] then
            BattleShoutGlowDB.markProbe = nil  -- (a new session's notes)
            C_Timer.After(4, function() markSelfTest(false) end)
        end        place()
        C_Timer.After(2, function() pcall(place) end)  -- again once the controller layout has put the portrait in place
        scanSoon()
    elseif e == "UNIT_AURA" then
        refresh()
    elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
        onCast(select(3, ...))
    else
        if e == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(1, refresh)
            wipe(dots); wipe(stacks); wipe(areas)  -- (the fight's targets: gone)
            markMake()
        end
        if e == "SPELLS_CHANGED" then
            setup(); wipe(lastsCache)
            markLearn(); markMake()  -- (a new rank of Rend; or Rend learned at last)
        end
        if e == "ADDON_LOADED" and (...) == "BattleShoutGlow" then
            -- QuietKit's welcome keeps its marks in a table of their own: what's learned in a first session (a buff's
            -- time) would make a new player look like one who had Buff Glow before. had: one who did.
            if BattleShoutGlowDB ~= unsaved and type(BattleShoutGlowDB.welcome) ~= "table" then
                BattleShoutGlowDB.welcome = { had = true }
            end
        end
        -- (a loading screen, or a switch between controller and mouse: the crossbar's buttons are looked for again
        -- only if none were found; the addon that makes the crossbar loading: they're new)
        if e == "PLAYER_ENTERING_WORLD" or e == "GAME_PAD_ACTIVE_CHANGED" then padDirty = true end
        if e == "ADDON_LOADED" and tostring((...)):find("Gamepad") then padDirty, padStale = true, true end
        if e ~= "ADDON_LOADED" or padDirty then scanSoon() end
    end
end)
pcall(ev.RegisterEvent, ev, "GAME_PAD_ACTIVE_CHANGED")
ev:RegisterEvent("ADDON_LOADED")
local since, sinceRead = 0, 0
local updateError
ev:SetScript("OnUpdate", function(_, elapsed)
    since, sinceRead = since + elapsed, sinceRead + elapsed
    if sinceRead >= 1 then sinceRead = 0; refresh() end
    if since >= 0.15 then
        since = 0
        local ok, err = pcall(update)
        if not ok and not updateError then  -- (said once: a broken update would otherwise just go dark)
            updateError = tostring(err)
            QuietKit.Toast("Buff Glow stopped by an error. /bsg why shows it.", ICON)
        end
    end
end)

SLASH_BATTLESHOUTGLOW1 = "/bsg"
SLASH_BATTLESHOUTGLOW2 = "/bglow"
-- The icons movable (dragged where you like) or placed
local function setMoving(moving)
    strip:EnableMouse(moving)
    bg:SetShown(moving)
end

SlashCmdList.BATTLESHOUTGLOW = function(msg)
    msg = (msg or ""):lower()
    if msg == "help" then
        Print("the commands:")
        print("  /bsg  what it watches for your class, and how many buttons glow")
        print("  /bsg rotation  the next-move ring on or off;  /bsg why  why each move was lit or not")
        print("  /bsg rend  the red mark on enemy nameplates still without your Rend, on or off;  /bsg rend macro  "
            .. "a Rend Auto macro that casts on what you hover;  /bsg slam macro, /bsg bash macro  the same for Shield Slam, Shield Bash;  /bsg rend why  what the marks saw;  /bsg rend test  a check")
        print("  /bsg icons  separate icons as well, with the controller;  /bsg move  drag them;  /bsg reset  "
            .. "back under your portrait")
        print("  /bsg options  the settings (Options, AddOns, Quiet)")
        return
    elseif msg == "options" or msg == "settings" then
        if not QuietKit.Open("battleshoutglow") then
            Print("the settings are in Options, AddOns, Quiet, Buff Glow.")
        end
        return
    elseif msg == "move" then
        local moving = not strip:IsMouseEnabled()
        setMoving(moving)
        Print(moving and "drag the icons where you want them, then /bsg move again" or "icons placed")
        return
    elseif msg == "icons" then
        BattleShoutGlowDB.icons = not BattleShoutGlowDB.icons
        Print("separate icons " .. (BattleShoutGlowDB.icons and "on (under your portrait, /bsg move to place them)" or "off"))
        return
    elseif msg == "reset" then
        BattleShoutGlowDB.pos = nil
        place()
        Print("the icons are back under your portrait.")
        return
    elseif msg == "why" then
        -- Why each move was or wasn't lit: at the last moment of your last fight, or now if you have a target
        local why = lastWhy
        local when = "at the end of your last fight"
        if enemyTargeted() then
            why, when = {}, "now"
            pickNext(why)
        end
        local r = rage()
        if BY_FORM then
            Print(("next move %s%s:"):format(when, updateError and (" (error: " .. updateError .. ")") or ""))
        else
            Print(("rotation %s (stance %s, rage %s)%s:"):format(when, tostring(stance()),
                r and tostring(r) or "can't be read", updateError and (", error: " .. updateError) or ""))
        end
        if not why or not why[1] then
            print("  nothing yet: fight something with it targeted, then /bsg why")
        else
            for _, line in ipairs(why) do print("  " .. line) end
        end
        return
    elseif msg == "rend macro" or msg == "slam macro" or msg == "bash macro" then
        local spec = msg == "slam macro" and slamMacroSpec() or msg == "bash macro" and bashMacroSpec()
            or markMacroSpec()
        local ok, why = QuietKit.MacroReady(spec)
        Print(ok and ('"' .. spec.name .. '" casts on the enemy under your mouse, else your '
            .. 'target; drag it to your bar from /macro. Your other macros are left as they are.') or tostring(why))
        return
    elseif msg == "rend test" then
        if markSelfTest(true) then
            Print("two test squares above the middle of your screen for 12 sec: each should show a buff of yours "
                .. "over its red. /bsg rend why in a moment for what they saw.")
        else
            Print("the test needs you out of a fight, with a buff on you (Battle Shout will do).")
        end
        return
    elseif msg == "rend why" then
        Print(("%s marks: macros %s; IDs %s; %d display(s)%s."):format(tostring(MARK), tostring(markMacroState()),
            (function()
                local ids = {}
                for id in pairs(markIds) do ids[#ids + 1] = tostring(id) end
                table.sort(ids)
                return table.concat(ids, " ")
            end)(), #markSlots, markError and (", error: " .. markError) or ""))
        local p = BattleShoutGlowDB.markProbe or {}
        if not p[1] then print("  nothing seen yet: Rend something, then /bsg rend why") end
        for i = math.max(1, #p - 14), #p do print("  " .. p[i]) end
        return
    elseif msg == "rend" then
        BattleShoutGlowDB.rendMark = BattleShoutGlowDB.rendMark == false
        markMake()
        Print("Rend marks on nameplates " .. (BattleShoutGlowDB.rendMark and "on" or "off")
            .. (MARK and "" or " (only for Warriors)")
            .. (BattleShoutGlowDB.rendMark and InCombatLockdown() and not markSlots[1] and " (made once you're out of the fight)" or ""))
        return
    elseif msg == "rotation" then
        BattleShoutGlowDB.rotation = BattleShoutGlowDB.rotation == false
        Print("rotation light " .. (BattleShoutGlowDB.rotation and "on" or "off")
            .. (ROTATION[1] and "" or " (no rotation for your class yet)"))
        return
    end
    setup()
    refresh()
    padDirty, padStale = true, true
    local n, onPad = scan()
    local parts = {}
    for _, g in ipairs(KEEP) do
        local state = isUp(g) and "up" or "not up"
        if g.combatOnly and not inFight() and not isUp(g) then state = "not up (only missed in a fight)" end
        local name = lastUsed(g) or g.first
        local lasts = learnedDuration(name)
        if lasts then state = state .. ", lasts " .. lasts .. " s" end
        if next(g.ends) then
            local kept = endsKept(g)
            state = state .. (kept == true and ", stays after Judgement" or kept == false and ", Judgement uses it up"
                or ", Judgement not seen yet")
        end
        parts[#parts + 1] = name .. ": " .. state
    end
    local secretNote = (KEEP[1] and KEEP[1].known == nil) and " (buffs are secret now: going by your last casts)" or ""
    if ROTATION[1] then
        local moves, listed = {}, {}
        for _, step in ipairs(currentRotation() or {}) do
            if step.choices then step.name = chosen(step) end
            if knows(step.name) and not listed[step.name] then
                listed[step.name] = true
                moves[#moves + 1] = step.name
            end
        end
        local nextName = pickNext()
        local STANCES = { [1] = "Battle Stance", [2] = "Defensive Stance", [3] = "Berserker Stance" }
        secretNote = secretNote .. (" Rotation light %s, %s: %s.%s"):format(
            BattleShoutGlowDB.rotation == false and "off (/bsg rotation)" or "on",
            BY_FORM and "as you are now" or STANCES[stance() or 1] or "this stance",
            #moves > 0 and table.concat(moves, " > ") or "no moves learned yet",
            nextName and (" Next now: " .. nextName .. ".") or "")
    end
    if MARK then
        local on = 0
        for _ in pairs(markOn) do on = on + 1 end
        local state
        if BattleShoutGlowDB.rendMark == false then state = "off (/bsg rend)"
        elseif not knows(MARK) then state = "on, once you've learned it"
        elseif markError then state = "can't be shown: " .. markError
        elseif not markSlots[1] then state = "on, made once you're out of the fight"
        else state = ("on, following %d enemy nameplate(s)"):format(on) end
        secretNote = secretNote .. (" %s marks: %s."):format(MARK, state)
    end
    Print(("%d button(s) glow, %d of them on the crossbar (of %d crossbar buttons found). %s%s")
        :format(n, onPad, #padButtons, #parts > 0 and (table.concat(parts, ", ") .. ".") or "Nothing to keep up for your class.",
            secretNote))
end

-- ---------- the settings, for QuietKit (QuietKit.lua): Options > AddOns > Quiet, and Improved Forever's Quiet tab ----------
QuietKit.Register({
    key = "battleshoutglow",
    title = "Buff Glow",
    icon = ICON,
    about = "While a buff you keep up isn't on you (Battle Shout, a Paladin's aura, blessing or seal, Fortitude, Arcane "
        .. "Intellect...) its button pulses gold, and moves that open up (Overpower, Revenge, Hammer of Wrath...) glint "
        .. "blue. Your next move gets a soft ring, for every class; your interrupt blinks orange while your target "
        .. "casts, and for a Warrior enemy nameplates without your Rend get a red mark in a fight.",
    how = "Nothing to set up: keep those spells on your action bars or crossbar.",
    command = "/bsg",
    db = function()
        BattleShoutGlowDB.welcome = BattleShoutGlowDB.welcome or {}
        return BattleShoutGlowDB.welcome
    end,
    news = {
        version = "3.7.0",
        text = "Every class now gets the next-move ring a Warrior had, each after its WoW Forever levelling guide "
            .. "(/bsg why says why a move was lit; the switch is in the settings). And more buffs to keep up: Divine "
            .. "Spirit, Heart of the Lion, Trueshot Aura, Water Shield, a shaman's weapon imbue, a druid's Thorns.",
    },
    items = {
        {
            label = "Rend marks on nameplates (Warriors)",
            tip = "In a fight, a red Rend icon beside each enemy's nameplate while your Rend isn't on it. Once it "
                .. "is, your Rend's own icon covers the mark, its time running down. Not on enemies that don't bleed.",
            get = function() return BattleShoutGlowDB.rendMark ~= false end,
            set = function(on)
                BattleShoutGlowDB.rendMark = on and true or false
                markMake()
            end,
        },
        {
            label = "Rend on what you hover",
            tip = "Rend Auto: a macro that casts Rend on the enemy under your mouse (its nameplate or itself), else "
                .. "on your target, swapping out of Berserker Stance first. Yours already exists: this puts its text back if it changed.",
            macro = markMacroSpec(),
        },
        {
            label = "Shield Slam on what you hover",
            tip = "Shield Slam Auto: a macro that casts Shield Slam on the enemy under your mouse (its nameplate or "
                .. "itself), else on your target. Made if it isn't there; its text put back if it changed.",
            macro = slamMacroSpec(),
        },
        {
            label = "Shield Bash on what you hover",
            tip = "Shield Bash Auto: a macro that interrupts the enemy under your mouse (its nameplate or itself), else "
                .. "your target, swapping out of Berserker Stance first. Made if it isn't there; its text put back if "
                .. "it changed.",
            macro = bashMacroSpec(),
        },
        {
            label = "Next-move ring",
            tip = "A slow pale-green ring on the move to press next, for your class as its WoW Forever levelling guide "
                .. "plays it (a warrior's by stance, a druid's by form); an orange blink on your interrupt while your "
                .. "target casts. /bsg why says why each move was lit or not.",
            get = function() return BattleShoutGlowDB.rotation ~= false end,
            set = function(on) BattleShoutGlowDB.rotation = on and true or false end,
        },
        {
            section = "With the controller",
            label = "Separate icons as well",
            tip = "The same glows as icons of their own, under your portrait, while the controller is on: for "
                .. "crossbar buttons the game won't let an addon read.",
            get = function() return BattleShoutGlowDB.icons and true or false end,
            set = function(on) BattleShoutGlowDB.icons = on and true or false end,
        },
        {
            label = "Move the icons",
            tip = "Shows every icon so you can drag them where you like. Turn it off again to leave them there.",
            get = function() return strip:IsMouseEnabled() and true or false end,
            set = function(on) setMoving(on) end,
        },
        {
            label = "Back under your portrait",
            tip = "Puts the icons back where they start, under your portrait.",
            text = "Reset their place",
            run = function()
                BattleShoutGlowDB.pos = nil
                place()
            end,
        },
    },
})