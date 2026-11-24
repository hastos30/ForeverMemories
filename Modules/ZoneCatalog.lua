-- Modules/ZoneCatalog.lua
-- World Explorer (v0.9.0): the catalog of open-world zones and capitals of
-- World of Warcraft: Forever and the exploration progress of the current
-- character.
--
-- Catalog: a static list of AreaTable IDs, checked on 2026-11-24 against
-- three community catalogs of Forever 1.60.1 (see API_COMPATIBILITY.md,
-- "v0.9.0: каталог зон"). The IDs are stable and do not depend on the
-- language. Names come from the client (C_Map.GetAreaInfo) in its own
-- language. An ID the client does not know is left out, so every count
-- is computed, never typed in.
--
-- Visits are stored by zone key (map ID, Locations.lua). A key is linked
-- to a catalog zone through the client's own name of that zone, read in
-- the same language in the same session; the identity is the area ID.
-- Dungeons, raids and battlegrounds are not in the catalog and never
-- count. Progress = zones whose visit ForeverMemories registered, not the
-- map's fog of war.
local _, ns = ...

local ZoneCatalog = {}
ns.ZoneCatalog = ZoneCatalog

local API = ns.API

-- { AreaTable ID, English name } per region. English names are used only
-- when the client cannot name an area (enUS client) and for /fm zones.
ZoneCatalog.REGIONS = {
    { id = "EK", label = "REGION_EK", zones = {
        { 36, "Alterac Mountains" }, { 45, "Arathi Highlands" }, { 3, "Badlands" },
        { 4, "Blasted Lands" }, { 46, "Burning Steppes" }, { 41, "Deadwind Pass" },
        { 1, "Dun Morogh" }, { 10, "Duskwood" }, { 139, "Eastern Plaguelands" },
        { 12, "Elwynn Forest" }, { 267, "Hillsbrad Foothills" }, { 1537, "Ironforge" },
        { 38, "Loch Modan" }, { 44, "Redridge Mountains" }, { 16591, "Riverglades" },
        { 16756, "Ruins of Gilneas" }, { 51, "Searing Gorge" }, { 130, "Silverpine Forest" },
        { 1519, "Stormwind City" }, { 33, "Stranglethorn Vale" }, { 8, "Swamp of Sorrows" },
        { 47, "The Hinterlands" }, { 85, "Tirisfal Glades" }, { 1497, "Undercity" },
        { 28, "Western Plaguelands" }, { 40, "Westfall" }, { 11, "Wetlands" },
    } },
    { id = "KALIMDOR", label = "REGION_KALIMDOR", zones = {
        { 331, "Ashenvale" }, { 16, "Azshara" }, { 148, "Darkshore" }, { 1657, "Darnassus" },
        { 405, "Desolace" }, { 14, "Durotar" }, { 15, "Dustwallow Marsh" }, { 361, "Felwood" },
        { 357, "Feralas" }, { 493, "Moonglade" }, { 616, "Mount Hyjal" }, { 215, "Mulgore" },
        { 1637, "Orgrimmar" }, { 16651, "Shen'dralas" }, { 1377, "Silithus" },
        { 406, "Stonetalon Mountains" }, { 440, "Tanaris" }, { 141, "Teldrassil" },
        { 17, "The Barrens" }, { 400, "Thousand Needles" }, { 1638, "Thunder Bluff" },
        { 490, "Un'Goro Crater" }, { 618, "Winterspring" },
    } },
    -- A separate starting island (all three catalogs list it apart from
    -- both continents). Its region name is the zone name from the client.
    { id = "ZEPHRAS", area = 16593, zones = { { 16593, "Zephras Isle" } } },
}

local resolved   -- { status, regions, byName, missing } for this session
local keyCache = {}

-- Reads the zone names from the client once per session.
--   status "client"  - names from C_Map.GetAreaInfo (any language)
--          "english" - no GetAreaInfo, English client: English names
--          "unavailable" - names cannot be confirmed; no percentage shown
local function fallbackStatus()
    return API.GetLocale() == "enUS" and "english" or "unavailable"
end

