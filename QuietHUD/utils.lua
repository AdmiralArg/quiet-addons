local addonName, privateTable = ...

privateTable.Utils = {}

--- Validates if a UI object exposes the required API surface and is not protected by the client's security model.
--- @param frame table|userdata The UI object to evaluate.
--- @return boolean True if the object is safe to manipulate.
function privateTable.Utils.IsFrameAccessible(frame)
    if type(frame) ~= "table" and type(frame) ~= "userdata" then
        return false
    end

    if type(frame.GetAlpha) ~= "function" or type(frame.SetAlpha) ~= "function" then
        return false
    end

    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return false
    end

    return true
end

-- Sliders step in whole numbers (Improved Forever's, and the kit's go there as they are): alphas are shown in
-- percent, times in tenths (or hundredths) of a second, and turned back when stored. Here, in the first file loaded,
-- because both frames.lua and settings.lua take them as they load.
function privateTable.ToSteps(value, scale)
    return math.floor((value or 0) * scale + 0.5)
end

function privateTable.FromSteps(steps, scale)
    return math.floor(steps + 0.5) / scale
end