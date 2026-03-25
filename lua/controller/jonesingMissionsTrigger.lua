-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}


-- ── jbeam lifecycle callbacks ─────────────────────────────────────────────────

local function init(jbeamData)
    -- This controller is attached to the jonesing_dummy jbeam slot, which is a license-plate slot.  
    -- When the Universal Dummy Mod is loaded, it occupies this slot and thus activates this controller.  The controller's purpose is to bridge from the Vehicle-Engine (VE) context to the Game-Engine (GE) context so that propRecycler can spawn and recycle 10 jonesing_dummy pedestrians around the map as traffic.

    -- TODO: Start GTA Like Mission Trigger here, which will spawn random missions for the player to complete as they explore the city. These missions could include tasks such as delivering packages, racing against other NPCs, or evading the police.

    -- Example:
    -- obj:queueGameEngineLua(
    --     "extensions.load('propRecycler');" ..
    --     "propRecycler.spawn10DummiesAndStart({maxDistance=150,leadDistance=50,lateralJitter=10,debug=true})"
    -- )
end


local function reset()
    -- Vehicle reset (I-key / Insert-key): dummies are already alive on the map,
    -- so there is nothing to do here.  A new spawn must NOT be issued on every
    -- reset or the pool would grow by 10 on each respawn.
end


-- ── public interface ──────────────────────────────────────────────────────────
M.init      = init
M.reset     = reset

return M
