-- UI/Settings.lua
-- Tabs: Capture, Journey, Profiles, Settings.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local function current()
    return ns.Profiles.Current()
end

local function settingCheck(parent, label, key, after)
    return W.Check(parent, label,
        function() return ns.db.settings[key] end,
        function(value)
            ns.db.settings[key] = value
            if after then after(value) end
        end)
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------
UI.builders.capture = function(parent)
    local column = W.Column(parent, 16, 16)
    column:Add(W.Heading(parent, L.MANUAL_SHOT), 26)
    column:Add(W.Cycle(parent, L.FIELD_MODE, {
            { value = "normal", text = L.MODE_normal },
            { value = "clean", text = L.MODE_clean },
            { value = "dual", text = L.MODE_dual },
        },
        function() return current().rules.MANUAL.mode end,
        function(value) ns.Profiles.SetRule("MANUAL", "mode", value) end))
    column:Add(W.Stepper(parent, L.FIELD_FRAMES, ns.Registry.FIELDS.frames,
        function() return current().rules.MANUAL.frames end,
        function(value) ns.Profiles.SetRule("MANUAL", "frames", value) end))
    column:Add(W.Cycle(parent, L.MANUAL_TIMER, {
            { value = 0, text = L.TIMER_OFF }, { value = 3, text = "3 s" },
            { value = 5, text = "5 s" }, { value = 10, text = "10 s" },
        },
        function() return ns.db.settings.manualTimer end,
        function(value) ns.db.settings.manualTimer = value end))
    column:Space(8)
    column:Add(W.Heading(parent, L.SAFETY), 26)
    column:Add(settingCheck(parent, L.CLEAN_ALLOWED, "cleanAllowed"))
    local cleanNote = column:Add(W.Text(parent, L.CLEAN_NOTE, "GameFontHighlightSmall"), 30, 28)
    cleanNote:SetWidth(560)
    column:Space(4)
    column:Add(W.Heading(parent, L.LIMITS), 26)
    local limitLabels = { perHour = L.LIMIT_PER_HOUR, perSession = L.LIMIT_PER_SESSION, journeyPerHour = L.LIMIT_JOURNEY }
    for _, field in ipairs({ "perHour", "perSession", "journeyPerHour" }) do
        column:Add(W.Stepper(parent, limitLabels[field], ns.Profiles.LIMIT_FIELDS[field],
            function() return current().limits[field] end,
            function(value) ns.Profiles.SetLimit(field, value) end))
    end
    column:Space(10)
    local test = W.Button(parent, L.TEST_SHOT, 160, function() ns.Engine.SubmitManual() end)
    column:Add(test, 26)
    local panel = W.Button(parent, L.MANUAL_PANEL, 160, function() ns.ManualPanel.Toggle() end)
    panel:SetPoint("LEFT", test, "RIGHT", 10, 0)
    return { Refresh = function() column:Refresh() end }
end

