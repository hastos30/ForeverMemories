-- UI/History.lua
-- "History" tab (spec 5, v0.9.0): the adventure diary of the current
-- character. The header and the 2 x 2 lifetime dashboard (total
-- screenshots, total steps, locations visited, total playtime) and the
-- two rows of sub-view buttons always stay in place; below them each
-- sub-view is ONE scrolling list (W.FlexList) of rows of different kinds:
--   Overview  - Adventure Calendar (12 weeks), the selected day, Recap
--   Screenshots - shots grouped by day (unchanged since 0.8.0)
--   Steps     - 7 / 30 day chart and the daily list
--   Locations - World Explorer: progress, filters, search, regions,
--               zones and the daily location history
--   Playtime  - 7 / 30 day chart, days played, average, longest session,
--               sessions, daily list
--   Journey   - timeline of important moments
--   Records   - personal records (v0.12.0)
--   Achievements - own achievements with filters (v0.13.0)
-- Overview also shows "On this day" (v0.13.0). The Character / All
-- characters switch (v0.12.0) shows the account and opens other
-- characters read-only.
-- Only visible rows have frames, so long histories stay cheap.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local WIDTH = UI.CONTENT_WIDTH
local INNER = WIDTH - 8 -- FlexList rows leave room for the scroll bar
local BUTTONS_TOP = 222  -- two rows of sub-view buttons (v0.12.0)
local VIEW_TOP = 294     -- sub-views start below the dashboard and buttons
local VIEW_HEIGHT = 276  -- content height (570) - VIEW_TOP

local ICON = {
    shots = "Interface\\Icons\\INV_Misc_Spyglass_03",
    steps = "Interface\\Icons\\Ability_Rogue_Sprint",
    zones = "Interface\\Icons\\INV_Misc_Map_01",
    newZones = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    playtime = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    days = "Interface\\Icons\\INV_Misc_Book_09",
    calendar = "Interface\\Icons\\INV_Misc_Note_01",
    sessions = "Interface\\Icons\\INV_Misc_PocketWatch_02",
}
UI.ICON = ICON

-- Fill colors of the calendar levels 0..4 and of "no data".
local LEVEL_COLORS = {
    [0] = { 0.165, 0.149, 0.125 }, -- dark
    { 0.353, 0.275, 0.188 },       -- muted brown
    { 0.541, 0.416, 0.235 },       -- bronze
    { 0.788, 0.639, 0.369 },       -- gold
    { 0.910, 0.812, 0.627 },       -- light gold
}
UI.LEVEL_COLORS = LEVEL_COLORS

local function setColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

-- "24 November · Today" for today, "23.11.2026" otherwise (daily lists).
local function shortDay(day)
    if day == ns.Util.DayKey(ns.API.Time()) then
        return ns.History.DayLabel(day)
    end
    local d = date("*t", ns.Util.DayStart(day))
    return string.format("%02d.%02d.%04d", d.day, d.month, d.year)
end

-- "1:05" from seconds (chart labels).
local function clock(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    return string.format("%d:%02d", math.floor(minutes / 60), minutes % 60)
end

---------------------------------------------------------------------------
-- Row kinds shared by several sub-views.
---------------------------------------------------------------------------
local COMMON = {}

-- Section title with an optional text on the right.
COMMON.heading = {
    height = 30,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = W.Text(row, "", "GameFontNormalLarge", W.COLORS.heading)
        row.text:SetPoint("LEFT", 0, 0)
        row.right = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
        row.right:SetPoint("RIGHT", 0, 0)
        row.right:SetJustifyH("RIGHT")
        return row
    end,
    fill = function(row, item)
        row.text:SetText(item.text)
        row.right:SetText(item.right or "")
    end,
}

-- Day group header: "24 November · Today" ... "8 locations".
COMMON.day = {
    height = 32,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.day = W.Text(row, "", "GameFontNormal", W.COLORS.heading)
        row.day:SetPoint("BOTTOMLEFT", 0, 7)
        row.count = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
        row.count:SetPoint("BOTTOMRIGHT", -8, 7)
        row.count:SetJustifyH("RIGHT")
        return row
    end,
    fill = function(row, item)
        row.day:SetText(ns.History.DayLabel(item.day))
        row.count:SetText(item.count or "")
    end,
}

-- Grey text: notes, empty states.
COMMON.note = {
    height = 26,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetPoint("RIGHT", 0, 0)
        return row
    end,
    fill = function(row, item)
        row.text:SetText(item.text)
        local c = item.color or W.COLORS.muted
        setColor(row.text, c)
    end,
}

-- Icon, label and a value on the right, with a thin line below (daily
-- lists, recap).
COMMON.value = {
    height = 32,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.icon = W.Icon(row, ICON.steps, 16)
        row.icon:SetPoint("LEFT", 0, 0)
        row.label = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.value = W.Text(row, "", "GameFontNormal", W.COLORS.heading)
        row.value:SetPoint("RIGHT", -8, 0)
        row.value:SetJustifyH("RIGHT")
        row.line = W.Divider(row)
        row.line:SetPoint("BOTTOMLEFT", 0, 0)
        row.line:SetPoint("BOTTOMRIGHT", -8, 0)
        return row
    end,
    fill = function(row, item)
        row.icon:SetTexture(item.icon)
        row.label:SetText(item.label)
        row.value:SetText(item.value)
    end,
}

---------------------------------------------------------------------------
-- Viewing another character (v0.12.0). History can show any saved
-- character read-only: while a view computes or fills its rows,
-- ns.character is that character, and it is put back right after (also
-- on an error). Nothing in History writes data, and Home, the clock and
-- every tracker keep working with the current character only.
---------------------------------------------------------------------------
local viewed -- key of the character shown, nil = the current one

local function viewedCharacter()
    if viewed and viewed ~= ns.characterKey then
        return ns.db.characters[viewed]
    end
end

local function withViewed(fn, ...)
    local character = viewedCharacter()
    if not character then
        return fn(...)
    end
    local saved = ns.character
    ns.character = character
    local ok, a, b = pcall(fn, ...)
    ns.character = saved
    if not ok then
        error(a, 0)
    end
    return a, b
end

-- kinds of a view = COMMON + its own; every fill sees the viewed character.
local function kindsWith(own)
    local kinds = {}
    local function add(key, kind)
        local copy = {}
        for field, value in pairs(kind) do
            copy[field] = value
        end
        copy.fill = function(...) return withViewed(kind.fill, ...) end
        kinds[key] = copy
    end
    for key, kind in pairs(COMMON) do
        add(key, kind)
    end
    for key, kind in pairs(own or {}) do
        add(key, kind)
    end
    return kinds
end

local function newView(parent, own, top)
    top = top or VIEW_TOP
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -top)
    view:SetPoint("BOTTOMRIGHT", 0, 0)
    view.list = W.FlexList(view, WIDTH, VIEW_HEIGHT + VIEW_TOP - top, kindsWith(own))
    view.list:SetPoint("TOPLEFT", 0, 0)
    return view
end

-- Shows `items`; with `day` scrolls to the row anchored to that day.
local function show(view, items, keep, day)
    view.list:SetItems(items, keep)
    if day then
        view.list:ScrollTo(function(item) return item.anchor == day end)
    end
end

---------------------------------------------------------------------------
-- Bar chart for 7 or 30 days (Steps and Playtime).
--   item.bars = { { day, value, label, tip }, ... }
---------------------------------------------------------------------------
local CHART_BARS = 96
local MAX_COLUMNS = 30

local function makeChart(parent)
    local chart = CreateFrame("Frame", nil, parent)
    local base = W.Divider(chart)
    base:SetPoint("BOTTOMLEFT", 0, 20)
    base:SetPoint("BOTTOMRIGHT", 0, 20)
    chart.columns = {}
    for i = 1, MAX_COLUMNS do
        local column = CreateFrame("Frame", nil, chart)
        column.bar = column:CreateTexture(nil, "ARTWORK")
        column.bar:SetPoint("BOTTOM", column, "BOTTOM", 0, 21)
        column.value = W.Text(column, "", "GameFontHighlightSmall", W.COLORS.heading)
        column.value:SetPoint("BOTTOM", column.bar, "TOP", 0, 3)
        column.value:SetJustifyH("CENTER")
        column.date = W.Text(column, "", "GameFontHighlightSmall", W.COLORS.muted)
        column.date:SetPoint("BOTTOM", column, "BOTTOM", 0, 3)
        column.date:SetJustifyH("CENTER")
        W.Tooltip(column, function() return column.tip end, function() return column.dayLabel end)
        chart.columns[i] = column
    end
    return chart
end

