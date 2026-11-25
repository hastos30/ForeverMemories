-- Modules/Journey.lua
-- Character Journey (v0.9.0): a timeline of important moments of the
-- current character. It listens to the same normalized events as auto
-- capture (Core/Events.lua calls Journey.OnEvent before the Engine), so it
-- works whether or not the event is photographed, and takes no shots.
--
-- Recorded:
--   LEVEL (every level), MAX_LEVEL (the level-up to GetMaxPlayerLevel),
--   FIRST_DUNGEON_BOSS / FIRST_RAID_BOSS (by IsInInstance at the kill),
--   FIRST_RARE / FIRST_EPIC / FIRST_LEGENDARY, FIRST_DUEL (own win), GUILD
--   (every real join). "First" means the first since ForeverMemories
--   tracks the character; each is written once. Nothing is invented for
--   the time before tracking: the start itself is shown as "Journey started".
local _, ns = ...

local Journey = {}
ns.Journey = Journey

local API = ns.API

Journey.listeners = {}

Journey.ICONS = {
    START = "Interface\\AddOns\\ForeverMemories\\Media\\Branding\\compass_emblem.tga",
    LEVEL = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    MAX_LEVEL = "Interface\\Icons\\INV_Crown_01",
    FIRST_DUNGEON_BOSS = "Interface\\Icons\\Ability_DualWield",
    FIRST_RAID_BOSS = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    FIRST_RARE = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02",
    FIRST_EPIC = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    FIRST_LEGENDARY = "Interface\\Icons\\INV_Misc_Gem_Topaz_02",
    FIRST_DUEL = "Interface\\Icons\\Ability_Parry",
    GUILD = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    -- v0.18.0: milestones and new firsts.
    FIRST_SHOT = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\auto_capture.tga",
    M_SHOTS = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\screenshots.tga",
    M_STEPS = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\steps.tga",
    M_HOURS = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\playtime.tga",
    M_GOLD = "Interface\\Icons\\INV_Misc_Coin_01",
    M_QUESTS = "Interface\\Icons\\INV_Misc_Note_01",
    FIRST_DEATH = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    M_DEATHS = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    M_EXALTED = "Interface\\Icons\\INV_Misc_Book_09",
    FIRST_EXALTED = "Interface\\Icons\\INV_Misc_Book_09",
    FIRST_TAXI = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    FIRST_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse",
    FIRST_PARTY = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    FIRST_RAID_GROUP = "Interface\\Icons\\INV_Misc_GroupLooking",
    ACHIEVEMENT = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\achievements.tga",
}

-- Three visual levels of the timeline (v0.18.0): 3 = legendary moment,
-- 2 = a first or a milestone, 1 = an ordinary step (a level).
function Journey.Tier(entry)
    local kind = entry.kind
    if kind == "MAX_LEVEL" or kind == "FIRST_LEGENDARY" or kind == "FIRST_RAID_BOSS" then
        return 3
    elseif kind == "ACHIEVEMENT" then
        local def = ns.Achievements and ns.Achievements.BY_ID[entry.info]
        return def and (def.rarity == "epic" or def.rarity == "legendary") and 3 or 2
    elseif kind == "LEVEL" then
        return 1
    end
    return 2
end

local function data()
    return ns.character and ns.character.journey
end

local function notify()
    for _, listener in ipairs(Journey.listeners) do
        ns.SafeCall("journey listener", listener)
    end
end

