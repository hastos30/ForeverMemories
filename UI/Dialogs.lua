-- UI/Dialogs.lua
-- Text box dialog (v0.10.0) for everything the player copies or pastes:
-- statistics export, backup, diagnostics, links (the game cannot open a
-- browser or write files, so text is copied with Ctrl+C / pasted with
-- Ctrl+V) and confirmations of irreversible actions.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local DIALOG_WIDTH, DIALOG_HEIGHT = 560, 420
local dialog

local function build()
    dialog = CreateFrame("Frame", "ForeverMemoriesTextDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    W.Backdrop(dialog, W.COLORS.background, 0.98, W.COLORS.gold, 0.9)
    dialog:Hide()
    ns.ownFrames[dialog] = true -- never in a screenshot
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverMemoriesTextDialog") -- Esc closes
    end

    dialog.title = W.Text(dialog, "", "GameFontNormalLarge", W.COLORS.heading)
    dialog.title:SetPoint("TOPLEFT", 16, -16)
    dialog.hint = W.Text(dialog, "", "GameFontHighlightSmall", W.COLORS.muted)
    dialog.hint:SetPoint("TOPLEFT", 16, -42)
    dialog.hint:SetPoint("RIGHT", dialog, "RIGHT", -16, 0)

    local box = W.Panel(dialog, W.COLORS.panel, W.COLORS.divider)
    box:SetPoint("TOPLEFT", 16, -66)
    box:SetPoint("BOTTOMRIGHT", -16, 56)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(DIALOG_WIDTH - 48)
    edit:SetMaxLetters(0)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local value = (self:GetVerticalScroll() or 0) - delta * W.SCROLL_STEP
        self:SetVerticalScroll(math.max(0, math.min(range, value)))
    end)
    -- Keeps the cursor visible while typing or selecting.
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top = scroll:GetVerticalScroll() or 0
        local visible = scroll:GetHeight() or 0
        y = -(y or 0)
        if y < top then
            scroll:SetVerticalScroll(y)
        elseif y + (height or 0) > top + visible then
            scroll:SetVerticalScroll(y + (height or 0) - visible)
        end
    end)
    edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    -- Read-only dialogs put their text back if it is changed.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and dialog.readOnly and self:GetText() ~= dialog.text then
            self:SetText(dialog.text)
            self:HighlightText()
        end
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    dialog.edit = edit

    dialog.close = W.Button(dialog, L.CLOSE, 140, 28, function() dialog:Hide() end)
    dialog.close:SetPoint("BOTTOMRIGHT", -16, 16)
    dialog.action = W.Button(dialog, "", 180, 28, function()
        if dialog.onAction then
            dialog.onAction(edit:GetText() or "")
        end
    end)
    dialog.action:SetPoint("RIGHT", dialog.close, "LEFT", -10, 0)
    dialog.select = W.Button(dialog, L.SELECT_ALL, 140, 28, function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    dialog.select:SetPoint("BOTTOMLEFT", 16, 16)
    dialog.status = W.Text(dialog, "", "GameFontHighlightSmall", W.COLORS.muted)
    dialog.status:SetPoint("LEFT", dialog.select, "RIGHT", 12, 0)
    dialog.status:SetPoint("RIGHT", dialog.action, "LEFT", -12, 0)
end

-- Shows `text` to copy: everything is selected, Ctrl+C copies it.
function UI.ShowCopyText(title, text, hint)
    if not dialog then build() end
    dialog.readOnly, dialog.text, dialog.onAction = true, text, nil
    dialog.title:SetText(title)
    dialog.hint:SetText(hint or L.COPY_HINT)
    dialog.status:SetText("")
    dialog.action:Hide()
    dialog.select:Show()
    dialog.edit:SetText(text)
    dialog:Show()
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
    return dialog
end

-- Empty box to paste into; onAction(text) runs on the action button.
function UI.ShowPasteText(title, hint, actionLabel, onAction)
    if not dialog then build() end
    dialog.readOnly, dialog.text, dialog.onAction = false, nil, onAction
    dialog.title:SetText(title)
    dialog.hint:SetText(hint)
    dialog.status:SetText("")
    dialog.action:SetLabel(actionLabel)
    dialog.action:Show()
    dialog.select:Hide()
    dialog.edit:SetText("")
    dialog:Show()
    dialog.edit:SetFocus()
    return dialog
end

function UI.SetDialogStatus(text, isError)
    if dialog then
        dialog.status:SetText(text or "")
        local c = isError and W.COLORS.error or W.COLORS.muted
        dialog.status:SetTextColor(c[1], c[2], c[3])
    end
end

function UI.HideDialog()
    if dialog then
        dialog:Hide()
    end
end

-- Yes / No question for an action that cannot be undone. The text is
-- shown as is ("%" is escaped: StaticPopup formats its text).
function UI.Confirm(text, acceptLabel, onAccept)
    StaticPopupDialogs.FOREVERMEMORIES_CONFIRM = {
        text = string.gsub(text, "%%", "%%%%"),
        button1 = acceptLabel or YES,
        button2 = L.CANCEL,
        OnAccept = function()
            ns.SafeCall("confirm", onAccept)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
    }
    StaticPopup_Show("FOREVERMEMORIES_CONFIRM")
end
