-- Modules/Notifications.lua
-- A small toast and a chat line (v0.6.0) after a shot is saved and the UI
-- is restored. The toast is hidden before every capture, so it never
-- appears in a screenshot. Both follow the "notifications" setting.
-- The Step Tracker has no notifications.
local _, ns = ...

local Notifications = {}
ns.Notifications = Notifications

-- Seconds on screen: the "toastDuration" setting (3, 5 or 10; v0.10.0).
function Notifications.Duration()
    return ns.db and ns.db.settings.toastDuration or 5
end

local L = ns.L
local frame, title, line
local hideToken = 0

local function ensureFrame()
    if frame then
        return
    end
    local W = ns.Widgets
    frame = CreateFrame("Frame", "ForeverMemoriesToast", UIParent, "BackdropTemplate")
    frame:SetSize(300, 50)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    frame:SetFrameStrata("HIGH")
    W.Backdrop(frame, W.COLORS.background, 0.94)
    local icon = W.Icon(frame, "Interface\\Icons\\INV_Misc_Spyglass_03", 30)
    icon:SetPoint("LEFT", 10, 0)
    title = W.Text(frame, "", "GameFontNormal", W.COLORS.heading)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    title:SetPoint("RIGHT", -10, 0)
    line = W.Text(frame, "", "GameFontHighlightSmall", W.COLORS.text)
    line:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)
    line:SetPoint("RIGHT", -10, 0)
    frame:EnableMouse(false) -- never in the way of the game
    frame:Hide()
end

function Notifications.HideNow()
    hideToken = hideToken + 1
    if frame then
        frame:Hide()
    end
end

-- `force` shows it even with notifications off ("Test notification").
function Notifications.Show(heading, text, force)
    if not ns.db.settings.notifications and not force then
        return
    end
    ensureFrame()
    title:SetText(heading)
    line:SetText(text or "")
    frame:Show()
    hideToken = hideToken + 1
    local myToken = hideToken
    ns.API.After(Notifications.Duration(), function()
        if myToken == hideToken then
            frame:Hide()
        end
    end)
end

-- Settings / General: "Test notification" with the current duration and
-- sound. Nothing is saved and no screenshot is taken.
function Notifications.Test()
    Notifications.Show(L.SHOT_SAVED, L.TEST_NOTIFICATION_TEXT, true)
    if ns.db.settings.sound then
        ns.API.PlaySuccessSound()
    end
end

-- Called by the Engine for every finished request.
function Notifications.OnComplete(record, request, result)
    if record then
        Notifications.Show(L.SHOT_SAVED, ns.History.Title(record))
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

table.insert(ns.Engine.onComplete, Notifications.OnComplete)
