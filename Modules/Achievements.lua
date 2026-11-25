-- Modules/Achievements.lua
-- Hall of Memories (v0.14.0): ForeverMemories' own achievements from the
-- approved catalog 1.0 (Modules/AchievementCatalog.lua; its source
-- JSON is no longer in the repo). 100 per character in 10 categories and
-- 6 account "Legacy" achievements. Separate from the game's achievements:
-- no points, no rewards, nothing to do daily.
--
-- Every condition is `metric >= target`. A metric adapter returns the
-- current value or nil = unknown (source missing in this client, tracker
-- not built yet, catalog not confirmed). Unknown is never shown as 0 and
-- never unlocks anything.
--
-- State of an achievement:
--   "done"        - unlocked (stored once per ID and scope, never revoked)
--   "progress"    - value known, target not reached
--   "pending"     - its tracker comes in a later version (unknown now)
--   "unknown"     - the client has no source / the catalog is unconfirmed
--   "unavailable" - cannot be tracked in Forever (reason shown), e.g. a
--                   boat trip: the client tells nothing about it.
--
-- First check of a character (or the account) after install or migration:
-- what is already reached is stored quietly with an unknown date ("seed").
-- Later unlocks get the real time ("live") and are announced to listeners.
local _, ns = ...

local Achievements = {}
ns.Achievements = Achievements

local API = ns.API

