-- UI/Journal.lua
-- Journal tab: filters, a page of up to 50 records in a scroll area and
-- details of the selected record (note, favorite, delete).
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local ROW_HEIGHT = 18

UI.builders.journal = function(parent)
    local filter = { char = nil, event = nil, status = nil, period = nil }
    local page = 1
    local selectedId

    -- Filters: dropdown lists. They live only while the window is open.
    local function filterDropdown(x, y, options, key, tip)
        local row = W.Dropdown(parent, "", options,
            function() return filter[key] end,
            function(value) filter[key] = value; page = 1 end, 140)
        row:SetPoint("TOPLEFT", x, y)
        row:SetWidth(140) -- no label: the row must not cover the next filter
        row.label:SetWidth(1)
        W.Tooltip(row, tip .. "\n\n|cff8c857a" .. L.TIP_FILTER_RESET .. "|r")
        row.button:ClearAllPoints()
        row.button:SetPoint("LEFT", row, "LEFT", 0, 0)
        return row
    end
    local charOptions = function()
        return { { value = nil, text = L.ALL_CHARACTERS }, { value = ns.characterKey, text = L.THIS_CHARACTER } }
    end
    local eventOptions = { { value = nil, text = L.ALL_EVENTS } }
    for _, trigger in ipairs(ns.Registry.TRIGGERS) do
        eventOptions[#eventOptions + 1] = { value = trigger.id, text = L["TRIGGER_" .. trigger.id] }
    end
    local statusOptions = { { value = nil, text = L.ALL_STATUSES } }
    for _, s in ipairs({ "success", "partial", "unconfirmed", "failed", "skipped" }) do
        statusOptions[#statusOptions + 1] = { value = s, text = L["STATUS_" .. s] }
    end
    local periodOptions = {
        { value = nil, text = L.ALL_TIME }, { value = 1, text = L.TODAY },
        { value = 7, text = L.LAST_7_DAYS }, { value = 30, text = L.LAST_30_DAYS },
        { value = "fav", text = L.FAVORITES },
    }
    local filters = {
        filterDropdown(12, -10, charOptions, "char", L.TIP_FILTER_CHAR),
        filterDropdown(158, -10, eventOptions, "event", L.TIP_FILTER_EVENT),
        filterDropdown(304, -10, statusOptions, "status", L.TIP_FILTER_STATUS),
        filterDropdown(450, -10, periodOptions, "period", L.TIP_FILTER_PERIOD),
    }

    -- Scroll area with up to 50 rows.
    -- Plain ScrollFrame scrolled with the mouse wheel (no template needed).
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 12, -42)
    scroll:SetSize(580, 250)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(580, ns.Journal.PAGE_SIZE * ROW_HEIGHT)
    scroll:SetScrollChild(list)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, list:GetHeight() - self:GetHeight())
        local value = ns.Util.Clamp(self:GetVerticalScroll() - delta * ROW_HEIGHT * 3, 0, maxScroll, 0)
        self:SetVerticalScroll(value)
    end)
    local rows = {}
    for i = 1, ns.Journal.PAGE_SIZE do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(570, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.text = W.Text(row, "", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetWidth(560)
        row:SetScript("OnClick", function(self)
            selectedId = self.entryId
            parent:Refresh()
        end)
        W.Tooltip(row, L.TIP_JOURNAL_ROW)
        rows[i] = row
    end

    local prev = W.Button(parent, "<", 30, function() page = page - 1; parent:Refresh() end)
    prev:SetPoint("TOPLEFT", 12, -298)
    W.Tooltip(prev, L.TIP_PREV_PAGE)
    local pageText = W.Text(parent, "")
    pageText:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    local nextButton = W.Button(parent, ">", 30, function() page = page + 1; parent:Refresh() end)
    nextButton:SetPoint("LEFT", prev, "RIGHT", 140, 0)
    W.Tooltip(nextButton, L.TIP_NEXT_PAGE)

    -- Details of the selected record.
    local details = W.Text(parent, "", "GameFontHighlightSmall")
    details:SetPoint("TOPLEFT", 12, -326)
    details:SetWidth(580)
    local noteBox = W.Input(parent, 300)
    noteBox:SetPoint("TOPLEFT", 18, -388)
    W.Tooltip(noteBox, L.TIP_NOTE)
    local saveNote = W.Button(parent, L.SAVE_NOTE, 110, function()
        ns.Journal.Update(selectedId, { note = noteBox:GetText() })
        noteBox:ClearFocus()
    end)
    saveNote:SetPoint("LEFT", noteBox, "RIGHT", 8, 0)
    W.Tooltip(saveNote, L.TIP_SAVE_NOTE, L.SAVE_NOTE)
    noteBox:SetScript("OnEnterPressed", function() saveNote:Click() end)
    local favButton = W.Button(parent, "", 110, function()
        local entry = ns.Journal.Get(selectedId)
        if entry then ns.Journal.Update(selectedId, { fav = not entry.fav }) end
    end)
    favButton:SetPoint("LEFT", saveNote, "RIGHT", 8, 0)
    W.Tooltip(favButton, L.TIP_FAVORITE, L.FAVORITE .. " / " .. L.UNFAVORITE)
    local deleteButton = W.Button(parent, L.DELETE, 110, function()
        UI.Confirm(L.CONFIRM_DELETE_ENTRY, function()
            ns.Journal.Delete(selectedId)
            selectedId = nil
        end)
    end)
    deleteButton:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", -6, -6)
    W.Tooltip(deleteButton, L.TIP_DELETE_ENTRY, L.DELETE)

    local function query()
        local q = { char = filter.char, event = filter.event, status = filter.status }
        if filter.period == "fav" then
            q.fav = true
        elseif filter.period then
            q.since = ns.Journal.DayStart(ns.API.Time()) - (filter.period - 1) * 86400
        end
        return ns.Journal.Query(q, page)
    end

    local function describe(entry)
        local lines = {
            string.format("#%d  %s  %s", entry.id, date("%Y-%m-%d %H:%M:%S", entry.t), L["STATUS_" .. entry.status]),
            ns.Notifications.EventNames(entry) .. "  -  " .. (entry.zone or "?") .. "  -  " .. (entry.char or "?"),
            string.format(L.DETAILS_MODES, L["MODE_" .. (entry.modeRequested or "normal")],
                entry.modeActual or "-", entry.ok or 0, entry.failed or 0),
        }
        if entry.skipReason then
            lines[#lines + 1] = L.SKIP_REASON .. ": " .. L["REASON_" .. entry.skipReason]
        end
        return table.concat(lines, "\n")
    end

    return {
        Refresh = function()
            for _, f in ipairs(filters) do f:Refresh() end
            local items, total, pages, realPage = query()
            page = realPage
            for i, row in ipairs(rows) do
                local entry = items[i]
                if entry then
                    row.entryId = entry.id
                    row.text:SetText(string.format("%s %s  %s  |cff8c857a%s  %s|r%s",
                        UI.STATUS_ICON[entry.status] or "", date("%m-%d %H:%M", entry.t),
                        ns.Notifications.EventNames(entry), entry.zone or "", entry.char or "",
                        entry.fav and "  |cffC9A35E*|r" or ""))
                    row:Show()
                else
                    row:Hide()
                end
            end
            list:SetHeight(math.max(1, #items) * ROW_HEIGHT)
            scroll:SetVerticalScroll(0)
            pageText:SetText(string.format(L.PAGE_OF, page, pages, total))
            prev:SetEnabled(page > 1)
            nextButton:SetEnabled(page < pages)
            local entry = selectedId and ns.Journal.Get(selectedId)
            details:SetText(entry and describe(entry) or L.SELECT_ENTRY)
            for _, widget in ipairs({ noteBox, saveNote, favButton, deleteButton }) do
                widget:SetShown(entry ~= nil)
            end
            if entry then
                if not noteBox:HasFocus() then
                    noteBox:SetText(entry.note or "")
                end
                favButton:SetText(entry.fav and L.UNFAVORITE or L.FAVORITE)
            end
        end,
    }
end
