-- Modules/Notifications.lua
-- On-screen notifications (v0.6.0, three kinds since v0.17.0) and the chat
-- line after a saved screenshot.
--   mini      - "Screenshot saved": a small card (frame ForeverMemoriesToast)
--   discovery - a new location, an earned common or rare achievement
--   legendary - an epic or legendary achievement, a legendary item
-- One notification is on screen at a time; the others wait in a short
-- queue. With "merge" on, the same notification coming again while it is
-- shown or waiting adds "+N more" instead of a new card. Every card is
-- hidden before each capture, so it never appears in a screenshot.
-- The Step Tracker has no notifications.
local _, ns = ...

local Notifications = {}
ns.Notifications = Notifications

local L = ns.L

Notifications.MAX_QUEUE = 5
Notifications.ART_HEIGHT = 120 -- zone picture on a discovery card
Notifications.STORY_HEIGHT = 48 -- room for a story of a few lines
Notifications.COMBAT_WAIT = 2 -- seconds: large cards wait for the end of combat
Notifications.GAP = 0.4 -- seconds between two cards
Notifications.FADE_IN = 0.25 -- seconds (v1.0.0-beta.4), only with animations on
Notifications.SIZES = { small = 0.85, normal = 1, large = 1.2 }
Notifications.POSITIONS = {
    top = { "TOP", 0, -120 },
    middle = { "CENTER", 0, 140 },
    bottom = { "BOTTOM", 0, 220 },
}
-- Setting that turns each kind on or off.
Notifications.SETTING = { mini = "notifyMini", discovery = "notifyDiscovery", legendary = "notifyLegendary" }

-- Seconds on screen, set for each kind (v1.0.0-beta.6; before: one
-- "toastDuration" for all).
Notifications.DURATION = { mini = "durationMini", discovery = "durationDiscovery", legendary = "durationLegendary" }
Notifications.HOVER_MIN = 1.5 -- seconds left after the mouse leaves a paused card
function Notifications.Duration(kind)
    local key = Notifications.DURATION[kind] or "durationMini"
    return ns.db and ns.db.settings[key] or ns.Database.SETTINGS[key].default
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
local cards = {}
local hooks -- card mouse handlers, set below the queue

