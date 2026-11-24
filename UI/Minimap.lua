-- UI/Minimap.lua
-- Minimap button: left click - window, right click - pause/resume,
-- middle click - manual shot. Drag to move around the minimap.
local _, ns = ...

local L = ns.L

local Minimap = {}
ns.Minimap = Minimap

local button

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

local function build()
    button = CreateFrame("Button", "ForeverMemoriesMinimapButton", _G.Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Engine.SetEnabled(not ns.db.settings.enabled)
        elseif mouseButton == "MiddleButton" then
            ns.Engine.ManualShot()
        else
            ns.UI.Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ForeverMemories")
        GameTooltip:AddLine(L.AUTO_CAPTURE .. ": " .. (ns.db.settings.enabled and L.ON or L.OFF), 1, 1, 1)
        GameTooltip:AddLine(string.format(L.TOOLTIP_TODAY, ns.Statistics.Get().today), 1, 1, 1)
        GameTooltip:AddLine(L.TOOLTIP_HINT, 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L.TIP_MINIMAP_DRAG, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Minimap.Update()
    if not _G.Minimap then
        return
    end
    if not button then
        build()
    end
    button:SetShown(ns.db.settings.minimap)
    place()
end

table.insert(ns.onLogin, Minimap.Update)
