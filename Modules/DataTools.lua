-- Modules/DataTools.lua
-- Settings / Data and Settings / About (v0.10.0): saved characters,
-- statistics export, text backup and its safe import, clearing history,
-- and the diagnostics report.
--
-- Everything stays inside the game: texts are shown in a copy box (the
-- player copies them with Ctrl+C), nothing is written to disk by the
-- addon, nothing is downloaded. A backup is parsed by Core/Serialize.lua
-- and is NEVER run as Lua code. Screenshot files are never touched.
local _, ns = ...

local DataTools = {}
ns.DataTools = DataTools

local L = ns.L

DataTools.listeners = {} -- called after history was cleared or deleted

local function notify()
    for _, listener in ipairs(DataTools.listeners) do
        ns.SafeCall("data listener", listener)
    end
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------

-- Short statistics of any saved character (from its own data only).
function DataTools.Summary(character)
    local zones, days, lastDay = 0, 0, nil
    for _ in pairs(character.visited or {}) do
        zones = zones + 1
    end
    for day, seconds in pairs(character.playtime and character.playtime.days or {}) do
        if seconds > 0 then
            days = days + 1
            if type(day) == "string" and (not lastDay or day > lastDay) then
                lastDay = day -- "YYYY-MM-DD" keys sort as dates
            end
        end
    end
    return {
        shots = character.shotsTotal or 0,
        steps = math.floor(character.steps and character.steps.total or 0),
        zones = zones,
        playtime = math.floor(character.playtime and character.playtime.total or 0),
        days = days,
        lastDay = lastDay, -- v1.0.0-beta.4: last day with play
        level = character.progress and character.progress.level,
        since = character.journey and character.journey.started,
    }
end

-- Saved characters, the current one first, then by name.
--   { { key, character, current, summary }, ... }
function DataTools.Characters()
    local list = {}
    for key, character in pairs(ns.db.characters) do
        list[#list + 1] = {
            key = key, character = character, current = key == ns.characterKey,
            summary = DataTools.Summary(character),
        }
    end
    table.sort(list, function(a, b)
        if a.current ~= b.current then
            return a.current
        end
        return ns.Util.Lower(a.key) < ns.Util.Lower(b.key)
    end)
    return list
end

-- Totals of every saved character (History / All characters, v0.12.0).
-- Locations are the union of the zones (one zone visited by two
-- characters counts once). Time is the active play measured by the addon
-- for each character; /played of the game is never added to it.
function DataTools.AccountTotals()
    local totals = { characters = 0, shots = 0, steps = 0, zones = 0, playtime = 0 }
    local zones = {}
    for _, character in pairs(ns.db.characters) do
        local s = DataTools.Summary(character)
        totals.characters = totals.characters + 1
        totals.shots = totals.shots + s.shots
        totals.steps = totals.steps + s.steps
        totals.playtime = totals.playtime + s.playtime
        for key in pairs(character.visited or {}) do
            zones[key] = true
        end
    end
    for _ in pairs(zones) do
        totals.zones = totals.zones + 1
    end
    return totals
end

function DataTools.DisplayName(character, key)
    local name = character.name or string.match(tostring(key), ":(.+)$") or tostring(key)
    return name
end

-- Deletes another character's history. The current one is cleared with
-- ClearCurrent instead (its tables are in use).
function DataTools.Delete(key)
    if key == ns.characterKey then
        return false
    end
    local ok = ns.Database.DeleteCharacter(ns.db, key)
    if ok then
        ns.Logger.Info("History deleted: " .. tostring(key))
        notify()
    end
    return ok
end

function DataTools.ClearCurrent()
    if not ns.character then
        return false
    end
    ns.Database.ClearCharacter(ns.character, ns.characterKey, ns.API.Time())
    ns.Activity.StartSession()
    ns.Locations.Visit()
    ns.Logger.Info("History cleared: " .. tostring(ns.characterKey))
    notify()
    return true
end

---------------------------------------------------------------------------
-- Statistics export: readable text, one block per character.
---------------------------------------------------------------------------
local function dateText(t)
    return t and date("%Y-%m-%d", t) or L.NO_DATA
end