local function makeCard(kind)
    local W, M = ns.Widgets, ns.Media
    local names = { mini = "ForeverMemoriesToast", discovery = "ForeverMemoriesToastDiscovery",
                    legendary = "ForeverMemoriesToastLegendary" }
    local card = CreateFrame("Frame", names[kind], UIParent, "BackdropTemplate")
    card:SetFrameStrata("HIGH")
    card.kind = kind
    -- v1.0.0-beta.6: the mouse over a card pauses its timer, "x" closes it,
    -- and in the position editor the card is dragged.
    card:EnableMouse(true)
    if card.SetClampedToScreen then card:SetClampedToScreen(true) end
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnEnter", function(self) hooks.enter(self) end)
    card:SetScript("OnLeave", function(self) hooks.leave(self) end)
    card:SetScript("OnDragStart", function(self) hooks.dragStart(self) end)
    card:SetScript("OnDragStop", function(self) hooks.dragStop(self) end)
    card:Hide()
    local c = W.COLORS
    if kind == "mini" then
        -- The art has fixed proportions (512 x 128): shown at 360 x 90 over
        -- an opaque panel, the icon sits in its slot on the left.
        card:SetSize(360, 90)
        local back = card:CreateTexture(nil, "BACKGROUND")
        -- beta.12: a fill texture cut to the frame's exact shape (tools/make_mini_back.py),
        -- so the dark background reaches the gold lines and never passes the end caps.
        back:SetAllPoints()
        back:SetTexture(M.NOTIFY.mini_back)
        local art = card:CreateTexture(nil, "BORDER")
        art:SetAllPoints()
        art:SetTexture(M.NOTIFY.mini_frame)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(26, 26) -- inside the slot of the art (beta.9: was 30 with its own frame)
        card.icon:SetPoint("CENTER", card, "LEFT", 44, 1)
        -- beta.11: both lines centered between the gold lines, clear of "x".
        card.title = W.Text(card, "", "GameFontNormal", c.heading)
        card.title:SetPoint("TOPLEFT", 74, -29)
        card.title:SetPoint("RIGHT", -48, 0)
        card.text = W.Text(card, "", "GameFontHighlightSmall", c.text)
        card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
        card.text:SetPoint("RIGHT", -48, 0)
    elseif kind == "discovery" then
        card:SetSize(380, 96)
        -- v1.0.0-beta.9: cut corners; the border texture holds the background.
        W.NineSlice(card, M.NOTIFY.discovery_border_9slice, 64, 16, 16, true)
        -- v0.18.0: the zone's illustration (optional ArtPack) on top.
        card.art = card:CreateTexture(nil, "ARTWORK")
        card.art:SetPoint("TOPLEFT", 8, -8)
        card.art:SetPoint("TOPRIGHT", -8, -8)
        card.art:SetHeight(Notifications.ART_HEIGHT)
        card.art:Hide()
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(60, 60)
        card.icon:SetPoint("TOPLEFT", 16, -18)
        card.caption = W.Text(card, "", "GameFontHighlightSmall", c.gold)
        card.caption:SetPoint("TOPLEFT", 92, -20)
        card.title = W.Text(card, "", "GameFontNormalLarge", c.heading)
        card.title:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -4)
        card.title:SetPoint("RIGHT", -18, 0)
        card.text = W.Text(card, "", "GameFontHighlightSmall", c.text)
        card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
        card.text:SetPoint("RIGHT", -18, 0)
        if card.text.SetWordWrap then card.text:SetWordWrap(true) end -- a story has a few lines
    else
        card:SetSize(430, 112)
        W.NineSlice(card, M.NOTIFY.legendary_border_9slice, 64, 16, 18, true) -- cut corners (beta.9)
        local glow = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        glow:SetTexture(M.NOTIFY.golden_glow)
        glow:SetSize(120, 120)
        glow:SetPoint("CENTER", card, "LEFT", 58, 4)
        glow:SetAlpha(0.7)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(64, 64)
        card.icon:SetPoint("CENTER", card, "LEFT", 58, 0)
        local left = card:CreateTexture(nil, "ARTWORK")
        left:SetTexture(M.NOTIFY.laurel_left)
        left:SetSize(34, 34)
        local right = card:CreateTexture(nil, "ARTWORK")
        right:SetTexture(M.NOTIFY.laurel_right)
        right:SetSize(34, 34)
        card.caption = W.Text(card, "", "GameFontHighlightSmall", c.gold)
        card.caption:SetPoint("TOP", card, "TOPLEFT", 260, -18)
        card.caption:SetJustifyH("CENTER")
        left:SetPoint("RIGHT", card.caption, "LEFT", -6, 0)
        right:SetPoint("LEFT", card.caption, "RIGHT", 6, 0)
        card.title = W.Text(card, "", "GameFontNormalLarge", c.heading)
        card.title:SetPoint("TOPLEFT", 104, -44)
        card.title:SetPoint("RIGHT", -20, 0)
        card.title:SetJustifyH("CENTER")
        card.text = W.Text(card, "", "GameFontHighlightSmall", c.text)
        card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
        card.text:SetPoint("RIGHT", -20, 0)
        card.text:SetJustifyH("CENTER")
    end
    -- beta.11: a plain "x" inside the frame (no square box over the gold line);
    -- muted, gold under the mouse.
    card.close = CreateFrame("Button", nil, card)
    card.close:SetSize(18, 18)
    card.close.label = W.Text(card.close, "x", "GameFontNormal", c.muted)
    card.close.label:SetPoint("CENTER", 0, 1)
    card.close.label:SetJustifyH("CENTER")
    card.close:SetScript("OnClick", function() hooks.close(card) end)
    W.AddScript(card.close, "OnEnter", function(self) local g = c.gold; self.label:SetTextColor(g[1], g[2], g[3]) end)
    W.AddScript(card.close, "OnLeave", function(self) local m = c.muted; self.label:SetTextColor(m[1], m[2], m[3]) end)
    local closeAt = { mini = { -30, -24 }, discovery = { -12, -10 }, legendary = { -14, -12 } }
    card.close:SetPoint("TOPRIGHT", closeAt[kind][1], closeAt[kind][2])
    W.Tooltip(card.close, nil, L.CLOSE)
    return card
end

local function cardOf(kind)
    if not cards[kind] then
        cards[kind] = makeCard(kind)
    end
    return cards[kind]
end

local editing, edit -- the kind in the position editor and its unsaved place

-- The card of a kind (built on first use); the edit panel follows it.
function Notifications.Card(kind)
    return Notifications.SETTING[kind] and cardOf(kind) or nil
end

-- Own place of a kind (v1.0.0-beta.6), or nil: then the common position
-- and size of Settings / Notifications.
function Notifications.Layout(kind)
    local own = ns.db.ui.notify
    return own and own[kind]
