-- Core/Init.lua
-- Namespace, the single event dispatcher, localization and startup order.
local addonName, ns = ...

ns.name = addonName
ns.version = "0.4.1-beta"

-- Our own frames (window, panels). They are hidden while a screenshot is
-- taken so they never appear in a memory.
ns.ownFrames = {}

---------------------------------------------------------------------------
-- Event dispatcher: one frame receives every event.
---------------------------------------------------------------------------
local dispatcher = CreateFrame("Frame")
local handlers = {}

-- Subscribes `callback(event, ...)`. Returns true, or false plus a reason
-- when the client rejects the event (unknown in this build).
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

-- Runs a function and logs instead of breaking the whole addon on error.
function ns.SafeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        ns.Logger.Error(label .. ": " .. tostring(err))
    end
    return ok
end

dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(event, list[i], event, ...)
    end
end)

---------------------------------------------------------------------------
-- Localization: Locales/*.lua fill ns.locales; ns.L falls back to English,
-- then to the key itself, so a missing string never causes an error.
---------------------------------------------------------------------------
ns.locales = {}
ns.L = setmetatable({}, {
    __index = function(_, key)
        local active = ns.activeLocale
        local english = ns.locales.enUS
        return (active and active[key]) or (english and english[key]) or key
    end,
})

-- Locale table for a setting value ("auto" = the game client language).
function ns.ResolveLocale(code)
    if code == nil or code == "auto" then
        code = ns.API.GetLocale()
    end
    return ns.locales[code] or ns.locales.enUS
end

-- Strings are read once at load, so a change is visible after a UI reload.
function ns.SetLocale(code)
    ns.activeLocale = ns.ResolveLocale(code)
end

---------------------------------------------------------------------------
-- Startup: onReady runs when saved data is loaded, onLogin when the
-- character is known (name, realm, level).
---------------------------------------------------------------------------
ns.onReady = {}
ns.onLogin = {}

ns.On("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName or ns.db then
        return
    end
    local db, repaired = ns.Database.Load(ForeverMemoriesDB)
    ForeverMemoriesDB = db
    ns.db = db
    ns.SetLocale(db.settings.locale)
    if #repaired > 0 then
        ns.Logger.Warn("Reset damaged saved data: " .. table.concat(repaired, ", "))
    end
    ns.Logger.Info("Loaded v" .. ns.version)
    for i = 1, #ns.onReady do
        ns.SafeCall("onReady", ns.onReady[i])
    end
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db then
        return
    end
    ns.characterKey = ns.API.CharacterKey()
    ns.character = ns.Database.Character(ns.db, ns.characterKey)
    for i = 1, #ns.onLogin do
        ns.SafeCall("onLogin", ns.onLogin[i])
    end
end)
