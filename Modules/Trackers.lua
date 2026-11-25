-- Modules/Trackers.lua
-- Trackers for the achievements that waited for them (v0.18.0). Every
-- value is a confirmed state seen by the add-on from now on; the past is
-- never guessed, and the state at login is a baseline, never an event
-- (being in a group when you log in is not "joining" one).
--
-- character.tracks = {
--   since = time,                    -- first tracking of this character
--   taxi = n,                        -- taxi flights seen from take-off to landing
--   mount = true,                    -- a ground mount used while moving on land
--   partyJoins = n, raidJoins = n,   -- joining a party / a raid group
--   groupDays = { [day] = true },    -- active play in a group
--   guildDays = { [day] = true },    -- active play in a guild
--   bosses = n, bossIDs = { [encounterID] = true }, deaths = n,
--   duskwoodNight = true,            -- Duskwood between 21:00 and 05:59 game time
--   homeAfterCap = true,             -- the race's starting zone after the level cap
-- }
-- Sources that the client lacks leave the value unknown (nil), never 0:
-- see Trackers.Sources(). Not tracked here (no verified signal yet):
-- crafts and battleground wins.
local _, ns = ...

local Trackers = {}
ns.Trackers = Trackers

local API = ns.API

Trackers.THROTTLE = 5 -- seconds between the checks on the activity clock

-- Night in Duskwood: from 21:00 through 05:59 of the game (server) time.
Trackers.NIGHT_FROM, Trackers.NIGHT_TO = 21, 6
Trackers.DUSKWOOD = 10 -- AreaTable ID
-- Starting zone of each race (AreaTable IDs of the zone catalog).
Trackers.START_ZONE = {
    Human = 12, Dwarf = 1, Gnome = 1, NightElf = 141,
    Orc = 14, Troll = 14, Tauren = 215, Scourge = 85,
}

-- listener() after any value changed (achievements check).
Trackers.listeners = {}

local function call(name, ...)
    local fn = API.Resolve(name)
    if not fn then
        return nil, false
    end
    local ok, value = pcall(fn, ...)
    if not ok or API.IsSecret(value) then
        return nil, false
    end
    return value, true
end

local function data(character)
    character = character or ns.character
    if not character then
        return nil
    end
    local t = character.tracks
    if type(t) ~= "table" then
        t = {}
        character.tracks = t
    end
    t.since = type(t.since) == "number" and t.since or API.Time()
    for _, key in ipairs({ "groupDays", "guildDays", "bossIDs" }) do
        if type(t[key]) ~= "table" then
            t[key] = {}
        end
    end
    for _, key in ipairs({ "taxi", "partyJoins", "raidJoins", "bosses", "deaths" }) do
        if type(t[key]) ~= "number" then
            t[key] = 0
        end
    end
    return t
end
Trackers.Data = data

local function changed()
    for i = 1, #Trackers.listeners do
        ns.SafeCall("tracker listener", Trackers.listeners[i])
    end
end

-- Which sources the client has (unknown states, /fm debug).
function Trackers.Sources()
    return {
        taxi = API.Resolve("UnitOnTaxi") ~= nil,
        mount = API.Resolve("IsMounted") ~= nil and API.Resolve("IsFlying") ~= nil,
        group = API.Resolve("IsInGroup") ~= nil and API.Resolve("IsInRaid") ~= nil,
        guild = API.Resolve("IsInGuild") ~= nil,
        gameTime = API.GameTime() ~= nil,
    }
end

-- Area ID of the zone the player is in (catalog zones only), or nil.
local function currentArea()
    local name = API.ZoneName()
    return name and ns.ZoneCatalog.AreaOfName(name) or nil
end

---------------------------------------------------------------------------
-- State seen on the activity clock (throttled).
---------------------------------------------------------------------------
local last = {} -- last seen state of this session: onTaxi, group
local nextCheck = 0

function Trackers.ResetSession()
    last = {}
    nextCheck = 0
end