-- Adds one moment. `first` = true: only if this kind was never recorded.
function Journey.Add(kind, info, zone, first)
    local journey = data()
    if not journey then
        return nil
    end
    local now = API.Time()
    if first then
        if journey.firsts[kind] then
            return nil
        end
        journey.firsts[kind] = now
    end
    local last = journey.events[#journey.events]
    if last and last.kind == kind and last.info == info and now - last.t < 60 then
        return nil -- the same moment reported twice
    end
    local entry = { t = now, kind = kind, zone = zone, info = info }
    journey.events[#journey.events + 1] = entry
    while #journey.events > ns.Database.MAX_JOURNEY do
        table.remove(journey.events, 1)
    end
    notify()
    return entry
end

local LOOT = { LOOT_RARE = "FIRST_RARE", LOOT_EPIC = "FIRST_EPIC", LOOT_LEGENDARY = "FIRST_LEGENDARY" }

-- A normalized event from Core/Events.lua (only confirmed game events).
function Journey.OnEvent(kind, info, zone)
    if kind == "LEVEL" and type(info) == "number" then
        local max = API.MaxLevel()
        if max and info >= max then
            Journey.Add("MAX_LEVEL", info, zone, true)
        else
            Journey.Add("LEVEL", info, zone)
        end
    elseif kind == "BOSS" then
        local where = API.InstanceType()
        if where == "party" then
            Journey.Add("FIRST_DUNGEON_BOSS", info, zone, true)
        elseif where == "raid" then
            Journey.Add("FIRST_RAID_BOSS", info, zone, true)
        end
    elseif LOOT[kind] then
        Journey.Add(LOOT[kind], info, zone, true)
    elseif kind == "DUEL" then
        Journey.Add("FIRST_DUEL", info, zone, true)
    elseif kind == "GUILD" then
        Journey.Add("GUILD", info, zone)
    end
end

-- Timeline, newest first; the start of tracking is the last entry.
function Journey.Rows()
    local journey = data()
    local rows = {}
    if not journey then
        return rows
    end
    for _, entry in ipairs(journey.events) do
        rows[#rows + 1] = entry
    end
    table.sort(rows, function(a, b) return a.t > b.t end)
    if journey.started then
        rows[#rows + 1] = { t = journey.started, kind = "START" }
    end
    return rows
end

function Journey.Icon(kind)
    return Journey.ICONS[kind] or ns.Registry.LEGACY_ICON
end

-- Title of a moment: "Reached level 30", "First epic item" ...
function Journey.Title(entry)
    local L = ns.L
    if entry.kind == "LEVEL" or entry.kind == "MAX_LEVEL" then
        return string.format(L["JOURNEY_" .. entry.kind], tonumber(entry.info) or 0)
    elseif entry.kind == "ACHIEVEMENT" then
        local def = ns.Achievements and ns.Achievements.BY_ID[entry.info]
        return string.format(L.JOURNEY_ACHIEVEMENT, def and ns.Achievements.Text(def, "title") or "?")
    elseif string.sub(entry.kind, 1, 2) == "M_" then
        return string.format(L["JOURNEY_" .. entry.kind], ns.Num(tonumber(entry.info) or 0))
    end
    return L["JOURNEY_" .. entry.kind]
end

-- Second line of a moment besides the zone (boss, item, opponent), or nil.
function Journey.Detail(entry)
    if entry.kind == "ACHIEVEMENT" or string.sub(entry.kind, 1, 2) == "M_" then
        return nil
    end
    return type(entry.info) == "string" and entry.info ~= "" and entry.info or nil
end

---------------------------------------------------------------------------
-- Milestones (v0.18.0): round numbers of what ForeverMemories already
-- keeps. What was reached before this version is marked as seen without
-- an entry (a baseline is never shown as a new moment).
---------------------------------------------------------------------------
Journey.MILESTONES = {
    { kind = "M_SHOTS", first = "FIRST_SHOT", steps = { 1, 100, 500, 1000 },
      value = function(c) return c.shotsTotal end },
    { kind = "M_STEPS", steps = { 1000, 100000, 500000, 1000000 },
      value = function(c) return c.steps and math.floor(c.steps.total or 0) end },
    { kind = "M_HOURS", steps = { 10, 100, 1000 },
      value = function(c) return c.playtime and math.floor((c.playtime.total or 0) / 3600) end },
    { kind = "M_GOLD", steps = { 1, 10, 100, 1000, 10000 },
      value = function(c) local p = c.progress return type(p) == "table" and p.maxMoney and math.floor(p.maxMoney / 10000) end },
    { kind = "M_QUESTS", steps = { 10, 100, 500, 1000 },
      value = function(c) local p = c.progress return type(p) == "table" and p.quests end },
    { kind = "M_DEATHS", first = "FIRST_DEATH", steps = { 1, 10, 100, 500 },
      value = function(c) local t = c.tracks return type(t) == "table" and t.deaths end },
    { kind = "M_EXALTED", first = "FIRST_EXALTED", steps = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
      value = function(c)
          local p = c.progress
          if type(p) ~= "table" or type(p.exalted) ~= "table" then return nil end
          local n = 0
          for _ in pairs(p.exalted) do n = n + 1 end
          return n
      end },
    { first = "FIRST_TAXI", steps = { 1 }, value = function(c) local t = c.tracks return type(t) == "table" and t.taxi end },
    { first = "FIRST_MOUNT", steps = { 1 }, value = function(c) local t = c.tracks return type(t) == "table" and (t.mount and 1 or 0) end },
    { first = "FIRST_PARTY", steps = { 1 }, value = function(c) local t = c.tracks return type(t) == "table" and t.partyJoins end },
    { first = "FIRST_RAID_GROUP", steps = { 1 }, value = function(c) local t = c.tracks return type(t) == "table" and t.raidJoins end },
}

function Journey.CheckMilestones()
    local character = ns.character
    local journey = data()
    if not journey or character ~= ns.db.characters[ns.characterKey] or ns.readOnly then
        return 0
    end
    local seeding = not journey.milestonesSeeded
    local added = 0
    for _, m in ipairs(Journey.MILESTONES) do
        local ok, value = pcall(m.value, character)
        if ok and type(value) == "number" then
            for _, step in ipairs(m.steps) do
                local kind = (step == 1 and m.first) or m.kind
                local key = "milestone:" .. tostring(m.kind or m.first) .. ":" .. step
                if kind and value >= step and not journey.firsts[key] then
                    journey.firsts[key] = API.Time()
                    if not seeding then
                        Journey.Add(kind, step, API.ZoneName())
                        added = added + 1
                    end
                end
            end
        end
    end
    journey.milestonesSeeded = true
    return added
end

-- Earned achievements (live only) join the timeline.
function Journey.OnAchievements(defs)
    for _, def in ipairs(defs or {}) do
        Journey.Add("ACHIEVEMENT", def.id, API.ZoneName())
    end
end

-- The start of tracking: the earliest real record, or this login.
table.insert(ns.onLogin, function()
    local journey = data()
    if journey and not journey.started then
        journey.started = API.Time()
    end
end)
