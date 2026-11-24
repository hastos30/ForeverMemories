-- UI/Settings.lua
-- Tabs: Capture, Journey, Profiles, Settings.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local function current()
    return ns.Profiles.Current()
end

local function settingCheck(parent, label, tip, key, after)
    return W.Tooltip(W.Check(parent, label,
        function() return ns.db.settings[key] end,
        function(value)
            ns.db.settings[key] = value
            if after then after(value) end
        end), tip)
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------
UI.builders.capture = function(parent)
    local column = W.Column(parent, 16, 16)
    column:Add(W.Heading(parent, L.MANUAL_SHOT), 26)
    column:Add(W.Tooltip(W.Dropdown(parent, L.FIELD_MODE, {
            { value = "normal", text = L.MODE_normal },
            { value = "clean", text = L.MODE_clean },
            { value = "dual", text = L.MODE_dual },
        },
        function() return current().rules.MANUAL.mode end,
        function(value) ns.Profiles.SetRule("MANUAL", "mode", value) end), L.TIP_FIELD_MODE))
    column:Add(W.Tooltip(W.Stepper(parent, L.FIELD_FRAMES, ns.Registry.FIELDS.frames,
        function() return current().rules.MANUAL.frames end,
        function(value) ns.Profiles.SetRule("MANUAL", "frames", value) end), L.TIP_FIELD_FRAMES))
    column:Add(W.Tooltip(W.Dropdown(parent, L.MANUAL_TIMER, {
            { value = 0, text = L.TIMER_OFF }, { value = 3, text = "3 s" },
            { value = 5, text = "5 s" }, { value = 10, text = "10 s" },
        },
        function() return ns.db.settings.manualTimer end,
        function(value) ns.db.settings.manualTimer = value end), L.TIP_MANUAL_TIMER))
    column:Space(8)
    column:Add(W.Heading(parent, L.SAFETY), 26)
    column:Add(settingCheck(parent, L.CLEAN_ALLOWED, L.TIP_CLEAN_ALLOWED, "cleanAllowed"))
    local cleanNote = column:Add(W.Text(parent, L.CLEAN_NOTE, "GameFontHighlightSmall"), 30, 28)
    cleanNote:SetWidth(560)
    column:Space(4)
    column:Add(W.Heading(parent, L.LIMITS), 26)
    local limitLabels = { perHour = L.LIMIT_PER_HOUR, perSession = L.LIMIT_PER_SESSION, journeyPerHour = L.LIMIT_JOURNEY }
    local limitTips = { perHour = L.TIP_LIMIT_PER_HOUR, perSession = L.TIP_LIMIT_PER_SESSION, journeyPerHour = L.TIP_LIMIT_JOURNEY }
    for _, field in ipairs({ "perHour", "perSession", "journeyPerHour" }) do
        column:Add(W.Tooltip(W.Stepper(parent, limitLabels[field], ns.Profiles.LIMIT_FIELDS[field],
            function() return current().limits[field] end,
            function(value) ns.Profiles.SetLimit(field, value) end), limitTips[field]))
    end
    column:Space(10)
    local test = W.Button(parent, L.TEST_SHOT, 160, function() ns.Engine.SubmitManual() end)
    W.Tooltip(test, L.TIP_TEST_SHOT, L.TEST_SHOT)
    column:Add(test, 26)
    local panel = W.Button(parent, L.MANUAL_PANEL, 160, function() ns.ManualPanel.Toggle() end)
    W.Tooltip(panel, L.TIP_MANUAL_PANEL, L.MANUAL_PANEL)
    panel:SetPoint("LEFT", test, "RIGHT", 10, 0)
    return { Refresh = function() column:Refresh() end }
end