local function fillChart(chart, item)
    local bars = item.bars
    local n = #bars
    local slot = INNER / n
    local top = 0
    for _, bar in ipairs(bars) do
        top = math.max(top, bar.value)
    end
    local today = ns.Util.DayKey(ns.API.Time())
    for i, column in ipairs(chart.columns) do
        local bar = bars[i]
        column:SetShown(bar ~= nil)
        if bar then
            column:ClearAllPoints()
            column:SetSize(slot, CHART_BARS + 40)
            column:SetPoint("BOTTOMLEFT", (i - 1) * slot, 0)
            local isToday = bar.day == today
            column.bar:SetWidth(math.max(2, slot * 0.62))
            column.bar:SetHeight(math.max(1, top > 0 and bar.value / top * CHART_BARS or 0))
            column.bar:SetShown(bar.value > 0) -- a day without activity has no bar
            local c = isToday and W.COLORS.gold or LEVEL_COLORS[2]
            column.bar:SetColorTexture(c[1], c[2], c[3], isToday and 1 or 0.9)
            -- 7 days: every value and date; 30 days: dates every 5th day.
            column.value:SetText(n <= 7 and bar.label or "")
            local d = date("*t", ns.Util.DayStart(bar.day))
            local dated = n <= 7 or isToday or (n - i) % 5 == 0
            column.date:SetText(dated and string.format("%02d.%02d", d.day, d.month) or "")
            setColor(column.date, isToday and W.COLORS.heading or W.COLORS.muted)
            column.tip = bar.tip
            column.dayLabel = ns.History.DayLabel(bar.day)
        end
    end
end