end

local function place(card)
    if editing == card.kind then
        return -- the editor moves it
    end
    local settings = ns.db.settings
    local own = Notifications.Layout(card.kind)
    card:ClearAllPoints()
    if own then
        card:SetPoint(own.point, UIParent, own.relPoint or own.point, own.x, own.y)
        card:SetScale(own.scale)
        return
    end
    local p = Notifications.POSITIONS[settings.notifyPosition] or Notifications.POSITIONS.top
    card:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    card:SetScale(Notifications.SIZES[settings.notifySize] or 1)
end

---------------------------------------------------------------------------
-- Queue
---------------------------------------------------------------------------
local queue, current = {}, nil
local token = 0

local function lineOf(n)
    local text = n.text or ""
    if n.count > 1 then
        local more = string.format(L.NOTIFY_MORE, n.count - 1)
        text = text ~= "" and (text .. "  ·  " .. more) or more
    end
    return text
end

local function draw(n)
    local card = cardOf(n.kind)
    for kind, other in pairs(cards) do
        if kind ~= n.kind then other:Hide() end
    end
    place(card)
    local icon = n.icon or ns.Media.NOTIFY.event_success
    card.icon:SetTexture(icon)
    -- v1.0.0-beta.9: the event icons have their own gold square; on the mini
    -- card (which has a slot) only their inside is shown. Game icons lose
    -- their border, the addon's other art is shown whole.
    if card.kind == "mini" and string.find(icon, "\\Notifications\\event_", 1, true) then
        card.icon:SetTexCoord(0.23, 0.77, 0.23, 0.77)
    elseif ns.Media.IsOwn(icon) then
        card.icon:SetTexCoord(0, 1, 0, 1)
    else
        card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if card.caption then
        card.caption:SetText(n.caption or "")
    end
    if n.kind == "discovery" then
        -- Layout with or without the picture and the story (v0.18.0).
        local top = 0
        if n.art then
            card.art:SetTexture(n.art)
            card.art:SetTexCoord(n.uv[1], n.uv[2], n.uv[3], n.uv[4])
            card.art:Show()
            top = Notifications.ART_HEIGHT + 6
        else
            card.art:Hide()
        end
        card.icon:ClearAllPoints()
        card.icon:SetPoint("TOPLEFT", 16, -18 - top)
        card.caption:ClearAllPoints()
        card.caption:SetPoint("TOPLEFT", 92, -20 - top)
        card:SetHeight(96 + top + (n.story and Notifications.STORY_HEIGHT or 0))
    end
    card.title:SetText(n.title or "")
    local c = n.color or ns.Widgets.COLORS.heading
    card.title:SetTextColor(c[1], c[2], c[3])
    card.text:SetText(lineOf(n))
    card:Show()
    -- v1.0.0-beta.4: a short fade-in, unless animations are off.
    if ns.db.settings.animations then
        local shown = 0
        card:SetAlpha(0)
        card:SetScript("OnUpdate", function(self, elapsed)
            shown = shown + (type(elapsed) == "number" and elapsed or Notifications.FADE_IN)
            if shown >= Notifications.FADE_IN then
                self:SetAlpha(1)
                self:SetScript("OnUpdate", nil)
            else
                self:SetAlpha(shown / Notifications.FADE_IN)
            end
        end)
    else
        card:SetScript("OnUpdate", nil)
        card:SetAlpha(1)
    end
end

local showNext

local deadline, paused -- end of the card on screen; seconds left while hovered

local function nextLater()
    if #queue > 0 then
        ns.API.After(Notifications.GAP, function()
            if not current then showNext() end
        end)
    end
end

local function startTimer(n, seconds)
    token = token + 1
    paused = nil
    local mine = token
    seconds = seconds or Notifications.Duration(n.kind)
    deadline = (ns.API.Now() or 0) + seconds
    ns.API.After(seconds, function()
        if mine == token and current == n then
            cardOf(n.kind):Hide()
            current = nil
            nextLater()
        end
    end)
end

-- Large cards that wait for the end of combat (v0.18.0): a discovery
-- always (its story is to be read), a legendary one unless the player
-- turned "Wait for the end of combat" off (v1.0.0-beta.6). The small
-- "Screenshot saved" card does not cover anything.
local function waitsInCombat(n)
    if n.force or n.kind == "mini" or not ns.API.InCombat() then
        return false
    end
    return n.kind == "discovery" or ns.db.settings.notifyCombatDefer
end
Notifications.WaitsInCombat = waitsInCombat