---------------------------------------------------------------------------
-- Journey
---------------------------------------------------------------------------
UI.builders.journey = function(parent)
    local column = W.Column(parent, 16, 16)
    local function journeyStepper(field, label, tip, suffix)
        return column:Add(W.Tooltip(W.Stepper(parent, label, ns.Profiles.JOURNEY_FIELDS[field],
            function() return current().journey[field] end,
            function(value) ns.Profiles.SetJourney(field, value) end, suffix), tip))
    end
    column:Add(W.Heading(parent, L.TRIGGER_JOURNEY), 26)
    column:Add(W.Tooltip(W.Check(parent, L.ENABLED,
        function() return current().rules.JOURNEY.enabled end,
        function(value) ns.Profiles.SetRule("JOURNEY", "enabled", value) end),
        L.TIP_JOURNEY_ENABLED, L.TRIGGER_JOURNEY))
    journeyStepper("interval", L.JOURNEY_INTERVAL, L.TIP_JOURNEY_INTERVAL, " min")
    journeyStepper("moveThreshold", L.JOURNEY_MOVE, L.TIP_JOURNEY_MOVE)
    column:Add(W.Tooltip(W.Stepper(parent, L.LIMIT_JOURNEY, ns.Profiles.LIMIT_FIELDS.journeyPerHour,
        function() return current().limits.journeyPerHour end,
        function(value) ns.Profiles.SetLimit("journeyPerHour", value) end), L.TIP_LIMIT_JOURNEY))
    column:Space(8)
    column:Add(W.Heading(parent, L.TRIGGER_RANDOM), 26)
    column:Add(W.Tooltip(W.Check(parent, L.ENABLED,
        function() return current().rules.RANDOM.enabled end,
        function(value) ns.Profiles.SetRule("RANDOM", "enabled", value) end),
        L.TIP_RANDOM_ENABLED, L.TRIGGER_RANDOM))
    journeyStepper("randomMin", L.RANDOM_MIN, L.TIP_RANDOM_MIN, " min")
    journeyStepper("randomMax", L.RANDOM_MAX, L.TIP_RANDOM_MAX, " min")
    column:Space(8)
    local note = column:Add(W.Text(parent, L.JOURNEY_NOTE, "GameFontHighlightSmall"), 60)
    note:SetWidth(580)
    return { Refresh = function() column:Refresh() end }
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
local function confirm(text, onAccept, acceptText, cancelText)
    StaticPopupDialogs.FOREVERMEMORIES_CONFIRM = {
        text = text,
        button1 = acceptText or YES or "Yes",
        button2 = cancelText or NO or "No",
        OnAccept = function() ns.SafeCall("confirm", onAccept) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FOREVERMEMORIES_CONFIRM")
end
UI.Confirm = confirm

-- Asks before reloading the interface. The setting is already saved:
-- "Later" keeps it, and it applies at the next /reload or login.
function UI.ConfirmReload(text)
    confirm(text, function()
        local ok, reason = ns.API.ReloadUI()
        if not ok then
            ns.Logger.Warn("ReloadUI failed: " .. tostring(reason))
            ns.API.Print(L.RELOAD_MANUALLY)
        end
    end, L.RELOAD_NOW, L.LATER)
end

UI.builders.profiles = function(parent)
    local selected = ns.Profiles.ActiveName()
    local rows = {}
    local status = W.Text(parent, "", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 12)
    status:SetWidth(580)

    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", 16, -16)
    listFrame:SetSize(260, 400)

    local function report(ok, reason)
        status:SetText(ok and "" or ("|cffff5555" .. L[reason or "PROFILE_MISSING"] .. "|r"))
        parent:Refresh()
    end

    local nameBox = W.Input(parent, 200)
    nameBox:SetPoint("TOPLEFT", 300, -40)
    W.Tooltip(nameBox, L.TIP_NEW_NAME, L.NEW_NAME)
    local nameLabel = W.Text(parent, L.NEW_NAME, "GameFontHighlightSmall")
    nameLabel:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", -4, 2)

    -- { label, tooltip, onClick }
    local actions = {
        { L.USE_FOR_ALL, L.TIP_USE_FOR_ALL, function() ns.Profiles.SetActive(selected, false); ns.Profiles.ClearCharacterOverride(); report(true) end },
        { L.USE_FOR_CHARACTER, L.TIP_USE_FOR_CHARACTER, function() report(ns.Profiles.SetActive(selected, true)) end },
        { L.COPY, L.TIP_COPY, function() report(ns.Profiles.Copy(selected, nameBox:GetText())) end },
        { L.RENAME, L.TIP_RENAME, function()
            local ok, reason = ns.Profiles.Rename(selected, nameBox:GetText())
            if ok then selected = nameBox:GetText() end
            report(ok, reason)
        end },
        { L.DELETE, L.TIP_DELETE_PROFILE, function()
            if ns.Profiles.IsPreset(selected) then return report(false, "PROFILE_READ_ONLY") end
            confirm(string.format(L.CONFIRM_DELETE_PROFILE, selected), function()
                report(ns.Profiles.Delete(selected))
                selected = ns.Profiles.ActiveName()
            end)
        end },
        { L.RESET, L.TIP_RESET_PROFILE, function()
            if ns.Profiles.IsPreset(selected) then return report(false, "PROFILE_READ_ONLY") end
            confirm(string.format(L.CONFIRM_RESET_PROFILE, selected), function()
                report(ns.Profiles.Reset(selected))
            end)
        end },
    }
    for i, action in ipairs(actions) do
        local button = W.Button(parent, action[1], 200, action[3])
        W.Tooltip(button, action[2], action[1])
        button:SetPoint("TOPLEFT", 296, -70 - (i - 1) * 28)
    end
    local info = W.Text(parent, L.PRESETS_READ_ONLY, "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 300, -250)
    info:SetWidth(300)

    return {
        Refresh = function()
            local names = ns.Profiles.List()
            if not ns.Profiles.Exists(selected) then
                selected = ns.Profiles.ActiveName()
            end
            local active = ns.Profiles.ActiveName()
            for i, name in ipairs(names) do
                local row = rows[i]
                if not row then
                    row = W.Button(listFrame, "", 240, function(self)
                        selected = self.profileName
                        parent:Refresh()
                    end)
                    row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
                    -- Presets describe themselves; every row explains the marks.
                    W.Tooltip(row, function()
                        local key = "TIP_PRESET_" .. row.profileName
                        local about = L[key] ~= key and (L[key] .. "\n\n") or ""
                        return about .. L.TIP_PROFILE_ROW
                    end, function() return row:GetText() end)
                    rows[i] = row
                end
                row.profileName = name
                local label = L["PRESET_" .. name] ~= "PRESET_" .. name and L["PRESET_" .. name] or name
                if name == active then
                    label = label .. (ns.Profiles.IsCharacterOverride() and " (" .. L.CHARACTER .. ")" or " *")
                end
                row:SetText(label)
                row:Show()
                if name == selected then row:LockHighlight() else row:UnlockHighlight() end
            end
            for i = #names + 1, #rows do
                rows[i]:Hide()
            end
        end,
    }
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
UI.builders.settings = function(parent)
    local column = W.Column(parent, 16, 16)
    column:Add(W.Tooltip(W.Dropdown(parent, L.LANGUAGE, {
            { value = "auto", text = L.LANG_AUTO }, { value = "ruRU", text = "Русский" },
            { value = "enUS", text = "English" },
        },
        function() return ns.db.settings.locale end,
        function(value)
            ns.db.settings.locale = value -- saved in ForeverMemoriesDB at once
            -- Ask for a reload only if the visible language really changes
            -- (e.g. "Game language" -> "English" on an English client does not).
            if ns.ResolveLocale(value) ~= ns.activeLocale then
                UI.ConfirmReload(L.CONFIRM_RELOAD_LANGUAGE)
            end
        end), L.TIP_LANGUAGE))
    local reloadNote = column:Add(W.Text(parent, L.LANGUAGE_RELOAD, "GameFontHighlightSmall"), 20, 4)
    reloadNote:SetWidth(560)
    column:Add(settingCheck(parent, L.SHOW_MINIMAP, L.TIP_SHOW_MINIMAP, "minimap", function() ns.Minimap.Update() end))
    column:Add(settingCheck(parent, L.NOTIFICATIONS, L.TIP_NOTIFICATIONS, "notifications"))
    column:Add(settingCheck(parent, L.SOUND, L.TIP_SOUND, "sound"))
    column:Add(W.Tooltip(W.Stepper(parent, L.NOTIFY_DURATION, { min = 1, max = 5, step = 1 },
        function() return ns.db.settings.notifyDuration end,
        function(value) ns.db.settings.notifyDuration = value end, " s"), L.TIP_NOTIFY_DURATION))
    column:Add(W.Tooltip(W.Stepper(parent, L.WINDOW_SCALE, { min = 0.8, max = 1.5, step = 0.1 },
        function() return ns.db.settings.scale end,
        function(value)
            ns.db.settings.scale = value
            UI.ApplyScale()
        end), L.TIP_WINDOW_SCALE))
    column:Space(8)
    column:Add(W.Tooltip(W.Button(parent, L.RESET_POSITION, 200, function() UI.ResetPosition() end),
        L.TIP_RESET_POSITION, L.RESET_POSITION), 26)
    return { Refresh = function() column:Refresh() end }
end