local function build(status)
    local result = { status = status, regions = {}, byName = {}, missing = {}, found = 0 }
    for _, region in ipairs(ZoneCatalog.REGIONS) do
        local zones = {}
        for _, z in ipairs(region.zones) do
            local name
            if status == "client" then
                name = API.AreaName(z[1])
            else
                name = z[2]
            end
            if name then
                local zone = { area = z[1], name = name, english = z[2] }
                zones[#zones + 1] = zone
                result.byName[name] = zone
                result.found = result.found + 1
            else
                result.missing[#result.missing + 1] = z[2] .. " (" .. z[1] .. ")"
            end
        end
        table.sort(zones, function(a, b) return a.name < b.name end)
        local name = region.label and ns.L[region.label]
            or (status == "client" and API.AreaName(region.area)) or region.zones[1][2]
        result.regions[#result.regions + 1] = { id = region.id, name = name, zones = zones }
    end
    return result
end

function ZoneCatalog.Resolve()
    if resolved then
        return resolved
    end
    local _, why = API.AreaName(ZoneCatalog.REGIONS[1].zones[1][1])
    local result = build(why == "missing" and fallbackStatus() or "client")
    if result.status == "client" and result.found == 0 then
        -- The client knows none of these IDs: they are not its IDs, so
        -- only the English names can still be trusted (enUS client).
        result = build(fallbackStatus())
    end
    resolved = result
    keyCache = {}
    return result
end

-- Forget the names (tests; a language change applies after /reload anyway).
function ZoneCatalog.Reset()
    resolved, keyCache = nil, {}
end

-- Catalog zone of a visit key ("map:1429", "zone:Elwynn Forest"), or false.
function ZoneCatalog.ZoneOfKey(key, knownName)
    local catalog = ZoneCatalog.Resolve()
    if keyCache[key] ~= nil then
        return keyCache[key]
    end
    local zone = knownName and catalog.byName[knownName]
    if not zone then
        local mapID = tonumber(string.match(key, "^map:(%d+)$"))
        local name = mapID and API.MapName(mapID) or string.match(key, "^zone:(.+)$")
        zone = name and catalog.byName[name]
    end
    keyCache[key] = zone or false
    return keyCache[key]
end

-- Names the day logs recorded for each key (the client's own zone text).
local function namesOfKeys(character)
    local names = {}
    for _, zones in pairs(character.locations and character.locations.days or {}) do
        for key, entry in pairs(zones) do
            names[key] = names[key] or entry.name
        end
    end
    return names
end

-- Exploration of the current character:
--   { status, complete, visited, total, percent (nil if not confirmed),
--     regions = { { id, name, visited, total, percent, zones = {
--         { area, name, visited, firstAt } } } } }
function ZoneCatalog.Explorer()
    local catalog = ZoneCatalog.Resolve()
    local character = ns.character or {}
    local names = namesOfKeys(character)
    local visits = {} -- area -> earliest registered visit time (or true)
    for key in pairs(character.visited or {}) do
        local zone = ZoneCatalog.ZoneOfKey(key, names[key])
        if zone then
            local at = character.visitedAt and character.visitedAt[key]
            local before = visits[zone.area]
            if not before or before == true or (at and at < before) then
                visits[zone.area] = at or before or true
            end
        end
    end
    local result = { status = catalog.status, complete = catalog.status ~= "unavailable",
                     visited = 0, total = 0, regions = {} }
    for _, region in ipairs(catalog.regions) do
        local r = { id = region.id, name = region.name, visited = 0, total = #region.zones, zones = {} }
        for _, zone in ipairs(region.zones) do
            local seen = visits[zone.area]
            r.zones[#r.zones + 1] = {
                area = zone.area, name = zone.name, visited = seen ~= nil,
                firstAt = type(seen) == "number" and seen or nil,
            }
            if seen then
                r.visited = r.visited + 1
            end
        end
        r.percent = r.total > 0 and r.visited / r.total * 100 or 0
        if r.total > 0 then
            result.regions[#result.regions + 1] = r
        end
        result.visited = result.visited + r.visited
        result.total = result.total + r.total
    end
    if result.complete and result.total > 0 then
        result.percent = result.visited / result.total * 100
    end
    return result
end

-- Region of the zone the character stands in (to open it first), or nil.
function ZoneCatalog.CurrentRegion()
    local key = API.ZoneKey()
    local zone = key and ZoneCatalog.ZoneOfKey(key, API.ZoneName())
    if not zone then
        return nil
    end
    for _, region in ipairs(ZoneCatalog.Resolve().regions) do
        for _, z in ipairs(region.zones) do
            if z == zone then
                return region.id
            end
        end
    end
end

-- Lines for /fm zones: what the client says about every catalog zone.
function ZoneCatalog.Dump()
    local catalog = ZoneCatalog.Resolve()
    local lines = { "status " .. catalog.status .. ", locale " .. tostring(API.GetLocale()) }
    for _, region in ipairs(catalog.regions) do
        lines[#lines + 1] = region.name .. ": " .. #region.zones
        for _, zone in ipairs(region.zones) do
            lines[#lines + 1] = string.format("  %d %s / %s", zone.area, zone.name, zone.english)
        end
    end
    lines[#lines + 1] = "missing in client: " .. (#catalog.missing == 0 and "-" or table.concat(catalog.missing, ", "))
    local key = API.ZoneKey()
    lines[#lines + 1] = string.format("here: key %s, zone %s, map %s, in catalog %s", tostring(key),
        tostring(API.ZoneName()), tostring(key and API.MapName(tonumber(string.match(key, "%d+") or ""))),
        tostring(key and ZoneCatalog.ZoneOfKey(key, API.ZoneName()) and true or false))
    return lines
end
