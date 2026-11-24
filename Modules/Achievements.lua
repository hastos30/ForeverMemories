-- Modules/Achievements.lua
-- Adventure Achievements (v0.13.0): ForeverMemories' own achievements,
-- separate from the game's achievements. Per character. Progress comes
-- from data that already exists (no new counters):
--   shots - shotsTotal, steps - steps.total, zones - visited zones,
--   days  - days with any recorded play (Records.PlayedDays),
--   region / catalog - World Explorer (ZoneCatalog.Explorer).
-- Completion is stored as character.achievements.done[id] = time, or 0
-- when the date is unknown (progress reached before 0.13.0 or while the
-- addon did not run). A completed achievement is never taken back, even
-- if the zone catalog grows later. No rewards, sounds or screenshots.
local _, ns = ...

local Achievements = {}
ns.Achievements = Achievements

local ICON = {
    photo = "Interface\\Icons\\INV_Misc_Spyglass_03",
    travel = "Interface\\Icons\\Ability_Rogue_Sprint",
    explore = "Interface\\Icons\\INV_Misc_Map_01",
    history = "Interface\\Icons\\INV_Misc_Book_09",
}

Achievements.GROUPS = { "photo", "travel", "explore", "history" }
Achievements.LIST = {
    { id = "FIRST_MEMORY", group = "photo", metric = "shots", target = 1 },
    { id = "PHOTOGRAPHER", group = "photo", metric = "shots", target = 100 },
    { id = "MEMORY_KEEPER", group = "photo", metric = "shots", target = 500 },
    { id = "MASTER_PHOTOGRAPHER", group = "photo", metric = "shots", target = 1000 },
    { id = "FIRST_STEPS", group = "travel", metric = "steps", target = 1000 },
    { id = "WANDERER", group = "travel", metric = "steps", target = 100000 },
    { id = "TRAVELER", group = "travel", metric = "steps", target = 500000 },
    { id = "ENDLESS_JOURNEY", group = "travel", metric = "steps", target = 1000000 },
    { id = "EXPLORER", group = "explore", metric = "zones", target = 25 },
    { id = "EK_EXPLORER", group = "explore", metric = "region", region = "EK" },
    { id = "KALIMDOR_EXPLORER", group = "explore", metric = "region", region = "KALIMDOR" },
    { id = "MASTER_OF_AZEROTH", group = "explore", metric = "catalog" },
    { id = "LIVING_HISTORY", group = "history", metric = "days", target = 30 },
    { id = "SEASON_OF_ADVENTURES", group = "history", metric = "days", target = 90 },
    { id = "YEAR_OF_MEMORIES", group = "history", metric = "days", target = 365 },
}
for _, def in ipairs(Achievements.LIST) do
    def.icon = ICON[def.group]
end

-- Current value and target of every metric of `groups` (nil = all) for
-- the current (or viewed) character. A catalog that cannot be confirmed
-- in this client gives no target (progress unknown).
local function measure(character, groups)
    local need = {}
    for _, group in ipairs(groups or Achievements.GROUPS) do
        need[group] = true
    end
    local m = {}
    if need.photo then
        m.shots = character.shotsTotal or 0
    end
    if need.travel then
        m.steps = math.floor(character.steps and character.steps.total or 0)
    end
    if need.explore then
        local zones = 0
        for _ in pairs(character.visited or {}) do
            zones = zones + 1
        end
        m.zones = zones
        local explorer = ns.ZoneCatalog.Explorer()
        if explorer.complete and explorer.total > 0 then
            m.catalog = { explorer.visited, explorer.total }
            for _, region in ipairs(explorer.regions) do
                m["region:" .. region.id] = { region.visited, region.total }
            end
        end
    end
    if need.history then
        local days = 0
        for _ in pairs(ns.Records.PlayedDays(character)) do
            days = days + 1
        end
        m.days = days
    end
    return m
end

local function progressOf(def, m)
    if def.metric == "region" or def.metric == "catalog" then
        local pair = m[def.metric == "region" and ("region:" .. def.region) or "catalog"]
        if pair then
            return pair[1], pair[2]
        end
        return nil, nil
    end
    return m[def.metric], def.target
end

local function store(character)
    local a = character.achievements
    if type(a) ~= "table" then
        a = { done = {}, seeded = false }
        character.achievements = a
    end
    return a
end

-- Records completions of the logged-in character. The first check ever
-- stores what is already complete with an unknown date (0).
function Achievements.Check(groups)
    local character = ns.character
    if not character or character ~= ns.db.characters[ns.characterKey] then
        return
    end
    local a = store(character)
    if not a.seeded then
        groups = nil
    end
    local wanted = {}
    for _, group in ipairs(groups or Achievements.GROUPS) do
        wanted[group] = true
    end
    local m = measure(character, groups)
    local now = ns.API.Time()
    for _, def in ipairs(Achievements.LIST) do
        if wanted[def.group] and not a.done[def.id] then
            local value, target = progressOf(def, m)
            if value and target and target > 0 and value >= target then
                a.done[def.id] = a.seeded and now or 0
                ns.Logger.Info("Achievement: " .. def.id)
            end
        end
    end
    a.seeded = true
end

-- Every achievement with its state for the current (or viewed) character:
--   { def, value, target, done, at (time or nil when unknown), available }
function Achievements.Get()
    local character = ns.character
    if not character then
        return {}
    end
    local done = type(character.achievements) == "table" and character.achievements.done or {}
    local m = measure(character)
    local list = {}
    for _, def in ipairs(Achievements.LIST) do
        local value, target = progressOf(def, m)
        local at = done[def.id]
        local reached = value and target and target > 0 and value >= target
        list[#list + 1] = {
            def = def, value = value, target = target, available = target ~= nil,
            done = at ~= nil or reached or false,
            at = type(at) == "number" and at > 0 and at or nil,
        }
    end
    return list
end

local function checker(...)
    local groups = { ... }
    return function() Achievements.Check(groups) end
end

table.insert(ns.onLogin, function() Achievements.Check() end)
table.insert(ns.History.listeners, checker("photo", "history"))
table.insert(ns.Steps.listeners, checker("travel"))
table.insert(ns.Locations.listeners, checker("explore", "history"))
