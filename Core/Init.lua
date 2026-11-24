-- Core/Init.lua
-- Namespace, the single event dispatcher, and SavedVariables loading.
local addonName, ns = ...

ns.name = addonName
ns.version = "0.0.1"

-- One frame receives every event and hands it to subscribed functions.
local dispatcher = CreateFrame("Frame")
local handlers = {}

-- Subscribes `callback(event, ...)` to an event.
-- Returns true, or false plus a reason when the client rejects the event.
function ns.On(event, callback)
    if not handlers[event] then
        local ok, reason = ns.API.RegisterFrameEvent(dispatcher, event)
        if not ok then
            return false, reason
        end
        handlers[event] = {}
    end
    local list = handlers[event]
    list[#list + 1] = callback
    return true
end

dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

-- Modules add functions here; they run once the saved data is ready.
ns.onReady = {}

ns.On("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName or ns.db then
        return
    end
    local db, repaired = ns.Database.Load(ForeverMemoriesDB)
    ForeverMemoriesDB = db
    ns.db = db
    if #repaired > 0 then
        ns.Logger.Warn("Reset damaged saved data: " .. table.concat(repaired, ", "))
    end
    ns.Logger.Info("Loaded v" .. ns.version .. ", load #" .. db.spike.loadCount)
    for i = 1, #ns.onReady do
        ns.onReady[i]()
    end
end)