function DataTools.StatsText()
    local lines = {
        "ForeverMemories v" .. ns.version .. " — " .. L.EXPORT_STATS_TITLE,
        L.EXPORT_CREATED .. ": " .. date("%Y-%m-%d %H:%M", ns.API.Time()),
        "",
    }
    local storage = ns.Database.Storage(ns.db)
    lines[#lines + 1] = string.format("%s: %d   %s: %d   %s: %d", L.DATA_CHARACTERS, storage.characters,
        L.DATA_SHOT_RECORDS, storage.shots, L.DATA_GAME_DAYS, storage.days)
    for _, item in ipairs(DataTools.Characters()) do
        local c, s = item.character, item.summary
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("%s — %s%s", DataTools.DisplayName(c, item.key), c.realm or "?",
            c.class and (" (" .. ns.API.ClassName(c.class) .. ")") or "")
        lines[#lines + 1] = "  " .. L.STAT_TOTAL_SHOTS .. ": " .. ns.Num(s.shots)
        lines[#lines + 1] = "  " .. L.STAT_TOTAL_STEPS .. ": " .. ns.Num(s.steps)
        lines[#lines + 1] = "  " .. L.STAT_ZONES_VISITED .. ": " .. ns.Num(s.zones)
        lines[#lines + 1] = "  " .. L.EXPORT_ACTIVE_TIME .. ": " .. ns.UI.FormatDuration(s.playtime)
        lines[#lines + 1] = "  " .. L.EXPORT_DAYS_PLAYED .. ": " .. ns.Num(s.days)
        lines[#lines + 1] = "  " .. L.EXPORT_TRACKING_SINCE .. ": " .. dateText(s.since)
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Backup: the whole saved data of the account (settings, window,
-- characters, old records) in the text format of Core/Serialize.lua.
-- The diagnostic zone dump is left out.
---------------------------------------------------------------------------
local BACKUP_FIELDS = { "schemaVersion", "settings", "ui", "counters", "characters", "legacy" }

function DataTools.BackupText()
    local data = { addonVersion = ns.version, createdAt = ns.API.Time() }
    for _, field in ipairs(BACKUP_FIELDS) do
        data[field] = ns.db[field]
    end
    return ns.Serialize.Encode(data, ns.db.schemaVersion)
end

-- Checks a pasted backup without changing anything. Returns a plan:
--   { db = validated data, characters = n, shots = n, createdAt, version,
--     repaired = n }
-- or nil plus an error code (IMPORT_ERROR_<code> in the locales):
--   empty, format, checksum, damaged, newer, structure
function DataTools.CheckBackup(text)
    local data, schemaOrError = ns.Serialize.Decode(text)
    if not data then
        return nil, schemaOrError
    end
    if schemaOrError > ns.Database.SCHEMA_VERSION
        or (type(data.schemaVersion) == "number" and data.schemaVersion > ns.Database.SCHEMA_VERSION) then
        return nil, "newer"
    end
    if type(data.characters) ~= "table" or type(data.settings) ~= "table" then
        return nil, "structure"
    end
    local createdAt = type(data.createdAt) == "number" and data.createdAt or nil
    local version = type(data.addonVersion) == "string" and data.addonVersion or nil
    data.createdAt, data.addonVersion = nil, nil
    -- The same migration and validation as a SavedVariables file.
    local ok, db, repaired, status = pcall(ns.Database.Load, data)
    if not ok or type(db) ~= "table" then
        return nil, "structure"
    end
    if status.incompatible then
        return nil, "newer"
    elseif status.unsafe then
        return nil, "structure" -- the migration would lose data: refused
    end
    local storage = ns.Database.Storage(db)
    return {
        db = db, characters = storage.characters, shots = storage.shots,
        createdAt = createdAt, version = version, repaired = #repaired,
    }
end

-- Replaces the saved data with a checked backup. The current character
-- continues with its data from the backup (or starts fresh if it is not
-- in it). A /reload is offered by the UI afterwards.
function DataTools.ApplyBackup(plan)
    local db = plan.db
    ForeverMemoriesDB = db
    ns.db = db
    if ns.characterKey then
        ns.character = ns.Database.Character(db, ns.characterKey, {
            name = ns.API.PlayerName(), realm = ns.API.RealmName(),
            class = ns.API.PlayerClass(), guid = ns.API.PlayerGUID(),
        })
        ns.Activity.StartSession()
        ns.Locations.Visit()
    end
    ns.Logger.Info("Backup imported: " .. plan.characters .. " characters")
    notify()
    return true
end

---------------------------------------------------------------------------
-- Diagnostics (Settings / About). No character name, realm, GUID or
-- guild: only what helps to find a bug.
---------------------------------------------------------------------------
local function lastError()
    local recent = ns.Logger.Recent()
    for i = #recent, 1, -1 do
        if recent[i].level == "ERROR" then
            return date("%H:%M:%S", recent[i].t) .. " " .. recent[i].msg
        end
    end
    return nil
end

-- { { label, value }, ... } for the technical block and the report.
function DataTools.DiagnosticsRows()
    local build = ns.API.GetBuild()
    local memory = ns.API.AddonMemoryKB(ns.name)
    local stepSource, stepReason, stepErrors = ns.Steps.Status()
    local passiveState = ns.Passive.Status()
    local engine = ns.Engine.GetState()
    return {
        { L.DIAG_ADDON_VERSION, ns.version },
        { L.DIAG_CLIENT, build and (build.version .. " (" .. build.build .. ")") or L.UNAVAILABLE },
        { "Interface", build and tostring(build.toc) or L.UNAVAILABLE },
        { L.DIAG_LOCALE, tostring(ns.API.GetLocale()) .. " / " .. tostring(ns.activeLocaleCode) },
        { L.DIAG_SCHEMA, tostring(ns.db.schemaVersion) },
        { L.DIAG_ENGINE, string.format("%s, %s", engine,
            ns.db.settings.enabled and L.STATE_ACTIVE or L.STATE_PAUSED) },
        { L.DIAG_STEPS, string.format("%s, %s / %s, errors %d",
            ns.Steps.IsRunning() and L.DIAG_RUNNING or L.DIAG_STOPPED, tostring(stepSource),
            tostring(stepReason), stepErrors or 0) },
        { L.DIAG_PASSIVE, string.format("%s, %s",
            ns.db.settings.passive and L.STATE_ON or L.STATE_OFF, tostring(passiveState)) },
        { L.DIAG_LAST_ERROR, lastError() or "-" },
        { L.DIAG_MEMORY, memory and (ns.Num(math.floor(memory + 0.5)) .. " KB") or L.UNAVAILABLE },
    }
end

function DataTools.DiagnosticsText()
    local lines = { "ForeverMemories diagnostics — " .. date("%Y-%m-%d %H:%M", ns.API.Time()) }
    for _, row in ipairs(DataTools.DiagnosticsRows()) do
        lines[#lines + 1] = row[1] .. ": " .. row[2]
    end
    return table.concat(lines, "\n")
end
