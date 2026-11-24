-- Modules/Journey.lua
-- Interval ("JOURNEY") and random ("RANDOM") shots (SPECIFICATION.md 5).
-- One 30-second ticker, only while one of them is enabled. No OnUpdate.
local _, ns = ...

local Journey = {}
ns.Journey = Journey

Journey.CHECK_EVERY = 30

local API = ns.API
local ticker
local lastJourneyAt      -- time of the last confirmed journey shot
local lastPosition       -- { mapID, x, y } of that shot
local lastZoneKey
local nextRandomAt

-- Returns nil when conditions are fine, otherwise a reason.
function Journey.BlockReason()
    if not ns.db.settings.enabled then return "paused" end
    if not ns.Engine.IsInWorld() then return "loading" end
    if API.InCombat() then return "combat" end
    if API.IsAFK() then return "afk" end
    if API.IsBlockingPanelOpen() then return "panel" end
    return nil
end

-- Has the player moved far enough since the last journey shot?
-- Falls back to a zone change, then to time only (documented limitation).
function Journey.HasMoved(threshold)
    if not lastPosition then
        return true
    end
    local mapID, x, y = API.PlayerPosition()
    if mapID and lastPosition.mapID then
        if mapID ~= lastPosition.mapID then
            return true
        end
        local dx, dy = x - lastPosition.x, y - lastPosition.y
        return math.sqrt(dx * dx + dy * dy) >= threshold
    end
    if lastZoneKey then
        return API.ZoneKey() ~= lastZoneKey
    end
    return true
end

local function randomDelay(journey)
    return math.random(journey.randomMin, journey.randomMax) * 60
end

function Journey.Check()
    local profile = ns.Profiles.Current()
    local now = API.Now()
    if Journey.BlockReason() then
        return
    end
    local journey = profile.journey
    if profile.rules.JOURNEY.enabled then
        local due = not lastJourneyAt or now - lastJourneyAt >= journey.interval * 60
        if due and Journey.HasMoved(journey.moveThreshold) then
            ns.Events.Emit("JOURNEY", "journey:" .. math.floor(now))
        end
    end
    if profile.rules.RANDOM.enabled then
        nextRandomAt = nextRandomAt or (now + randomDelay(journey))
        if now >= nextRandomAt then
            nextRandomAt = now + randomDelay(journey)
            ns.Events.Emit("RANDOM", "random:" .. math.floor(now))
        end
    end
end

-- Starts or stops the ticker to match the active profile.
function Journey.Update()
    local rules = ns.Profiles.Current().rules
    local wanted = rules.JOURNEY.enabled or rules.RANDOM.enabled
    if wanted and not ticker then
        ticker = API.NewTicker(Journey.CHECK_EVERY, function()
            ns.SafeCall("Journey", Journey.Check)
        end)
    elseif not wanted and ticker then
        ticker:Cancel()
        ticker = nil
        nextRandomAt = nil
    end
end

function Journey.IsRunning()
    return ticker ~= nil
end

-- Remember where the last confirmed journey shot was taken.
table.insert(ns.Engine.onComplete, function(entry, request)
    if entry.ok > 0 and ns.Util.Contains(request.types, "JOURNEY") then
        lastJourneyAt = API.Now()
        local mapID, x, y = API.PlayerPosition()
        lastPosition = mapID and { mapID = mapID, x = x, y = y } or nil
        lastZoneKey = API.ZoneKey()
    end
end)

table.insert(ns.onLogin, function()
    lastJourneyAt = API.Now() -- first journey shot one interval after login
    Journey.Update()
end)
table.insert(ns.Profiles.listeners, function()
    if ns.characterKey then
        Journey.Update()
    end
end)