Achievements.CATALOG = ns.AchievementCatalog
Achievements.CATEGORIES = {
    "memories", "steps", "travel", "locations", "time", "combat",
    "professions", "social", "anniversaries", "special",
}
Achievements.RARITIES = { "common", "rare", "epic", "legendary" }
-- Rarity colors of the Obsidian Journal palette (#B0A18B, #88A5CE, #B198C9, #D8A558).
Achievements.RARITY_COLORS = {
    common = { 0.690, 0.631, 0.545 }, rare = { 0.533, 0.647, 0.808 },
    epic = { 0.694, 0.596, 0.788 }, legendary = { 0.847, 0.647, 0.345 },
}

-- Built-in icons until the medallion textures are integrated (v0.15.0).
local ICON = {
    memories = "Interface\\Icons\\INV_Misc_Spyglass_03",
    steps = "Interface\\Icons\\Ability_Rogue_Sprint",
    travel = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    locations = "Interface\\Icons\\INV_Misc_Map_01",
    time = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    combat = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    chronicle = "Interface\\Icons\\INV_Misc_Book_09",
    social = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    special = "Interface\\Icons\\INV_Crown_01",
    legacy = "Interface\\Icons\\INV_Misc_Book_09",
}
Achievements.ICON = ICON

-- Metrics that cannot be tracked in World of Warcraft: Forever, with the
-- reason (locale key). Decided with Nedisan on 2026-11-25.
Achievements.UNAVAILABLE = {
    boat_completed = "ACH_WHY_TRANSPORT", zeppelin_completed = "ACH_WHY_TRANSPORT",
    dungeon_clears = "ACH_WHY_CLEAR", raid_clears = "ACH_WHY_CLEAR",
}

-- Metrics whose tracker is not built yet (they are unknown until then).
-- v0.18.0: the others are tracked by Modules/Trackers.lua; crafts and
-- battleground wins still have no verified signal in the Forever client.
Achievements.PENDING = {
    crafts = true, bg_wins = true,
}

-- Seconds of active play that make a day an "active day".
Achievements.ACTIVE_DAY = 60

-- Lookup by id.
Achievements.BY_ID = {}
for _, def in ipairs(Achievements.CATALOG.list) do
    Achievements.BY_ID[def.id] = def
end

-- Chains (v1.0.0-beta.18): chain id -> its steps in catalog order.
-- An achievement without `chain` is a chain of one step (not listed here).
Achievements.CHAINS = {}
for _, def in ipairs(Achievements.CATALOG.list) do
    if def.chain then
        local steps = Achievements.CHAINS[def.chain]
        if not steps then
            steps = {}
            Achievements.CHAINS[def.chain] = steps
        end
        steps[#steps + 1] = def
    end
end

-- Steps of the chain of `def` (a lone achievement: only itself).
function Achievements.Steps(def)
    return def and def.chain and Achievements.CHAINS[def.chain] or { def }
end

-- listener(list of newly unlocked defs) - live unlocks only.
Achievements.listeners = {}

---------------------------------------------------------------------------
-- Metric adapters. ctx = { character, now, cache } ; account ones get
-- ctx.db. Return a number or nil (unknown).
---------------------------------------------------------------------------
local function count(map, test)
    local n = 0
    for k, v in pairs(type(map) == "table" and map or {}) do
        if not test or test(v, k) then
            n = n + 1
        end
    end
    return n
end

local function positive(v)
    return type(v) == "number" and v > 0
end

local function cached(ctx, key, fn)
    if ctx.cache[key] == nil then
        ctx.cache[key] = fn() or false
    end
    return ctx.cache[key] or nil
end

local function explorer(ctx)
    return cached(ctx, "explorer", function()
        local e = ns.ZoneCatalog.Explorer(ctx.character)
        return e.complete and e.total > 0 and e or nil
    end)
end

local function shotKinds(ctx)
    return cached(ctx, "shotKinds", function()
        local k = { manual = 0, passive = 0, event = 0 }
        for _, r in ipairs(ctx.character.shots or {}) do
            if r.manual or r.ev == "MANUAL" then
                k.manual = k.manual + 1
            elseif r.ev == "PASSIVE" then
                k.passive = k.passive + 1
            else
                k.event = k.event + 1
            end
        end
        return k
    end)
end

-- Per catalog area: visits and steps from Location Analytics.
local function zoneTotals(ctx)
    return cached(ctx, "zoneTotals", function()
        local zs = ctx.character.zoneStats
        if type(zs) ~= "table" or type(zs.zones) ~= "table" or not explorer(ctx) then
            return nil
        end
        local areas = {}
        for key, entry in pairs(zs.zones) do
            local area = ns.ZoneCatalog.AreaOfKey(ctx.character, key)
            if area then
                local t = areas[area] or { visits = 0, steps = 0 }
                t.visits = t.visits + (entry.visits or 0)
                t.steps = t.steps + (entry.steps or 0)
                areas[area] = t
            end
        end
        return areas
    end)
end

local function region(ctx, id)
    local e = explorer(ctx)
    if not e then
        return nil
    end
    for _, r in ipairs(e.regions) do
        if r.id == id then
            return r
        end
    end
end

local function progressOf(ctx)
    return type(ctx.character.progress) == "table" and ctx.character.progress or nil
end

local function firstSeen(kind)
    return function(ctx)
        local j = ctx.character.journey
        if type(j) ~= "table" or not j.started then
            return nil -- the diary was never running: unknown
        end
        return type(j.firsts) == "table" and j.firsts[kind] and 1 or 0
    end
end

local M = {}
Achievements.METRICS = M

M.shots = function(ctx) return ctx.character.shotsTotal or 0 end
M.manual_shots = function(ctx) return shotKinds(ctx).manual end
M.passive_shots = function(ctx) return shotKinds(ctx).passive end
M.event_shots = function(ctx) return shotKinds(ctx).event end
M.shot_days = function(ctx) return count(ctx.character.shotsByDay, positive) end
M.shot_zones = function(ctx)
    if not explorer(ctx) then return nil end
    local areas = {}
    for name in pairs(ctx.character.shotZones or {}) do
        local area = ns.ZoneCatalog.AreaOfName(name)
        if area then areas[area] = true end
    end
    return count(areas)
end

M.steps = function(ctx) return math.floor(ctx.character.steps and ctx.character.steps.total or 0) end
M.step_days = function(ctx) return count(ctx.character.steps and ctx.character.steps.days, positive) end
M.step_zones = function(ctx)
    local areas = zoneTotals(ctx)
    return areas and count(areas, function(t) return t.steps > 0 end) or nil
end

M.zones = function(ctx) local e = explorer(ctx) return e and e.visited or nil end
M.capitals = function(ctx)
    local e = explorer(ctx)
    if not e then return nil end
    local n = 0
    for _, r in ipairs(e.regions) do
        for _, z in ipairs(r.zones) do
            if z.visited and ns.ZoneCatalog.CAPITALS[z.area] then n = n + 1 end
        end
    end
    return n
end
local function regionComplete(id)
    return function(ctx)
        local r = region(ctx, id)
        if not r then return nil end
        return r.total > 0 and r.visited >= r.total and 1 or 0
    end
end
M.east_complete = regionComplete("EK")
M.kalimdor_complete = regionComplete("KALIMDOR")
M.world_complete = function(ctx)
    local e = explorer(ctx)
    if not e then return nil end
    return e.visited >= e.total and 1 or 0
end
M.main_continents = function(ctx)
    if not explorer(ctx) then return nil end
    local n = 0
    for _, id in ipairs({ "EK", "KALIMDOR" }) do
        local r = region(ctx, id)
        if r and r.visited > 0 then n = n + 1 end
    end
    return n
end
M.visits = function(ctx)
    local areas = zoneTotals(ctx)
    if not areas then return nil end
    local n = 0
    for _, t in pairs(areas) do n = n + t.visits end
    return n
end
M.revisit_zones = function(ctx)
    local areas = zoneTotals(ctx)
    return areas and count(areas, function(t) return t.visits >= 2 end) or nil
end
M.max_zone_visits = function(ctx)
    local areas = zoneTotals(ctx)
    if not areas then return nil end
    local best = 0
    for _, t in pairs(areas) do best = math.max(best, t.visits) end
    return best
end

M.active_seconds = function(ctx) return math.floor(ctx.character.playtime and ctx.character.playtime.total or 0) end
M.active_days = function(ctx)
    return count(ctx.character.playtime and ctx.character.playtime.days,
        function(v) return type(v) == "number" and v >= Achievements.ACTIVE_DAY end)
end
M.sessions = function(ctx) return ctx.character.playtime and ctx.character.playtime.sessions or 0 end
M.elapsed_days = function(ctx)
    local started = ctx.character.journey and ctx.character.journey.started
    if type(started) ~= "number" then return nil end
    return math.max(0, math.floor((ctx.now - started) / 86400))
end

M.level_cap = function(ctx)
    local p = progressOf(ctx)
    if p and p.levelCap then return 1 end
    if ctx.character == ns.character then
        local level, cap = API.PlayerLevel(), API.MaxLevel()
        if level and cap then return level >= cap and 1 or 0 end
    end
    return p and 0 or nil
end
M.rare_loot = firstSeen("FIRST_RARE")
M.epic_loot = firstSeen("FIRST_EPIC")
M.legendary_loot = firstSeen("FIRST_LEGENDARY")
M.duel_wins = firstSeen("FIRST_DUEL")
M.guild_join = function(ctx)
    local g = ctx.character.guild
    if type(g) == "string" and g ~= "" then return 1 end
    local j = ctx.character.journey
    for _, e in ipairs(j and j.events or {}) do
        if e.kind == "GUILD" then return 1 end
    end
    return g == false and 0 or nil
end

M.max_gold_copper = function(ctx) local p = progressOf(ctx) return p and p.maxMoney or nil end
M.quests = function(ctx) local p = progressOf(ctx) return p and p.quests or nil end
M.exalted_factions = function(ctx) local p = progressOf(ctx) return p and p.exalted and count(p.exalted) or nil end
M.professions_learned = function(ctx) local p = progressOf(ctx) return p and p.professions and count(p.professions) or nil end
M.professions_max = function(ctx) local p = progressOf(ctx) return p and p.professionsMax and count(p.professionsMax) or nil end

-- Two confirmed shots in the same catalog zone on the same month-day of
-- neighbouring years (29 February only when it really matches).
M.anniversary_zone_shot = function(ctx)
    if not explorer(ctx) then return nil end
    local seen = {}
    for _, r in ipairs(ctx.character.shots or {}) do
        local area = ns.ZoneCatalog.AreaOfName(r.zone)
        if area and type(r.t) == "number" then
            local d = date("*t", r.t)
            seen[string.format("%d:%02d-%02d:%d", area, d.month, d.day, d.year)] = true
        end
    end
    for key in pairs(seen) do
        local area, md, year = string.match(key, "^(%d+):(%d%d%-%d%d):(%d+)$")
        if seen[string.format("%s:%s:%d", area, md, tonumber(year) - 1)] then
            return 1
        end
    end
    return 0
end

-- Account (local SavedVariables of this game account, not Battle.net).
local function hasHistory(c)
    return type(c) == "table" and ((c.shotsTotal or 0) > 0
        or (c.steps and (c.steps.total or 0) > 0)
        or (c.playtime and (c.playtime.total or 0) >= Achievements.ACTIVE_DAY)
        or next(c.visited or {}) ~= nil)
end
Achievements.HasHistory = hasHistory

-- v0.18.0: trackers. A missing client source = unknown (nil), never 0.
local function tracks(ctx, source)
    local t = ctx.character.tracks
    if type(t) ~= "table" then
        return nil
    end
    if source and ns.Trackers and ctx.character == ns.character and not ns.Trackers.Sources()[source] then
        return nil
    end
    return t
end
local function flag(value) return value and 1 or 0 end
M.taxi_completed = function(ctx) local t = tracks(ctx, "taxi") return t and t.taxi or nil end
M.ground_mount_seen = function(ctx) local t = tracks(ctx, "mount") return t and flag(t.mount) or nil end
M.party_joins = function(ctx) local t = tracks(ctx, "group") return t and t.partyJoins or nil end
M.raid_joins = function(ctx) local t = tracks(ctx, "group") return t and t.raidJoins or nil end
M.party_days = function(ctx) local t = tracks(ctx, "group") return t and count(t.groupDays) or nil end
M.guild_days = function(ctx) local t = tracks(ctx, "guild") return t and count(t.guildDays) or nil end
M.boss_kills = function(ctx) local t = tracks(ctx) return t and t.bosses or nil end
M.unique_bosses = function(ctx) local t = tracks(ctx) return t and count(t.bossIDs) or nil end
M.duskwood_night = function(ctx) local t = tracks(ctx, "gameTime") return t and flag(t.duskwoodNight) or nil end
M.home_after_cap = function(ctx)
    local p = progressOf(ctx)
    local race = p and p.race
    if not race or not (ns.Trackers and ns.Trackers.START_ZONE[race]) then
        return nil -- a race without a known starting zone
    end
    local t = tracks(ctx)
    return t and flag(t.homeAfterCap) or nil
end
-- The first main zone recorded for this character, entered again on
-- another day (or a second visit counted by Location Analytics).
M.first_zone_revisited = function(ctx)
    local c = ctx.character
    local firstKey, firstAt
    for key, at in pairs(type(c.visitedAt) == "table" and c.visitedAt or {}) do
        if type(at) == "number" and ns.ZoneCatalog.AreaOfKey(c, key) and (not firstAt or at < firstAt) then
            firstKey, firstAt = key, at
        end
    end
    if not firstKey then
        return nil
    end
    local days = 0
    local log = type(c.locations) == "table" and type(c.locations.days) == "table" and c.locations.days or {}
    for _, entries in pairs(log) do
        if type(entries) == "table" and entries[firstKey] then
            days = days + 1
        end
    end
    if days >= 2 then
        return 1
    end
    local areas = zoneTotals(ctx)
    local area = ns.ZoneCatalog.AreaOfKey(c, firstKey)
    return (areas and area and areas[area] and areas[area].visits >= 2) and 1 or 0
end

local A = {}
Achievements.ACCOUNT_METRICS = A
A.account_characters = function(ctx) return count(ctx.db.characters, hasHistory) end
A.account_shots = function(ctx)
    local n = 0
    for _, c in pairs(ctx.db.characters) do n = n + (c.shotsTotal or 0) end
    return n
end
A.account_steps = function(ctx)
    local n = 0
    for _, c in pairs(ctx.db.characters) do n = n + math.floor(c.steps and c.steps.total or 0) end
    return n
end
A.account_factions = function(ctx)
    local factions = {}
    for _, c in pairs(ctx.db.characters) do
        if hasHistory(c) and type(c.progress) == "table" and c.progress.faction then
            factions[c.progress.faction] = true
        end
    end
    return count(factions)
end
A.account_world_complete = function()
    local catalog = ns.ZoneCatalog.Resolve()
    if catalog.status == "unavailable" or catalog.found == 0 then return nil end
    local union = {}
    for _, c in pairs(ns.db.characters) do
        for area in pairs(ns.ZoneCatalog.VisitedAreas(c)) do union[area] = true end
    end
    local total, have = 0, 0
    for _, region in ipairs(catalog.regions) do
        for _, z in ipairs(region.zones) do
            total = total + 1
            if union[z.area] then have = have + 1 end
        end
    end
    return total > 0 and have >= total and 1 or 0
end

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
local function newContext(character)
    return { character = character, db = ns.db, now = API.Time(), cache = {} }
end

-- value, state for one definition (without the stored unlock).
local function evaluate(def, ctx)
    if Achievements.UNAVAILABLE[def.metric] then
        return nil, "unavailable"
    end
    if Achievements.PENDING[def.metric] then
        return nil, "pending"
    end
    local adapter = def.scope == "account" and A[def.metric] or M[def.metric]
    if not adapter then
        return nil, "unknown"
    end
    local ok, value = pcall(adapter, ctx)
    if not ok then
        ns.Logger.Error("achievement metric " .. def.metric .. ": " .. tostring(value))
        return nil, "unknown"
    end
    if type(value) ~= "number" then
        return nil, "unknown"
    end
    return value, value >= def.target and "reached" or "progress"
end
Achievements.Evaluate = evaluate

local function store(owner)
    local a = owner.achievements
    if type(a) ~= "table" then
        a = { seeded = false, unlocked = {} }
        owner.achievements = a
    end
    if type(a.unlocked) ~= "table" then
        a.unlocked = {}
    end
    return a
end

-- Unlocks what is reached for one scope; returns newly unlocked defs.
local function checkScope(scope, owner, ctx)
    local a = store(owner)
    local fresh = {}
    for _, def in ipairs(Achievements.CATALOG.list) do
        if def.scope == scope and not a.unlocked[def.id] then
            local _, state = evaluate(def, ctx)
            if state == "reached" then
                local live = a.seeded
                a.unlocked[def.id] = {
                    at = live and ctx.now or nil, seen = ctx.now, src = live and "live" or "seed",
                    cat = Achievements.CATALOG.version, cond = 1,
                }
                ns.Logger.Info("Achievement: " .. def.id .. (live and "" or " (already reached)"))
                Achievements.MovePin(def, a.unlocked)
                if live then
                    fresh[#fresh + 1] = def
                end
            end
        end
    end
    a.seeded = true
    return fresh
end

-- Checks the logged-in character and the account. Read-only sessions
-- (incompatible or unsafe saved data) never store anything.
function Achievements.Check()
    local character = ns.character
    if not character or character ~= ns.db.characters[ns.characterKey] or ns.readOnly then
        return {}
    end
    -- v0.18.0: round numbers for the Chronicle, on the same throttle.
    if ns.Journey and ns.Journey.CheckMilestones then
        ns.SafeCall("milestones", ns.Journey.CheckMilestones)
    end
    local ctx = newContext(character)
    local fresh = checkScope("character", character, ctx)
    for _, def in ipairs(checkScope("account", ns.db.account, ctx)) do
        fresh[#fresh + 1] = def
    end
    if #fresh > 0 then
        for i = 1, #Achievements.listeners do
            ns.SafeCall("achievement listener", Achievements.listeners[i], fresh)
        end
    end
    return fresh
end

-- Text of a definition in the active language.
function Achievements.Text(def, field)
    local t = def[field]
    if type(t) ~= "table" then
        return nil
    end
    return t[ns.activeLocaleCode] or t.enUS
end

-- Every achievement with its state for the current (or viewed) character:
--   { def, value, target, state, done, at, reason, secret }
-- `scope` = "character" (default) or "account".
function Achievements.Get(scope)
    scope = scope or "character"
    local character = ns.character
    if not character then
        return {}
    end
    local owner = scope == "account" and ns.db.account or character
    local unlocked = type(owner.achievements) == "table" and type(owner.achievements.unlocked) == "table"
        and owner.achievements.unlocked or {}
    local ctx = newContext(character)
    local list = {}
    for _, def in ipairs(Achievements.CATALOG.list) do
        if def.scope == scope then
            local value, state = evaluate(def, ctx)
            local u = unlocked[def.id]
            if u then
                state = "done"
            elseif state == "reached" then
                state = "done" -- viewing another character: reached = earned
            end
            list[#list + 1] = {
                def = def, value = value, target = def.target, state = state,
                done = state == "done", at = u and u.at or nil,
                reason = state == "unavailable" and Achievements.UNAVAILABLE[def.metric] or nil,
                secret = def.hidden and state ~= "done",
            }
        end
    end
    return list
end

-- Counts for headers: { done, total } of a scope.
-- Earned / all, and (v1.0.0-beta.7) earned / available: an achievement
-- Forever cannot track does not count as available unless it was earned.
function Achievements.Summary(scope, list)
    local done, total, availableDone, available = 0, 0, 0, 0
    for _, a in ipairs(list or Achievements.Get(scope)) do
        total = total + 1
        if a.done then done = done + 1 end
        if a.done or a.state ~= "unavailable" then
            available = available + 1
            if a.done then availableDone = availableDone + 1 end
        end
    end
    return done, total, availableDone, available
end

---------------------------------------------------------------------------
-- Cards (v1.0.0-beta.18): the page shows one card per chain.
--   { key, category, steps = { a, ... }, current = a, earned = n,
--     complete = bool, last = a or nil }
-- `current` is the first step not earned yet (the goal now); when every
-- step is earned it is the last step. `last` is the highest earned step.
-- `list` is the result of Achievements.Get (same order as the catalog).
---------------------------------------------------------------------------
function Achievements.Cards(list)
    local cards, byChain = {}, {}
    for _, a in ipairs(list or {}) do
        local chain = a.def.chain
        local card = chain and byChain[chain]
        if not card then
            card = { key = chain or a.def.id, category = a.def.category, steps = {}, earned = 0 }
            cards[#cards + 1] = card
            if chain then
                byChain[chain] = card
            end
        end
        card.steps[#card.steps + 1] = a
        if a.done then
            card.earned = card.earned + 1
            card.last = a
        elseif not card.current then
            card.current = a
        end
    end
    for _, card in ipairs(cards) do
        card.complete = card.current == nil
        card.current = card.current or card.steps[#card.steps]
    end
    return cards
end

-- Earned / total steps by category and by rarity, for the dashboard:
--   { done, total, categories = { [cat] = { done, total } },
--     rarities = { [rarity] = { done, total } } }
function Achievements.Breakdown(list)
    local result = { done = 0, total = 0, categories = {}, rarities = {} }
    local function add(map, key, done)
        local entry = map[key]
        if not entry then
            entry = { done = 0, total = 0 }
            map[key] = entry
        end
        entry.total = entry.total + 1
        if done then entry.done = entry.done + 1 end
    end
    for _, a in ipairs(list or {}) do
        result.total = result.total + 1
        if a.done then result.done = result.done + 1 end
        add(result.categories, a.def.category, a.done)
        add(result.rarities, a.def.rarity, a.done)
    end
    return result
end

---------------------------------------------------------------------------
-- Goals on Home (v0.16.0): up to three pinned achievements, the rest of
-- the three places go to the nearest ones (highest share of the target).
-- Pins are kept in ns.db.ui.pins = { id, ... } for the whole account; a
-- secret, earned or unavailable achievement cannot be pinned.
---------------------------------------------------------------------------
Achievements.MAX_PINS = 3

local function pins()
    local ui = ns.db.ui
    if type(ui.pins) ~= "table" then
        ui.pins = {}
    end
    return ui.pins
end
Achievements.Pins = pins

function Achievements.IsPinned(id)
    for _, pinned in ipairs(pins()) do
        if pinned == id then
            return true
        end
    end
    return false
end

function Achievements.CanPin(a)
    return a ~= nil and not a.done and not a.secret and a.state ~= "unavailable"
end

-- Pins or unpins; returns the new state, or nil when three are pinned.
function Achievements.TogglePin(id)
    local list = pins()
    for i, pinned in ipairs(list) do
        if pinned == id then
            table.remove(list, i)
            return false
        end
    end
    if #list >= Achievements.MAX_PINS then
        return nil
    end
    list[#list + 1] = id
    return true
end

-- v1.0.0-beta.18: when a pinned step is earned, the pin moves to the next
-- step of its chain that is not earned yet (`unlocked` = the owner's
-- unlocked map). A lone achievement or the last step just drops its pin.
function Achievements.MovePin(def, unlocked)
    if not def.chain or not (ns.db and ns.db.ui) then
        return
    end
    local list = pins()
    for i, pinned in ipairs(list) do
        if pinned == def.id then
            for _, step in ipairs(Achievements.CHAINS[def.chain]) do
                if not unlocked[step.id] and step.id ~= def.id and not Achievements.IsPinned(step.id) then
                    list[i] = step.id
                    return
                end
            end
            return
        end
    end
end

local function share(a)
    if type(a.value) == "number" and type(a.target) == "number" and a.target > 0 then
        return a.value / a.target
    end
    return nil
end

-- { { achievement = a, pinned = bool }, ... } for Home, at most `n`.
-- Pins of earned achievements drop out by themselves (never shown as goals).
function Achievements.Goals(n)
    n = n or Achievements.MAX_PINS
    -- v1.0.0-beta.18: only the current step of a chain is a goal (never
    -- "Photographer 37/100" and "Memory Keeper 37/500" side by side).
    local byId, all = {}, {}
    for _, scope in ipairs({ "character", "account" }) do
        for _, card in ipairs(Achievements.Cards(Achievements.Get(scope))) do
            for _, a in ipairs(card.steps) do
                byId[a.def.id] = a
            end
            all[#all + 1] = card.current
        end
    end
    local goals, used = {}, {}
    for _, id in ipairs(pins()) do
        local a = byId[id]
        if Achievements.CanPin(a) and #goals < n and not used[id] then
            goals[#goals + 1] = { achievement = a, pinned = true }
            used[id] = true
            if a.def.chain then
                used[a.def.chain] = true -- one goal per chain
            end
        end
    end
    local nearest = {}
    for _, a in ipairs(all) do
        if not used[a.def.id] and not (a.def.chain and used[a.def.chain]) and Achievements.CanPin(a) and a.state == "progress" and share(a) then
            nearest[#nearest + 1] = a
        end
    end
    table.sort(nearest, function(x, y)
        local sx, sy = share(x), share(y)
        if sx ~= sy then
            return sx > sy
        end
        return x.def.id < y.def.id
    end)
    for _, a in ipairs(nearest) do
        if #goals >= n then
            break
        end
        goals[#goals + 1] = { achievement = a, pinned = false }
    end
    return goals
end

-- Trackers report often (steps every second): checks are throttled to one
-- per THROTTLE seconds, the login check runs at once.
Achievements.THROTTLE = 5
local scheduled = false
local function check()
    if scheduled then
        return
    end
    scheduled = true
    API.After(Achievements.THROTTLE, function()
        scheduled = false
        Achievements.Check()
    end)
end

table.insert(ns.onLogin, function() Achievements.Check() end)
table.insert(Achievements.listeners, function(defs) ns.Notifications.OnAchievements(defs) end)
table.insert(Achievements.listeners, function(defs) ns.Journey.OnAchievements(defs) end)
table.insert(ns.History.listeners, check)
table.insert(ns.Steps.listeners, check)
table.insert(ns.Locations.listeners, check)
table.insert(ns.Progress.listeners, check)
table.insert(ns.Trackers.listeners, check)
