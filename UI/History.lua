-- UI/History.lua
-- "History" tab (spec 5, v0.8.0): lifetime statistics of the current
-- character. A 2 x 2 dashboard (total screenshots, total steps, zones
-- visited, days played) stays visible above three sub-views:
-- Screenshots (grouped by day), Steps (seven-day chart, daily list) and
-- Locations (zones by day). Long lists reuse a few row frames
-- (W.ScrollList) instead of creating one frame per record.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local WIDTH = UI.CONTENT_WIDTH
local VIEW_TOP = 260     -- sub-views start below the dashboard and buttons
local VIEW_HEIGHT = 310  -- content height (570) - VIEW_TOP

---------------------------------------------------------------------------
-- Shots
---------------------------------------------------------------------------
local SHOT_ROW = 40

local function makeShotListRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.shot = W.Panel(row, W.COLORS.panel, W.COLORS.divider)
    row.shot:SetPoint("TOPLEFT", 0, -2)
    row.shot:SetPoint("BOTTOMRIGHT", 0, 2)
    row.inner = UI.MakeShotRow(row.shot, 26)
    row.inner:SetPoint("TOPLEFT", 8, 0)
    row.inner:SetPoint("BOTTOMRIGHT", 0, 0)
    row.day = W.Text(row, "", "GameFontNormal", W.COLORS.heading)
    row.day:SetPoint("BOTTOMLEFT", 0, 8)
    row.count = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.count:SetPoint("BOTTOMRIGHT", -8, 8)
    row.count:SetJustifyH("RIGHT")
    return row
end

local function fillShotListRow(row, item)
    local isDay = item.kind == "day"
    row.shot:SetShown(not isDay)
    row.day:SetShown(isDay)
    row.count:SetShown(isDay)
    if isDay then
        row.day:SetText(ns.History.DayLabel(item.day))
        row.count:SetText(ns.Count(item.count, "SHOTS"))
    else
        UI.FillShotRow(row.inner, item.record, false)
    end
end

