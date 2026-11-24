-- Capture/Strategies.lua
-- Turns a request mode into a list of frames, and decides the real mode of
-- each frame at capture time.
local _, ns = ...

local Strategies = {}
ns.Strategies = Strategies

-- "dual" = one normal and one clean frame per cycle.
function Strategies.Plan(mode, cycles)
    local plan = {}
    for cycle = 1, cycles do
        if mode == "dual" then
            plan[#plan + 1] = { mode = "normal", cycle = cycle }
            plan[#plan + 1] = { mode = "clean", cycle = cycle, pair = true }
        else
            plan[#plan + 1] = { mode = mode, cycle = cycle }
        end
    end
    return plan
end

-- Returns "normal", "clean" or "skip".
-- Unsafe clean: a dual pair keeps only its normal frame, a clean frame
-- degrades to normal. The UI is never hidden in combat.
function Strategies.Resolve(frame, context)
    if frame.mode ~= "clean" then
        return frame.mode
    end
    if context.inCombat or not context.cleanAllowed then
        return frame.pair and "skip" or "normal"
    end
    return "clean"
end
