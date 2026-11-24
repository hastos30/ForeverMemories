-- Capture/Rules.lua
-- Pure decision: should this game event become a capture request?
-- Evaluate(event, settings, context) -> request, or nil plus a reason.
local _, ns = ...

local Rules = {}
ns.Rules = Rules

Rules.TTL_AUTO = 10    -- seconds a request may wait before it is stale
Rules.TTL_MANUAL = 30

-- context fields:
--   now                   current time (seconds)
--   lastByKey             map event key -> time it last produced a request
--   limitReason(request)  reason string when an internal limit is reached
function Rules.Evaluate(event, settings, context)
    local trigger = ns.Registry.TRIGGERS[event.type]
    if not trigger then
        return nil, "unknown_trigger"
    end
    local manual = event.type == "MANUAL"
    if not manual then
        if not ns.Registry.IsAvailable(event.type) then
            return nil, "unavailable"
        end
        if not settings.events[event.type] then
            return nil, "disabled"
        end
        if not settings.enabled then
            return nil, "paused"
        end
        local last = context.lastByKey and context.lastByKey[event.key]
        if last and context.now - last < ns.Registry.DEDUPE_WINDOW then
            return nil, "duplicate"
        end
    end

    local request = {
        types = { event.type },
        keys = { event.key },
        infos = { event.info or false },
        mode = settings.mode,
        priority = trigger.priority,
        createdAt = context.now,
        dueAt = context.now + trigger.delay,
        ttl = manual and Rules.TTL_MANUAL or Rules.TTL_AUTO,
        manual = manual,
        character = event.character,
        zone = event.zone,
    }
    if context.limitReason then
        local reason = context.limitReason(request)
        if reason then
            return nil, reason
        end
    end
    return request
end
