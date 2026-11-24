-- UI/Settings.lua
-- "Settings" tab (v0.10.0): four inner pages under one row of buttons,
--   General   - interface and notifications (this file)
--   Data      - saved characters, export, backup, import (SettingsData.lua)
--   About     - project, community links, diagnostics (SettingsAbout.lua)
--   Changelog - history of updates from CHANGELOG.md (SettingsAbout.lua)
-- Pages are built when first opened. Diagnostics in chat stay in
-- /fm status, /fm debug and /fm log.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

UI.SETTINGS_PAGES = { "general", "data", "about", "changelog" }
UI.settingsPages = {} -- builders: id -> function(parent) -> view
UI.SETTINGS_PAGE_TOP = 38

local SCALE_MIN, SCALE_MAX, SCALE_STEP = ns.Database.SETTINGS.scale.min, ns.Database.SETTINGS.scale.max, 0.05

local function settingCheck(parent, key, label, tip, after)
    local check = W.Check(parent, label,
        function() return ns.db.settings[key] end,
        function(value)
            ns.db.settings[key] = value
            if after then after(value) end
        end, UI.CONTENT_WIDTH)
    return W.Tooltip(check, tip)
end

-- Language: saved at once; a reload is offered, never forced.
local function setLanguage(value)
    local before = ns.activeLocaleCode
    ns.db.settings.locale = value
    if ns.ResolveLocaleCode(value) ~= before then
        UI.ConfirmReload(L.RELOAD_FOR_LANGUAGE)
    end
end

UI.settingsPages.general = function(parent)
    local width = UI.CONTENT_WIDTH
    local interface = W.Heading(parent, L.SET_INTERFACE)
    interface:SetPoint("TOPLEFT", 0, 0)

    local languageLabel = W.Text(parent, L.SET_LANGUAGE)
    languageLabel:SetPoint("TOPLEFT", 0, -36)
    local language = W.Dropdown(parent, {
        { value = "auto", text = L.LANGUAGE_AUTO },
        { value = "enUS", text = "English" },
        { value = "ruRU", text = "Русский" },
    }, function() return ns.db.settings.locale end, setLanguage, 200)
    language:SetPoint("TOPRIGHT", 0, -30)
    W.Tooltip(language, L.TIP_SET_LANGUAGE, L.SET_LANGUAGE)

    local scaleLabel = W.Text(parent, L.SET_SCALE)
    scaleLabel:SetPoint("TOPLEFT", 0, -72)
    local scaleValue = W.Text(parent, "", "GameFontNormal", W.COLORS.heading)
    scaleValue:SetPoint("TOPRIGHT", 0, -72)
    scaleValue:SetJustifyH("RIGHT")
    local function showScale()
        scaleValue:SetText(math.floor(ns.db.settings.scale * 100 + 0.5) .. "%")
    end
    local slider = W.Slider(parent, width - 20, SCALE_MIN, SCALE_MAX, SCALE_STEP,
        function() return ns.db.settings.scale end,
        function(value)
            ns.db.settings.scale = ns.Util.Clamp(value, SCALE_MIN, SCALE_MAX, 1)
            showScale()
            UI.ApplyScale()
        end)
    slider:SetPoint("TOPLEFT", 10, -96)
    W.Tooltip(slider, L.TIP_SET_SCALE, L.SET_SCALE)

    local checks = {
        settingCheck(parent, "minimap", L.SET_MINIMAP, L.TIP_SET_MINIMAP, function() ns.Minimap.Update() end),
        settingCheck(parent, "rememberTab", L.SET_REMEMBER_TAB, L.TIP_SET_REMEMBER_TAB),
    }
    checks[1]:SetPoint("TOPLEFT", 0, -126)
    checks[2]:SetPoint("TOPLEFT", 0, -154)

    local position = W.Button(parent, L.RESET_POSITION, width, 28, function()
        UI.ResetPosition()
    end)
    position:SetPoint("TOPLEFT", 0, -186)
    W.Tooltip(position, L.TIP_RESET_POSITION, L.RESET_POSITION)

    local line = W.Divider(parent)
    line:SetPoint("TOPLEFT", 0, -228)
    line:SetPoint("TOPRIGHT", 0, -228)

    local notifications = W.Heading(parent, L.SET_NOTIFICATIONS_BLOCK)
    notifications:SetPoint("TOPLEFT", 0, -242)
    checks[3] = settingCheck(parent, "notifications", L.SET_NOTIFICATIONS, L.TIP_SET_NOTIFICATIONS)
    checks[4] = settingCheck(parent, "sound", L.SET_SOUND, L.TIP_SET_SOUND)
    checks[3]:SetPoint("TOPLEFT", 0, -272)
    checks[4]:SetPoint("TOPLEFT", 0, -300)

    local durationLabel = W.Text(parent, L.SET_TOAST_DURATION)
    durationLabel:SetPoint("TOPLEFT", 0, -338)
    local duration = W.Segmented(parent, {
        { 3, string.format(L.SECONDS_SHORT, 3) },
        { 5, string.format(L.SECONDS_SHORT, 5) },
        { 10, string.format(L.SECONDS_SHORT, 10) },
    }, 200, function(value)
        ns.db.settings.toastDuration = value
    end)
    duration:SetPoint("TOPRIGHT", 0, -332)
    W.Tooltip(durationLabel, L.TIP_SET_TOAST_DURATION, L.SET_TOAST_DURATION)

    local test = W.Button(parent, L.TEST_NOTIFICATION, width, 28, function()
        ns.Notifications.Test()
    end)
    test:SetPoint("TOPLEFT", 0, -370)
    W.Tooltip(test, L.TIP_TEST_NOTIFICATION, L.TEST_NOTIFICATION)

    local defaults = W.Button(parent, L.RESTORE_DEFAULTS, width, 28, function()
        UI.Confirm(L.CONFIRM_RESTORE_DEFAULTS, L.RESTORE, function()
            local before = ns.activeLocaleCode
            ns.Database.ResetGeneral(ns.db)
            ns.Minimap.Update()
            UI.ResetPosition()
            UI.ApplyScale()
            parent:Refresh()
            if ns.ResolveLocaleCode(ns.db.settings.locale) ~= before then
                UI.ConfirmReload(L.RELOAD_FOR_LANGUAGE)
            end
        end)
    end)
    defaults:SetPoint("TOPLEFT", 0, -416)
    W.Tooltip(defaults, L.TIP_RESTORE_DEFAULTS, L.RESTORE_DEFAULTS)

    function parent:Refresh()
        for _, check in ipairs(checks) do
            check:Refresh()
        end
        language:Refresh()
        slider:Refresh()
        showScale()
        duration:SetValue(ns.db.settings.toastDuration)
    end
    return { Refresh = function() parent:Refresh() end }
