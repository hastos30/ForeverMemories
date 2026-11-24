-- Core/API.lua
-- The only place that touches World of Warcraft client functions directly.
-- Every wrapper returns a value, or nil plus a reason string, and never
-- assumes that a function exists: Forever may differ from Retail.
local _, ns = ...

local API = {}
ns.API = API

local function isFunction(value)
    return type(value) == "function"
end

-- Resolves a dotted name such as "C_Timer.After" in the global table.
-- Returns the function or nil.
function API.Resolve(name)
    local current = _G
    for part in string.gmatch(name, "[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[part]
    end
    if isFunction(current) then
        return current
    end
    return nil
end

function API.GetBuild()
    if not isFunction(GetBuildInfo) then
        return nil, "GetBuildInfo unavailable"
    end
    local version, build, buildDate, tocVersion = GetBuildInfo()
    return {
        version = tostring(version),
        build = tostring(build),
        date = tostring(buildDate),
        toc = tonumber(tocVersion),
    }
end

-- Returns true/false when the client can tell, or nil plus a reason.
function API.IsEventValid(event)
    local isValid = API.Resolve("C_EventUtils.IsEventValid")
    if not isValid then
        return nil, "C_EventUtils.IsEventValid unavailable"
    end
    return isValid(event) and true or false
end

-- Registers an event on a frame without throwing on unknown events.
function API.RegisterFrameEvent(frame, event)
    if API.IsEventValid(event) == false then
        return false, "unknown event"
    end
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        return false, tostring(err)
    end
    return true
end

-- Calls the client Screenshot(). A Lua error is caught here; a blocked
-- protected call is reported by the client through ADDON_ACTION_* events,
-- which the probe records separately.
function API.TakeScreenshot()
    if not isFunction(Screenshot) then
        return nil, "Screenshot unavailable"
    end
    local ok, err = pcall(Screenshot)
    if not ok then
        return nil, tostring(err)
    end
    return true
end

function API.After(seconds, callback)
    local after = API.Resolve("C_Timer.After")
    if not after then
        return nil, "C_Timer.After unavailable"
    end
    after(seconds, callback)
    return true
end

-- Seconds since an arbitrary point, for measuring durations.
function API.Now()
    return GetTime()
end

-- Unix time, for saving dates.
function API.Time()
    return time()
end

function API.InCombat()
    if not isFunction(InCombatLockdown) then
        return nil, "InCombatLockdown unavailable"
    end
    return InCombatLockdown() and true or false
end

function API.Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffC9A35EForeverMemories|r: " .. tostring(message))
    end
end
