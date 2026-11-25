-- Core/Database.lua
-- Loads, migrates and validates ForeverMemoriesDB. Pure logic: no client
-- calls, so every rule here is covered by offline tests.
--
-- Schema 4 (v0.5.1; 3 had the same layout with 0.75 m steps):
--   schemaVersion = 4
--   settings   = account-wide settings (one set for every character)
--   ui         = { point = { point, relativePoint, x, y } }
--   counters   = { unattributed = n }  Print Screen etc., diagnostics only
--   characters = { ["Realm:Name"] = character }
--   legacy     = old journal records whose character is unknown (kept,
--                never shown and never given to a random character)
--
-- character = {
--   name, realm, class, guid,
--   shots = { { t, ev, zone, info, manual, id }, ... }  oldest first
--   shotsTotal, shotsByDay = { ["2026-11-24"] = n }, shotZones = { [zone] = true },
--   visited = { [zoneKey] = true }, zonesSeeded,
--   guild = name | false | nil (nil = unknown yet),
--   steps = { total = x, days = { ["2026-11-24"] = x }, since = t },
--   passive = { elapsed = seconds of active play, interval = minutes it
--               was counted for },  (v0.6.0; added by validation, no
--               migration needed)
--   playtime = { total = seconds, days = { ["2026-11-24"] = seconds } },
--   locations = { days = { ["2026-11-24"] = { [zoneKey] = { name, t, first, instance } } } },
--               (v0.8.0; both added by validation, no migration needed)
--   -- Schema 5 (v0.9.0):
--   visitedAt = { [zoneKey] = Unix time of the first registered visit },
--   playtime.sinceDay = first day the Playtime Tracker counted ("2026-11-24"),
--   playtime.sessions / playtime.longest = closed sessions and the longest
--               one (active seconds), playtime.session = { start, last, active },
--   journey = { started = t, events = { { t, kind, zone, info } }, firsts = { [kind] = t } }
--   -- v0.11.0 (no migration, created on first use):
--   -- v0.12.0: playtime.session also counts shots, steps, zones, newZones,
--   -- levels and ended (logout time); playtime.lastSession = the last
--   -- closed one; playtime.longestAt = start of the longest session.
--   -- 1.0.0-beta.16: playtime.played = { total = /played seconds, at = Unix
--   -- time } — the last /played, saved for History of other characters.
--   zoneStats = { since = t, current = { key, t },
--                 zones = { [zoneKey] = { time, steps, visits, last } } }
--   -- Schema 6 (v0.14.0): Hall of Memories, catalog 1.0.
--   achievements = { seeded, unlocked = { [id] = unlock }, legacy = { [oldId] = time | 0 } }
--   progress = see Modules/Progress.lua (created on first use)
-- }
-- account = { achievements = { seeded, unlocked = { [id] = unlock } } }  (schema 6)
-- unlock = { at = time | nil (date unknown), seen = time | nil (when the
--            addon noticed it), src = "live" | "seed" | "legacy",
--            cat = catalog version, cond = condition version }
-- migrations = { { from, to, at, before = totals, after = totals } }  last 10
--
-- Safety (v0.14.0): a migration runs on a copy; the copy is used only if
-- no total (characters, screenshots, steps, days, zones, achievements)
-- went down. A file from a NEWER version of the addon is never migrated
-- or rewritten: the addon runs read-only on an empty scratch table.
-- Unknown top-level fields are kept as they are.
local _, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA_VERSION = 6
Database.MAX_SHOTS = 5000 -- per character; counters are never trimmed
Database.MAX_JOURNEY = 500 -- per character; levels and firsts only, far below this

-- Settings: type, default and allowed values. Anything else is reset.
Database.SETTINGS = {
    enabled = { kind = "boolean", default = true },
    mode = { kind = "enum", default = "normal", values = { "normal", "clean" } },
    notifications = { kind = "boolean", default = true },
    sound = { kind = "boolean", default = false },
    minimap = { kind = "boolean", default = true },
    minimapAngle = { kind = "number", default = 200, min = 0, max = 360 },
    locale = { kind = "enum", default = "auto", values = { "auto", "enUS", "ruRU" } },
    scale = { kind = "number", default = 1, min = 0.7, max = 1.5 }, -- 70-150 % since v0.10.0
    -- Passive capture (v0.6.0): on/off and minutes of active play.
    passive = { kind = "boolean", default = true },
    passiveInterval = { kind = "enum", default = 30, values = { 15, 30, 45, 60 } },
    -- Settings / General (v0.10.0).
    rememberTab = { kind = "boolean", default = true },
    toastDuration = { kind = "enum", default = 5, values = { 3, 5, 10 } },
    -- Appearance (v0.15.0): Obsidian Journal fonts; off = the client's own.
    fonts = { kind = "boolean", default = true },
    -- Notifications (v0.17.0): three kinds, where, how large, merging.
    notifyMini = { kind = "boolean", default = true },      -- screenshot saved
    notifyDiscovery = { kind = "boolean", default = true }, -- new location, achievement
    notifyLegendary = { kind = "boolean", default = true }, -- epic / legendary moments
    notifyPosition = { kind = "enum", default = "top", values = { "top", "middle", "bottom" } },
    notifySize = { kind = "enum", default = "normal", values = { "small", "normal", "large" } },
    notifyMerge = { kind = "boolean", default = true },
    -- v0.18.0: zone illustrations of the optional ForeverMemories_ArtPack.
    artpack = { kind = "boolean", default = true },
    -- v1.0.0-beta.4: short decorative effects (the fade-in of notifications).
    animations = { kind = "boolean", default = true },
    -- v1.0.0-beta.6: seconds on screen for each kind (mini takes the old
    -- toastDuration, which is kept for older versions), and large cards
    -- waiting for the end of combat.
    durationMini = { kind = "enum", default = 5, values = { 3, 5, 10 } },
    durationDiscovery = { kind = "enum", default = 15, values = { 10, 15, 20 } },
    durationLegendary = { kind = "enum", default = 10, values = { 7, 10, 15 } },
    notifyCombatDefer = { kind = "boolean", default = true },
}