end

---------------------------------------------------------------------------
-- The tab: a row of four page buttons and the selected page.
---------------------------------------------------------------------------
UI.builders.settings = function(parent)
    local pages, buttons = {}, {}
    local current = "general"
    local gap = 6
    local count = #UI.SETTINGS_PAGES
    local width = (UI.CONTENT_WIDTH - gap * (count - 1)) / count

    local function select(id)
        current = UI.settingsPages[id] and id or "general"
        if not pages[current] then
            local frame = CreateFrame("Frame", nil, parent)
            frame:SetPoint("TOPLEFT", 0, -UI.SETTINGS_PAGE_TOP)
            frame:SetPoint("BOTTOMRIGHT", 0, 0)
            frame.view = UI.settingsPages[current](frame) or {}
            pages[current] = frame
        end
        for key, frame in pairs(pages) do
            frame:SetShown(key == current)
        end
        for key, button in pairs(buttons) do
            button:SetSelected(key == current)
        end
        if current == "changelog" then
            UI.MarkChangelogSeen()
        end
        local view = pages[current].view
        if view.Refresh then
            ns.SafeCall("settings " .. current, view.Refresh)
        end
    end
    for i, id in ipairs(UI.SETTINGS_PAGES) do
        local button = W.Button(parent, L["SETTINGS_" .. string.upper(id)], width, 28, function() select(id) end)
        button:SetPoint("TOPLEFT", (i - 1) * (width + gap), 0)
        buttons[id] = button
    end
    return {
        Select = function(id) current = UI.settingsPages[id] and id or current end,
        Refresh = function() select(current) end,
        Current = function() return current end,
    }
end