-- Heading with a 7 / 30 days switch (shown only when there is data
-- older than seven days).
local function makeChartHeader(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.text = W.Text(row, "", "GameFontNormalLarge", W.COLORS.heading)
    row.text:SetPoint("LEFT", 0, 0)
    row.switch = W.Segmented(row, { { 7, L.DAYS_7 }, { 30, L.DAYS_30 } }, 150, function(value)
        if row.onSelect then row.onSelect(value) end
    end)
    row.switch:SetPoint("RIGHT", 0, 0)
    return row
end

local function fillChartHeader(row, item)
    row.text:SetText(item.text)
    row.switch:SetShown(item.switch)
    row.switch:SetValue(item.days)
    row.onSelect = item.onSelect
end

local function chartBars(days, value, label, tip)
    local today = ns.Util.DayKey(ns.API.Time())
    local bars = {}
    for i = 1, days do
        local day = ns.Util.DayBefore(today, days - i)
        local v = value(day)
        bars[i] = { day = day, value = v, label = label(v), tip = tip(v) }
    end
    return bars
end

local CHART_KINDS = {
    chartHeader = { height = 34, make = makeChartHeader, fill = fillChartHeader },
    chart = { height = CHART_BARS + 50, make = makeChart, fill = fillChart },
}

---------------------------------------------------------------------------
-- Screenshots (v0.11.0: search, filters, sort). Search and filters work on
-- the metadata of registered shots only; image files are never opened.
---------------------------------------------------------------------------
local SHOT_TYPES = { "all" }
for _, id in ipairs(ns.Registry.EVENTS) do
    SHOT_TYPES[#SHOT_TYPES + 1] = id
end
SHOT_TYPES[#SHOT_TYPES + 1] = "PASSIVE"
SHOT_TYPES[#SHOT_TYPES + 1] = "MANUAL"

local function newShotFilter()
    return { text = "", type = "all", zone = nil, from = nil, to = nil, fromText = "", toText = "", order = "new" }
end

-- True when the filter differs from "all shots, newest first".
local function filtered(f)
    return f.text ~= "" or f.type ~= "all" or f.zone ~= nil or f.fromText ~= "" or f.toText ~= "" or f.order ~= "new"
end

local function buildShots(parent)
    local view
    local state = { filter = newShotFilter(), open = false }
    local zoneOptions = { { value = false, text = L.FILTER_ALL_ZONES } }
    local function refresh()
        view:Refresh(nil, true)
    end
    local function dateBox(row, key)
        local box = W.SearchBox(row, L.DATE_HINT, 120, function(text)
            local f = state.filter
            f[key .. "Text"] = text
            f[key] = ns.Util.ParseDate(text)
            refresh()
        end)
        box:SetMaxLetters(10)
        return box
    end
    view = newView(parent, {
        shot = {
            height = 44,
            make = function(p)
                local row = W.Panel(p, W.COLORS.panel, W.COLORS.divider)
                row.inner = UI.MakeShotRow(row, 26)
                row.inner:SetPoint("TOPLEFT", 8, -4)
                row.inner:SetPoint("BOTTOMRIGHT", 0, 4)
                return row
            end,
            fill = function(row, item)
                UI.FillShotRow(row.inner, item.record, false)
            end,
        },
        shotSearch = {
            height = 38,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.edit = W.SearchBox(row, L.SEARCH_SHOTS, INNER - 140, function(text)
                    state.filter.text = text
                    refresh()
                end)
                row.edit:SetPoint("LEFT", 0, 0)
                row.toggle = W.Button(row, "", 130, 28, function()
                    state.open = not state.open
                    refresh()
                end)
                row.toggle:SetPoint("RIGHT", 0, 0)
                W.Tooltip(row.toggle, L.TIP_SHOT_FILTERS, L.FILTERS)
                return row
            end,
            fill = function(row)
                if (row.edit:GetText() or "") ~= state.filter.text then
                    row.edit:SetText(state.filter.text)
                end
                row.toggle:SetLabel(L.FILTERS .. (state.open and "  v" or "  >"))
                row.toggle:SetSelected(state.open)
            end,
        },
        shotFilters = {
            height = 76,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                local half = (INNER - 10) / 2
                local typeOptions = {}
                for _, id in ipairs(SHOT_TYPES) do
                    typeOptions[#typeOptions + 1] = { value = id,
                        text = id == "all" and L.FILTER_ALL_TYPES or L["EVENT_" .. id] }
                end
                row.kind = W.Dropdown(row, typeOptions, function() return state.filter.type end,
                    function(value) state.filter.type = value; refresh() end, half)
                row.kind:SetPoint("TOPLEFT", 0, -2)
                W.Tooltip(row.kind, L.TIP_FILTER_TYPE, L.FILTER_TYPE)
                row.zone = W.Dropdown(row, zoneOptions, function() return state.filter.zone or false end,
                    function(value) state.filter.zone = value or nil; refresh() end, half)
                row.zone:SetPoint("TOPRIGHT", 0, -2)
                W.Tooltip(row.zone, L.TIP_FILTER_ZONE, L.FILTER_ZONE)
                row.fromLabel = W.Text(row, L.DATE_FROM, "GameFontHighlightSmall", W.COLORS.muted)
                row.fromLabel:SetPoint("BOTTOMLEFT", 0, 12)
                row.from = dateBox(row, "from")
                row.from:SetPoint("BOTTOMLEFT", 24, 4)
                row.toLabel = W.Text(row, L.DATE_TO, "GameFontHighlightSmall", W.COLORS.muted)
                row.toLabel:SetPoint("LEFT", row.from, "RIGHT", 10, 0)
                row.to = dateBox(row, "to")
                row.to:SetPoint("LEFT", row.toLabel, "RIGHT", 8, 0)
                W.Tooltip(row.from, L.TIP_FILTER_DATES, L.DATE_RANGE)
                W.Tooltip(row.to, L.TIP_FILTER_DATES, L.DATE_RANGE)
                row.order = W.Dropdown(row, {
                    { value = "new", text = L.SORT_NEW }, { value = "old", text = L.SORT_OLD },
                }, function() return state.filter.order end,
                    function(value) state.filter.order = value; refresh() end, 170)
                row.order:SetPoint("BOTTOMRIGHT", 0, 4)
                return row
            end,
            fill = function(row)
                local f = state.filter
                row.kind:Refresh()
                row.zone:Refresh()
                row.order:Refresh()
                if (row.from:GetText() or "") ~= f.fromText then row.from:SetText(f.fromText) end
                if (row.to:GetText() or "") ~= f.toText then row.to:SetText(f.toText) end
            end,
        },
        shotCount = {
            height = 28,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.text = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.text)
                row.text:SetPoint("LEFT", 0, 0)
                row.reset = W.Link(row, L.RESET_FILTERS, function()
                    state.filter = newShotFilter()
                    refresh()
                end)
                row.reset:SetPoint("RIGHT", 0, 0)
                return row
            end,
            fill = function(row, item)
                row.text:SetText(item.text)
                setColor(row.text, item.invalid and W.COLORS.error or W.COLORS.text)
                row.reset:SetShown(item.canReset)
            end,
        },
    })
    function view:Refresh(day, keep)
        -- Location filter: the zones of this character's shots.
        for i = #zoneOptions, 2, -1 do
            zoneOptions[i] = nil
        end
        for _, zone in ipairs(ns.History.ShotZones()) do
            zoneOptions[#zoneOptions + 1] = { value = zone, text = zone }
        end
        local f = state.filter
        local items = { { kind = "shotSearch" } }
        if state.open then
            items[#items + 1] = { kind = "shotFilters" }
        end
        local results = ns.History.Search(f)
        local invalid = (f.fromText ~= "" and not f.from) or (f.toText ~= "" and not f.to)
        items[#items + 1] = { kind = "shotCount", canReset = filtered(f), invalid = invalid,
            text = invalid and L.INVALID_DATE or string.format(L.FOUND_COUNT, ns.Num(#results)) }
        local header
        for _, record in ipairs(results) do
            local d = ns.Util.DayKey(record.t)
            if not header or header.day ~= d then
                header = { kind = "day", day = d, n = 0, anchor = d }
                items[#items + 1] = header
            end
            header.n = header.n + 1
            items[#items + 1] = { kind = "shot", record = record }
        end
        for _, item in ipairs(items) do
            if item.kind == "day" then
                item.count = ns.Count(item.n, "SHOTS")
            end
        end
        if #results == 0 then
            items[#items + 1] = { kind = "note", text = filtered(f) and L.NOTHING_FOUND or L.NO_SHOTS_YET }
        end
        items[#items + 1] = { kind = "note", text = L.SCREENSHOTS_FOLDER_NOTE }
        show(self, items, keep, day)
    end
    return view
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local function buildSteps(parent)
    local view = newView(parent, CHART_KINDS)
    view.days = 7
    function view:Refresh(day, keep)
        local steps = ns.character and ns.character.steps.days or {}
        local first = ns.Adventure.FirstDay(steps)
        local today = ns.Util.DayKey(ns.API.Time())
        local hasMore = first ~= nil and first < ns.Util.DayBefore(today, 6)
        if not hasMore then
            self.days = 7
        end
        local items = {
            { kind = "chartHeader", text = L.SUB_STEPS, days = self.days, switch = hasMore,
              onSelect = function(value) self.days = value; self:Refresh() end },
            { kind = "chart", bars = chartBars(self.days, ns.Steps.OnDay, ns.Num,
                function(v) return ns.Count(v, "STEPS") end) },
            { kind = "heading", text = L.DAILY_HISTORY },
        }
        for _, entry in ipairs(ns.Adventure.DailyList(first, ns.Steps.OnDay)) do
            items[#items + 1] = { kind = "value", icon = ICON.steps, label = shortDay(entry.day),
                                  value = ns.Num(entry.value), anchor = entry.day }
        end
        if not first then
            items[#items + 1] = { kind = "note", text = L.NO_STEPS_YET }
        end
        items[#items + 1] = { kind = "note", text = L.STEPS_NOTE }
        show(self, items, keep, day)
    end
    return view
end

---------------------------------------------------------------------------
-- Playtime
---------------------------------------------------------------------------
local function buildPlaytime(parent)
    local view = newView(parent, {
        chartHeader = CHART_KINDS.chartHeader,
        chart = CHART_KINDS.chart,
        tiles = {
            height = 176,
            make = function(p)
                local frame = CreateFrame("Frame", nil, p)
                frame.cards = UI.Dashboard(frame, 4, {
                    { "days", ICON.days, L.DAYS_PLAYED, L.TIP_DAYS_PLAYED },
                    { "average", ICON.playtime, L.AVERAGE_PLAYTIME, L.TIP_AVERAGE_PLAYTIME },
                    { "longest", ICON.sessions, L.LONGEST_SESSION, L.TIP_LONGEST_SESSION },
                    { "sessions", ICON.calendar, L.SESSIONS, L.TIP_SESSIONS },
                }, INNER)
                return frame
            end,
            fill = function(frame, item)
                frame.cards.days.value:SetText(ns.Num(item.days))
                frame.cards.average.value:SetText(item.days > 0 and UI.FormatDuration(item.average) or L.NO_DATA)
                frame.cards.longest.value:SetText(item.sessions > 0 and UI.FormatDuration(item.longest) or L.NO_DATA)
                frame.cards.sessions.value:SetText(item.sessions > 0 and ns.Num(item.sessions) or L.NO_DATA)
            end,
        },
    })
    view.days = 7
    function view:Refresh(day, keep)
        local played = ns.character and ns.character.playtime.days or {}
        local first = ns.Activity.SinceDay() or ns.Adventure.FirstDay(played)
        local today = ns.Util.DayKey(ns.API.Time())
        local hasMore = first ~= nil and first < ns.Util.DayBefore(today, 6)
        if not hasMore then
            self.days = 7
        end
        local days, _, average = ns.Activity.PlayedDays()
        local sessions, longest = ns.Activity.Sessions()
        local items = {
            { kind = "chartHeader", text = L.PLAYTIME_HEADING, days = self.days, switch = hasMore,
              onSelect = function(value) self.days = value; self:Refresh() end },
            { kind = "chart", bars = chartBars(self.days, ns.Activity.OnDay, clock, UI.FormatDuration) },
            { kind = "tiles", days = days, average = average, sessions = sessions, longest = longest },
            { kind = "note", text = L.PLAYTIME_NOTE, height = 30 },
            { kind = "heading", text = L.DAILY_HISTORY },
        }
        for _, entry in ipairs(ns.Adventure.DailyList(first, ns.Activity.OnDay)) do
            items[#items + 1] = { kind = "value", icon = ICON.playtime, label = shortDay(entry.day),
                                  value = UI.FormatDuration(entry.value), anchor = entry.day }
        end
        if not first then
            items[#items + 1] = { kind = "note", text = L.NO_PLAYTIME_YET }
        end
        show(self, items, keep, day)
    end
    return view
end

---------------------------------------------------------------------------
-- Locations: World Explorer and Location History
---------------------------------------------------------------------------
local CHECK_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local DOT_ICON = "Interface\\COMMON\\Indicator-Gray"

local function progressBar(parent, height)
    local track = parent:CreateTexture(nil, "ARTWORK")
    track:SetHeight(height)
    local d = W.COLORS.divider
    track:SetColorTexture(d[1], d[2], d[3], 1)
    local fill = parent:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(height)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    local g = W.COLORS.gold
    fill:SetColorTexture(g[1], g[2], g[3], 1)
    function track:SetProgress(fraction, width)
        fill:SetWidth(math.max(1, width * fraction))
        fill:SetShown(fraction > 0)
    end
    return track
end

local function percentText(value)
    return ns.Dec(value, 1) .. "%"
end

local function buildLocations(parent)
    local view
    local state = { filter = "all", search = "", expanded = {}, history = false, card = nil }

    local kinds = {
        progress = {
            height = 104,
            make = function(p)
                local box = W.Panel(p, W.COLORS.panel, W.COLORS.gold)
                box.label = W.Text(box, L.EXPLORATION_PROGRESS, "GameFontHighlight", W.COLORS.text)
                box.label:SetPoint("TOPLEFT", 14, -12)
                box.count = W.Text(box, "", "GameFontNormalHuge", W.COLORS.heading)
                box.count:SetPoint("TOPLEFT", 14, -32)
                box.percent = W.Text(box, "", "GameFontNormalHuge", W.COLORS.heading)
                box.percent:SetPoint("TOPRIGHT", -14, -28)
                box.percent:SetJustifyH("RIGHT")
                box.bar = progressBar(box, 6)
                box.bar:SetPoint("TOPLEFT", 14, -66)
                box.bar:SetPoint("TOPRIGHT", -14, -66)
                box.visited = W.Text(box, "", "GameFontHighlightSmall", W.COLORS.active)
                box.visited:SetPoint("BOTTOMLEFT", 14, 10)
                box.left = W.Text(box, "", "GameFontHighlightSmall", W.COLORS.muted)
                box.left:SetPoint("BOTTOMRIGHT", -14, 10)
                box.left:SetJustifyH("RIGHT")
                W.Tooltip(box, L.TIP_EXPLORER, L.WORLD_EXPLORER)
                return box
            end,
            fill = function(box, item)
                local e = item.explorer
                box.count:SetText(ns.Num(e.visited) .. " / " .. ns.Num(e.total))
                box.percent:SetText(e.percent and percentText(e.percent) or L.NO_DATA)
                box.bar:SetProgress(e.percent and e.percent / 100 or 0, INNER - 28)
                box.visited:SetText(string.format(L.VISITED_COUNT, ns.Num(e.visited)))
                box.left:SetText(e.percent and string.format(L.LEFT_COUNT, ns.Num(e.total - e.visited))
                    or L.CATALOG_UNAVAILABLE)
            end,
        },
        filters = {
            height = 38,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.switch = W.Segmented(row, {
                    { "all", L.FILTER_ALL }, { "visited", L.FILTER_VISITED }, { "unvisited", L.FILTER_UNVISITED },
                }, 390, function(value)
                    state.filter = value
                    view:Refresh(nil, true)
                end)
                row.switch:SetPoint("LEFT", 0, 0)
                return row
            end,
            fill = function(row) row.switch:SetValue(state.filter) end,
        },
        search = {
            height = 38,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.edit = W.SearchBox(row, L.SEARCH_ZONE, INNER, function(text)
                    state.search = text
                    view:Refresh(nil, true)
                end)
                row.edit:SetPoint("LEFT", 0, 0)
                return row
            end,
            fill = function(row)
                if (row.edit:GetText() or "") ~= state.search then
                    row.edit:SetText(state.search)
                end
            end,
        },
        region = {
            height = 60,
            make = function(p)
                local box = CreateFrame("Button", nil, p, "BackdropTemplate")
                W.Backdrop(box, W.COLORS.panel, 0.95, W.COLORS.divider)
                box.arrow = W.Text(box, ">", "GameFontNormal", W.COLORS.gold)
                box.arrow:SetPoint("TOPLEFT", 12, -14)
                box.name = W.Text(box, "", "GameFontNormal", W.COLORS.heading)
                box.name:SetPoint("TOPLEFT", 30, -14)
                box.count = W.Text(box, "", "GameFontHighlightSmall", W.COLORS.text)
                box.count:SetPoint("TOPRIGHT", -12, -15)
                box.count:SetJustifyH("RIGHT")
                box.bar = progressBar(box, 4)
                box.bar:SetPoint("TOPLEFT", 12, -40)
                box.bar:SetPoint("TOPRIGHT", -12, -40)
                box:SetScript("OnClick", function(self)
                    state.expanded[self.id] = not self.open
                    view:Refresh(nil, true)
                end)
                return box
            end,
            fill = function(box, item)
                local r = item.region
                box.id, box.open = r.id, item.open
                box.arrow:SetText(item.open and "v" or ">")
                box.name:SetText(r.name)
                box.count:SetText(string.format("%s/%s  ·  %s", ns.Num(r.visited), ns.Num(r.total), percentText(r.percent)))
                box.bar:SetProgress(r.total > 0 and r.visited / r.total or 0, INNER - 24)
            end,
        },
        zone = {
            height = 40,
            make = function(p)
                local row = CreateFrame("Button", nil, p)
                local g = W.COLORS.gold
                local highlight = row:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints()
                highlight:SetColorTexture(g[1], g[2], g[3], 0.06)
                row.arrow = W.Text(row, ">", "GameFontNormal", W.COLORS.muted)
                row.arrow:SetPoint("RIGHT", -2, 0)
                -- v0.11.0: a click opens the location card.
                row:SetScript("OnClick", function(self)
                    if self.area then
                        state.card = self.area
                        view:Refresh()
                    end
                end)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(14, 14)
                row.icon:SetPoint("LEFT", 16, 0)
                row.name = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
                row.name:SetPoint("LEFT", 40, 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -130, 0)
                row.first = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.first:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
                row.status = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.status:SetPoint("RIGHT", -20, 0)
                row.status:SetJustifyH("RIGHT")
                row.line = W.Divider(row)
                row.line:SetPoint("BOTTOMLEFT", 12, 0)
                row.line:SetPoint("BOTTOMRIGHT", -12, 0)
                return row
            end,
            fill = function(row, item)
                local z = item.zone
                row.area = z.area
                row.icon:SetTexture(z.visited and CHECK_ICON or DOT_ICON)
                row.name:SetText(z.name)
                setColor(row.name, z.visited and W.COLORS.text or W.COLORS.muted)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", 40, z.firstAt and 7 or 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -130, z.firstAt and 7 or 0)
                row.first:SetText(z.firstAt and string.format(L.FIRST_VISIT_DATE, date("%d.%m.%Y", z.firstAt)) or "")
                row.status:SetText(z.visited and L.VISITED or L.UNVISITED)
                setColor(row.status, z.visited and W.COLORS.active or W.COLORS.muted)
            end,
        },
        historyHeader = {
            height = 52,
            make = function(p)
                local box = CreateFrame("Button", nil, p, "BackdropTemplate")
                W.Backdrop(box, W.COLORS.panel, 0.95, W.COLORS.divider)
                box.label = W.Text(box, L.LOCATION_HISTORY, "GameFontNormalLarge", W.COLORS.heading)
                box.label:SetPoint("LEFT", 14, 0)
                box.arrow = W.Text(box, ">", "GameFontNormal", W.COLORS.gold)
                box.arrow:SetPoint("RIGHT", -14, 0)
                box:SetScript("OnClick", function()
                    state.history = not state.history
                    view:Refresh(nil, true)
                end)
                return box
            end,
            fill = function(box)
                box.arrow:SetText(state.history and "v" or ">")
            end,
        },
        visit = {
            height = 40,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.icon = W.Icon(row, ICON.zones, 16)
                row.icon:SetPoint("LEFT", 0, 0)
                row.name = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                row.first = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.active)
                row.first:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
                row.time = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.time:SetPoint("RIGHT", -8, 0)
                row.time:SetJustifyH("RIGHT")
                return row
            end,
            fill = function(row, item)
                local entry = item.entry
                local sub = entry.first and L.FIRST_VISIT
                    or (entry.instance and L["INSTANCE_" .. entry.instance]) or nil
                row.name:SetText(entry.name)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, sub and 7 or 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -80, sub and 7 or 0)
                row.first:SetText(sub or "")
                setColor(row.first, entry.first and W.COLORS.active or W.COLORS.muted)
                row.time:SetText(date("%H:%M", entry.t))
            end,
        },
    }
    -- Location card (v0.11.0).
    kinds.back = {
        height = 34,
        make = function(p)
            local row = CreateFrame("Frame", nil, p)
            row.link = W.Link(row, "<  " .. L.BACK_TO_CATALOG, function()
                state.card = nil
                view:Refresh()
            end)
            row.link:SetPoint("LEFT", -8, 0)
            return row
        end,
        fill = function() end,
    }
    kinds.zoneCard = {
        height = 84,
        make = function(p)
            local box = W.Panel(p, W.COLORS.panel, W.COLORS.gold)
            box.icon = W.IconBox(box, ICON.zones, 48)
            box.icon:SetPoint("LEFT", 14, 0)
            box.name = W.Text(box, "", "GameFontNormalHuge", W.COLORS.heading)
            box.name:SetPoint("TOPLEFT", box.icon, "TOPRIGHT", 14, -2)
            box.name:SetPoint("RIGHT", box, "RIGHT", -14, 0)
            box.region = W.Text(box, "", "GameFontHighlight", W.COLORS.text)
            box.region:SetPoint("BOTTOMLEFT", box.icon, "BOTTOMRIGHT", 14, 2)
            box.status = W.Text(box, "", "GameFontHighlightSmall", W.COLORS.active)
            box.status:SetPoint("BOTTOMRIGHT", -14, 14)
            box.status:SetJustifyH("RIGHT")
            return box
        end,
        fill = function(box, item)
            local c = item.card
            box.name:SetText(c.name)
            box.region:SetText(c.region)
            box.status:SetText(c.visited and L.VISITED or L.UNVISITED)
            setColor(box.status, c.visited and W.COLORS.active or W.COLORS.muted)
            box.icon:SetIcon(c.visited and ICON.zones or ICON.newZones)
        end,
    }
    kinds.cardShot = {
        height = 40,
        make = function(p)
            local row = UI.MakeShotRow(p, 26)
            row.line = W.Divider(row)
            row.line:SetPoint("BOTTOMLEFT", 0, 0)
            row.line:SetPoint("BOTTOMRIGHT", -8, 0)
            return row
        end,
        fill = function(row, item)
            UI.FillShotRow(row, item.record, true)
        end,
    }
    view = newView(parent, kinds)

    local function when(t)
        return t and (ns.History.DateText(ns.Util.DayKey(t)) .. " " .. date("%Y, %H:%M", t)) or L.NO_DATA
    end

    -- Items of the location card of catalog area `area`.
    local function cardItems(area)
        local c = ns.ZoneStats.Card(area, 5)
        if not c then
            state.card = nil
            return nil
        end
        local tracked = c.since ~= nil
        local items = {
            { kind = "back" },
            { kind = "zoneCard", card = c },
            { kind = "value", icon = ICON.playtime, label = L.ZONE_TIME,
              value = tracked and UI.FormatDuration(c.time) or L.NO_DATA },
            { kind = "value", icon = ICON.calendar, label = L.ZONE_DAYS, value = ns.Num(c.days) },
            { kind = "value", icon = ICON.zones, label = L.ZONE_VISITS,
              value = tracked and ns.Num(c.visits) or L.NO_DATA },
            { kind = "value", icon = ICON.steps, label = L.ZONE_STEPS,
              value = tracked and ns.Num(c.steps) or L.NO_DATA },
            { kind = "value", icon = ICON.shots, label = L.ZONE_SHOTS, value = ns.Num(c.shots) },
            { kind = "value", icon = ICON.newZones, label = L.ZONE_FIRST_VISIT, value = when(c.firstAt) },
            { kind = "value", icon = ICON.sessions, label = L.ZONE_LAST_VISIT, value = when(c.lastAt) },
        }
        if tracked then
            items[#items + 1] = { kind = "note", height = 30,
                text = string.format(L.ZONE_TRACKED_SINCE, date("%d.%m.%Y", c.since)) }
        end
        items[#items + 1] = { kind = "heading", text = L.ZONE_LATEST_SHOTS }
        for _, record in ipairs(c.latest) do
            items[#items + 1] = { kind = "cardShot", record = record }
        end
        if #c.latest == 0 then
            items[#items + 1] = { kind = "note", text = L.ZONE_NO_SHOTS }
        end
        return items
    end

    local function matches(zone, query)
        if state.filter == "visited" and not zone.visited then return false end
        if state.filter == "unvisited" and zone.visited then return false end
        return query == "" or string.find(ns.Util.Lower(zone.name), query, 1, true) ~= nil
    end

    function view:Refresh(day, keep)
        if day then
            state.history = true
            state.card = nil
        end
        if state.card then
            local items = cardItems(state.card)
            if items then
                return show(self, items, keep)
            end
        end
        local explorer = ns.ZoneCatalog.Explorer()
        if not self.opened then
            -- First look: the region you stand in is open.
            self.opened = true
            local here = ns.ZoneCatalog.CurrentRegion()
            if here then
                state.expanded[here] = true
            end
        end
        local items = {
            { kind = "heading", text = L.WORLD_EXPLORER },
            { kind = "progress", explorer = explorer },
            { kind = "filters" },
            { kind = "search" },
        }
        local query = ns.Util.Lower(state.search)
        local found = 0
        for _, region in ipairs(explorer.regions) do
            local zones = {}
            for _, zone in ipairs(region.zones) do
                if matches(zone, query) then
                    zones[#zones + 1] = zone
                end
            end
            found = found + #zones
            -- While searching, regions with results open and the rest hide.
            if query == "" or #zones > 0 then
                local open = query ~= "" or state.expanded[region.id] == true
                items[#items + 1] = { kind = "region", region = region, open = open }
                if open then
                    for _, zone in ipairs(zones) do
                        items[#items + 1] = { kind = "zone", zone = zone }
                    end
                    if #zones == 0 then
                        items[#items + 1] = { kind = "note", text = L.NOTHING_FOUND }
                    end
                end
            end
        end
        if query ~= "" and found == 0 then
            items[#items + 1] = { kind = "note", text = L.NOTHING_FOUND }
        end
        items[#items + 1] = { kind = "historyHeader" }
        if state.history then
            local rows = ns.Locations.Rows()
            for _, row in ipairs(rows) do
                if row.kind == "day" then
                    items[#items + 1] = { kind = "day", day = row.day, count = ns.Count(row.count, "ZONES"), anchor = row.day }
                else
                    items[#items + 1] = { kind = "visit", entry = row.entry }
                end
            end
            if #rows == 0 then
                items[#items + 1] = { kind = "note", text = L.NO_ZONES_YET }
            end
        end
        show(self, items, keep, day)
    end
    return view
end

---------------------------------------------------------------------------
-- Journey
---------------------------------------------------------------------------
local function buildJourney(parent)
    local view = newView(parent, {
        moment = {
            height = 92,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.line = row:CreateTexture(nil, "BACKGROUND")
                local d = W.COLORS.divider
                row.line:SetColorTexture(d[1], d[2], d[3], 1)
                row.line:SetWidth(2)
                row.line:SetPoint("TOPLEFT", 11, 0)
                row.line:SetPoint("BOTTOMLEFT", 11, 0)
                row.icon = W.IconBox(row, ICON.shots, 24)
                row.icon:SetPoint("TOPLEFT", 0, -6)
                row.card = W.Panel(row, W.COLORS.panel, W.COLORS.divider)
                row.card:SetPoint("TOPLEFT", 34, -2)
                row.card:SetPoint("BOTTOMRIGHT", 0, 8)
                row.title = W.Text(row.card, "", "GameFontNormal", W.COLORS.heading)
                row.title:SetPoint("TOPLEFT", 12, -12)
                row.title:SetPoint("RIGHT", row.card, "RIGHT", -12, 0)
                row.zone = W.Text(row.card, "", "GameFontHighlightSmall", W.COLORS.text)
                row.zone:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -6)
                row.zone:SetPoint("RIGHT", row.card, "RIGHT", -12, 0)
                row.when = W.Text(row.card, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.when:SetPoint("TOPLEFT", row.zone, "BOTTOMLEFT", 0, -6)
                return row
            end,
            fill = function(row, item)
                local e = item.entry
                row.icon:SetIcon(ns.Journey.Icon(e.kind))
                row.title:SetText(ns.Journey.Title(e))
                local parts = {}
                if type(e.zone) == "string" and e.zone ~= "" then parts[#parts + 1] = e.zone end
                if e.kind == "START" then parts[#parts + 1] = L.JOURNEY_START_DETAIL end
                if type(e.info) == "string" and e.info ~= "" then parts[#parts + 1] = e.info end
                row.zone:SetText(table.concat(parts, "  ·  "))
                row.when:SetText(ns.History.DateText(ns.Util.DayKey(e.t)) .. "  ·  " .. date("%H:%M", e.t))
            end,
        },
    })
    function view:Refresh(_, keep)
        local name = ns.character and ns.character.name or "?"
        local items = { { kind = "note", text = string.format(L.JOURNEY_SUBTITLE, name), color = W.COLORS.text } }
        for _, entry in ipairs(ns.Journey.Rows()) do
            items[#items + 1] = { kind = "moment", entry = entry }
        end
        if #items == 1 then
            items[2] = { kind = "note", text = L.NO_DATA }
        end
        show(self, items, keep)
    end
    return view
end

---------------------------------------------------------------------------
-- Overview: Adventure Calendar, the selected day, Adventure Recap
---------------------------------------------------------------------------
local CELL_GAP, CELL_H, LABEL_W, GRID_TOP = 4, 16, 28, 46

local function paintCell(cell, info, selected)
    local state = info.state
    local fill, alpha = W.COLORS.background, 0
    if state == "nodata" then
        fill, alpha = W.COLORS.panel, 0.35
    elseif type(state) == "number" then
        fill, alpha = LEVEL_COLORS[state], 1
    end
    local border, borderAlpha = W.COLORS.divider, state == "nodata" and 0.35 or 0.8
    if info.today then
        border, borderAlpha = LEVEL_COLORS[4], 1
    elseif selected then
        border, borderAlpha = W.COLORS.gold, 1
    end
    if cell.SetBackdropColor then -- the backdrop itself is set once, at creation
        cell:SetBackdropColor(fill[1], fill[2], fill[3], alpha)
        cell:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha)
    end
end

-- Tooltip lines of a calendar day.
local function dayTip(info)
    if info.state == "future" then
        return nil
    end
    local d = info.info
    if not d.recorded and not d.any then
        return L.NO_DATA
    end
    return string.format("%s: %s\n%s: %s\n%s: %s\n%s: %s",
        L.DAY_PLAYTIME, d.recorded and UI.FormatDuration(d.playtime) or L.NO_DATA,
        L.DAY_SHOTS, ns.Num(d.shots), L.DAY_STEPS, ns.Num(d.steps), L.DAY_ZONES, ns.Num(d.zones))
end

local function makeCalendar(parent, onPick)
    local frame = CreateFrame("Frame", nil, parent)
    local icon = W.Icon(frame, ICON.calendar, 16)
    icon:SetPoint("TOPLEFT", 0, -4)
    local title = W.Text(frame, L.ADVENTURE_CALENDAR, "GameFontNormalLarge", W.COLORS.heading)
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    frame.weeks = W.Text(frame, "", "GameFontHighlightSmall", W.COLORS.text)
    frame.weeks:SetPoint("TOPRIGHT", 0, -6)
    frame.weeks:SetJustifyH("RIGHT")
    local weeks = ns.Adventure.WEEKS
    local cellW = (INNER - LABEL_W) / weeks
    for d = 1, 7 do
        local label = W.Text(frame, L["WEEKDAY_" .. d], "GameFontHighlightSmall", W.COLORS.muted)
        label:SetPoint("TOPLEFT", 0, -(GRID_TOP + (d - 1) * (CELL_H + CELL_GAP)))
    end
    frame.months, frame.cells = {}, {}
    for w = 1, weeks do
        local month = W.Text(frame, "", "GameFontHighlightSmall", W.COLORS.muted)
        month:SetPoint("TOPLEFT", LABEL_W + (w - 1) * cellW, -28)
        frame.months[w] = month
        frame.cells[w] = {}
        for d = 1, 7 do
            local cell = CreateFrame("Button", nil, frame, "BackdropTemplate")
            W.Backdrop(cell, W.COLORS.background, 0, W.COLORS.divider)
            cell:SetSize(cellW - CELL_GAP, CELL_H)
            cell:SetPoint("TOPLEFT", LABEL_W + (w - 1) * cellW, -(GRID_TOP + (d - 1) * (CELL_H + CELL_GAP)))
            cell:SetScript("OnClick", function(self)
                if self.info and self.info.state ~= "future" then
                    onPick(self.info.day)
                end
            end)
            W.Tooltip(cell, function() return cell.info and dayTip(cell.info) end,
                function() return cell.info and ns.History.DayLabel(cell.info.day) end)
            frame.cells[w][d] = cell
        end
    end
    -- Legend: no data | less [0..4] more
    local legendY = -(GRID_TOP + 7 * (CELL_H + CELL_GAP) + 4)
    local more = W.Text(frame, L.MORE, "GameFontHighlightSmall", W.COLORS.text)
    more:SetPoint("TOPRIGHT", 0, legendY)
    more:SetJustifyH("RIGHT")
    local anchor = more
    for level = 4, 0, -1 do
        local swatch = W.Panel(frame, LEVEL_COLORS[level], W.COLORS.divider)
        swatch:SetSize(12, 12)
        swatch:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        anchor = swatch
    end
    local less = W.Text(frame, L.LESS, "GameFontHighlightSmall", W.COLORS.text)
    less:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    local none = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    W.Backdrop(none, W.COLORS.panel, 0.35, W.COLORS.divider, 0.35)
    none:SetSize(12, 12)
    none:SetPoint("TOPLEFT", LABEL_W, legendY - 1)
    local noneText = W.Text(frame, L.NO_DATA, "GameFontHighlightSmall", W.COLORS.muted)
    noneText:SetPoint("LEFT", none, "RIGHT", 6, 0)
    W.Tooltip(frame, L.TIP_CALENDAR, L.ADVENTURE_CALENDAR)
    return frame
end

local function fillCalendar(frame, item)
    frame.weeks:SetText(ns.Count(#item.columns, "WEEKS"))
    for w, column in ipairs(item.columns) do
        frame.months[w]:SetText(column.month and L["MONTH_NAME_" .. column.month] or "")
        for d, info in ipairs(column.days) do
            local cell = frame.cells[w][d]
            cell.info = info
            cell:SetShown(info.state ~= "future") -- future days are not drawn
            paintCell(cell, info, info.day == item.selected)
        end
    end
end

-- One figure of the selected day; a click opens its history at that day.
local function makeDayStat(parent, icon, label)
    local stat = CreateFrame("Button", nil, parent)
    stat.icon = W.Icon(stat, icon, 18)
    stat.icon:SetPoint("LEFT", 10, 0)
    stat.value = W.Text(stat, "", "GameFontNormalLarge", W.COLORS.heading)
    stat.value:SetPoint("TOPLEFT", 40, -6)
    stat.label = W.Text(stat, label, "GameFontHighlightSmall", W.COLORS.text)
    stat.label:SetPoint("BOTTOMLEFT", 40, 6)
    stat.arrow = W.Text(stat, ">", "GameFontNormal", W.COLORS.muted)
    stat.arrow:SetPoint("RIGHT", -12, 0)
    local highlight = stat:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    local g = W.COLORS.gold
    highlight:SetColorTexture(g[1], g[2], g[3], 0.06)
    stat:SetScript("OnClick", function(self)
        if self.target then
            UI.OpenHistory(self.target, self.day)
        end
    end)
    return stat
end

local DAY_STATS = {
    { "shots", "shots", "DAY_SHOTS" }, { "steps", "steps", "DAY_STEPS" },
    { "zones", "zones", "DAY_ZONES" }, { "playtime", "playtime", "DAY_PLAYTIME" },
}

local function makeDayPanel(parent)
    local box = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
    box.title = W.Text(box, "", "GameFontNormalLarge", W.COLORS.heading)
    box.title:SetPoint("TOPLEFT", 14, -12)
    box.state = W.Text(box, "", "GameFontHighlightSmall", W.COLORS.text)
    box.state:SetPoint("TOPRIGHT", -14, -14)
    box.state:SetJustifyH("RIGHT")
    box.stats = {}
    local half = (INNER - 24) / 2
    for i, spec in ipairs(DAY_STATS) do
        local stat = makeDayStat(box, ICON[spec[1]], L[spec[3]])
        stat:SetSize(half - 4, 46)
        stat:SetPoint("TOPLEFT", 12 + ((i - 1) % 2) * half, -40 - math.floor((i - 1) / 2) * 50)
        stat.view = spec[2]
        box.stats[spec[1]] = stat
    end
    return box
end

local function fillDayPanel(box, item)
    local d = ns.Adventure.Day(item.day)
    box.title:SetText(ns.History.DayLabel(item.day))
    local state = (d.level > 0 and L.ACTIVE_DAY) or (d.recorded and L.NO_ACTIVITY)
        or (d.any and L.PLAYTIME_NOT_RECORDED) or L.NO_DATA
    box.state:SetText(state)
    local texts = {
        shots = ns.Num(d.shots), steps = ns.Num(d.steps), zones = ns.Num(d.zones),
        playtime = d.recorded and UI.FormatDuration(d.playtime) or L.NO_DATA,
    }
    local has = { shots = d.shots > 0, steps = d.steps > 0, zones = d.zones > 0, playtime = d.playtime > 0 }
    for key, stat in pairs(box.stats) do
        stat.value:SetText(texts[key])
        stat.arrow:SetShown(has[key])
        stat.target = has[key] and stat.view or nil
        stat.day = item.day
    end
end

local RECAP_ROWS = {
    { "shots", "RECAP_SHOTS", ns.Num }, { "steps", "RECAP_STEPS", ns.Num },
    { "zones", "RECAP_ZONES", ns.Num }, { "newZones", "RECAP_NEW_ZONES", ns.Num },
    { "playtime", "RECAP_PLAYTIME", function(v) return UI.FormatDuration(v) end },
    { "days", "RECAP_DAYS", ns.Num },
}

local function rangeText(first, last)
    local a, b = date("*t", ns.Util.DayStart(first)), date("*t", ns.Util.DayStart(last))
    return string.format("%02d.%02d - %02d.%02d", a.day, a.month, b.day, b.month)
end

-- On This Day (v0.13.0): a week, a month and a year ago. The block is
-- left out when there is nothing to remember.
local function makeMemoryRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.icon = W.IconBox(row, ICON.shots, 30)
    row.icon:SetPoint("LEFT", 0, 0)
    row.title = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.title:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.detail = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.time = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.time:SetPoint("RIGHT", -8, 0)
    row.time:SetJustifyH("RIGHT")
    return row
end

local function fillMemoryRow(row, item)
    local m = item.memory
    row.icon:SetIcon(m.icon)
    row.title:SetText(m.title)
    local parts = {}
    for _, part in ipairs({ m.zone, m.detail }) do
        if type(part) == "string" and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    row.detail:SetText(table.concat(parts, "  ·  "))
    row.time:SetText(date("%H:%M", m.t))
end

local function addMemories(items)
    local periods = ns.Memories.OnThisDay()
    if #periods == 0 then
        return
    end
    items[#items + 1] = { kind = "heading", text = L.ON_THIS_DAY }
    for _, p in ipairs(periods) do
        items[#items + 1] = { kind = "day", day = p.day, count = L["MEMORY_" .. string.upper(p.period)] }
        for _, memory in ipairs(p.items) do
            items[#items + 1] = { kind = "memory", memory = memory }
        end
        if p.more > 0 then
            items[#items + 1] = { kind = "note", text = string.format(L.MEMORY_MORE, ns.Num(p.more)) }
        end
    end
end

local function buildOverview(parent)
    local view
    local state = { selected = nil, period = "week" }
    view = newView(parent, {
        calendar = {
            height = GRID_TOP + 7 * (CELL_H + CELL_GAP) + 26,
            make = function(p)
                return makeCalendar(p, function(day)
                    state.selected = day
                    view:Refresh(nil, true)
                end)
            end,
            fill = fillCalendar,
        },
        dayPanel = { height = 150, make = makeDayPanel, fill = fillDayPanel },
        memory = { height = 42, make = makeMemoryRow, fill = fillMemoryRow },
        recapHeader = {
            height = 44,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.text = W.Text(row, L.ADVENTURE_RECAP, "GameFontNormalLarge", W.COLORS.heading)
                row.text:SetPoint("LEFT", 0, 0)
                row.range = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.range:SetPoint("LEFT", row.text, "RIGHT", 10, -1)
                row.switch = W.Segmented(row, { { "week", L.WEEK }, { "month", L.MONTH } }, 170, function(value)
                    state.period = value
                    view:Refresh(nil, true)
                end)
                row.switch:SetPoint("RIGHT", 0, 0)
                return row
            end,
            fill = function(row, item)
                row.switch:SetValue(state.period)
                row.range:SetText(item.range)
            end,
        },
    })
    function view:Refresh(_, keep)
        local today = ns.Util.DayKey(ns.API.Time())
        state.selected = state.selected and state.selected <= today and state.selected or today
        local first, last
        if state.period == "month" then
            first, last = ns.Adventure.MonthRange(today)
        else
            first, last = ns.Adventure.WeekRange(today)
        end
        local recap = ns.Adventure.Period(first, last)
        local items = {
            { kind = "calendar", columns = ns.Adventure.Calendar(today), selected = state.selected },
            { kind = "dayPanel", day = state.selected },
        }
        addMemories(items)
        items[#items + 1] = { kind = "recapHeader", range = rangeText(first, last) }
        for _, spec in ipairs(RECAP_ROWS) do
            items[#items + 1] = { kind = "value", icon = ICON[spec[1]], label = L[spec[2]],
                                  value = spec[3](recap[spec[1]]) }
        end
        show(self, items, keep)
    end
    return view
end

---------------------------------------------------------------------------
-- Records (v0.12.0): personal records from Records.Get().
---------------------------------------------------------------------------
local function fullDate(day)
    local d = date("*t", ns.Util.DayStart(day))
    return string.format("%02d.%02d.%04d", d.day, d.month, d.year)
end

local function duration(v) return UI.FormatDuration(v) end
local RECORDS = {
    steps = { ICON.steps, "RECORD_STEPS", function(v) return ns.Count(v, "STEPS") end },
    shots = { ICON.shots, "RECORD_SHOTS", function(v) return ns.Count(v, "SHOTS") end },
    zones = { ICON.zones, "RECORD_ZONES", function(v) return ns.Count(v, "ZONES") end },
    playtime = { ICON.playtime, "RECORD_PLAYTIME", duration },
    session = { ICON.sessions, "RECORD_SESSION", duration },
    streak = { ICON.days, "RECORD_STREAK", function(v) return ns.Count(v, "DAYS") end },
}

-- Text under a record: its date, the period of a streak, or "date unknown".
local function recordWhen(id, record)
    if record.value == nil then
        return L.RECORD_NO_DATA_HINT
    elseif not record.day then
        return L.DATE_UNKNOWN
    elseif id == "streak" and record.last and record.last ~= record.day then
        return fullDate(record.day) .. " - " .. fullDate(record.last)
    end
    return fullDate(record.day)
end

local function buildRecords(parent)
    local view = newView(parent, {
        record = {
            height = 54,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.icon = W.Icon(row, ICON.steps, 28)
                row.icon:SetPoint("LEFT", 4, 0)
                row.title = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
                row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 0)
                row.when = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.when:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 12, 0)
                row.value = W.Text(row, "", "GameFontNormalLarge", W.COLORS.heading)
                row.value:SetPoint("RIGHT", -8, 0)
                row.value:SetJustifyH("RIGHT")
                row.line = W.Divider(row)
                row.line:SetPoint("BOTTOMLEFT", 0, 0)
                row.line:SetPoint("BOTTOMRIGHT", -8, 0)
                return row
            end,
            fill = function(row, item)
                row.icon:SetTexture(item.icon)
                row.title:SetText(item.title)
                row.when:SetText(item.when)
                row.value:SetText(item.value)
                setColor(row.value, item.has and W.COLORS.heading or W.COLORS.muted)
            end,
        },
    })
    function view:Refresh(_, keep)
        local records = ns.Records.Get()
        local items = { { kind = "heading", text = L.RECORDS_TITLE } }
        for _, id in ipairs(ns.Records.ORDER) do
            local record, spec = records[id] or {}, RECORDS[id]
            items[#items + 1] = {
                kind = "record", icon = spec[1], title = L[spec[2]], when = recordWhen(id, record),
                value = record.value and spec[3](record.value) or L.NO_DATA, has = record.value ~= nil,
            }
        end
        items[#items + 1] = { kind = "note", text = L.RECORDS_NOTE, height = 40 }
        show(self, items, keep)
    end
    return view
end

---------------------------------------------------------------------------
-- Achievements (v0.13.0): ForeverMemories' own achievements with a filter
-- All / Completed / In progress, grouped like the catalog.
---------------------------------------------------------------------------
local ACH_FILTERS = { { "all", "ACH_ALL" }, { "done", "ACH_DONE" }, { "progress", "ACH_IN_PROGRESS" } }

local function achievementStatus(a)
    if a.done then
        return a.at and string.format(L.ACH_EARNED_ON, fullDate(ns.Util.DayKey(a.at))) or L.ACH_EARNED_UNKNOWN,
            W.COLORS.active
    elseif not a.available then
        return L.ACH_CATALOG_UNCONFIRMED, W.COLORS.muted
    end
    return L.ACH_IN_PROGRESS, W.COLORS.muted
end

local function buildAchievements(parent)
    local view
    local state = { filter = "all" }
    local BAR = INNER - 190
    view = newView(parent, {
        achFilter = {
            height = 40,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                local options = {}
                for i, f in ipairs(ACH_FILTERS) do
                    options[i] = { f[1], L[f[2]] }
                end
                row.switch = W.Segmented(row, options, 330, function(value)
                    state.filter = value
                    view:Refresh()
                end)
                row.switch:SetPoint("LEFT", 0, 0)
                row.summary = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.summary:SetPoint("RIGHT", -8, 0)
                row.summary:SetJustifyH("RIGHT")
                return row
            end,
            fill = function(row, item)
                row.switch:SetValue(state.filter)
                row.summary:SetText(item.summary)
            end,
        },
        achievement = {
            height = 66,
            make = function(p)
                local row = CreateFrame("Frame", nil, p)
                row.icon = W.IconBox(row, ICON.shots, 38)
                row.icon:SetPoint("LEFT", 0, 0)
                row.title = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
                row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 2)
                row.status = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.status:SetPoint("TOPRIGHT", -8, -10)
                row.status:SetJustifyH("RIGHT")
                row.desc = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
                row.desc:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.bar = progressBar(row, 4)
                row.bar:SetWidth(BAR)
                row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 12, 2)
                row.count = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.heading)
                row.count:SetPoint("RIGHT", -8, 0)
                row.count:SetPoint("BOTTOM", row.bar, "BOTTOM", 0, -4)
                row.count:SetJustifyH("RIGHT")
                row.line = W.Divider(row)
                row.line:SetPoint("BOTTOMLEFT", 0, 0)
                row.line:SetPoint("BOTTOMRIGHT", -8, 0)
                return row
            end,
            fill = function(row, item)
                local a = item.achievement
                row.icon:SetIcon(a.def.icon)
                row.icon:SetAlpha(a.done and 1 or 0.45)
                row.title:SetText(L["ACH_" .. a.def.id])
                setColor(row.title, a.done and W.COLORS.heading or W.COLORS.text)
                row.desc:SetText(L["ACH_" .. a.def.id .. "_DESC"])
                local status, color = achievementStatus(a)
                row.status:SetText(status)
                setColor(row.status, color)
                local value, target = a.value, a.target
                if a.done and target and (not value or value > target) then
                    value = target -- never "less than done", never over 100 %
                end
                if value and target then
                    row.count:SetText(ns.Num(value) .. " / " .. ns.Num(target))
                    row.bar:SetProgress(math.min(1, value / target), BAR)
                else
                    row.count:SetText(a.done and L.ACH_COMPLETE or "-")
                    row.bar:SetProgress(a.done and 1 or 0, BAR)
                end
            end,
        },
    })
    function view:Refresh(_, keep)
        local list = ns.Achievements.Get()
        local done = 0
        for _, a in ipairs(list) do
            if a.done then
                done = done + 1
            end
        end
        local items = { { kind = "achFilter", summary = string.format(L.ACH_SUMMARY, done, #list) } }
        for _, group in ipairs(ns.Achievements.GROUPS) do
            local heading = false
            for _, a in ipairs(list) do
                local wanted = state.filter == "all" or (state.filter == "done") == a.done
                if a.def.group == group and wanted then
                    if not heading then
                        items[#items + 1] = { kind = "heading", text = L["ACH_GROUP_" .. string.upper(group)] }
                        heading = true
                    end
                    items[#items + 1] = { kind = "achievement", achievement = a }
                end
            end
        end
        if #items == 1 then
            items[#items + 1] = { kind = "note", text = state.filter == "done" and L.ACH_NONE_DONE or L.ACH_ALL_DONE }
        end
        items[#items + 1] = { kind = "note", text = L.ACH_NOTE, height = 40 }
        show(self, items, keep)
    end
    return view
end

---------------------------------------------------------------------------
-- All characters (v0.12.0): the saved characters of the account. A click
-- opens a character's History read-only.
---------------------------------------------------------------------------
local function buildAccount(parent, onOpen)
    local g = W.COLORS.gold
    local view = newView(parent, {
        character = {
            height = 50,
            make = function(p)
                local row = CreateFrame("Button", nil, p)
                local highlight = row:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints()
                highlight:SetColorTexture(g[1], g[2], g[3], 0.06)
                row.portrait = row:CreateTexture(nil, "ARTWORK")
                row.portrait:SetSize(28, 28)
                row.portrait:SetPoint("LEFT", 6, 0)
                row.name = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
                row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 10, 0)
                row.detail = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
                row.detail:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", 10, 0)
                row.detail:SetPoint("RIGHT", row, "RIGHT", -30, 0)
                row.tag = W.Text(row, L.CURRENT_CHARACTER, "GameFontHighlightSmall", W.COLORS.active)
                row.tag:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
                row.arrow = W.Text(row, ">", "GameFontNormal", W.COLORS.muted)
                row.arrow:SetPoint("RIGHT", -8, 0)
                row.line = W.Divider(row)
                row.line:SetPoint("BOTTOMLEFT", 0, 0)
                row.line:SetPoint("BOTTOMRIGHT", -8, 0)
                row:SetScript("OnClick", function(self)
                    if self.key then
                        onOpen(self.key)
                    end
                end)
                return row
            end,
            fill = function(row, item)
                local c, s = item.character, item.summary
                local file, coords = ns.API.ClassIcon(c.class)
                if file then
                    row.portrait:SetTexture(file)
                    row.portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                else
                    row.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                row.key = item.key
                row.name:SetText(ns.DataTools.DisplayName(c, item.key) .. " - " .. (c.realm or "?"))
                row.tag:SetShown(item.current)
                row.detail:SetText(table.concat({
                    ns.Count(s.shots, "SHOTS"), ns.Count(s.steps, "STEPS"), ns.Count(s.zones, "ZONES"),
                    UI.FormatDuration(s.playtime),
                }, "  ·  "))
            end,
        },
    }, BUTTONS_TOP)
    function view:Refresh(_, keep)
        local list = ns.DataTools.Characters()
        local items = { { kind = "heading", text = L.ACCOUNT_CHARACTERS, right = ns.Num(#list) } }
        for _, item in ipairs(list) do
            items[#items + 1] = { kind = "character", key = item.key, character = item.character,
                                  summary = item.summary, current = item.current }
        end
        items[#items + 1] = { kind = "note", text = L.ACCOUNT_NOTE, height = 40 }
        show(self, items, keep)
    end
    return view
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
local ORDER = { "overview", "shots", "steps", "zones", "playtime", "journey", "records", "achievements" }
local LABELS = { overview = "SUB_OVERVIEW", shots = "SUB_SHOTS", steps = "SUB_STEPS",
                 zones = "SUB_ZONES", playtime = "SUB_PLAYTIME", journey = "SUB_JOURNEY",
                 records = "SUB_RECORDS", achievements = "SUB_ACHIEVEMENTS" }
local BUTTONS_PER_ROW = 4

UI.builders.history = function(parent)
    local refreshHeader = UI.CharacterHeader(parent, L.LIFETIME_STATS)
    local cards = UI.Dashboard(parent, 44, {
        { "shots", ICON.shots, L.STAT_TOTAL, L.TIP_STAT_TOTAL },
        { "steps", ICON.steps, L.TOTAL_STEPS, L.STEPS_NOTE },
        { "zones", ICON.zones, L.STAT_ZONES_TOTAL, L.TIP_STAT_ZONES_TOTAL },
        { "playtime", ICON.playtime, L.STAT_PLAYTIME_TOTAL, L.TIP_STAT_PLAYTIME_TOTAL },
    })

    local views = {
        overview = buildOverview(parent), shots = buildShots(parent), steps = buildSteps(parent),
        zones = buildLocations(parent), playtime = buildPlaytime(parent), journey = buildJourney(parent),
        records = buildRecords(parent), achievements = buildAchievements(parent),
    }
    -- Every Refresh of a sub-view sees the viewed character.
    for _, view in pairs(views) do
        local refresh = view.Refresh
        view.Refresh = function(...) return withViewed(refresh, ...) end
    end
    local buttons = {}
    local current = "overview"
    local mode = "character" -- or "account"
    local pendingDay
    local refresh, account, modeSwitch, back

    -- Shows a sub-view; `day` scrolls it to that date, `keep` keeps the
    -- scroll position (data refresh of the same sub-view).
    local function select(id, day, keep)
        current = views[id] and id or "overview"
        local showViews = mode == "character"
        for key, view in pairs(views) do
            view:SetShown(showViews and key == current)
            buttons[key]:SetShown(showViews)
            buttons[key]:SetSelected(key == current)
        end
        account:SetShown(not showViews)
        if showViews then
            views[current]:Refresh(day, keep)
        else
            account:Refresh(nil, keep)
        end
    end
    local gap = 6
    local width = (WIDTH - gap * (BUTTONS_PER_ROW - 1)) / BUTTONS_PER_ROW
    for i, id in ipairs(ORDER) do
        local column, line = (i - 1) % BUTTONS_PER_ROW, math.floor((i - 1) / BUTTONS_PER_ROW)
        buttons[id] = W.Button(parent, L[LABELS[id]], width, 30, function() select(id) end)
        buttons[id]:SetPoint("TOPLEFT", column * (width + gap), -BUTTONS_TOP - line * 34)
    end

    -- Character / All characters, and the way back from a viewed character.
    local function setMode(value, key)
        mode, viewed = value, key
        refresh()
    end
    account = buildAccount(parent, function(key)
        setMode("character", key ~= ns.characterKey and key or nil)
    end)
    account:Hide()
    modeSwitch = W.Segmented(parent, { { "character", L.MODE_CHARACTER }, { "account", L.MODE_ACCOUNT } }, 250,
        function(value) setMode(value, nil) end)
    modeSwitch:SetPoint("TOPRIGHT", 0, -2)
    W.Tooltip(modeSwitch, L.TIP_MODE_ACCOUNT, L.MODE_ACCOUNT)
    back = W.Link(parent, L.BACK_TO_CURRENT, function() setMode("character", nil) end)
    back:SetPoint("TOPRIGHT", 0, -28)

    local function refreshPlaytime()
        if mode == "character" and not viewedCharacter() then
            cards.playtime.value:SetText(UI.FormatDuration((ns.Activity.Lifetime())))
        end
    end
    local function refreshSteps()
        if mode == "character" and not viewedCharacter() then
            cards.steps.value:SetText(ns.Num(ns.Steps.Total()))
            if current == "steps" then
                views.steps:Refresh(nil, true)
            end
        end
    end

    local switched
    refresh = function()
        if viewed and not viewedCharacter() then
            viewed = nil -- deleted, or it is the current character now
        end
        modeSwitch:SetValue(mode)
        back:SetShown(viewed ~= nil)
        if mode == "account" then
            local t = ns.DataTools.AccountTotals()
            refreshHeader(L.ACCOUNT_CAPTION, L.ACCOUNT_TITLE, "Interface\\Icons\\INV_Misc_GroupNeedMore")
            cards.shots.value:SetText(ns.Num(t.shots))
            cards.steps.value:SetText(ns.Num(t.steps))
            cards.zones.value:SetText(ns.Num(t.zones))
            cards.playtime.value:SetText(UI.FormatDuration(t.playtime))
            cards.playtime.caption:SetText(L.ACCOUNT_ACTIVE_TIME)
        else
            withViewed(function()
                refreshHeader(viewedCharacter() and L.VIEWING_READ_ONLY or L.LIFETIME_STATS)
                cards.shots.value:SetText(ns.Num(ns.History.Stats().total))
                cards.zones.value:SetText(ns.Num(ns.Locations.Total()))
                cards.steps.value:SetText(ns.Num(ns.Steps.Total()))
                -- /played exists only for the logged-in character.
                cards.playtime.value:SetText(UI.FormatDuration((ns.Activity.Lifetime())))
            end)
            cards.playtime.caption:SetText(viewedCharacter() and L.ACCOUNT_ACTIVE_TIME or L.STAT_PLAYTIME_TOTAL)
        end
        select(current, pendingDay, not switched)
        pendingDay, switched = nil, false
    end
    return {
        -- Opening the tab from elsewhere picks a sub-view (and a day).
        Select = function(id, day)
            mode, viewed = "character", nil
            current, pendingDay, switched = views[id] and id or "overview", day, true
        end,
        -- Opening the tab again starts with the current character.
        Reset = function()
            mode, viewed, switched = "character", nil, true
        end,
        Refresh = refresh,
        RefreshSteps = refreshSteps,
        RefreshClock = refreshPlaytime,
        Current = function() return current end,
        Mode = function() return mode, viewed end,
    }
end

-- History at a sub-view, scrolled to a day (Overview's day panel).
function UI.OpenHistory(id, day)
    UI.ShowTab("history", id, day)
end
