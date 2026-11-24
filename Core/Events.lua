-- Core/Events.lua
-- Turns client events into normalized events
--   { type, key, info, character, zone }
-- and hands them to the Engine. Only events the client accepts are
-- registered; a trigger whose event is rejected is marked unavailable
-- and shown greyed out with the reason. Nothing is guessed: an event that
-- cannot be told apart reliably is not captured (spec 5.3).
local _, ns = ...

local Events = {}
ns.Events = Events

local API = ns.API

local function emit(kind, key, info)
    if not ns.characterKey then
        return
    end
    ns.Engine.Submit({
        type = kind,
        key = key,
        info = info,
        character = ns.characterKey,
        zone = API.ZoneName(),
    })
end
Events.Emit = emit

---------------------------------------------------------------------------
-- Items: own rare / epic / legendary items from CHAT_MSG_LOOT. The client
-- writes this line only when the item is received (loot, quest reward,
-- purchase), never when it is moved between bag slots.
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

local LOOT_BY_QUALITY = { [3] = "LOOT_RARE", [4] = "LOOT_EPIC", [5] = "LOOT_LEGENDARY" }

-- One item = one event of exactly one quality, so they never duplicate.
local function onLoot(_, text)
    local link = Events.OwnLootLink(text)
    if not link then
        return
    end
    local kind = LOOT_BY_QUALITY[API.ItemQuality(link)]
    if kind then
        local itemID = string.match(link, "item:(%d+)") or link
        emit(kind, "loot:" .. itemID, link)
    end
end

---------------------------------------------------------------------------
-- Duel: "%1$s has defeated %2$s in a duel" style system messages.
-- Only a win of the current character counts.
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
    local me = API.PlayerName()
    if winner and me and winner == me then
        emit("DUEL", "duel:" .. tostring(loser), loser)
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
    emit("ZONE", key, nil)
end

---------------------------------------------------------------------------
-- Guild: a real join, never a login. The client may report "no guild"
-- for a moment after login, so the saved state is not changed to
-- "no guild" during the first GUILD_GRACE seconds, and a join is only
-- recognised against a known earlier state.
---------------------------------------------------------------------------
Events.GUILD_GRACE = 30
local loginAt = 0

function Events.CheckGuild()
    local character = ns.character
    if not character then
        return
    end
    local name = API.IsInGuild() and API.GuildName() or nil
    local graceOver = API.Now() - loginAt >= Events.GUILD_GRACE
    if name then
        local before = character.guild
        character.guild = name
        if before == false then
            emit("GUILD", "guild:" .. name, name)
        end
    elseif graceOver and not API.IsInGuild() then
        character.guild = false
    end
end

---------------------------------------------------------------------------
-- Trigger definitions: client events and handlers.
---------------------------------------------------------------------------
local DEFINITIONS = {
    LEVEL = {
        events = { "PLAYER_LEVEL_UP" },
        -- Every level, the maximum one too (it is not a separate event).
        handler = function(_, level)
            if not API.IsPlainNumber(level) then
                return
            end
            emit("LEVEL", "level:" .. level, level)
        end,
    },
    DEATH = {
        events = { "PLAYER_DEAD" },
        handler = function() emit("DEATH", "death", nil) end,
    },
    BOSS = {
        events = { "ENCOUNTER_END" },
        -- Only a successful encounter inside a dungeon or a raid.
        handler = function(_, encounterID, encounterName, difficultyID, _, success)
            if API.IsSecret(success) or API.IsSecret(encounterID) then
                return
            end
            local where = API.InstanceType()
            if (success == 1 or success == true) and (where == "party" or where == "raid") then
                local name = type(encounterName) == "string" and not API.IsSecret(encounterName)
                    and encounterName or nil
                emit("BOSS", "boss:" .. tostring(encounterID) .. ":" .. tostring(difficultyID), name)
            end
        end,
    },
    DUEL = { events = { "CHAT_MSG_SYSTEM" }, handler = onSystemMessage },
    LOOT_RARE = { events = { "CHAT_MSG_LOOT" }, handler = onLoot },
    LOOT_EPIC = { events = { "CHAT_MSG_LOOT" }, sharesWith = "LOOT_RARE" },
    LOOT_LEGENDARY = { events = { "CHAT_MSG_LOOT" }, sharesWith = "LOOT_RARE" },
    ZONE = {
        events = { "ZONE_CHANGED_NEW_AREA" },
        handler = function() Events.CheckZone() end,
    },
    GUILD = {
        events = { "PLAYER_GUILD_UPDATE" },
        handler = function() Events.CheckGuild() end,
    },
}

-- Registers every trigger. Called once at login.
function Events.Init()
    loginAt = API.Now()
    local registered = {}
    for _, id in ipairs(ns.Registry.EVENTS) do
        local def = DEFINITIONS[id]
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
        ns.Registry.SetStatus(id, ok, reason)
    end
    Events.CheckZone()
    -- A later check settles "no guild" once the grace period is over.
    API.After(Events.GUILD_GRACE + 1, function() ns.SafeCall("guild", Events.CheckGuild) end)
    Events.CheckGuild()
end

table.insert(ns.onLogin, Events.Init)
