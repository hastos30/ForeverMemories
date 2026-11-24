-- Core/API.lua
-- The only place that touches World of Warcraft client functions directly.
-- Every wrapper checks that the client function exists and returns a value,
-- or nil plus a reason string. Forever may differ from Retail, so nothing
-- here assumes a function is present, and no secret value is ever used in
-- arithmetic or comparisons (that would be a Lua error in 12.x clients).
local _, ns = ...

local API = {}
ns.API = API

local function isFunction(value)
    return type(value) == "function"
end

-- Resolves a dotted name such as "C_Timer.After" in the global table.
function API.Resolve(name)
    local current = _G
    for part in string.gmatch(name, "[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[part]
    end
    if isFunction(current) then
        return current
    end
    return nil
end

-- Calls a client function by name; nil plus a reason if it is missing.
local function call(name, ...)
    local fn = API.Resolve(name)
    if not fn then
        return nil, name .. " unavailable"
    end
    return fn(...)
end

-- True when the value is a secret value we must not read.
function API.IsSecret(value)
    local check = API.Resolve("issecretvalue")
    return check ~= nil and check(value) and true or false
end

-- A plain, readable number (not nil, not secret, not NaN).
local function plainNumber(value)
    return type(value) == "number" and not API.IsSecret(value) and value == value
end
API.IsPlainNumber = plainNumber

function API.GetBuild()
    if not isFunction(GetBuildInfo) then
        return nil, "GetBuildInfo unavailable"
    end
    local version, build, buildDate, tocVersion = GetBuildInfo()
    return {
        version = tostring(version),
        build = tostring(build),
        date = tostring(buildDate),
        toc = tonumber(tocVersion),
    }
end

function API.IsEventValid(event)
    local isValid = API.Resolve("C_EventUtils.IsEventValid")
    if not isValid then
        return nil, "C_EventUtils.IsEventValid unavailable"
    end
    return isValid(event) and true or false
end

function API.RegisterFrameEvent(frame, event)
    if API.IsEventValid(event) == false then
        return false, "unknown event"
    end
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        return false, tostring(err)
    end
    return true
end

-- Confirmed in Forever 1.60.1 (71037): works from addon code, also in combat.
function API.TakeScreenshot()
    if not isFunction(Screenshot) then
        return nil, "Screenshot unavailable"
    end
    local ok, err = pcall(Screenshot)
    if not ok then
        return nil, tostring(err)
    end
    return true
end

function API.After(seconds, callback)
    local after = API.Resolve("C_Timer.After")
    if not after then
        return nil, "C_Timer.After unavailable"
    end
    after(seconds, callback)
    return true
end

-- Repeating timer; returns a handle with :Cancel(), or nil plus a reason.
function API.NewTicker(seconds, callback)
    local newTicker = API.Resolve("C_Timer.NewTicker")
    if not newTicker then
        return nil, "C_Timer.NewTicker unavailable"
    end
    return newTicker(seconds, callback)
end

function API.Now()
    return GetTime()
end

function API.Time()
    return time()
end

function API.InCombat()
    if not isFunction(InCombatLockdown) then
        return false
    end
    return InCombatLockdown() and true or false
end

-- /played: asks the server for the character's total time in the game.
-- The answer arrives as TIME_PLAYED_MSG(totalSeconds, levelSeconds). Chat
-- frames normally print it; with `quiet` the event is taken away from the
-- chat frames for this request (only those that had it). Returns true and
-- the list of muted frames (give it to API.RestoreChatEvent later), or nil
-- plus a reason. Standard client function, not yet checked in Forever.
function API.RequestTimePlayed(quiet)
    local request = API.Resolve("RequestTimePlayed")
    if not request then
        return nil, "RequestTimePlayed unavailable"
    end
    local muted = {}
    if quiet then
        for i = 1, (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS or 10) do
            local frame = _G["ChatFrame" .. i]
            if type(frame) == "table" and frame.IsEventRegistered
                and frame:IsEventRegistered("TIME_PLAYED_MSG") then
                frame:UnregisterEvent("TIME_PLAYED_MSG")
                muted[#muted + 1] = frame
            end
        end
    end
    local ok, err = pcall(request)
    if not ok then
        API.RestoreChatEvent(muted, "TIME_PLAYED_MSG")
        return nil, tostring(err)
    end
    return true, muted
end

-- Gives an event back to the frames muted above.
function API.RestoreChatEvent(frames, event)
    for _, frame in ipairs(frames or {}) do
        pcall(frame.RegisterEvent, frame, event)
    end
end

-- True when the character is marked AFK. UnitIsAFK is a standard client
-- function, not yet checked in Forever: if it is missing or returns a
-- secret value, the character is treated as not AFK (see
-- API_COMPATIBILITY.md, "Пассивная съёмка").
function API.IsAFK()
    local isAFK = API.Resolve("UnitIsAFK")
    if not isAFK then
        return false
    end
    local value = isAFK("player")
    if API.IsSecret(value) then
        return false
    end
    return value and true or false
end

function API.PlayerLevel()
    return call("UnitLevel", "player")
end

function API.PlayerName()
    local name = call("UnitName", "player")
    if type(name) ~= "string" or API.IsSecret(name) then
        return nil
    end
    return name
end

-- Class file name ("DRUID") or nil.
function API.PlayerClass()
    local _, classFile = call("UnitClass", "player")
    if type(classFile) ~= "string" or API.IsSecret(classFile) then
        return nil
    end
    return classFile
end

function API.RealmName()
    local realm = call("GetRealmName")
    if type(realm) ~= "string" or API.IsSecret(realm) then
        return nil
    end
    return realm
end

-- Player GUID as a plain string, or nil (missing or secret).
function API.PlayerGUID()
    local guid = call("UnitGUID", "player")
    if type(guid) ~= "string" or API.IsSecret(guid) or guid == "" then
        return nil
    end
    return guid
end

-- Storage key of the current character: "Realm:Name".
-- Why not the GUID: see API_COMPATIBILITY.md ("Идентификация персонажа").
function API.CharacterKey()
    local name, realm = API.PlayerName(), API.RealmName()
    if not name or not realm then
        return nil
    end
    return realm .. ":" .. name
end

function API.ZoneName()
    local zone = call("GetRealZoneText")
    if type(zone) ~= "string" or zone == "" or API.IsSecret(zone) then
        return nil
    end
    return zone
end

-- Stable zone map ID: climbs from sub-maps (dungeon floors, micro maps) to
-- the zone map. Returns nil if the client cannot tell.
function API.ZoneMapID()
    local mapID = call("C_Map.GetBestMapForUnit", "player")
    if not plainNumber(mapID) then
        return nil
    end
    local getInfo = API.Resolve("C_Map.GetMapInfo")
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _ = 1, 5 do
        local info = getInfo and getInfo(mapID)
        if not info or not info.mapType or info.mapType <= zoneType
            or not info.parentMapID or info.parentMapID == 0 then
            break
        end
        mapID = info.parentMapID
    end
    return mapID
end

-- Stable key for "first visit": map ID if known, otherwise the zone name.
function API.ZoneKey()
    local mapID = API.ZoneMapID()
    if mapID then
        return "map:" .. mapID
    end
    local name = API.ZoneName()
    return name and ("zone:" .. name) or nil
end

-- "none", "party", "raid", "pvp", "arena", "scenario" or nil.
function API.InstanceType()
    local _, instanceType = call("IsInInstance")
    if type(instanceType) ~= "string" or API.IsSecret(instanceType) then
        return nil
    end
    return instanceType
end

function API.IsInGuild()
    return call("IsInGuild") and true or false
end

-- Guild name or nil (not in a guild, or the client has not loaded it yet).
function API.GuildName()
    local name = call("GetGuildInfo", "player")
    if type(name) ~= "string" or name == "" or API.IsSecret(name) then
        return nil
    end
    return name
end

function API.GetLocale()
    return call("GetLocale") or "enUS"
end

-- Item quality (0..8) from an item link, or nil.
function API.ItemQuality(link)
    local byID = API.Resolve("C_Item.GetItemQualityByID")
    if byID then
        local ok, quality = pcall(byID, link)
        if ok and plainNumber(quality) then
            return quality
        end
    end
    -- Modern links: |cnIQ4:...; older links: |cffa335ee...
    local iq = string.match(link, "|cnIQ(%d):")
    if iq then
        return tonumber(iq)
    end
    local color = string.match(link, "|c(%x%x%x%x%x%x%x%x)")
    local byColor = { ff0070dd = 3, ffa335ee = 4, ffff8000 = 5 }
    return color and byColor[string.lower(color)] or nil
end

---------------------------------------------------------------------------
-- Movement (Step Tracker). All distances are in yards, the unit of
-- UnitPosition and GetUnitSpeed (warcraft.wiki.gg, 2026-11-24).
---------------------------------------------------------------------------

-- Own movement speed (yards per second), or nil when unknown or secret.
-- On a boat or a zeppelin this is the player's own speed, not the boat's.
function API.UnitSpeed()
    local current = call("GetUnitSpeed", "player")
    if not plainNumber(current) then
        return nil
    end
    return current
end

-- Movement that must never count as steps. Returns a reason or nil.
-- `known` is false when a needed client function is missing: then the
-- state cannot be excluded reliably and nothing is counted.
function API.MovementExclusion()
    local checks = {
        { "UnitOnTaxi", "taxi", "player" },
        { "UnitInVehicle", "vehicle", "player" },
        { "IsFlying", "flying" },
        { "IsSwimming", "swimming" },
    }
    for _, check in ipairs(checks) do
        local fn = API.Resolve(check[1])
        if not fn then
            return "missing:" .. check[1]
        end
        local value = fn(check[3])
        if API.IsSecret(value) then
            return "secret:" .. check[1]
        end
        if value then
            return check[2]
        end
    end
    return nil
end

-- World position in yards with the id of its coordinate space, or nil.
-- Two positions can be compared only if their `space` is equal.
--   1) UnitPosition: instance coordinates (nil inside instances).
--   2) Map position converted to continent coordinates.
function API.WorldPosition()
    local y, x, _, instanceID = call("UnitPosition", "player")
    if plainNumber(x) and plainNumber(y) and plainNumber(instanceID) then
        return "i" .. instanceID, x, y, "UnitPosition"
    end
    local mapID = call("C_Map.GetBestMapForUnit", "player")
    if not plainNumber(mapID) then
        return nil
    end
    local position = call("C_Map.GetPlayerMapPosition", mapID, "player")
    if type(position) ~= "table" or not position.GetXY then
        return nil
    end
    local toWorld = API.Resolve("C_Map.GetWorldPosFromMapPos")
    if not toWorld then
        return nil
    end
    local ok, continentID, world = pcall(toWorld, mapID, position)
    if not ok or not plainNumber(continentID) or type(world) ~= "table" or not world.GetXY then
        return nil
    end
    local wx, wy = world:GetXY()
    if not plainNumber(wx) or not plainNumber(wy) then
        return nil
    end
    return "c" .. continentID, wx, wy, "MapPosition"
end

---------------------------------------------------------------------------
-- Interface helpers
---------------------------------------------------------------------------

-- Texture and coordinates of the class icon, or nil.
function API.ClassIcon(classFile)
    local coords = type(CLASS_ICON_TCOORDS) == "table" and classFile and CLASS_ICON_TCOORDS[classFile]
    if type(coords) ~= "table" then
        return nil
    end
    return "Interface\\TargetingFrame\\UI-Classes-Circles", coords
end

function API.PlaySuccessSound()
    if isFunction(PlaySound) and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- Reloads the interface; the client writes SavedVariables first.
function API.ReloadUI()
    local reload = API.Resolve("ReloadUI")
    if not reload then
        return nil, "ReloadUI unavailable"
    end
    local ok, err = pcall(reload)
    if not ok then
        return nil, tostring(err)
    end
    return true
end

function API.Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffC9A35EForeverMemories|r: " .. tostring(message))
    end
end
