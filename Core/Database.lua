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
--   zoneStats = { since = t, current = { key, t },
--                 zones = { [zoneKey] = { time, steps, visits, last } } }
-- }
local _, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA_VERSION = 5
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
}

-- Settings on the Settings / General page: "Restore defaults" resets only
-- these (and the window position). Capture settings, statistics and
-- history are never touched by it.
Database.GENERAL_SETTINGS = { "locale", "scale", "minimap", "rememberTab", "notifications", "sound", "toastDuration" }

function Database.ResetGeneral(db)
    for _, key in ipairs(Database.GENERAL_SETTINGS) do
        db.settings[key] = Database.SETTINGS[key].default
    end
    db.ui.point = nil
end

local TOP_LEVEL = {
    schemaVersion = true, settings = true, ui = true, counters = true,
    characters = true, legacy = true, zoneDump = true,
}

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
}

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

-- Adventure Achievements (v0.13.0): { seeded, done = { [id] = time | 0 } }.
local function validateAchievements(character, path, repaired)
    local a = character.achievements
    if a == nil then
        return
    end
    if type(a) ~= "table" or type(a.done) ~= "table" then
        character.achievements = nil
        repaired[#repaired + 1] = path .. ".achievements"
        return
    end
    a.seeded = a.seeded == true
    for id, at in pairs(a.done) do
        if type(id) ~= "string" or not number(at) or at < 0 then
            a.done[id] = nil
            repaired[#repaired + 1] = path .. ".achievements." .. tostring(id)
        end
    end
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
        end
    end
end

-- Takes whatever the client loaded and returns a valid table plus the list
-- of paths that had to be reset.
function Database.Load(raw)
    local repaired = {}
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
    for v = version, Database.SCHEMA_VERSION - 1 do
        if Database.MIGRATIONS[v] then
            Database.MIGRATIONS[v](db)
        end
        db.schemaVersion = v + 1
    end
    db.schemaVersion = Database.SCHEMA_VERSION

    for key in pairs(db) do
        if not TOP_LEVEL[key] then
            db[key] = nil
            repaired[#repaired + 1] = tostring(key)
        end
    end

    validateSettings(db, repaired)
    validateCharacters(db, repaired)
    tableOf(db, "ui", repaired, "ui")
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
    return db, repaired
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
                -- diagnostics (see API_COMPATIBILITY.md), data is kept.
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
