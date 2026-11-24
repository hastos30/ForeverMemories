-- UI/Widgets.lua
-- Small building blocks for the window: text, buttons, checkboxes,
-- "- value +" steppers and click-to-cycle selectors.
-- Every input widget has :Refresh() that re-reads its value.
-- Only long-standing templates are used (UIPanelButtonTemplate,
-- UICheckButtonTemplate, InputBoxTemplate, BackdropTemplate).
local _, ns = ...

local W = {}
ns.Widgets = W

W.COLORS = {
    background = { 0.063, 0.063, 0.059 }, -- #10100F
    panel = { 0.157, 0.129, 0.086 },      -- #282116
    gold = { 0.788, 0.639, 0.369 },       -- #C9A35E
    text = { 0.910, 0.863, 0.753 },       -- #E8DCC0
    active = { 0.486, 0.667, 0.400 },     -- #7CAA66
    muted = { 0.55, 0.52, 0.46 },
}

function W.Backdrop(frame, color, alpha)
    if not frame.SetBackdrop then
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local c = color or W.COLORS.panel
    frame:SetBackdropColor(c[1], c[2], c[3], alpha or 0.95)
    local g = W.COLORS.gold
    frame:SetBackdropBorderColor(g[1], g[2], g[3], 0.8)
end

function W.Text(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    local c = color or W.COLORS.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

function W.Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 22)
    button:SetText(text)
    button:SetScript("OnClick", function(self, mouseButton)
        ns.SafeCall("button", onClick, self, mouseButton)
    end)
    return button
end

function W.Check(parent, label, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.label = W.Text(check, label)
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check:SetScript("OnClick", function(self)
        ns.SafeCall("check", set, self:GetChecked() and true or false)
        if parent.Refresh then parent:Refresh() end
    end)
    function check:Refresh()
        self:SetChecked(get() and true or false)
    end
    return check
end

local function formatNumber(value, step)
    if step < 1 then
        local decimals = step < 0.1 and 2 or 1
        return string.format("%." .. decimals .. "f", value)
    end
    return tostring(math.floor(value + 0.5))
end

-- Row: "label   [-] value [+]"
function W.Stepper(parent, label, spec, get, set, suffix)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 24)
    row.label = W.Text(row, label)
    row.label:SetPoint("LEFT")
    row.label:SetWidth(170)
    local minus = W.Button(row, "-", 24)
    minus:SetPoint("LEFT", row, "LEFT", 172, 0)
    row.value = W.Text(row, "", "GameFontHighlight")
    row.value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    row.value:SetWidth(56)
    row.value:SetJustifyH("CENTER")
    local plus = W.Button(row, "+", 24)
    plus:SetPoint("LEFT", row.value, "RIGHT", 4, 0)

    local function change(direction)
        local value = (get() or spec.min) + direction * spec.step
        value = math.floor(value / spec.step + 0.5) * spec.step
        value = ns.Util.Clamp(value, spec.min, spec.max, spec.min)
        set(value)
        if parent.Refresh then parent:Refresh() else row:Refresh() end
    end
    minus:SetScript("OnClick", function() ns.SafeCall("stepper", change, -1) end)
    plus:SetScript("OnClick", function() ns.SafeCall("stepper", change, 1) end)

    function row:Refresh()
        local value = get()
        row.value:SetText(value and (formatNumber(value, spec.step) .. (suffix or "")) or "-")
    end
    function row:SetEnabled(enabled)
        minus:SetEnabled(enabled)
        plus:SetEnabled(enabled)
    end
    return row
end

-- Row: "label   [current option]" - click to switch to the next option.
-- options: list of { value = ..., text = ... } or a function returning it.
function W.Cycle(parent, label, options, get, set, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 24)
    row.label = W.Text(row, label)
    row.label:SetPoint("LEFT")
    row.label:SetWidth(170)
    local button = W.Button(row, "", width or 120)
    button:SetPoint("LEFT", row, "LEFT", 172, 0)
    row.button = button

    local function list()
        return type(options) == "function" and options() or options
    end
    local function indexOf(value)
        for i, option in ipairs(list()) do
            if option.value == value then
                return i
            end
        end
        return 0
    end
    button:SetScript("OnClick", function(_, mouseButton)
        local opts = list()
        if #opts == 0 then return end
        local step = mouseButton == "RightButton" and -1 or 1
        local nextIndex = (indexOf(get()) - 1 + step) % #opts + 1
        ns.SafeCall("cycle", set, opts[nextIndex].value)
        if parent.Refresh then parent:Refresh() else row:Refresh() end
    end)
    if button.RegisterForClicks then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    function row:Refresh()
        local option = list()[indexOf(get())]
        button:SetText(option and option.text or tostring(get()))
    end
    function row:SetEnabled(enabled)
        button:SetEnabled(enabled)
    end
    return row
end

function W.Input(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- Vertical layout: each Add() places a widget under the previous one.
function W.Column(parent, x, y, gap)
    local column = { y = y, widgets = {} }
    function column:Add(widget, height, indent)
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (indent or 0), -self.y)
        self.y = self.y + (height or 26) + (gap or 2)
        if widget.Refresh then
            self.widgets[#self.widgets + 1] = widget
        end
        return widget
    end
    function column:Space(height)
        self.y = self.y + height
    end
    function column:Refresh()
        for _, widget in ipairs(self.widgets) do
            widget:Refresh()
        end
    end
    return column
end

-- A titled block of text (used for headings).
function W.Heading(parent, text)
    return W.Text(parent, text, "GameFontNormalLarge", W.COLORS.gold)
end
