-- Core/Init.lua
-- Namespace, the single event dispatcher, localization and startup order.
local addonName, ns = ...

ns.name = addonName
ns.version = "1.0.0-beta.16"

-- Our own frames (the window). They are hidden while a screenshot is
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

-- Locale code for a setting value ("auto" = the game client language).
function ns.ResolveLocaleCode(code)
    if code == nil or code == "auto" then
        code = ns.API.GetLocale()
    end
    return ns.locales[code] and code or "enUS"
end

function ns.ResolveLocale(code)
    return ns.locales[ns.ResolveLocaleCode(code)]
end

-- Strings are read once at load, so a change is visible after a UI reload.
function ns.SetLocale(code)
    ns.activeLocaleCode = ns.ResolveLocaleCode(code)
    ns.activeLocale = ns.locales[ns.activeLocaleCode]
end

-- Whole number with the separator of the active language: "12 458".
function ns.Num(value)
    return ns.Util.FormatNumber(value, ns.L.THOUSANDS_SEP)
end

-- Decimal number in the style of the active language: "3,27" / "3.27".
function ns.Dec(value, decimals)
    return ns.Util.FormatDecimal(value, decimals, ns.L.THOUSANDS_SEP, ns.L.DECIMAL_SEP)
end

-- Number with the right word form: ns.Count(1245872, "STEPS") ->
-- "1 245 872 шага" (keys STEPS_one, STEPS_few, STEPS_many).
function ns.Count(value, key)
    local form = ns.Util.PluralForm(value, ns.activeLocaleCode)
    local word = ns.L[key .. "_" .. form]
    if word == key .. "_" .. form then
        word = ns.L[key .. "_many"]
    end
    return ns.Num(value) .. " " .. word
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
    local db, repaired, status = ns.Database.Load(ForeverMemoriesDB)
    ns.loadStatus = status
    if status.incompatible or status.unsafe then
        -- Saved data is left exactly as it is (it is still what the game
        -- writes back); this session works on a scratch table.
        ns.readOnly = true
    else
        ForeverMemoriesDB = db
    end
    ns.db = db
    ns.SetLocale(db.settings.locale)
    if #repaired > 0 then
        ns.Logger.Warn("Reset damaged saved data: " .. table.concat(repaired, ", "))
    end
    if status.incompatible then
        ns.API.Print(string.format(ns.L.DB_INCOMPATIBLE, status.incompatible, ns.Database.SCHEMA_VERSION))
    elseif status.unsafe then
        ns.API.Print(string.format(ns.L.DB_UNSAFE, table.concat(status.unsafe, ", ")))
    elseif status.migrated then
        ns.Logger.Info(string.format("Migrated saved data: schema %d -> %d", status.migrated.from, status.migrated.to))
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
    local key = ns.API.CharacterKey()
    if not key then
        ns.Logger.Error("Character name or realm unavailable: history is off this session")
        return
    end
    ns.characterKey = key
    ns.character = ns.Database.Character(ns.db, key, {
        name = ns.API.PlayerName(), realm = ns.API.RealmName(),
        class = ns.API.PlayerClass(), guid = ns.API.PlayerGUID(),
    })
    for i = 1, #ns.onLogin do
        ns.SafeCall("onLogin", ns.onLogin[i])
    end
end)