local function buildShots(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -VIEW_TOP)
    view:SetPoint("BOTTOMRIGHT", 0, 0)
    local list = W.ScrollList(view, WIDTH, VIEW_HEIGHT - 26, SHOT_ROW, makeShotListRow, fillShotListRow)
    list:SetPoint("TOPLEFT", 0, 0)
    local empty = W.Text(view, L.NO_SHOTS_YET, "GameFontHighlight", W.COLORS.muted)
    empty:SetPoint("TOPLEFT", 0, -12)
    local line = W.Divider(view)
    line:SetPoint("BOTTOMLEFT", 0, 20)
    line:SetPoint("BOTTOMRIGHT", 0, 20)
    local note = W.Text(view, L.SCREENSHOTS_FOLDER_NOTE, "GameFontHighlightSmall", W.COLORS.muted)
    note:SetPoint("BOTTOMLEFT", 0, 2)
    function view:Refresh()
        local rows = ns.History.Rows()
        list:SetItems(rows, true)
        empty:SetShown(#rows == 0)
    end
    view.list = list
    return view
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local CHART_HEIGHT = 66

local function buildChart(parent)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(WIDTH, CHART_HEIGHT + 40)
    local base = W.Divider(chart)
    base:SetPoint("BOTTOMLEFT", 0, 20)
    base:SetPoint("BOTTOMRIGHT", 0, 20)
    local bars = {}
    local slot = WIDTH / 7
    for i = 1, 7 do
        local column = CreateFrame("Frame", nil, chart)
        column:SetSize(slot, CHART_HEIGHT + 40)
        column:SetPoint("BOTTOMLEFT", (i - 1) * slot, 0)
        column.bar = column:CreateTexture(nil, "ARTWORK")
        column.bar:SetWidth(slot * 0.62)
        column.bar:SetPoint("BOTTOM", column, "BOTTOM", 0, 21)
        column.value = W.Text(column, "", "GameFontHighlightSmall", W.COLORS.heading)
        column.value:SetPoint("BOTTOM", column.bar, "TOP", 0, 3)
        column.value:SetJustifyH("CENTER")
        column.date = W.Text(column, "", "GameFontHighlightSmall", W.COLORS.muted)
        column.date:SetPoint("BOTTOM", column, "BOTTOM", 0, 3)
        column.date:SetJustifyH("CENTER")
        W.Tooltip(column, function()
            return ns.Count(column.steps or 0, "STEPS")
        end, function() return column.dayLabel end)
        bars[i] = column
    end
    function chart:Refresh()
        local today = ns.Util.DayKey(ns.API.Time())
        local values, top = {}, 0
        for i = 1, 7 do
            local day = ns.Util.DayBefore(today, 7 - i)
            values[i] = { day = day, steps = ns.Steps.OnDay(day) }
            top = math.max(top, values[i].steps)
        end
        for i, column in ipairs(bars) do
            local v = values[i]
            local isToday = i == 7
            local height = top > 0 and v.steps / top * CHART_HEIGHT or 0
            column.bar:SetHeight(math.max(1, height))
            column.bar:SetShown(v.steps > 0) -- a day without steps has no bar
            local c = isToday and W.COLORS.gold or W.COLORS.divider
            column.bar:SetColorTexture(c[1], c[2], c[3], isToday and 1 or 0.9)
            column.value:SetText(v.steps > 0 and ns.Num(v.steps) or "")
            local d = date("*t", ns.Util.DayStart(v.day))
            column.date:SetText(string.format("%02d.%02d", d.day, d.month))
            local dc = isToday and W.COLORS.heading or W.COLORS.muted
            column.date:SetTextColor(dc[1], dc[2], dc[3])
            column.steps = v.steps
            column.dayLabel = ns.History.DayLabel(v.day)
        end
    end
    return chart
end

local DAY_ROW = 30

local function makeDayRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.icon = W.Icon(row, "Interface\\Icons\\Ability_Rogue_Sprint", 16)
    row.icon:SetPoint("LEFT", 0, 0)
    row.day = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
    row.day:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.steps = W.Text(row, "", "GameFontNormal", W.COLORS.heading)
    row.steps:SetPoint("RIGHT", -8, 0)
    row.steps:SetJustifyH("RIGHT")
    row.line = W.Divider(row)
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", -8, 0)
    return row
end

local function fillDayRow(row, item)
    row.day:SetText(ns.History.DayLabel(item.day))
    row.steps:SetText(ns.Num(item.steps))
end

local function buildSteps(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -VIEW_TOP)
    view:SetPoint("BOTTOMRIGHT", 0, 0)

    local chartTitle = W.Text(view, L.LAST_7_DAYS, "GameFontNormal", W.COLORS.heading)
    chartTitle:SetPoint("TOPLEFT", 0, 0)
    local chart = buildChart(view)
    chart:SetPoint("TOPLEFT", 0, -16)

    local list = W.ScrollList(view, WIDTH, VIEW_HEIGHT - 150, DAY_ROW, makeDayRow, fillDayRow)
    list:SetPoint("TOPLEFT", 0, -128)
    local empty = W.Text(view, L.NO_STEPS_YET, "GameFontHighlight", W.COLORS.muted)
    empty:SetPoint("TOPLEFT", 0, -136)
    local note = W.Text(view, L.STEPS_NOTE, "GameFontHighlightSmall", W.COLORS.muted)
    note:SetPoint("BOTTOMLEFT", 0, 2)

    function view:Refresh()
        chart:Refresh()
        local days = ns.Steps.Days()
        list:SetItems(days, true)
        empty:SetShown(#days == 0)
    end
    return view
end

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------
local ZONE_ROW = 40

local function makeZoneRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.zone = W.Panel(row, W.COLORS.panel, W.COLORS.divider)
    row.zone:SetPoint("TOPLEFT", 0, -2)
    row.zone:SetPoint("BOTTOMRIGHT", 0, 2)
    row.icon = W.IconBox(row.zone, "Interface\\Icons\\INV_Misc_Map_01", 26)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = W.Text(row.zone, "", "GameFontHighlight", W.COLORS.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetPoint("RIGHT", row.zone, "RIGHT", -150, 0)
    row.first = W.Text(row.zone, L.FIRST_VISIT, "GameFontHighlightSmall", W.COLORS.active)
    row.first:SetPoint("RIGHT", row.zone, "RIGHT", -60, 0)
    row.first:SetJustifyH("RIGHT")
    row.time = W.Text(row.zone, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.time:SetPoint("RIGHT", row.zone, "RIGHT", -8, 0)
    row.time:SetJustifyH("RIGHT")
    row.day = W.Text(row, "", "GameFontNormal", W.COLORS.heading)
    row.day:SetPoint("BOTTOMLEFT", 0, 8)
    row.count = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.count:SetPoint("BOTTOMRIGHT", -8, 8)
    row.count:SetJustifyH("RIGHT")
    return row
end

local function fillZoneRow(row, item)
    local isDay = item.kind == "day"
    row.zone:SetShown(not isDay)
    row.day:SetShown(isDay)
    row.count:SetShown(isDay)
    if isDay then
        row.day:SetText(ns.History.DayLabel(item.day))
        row.count:SetText(ns.Count(item.count, "ZONES"))
    else
        row.name:SetText(item.entry.name)
        row.first:SetShown(item.entry.first == true)
        row.time:SetText(date("%H:%M", item.entry.t))
    end
end

local function buildLocations(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -VIEW_TOP)
    view:SetPoint("BOTTOMRIGHT", 0, 0)
    local list = W.ScrollList(view, WIDTH, VIEW_HEIGHT, ZONE_ROW, makeZoneRow, fillZoneRow)
    list:SetPoint("TOPLEFT", 0, 0)
    local empty = W.Text(view, L.NO_ZONES_YET, "GameFontHighlight", W.COLORS.muted)
    empty:SetPoint("TOPLEFT", 0, -12)
    function view:Refresh()
        local rows = ns.Locations.Rows()
        list:SetItems(rows, true)
        empty:SetShown(#rows == 0)
    end
    return view
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
UI.builders.history = function(parent)
    local refreshHeader = UI.CharacterHeader(parent, L.LIFETIME_STATS)
    local cards = UI.Dashboard(parent, 44, {
        { "shots", "Interface\\Icons\\INV_Misc_Spyglass_03", L.STAT_TOTAL, L.TIP_STAT_TOTAL },
        { "steps", "Interface\\Icons\\Ability_Rogue_Sprint", L.TOTAL_STEPS, L.STEPS_NOTE },
        { "zones", "Interface\\Icons\\INV_Misc_Map_01", L.STAT_ZONES_TOTAL, L.TIP_STAT_ZONES_TOTAL },
        { "days", "Interface\\Icons\\INV_Misc_Note_01", L.STAT_DAYS_PLAYED, L.TIP_STAT_DAYS_PLAYED },
    })

    local order = { "shots", "steps", "zones" }
    local labels = { shots = L.SUB_SHOTS, steps = L.SUB_STEPS, zones = L.SUB_ZONES }
    local views = { shots = buildShots(parent), steps = buildSteps(parent), zones = buildLocations(parent) }
    local buttons = {}
    local current = "shots"

    local function select(id)
        current = views[id] and id or "shots"
        for key, view in pairs(views) do
            view:SetShown(key == current)
            buttons[key]:SetSelected(key == current)
        end
        views[current]:Refresh()
    end
    local gap = 6
    local third = (WIDTH - 2 * gap) / 3
    for i, id in ipairs(order) do
        buttons[id] = W.Button(parent, labels[id], third, 30, function() select(id) end)
        buttons[id]:SetPoint("TOPLEFT", (i - 1) * (third + gap), -222)
    end

    local function refreshSteps()
        cards.steps.value:SetText(ns.Num(ns.Steps.Total()))
        if current == "steps" then
            views.steps:Refresh()
        end
    end
    return {
        -- Opening the tab from elsewhere (e.g. Home's link) picks a sub-view.
        Select = function(id) current = id end,
        Refresh = function()
            refreshHeader()
            cards.shots.value:SetText(ns.Num(ns.History.Stats().total))
            cards.zones.value:SetText(ns.Num(ns.Locations.Total()))
            cards.days.value:SetText(ns.Num(ns.Activity.DaysPlayed()))
            refreshSteps()
            select(current)
        end,
        RefreshSteps = refreshSteps,
    }
end
