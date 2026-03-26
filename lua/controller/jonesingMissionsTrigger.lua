-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}


-- ── jbeam lifecycle callbacks ─────────────────────────────────────────────────

local function init(jbeamData)
    -- This controller is attached to the jonesing_dummy jbeam slot, which is a license-plate slot.
    -- When the Universal Dummy Mod is loaded, it occupies this slot and thus activates this controller.
    -- The controller bridges from the Vehicle-Engine (VE) context to the Game-Engine (GE) context to
    -- load the GTA-like mission system extension.

    -- Load the mission manager extension in the Game-Engine context.  It draws glowing mission-start
    -- markers at key map locations and, when the player drives into one, spawns either a fleeing
    -- target vehicle (CHASE) or a ring of pursuing police cars (ESCAPE).
    obj:queueGameEngineLua("extensions.load('gameplay/jonesingMissions')")
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
