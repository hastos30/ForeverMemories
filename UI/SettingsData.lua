-- UI/SettingsData.lua
-- Settings / Data (v0.10.0; v1.0.0-beta.4 layout of the prototype): four
-- cards, the saved characters (class, level, last play), "Backup &
-- export" and "Manage history" (delete the current character's history,
-- reset all settings). Every delete asks first and names the character.
-- Screenshot files are never touched.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local ROW_HEIGHT = 40
local VISIBLE_ROWS = 2

local function characterName(item)
    return ns.DataTools.DisplayName(item.character, item.key)
end

local function makeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(26, 26)
    row.portrait:SetPoint("LEFT", 0, 0)
    row.name = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
    row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 10, 1)
    row.detail = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.detail:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", 10, -1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.tag = W.Text(row, L.CURRENT_CHARACTER, "GameFontHighlightSmall", W.COLORS.active)
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.action = W.Button(row, "", 90, 24, function(self)
        if row.onAction then row.onAction() end
    end)
    row.action:SetPoint("RIGHT", -4, 0)
    row.line = W.Divider(row)
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    return row
end

-- "Druid · Level 26 · active" / "Mage · Level 12 · last played 24 November 2026".
function UI.CharacterDetail(item)
    local c, s = item.character, item.summary
    local parts = { c.class and ns.API.ClassName(c.class) or "?" }
    if s.level then
        parts[#parts + 1] = string.format(L.LEVEL_N, s.level)
    end
    if item.current then
        parts[#parts + 1] = L.CHARACTER_ACTIVE
    elseif s.lastDay then
        parts[#parts + 1] = string.format(L.LAST_PLAYED, ns.History.DateText(s.lastDay))
    end
    return table.concat(parts, "  ·  ")
end

-- Import: paste -> check -> confirm (with what will be replaced) -> apply.
local function startImport(refresh)
    UI.ShowPasteText(L.IMPORT_TITLE, L.IMPORT_HINT, L.IMPORT_CHECK, function(text)
        local plan, code = ns.DataTools.CheckBackup(text)
        if not plan then
            UI.SetDialogStatus(L["IMPORT_ERROR_" .. string.upper(code)], true)
            return
        end
        UI.HideDialog()
        local created = plan.createdAt and date("%Y-%m-%d %H:%M", plan.createdAt) or L.NO_DATA
        UI.Confirm(string.format(L.CONFIRM_IMPORT, created, plan.version or "?", plan.characters,
            plan.shots), L.IMPORT_APPLY, function()
            ns.DataTools.ApplyBackup(plan)
            refresh()
            UI.ConfirmReload(L.IMPORT_DONE)
        end)
    end)
end

UI.settingsPages.data = function(parent)
    local width = UI.SETTINGS_WIDTH
    -- Four cards in one row (v1.0.0-beta.4).
    local specs = {
        { "characters", ns.Media.ICON.account, L.DATA_CHARACTERS, L.TIP_DATA_CHARACTERS },
        { "shots", ns.Media.ICON.shots, L.DATA_MEMORIES, L.TIP_DATA_SHOT_RECORDS },
        { "days", ns.Media.ICON.days, L.DATA_TRACKED_DATES, L.TIP_DATA_GAME_DAYS },
        { "zones", ns.Media.ICON.zones, L.DATA_UNIQUE_ZONES, L.TIP_DATA_UNIQUE_ZONES },
    }
    -- Two columns in a narrow page (v1.0.0-beta.5).
    local gap = 8
    local columns = width < 480 and 2 or 4
    local cardW = (width - gap * (columns - 1)) / columns
    local cards = {}
    for i, spec in ipairs(specs) do
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        W.Backdrop(card, W.COLORS.panel, 0.95, W.COLORS.divider)
        card:SetSize(cardW, 56)
        local col, line = (i - 1) % columns, math.floor((i - 1) / columns)
        card:SetPoint("TOPLEFT", col * (cardW + gap), -line * (56 + gap))
        card.value = W.Text(card, "", "GameFontHighlightLarge", W.COLORS.heading) -- beta.8: Inter digits
        card.value:SetPoint("TOPLEFT", 10, -8)
        card.caption = W.Text(card, spec[3], "GameFontHighlightSmall", W.COLORS.muted)
        card.caption:SetPoint("BOTTOMLEFT", 10, 8)
        card.caption:SetPoint("RIGHT", card, "RIGHT", -6, 0)
        W.Tooltip(card, spec[4], spec[3])
        cards[spec[1]] = card
    end

    local top = (4 / columns) * (56 + gap) - gap + 12
    UI.SettingsSection(parent, L.SAVED_CHARACTERS, top)
    local refresh
    local list = W.ScrollList(parent, width, ROW_HEIGHT * VISIBLE_ROWS, ROW_HEIGHT, makeRow, function(row, item)
        local c = item.character
        local file, coords = ns.API.ClassIcon(c.class)
        if file then
            row.portrait:SetTexture(file)
            row.portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            row.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        local name = characterName(item)
        row.name:SetText(name)
        local color = item.current and W.COLORS.heading or W.COLORS.text
        row.name:SetTextColor(color[1], color[2], color[3])
        row.tag:SetShown(item.current)
        row.detail:SetText(UI.CharacterDetail(item))
        -- The current character is cleared under "Manage history".
        row.action:SetShown(not item.current)
        row.action:SetLabel(L.DELETE)
        row.onAction = not item.current and function()
            UI.Confirm(string.format(L.CONFIRM_DELETE_CHARACTER, name), L.DELETE, function()
                ns.DataTools.Delete(item.key)
                refresh()
            end)
        end
        W.Tooltip(row.action, L.TIP_DELETE_CHARACTER)
    end)
    list:SetPoint("TOPLEFT", 0, -(top + 26))

    local y = top + 26 + ROW_HEIGHT * VISIBLE_ROWS + 12
    UI.SettingsSection(parent, L.BACKUP_EXPORT, y)
    UI.SettingsActionRow(parent, y + 28, L.EXPORT_STATS, nil, L.EXPORT_SHORT, function()
        UI.ShowCopyText(L.EXPORT_STATS, ns.DataTools.StatsText())
    end, L.TIP_EXPORT_STATS)
    UI.SettingsActionRow(parent, y + 60, L.CREATE_BACKUP, nil, L.CREATE_SHORT, function()
        UI.ShowCopyText(L.BACKUP, ns.DataTools.BackupText(), L.BACKUP_HINT)
    end, L.TIP_BACKUP)
    UI.SettingsActionRow(parent, y + 92, L.RESTORE_BACKUP, L.RESTORE_BACKUP_NOTE, L.IMPORT_SHORT, function()
        startImport(refresh)
    end, L.TIP_IMPORT)

    y = y + 136
    UI.SettingsSection(parent, L.MANAGE_HISTORY, y)
    UI.SettingsActionRow(parent, y + 28, L.DELETE_CHARACTER_HISTORY, L.DATA_NOTE, L.DELETE_ELLIPSIS, function()
        local name = ns.DataTools.DisplayName(ns.character, ns.characterKey)
        UI.Confirm(string.format(L.CONFIRM_CLEAR_CURRENT, name), L.CLEAR_HISTORY, function()
            ns.DataTools.ClearCurrent()
            refresh()
        end)
    end, L.TIP_CLEAR_HISTORY)
    UI.SettingsActionRow(parent, y + 66, L.RESET_ALL_SETTINGS, L.RESET_ALL_NOTE, L.RESET_ELLIPSIS, function()
        UI.Confirm(L.CONFIRM_RESET_ALL, L.RESTORE, function()
            ns.Database.ResetAllSettings(ns.db)
            ns.Minimap.Update()
            UI.ResetGeometry()
            UI.ApplyScale()
            if ns.ResolveLocaleCode(ns.db.settings.locale) ~= ns.activeLocaleCode then
                UI.ConfirmReload(L.RELOAD_FOR_LANGUAGE)
            end
            refresh()
        end)
    end, L.TIP_RESET_ALL)

    refresh = function()
        local storage = ns.Database.Storage(ns.db)
        cards.characters.value:SetText(ns.Num(storage.characters))
        cards.shots.value:SetText(ns.Num(storage.shots))
        cards.days.value:SetText(ns.Num(storage.days))
        cards.zones.value:SetText(ns.Num(ns.DataTools.AccountTotals().zones))
        list:SetItems(ns.DataTools.Characters(), true)
    end
    return { Refresh = refresh }
end