-- Settings on the Settings / General page: "Restore defaults" resets only
-- these (and the window position). Capture settings, statistics and
-- history are never touched by it.
Database.GENERAL_SETTINGS = { "locale", "scale", "minimap", "rememberTab", "notifications", "sound", "toastDuration" }
-- v0.17.0: Settings / Appearance and Settings / Notifications have their
-- own "Restore defaults"; each resets only its page.
-- v1.0.0-beta.4: language, minimap and last tab moved to Settings / General;
-- "Reset appearance" keeps them (and resets the window size and position).
Database.APPEARANCE_SETTINGS = { "scale", "fonts", "artpack", "animations" }
Database.NOTIFY_SETTINGS = { "notifications", "sound", "toastDuration", "durationMini", "durationDiscovery",
                             "durationLegendary", "notifyCombatDefer", "notifyMini", "notifyDiscovery",
                             "notifyLegendary", "notifyPosition", "notifySize", "notifyMerge" }

function Database.ResetKeys(db, keys)
    for _, key in ipairs(keys) do
        db.settings[key] = Database.SETTINGS[key].default
    end
end

-- v1.0.0-beta.6: own place and scale of each notification kind, set in
-- Settings / Notifications / Edit position.
--   ui.notify = { [kind] = { point, x, y, scale, locked } }
Database.NOTIFY_POINTS = { TOP = true, CENTER = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
function Database.ValidateNotifyLayout(ui, repaired)
    if ui.notify == nil then
        return
    end
    if type(ui.notify) ~= "table" then
        ui.notify = nil
        repaired[#repaired + 1] = "ui.notify"
        return
    end
    for kind, entry in pairs(ui.notify) do
        local ok = (kind == "mini" or kind == "discovery" or kind == "legendary") and type(entry) == "table"
            and Database.NOTIFY_POINTS[entry.point]
            and type(entry.x) == "number" and entry.x == entry.x and math.abs(entry.x) <= 4000
            and type(entry.y) == "number" and entry.y == entry.y and math.abs(entry.y) <= 4000
            and type(entry.scale) == "number" and entry.scale >= 0.5 and entry.scale <= 2
        if ok then
            entry.locked = entry.locked == true or nil
        else
            ui.notify[kind] = nil
            repaired[#repaired + 1] = "ui.notify." .. tostring(kind)
        end
    end
end

-- Settings / Data "Reset all settings" (v1.0.0-beta.4): every setting,
-- Auto capture and its event switches included, and the window size and
-- position. History, statistics and earned achievements are not touched.
function Database.ResetAllSettings(db)
    for key, spec in pairs(Database.SETTINGS) do
        db.settings[key] = spec.default
    end
    for _, id in ipairs(ns.Registry.EVENTS) do
        db.settings.events[id] = true
    end
    db.ui.point, db.ui.size = nil, nil
    db.ui.notify = nil -- own places of the notifications (v1.0.0-beta.6)
end

function Database.ResetGeneral(db)
    for _, key in ipairs(Database.GENERAL_SETTINGS) do
        db.settings[key] = Database.SETTINGS[key].default
    end
    db.ui.point, db.ui.size = nil, nil
end

local TOP_LEVEL = {
    schemaVersion = true, settings = true, ui = true, counters = true,
    characters = true, legacy = true, zoneDump = true, account = true, migrations = true,
}
Database.MAX_MIGRATION_REPORTS = 10

-- v0.13.0 achievement IDs -> catalog 1.0 IDs (same condition).
-- YEAR_OF_MEMORIES was "365 days with play", so it becomes
-- fm.anniversaries.active365 (not fm.anniversaries.year, whose English
-- title is the same but whose condition is 365 days since the start).
Database.LEGACY_ACHIEVEMENTS = {
    FIRST_MEMORY = "fm.memories.first", PHOTOGRAPHER = "fm.memories.photographer",
    MEMORY_KEEPER = "fm.memories.keeper", MASTER_PHOTOGRAPHER = "fm.memories.master",
    FIRST_STEPS = "fm.steps.first", WANDERER = "fm.steps.wanderer",
    TRAVELER = "fm.steps.traveler", ENDLESS_JOURNEY = "fm.steps.endless",
    EXPLORER = "fm.locations.explorer", EK_EXPLORER = "fm.locations.east",
    KALIMDOR_EXPLORER = "fm.locations.kalimdor", MASTER_OF_AZEROTH = "fm.locations.world",
    LIVING_HISTORY = "fm.anniversaries.active30", SEASON_OF_ADVENTURES = "fm.anniversaries.active90",
    YEAR_OF_MEMORIES = "fm.anniversaries.active365",
}
Database.CATALOG_VERSION = "1.0"

local function tableOf(parent, key, repaired, path)
    if type(parent[key]) ~= "table" then
        if parent[key] ~= nil then
            repaired[#repaired + 1] = path
        end
        parent[key] = {}
    end
    return parent[key]
end

local function newCharacter(key)
    local realm, name = string.match(tostring(key), "^(.-):(.+)$")
    return {
        name = name, realm = realm,
        shots = {}, shotsTotal = 0, shotsByDay = {}, shotZones = {},
        visited = {}, visitedAt = {},
        steps = { total = 0, days = {} },
        passive = { elapsed = 0 },
        playtime = { total = 0, days = {}, sessions = 0, longest = 0 },
        locations = { days = {} },
        journey = { events = {}, firsts = {} },
    }
end

-- Counts one confirmed shot in the character's statistics.
function Database.CountShot(character, record)
    character.shotsTotal = (character.shotsTotal or 0) + 1
    local day = ns.Util.DayKey(record.t)
    character.shotsByDay[day] = (character.shotsByDay[day] or 0) + 1
    if type(record.zone) == "string" and record.zone ~= "" then
        character.shotZones[record.zone] = true
    end
end

---------------------------------------------------------------------------
-- Migrations: MIGRATIONS[n] turns schema n into n + 1. Each runs once:
-- schemaVersion is raised right after it, so nothing is copied twice.
---------------------------------------------------------------------------

-- Old event types that are the same event now.
local RENAMED = { MAX_LEVEL = "LEVEL" }

-- Old journal entry -> new shot record (nil if no shot was saved).
local function convertEntry(entry)
    if type(entry) ~= "table" or type(entry.t) ~= "number"
        or type(entry.ok) ~= "number" or entry.ok <= 0 then
        return nil
    end
    local events = type(entry.events) == "table" and entry.events or {}
    local ev = events[1] or "MANUAL"
    ev = RENAMED[ev] or ev
    local info
    local key = type(entry.keys) == "table" and entry.keys[1]
    if ev == "LEVEL" and type(key) == "string" then
        info = tonumber(string.match(key, "^level:(%d+)$"))
    end
    return {
        t = entry.t, ev = ev, zone = entry.zone, info = info,
        manual = entry.manual or nil, id = entry.id,
    }
end

-- Old trigger ids that are one of the nine events now.
local KEPT_EVENTS = {
    LEVEL = "LEVEL", DEATH = "DEATH", BOSS = "BOSS", DUEL = "DUEL", LOOT_EPIC = "LOOT_EPIC",
    LOOT_LEGENDARY = "LOOT_LEGENDARY", ZONE = "ZONE", GUILD = "GUILD",
}

Database.MIGRATIONS = {
    [1] = function(db)
        -- v0.0.1 spike data is not needed any more.
        db.spike = nil
    end,

    -- 0.4.2-beta -> 0.5.0: profiles become one set of account settings,
    -- the shared journal becomes per-character history.
    [2] = function(db)
        local old = type(db.settings) == "table" and db.settings or {}
        local settings = {}
        for _, key in ipairs({ "enabled", "locale", "notifications", "sound", "minimap", "minimapAngle" }) do
            settings[key] = old[key]
        end
        if type(old.scale) == "number" then
            settings.scale = ns.Util.Clamp(old.scale, Database.SETTINGS.scale.min, Database.SETTINGS.scale.max, 1)
        end

        -- Only switches the player changed on purpose (a custom profile)
        -- are carried over; preset defaults give way to the new defaults.
        settings.events = {}
        local profiles = type(db.profiles) == "table" and db.profiles or {}
        local active = profiles[old.defaultProfile]
        if type(active) == "table" and type(active.rules) == "table" then
            for oldId, newId in pairs(KEPT_EVENTS) do
                local rule = active.rules[oldId]
                if type(rule) == "table" and type(rule.enabled) == "boolean" then
                    settings.events[newId] = rule.enabled
                end
            end
        end
        db.settings = settings

        -- Characters keep the zones they visited.
        local characters = {}
        if type(db.characters) == "table" then
            for key, oldChar in pairs(db.characters) do
                if type(key) == "string" and type(oldChar) == "table" then
                    local character = newCharacter(key)
                    if type(oldChar.visited) == "table" then
                        character.visited = oldChar.visited
                    end
                    character.zonesSeeded = oldChar.zonesSeeded or nil
                    characters[key] = character
                end
            end
        end
        db.characters = characters

        -- Journal: confirmed shots go to the character recorded in them.
        local legacy = {}
        if type(db.journal) == "table" then
            for _, entry in ipairs(db.journal) do
                local record = convertEntry(entry)
                if record then
                    local key = entry.char
                    if type(key) == "string" and string.find(key, ":", 1, true) then
                        characters[key] = characters[key] or newCharacter(key)
                        local character = characters[key]
                        character.shots[#character.shots + 1] = record
                        Database.CountShot(character, record)
                    else
                        legacy[#legacy + 1] = record
                    end
                end
            end
        end
        db.legacy = #legacy > 0 and legacy or nil

        db.profiles, db.journal, db.nextJournalId = nil, nil, nil
    end,

    -- 0.5.0 -> 0.5.1: one step is 1.5 m instead of 0.75 m. Steps already
    -- counted are converted, so old and new days are comparable.
    [3] = function(db)
        if type(db.characters) ~= "table" then
            return
        end
        local factor = 0.75 / 1.5
        for _, character in pairs(db.characters) do
            local steps = type(character) == "table" and character.steps
            if type(steps) == "table" then
                if type(steps.total) == "number" then
                    steps.total = steps.total * factor
                end
                if type(steps.days) == "table" then
                    for day, value in pairs(steps.days) do
                        if type(value) == "number" then
                            steps.days[day] = value * factor
                        end
                    end
                end
            end
        end
    end,

    -- 0.8.x -> 0.9.0: adventure diary. Only facts already in the data are
    -- used: nothing gets a date it did not have.
    [4] = function(db)
        if type(db.characters) ~= "table" then
            return
        end
        for _, character in pairs(db.characters) do
            if type(character) == "table" then
                Database.UpgradeCharacter(character)
            end
        end
    end,

    -- 0.13.0 -> 0.14.0: Hall of Memories. Earned achievements keep their
    -- date (or stay "date unknown"); nothing is earned or lost here.
    [5] = function(db)
        if type(db.characters) ~= "table" then
            return
        end
        for _, character in pairs(db.characters) do
            if type(character) == "table" then
                Database.UpgradeAchievements(character)
            end
        end
    end,
}

-- v0.13.0 achievements -> schema 6. Idempotent: running it twice changes
-- nothing; an unlock already present is never overwritten.
function Database.UpgradeAchievements(character)
    local a = character.achievements
    if type(a) ~= "table" then
        return
    end
    if type(a.unlocked) ~= "table" then
        a.unlocked = {}
    end
    if type(a.done) == "table" then
        a.legacy = type(a.legacy) == "table" and a.legacy or {}
        for oldId, at in pairs(a.done) do
            local id = Database.LEGACY_ACHIEVEMENTS[oldId]
            local known = type(at) == "number" and at > 0 and at or nil
            if id and not a.unlocked[id] then
                a.unlocked[id] = { at = known, seen = known, src = "legacy", cat = Database.CATALOG_VERSION, cond = 1 }
            end
            a.legacy[oldId] = at
        end
        a.done = nil
    end
end

-- Totals that a migration must never lower.
function Database.Totals(db)
    local t = { characters = 0, shots = 0, steps = 0, days = 0, zones = 0, achievements = 0 }
    if type(db) ~= "table" or type(db.characters) ~= "table" then
        return t
    end
    local days = {}
    for _, c in pairs(db.characters) do
        if type(c) == "table" then
            t.characters = t.characters + 1
            t.shots = t.shots + (type(c.shotsTotal) == "number" and c.shotsTotal or 0)
            local steps = type(c.steps) == "table" and c.steps or {}
            t.steps = t.steps + math.floor(type(steps.total) == "number" and steps.total or 0)
            for _, map in ipairs({ type(c.playtime) == "table" and c.playtime.days, steps.days, c.shotsByDay }) do
                if type(map) == "table" then
                    for day, value in pairs(map) do
                        if type(value) == "number" and value > 0 then
                            days[day] = true
                        end
                    end
                end
            end
            for _ in pairs(type(c.visited) == "table" and c.visited or {}) do
                t.zones = t.zones + 1
            end
            local a = type(c.achievements) == "table" and c.achievements or {}
            local earned = {}
            for _, old in pairs({ a.done or false, a.legacy or false }) do
                for id in pairs(type(old) == "table" and old or {}) do
                    earned[Database.LEGACY_ACHIEVEMENTS[id] or id] = true
                end
            end
            for id in pairs(type(a.unlocked) == "table" and a.unlocked or {}) do
                earned[id] = true
            end
            for _ in pairs(earned) do
                t.achievements = t.achievements + 1
            end
        end
    end
    for _ in pairs(days) do
        t.days = t.days + 1
    end
    return t
end

-- Names of the totals that went down from `before` to `after`.
function Database.Lost(before, after)
    local lost = {}
    for key, value in pairs(before) do
        if (after[key] or 0) < value then
            lost[#lost + 1] = key
        end
    end
    table.sort(lost)
    return lost
end

function Database.Copy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[Database.Copy(k)] = Database.Copy(v)
    end
    return copy
end

-- Journey kinds that come from older shot records (real dates).
local JOURNEY_FROM_SHOT = {
    LOOT_RARE = "FIRST_RARE", LOOT_EPIC = "FIRST_EPIC", LOOT_LEGENDARY = "FIRST_LEGENDARY",
    DUEL = "FIRST_DUEL", GUILD = "GUILD",
}
Database.FIRST_KINDS = {
    FIRST_DUNGEON_BOSS = true, FIRST_RAID_BOSS = true, FIRST_RARE = true, FIRST_EPIC = true,
    FIRST_LEGENDARY = true, FIRST_DUEL = true, MAX_LEVEL = true,
}

-- Schema 4 -> 5 for one character (also safe on partial data).
function Database.UpgradeCharacter(character)
    local earliest
    local function seen(t)
        if type(t) == "number" and (not earliest or t < earliest) then
            earliest = t
        end
    end

    -- First registered visit of each zone: the earliest day-log entry.
    local visitedAt = type(character.visitedAt) == "table" and character.visitedAt or {}
    local logs = type(character.locations) == "table" and type(character.locations.days) == "table"
        and character.locations.days or {}
    for _, zones in pairs(logs) do
        if type(zones) == "table" then
            for key, entry in pairs(zones) do
                if type(entry) == "table" and type(entry.t) == "number" then
                    seen(entry.t)
                    if not visitedAt[key] or entry.t < visitedAt[key] then
                        visitedAt[key] = entry.t
                    end
                end
            end
        end
    end
    character.visitedAt = visitedAt

    -- Playtime: the day it started counting; no sessions are known yet.
    local playtime = type(character.playtime) == "table" and character.playtime or nil
    if playtime and type(playtime.days) == "table" then
        local first
        for day in pairs(playtime.days) do
            if type(day) == "string" and (not first or day < first) then
                first = day
            end
        end
        playtime.sinceDay = playtime.sinceDay or first
        playtime.sessions = playtime.sessions or 0
        playtime.longest = playtime.longest or 0
    end

    -- Journey from shots that really happened (levels, first items,
    -- first duel win, guild joins). Bosses are skipped: an old shot does
    -- not say whether it was a dungeon or a raid.
    local journey = { events = {}, firsts = {} }
    local shots = type(character.shots) == "table" and character.shots or {}
    local levels = {}
    for _, record in ipairs(shots) do
        if type(record) == "table" and type(record.t) == "number" then
            seen(record.t)
            local kind
            if record.ev == "LEVEL" and type(record.info) == "number" and not levels[record.info] then
                levels[record.info] = true
                kind = "LEVEL"
            else
                kind = JOURNEY_FROM_SHOT[record.ev]
            end
            if kind and not (Database.FIRST_KINDS[kind] and journey.firsts[kind]) then
                if Database.FIRST_KINDS[kind] then
                    journey.firsts[kind] = record.t
                end
                journey.events[#journey.events + 1] = {
                    t = record.t, kind = kind, zone = record.zone, info = record.info,
                }
            end
        end
    end
    if type(character.steps) == "table" then
        seen(character.steps.since)
    end
    journey.started = earliest -- nil: set at the next login (nothing known before)
    local old = character.journey
    if type(old) ~= "table" or ((type(old.events) ~= "table" or #old.events == 0) and not old.started) then
        character.journey = journey
    end
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------
local function validSetting(spec, value)
    if spec.kind == "enum" then
        for _, allowed in ipairs(spec.values) do
            if value == allowed then
                return true
            end
        end
        return false
    end
    if type(value) ~= spec.kind then
        return false
    end
    if spec.kind == "number" then
        return value == value and value >= spec.min and value <= spec.max
    end
    return true
end

local function validateSettings(db, repaired)
    local settings = tableOf(db, "settings", repaired, "settings")
    for key, value in pairs(settings) do
        if key ~= "events" then
            local spec = Database.SETTINGS[key]
            if not spec or not validSetting(spec, value) then
                settings[key] = nil
                repaired[#repaired + 1] = "settings." .. tostring(key)
            end
        end
    end
    -- v1.0.0-beta.6: the mini card keeps the duration chosen before.
    if settings.durationMini == nil and validSetting(Database.SETTINGS.durationMini, settings.toastDuration) then
        settings.durationMini = settings.toastDuration
    end
    for key, spec in pairs(Database.SETTINGS) do
        if settings[key] == nil then
            settings[key] = spec.default
        end
    end
    -- Events: every approved event has a switch, on by default.
    local events = tableOf(settings, "events", repaired, "settings.events")
    for key, value in pairs(events) do
        if not ns.Util.Contains(ns.Registry.EVENTS, key) or type(value) ~= "boolean" then
            events[key] = nil
            repaired[#repaired + 1] = "settings.events." .. tostring(key)
        end
    end
    for _, id in ipairs(ns.Registry.EVENTS) do
        if events[id] == nil then
            events[id] = true
        end
    end
end

local function number(value)
    return type(value) == "number" and value == value and value >= 0
end

local function validateCharacter(character, path, repaired)
    tableOf(character, "visited", repaired, path .. ".visited")
    tableOf(character, "shotsByDay", repaired, path .. ".shotsByDay")
    tableOf(character, "shotZones", repaired, path .. ".shotZones")
    local shots = tableOf(character, "shots", repaired, path .. ".shots")
    local clean = {}
    for i = 1, #shots do
        local record = shots[i]
        if type(record) == "table" and type(record.t) == "number" and type(record.ev) == "string" then
            clean[#clean + 1] = record
        else
            repaired[#repaired + 1] = path .. ".shots[" .. i .. "]"
        end
    end
    while #clean > Database.MAX_SHOTS do
        table.remove(clean, 1)
    end
    character.shots = clean
    if not number(character.shotsTotal) then
        character.shotsTotal = #clean
    end
    for key, value in pairs(character.shotsByDay) do
        if type(key) ~= "string" or not number(value) then
            character.shotsByDay[key] = nil
        end
    end
    local steps = tableOf(character, "steps", repaired, path .. ".steps")
    if not number(steps.total) then
        steps.total = 0
    end
    local days = tableOf(steps, "days", repaired, path .. ".steps.days")
    for key, value in pairs(days) do
        if type(key) ~= "string" or not number(value) then
            days[key] = nil
            repaired[#repaired + 1] = path .. ".steps.days." .. tostring(key)
        end
    end
    local passive = tableOf(character, "passive", repaired, path .. ".passive")
    if not number(passive.elapsed) or passive.elapsed > 3600 then
        passive.elapsed = 0
    end
    if type(passive.interval) ~= "number" then
        passive.interval = nil -- the timer sets it and starts from zero
    end
    local playtime = tableOf(character, "playtime", repaired, path .. ".playtime")
    if not number(playtime.total) then
        playtime.total = 0
    end
    if not number(playtime.sessions) then
        playtime.sessions = 0
    end
    if not number(playtime.longest) then
        playtime.longest = 0
    end
    if type(playtime.sinceDay) ~= "string" then
        playtime.sinceDay = nil
    end
    local session = playtime.session
    if session ~= nil and (type(session) ~= "table" or not number(session.start)
        or not number(session.last) or not number(session.active)) then
        playtime.session = nil
        repaired[#repaired + 1] = path .. ".playtime.session"
    end
    if playtime.session then
        local s = playtime.session
        for _, field in ipairs({ "shots", "steps", "newZones", "levels", "ended" }) do
            if s[field] ~= nil and not number(s[field]) then
                s[field] = nil
            end
        end
        if s.zones ~= nil and type(s.zones) ~= "table" then
            s.zones = nil
        end
    end
    if playtime.longestAt ~= nil and not number(playtime.longestAt) then
        playtime.longestAt = nil
    end
    local saved = playtime.played
    if saved ~= nil and (type(saved) ~= "table" or not number(saved.total) or not number(saved.at)) then
        playtime.played = nil
        repaired[#repaired + 1] = path .. ".playtime.played"
    end
    local last = playtime.lastSession
    if last ~= nil and (type(last) ~= "table" or not number(last.start) or not number(last.finish)
        or not number(last.active)) then
        playtime.lastSession = nil
        repaired[#repaired + 1] = path .. ".playtime.lastSession"
    end
    local played = tableOf(playtime, "days", repaired, path .. ".playtime.days")
    for key, value in pairs(played) do
        if type(key) ~= "string" or not number(value) then
            played[key] = nil
            repaired[#repaired + 1] = path .. ".playtime.days." .. tostring(key)
        end
    end
    local locations = tableOf(character, "locations", repaired, path .. ".locations")
    local visits = tableOf(locations, "days", repaired, path .. ".locations.days")
    for day, zones in pairs(visits) do
        if type(day) ~= "string" or type(zones) ~= "table" then
            visits[day] = nil
            repaired[#repaired + 1] = path .. ".locations.days." .. tostring(day)
        else
            for key, entry in pairs(zones) do
                if type(entry) ~= "table" or type(entry.t) ~= "number" or type(entry.name) ~= "string" then
                    zones[key] = nil
                    repaired[#repaired + 1] = path .. ".locations.days." .. day .. "." .. tostring(key)
                end
            end
        end
    end
end

-- Location Analytics (v0.11.0): added on first use, checked here.
local function validateZoneStats(character, path, repaired)
    local zs = character.zoneStats
    if zs == nil then
        return
    end
    if type(zs) ~= "table" or type(zs.zones) ~= "table" then
        character.zoneStats = nil
        repaired[#repaired + 1] = path .. ".zoneStats"
        return
    end
    if not number(zs.since) then
        zs.since = nil
    end
    if zs.current ~= nil and (type(zs.current) ~= "table" or type(zs.current.key) ~= "string"
        or not number(zs.current.t)) then
        zs.current = nil
    end
    for key, entry in pairs(zs.zones) do
        if type(key) ~= "string" or type(entry) ~= "table" or not number(entry.time)
            or not number(entry.steps) or not number(entry.visits) then
            zs.zones[key] = nil
            repaired[#repaired + 1] = path .. ".zoneStats." .. tostring(key)
        elseif entry.last ~= nil and not number(entry.last) then
            entry.last = nil
        end
    end
end

-- Hall of Memories (schema 6): { seeded, unlocked = { [id] = unlock }, legacy }.
-- An unlock whose ID is not in this catalog is KEPT (a newer catalog may
-- know it); only malformed entries are dropped.
local function validateUnlocks(a, path, repaired)
    a.seeded = a.seeded == true
    if type(a.unlocked) ~= "table" then
        if a.unlocked ~= nil then
            repaired[#repaired + 1] = path .. ".unlocked"
        end
        a.unlocked = {}
    end
    for id, u in pairs(a.unlocked) do
        if type(id) ~= "string" or type(u) ~= "table" then
            a.unlocked[id] = nil
            repaired[#repaired + 1] = path .. ".unlocked." .. tostring(id)
        else
            if u.at ~= nil and not number(u.at) then u.at = nil end
            if u.seen ~= nil and not number(u.seen) then u.seen = nil end
            if u.src ~= "live" and u.src ~= "seed" and u.src ~= "legacy" then u.src = "seed" end
            if type(u.cat) ~= "string" then u.cat = Database.CATALOG_VERSION end
            if not number(u.cond) then u.cond = 1 end
        end
    end
    if a.legacy ~= nil and type(a.legacy) ~= "table" then
        a.legacy = nil
    end
end
Database.ValidateUnlocks = validateUnlocks

local function validateAchievements(character, path, repaired)
    local a = character.achievements
    if a == nil then
        return
    end
    if type(a) ~= "table" then
        character.achievements = nil
        repaired[#repaired + 1] = path .. ".achievements"
        return
    end
    Database.UpgradeAchievements(character) -- a v0.13 table restored from a backup
    validateUnlocks(a, path .. ".achievements", repaired)
end

local function validateProgress(character, path, repaired)
    local p = character.progress
    if p == nil then
        return
    end
    if type(p) ~= "table" then
        character.progress = nil
        repaired[#repaired + 1] = path .. ".progress"
        return
    end
    for _, key in ipairs({ "maxMoney", "quests", "level" }) do
        if p[key] ~= nil and not number(p[key]) then
            p[key] = nil
        end
    end
    for _, key in ipairs({ "exalted", "professions", "professionsMax" }) do
        if p[key] ~= nil and type(p[key]) ~= "table" then
            p[key] = nil
        end
    end
    if p.faction ~= nil and p.faction ~= "Alliance" and p.faction ~= "Horde" then
        p.faction = nil
    end
    if p.race ~= nil and type(p.race) ~= "string" then
        p.race = nil
    end
    p.levelCap = p.levelCap == true or nil
end

local function validateJourney(character, path, repaired)
    local visitedAt = tableOf(character, "visitedAt", repaired, path .. ".visitedAt")
    for key, value in pairs(visitedAt) do
        if type(key) ~= "string" or not number(value) then
            visitedAt[key] = nil
        end
    end
    local journey = tableOf(character, "journey", repaired, path .. ".journey")
    if journey.started ~= nil and not number(journey.started) then
        journey.started = nil
    end
    tableOf(journey, "firsts", repaired, path .. ".journey.firsts")
    local events = tableOf(journey, "events", repaired, path .. ".journey.events")
    local clean = {}
    for i = 1, #events do
        local e = events[i]
        if type(e) == "table" and number(e.t) and type(e.kind) == "string" then
            clean[#clean + 1] = e
        else
            repaired[#repaired + 1] = path .. ".journey.events[" .. i .. "]"
        end
    end
    while #clean > Database.MAX_JOURNEY do
        table.remove(clean, 1)
    end
    journey.events = clean
end

local function validateCharacters(db, repaired)
    local characters = tableOf(db, "characters", repaired, "characters")
    for key, character in pairs(characters) do
        if type(key) ~= "string" or type(character) ~= "table" then
            characters[key] = nil
            repaired[#repaired + 1] = "characters." .. tostring(key)
        else
            validateCharacter(character, "characters." .. key, repaired)
            validateJourney(character, "characters." .. key, repaired)
            validateZoneStats(character, "characters." .. key, repaired)
            validateAchievements(character, "characters." .. key, repaired)
            validateProgress(character, "characters." .. key, repaired)
        end
    end
end

-- Brings a table to the current schema and validates it (in place).
local function upgrade(db, version, repaired)
    for v = version, Database.SCHEMA_VERSION - 1 do
        if Database.MIGRATIONS[v] then
            Database.MIGRATIONS[v](db)
        end
        db.schemaVersion = v + 1
    end
    db.schemaVersion = Database.SCHEMA_VERSION

    for key in pairs(db) do
        if not TOP_LEVEL[key] then
            -- Unknown field (a newer or older version, a hand edit): kept.
            repaired[#repaired + 1] = "kept unknown field " .. tostring(key)
        end
    end

    validateSettings(db, repaired)
    validateCharacters(db, repaired)
    local ui = tableOf(db, "ui", repaired, "ui")
    if ui.size ~= nil and (type(ui.size) ~= "table" or not number(ui.size[1]) or not number(ui.size[2])) then
        ui.size = nil
        repaired[#repaired + 1] = "ui.size"
    end
    -- v0.16.0: pinned achievements (IDs, at most three) and open groups
    -- of the Auto capture tab.
    if ui.pins ~= nil then
        local clean = {}
        if type(ui.pins) == "table" then
            for _, id in ipairs(ui.pins) do
                if type(id) == "string" and #clean < 3 then
                    clean[#clean + 1] = id
                end
            end
        end
        if type(ui.pins) ~= "table" or #clean ~= #ui.pins then
            repaired[#repaired + 1] = "ui.pins"
        end
        ui.pins = clean
    end
    if ui.captureOpen ~= nil and type(ui.captureOpen) ~= "table" then
        ui.captureOpen = nil
        repaired[#repaired + 1] = "ui.captureOpen"
    end
    Database.ValidateNotifyLayout(ui, repaired)
    tableOf(db, "counters", repaired, "counters")
    if type(db.counters.unattributed) ~= "number" then
        db.counters.unattributed = 0
    end
    if db.legacy ~= nil and type(db.legacy) ~= "table" then
        db.legacy = nil
    end
    if db.zoneDump ~= nil and type(db.zoneDump) ~= "table" then
        db.zoneDump = nil
    end
    local account = tableOf(db, "account", repaired, "account")
    local a = tableOf(account, "achievements", repaired, "account.achievements")
    validateUnlocks(a, "account.achievements", repaired)
    if db.migrations ~= nil and type(db.migrations) ~= "table" then
        db.migrations = nil
    end
    return db
end

-- Takes whatever the client loaded and returns a valid table, the list of
-- paths that had to be reset, and a status:
--   { migrated = { from, to } | nil,
--     incompatible = schema | nil  (a newer addon wrote it: not touched),
--     unsafe = { lost totals } | nil (migration would lose data: not touched) }
-- With incompatible or unsafe, the returned table is a fresh scratch table
-- and `raw` is left exactly as it was: the caller must not save over it.
function Database.Load(raw)
    local repaired = {}
    local status = {}
    local db = raw
    if type(db) ~= "table" then
        if db ~= nil then
            repaired[#repaired + 1] = "ForeverMemoriesDB"
        end
        db = {}
    end

    local version = db.schemaVersion
    if type(version) ~= "number" then
        if db.spike ~= nil or version ~= nil then
            version = 1
            if db.schemaVersion ~= nil then
                repaired[#repaired + 1] = "schemaVersion"
            end
        else
            version = Database.SCHEMA_VERSION
        end
    end
    if version > Database.SCHEMA_VERSION then
        status.incompatible = version
        return upgrade({}, Database.SCHEMA_VERSION, {}), repaired, status
    end

    if version < Database.SCHEMA_VERSION and db == raw then
        -- Migrate a copy; keep it only if nothing was lost.
        local before = Database.Totals(raw)
        local copy = upgrade(Database.Copy(raw), version, repaired)
        local after = Database.Totals(copy)
        local lost = version >= 5 and Database.Lost(before, after) or {}
        if #lost > 0 then
            status.unsafe = lost
            return upgrade({}, Database.SCHEMA_VERSION, {}), repaired, status
        end
        status.migrated = { from = version, to = Database.SCHEMA_VERSION }
        copy.migrations = type(copy.migrations) == "table" and copy.migrations or {}
        table.insert(copy.migrations, { from = version, to = Database.SCHEMA_VERSION,
            at = type(time) == "function" and time() or nil, before = before, after = after })
        while #copy.migrations > Database.MAX_MIGRATION_REPORTS do
            table.remove(copy.migrations, 1)
        end
        return copy, repaired, status
    end
    return upgrade(db, version, repaired), repaired, status
end

-- Per-character storage, created on first use. Name, realm, class and
-- GUID are refreshed at every login.
function Database.Character(db, key, info)
    local character = db.characters[key]
    if not character then
        character = newCharacter(key)
        db.characters[key] = character
    end
    if info then
        character.name = info.name or character.name
        character.realm = info.realm or character.realm
        character.class = info.class or character.class
        if info.guid then
            if character.guid and character.guid ~= info.guid then
                -- Same name and realm, different GUID: recorded for
                -- diagnostics (see docs/TESTING.md), data is kept.
                character.guidChanged = true
            end
            character.guid = info.guid
        end
    end
    return character
end

---------------------------------------------------------------------------
-- Settings / Data (v0.10.0)
---------------------------------------------------------------------------

-- Removes the saved history of another character. Screenshot files on
-- disk are never touched (the addon cannot reach them).
function Database.DeleteCharacter(db, key)
    if type(key) ~= "string" or not db.characters[key] then
        return false
    end
    db.characters[key] = nil
    return true
end

-- Clears the history of a character in place (the table stays the same,
-- so modules holding it keep working). Name, realm, class and GUID stay;
-- tracking starts again at `now`.
function Database.ClearCharacter(character, key, now)
    local keep = {
        name = character.name, realm = character.realm, class = character.class,
        guid = character.guid, guild = character.guild,
    }
    for field in pairs(character) do
        character[field] = nil
    end
    for field, value in pairs(newCharacter(key)) do
        character[field] = value
    end
    for field, value in pairs(keep) do
        character[field] = value
    end
    character.zonesSeeded = true -- the current zone is not a "new zone" shot
    character.journey.started = now
    character.steps.since = now
    return character
end

-- Account totals for Settings / Data. Days are a union of the calendar
-- days with playtime, steps or screenshots of any character.
function Database.Storage(db)
    local result = { characters = 0, shots = 0, days = 0 }
    local days = {}
    for _, character in pairs(db.characters) do
        result.characters = result.characters + 1
        result.shots = result.shots + #character.shots
        for _, map in ipairs({ character.playtime.days, character.steps.days, character.shotsByDay }) do
            for day, value in pairs(map) do
                if value > 0 then
                    days[day] = true
                end
            end
        end
    end
    for _ in pairs(days) do
        result.days = result.days + 1
    end
    return result
end
