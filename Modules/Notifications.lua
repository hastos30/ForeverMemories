-- Modules/Notifications.lua
-- A small toast after a capture is finished and the UI is restored.
-- It is hidden before every capture so it never appears in a memory.
local _, ns = ...

local Notifications = {}
ns.Notifications = Notifications

local L = ns.L
local frame, text
local hideToken = 0

local function ensureFrame()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "ForeverMemoriesToast", UIParent, "BackdropTemplate")
    frame:SetSize(360, 46)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    frame:SetFrameStrata("HIGH")
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.063, 0.063, 0.059, 0.92)
        frame:SetBackdropBorderColor(0.788, 0.639, 0.369, 1)
    end
    text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    text:SetWidth(340)
    frame:Hide()
end

function Notifications.HideNow()
    hideToken = hideToken + 1
    if frame then
        frame:Hide()
    end
end

function Notifications.Message(message)
    if not ns.db.settings.notifications then
        return
    end
    ensureFrame()
    text:SetText(message)
    frame:Show()
    hideToken = hideToken + 1
    local myToken = hideToken
    ns.API.After(ns.db.settings.notifyDuration, function()
        if myToken == hideToken then
            frame:Hide()
        end
    end)
end

function Notifications.EventNames(entry)
    local names = {}
    for _, kind in ipairs(entry.events) do
        names[#names + 1] = L["TRIGGER_" .. kind]
    end
    return table.concat(names, ", ")
end

-- Called by the Engine for every finished request.
function Notifications.OnComplete(entry)
    local what = Notifications.EventNames(entry)
    local where = entry.zone and (" - " .. entry.zone) or ""
    if entry.status == "success" or entry.status == "partial" then
        Notifications.Message("|cff7CAA66" .. L.MEMORY_SAVED .. "|r\n" .. what .. where)
        if ns.db.settings.sound then
            ns.API.PlaySuccessSound()
        end
    elseif entry.status == "unconfirmed" then
        Notifications.Message(L.MEMORY_UNCONFIRMED .. "\n" .. what)
    elseif entry.manual then
        -- Automatic skips stay in the journal; manual ones get feedback.
        local reason = entry.skipReason and L["REASON_" .. entry.skipReason] or L["STATUS_" .. entry.status]
        ns.API.Print(L.MANUAL_NOT_TAKEN .. ": " .. reason)
    end
end

table.insert(ns.Engine.onComplete, Notifications.OnComplete)

-- Anniversary: once a day at login, remind about memories from this day
-- in earlier years.
table.insert(ns.onLogin, function()
    local now = ns.API.Time()
    local today = date("%Y-%m-%d", now)
    if ns.db.settings.anniversaryShown == today then
        return
    end
    local entries = ns.Journal.Anniversary(now)
    if #entries == 0 then
        return
    end
    ns.db.settings.anniversaryShown = today
    ns.API.Print(L.ANNIVERSARY_TITLE)
    for i = 1, math.min(3, #entries) do
        local entry = entries[i]
        ns.API.Print(string.format("  %s: %s%s", date("%Y-%m-%d", entry.t),
            Notifications.EventNames(entry), entry.zone and (" - " .. entry.zone) or ""))
    end
end)
