-- UI/SettingsData.lua
-- Settings / Data (v0.10.0): account storage, saved characters, statistics
-- export, text backup and its safe import, deleting history. Every delete
-- asks first and names the character. Screenshot files are never touched.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local ROW_HEIGHT = 44
local VISIBLE_ROWS = 3

local function characterName(item)
    return ns.DataTools.DisplayName(item.character, item.key) .. " — " .. (item.character.realm or "?")
end

local function makeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(28, 28)
    row.portrait:SetPoint("LEFT", 0, 0)
    row.name = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
    row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 10, 0)
    row.detail = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.detail:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", 10, 0)
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
    local width = UI.CONTENT_WIDTH
    local cards, y = UI.Dashboard(parent, 0, {
        { "characters", "Interface\\Icons\\INV_Misc_GroupNeedMore", L.DATA_CHARACTERS, L.TIP_DATA_CHARACTERS },
        { "shots", "Interface\\Icons\\INV_Misc_Spyglass_03", L.DATA_SHOT_RECORDS, L.TIP_DATA_SHOT_RECORDS },
        { "days", "Interface\\Icons\\INV_Misc_Note_01", L.DATA_GAME_DAYS, L.TIP_DATA_GAME_DAYS },
        { "memory", "Interface\\Icons\\INV_Misc_Gear_01", L.DATA_MEMORY, L.TIP_DATA_MEMORY },
    })

    local heading = W.Heading(parent, L.SAVED_CHARACTERS)
    heading:SetPoint("TOPLEFT", 0, -(y + 12))

    local refresh
    local list = W.ScrollList(parent, width, ROW_HEIGHT * VISIBLE_ROWS, ROW_HEIGHT, makeRow, function(row, item)
        local c, s = item.character, item.summary
        local file, coords = ns.API.ClassIcon(c.class)
        if file then
            row.portrait:SetTexture(file)
            row.portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            row.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.name:SetText(characterName(item))
        local color = item.current and W.COLORS.heading or W.COLORS.text
        row.name:SetTextColor(color[1], color[2], color[3])
        row.tag:SetShown(item.current)
        row.detail:SetText(table.concat({
            c.class and ns.API.ClassName(c.class) or "?",
            ns.Count(s.shots, "SHOTS"), ns.Count(s.steps, "STEPS"), ns.Count(s.days, "DAYS"),
        }, "  ·  "))
        local name = characterName(item)
        if item.current then
            row.action:SetLabel(L.CLEAR_HISTORY)
            row.onAction = function()
                UI.Confirm(string.format(L.CONFIRM_CLEAR_CURRENT, name), L.CLEAR_HISTORY, function()
                    ns.DataTools.ClearCurrent()
                    refresh()
                end)
            end
        else
            row.action:SetLabel(L.DELETE)
            row.onAction = function()
                UI.Confirm(string.format(L.CONFIRM_DELETE_CHARACTER, name), L.DELETE, function()
                    ns.DataTools.Delete(item.key)
                    refresh()
                end)
            end
        end
        W.Tooltip(row.action, item.current and L.TIP_CLEAR_HISTORY or L.TIP_DELETE_CHARACTER)
    end)
    local listTop = y + 42
    list:SetPoint("TOPLEFT", 0, -listTop)

    local buttonsTop = listTop + ROW_HEIGHT * VISIBLE_ROWS + 10
    local export = W.Button(parent, L.EXPORT_STATS, width, 28, function()
        UI.ShowCopyText(L.EXPORT_STATS, ns.DataTools.StatsText())
    end)
    export:SetPoint("TOPLEFT", 0, -buttonsTop)
    W.Tooltip(export, L.TIP_EXPORT_STATS, L.EXPORT_STATS)
    local backup = W.Button(parent, L.BACKUP, width, 28, function()
        UI.ShowCopyText(L.BACKUP, ns.DataTools.BackupText(), L.BACKUP_HINT)
    end)
    backup:SetPoint("TOPLEFT", 0, -(buttonsTop + 34))
    W.Tooltip(backup, L.TIP_BACKUP, L.BACKUP)
    local import = W.Button(parent, L.IMPORT, width, 28, function()
        startImport(refresh)
    end)
    import:SetPoint("TOPLEFT", 0, -(buttonsTop + 68))
    W.Tooltip(import, L.TIP_IMPORT, L.IMPORT)
    local note = W.Text(parent, L.DATA_NOTE, "GameFontHighlightSmall", W.COLORS.muted)
    note:SetPoint("TOPLEFT", 0, -(buttonsTop + 106))
    note:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    refresh = function()
        local storage = ns.Database.Storage(ns.db)
        cards.characters.value:SetText(ns.Num(storage.characters))
        cards.shots.value:SetText(ns.Num(storage.shots))
        cards.days.value:SetText(ns.Num(storage.days))
        local memory = ns.API.AddonMemoryKB(ns.name)
        cards.memory.value:SetText(memory and (ns.Num(math.floor(memory + 0.5)) .. " KB") or L.UNAVAILABLE)
        list:SetItems(ns.DataTools.Characters(), true)
    end
    return { Refresh = refresh }
end
