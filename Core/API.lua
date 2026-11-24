-- Core/API.lua
-- The only place that touches World of Warcraft client functions directly.
-- Every wrapper checks that the client function exists and returns a value,
-- or nil plus a reason string. Forever may differ from Retail, so nothing
-- here assumes a function is present.
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

-- True when the value is a Midnight-style secret value we must not read.
function API.IsSecret(value)
    local check = API.Resolve("issecretvalue")
    return check ~= nil and check(value) and true or false
end

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

function API.IsAFK()
    return call("UnitIsAFK", "player") and true or false
end

function API.PlayerLevel()
    return call("UnitLevel", "player")
end

function API.MaxLevel()
    return call("GetMaxPlayerLevel")
end

function API.PlayerName()
    return (call("UnitName", "player"))
end

function API.PlayerClass()
    local _, classFile = call("UnitClass", "player")
    return classFile
end

function API.CharacterKey()
    local name = API.PlayerName() or "?"
    local realm = call("GetRealmName") or "?"
    return realm .. ":" .. name
end

function API.ZoneName()
    local zone = call("GetRealZoneText")
    if type(zone) ~= "string" or zone == "" then
        return nil
    end
    return zone
end

-- Stable zone map ID: climbs from sub-maps (dungeon floors, micro maps) to
-- the zone map. Returns nil if the client cannot tell.
function API.ZoneMapID()
    local mapID = call("C_Map.GetBestMapForUnit", "player")
    if type(mapID) ~= "number" then
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

-- Player position on the current map (0..1), or nil (e.g. in instances).
function API.PlayerPosition()
    local mapID = call("C_Map.GetBestMapForUnit", "player")
    if type(mapID) ~= "number" then
        return nil
    end
    local position = call("C_Map.GetPlayerMapPosition", mapID, "player")
    if type(position) ~= "table" or not position.GetXY then
        return nil
    end
    local x, y = position:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" or API.IsSecret(x) then
        return nil
    end
    return mapID, x, y
end

function API.InInstance()
    return call("IsInInstance") and true or false
end

function API.InstanceName()
    return (call("GetInstanceInfo"))
end

function API.IsInGuild()
    return call("IsInGuild") and true or false
end

function API.GuildName()
    return (call("GetGuildInfo", "player"))
end

function API.NumShapeshiftForms()
    return call("GetNumShapeshiftForms") or 0
end

function API.GetLocale()
    return call("GetLocale") or "enUS"
end

-- Item quality (0..8) from an item link, or nil.
function API.ItemQuality(link)
    local byID = API.Resolve("C_Item.GetItemQualityByID")
    if byID then
        local ok, quality = pcall(byID, link)
        if ok and type(quality) == "number" then
            return quality
        end
    end
    -- Modern links: |cnIQ4:...; older links: |cffa335ee...
    local iq = string.match(link, "|cnIQ(%d):")
    if iq then
        return tonumber(iq)
    end
    local color = string.match(link, "|c(%x%x%x%x%x%x%x%x)")
    local byColor = { ffa335ee = 4, ffff8000 = 5 }
    return color and byColor[string.lower(color)] or nil
end

-- True while a full-screen panel is open (map, game menu, settings).
function API.IsBlockingPanelOpen()
    local names = { "WorldMapFrame", "GameMenuFrame", "SettingsPanel" }
    for _, name in ipairs(names) do
        local frame = _G[name]
        if type(frame) == "table" and frame.IsShown and frame:IsShown() then
            return true
        end
    end
    return false
end

function API.PlaySuccessSound()
    if isFunction(PlaySound) and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- Reloads the interface; the client writes SavedVariables first.
-- Not yet verified in Forever: ReloadUI() called from addon code (a click in
-- a confirmation dialog). The /reload command itself works (v0.0.1, S7).
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
