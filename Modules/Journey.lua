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
    START = "Interface\\Icons\\INV_Misc_Book_09",
    LEVEL = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    MAX_LEVEL = "Interface\\Icons\\INV_Crown_01",
    FIRST_DUNGEON_BOSS = "Interface\\Icons\\Ability_DualWield",
    FIRST_RAID_BOSS = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    FIRST_RARE = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02",
    FIRST_EPIC = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    FIRST_LEGENDARY = "Interface\\Icons\\INV_Misc_Gem_Topaz_02",
    FIRST_DUEL = "Interface\\Icons\\Ability_Parry",
    GUILD = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
}

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
    end
    return L["JOURNEY_" .. entry.kind]
end

-- The start of tracking: the earliest real record, or this login.
table.insert(ns.onLogin, function()
    local journey = data()
    if journey and not journey.started then
        journey.started = API.Time()
    end
end)
