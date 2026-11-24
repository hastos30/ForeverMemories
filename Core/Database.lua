-- Core/Database.lua
-- Validates the SavedVariables table. Pure logic: no client calls, so it
-- can be tested outside the game.
--
-- v0.0.1 keeps only spike data under `spike`. The full schema from
-- ARCHITECTURE.md section 5 arrives in v0.1.0 with a migration.
local _, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA_VERSION = 1
Database.MAX_SHOTS = 50
Database.MAX_PROBES = 10

local function ensureTable(parent, key, repaired)
    if type(parent[key]) ~= "table" then
        if parent[key] ~= nil then
            repaired[#repaired + 1] = key
        end
        parent[key] = {}
    end
    return parent[key]
end

local function ensureNumber(parent, key, default, repaired)
    if type(parent[key]) ~= "number" then
        if parent[key] ~= nil then
            repaired[#repaired + 1] = key
        end
        parent[key] = default
    end
end

-- Takes whatever the client loaded (may be nil or corrupted) and returns
-- a valid table plus the list of keys that had to be reset.
function Database.Load(raw)
    local repaired = {}
    local db = raw
    if type(db) ~= "table" then
        if db ~= nil then
            repaired[#repaired + 1] = "ForeverMemoriesDB"
        end
        db = {}
    end
    ensureNumber(db, "schemaVersion", Database.SCHEMA_VERSION, repaired)

    local spike = ensureTable(db, "spike", repaired)
    ensureTable(spike, "shots", repaired)
    ensureTable(spike, "probes", repaired)
    ensureTable(spike, "events", repaired)
    ensureNumber(spike, "nextShotId", 1, repaired)
    ensureNumber(spike, "screenshotCalls", 0, repaired)
    ensureNumber(spike, "unattributedResults", 0, repaired)
    -- Counts addon loads; growing across /reload proves SavedVariables work.
    ensureNumber(spike, "loadCount", 0, repaired)
    spike.loadCount = spike.loadCount + 1

    return db, repaired
end

-- Appends to a list and drops the oldest items above `limit`.
function Database.AppendCapped(list, item, limit)
    list[#list + 1] = item
    while #list > limit do
        table.remove(list, 1)
    end
end
