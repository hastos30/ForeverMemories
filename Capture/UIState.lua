-- Capture/UIState.lua
-- snapshot/prepare/restore of the interface around a screenshot.
-- Restores only what the addon itself changed, and restoring twice is safe.
local _, ns = ...

local UIState = {}
ns.UIState = UIState

local hidUIParent = false
local restoreAfterCombat = false
local hiddenOwn = {}

local function uiParent()
    return _G.UIParent
end

-- Hides our own frames (always) and the whole UI for "clean".
-- Returns the mode really used.
function UIState.Prepare(mode)
    for frame in pairs(ns.ownFrames) do
        if frame:IsShown() then
            frame:Hide()
            hiddenOwn[#hiddenOwn + 1] = frame
        end
    end
    if ns.Notifications then
        ns.Notifications.HideNow()
    end
    if mode ~= "clean" then
        return mode
    end
    local parent = uiParent()
    if ns.API.InCombat() or not parent then
        return "normal"
    end
    if not parent:IsShown() then
        -- The player hid the UI already (Alt+Z): do not touch it.
        return "clean"
    end
    parent:Hide()
    hidUIParent = true
    return "clean"
end

function UIState.IsUIHiddenByUs()
    return hidUIParent
end

function UIState.Restore()
    if hidUIParent then
        if ns.API.InCombat() then
            restoreAfterCombat = true
            ns.Logger.Warn("UI restore delayed until combat ends")
        else
            uiParent():Show()
            hidUIParent = false
            restoreAfterCombat = false
        end
    end
    for i = 1, #hiddenOwn do
        hiddenOwn[i]:Show()
    end
    hiddenOwn = {}
end

-- PLAYER_REGEN_DISABLED fires just before combat lockdown starts, so the
-- UI can still be shown here. This keeps the player from fighting blind.
ns.On("PLAYER_REGEN_DISABLED", function()
    if hidUIParent then
        UIState.Restore()
        if ns.Engine then
            ns.Engine.OnUIRestoredByCombat()
        end
    end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if restoreAfterCombat then
        UIState.Restore()
    end
end)

-- /fm ui: emergency restore, also when the addon did not hide the UI.
function UIState.ForceShow()
    if ns.API.InCombat() then
        return false
    end
    local parent = uiParent()
    if parent and not parent:IsShown() then
        parent:Show()
    end
    hidUIParent = false
    restoreAfterCombat = false
    return true
end
