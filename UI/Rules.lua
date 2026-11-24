-- UI/Rules.lua
-- "Events" tab: one row per trigger with an on/off checkbox and API
-- status. In advanced mode, the selected trigger can be edited.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local function rule(id)
    return ns.Profiles.Current().rules[id]
end

local function reasonText(reason)
    if not reason then
        return ""
    end
    local localized = L[reason]
    return localized ~= reason and localized or (L.REASON_EVENT_REJECTED .. " (" .. reason .. ")")
end

UI.builders.events = function(parent)
    local selected = "LEVEL"
    local rows = {}

    local advanced = W.Check(parent, L.ADVANCED_MODE,
        function() return ns.db.settings.advanced end,
        function(value) ns.db.settings.advanced = value end)
    advanced:SetPoint("TOPLEFT", 12, -10)

    local listTop = 40
    for i, trigger in ipairs(ns.Registry.TRIGGERS) do
        local id = trigger.id
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(300, 20)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetPoint("TOPLEFT", 12, -listTop - (i - 1) * 21)
        row.check = W.Check(row, L["TRIGGER_" .. id],
            function() return rule(id).enabled end,
            function(value) ns.Profiles.SetRule(id, "enabled", value) end)
        row.check:SetPoint("LEFT")
        row.check:SetSize(20, 20)
        row.status = W.Text(row, "", "GameFontDisableSmall", W.COLORS.muted)
        row.status:SetPoint("LEFT", row, "LEFT", 190, 0)
        row.status:SetWidth(110)
        row:SetScript("OnClick", function()
            selected = id
            parent:Refresh()
        end)
        row.id = id
        rows[#rows + 1] = row
    end

    -- Editor for the selected trigger (advanced mode only).
    local editor = CreateFrame("Frame", nil, parent)
    editor:SetPoint("TOPLEFT", 330, -40)
    editor:SetSize(300, 420)
    editor.Refresh = function() parent:Refresh() end
    local title = W.Heading(editor, "")
    title:SetPoint("TOPLEFT")
    local availability = W.Text(editor, "", "GameFontHighlightSmall")
    availability:SetPoint("TOPLEFT", 0, -26)
    availability:SetWidth(300)

    local column = W.Column(editor, 0, 56)
    local fields = {}
    local function stepper(field, label, suffix)
        local spec = ns.Registry.FIELDS[field]
        fields[field] = column:Add(W.Stepper(editor, label, spec,
            function() return rule(selected)[field] end,
            function(value) ns.Profiles.SetRule(selected, field, value) end, suffix))
    end
    stepper("delay", L.FIELD_DELAY, " s")
    stepper("frames", L.FIELD_FRAMES)
    stepper("interval", L.FIELD_INTERVAL, " s")
    local modeOptions = {
        { value = "normal", text = L.MODE_normal },
        { value = "clean", text = L.MODE_clean },
        { value = "dual", text = L.MODE_dual },
    }
    fields.mode = column:Add(W.Dropdown(editor, L.FIELD_MODE, modeOptions,
        function() return rule(selected).mode end,
        function(value) ns.Profiles.SetRule(selected, "mode", value) end))
    stepper("priority", L.FIELD_PRIORITY)
    stepper("cooldown", L.FIELD_COOLDOWN, " s")
    fields.firstOnly = column:Add(W.Check(editor, L.FIELD_FIRST_ONLY,
        function() return rule(selected).firstOnly end,
        function(value) ns.Profiles.SetRule(selected, "firstOnly", value) end))

    -- Quest IDs for the QUEST trigger (per character).
    column:Space(8)
    local questLabel = column:Add(W.Text(editor, L.QUEST_IDS, "GameFontHighlightSmall"), 18)
    local questBox = column:Add(W.Input(editor, 260), 24, 6)
    questBox:SetScript("OnEnterPressed", function(self)
        local quests = {}
        for id in string.gmatch(self:GetText() or "", "%d+") do
            quests[tonumber(id)] = true
        end
        ns.character.quests = quests
        self:ClearFocus()
    end)
    local function questText()
        local ids = {}
        for id in pairs(ns.character and ns.character.quests or {}) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        return table.concat(ids, ", ")
    end
    local simpleHint = W.Text(parent, L.SIMPLE_HINT, "GameFontHighlightSmall")
    simpleHint:SetPoint("TOPLEFT", 330, -40)
    simpleHint:SetWidth(280)

    return {
        Refresh = function()
            advanced:Refresh()
            for _, row in ipairs(rows) do
                local available, reason = ns.Registry.Status(row.id)
                row.check:Refresh()
                row.check:SetEnabled(available)
                row.status:SetText(available and "" or L.UNAVAILABLE)
                if row.id == selected then row:LockHighlight() else row:UnlockHighlight() end
            end
            local isAdvanced = ns.db.settings.advanced
            editor:SetShown(isAdvanced)
            simpleHint:SetShown(not isAdvanced)
            if not isAdvanced then
                return
            end
            local available, reason = ns.Registry.Status(selected)
            title:SetText(L["TRIGGER_" .. selected])
            availability:SetText(available and ("|cff7CAA66" .. L.AVAILABLE .. "|r")
                or ("|cffff5555" .. L.UNAVAILABLE .. ":|r " .. reasonText(reason)))
            column:Refresh()
            local isManual = selected == "MANUAL"
            fields.priority:SetShown(not isManual)
            fields.firstOnly:SetShown(not isManual)
            local isQuest = selected == "QUEST"
            questLabel:SetShown(isQuest)
            questBox:SetShown(isQuest)
            if isQuest and not questBox:HasFocus() then
                questBox:SetText(questText())
            end
        end,
    }
end
