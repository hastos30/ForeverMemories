-- Core/Events.lua
-- Turns client events into normalized events
--   { type, key, ts, character, zone, payload }
-- and hands them to the Engine. Only events the client accepts are
-- registered; a trigger whose event is rejected is marked unavailable.
local _, ns = ...

local Events = {}
ns.Events = Events

local API = ns.API

local function emit(kind, key, payload)
    if not ns.characterKey then
        return
    end
    ns.Engine.Submit({
        type = kind,
        key = key,
        ts = API.Now(),
        character = ns.characterKey,
        zone = API.ZoneName(),
        payload = payload,
    })
end
Events.Emit = emit

---------------------------------------------------------------------------
-- Loot: own epic/legendary items from CHAT_MSG_LOOT.
---------------------------------------------------------------------------
local lootPatterns

local function buildLootPatterns()
    lootPatterns = {}
    local names = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
                    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }
    for _, name in ipairs(names) do
        local pattern, order = ns.Util.FormatToPattern(_G[name])
        if pattern then
            lootPatterns[#lootPatterns + 1] = { pattern = pattern, order = order }
        end
    end
end

-- Returns the item link if `text` says that the player received an item.
function Events.OwnLootLink(text)
    if type(text) ~= "string" or API.IsSecret(text) then
        return nil
    end
    if not lootPatterns then
        buildLootPatterns()
    end
    for _, p in ipairs(lootPatterns) do
        local captures = ns.Util.MatchFormat(text, p.pattern, p.order)
        if captures and captures[1] then
            return captures[1]
        end
    end
    return nil
end

local function onLoot(_, text)
    local link = Events.OwnLootLink(text)
    if not link then
        return
    end
    local quality = API.ItemQuality(link)
    local itemID = string.match(link, "item:(%d+)") or link
    if quality == 5 then
        emit("LOOT_LEGENDARY", "loot:" .. itemID, { link = link })
    elseif quality == 4 then
        emit("LOOT_EPIC", "loot:" .. itemID, { link = link })
    end
end

---------------------------------------------------------------------------
-- Duel: "%1$s has defeated %2$s in a duel" style system messages.
---------------------------------------------------------------------------
local duelPatterns

function Events.DuelWinner(text)
    if type(text) ~= "string" or API.IsSecret(text) then
        return nil
    end
    if not duelPatterns then
        duelPatterns = {}
        for _, name in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
            local pattern, order = ns.Util.FormatToPattern(_G[name])
            if pattern then
                duelPatterns[#duelPatterns + 1] = { pattern = pattern, order = order }
            end
        end
    end
    for _, p in ipairs(duelPatterns) do
        local captures = ns.Util.MatchFormat(text, p.pattern, p.order)
        if captures then
            return captures[1], captures[2]
        end
    end
end

local function onSystemMessage(_, text)
    local winner, loser = Events.DuelWinner(text)
    if winner and winner == API.PlayerName() then
        emit("DUEL", "duel:" .. tostring(loser), nil)
    end
end

---------------------------------------------------------------------------
-- Zone: first visit per character, by stable map ID.
---------------------------------------------------------------------------
function Events.CheckZone()
    local character = ns.character
    local key = API.ZoneKey()
    if not character or not key or character.visited[key] then
        return
    end
    character.visited[key] = true
    if not character.zonesSeeded then
        -- Fresh install: the zone you are standing in is not a new memory.
        character.zonesSeeded = true
        return
    end
    emit("ZONE", key, { zone = API.ZoneName() })
end

---------------------------------------------------------------------------
-- Trigger definitions: client events and handlers.
---------------------------------------------------------------------------
local wasInGuild
local DEFINITIONS = {
    LEVEL = {
        events = { "PLAYER_LEVEL_UP" },
        handler = function(_, level)
            local maxLevel = API.MaxLevel()
            if type(level) ~= "number" or API.IsSecret(level) then
                return
            end
            -- MAX_LEVEL replaces LEVEL for the same level-up.
            if type(maxLevel) == "number" and level >= maxLevel then
                emit("MAX_LEVEL", "level:" .. level)
            else
                emit("LEVEL", "level:" .. level)
            end
        end,
    },
    MAX_LEVEL = { events = { "PLAYER_LEVEL_UP" }, sharesWith = "LEVEL" },
    ZONE = {
        events = { "ZONE_CHANGED_NEW_AREA" },
        handler = function() Events.CheckZone() end,
    },
    BOSS = {
        events = { "ENCOUNTER_END" },
        handler = function(_, encounterID, _, difficultyID, _, success)
            if API.IsSecret(success) or API.IsSecret(encounterID) then
                return
            end
            if success == 1 or success == true then
                emit("BOSS", "boss:" .. tostring(encounterID) .. ":" .. tostring(difficultyID))
            end
        end,
    },
    LOOT_EPIC = { events = { "CHAT_MSG_LOOT" }, handler = onLoot },
    LOOT_LEGENDARY = { events = { "CHAT_MSG_LOOT" }, sharesWith = "LOOT_EPIC" },
    MOUNT = {
        events = { "NEW_MOUNT_ADDED" },
        handler = function(_, mountID)
            emit("MOUNT", "mount:" .. tostring(mountID))
        end,
    },
    DUNGEON = {
        events = { "LFG_COMPLETION_REWARD" },
        handler = function()
            emit("DUNGEON", "dungeon:" .. tostring(API.InstanceName()))
        end,
    },
    DUEL = { events = { "CHAT_MSG_SYSTEM" }, handler = onSystemMessage },
    DEATH = {
        events = { "PLAYER_DEAD" },
        handler = function() emit("DEATH", "death") end,
    },
    QUEST = {
        events = { "QUEST_TURNED_IN" },
        handler = function(_, questID)
            if ns.character and questID and ns.character.quests[questID] then
                emit("QUEST", "quest:" .. questID)
            end
        end,
    },
    GUILD = {
        events = { "PLAYER_GUILD_UPDATE" },
        handler = function()
            local inGuild = API.IsInGuild()
            if inGuild and wasInGuild == false then
                emit("GUILD", "guild:" .. tostring(API.GuildName()))
            end
            wasInGuild = inGuild
        end,
    },
    FORM = {
        events = { "UPDATE_SHAPESHIFT_FORMS" },
        handler = function()
            local character = ns.character
            if not character or API.PlayerClass() ~= "DRUID" then
                return
            end
            local count = API.NumShapeshiftForms()
            local known = character.forms
            character.forms = math.max(count, known or 0)
            if known and count > known then
                emit("FORM", "form:" .. count)
            end
        end,
    },
}

-- Registers every supported trigger. Called once at login.
function Events.Init()
    wasInGuild = API.IsInGuild()
    if ns.character and API.PlayerClass() == "DRUID" and not ns.character.forms then
        ns.character.forms = API.NumShapeshiftForms()
    end
    local registered = {}
    for _, trigger in ipairs(ns.Registry.TRIGGERS) do
        local def = DEFINITIONS[trigger.id]
        if def and not trigger.unsupported then
            local ok, reason = true, nil
            for _, event in ipairs(def.events) do
                if registered[event] == nil then
                    local handler = def.handler or DEFINITIONS[def.sharesWith].handler
                    local okEvent, why = ns.On(event, handler)
                    registered[event] = okEvent and true or (why or "rejected")
                end
                if registered[event] ~= true then
                    ok, reason = false, event .. ": " .. tostring(registered[event])
                end
            end
            ns.Registry.SetStatus(trigger.id, ok, reason)
        end
    end
    ns.Profiles.Invalidate()
    Events.CheckZone()
end

table.insert(ns.onLogin, Events.Init)
