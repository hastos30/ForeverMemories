-- UI/Settings.lua
-- "Settings" tab (spec 8): minimap button, notifications, sound, language,
-- window scale and "reset window position". Nothing technical: diagnostics
-- stay in /fm status, /fm debug and /fm log.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.75, 1.3, 0.05

local function settingCheck(parent, key, label, tip, after)
    local check = W.Check(parent, label,
        function() return ns.db.settings[key] end,
        function(value)
            ns.db.settings[key] = value
            if after then after(value) end
        end, UI.CONTENT_WIDTH)
    return W.Tooltip(check, tip)
end

UI.builders.settings = function(parent)
    local heading = W.Heading(parent, L.GENERAL_SETTINGS)
    heading:SetPoint("TOPLEFT", 0, 0)
    local checks = {
        settingCheck(parent, "minimap", L.SET_MINIMAP, L.TIP_SET_MINIMAP, function() ns.Minimap.Update() end),
        settingCheck(parent, "notifications", L.SET_NOTIFICATIONS, L.TIP_SET_NOTIFICATIONS),
        settingCheck(parent, "sound", L.SET_SOUND, L.TIP_SET_SOUND),
    }
    for i, check in ipairs(checks) do
        check:SetPoint("TOPLEFT", 0, -30 - (i - 1) * 32)
    end
    local line = W.Divider(parent)
    line:SetPoint("TOPLEFT", 0, -130)
    line:SetPoint("TOPRIGHT", 0, -130)

    -- Language: saved at once; a reload is offered, never forced.
    local languageLabel = W.Text(parent, L.SET_LANGUAGE)
    languageLabel:SetPoint("TOPLEFT", 0, -152)
    local language = W.Dropdown(parent, {
        { value = "auto", text = L.LANGUAGE_AUTO },
        { value = "enUS", text = "English" },
        { value = "ruRU", text = "Русский" },
    }, function() return ns.db.settings.locale end, function(value)
        local before = ns.activeLocaleCode
        ns.db.settings.locale = value
        if ns.ResolveLocaleCode(value) ~= before then
            UI.ConfirmReload(L.RELOAD_FOR_LANGUAGE)
        end
    end, 170)
    language:SetPoint("TOPRIGHT", 0, -146)
    W.Tooltip(language, L.TIP_SET_LANGUAGE, L.SET_LANGUAGE)

    local scaleLabel = W.Text(parent, L.SET_SCALE)
    scaleLabel:SetPoint("TOPLEFT", 0, -196)
    local scaleValue = W.Text(parent, "", "GameFontNormal", W.COLORS.heading)
    scaleValue:SetPoint("TOPRIGHT", 0, -196)
    scaleValue:SetJustifyH("RIGHT")
    local slider = W.Slider(parent, UI.CONTENT_WIDTH - 20, SCALE_MIN, SCALE_MAX, SCALE_STEP,
        function() return ns.db.settings.scale end,
        function(value)
            ns.db.settings.scale = ns.Util.Clamp(value, SCALE_MIN, SCALE_MAX, 1)
            scaleValue:SetText(math.floor(ns.db.settings.scale * 100 + 0.5) .. "%")
            UI.ApplyScale()
        end)
    slider:SetPoint("TOPLEFT", 10, -224)
    W.Tooltip(slider, L.TIP_SET_SCALE, L.SET_SCALE)

    local reset = W.Button(parent, L.RESET_POSITION, UI.CONTENT_WIDTH, 30, function()
        UI.ResetPosition()
    end)
    reset:SetPoint("TOPLEFT", 0, -266)
    W.Tooltip(reset, L.TIP_RESET_POSITION, L.RESET_POSITION)

    function parent:Refresh()
        for _, check in ipairs(checks) do
            check:Refresh()
        end
        language:Refresh()
        slider:Refresh()
        scaleValue:SetText(math.floor(ns.db.settings.scale * 100 + 0.5) .. "%")
    end
    return { Refresh = function() parent:Refresh() end }
end
