-- UI/Minimap.lua
-- Minimap button (spec 9): left click - window, right click - pause /
-- resume, middle click - manual shot. Drag to move it around the minimap.
-- The icon turns grey while auto capture is paused.
local _, ns = ...

local L = ns.L
local W = ns.Widgets

local Minimap = {}
ns.Minimap = Minimap

local button, icon

local function place()
    local angle = math.rad(ns.db.settings.minimapAngle)
    local radius = (_G.Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", _G.Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = _G.Minimap:GetCenter()
    local scale = _G.Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    place()
end

local function showTooltip(self)
    local enabled = ns.db.settings.enabled
    local stats = ns.History.Stats()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local h = W.COLORS.heading
    GameTooltip:SetText("ForeverMemories", h[1], h[2], h[3])
    local s = enabled and W.COLORS.active or W.COLORS.paused
    GameTooltip:AddLine(L.AUTO_CAPTURE .. ": " .. (enabled and L.STATE_ACTIVE or L.STATE_PAUSED), s[1], s[2], s[3])
    GameTooltip:AddLine(ns.character and ns.character.name or "?", 1, 1, 1)
    GameTooltip:AddLine(L.STAT_TODAY .. ": " .. ns.Num(stats.today), 1, 1, 1)
    GameTooltip:AddLine(L.STAT_STEPS_TODAY .. ": " .. ns.Num(ns.Steps.Today()), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.MINIMAP_HINT_LEFT, 0.65, 0.62, 0.56)
    GameTooltip:AddLine(L.MINIMAP_HINT_RIGHT, 0.65, 0.62, 0.56)
    GameTooltip:AddLine(L.MINIMAP_HINT_MIDDLE, 0.65, 0.62, 0.56)
    GameTooltip:AddLine(L.MINIMAP_HINT_DRAG, 0.65, 0.62, 0.56, true)
    GameTooltip:Show()
end

local function build()
    button = CreateFrame("Button", "ForeverMemoriesMinimapButton", _G.Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ns.Media.MINIMAP) -- Obsidian compass (v0.15.0)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ns.Engine.SetEnabled(not ns.db.settings.enabled)
        elseif mouseButton == "MiddleButton" then
            ns.Engine.ManualShot()
        else
            ns.UI.Toggle()
        end
        if GameTooltip:IsOwned(self) then
            showTooltip(self)
        end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Shows or hides the button and paints the paused state.
function Minimap.Update()
    if not _G.Minimap or not ns.db then
        return
    end
    if not button then
        build()
    end
    button:SetShown(ns.db.settings.minimap)
    if icon.SetDesaturated then
        icon:SetDesaturated(not ns.db.settings.enabled)
    end
    place()
end

table.insert(ns.onLogin, Minimap.Update)
table.insert(ns.Engine.stateListeners, Minimap.Update)