---------------------------------------------------------------------------
-- Journey
---------------------------------------------------------------------------
UI.builders.journey = function(parent)
    local column = W.Column(parent, 16, 16)
    local function journeyStepper(field, label, suffix)
        return column:Add(W.Stepper(parent, label, ns.Profiles.JOURNEY_FIELDS[field],
            function() return current().journey[field] end,
            function(value) ns.Profiles.SetJourney(field, value) end, suffix))
    end
    column:Add(W.Heading(parent, L.TRIGGER_JOURNEY), 26)
    column:Add(W.Check(parent, L.ENABLED,
        function() return current().rules.JOURNEY.enabled end,
        function(value) ns.Profiles.SetRule("JOURNEY", "enabled", value) end))
    journeyStepper("interval", L.JOURNEY_INTERVAL, " min")
    journeyStepper("moveThreshold", L.JOURNEY_MOVE)
    column:Add(W.Stepper(parent, L.LIMIT_JOURNEY, ns.Profiles.LIMIT_FIELDS.journeyPerHour,
        function() return current().limits.journeyPerHour end,
        function(value) ns.Profiles.SetLimit("journeyPerHour", value) end))
    column:Space(8)
    column:Add(W.Heading(parent, L.TRIGGER_RANDOM), 26)
    column:Add(W.Check(parent, L.ENABLED,
        function() return current().rules.RANDOM.enabled end,
        function(value) ns.Profiles.SetRule("RANDOM", "enabled", value) end))
    journeyStepper("randomMin", L.RANDOM_MIN, " min")
    journeyStepper("randomMax", L.RANDOM_MAX, " min")
    column:Space(8)
    local note = column:Add(W.Text(parent, L.JOURNEY_NOTE, "GameFontHighlightSmall"), 60)
    note:SetWidth(580)
    return { Refresh = function() column:Refresh() end }
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
local function confirm(text, onAccept)
    StaticPopupDialogs.FOREVERMEMORIES_CONFIRM = {
        text = text,
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function() ns.SafeCall("confirm", onAccept) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FOREVERMEMORIES_CONFIRM")
end
UI.Confirm = confirm

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
    local nameLabel = W.Text(parent, L.NEW_NAME, "GameFontHighlightSmall")
    nameLabel:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", -4, 2)

    local actions = {
        { L.USE_FOR_ALL, function() ns.Profiles.SetActive(selected, false); ns.Profiles.ClearCharacterOverride(); report(true) end },
        { L.USE_FOR_CHARACTER, function() report(ns.Profiles.SetActive(selected, true)) end },
        { L.COPY, function() report(ns.Profiles.Copy(selected, nameBox:GetText())) end },
        { L.RENAME, function()
            local ok, reason = ns.Profiles.Rename(selected, nameBox:GetText())
            if ok then selected = nameBox:GetText() end
            report(ok, reason)
        end },
        { L.DELETE, function()
            if ns.Profiles.IsPreset(selected) then return report(false, "PROFILE_READ_ONLY") end
            confirm(string.format(L.CONFIRM_DELETE_PROFILE, selected), function()
                report(ns.Profiles.Delete(selected))
                selected = ns.Profiles.ActiveName()
            end)
        end },
        { L.RESET, function()
            if ns.Profiles.IsPreset(selected) then return report(false, "PROFILE_READ_ONLY") end
            confirm(string.format(L.CONFIRM_RESET_PROFILE, selected), function()
                report(ns.Profiles.Reset(selected))
            end)
        end },
    }
    for i, action in ipairs(actions) do
        local button = W.Button(parent, action[1], 200, action[2])
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
    column:Add(W.Cycle(parent, L.LANGUAGE, {
            { value = "auto", text = L.LANG_AUTO }, { value = "ruRU", text = "Русский" },
            { value = "enUS", text = "English" },
        },
        function() return ns.db.settings.locale end,
        function(value) ns.db.settings.locale = value end))
    local reloadNote = column:Add(W.Text(parent, L.LANGUAGE_RELOAD, "GameFontHighlightSmall"), 20, 4)
    reloadNote:SetWidth(560)
    column:Add(settingCheck(parent, L.SHOW_MINIMAP, "minimap", function() ns.Minimap.Update() end))
    column:Add(settingCheck(parent, L.NOTIFICATIONS, "notifications"))
    column:Add(settingCheck(parent, L.SOUND, "sound"))
    column:Add(W.Stepper(parent, L.NOTIFY_DURATION, { min = 1, max = 5, step = 1 },
        function() return ns.db.settings.notifyDuration end,
        function(value) ns.db.settings.notifyDuration = value end, " s"))
    column:Add(W.Stepper(parent, L.WINDOW_SCALE, { min = 0.8, max = 1.5, step = 0.1 },
        function() return ns.db.settings.scale end,
        function(value)
            ns.db.settings.scale = value
            UI.ApplyScale()
        end))
    column:Space(8)
    column:Add(W.Button(parent, L.RESET_POSITION, 200, function() UI.ResetPosition() end), 26)
    return { Refresh = function() column:Refresh() end }
end
