-- Capture/Rules.lua
-- Pure decision: should this game event become a capture request?
-- evaluate(event, profile, context) -> request, or nil plus a reason.
local _, ns = ...

local Rules = {}
ns.Rules = Rules

Rules.TTL_AUTO = 10
Rules.TTL_JOURNEY = 5
Rules.TTL_MANUAL = 30

local JOURNEY_TYPES = { JOURNEY = true, RANDOM = true }

-- context fields:
--   now           current time (seconds)
--   paused        automatic capture is off
--   lastByKey     map event key -> time it last produced a request
--   isFirst(key)  true if this key never produced a confirmed memory
--   limitReason(request) -> reason string when a limit is reached
function Rules.Evaluate(event, profile, context)
    local rule = profile.rules[event.type]
    if not rule then
        return nil, "unknown_trigger"
    end
    if not rule.enabled then
        return nil, "disabled"
    end
    local manual = event.type == "MANUAL"
    if context.paused and not manual then
        return nil, "paused"
    end
    if rule.firstOnly and context.isFirst and not context.isFirst(event.key) then
        return nil, "not_first"
    end
    local window = manual and rule.cooldown or math.max(rule.cooldown, ns.Registry.DEDUPE_WINDOW)
    local last = context.lastByKey and context.lastByKey[event.key]
    if last and window > 0 and context.now - last < window then
        return nil, "cooldown"
    end

    local journey = JOURNEY_TYPES[event.type] or false
    local request = {
        types = { event.type },
        keys = { event.key },
        mode = event.mode or rule.mode,
        frames = event.frames or rule.frames,
        interval = rule.interval,
        priority = manual and 0 or rule.priority,
        createdAt = context.now,
        dueAt = context.now + (event.delay or rule.delay),
        ttl = manual and Rules.TTL_MANUAL or (journey and Rules.TTL_JOURNEY or Rules.TTL_AUTO),
        manual = manual,
        journey = journey,
        limits = ns.Util.Copy(profile.limits),
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