showNext = function()
    if editing then
        return -- the editor shows its sample; the queue waits
    end
    local n = table.remove(queue, 1)
    if not n then
        return
    end
    if waitsInCombat(n) then
        table.insert(queue, 1, n)
        ns.API.After(Notifications.COMBAT_WAIT, function()
            if not current then showNext() end
        end)
        return
    end
    current = n
    draw(n)
    startTimer(n)
end

local function same(a, b)
    return a and b and a.kind == b.kind and a.title == b.title and a.caption == b.caption
end

-- Shows a notification, or queues it.
--   n = { kind, title, text, caption, icon, color }
-- `force` shows it even when this kind or notifications are off (tests).
function Notifications.Push(n, force)
    local settings = ns.db.settings
    n.kind = Notifications.SETTING[n.kind] and n.kind or "mini"
    if not force and not (settings.notifications and settings[Notifications.SETTING[n.kind]]) then
        return false
    end
    n.count = 1
    if settings.notifyMerge and not force then
        local target = same(current, n) and current or nil
        if not target then
            for i = #queue, 1, -1 do
                if same(queue[i], n) then
                    target = queue[i]
                    break
                end
            end
        end
        if target then
            target.count = target.count + 1
            target.text = n.text
            if target == current then
                draw(current)
                startTimer(current) -- the merged card stays its full time
            end
            return true
        end
    end
    n.force = force
    if force then
        queue = {} -- a test shows at once
        current = nil
    end
    if #queue >= Notifications.MAX_QUEUE then
        table.remove(queue, 1) -- the oldest waiting one gives way
    end
    queue[#queue + 1] = n
    if not current then
        showNext()
    end
    return true
end

-- Before a capture: every card is hidden. The one on screen goes back to
-- the front of the queue and is shown again, in full, after the shot (a
-- new location is announced at once, and its screenshot follows).
function Notifications.HideNow()
    token = token + 1
    paused = nil
    for _, card in pairs(cards) do
        card:Hide()
    end
    if editing then -- the editor's sample comes back after the shot
        local kind = editing
        ns.API.After(3, function()
            if editing == kind then cardOf(kind):Show() end
        end)
    end
    if current then
        table.insert(queue, 1, current)
    end
    current = nil
    if #queue > 0 then
        ns.API.After(3, function()
            if not current then showNext() end
        end)
    end
end

-- What is on screen and waiting (for tests and /fm debug).
function Notifications.State()
    return current, #queue
end

---------------------------------------------------------------------------
-- Mouse on a card (v1.0.0-beta.6): hover pauses, "x" closes.
---------------------------------------------------------------------------
local function isCurrent(card)
    return current ~= nil and current.kind == card.kind and editing ~= card.kind
end

hooks = {
    enter = function(card)
        if isCurrent(card) and not paused then
            paused = math.max(Notifications.HOVER_MIN, (deadline or 0) - (ns.API.Now() or 0))
            token = token + 1 -- the running timer no longer hides it
        end
    end,
    leave = function(card)
        if isCurrent(card) and paused then
            startTimer(current, paused)
        end
    end,
    close = function(card)
        if editing == card.kind then
            return
        end
        token = token + 1
        paused = nil
        card:Hide()
        if current and current.kind == card.kind then
            current = nil
            nextLater()
        end
    end,
    dragStart = function(card)
        if editing == card.kind and edit and not edit.locked then
            card:StartMoving()
        end
    end,
    dragStop = function(card)
        if editing ~= card.kind or not edit then
            return
        end
        card:StopMovingOrSizing()
        if card.SetUserPlaced then card:SetUserPlaced(false) end -- saved by us, not in layout-local.txt
        local point, _, relPoint, x, y = card:GetPoint()
        if ns.Database.NOTIFY_POINTS[point] and type(x) == "number" and type(y) == "number" then
            edit.point, edit.relPoint, edit.x, edit.y = point, relPoint, x, y
            edit.moved = true
        end
    end,
}
Notifications.hooks = hooks -- tests

---------------------------------------------------------------------------
-- Position editor (v1.0.0-beta.6), opened from Settings / Notifications:
-- a sample of one kind stays on screen; it is dragged, scaled, locked or
-- reset; Done saves, Cancel (and leaving Settings) keeps the old place.
-- The sample creates no statistics, achievements, sound or screenshot.
---------------------------------------------------------------------------
local sampleOf -- set below with the tests

local function copy(t)
    if not t then return nil end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- Current place of the card as an editor state.
local function stateOfCard(card, locked)
    local point, _, relPoint, x, y = card:GetPoint()
    return { point = ns.Database.NOTIFY_POINTS[point] and point or "CENTER",
             relPoint = ns.Database.NOTIFY_POINTS[relPoint] and relPoint or nil,
             x = type(x) == "number" and x or 0, y = type(y) == "number" and y or 0,
             scale = card:GetScale() or 1, locked = locked }
end

function Notifications.StartEdit(kind)
    if not Notifications.SETTING[kind] then
        return false
    end
    if editing then
        Notifications.EndEdit(false)
    end
    -- The card on screen goes back to the queue and waits.
    token = token + 1
    paused = nil
    for _, card in pairs(cards) do card:Hide() end
    if current then
        table.insert(queue, 1, current)
        current = nil
    end
    local card = cardOf(kind)
    local n = sampleOf(kind)
    n.count = 1
    draw(n) -- placed where it would appear now
    card:SetAlpha(1)
    card:SetScript("OnUpdate", nil)
    local own = Notifications.Layout(kind)
    edit = copy(own) or stateOfCard(card, nil)
    editing = kind
    return true
end

function Notifications.Editing()
    return editing, edit
end

function Notifications.EditScale(value)
    if not edit then return end
    edit.scale = math.max(0.5, math.min(2, value))
    edit.moved = true
    cardOf(editing):SetScale(edit.scale)
end

-- v1.0.0-beta.10: place and size presets in the edit panel of each kind.
-- They move / scale the sample at once; Done saves them as its own place.
function Notifications.EditPreset(position)
    local p = Notifications.POSITIONS[position]
    if not (edit and p) then return end
    local card = cardOf(editing)
    card:ClearAllPoints()
    card:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    edit.point, edit.relPoint, edit.x, edit.y = p[1], p[1], p[2], p[3]
    edit.preset, edit.moved = position, true
end

function Notifications.EditSize(size)
    local scale = Notifications.SIZES[size]
    if scale then Notifications.EditScale(scale) end
end

-- The preset the edited place matches, or nil (dragged by hand).
function Notifications.EditPresetOf()
    if not edit then return nil end
    for name, p in pairs(Notifications.POSITIONS) do
        if edit.point == p[1] and edit.x == p[2] and edit.y == p[3] then
            return name
        end
    end
    return nil
end

function Notifications.EditLock(value)
    if edit then edit.locked = value and true or nil end
end

-- Back to the common position and size (saved with Done).
function Notifications.EditReset()
    if not editing then return end
    local kind, card = editing, cardOf(editing)
    local own = ns.db.ui.notify
    local saved = own and own[kind]
    if own then own[kind] = nil end
    editing = nil
    place(card)
    editing = kind
    if own then own[kind] = saved end
    edit = stateOfCard(card, edit and edit.locked)
    edit.reset = true
end

function Notifications.EndEdit(save)
    if not editing then
        return false
    end
    local kind, state = editing, edit
    editing, edit = nil, nil
    if save and state then
        local ui = ns.db.ui
        if state.reset and not state.moved then
            if ui.notify then ui.notify[kind] = nil end
        else
            ui.notify = ui.notify or {}
            ui.notify[kind] = { point = state.point, relPoint = state.relPoint, x = state.x, y = state.y,
                                scale = state.scale, locked = state.locked }
        end
    end
    cardOf(kind):Hide()
    if not current and #queue > 0 then
        showNext()
    end
    return true
end

-- Kept for the shot notification (v0.6.0 API).
function Notifications.Show(heading, text, force)
    return Notifications.Push({ kind = "mini", title = heading, text = text }, force)
end

---------------------------------------------------------------------------
-- Tests from Settings / Notifications: nothing is saved, no screenshot.
---------------------------------------------------------------------------
-- A sample of each kind (previews and the position editor).
sampleOf = function(kind)
    local M = ns.Media
    if kind == "discovery" then
        local area = 12 -- Elwynn Forest: its story and, with the ArtPack, its picture
        local story = ns.Stories.Get(area)
        local art, l, r, t, b = ns.ArtPack.Zone(area, (380 - 12) / Notifications.ART_HEIGHT)
        return { kind = "discovery", caption = L.NOTIFY_NEW_ZONE, title = L.NOTIFY_SAMPLE_ZONE,
                 text = story or L.TEST_NOTIFICATION_TEXT, story = story ~= nil, art = art,
                 uv = art and { l, r, t, b } or nil, icon = M.NOTIFY.discovery_compass }
    elseif kind == "legendary" then
        return { kind = "legendary", caption = L.NOTIFY_ACHIEVEMENT, title = L.NOTIFY_SAMPLE_ACHIEVEMENT,
                 text = L.TEST_NOTIFICATION_TEXT, icon = M.NOTIFY.legendary_gem,
                 color = ns.Achievements.RARITY_COLORS.legendary }
    end
    return { kind = "mini", title = L.SHOT_SAVED, text = L.TEST_NOTIFICATION_TEXT, icon = M.NOTIFY.event_success }
end

-- True while the preview of this kind is on screen (v1.0.0-beta.10).
function Notifications.IsPreviewing(kind)
    return current ~= nil and current.kind == kind and current.preview == true
        and cards[kind] ~= nil and cards[kind]:IsShown()
end

-- Preview of a kind; pressed again while it is shown, it closes it.
function Notifications.Test(kind)
    kind = Notifications.SETTING[kind] and kind or "mini"
    if editing then
        Notifications.EndEdit(false)
    end
    if Notifications.IsPreviewing(kind) then
        hooks.close(cards[kind])
        return false
    end
    local n = sampleOf(kind)
    n.preview = true
    Notifications.Push(n, true)
    if ns.db.settings.sound then
        ns.API.PlaySuccessSound()
    end
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
-- Called by the Engine for every finished request.
function Notifications.OnComplete(record, request, result)
    if record then
        local M = ns.Media
        if record.ev == "LOOT_LEGENDARY" then
            Notifications.Push({ kind = "legendary", caption = L.SHOT_SAVED, title = ns.History.Title(record),
                                 text = ns.History.Detail(record), icon = M.NOTIFY.legendary_gem,
                                 color = ns.Achievements.RARITY_COLORS.legendary })
        else
            Notifications.Push({ kind = "mini", title = L.SHOT_SAVED, text = ns.History.Title(record),
                                 icon = ns.Registry.Icon(record.ev) })
        end
        if ns.db.settings.notifications then
            -- v0.6.0: every saved shot is also reported in chat.
            local detail = ns.History.Detail(record)
            ns.API.Print(L.SHOT_SAVED .. ": " .. ns.History.Title(record)
                .. (detail ~= "" and (" (" .. detail .. ")") or ""))
        end
        if ns.db.settings.sound then
            ns.API.PlaySuccessSound()
        end
    elseif request.manual then
        -- Automatic skips go to the log only; a manual one gets feedback.
        local reason = L["REASON_" .. tostring(result.reason)]
        if reason == "REASON_" .. tostring(result.reason) then
            reason = L["STATUS_" .. result.status]
        end
        ns.API.Print(L.MANUAL_NOT_TAKEN .. ": " .. reason)
    end
end

-- A new location of this character (first visit, not the first login):
-- with its story and picture when there are (v0.18.0).
function Notifications.OnZone(_, isNew)
    if isNew then
        local name = ns.API.ZoneName()
        local area = name and ns.ZoneCatalog.AreaOfName(name)
        local story = ns.Stories.Get(area)
        local art, l, r, t, b = ns.ArtPack.Zone(area, (380 - 12) / Notifications.ART_HEIGHT)
        Notifications.Push({ kind = "discovery", caption = L.NOTIFY_NEW_ZONE,
                             title = ns.ZoneText(name) or L.UNKNOWN_LOCATION, text = story or L.NOTIFY_NEW_ZONE_TEXT,
                             story = story ~= nil, art = art, uv = art and { l, r, t, b } or nil,
                             icon = ns.Media.NOTIFY.discovery_compass })
    end
end

-- Achievements earned right now (never the ones found already reached).
function Notifications.OnAchievements(defs)
    local A, M = ns.Achievements, ns.Media
    for _, def in ipairs(defs or {}) do
        local big = def.rarity == "epic" or def.rarity == "legendary"
        local title = A.Text(def, "title") or def.id
        Notifications.Push({
            kind = big and "legendary" or "discovery", caption = L.NOTIFY_ACHIEVEMENT, title = title,
            text = A.Text(def, "description"), color = A.RARITY_COLORS[def.rarity],
            icon = M.MEDALLIONS[def.medallion] or M.MEDALLIONS.special,
        })
        if ns.db.settings.notifications then
            ns.API.Print(L.NOTIFY_ACHIEVEMENT .. ": " .. title)
        end
    end
end

table.insert(ns.Engine.onComplete, Notifications.OnComplete)
table.insert(ns.Locations.listeners, Notifications.OnZone)
