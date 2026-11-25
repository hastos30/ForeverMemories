-- Modules/Progress.lua
-- Character state the achievements need that no other module keeps
-- (v0.14.0): highest money, completed quests, Exalted factions, primary
-- professions and the ones at the profession cap, faction, race and the
-- level cap. Everything is a confirmed state read from the client; a
-- source the client lacks stays nil ("unknown"), never 0.
--
-- Values only grow: a forgotten profession, money spent or a lost
-- reputation never lowers what was reached (achievements are never taken
-- back). Read at login and after the events that change them, throttled.
--
-- character.progress = {
--   maxMoney = copper, quests = n,
--   exalted = { [factionID] = true }, professions = { [skillLine] = true },
--   professionsMax = { [skillLine] = true },
--   faction = "Alliance" | "Horde", race = "Human", levelCap = true,
-- }
local _, ns = ...

local Progress = {}
ns.Progress = Progress

local API = ns.API

-- Skill of a primary profession at its highest rank (Artisan in the
-- original game). PENDING in the Forever client: confirm when a character
-- reaches it (maxRank from GetProfessionInfo is only the cap of the
-- current rank, e.g. 150 for Journeyman, so it cannot be used).
Progress.PROFESSION_CAP = 300
Progress.DELAY = 2 -- seconds: several events in a row give one read

-- listener() after any value changed.
Progress.listeners = {}

local function data(character)
    local p = character.progress
    if type(p) ~= "table" then
        p = {}
        character.progress = p
    end
    for _, key in ipairs({ "exalted", "professions", "professionsMax" }) do
        if type(p[key]) ~= "table" then
            p[key] = {}
        end
    end
    return p
end
Progress.Data = data

local function raise(p, key, value)
    if type(value) == "number" and (type(p[key]) ~= "number" or value > p[key]) then
        p[key] = value
        return true
    end
    return false
end

local function mark(set, id)
    if id ~= nil and not set[id] then
        set[id] = true
        return true
    end
    return false
end

-- Reads every source once. Returns true if anything changed.
function Progress.Refresh()
    local character = ns.character
    if not character or character ~= ns.db.characters[ns.characterKey] then
        return false
    end
    local p = data(character)
    local changed = false
    changed = raise(p, "maxMoney", API.Money()) or changed
    changed = raise(p, "quests", (API.CompletedQuestCount())) or changed
    for _, id in ipairs(API.ExaltedFactionIDs() or {}) do
        changed = mark(p.exalted, id) or changed
    end
    for _, prof in ipairs(API.PrimaryProfessions() or {}) do
        changed = mark(p.professions, prof.skillLine) or changed
        if prof.rank >= Progress.PROFESSION_CAP then
            changed = mark(p.professionsMax, prof.skillLine) or changed
        end
    end
    local faction = API.FactionGroup()
    if faction and p.faction ~= faction then
        p.faction, changed = faction, true
    end
    local race = API.RaceFile()
    if race and p.race ~= race then
        p.race, changed = race, true
    end
    local level, cap = API.PlayerLevel(), API.MaxLevel()
    -- v1.0.0-beta.4: the last seen level, for Settings / Data (not a change
    -- that needs the listeners).
    if API.IsPlainNumber(level) and level > 0 then
        p.level = level
    end
    if level and cap and level >= cap and not p.levelCap then
        p.levelCap, changed = true, true
    end
    if changed then
        for i = 1, #Progress.listeners do
            ns.SafeCall("progress listener", Progress.listeners[i])
        end
    end
    return changed
end

-- Which sources the client has (for /fm debug and "unknown" states).
function Progress.Sources()
    return {
        money = API.Money() ~= nil,
        quests = API.CompletedQuestCount() ~= nil,
        reputation = API.ExaltedFactionIDs() ~= nil,
        professions = API.PrimaryProfessions() ~= nil,
    }
end

local pending = false
local function schedule()
    if pending then
        return
    end
    pending = true
    API.After(Progress.DELAY, function()
        pending = false
        Progress.Refresh()
    end)
end
Progress.Schedule = schedule

table.insert(ns.onLogin, function() Progress.Refresh() end)
for _, event in ipairs({ "PLAYER_MONEY", "QUEST_TURNED_IN", "UPDATE_FACTION", "SKILL_LINES_CHANGED",
                         "TRADE_SKILL_SHOW", "CHAT_MSG_SKILL", "PLAYER_LEVEL_UP" }) do
    ns.On(event, schedule) -- an event the client rejects is simply not used
end