function Trackers.Check(active)
    local character = ns.character
    if not character or character ~= ns.db.characters[ns.characterKey] or ns.readOnly then
        return false
    end
    local t = data(character)
    local any = false
    local today = ns.Util.DayKey(API.Time())

    -- Taxi: counted when a flight seen in the air lands.
    local onTaxi, hasTaxi = call("UnitOnTaxi", "player")
    if hasTaxi then
        onTaxi = onTaxi and true or false
        if last.onTaxi == true and onTaxi == false then
            t.taxi = t.taxi + 1
            any = true
        end
        last.onTaxi = onTaxi
    end

    -- Ground mount: mounted, moving, on land, not flying and not on a taxi.
    if not t.mount and hasTaxi and not onTaxi then
        local mounted, hasMounted = call("IsMounted")
        local flying, hasFlying = call("IsFlying")
        local swimming = call("IsSwimming")
        local speed = API.UnitSpeed()
        if hasMounted and hasFlying and mounted and not flying and not swimming and speed and speed > 0 then
            t.mount = true
            any = true
        end
    end

    -- Groups: a join is a change from "not in a group" seen by the add-on.
    local inGroup, hasGroup = call("IsInGroup")
    local inRaid, hasRaid = call("IsInRaid")
    if hasGroup and hasRaid then
        local state = inRaid and "raid" or (inGroup and "party" or "none")
        if last.group and last.group ~= state then
            if state == "party" and last.group == "none" then
                t.partyJoins = t.partyJoins + 1
                any = true
            elseif state == "raid" then
                t.raidJoins = t.raidJoins + 1
                any = true
            end
        end
        last.group = state
        if state ~= "none" and active and active > 0 and not t.groupDays[today] then
            t.groupDays[today] = true
            any = true
        end
    end

    -- Guild days: active play while in a guild.
    if active and active > 0 and not t.guildDays[today] and API.IsInGuild() then
        t.guildDays[today] = true
        any = true
    end

    local area = currentArea()
    -- Duskwood at night (game time; the clock of the server, not of the PC).
    if not t.duskwoodNight and area == Trackers.DUSKWOOD then
        local hour = API.GameTime()
        if hour and (hour >= Trackers.NIGHT_FROM or hour < Trackers.NIGHT_TO) then
            t.duskwoodNight = true
            any = true
        end
    end
    -- Home after the level cap: the starting zone of the character's race.
    if not t.homeAfterCap and area then
        local p = character.progress
        local race = (type(p) == "table" and p.race) or API.RaceFile()
        local home = race and Trackers.START_ZONE[race]
        if home and area == home and type(p) == "table" and p.levelCap then
            t.homeAfterCap = true
            any = true
        end
    end

    if any then
        changed()
    end
    return any
end

-- A boss defeat in a dungeon or raid (Core/Events.lua, ENCOUNTER_END).
function Trackers.OnEvent(kind, _, key)
    if (kind ~= "BOSS" and kind ~= "DEATH") or ns.readOnly then
        return
    end
    local t = data()
    if not t then
        return
    end
    if kind == "DEATH" then -- v0.18.0: for the Chronicle (first death, 10, 100, 500)
        t.deaths = t.deaths + 1
        changed()
        return
    end
    t.bosses = t.bosses + 1
    local id = type(key) == "string" and key:match("^boss:([^:]+)") or nil
    if id and id ~= "nil" then
        t.bossIDs[id] = true
    end
    changed()
end

table.insert(ns.Activity.listeners, function(active)
    local now = API.Now()
    if now < nextCheck then
        return
    end
    nextCheck = now + Trackers.THROTTLE
    Trackers.Check(active)
end)
table.insert(ns.Events.listeners, Trackers.OnEvent)
table.insert(ns.onLogin, function()
    Trackers.ResetSession()
    data()
end)
for _, event in ipairs({ "GROUP_ROSTER_UPDATE" }) do
    ns.On(event, function() nextCheck = 0 end) -- check soon after a change
end
