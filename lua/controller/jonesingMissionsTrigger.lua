-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local function init(jbeamData)
    local plateText = "Jonesing"

    if obj and obj.setDynDataFieldbyName then
        obj:setDynDataFieldbyName("licenseText", 0, plateText)
        obj:setDynDataFieldbyName("licensePlateText", 0, plateText)
    end

    obj:queueGameEngineLua("extensions.load('gameplay/jonesingMissions')")
end

local function reset()
    -- Do nothing on vehicle reset.
end

M.init = init
M.reset = reset

return M