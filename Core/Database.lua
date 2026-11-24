-- Core/Database.lua
-- Loads, migrates and validates ForeverMemoriesDB. Pure logic: no client
-- calls, so every rule here is covered by offline tests.
local _, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA_VERSION = 2
Database.MAX_JOURNAL = 2000
Database.MAX_FAVORITES = 500

-- Settings: type, default and allowed values. Anything else is reset.
Database.SETTINGS = {
    enabled = { kind = "boolean", default = true },
    locale = { kind = "enum", default = "auto", values = { "auto", "enUS", "ruRU" } },
    notifications = { kind = "boolean", default = true },
    notifyDuration = { kind = "number", default = 3, min = 1, max = 5 },
    sound = { kind = "boolean", default = true },
    minimap = { kind = "boolean", default = true },
    minimapAngle = { kind = "number", default = 200, min = 0, max = 360 },
    scale = { kind = "number", default = 1, min = 0.8, max = 1.5 },
    manualTimer = { kind = "enum", default = 0, values = { 0, 3, 5, 10 } },
    cleanAllowed = { kind = "boolean", default = true },
    advanced = { kind = "boolean", default = false },
    defaultProfile = { kind = "string", default = "Adventurer" },
    firstRunDone = { kind = "boolean", default = false },
    anniversaryShown = { kind = "string", default = "" },
}

local TOP_LEVEL = {
    schemaVersion = true, settings = true, profiles = true, characters = true,
    journal = true, nextJournalId = true, counters = true, ui = true,
}

-- Sequential migrations: MIGRATIONS[n] turns schema n into n + 1.
Database.MIGRATIONS = {
    [1] = function(db)
        -- v0.0.1 spike data is not needed any more.
        db.spike = nil
    end,
}

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

local function tableOf(parent, key, repaired, path)
    if type(parent[key]) ~= "table" then
        if parent[key] ~= nil then
            repaired[#repaired + 1] = path
        end
        parent[key] = {}
    end
    return parent[key]
end

local function validateSettings(db, repaired)
    local settings = tableOf(db, "settings", repaired, "settings")
    for key, value in pairs(settings) do
        if not Database.SETTINGS[key] then
            settings[key] = nil
            repaired[#repaired + 1] = "settings." .. tostring(key)
        elseif not validSetting(Database.SETTINGS[key], value) then
            settings[key] = nil
            repaired[#repaired + 1] = "settings." .. key
        end
    end
    for key, spec in pairs(Database.SETTINGS) do
        if settings[key] == nil then
            settings[key] = spec.default
        end
    end
end

local function validateProfiles(db, repaired)
    local profiles = tableOf(db, "profiles", repaired, "profiles")
    for name, profile in pairs(profiles) do
        if type(name) ~= "string" or type(profile) ~= "table" then
            profiles[name] = nil
            repaired[#repaired + 1] = "profiles." .. tostring(name)
        else
            if type(profile.base) ~= "string" then
                profile.base = "Adventurer"
            end
            tableOf(profile, "rules", repaired, "profiles." .. name .. ".rules")
            tableOf(profile, "limits", repaired, "profiles." .. name .. ".limits")
            tableOf(profile, "journey", repaired, "profiles." .. name .. ".journey")
        end
    end
end

local function validateCharacters(db, repaired)
    local characters = tableOf(db, "characters", repaired, "characters")
    for key, character in pairs(characters) do
        if type(key) ~= "string" or type(character) ~= "table" then
            characters[key] = nil
            repaired[#repaired + 1] = "characters." .. tostring(key)
        else
            local path = "characters." .. key
            tableOf(character, "visited", repaired, path .. ".visited")
            tableOf(character, "firstEvents", repaired, path .. ".firstEvents")
            tableOf(character, "quests", repaired, path .. ".quests")
            if character.profile ~= nil and type(character.profile) ~= "string" then
                character.profile = nil
                repaired[#repaired + 1] = path .. ".profile"
            end
        end
    end
end

local function validateJournal(db, repaired)
    local journal = tableOf(db, "journal", repaired, "journal")
    local clean = {}
    local maxId = 0
    for i = 1, #journal do
        local entry = journal[i]
        if type(entry) == "table" and type(entry.id) == "number" and type(entry.t) == "number" then
            if type(entry.events) ~= "table" then
                entry.events = {}
            end
            clean[#clean + 1] = entry
            if entry.id > maxId then
                maxId = entry.id
            end
        else
            repaired[#repaired + 1] = "journal[" .. i .. "]"
        end
    end
    db.journal = clean
    if type(db.nextJournalId) ~= "number" or db.nextJournalId <= maxId then
        db.nextJournalId = maxId + 1
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
    end
    db.schemaVersion = Database.SCHEMA_VERSION

    for key in pairs(db) do
        if not TOP_LEVEL[key] then
            db[key] = nil
            repaired[#repaired + 1] = tostring(key)
        end
    end

    validateSettings(db, repaired)
    validateProfiles(db, repaired)
    validateCharacters(db, repaired)
    validateJournal(db, repaired)
    tableOf(db, "counters", repaired, "counters")
    tableOf(db, "ui", repaired, "ui")
    if type(db.counters.unattributed) ~= "number" then
        db.counters.unattributed = 0
    end

    return db, repaired
end

-- Per-character storage, created on first use.
function Database.Character(db, key)
    local character = db.characters[key]
    if not character then
        character = { visited = {}, firstEvents = {}, quests = {} }
        db.characters[key] = character
    end
    return character
end
