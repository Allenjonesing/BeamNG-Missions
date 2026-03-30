-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- Jonesing GTA-like Mission System
--
-- Draws GTA-style glowing beacon columns at key map locations.  When the player
-- drives into a marker a mission begins:
--
--   CHASE  – a target vehicle spawns and flees; player must catch and destroy it.
--   ESCAPE – police spawn; player must outrun them all within the time limit.
--   FOLLOW – player must tail a moving target, stay close without damaging it.
--   ENDURE – police recycle endlessly; survive the full time limit without being wrecked.
--   REACH  – escape recycling police and drive to a destination column of light.
--
-- Mission markers are placed on valid roadways using the map navigation graph so
-- they are always accessible by vehicle.  Positions are randomised each session.
--
-- An ImGui HUD panel (top-left) shows every mission with a compass direction and
-- distance so the player can navigate to them from anywhere on the map.

local M = {}

-- ── Mission types ──────────────────────────────────────────────────────────────
local CHASE  = "chase"
local ESCAPE = "escape"
local FOLLOW = "follow"
local ENDURE = "endure"
local REACH  = "reach"

-- ── Mission templates ──────────────────────────────────────────────────────────
-- Positions are assigned at runtime from the map navigation graph.  The fallback
-- coordinates target West Coast USA.
local missionTemplates = {
    {
        name          = "Smash and Grab",
        type          = CHASE,
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.70 },
        fallbackPos   = vec3(  100,  200, 25),
    },
    {
        name          = "Heat Wave",
        type          = ESCAPE,
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.70 },
        fallbackPos   = vec3( -300,  100, 20),
    },
    {
        name          = "Interstate Takedown",
        type          = CHASE,
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.70 },
        fallbackPos   = vec3(  500, -200, 30),
    },
    {
        name          = "Ambush Alley",
        type          = ESCAPE,
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.70 },
        fallbackPos   = vec3( -100,  500, 22),
    },
    {
        name          = "Marked for Destruction",
        type          = CHASE,
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.70 },
        fallbackPos   = vec3(  300,  350, 28),
    },
    {
        name          = "Phantom Tail",
        type          = FOLLOW,
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.85, b = 0.60, a = 0.70 },
        fallbackPos   = vec3(  200, -100, 25),
    },
    {
        name          = "Endless Pursuit",
        type          = ENDURE,
        triggerRadius = 12,
        color         = { r = 0.70, g = 0.10, b = 0.90, a = 0.70 },
        fallbackPos   = vec3( -200,  350, 22),
    },
    {
        name          = "Extraction Point",
        type          = REACH,
        triggerRadius = 12,
        color         = { r = 0.85, g = 0.90, b = 1.00, a = 0.70 },
        needsDest     = true,
        fallbackPos   = vec3(  400,  100, 28),
        fallbackDest  = vec3( -400, -300, 25),
    },
    {
        name          = "Ghost Recon",
        type          = FOLLOW,
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.85, b = 0.60, a = 0.70 },
        fallbackPos   = vec3( -350, -150, 24),
    },
    {
        name          = "Iron Will",
        type          = ENDURE,
        triggerRadius = 12,
        color         = { r = 0.70, g = 0.10, b = 0.90, a = 0.70 },
        fallbackPos   = vec3(  150,  450, 26),
    },
    {
        name          = "Midnight Run",
        type          = REACH,
        triggerRadius = 12,
        color         = { r = 0.85, g = 0.90, b = 1.00, a = 0.70 },
        needsDest     = true,
        fallbackPos   = vec3( -250, -400, 20),
        fallbackDest  = vec3(  350,  250, 30),
    },
    {
        name          = "Blitz Escape",
        type          = ESCAPE,
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.70 },
        fallbackPos   = vec3(  450, -350, 27),
    },
}

-- ── Tuning constants ───────────────────────────────────────────────────────────
local PULSE_SPEED           = 1.5    -- marker pulse rate (radians / second)
local ESCAPE_TIME_LIMIT     = 180    -- seconds before ESCAPE mission fails
local MISSION_COOLDOWN      = 10     -- seconds before the same marker can re-trigger
local ESCAPE_MIN_DISTANCE   = 250    -- metres: all police beyond this = escaped (ESCAPE win)
local CHASE_DAMAGE_THRESH   = 0.75   -- damage fraction that counts as "destroyed"
local CHASE_ESCAPE_DISTANCE = 300    -- metres: target beyond this = got away (CHASE fail)
local CHASE_SPAWN_OFFSET    = 80     -- metres ahead of player to spawn the target
local CHASE_TARGET_MODEL    = "etk800"
local POLICE_SPAWN_RADIUS   = { min = 40, max = 60 }
local POLICE_COUNT          = 3      -- kept small for performance

-- FOLLOW mission tuning
local FOLLOW_MIN_DIST       = 15     -- metres: too close = out-of-range
local FOLLOW_MAX_DIST       = 60     -- metres: too far  = out-of-range
local FOLLOW_GRACE          = 3.0    -- seconds the player can be out-of-range before failing
local FOLLOW_DURATION       = 90     -- seconds of sustained in-range following = success
local FOLLOW_DAMAGE_THRESH  = 0.30   -- damage to followed vehicle that triggers failure
local FOLLOW_DMG_INTERVAL   = 1.0    -- seconds between VE-side damage re-checks

-- ENDURE mission tuning
local ENDURE_TIME_LIMIT        = 90     -- seconds to survive recycling police = success
local ENDURE_RECYCLE_DIST      = 300    -- police beyond this from the player are teleported back
local POLICE_TELEPORT_RADIUS   = { min = 150, max = 250 }  -- far-ahead recycle teleport range (m)
local POLICE_TELEPORT_INTERVAL = 2.0    -- seconds between recycle-teleport checks

-- REACH mission tuning
local REACH_TIME_LIMIT      = 180    -- seconds to reach destination before failing
local REACH_RADIUS          = 20     -- metres: arriving within this of destPos = success

-- Player damage tracking (ESCAPE / ENDURE / REACH fail condition)
local PLAYER_DAMAGE_THRESH      = 0.80   -- player vehicle wrecked at this damage level
local PLAYER_DMG_CHECK_INTERVAL = 1.0    -- seconds between VE-side player damage checks

-- Beacon visual constants — dense pillar so spheres overlap and form a solid column
local BEACON_BELOW        = 40     -- metres below marker Z — pierces shallow terrain
local BEACON_ABOVE        = 200    -- metres above marker Z — visible from far away
local BEACON_STEPS        = 100    -- sphere slices; denser steps for the taller pillar
local BEACON_PILLAR_R     = 2.5    -- radius of pillar spheres (m)
local BEACON_RING_SEGS    = 12     -- segments in the ground-level trigger ring

-- Destination beacon (REACH mission) — brighter and distinct from mission markers (larger radius)
local DEST_BEACON_BELOW   = 40
local DEST_BEACON_ABOVE   = 200
local DEST_BEACON_STEPS   = 100
local DEST_BEACON_R       = 3.0   -- larger than BEACON_PILLAR_R so it stands out
local DEST_BEACON_RING    = 12

-- Road placement tuning
local MIN_MISSION_SPACING  = 200    -- metres between mission markers
local INIT_TIMEOUT         = 5.0    -- seconds to wait for map data before using fallback positions

-- HUD constants
local HUD_WINDOW_WIDTH    = 275
local DIST_KM_THRESHOLD   = 1000   -- metres; above this shown in km

-- ── State ──────────────────────────────────────────────────────────────────────
local pulseTime         = 0
local mission           = nil   -- active mission table, or nil when idle
local spawnedVehicles   = {}    -- { id = <vehicleID>, role = "target"|"police" }
local missionCooldowns  = {}    -- mp.name -> seconds remaining on cooldown
local destroyedTargets  = {}    -- [vehicleID] = true when VE reports damage >= threshold
local playerWrecked     = false -- set by VE callback when player damage >= threshold
local missionPoints     = {}    -- populated at init from templates + road positions
local initialized       = false -- true once mission positions have been assigned
local initTimer         = 0     -- seconds spent waiting for map data

-- ── Road position finding ──────────────────────────────────────────────────────
-- Collects positions from the map navigation graph (road network) and returns
-- `count` positions that are at least `minSpacing` metres apart.  Returns nil if
-- the map graph is unavailable or has too few nodes.
local function findRandomRoadPositions(count, minSpacing)
    if not map or not map.getGraphpath then return nil end

    local ok, gp = pcall(map.getGraphpath)
    if not ok or not gp then return nil end

    -- Collect all road node positions from the graph
    local allPositions = {}

    -- Try the positions table first (common in recent BeamNG versions)
    if type(gp.positions) == "table" then
        for _, pos in pairs(gp.positions) do
            if pos and type(pos.x) == "number" then
                table.insert(allPositions, vec3(pos.x, pos.y, pos.z))
            end
        end
    end

    -- Fallback: read positions from graph node data
    if #allPositions == 0 and type(gp.graph) == "table" then
        for _, nodeData in pairs(gp.graph) do
            if type(nodeData) == "table" and nodeData.pos then
                local p = nodeData.pos
                if type(p.x) == "number" then
                    table.insert(allPositions, vec3(p.x, p.y, p.z))
                end
            end
        end
    end

    if #allPositions < count then return nil end

    -- Fisher-Yates shuffle for random selection
    for i = #allPositions, 2, -1 do
        local j = math.random(1, i)
        allPositions[i], allPositions[j] = allPositions[j], allPositions[i]
    end

    -- Pick positions that are at least minSpacing apart
    local chosen = {}
    for _, pos in ipairs(allPositions) do
        local tooClose = false
        for _, c in ipairs(chosen) do
            if pos:distance(c) < minSpacing then
                tooClose = true
                break
            end
        end
        if not tooClose then
            table.insert(chosen, pos)
            if #chosen >= count then break end
        end
    end

    return #chosen >= count and chosen or nil
end

-- Counts how many positions are needed (one per mission plus one extra per REACH for destPos).
local function countNeededPositions()
    local n = 0
    for _, tpl in ipairs(missionTemplates) do
        n = n + 1
        if tpl.needsDest then n = n + 1 end
    end
    return n
end

-- Builds the missionPoints table from templates using the given list of road positions.
local function buildMissionPointsFromPositions(positions)
    missionPoints = {}
    local idx = 1
    for _, tpl in ipairs(missionTemplates) do
        local mp = {
            name          = tpl.name,
            type          = tpl.type,
            triggerRadius = tpl.triggerRadius,
            color         = tpl.color,
            pos           = positions[idx],
        }
        idx = idx + 1
        if tpl.needsDest then
            mp.destPos = positions[idx]
            idx = idx + 1
        end
        mp.triggerRadiusSq        = mp.triggerRadius * mp.triggerRadius
        missionCooldowns[mp.name] = 0
        table.insert(missionPoints, mp)
    end
end

-- Builds the missionPoints table using hardcoded fallback coordinates.
local function buildMissionPointsFallback()
    missionPoints = {}
    for _, tpl in ipairs(missionTemplates) do
        local mp = {
            name          = tpl.name,
            type          = tpl.type,
            triggerRadius = tpl.triggerRadius,
            color         = tpl.color,
            pos           = tpl.fallbackPos,
        }
        if tpl.needsDest then
            mp.destPos = tpl.fallbackDest
        end
        mp.triggerRadiusSq        = mp.triggerRadius * mp.triggerRadius
        missionCooldowns[mp.name] = 0
        table.insert(missionPoints, mp)
    end
end

-- Attempts to place missions on valid road positions.  Returns true on success.
local function tryInitMissions()
    local needed    = countNeededPositions()
    local positions = findRandomRoadPositions(needed, MIN_MISSION_SPACING)

    if positions then
        buildMissionPointsFromPositions(positions)
        log("I", "jonesingMissions",
            "Placed " .. #missionPoints .. " missions on road positions from the navigation graph.")
        return true
    end
    return false
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function getPlayerVehicle()
    return be:getPlayerVehicle(0)
end

local function getPlayerPos()
    local v = getPlayerVehicle()
    if not v then return nil end
    return v:getPosition()
end

local function notify(msgType, title, msg)
    guihooks.trigger("toastrMsg", { type = msgType, title = title, msg = msg })
end

-- Builds the VE-side Lua command string that checks vehicle damage and fires a GE
-- callback.  obj:getDamage() is wrapped in pcall because the method was removed in
-- newer BeamNG versions; the fallback reads obj.damage as a direct field.
local function makeDamageCheckCmd(threshold, vehicleId)
    return string.format([[
        local ok, d = pcall(function() return obj:getDamage() end)
        if not ok then d = type(obj.damage) == 'number' and obj.damage or 0 end
        if d >= %f then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportTargetDamaged(%d)')
        end
    ]], threshold, vehicleId)
end

-- Same as above but fires reportFollowTargetDamaged (FOLLOW missions).
local function makeFollowDamageCheckCmd(threshold, vehicleId)
    return string.format([[
        local ok, d = pcall(function() return obj:getDamage() end)
        if not ok then d = type(obj.damage) == 'number' and obj.damage or 0 end
        if d >= %f then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportFollowTargetDamaged(%d)')
        end
    ]], threshold, vehicleId)
end

-- VE-side command that checks the *player* vehicle's damage and fires
-- reportPlayerWrecked when the threshold is exceeded (ESCAPE/ENDURE/REACH).
local function makePlayerDamageCheckCmd(threshold)
    return string.format([[
        local ok, d = pcall(function() return obj:getDamage() end)
        if not ok then d = type(obj.damage) == 'number' and obj.damage or 0 end
        if d >= %f then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportPlayerWrecked()')
        end
    ]], threshold)
end

-- Returns an 8-point compass abbreviation for a world-space (dx, dy) vector.
-- Axis convention: +X = East, +Y = North (standard BeamNG world coordinates).
local function compassDir(dx, dy)
    local angle = math.atan2(dy, dx) * (180 / math.pi)
    if angle < 0 then angle = angle + 360 end
    local dirs = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
    local idx   = (math.floor((angle + 22.5) / 45) % 8) + 1
    return dirs[idx]
end

-- Spawns one police/pursuer at a random position around playerPos and sets its AI.
-- Returns the spawned vehicle object, or nil on failure.
local function spawnPoliceVehicle(playerPos, playerID)
    local angle    = math.random() * 2 * math.pi
    local dist     = math.random(POLICE_SPAWN_RADIUS.min, POLICE_SPAWN_RADIUS.max)
    local spawnPos = vec3(
        playerPos.x + math.cos(angle) * dist,
        playerPos.y + math.sin(angle) * dist,
        playerPos.z
    )
    local veh = core_vehicles.spawnNewVehicle("etk800", {
        pos   = spawnPos,
        rot   = quat(0, 0, 0, 1),
        color = "0.85 0.85 0.85 1",
    })
    if veh then
        veh:queueLuaCommand(
            "ai.setMode('chase'); ai.setTargetObjectID(" .. tostring(playerID) .. ")"
        )
    end
    return veh
end

-- ── Beacon rendering ───────────────────────────────────────────────────────────
-- Draws a GTA-style vertical beacon column.
local function drawBeacon(mp, col)
    local cx   = mp.pos.x
    local cy   = mp.pos.y
    local cz   = mp.pos.z
    local botZ = cz - BEACON_BELOW
    local topZ = cz + BEACON_ABOVE

    -- Ground-level trigger ring (ring of small spheres at the trigger radius)
    for s = 0, BEACON_RING_SEGS - 1 do
        local a  = (s / BEACON_RING_SEGS) * 2 * math.pi
        local rx = cx + math.cos(a) * mp.triggerRadius
        local ry = cy + math.sin(a) * mp.triggerRadius
        debugDrawer:drawSphere(vec3(rx, ry, cz), 1.0, col)
    end

    -- Vertical pillar (gentle taper keeps spheres large enough to overlap at every step)
    for s = 0, BEACON_STEPS do
        local t = s / BEACON_STEPS
        local z = botZ + t * (topZ - botZ)
        local r = BEACON_PILLAR_R * (1.0 - t * 0.20)
        debugDrawer:drawSphere(vec3(cx, cy, z), r, col)
    end

    -- Cap sphere at the very top
    debugDrawer:drawSphere(vec3(cx, cy, topZ), mp.triggerRadius * 0.35, col)
end

-- Draws the REACH destination beacon — a bright white full pillar at destPos.
local function drawDestBeacon(destPos, pulse)
    local cx   = destPos.x
    local cy   = destPos.y
    local cz   = destPos.z
    local botZ = cz - DEST_BEACON_BELOW   -- extends underground like regular beacons
    local topZ = cz + DEST_BEACON_ABOVE
    local col  = ColorF(1.0, 1.0, 1.0, 0.55 + 0.45 * pulse)

    -- Outer ring at ground level marks the landing zone
    for s = 0, DEST_BEACON_RING - 1 do
        local a  = (s / DEST_BEACON_RING) * 2 * math.pi
        local rx = cx + math.cos(a) * REACH_RADIUS
        local ry = cy + math.sin(a) * REACH_RADIUS
        debugDrawer:drawSphere(vec3(rx, ry, cz), 1.5, col)
    end

    -- Full vertical pillar (same style as mission markers — bottom to top, gentle taper)
    for s = 0, DEST_BEACON_STEPS do
        local t = s / DEST_BEACON_STEPS
        local z = botZ + t * (topZ - botZ)
        local r = DEST_BEACON_R * (1.0 - t * 0.20)
        debugDrawer:drawSphere(vec3(cx, cy, z), r, col)
    end

    -- Cap
    debugDrawer:drawSphere(vec3(cx, cy, topZ), REACH_RADIUS * 0.35, col)
end

-- ── Mission start helpers ──────────────────────────────────────────────────────
local function startChase(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    local offset   = vec3(math.random(-40, 40), CHASE_SPAWN_OFFSET, 0)
    local spawnPos = vec3(playerPos.x + offset.x, playerPos.y + offset.y, playerPos.z)

    -- core_vehicles.spawnNewVehicle returns the vehicle object (userdata), not a number.
    local targetVeh = core_vehicles.spawnNewVehicle(CHASE_TARGET_MODEL, {
        pos    = spawnPos,
        rot    = quat(0, 0, 0, 1),
        config = "vehicles/etk800/etk800.pc",
        color  = "0.1 0.3 0.9 1",
    })

    if targetVeh then
        local targetID = targetVeh:getID()
        table.insert(spawnedVehicles, { id = targetID, role = "target" })
        targetVeh:queueLuaCommand(
            "ai.setMode('flee'); ai.setTargetObjectID(" .. tostring(playerID) .. ")"
        )
        -- VE-side damage monitor; fires GE callback when threshold is reached
        targetVeh:queueLuaCommand(makeDamageCheckCmd(CHASE_DAMAGE_THRESH, targetID))
        be:enterVehicle(0, playerVeh)
        notify("info",
            "MISSION: " .. point.name,
            string.format(
                "A suspect vehicle is fleeing! Chase it down and wreck it before it escapes beyond %d m. "
                .. "Ram it, pit manoeuvre it — do whatever it takes to stop it!",
                CHASE_ESCAPE_DISTANCE))
    else
        notify("error", "Spawn Failed", "Could not spawn chase target — mission aborted.")
        cleanupMission(false, "Target failed to spawn.")
    end
end

local function startEscape(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    for i = 1, POLICE_COUNT do
        local pVeh = spawnPoliceVehicle(playerPos, playerID)
        if pVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            table.insert(spawnedVehicles, { id = pVeh:getID(), role = "police" })
        end
    end
    be:enterVehicle(0, playerVeh)

    local spawned = mission.policeSpawned or 0
    if spawned == 0 then
        notify("error", "Spawn Failed", "No police vehicles could spawn — mission aborted.")
        cleanupMission(false, "Police failed to spawn.")
        return
    end
    notify("warning",
        "MISSION: " .. point.name,
        string.format(
            "You've been spotted! %d police unit%s in hot pursuit! "
            .. "Put %d m between you and every officer to shake them. "
            .. "You have %d seconds — and if they wreck your vehicle, it's over!",
            spawned, spawned ~= 1 and "s are" or " is",
            ESCAPE_MIN_DISTANCE, ESCAPE_TIME_LIMIT))
end

local function startFollow(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end

    -- Spawn the target vehicle ~50 m ahead in a random direction
    local angle    = math.random() * 2 * math.pi
    local spawnPos = vec3(
        playerPos.x + math.cos(angle) * 50,
        playerPos.y + math.sin(angle) * 50,
        playerPos.z
    )

    local targetVeh = core_vehicles.spawnNewVehicle("etk800", {
        pos   = spawnPos,
        rot   = quat(0, 0, 0, 1),
        color = "0.9 0.7 0.1 1",  -- yellow-gold so the player can identify it
    })

    if targetVeh then
        local targetID = targetVeh:getID()
        table.insert(spawnedVehicles, { id = targetID, role = "target" })
        -- traffic mode: vehicle drives on roads as if it were a civilian
        targetVeh:queueLuaCommand("ai.setMode('traffic')")
        -- Initial VE-side damage check; re-queued every FOLLOW_DMG_INTERVAL seconds
        targetVeh:queueLuaCommand(makeFollowDamageCheckCmd(FOLLOW_DAMAGE_THRESH, targetID))
        be:enterVehicle(0, playerVeh)
        notify("info",
            "MISSION: " .. point.name,
            string.format(
                "An undercover target is on the move! Tail the yellow vehicle and stay between "
                .. "%d m and %d m for %d seconds. Don't get too close or you'll blow your cover "
                .. "— and don't collide with them or the operation is compromised!",
                FOLLOW_MIN_DIST, FOLLOW_MAX_DIST, FOLLOW_DURATION))
    else
        notify("error", "Spawn Failed", "Could not spawn follow target — mission aborted.")
        cleanupMission(false, "Target failed to spawn.")
    end
end

local function startEndure(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    for i = 1, POLICE_COUNT do
        local pVeh = spawnPoliceVehicle(playerPos, playerID)
        if pVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            table.insert(spawnedVehicles, { id = pVeh:getID(), role = "police" })
        end
    end
    be:enterVehicle(0, playerVeh)

    local spawned = mission.policeSpawned or 0
    if spawned == 0 then
        notify("error", "Spawn Failed", "No police could spawn — mission aborted.")
        cleanupMission(false, "Police failed to spawn.")
        return
    end
    mission.recycleTimer = 0
    notify("warning",
        "MISSION: " .. point.name,
        string.format(
            "You're surrounded and reinforcements are endless! Survive for %d seconds as police "
            .. "units swarm your position. If your vehicle is wrecked, it's all over — stay mobile "
            .. "and stay alive!",
            ENDURE_TIME_LIMIT))
end

local function startReach(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    for i = 1, POLICE_COUNT do
        local pVeh = spawnPoliceVehicle(playerPos, playerID)
        if pVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            table.insert(spawnedVehicles, { id = pVeh:getID(), role = "police" })
        end
    end
    be:enterVehicle(0, playerVeh)

    local spawned = mission.policeSpawned or 0
    if spawned == 0 then
        notify("error", "Spawn Failed", "No police could spawn — mission aborted.")
        cleanupMission(false, "Police failed to spawn.")
        return
    end
    mission.recycleTimer = 0
    notify("warning",
        "MISSION: " .. point.name,
        string.format(
            "The extraction point is marked — get there in %d seconds! Police will pursue "
            .. "relentlessly and won't give up. If your vehicle is destroyed before you arrive, "
            .. "the mission fails!",
            REACH_TIME_LIMIT))
end

-- ── Mission lifecycle ──────────────────────────────────────────────────────────
local function startMission(point)
    if mission then return end

    local playerPos = getPlayerPos()
    if not playerPos then return end

    spawnedVehicles = {}
    playerWrecked   = false
    mission = { point = point, timer = 0, policeSpawned = 0, playerDmgTimer = 0 }

    if     point.type == CHASE  then startChase (point, playerPos)
    elseif point.type == ESCAPE then startEscape(point, playerPos)
    elseif point.type == FOLLOW then startFollow(point, playerPos)
    elseif point.type == ENDURE then startEndure(point, playerPos)
    elseif point.type == REACH  then startReach (point, playerPos)
    end
end

local function cleanupMission(success, failMsg)
    if not mission then return end

    missionCooldowns[mission.point.name] = MISSION_COOLDOWN

    -- Despawn all mission-spawned vehicles.
    -- scenetree.findObjectById is used for deletion; be:deleteObjectByID does not exist.
    for _, vd in ipairs(spawnedVehicles) do
        local vehObj = scenetree.findObjectById(vd.id)
        if vehObj then vehObj:delete() end
    end
    spawnedVehicles  = {}
    destroyedTargets = {}
    playerWrecked    = false

    if success then
        notify("success", "Mission Complete!", "Well done!  '" .. mission.point.name .. "' completed!")
    else
        notify("error", "Mission Failed!", failMsg or ("'" .. mission.point.name .. "' failed."))
    end

    mission = nil
end

-- ── Shared HUD helpers ─────────────────────────────────────────────────────────
-- Returns the distance from the player to the first alive "target" vehicle, or nil.
local function getTargetDist(playerPos)
    if not playerPos then return nil end
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            if v then return playerPos:distance(v:getPosition()) end
        end
    end
    return nil
end

-- Counts how many spawned police objects still exist in the scene.
local function countAlivePolice()
    local n = 0
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" and be:getObjectByID(vd.id) then
            n = n + 1
        end
    end
    return n
end

-- Returns the ImGui type-tag string and colour for a mission type.
local function typeStyle(mtype)
    if mtype == CHASE  then return "C", im.ImVec4(1.0,  0.55, 0.15, 1.0) end
    if mtype == ESCAPE then return "E", im.ImVec4(0.25, 0.55, 1.0,  1.0) end
    if mtype == FOLLOW then return "F", im.ImVec4(0.10, 0.90, 0.55, 1.0) end
    if mtype == ENDURE then return "N", im.ImVec4(0.75, 0.20, 1.0,  1.0) end
    if mtype == REACH  then return "R", im.ImVec4(0.85, 0.85, 1.0,  1.0) end
    return "?", im.ImVec4(1.0, 1.0, 1.0, 1.0)
end

-- ── ImGui HUD panel ────────────────────────────────────────────────────────────
local function drawHUD()
    if not im then return end
    local playerPos = getPlayerPos()
    if not playerPos then return end

    im.SetNextWindowSize(im.ImVec2(HUD_WINDOW_WIDTH, 0), im.Cond_Always)
    im.SetNextWindowPos(im.ImVec2(10, 10), im.Cond_Always)
    im.SetNextWindowBgAlpha(0.82)

    local winFlags = bit.bor(
        im.WindowFlags_NoTitleBar,
        im.WindowFlags_NoResize,
        im.WindowFlags_NoMove,
        im.WindowFlags_NoSavedSettings,
        im.WindowFlags_NoScrollbar
    )

    local drawn = im.Begin("##jonesingHUD", nil, winFlags)
    if drawn then
        im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0), "  MISSIONS")
        im.Separator()

        for _, mp in ipairs(missionPoints) do
            local isActive   = mission and mission.point == mp
            local onCooldown = (missionCooldowns[mp.name] or 0) > 0
            local dist       = playerPos:distance(mp.pos)
            local distStr    = dist < DIST_KM_THRESHOLD
                               and string.format("%d m", math.floor(dist))
                               or  string.format("%.1f km", dist / DIST_KM_THRESHOLD)
            local tag, tc    = typeStyle(mp.type)

            if isActive then
                local mtype = mp.type
                if mtype == CHASE then
                    local tDist = getTargetDist(playerPos)
                    local tStr  = tDist and string.format("%d m", math.floor(tDist)) or "??"
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0), "  >> " .. mp.name)
                    im.TextColored(im.ImVec4(1.0, 0.65, 0.0, 1.0),
                        string.format("       Target: %s / %d m limit", tStr, CHASE_ESCAPE_DISTANCE))

                elseif mtype == ESCAPE then
                    local rem = math.max(0, math.ceil(ESCAPE_TIME_LIMIT - mission.timer))
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0),
                        string.format("  >> %s  [%ds]", mp.name, rem))

                elseif mtype == FOLLOW then
                    local tDist = getTargetDist(playerPos)
                    local tStr  = tDist and string.format("%d m", math.floor(tDist)) or "gone"
                    local prog  = math.floor(math.min(mission.timer, FOLLOW_DURATION))
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0), "  >> " .. mp.name)
                    im.TextColored(im.ImVec4(0.10, 1.0, 0.65, 1.0),
                        string.format("       %s  %d/%ds", tStr, prog, FOLLOW_DURATION))

                elseif mtype == ENDURE then
                    local rem = math.max(0, math.ceil(ENDURE_TIME_LIMIT - mission.timer))
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0),
                        string.format("  >> %s  [%ds left]", mp.name, rem))

                elseif mtype == REACH then
                    local rem   = math.max(0, math.ceil(REACH_TIME_LIMIT - mission.timer))
                    local dDist = mp.destPos and playerPos:distance(mp.destPos)
                    local dStr  = dDist and string.format("%d m", math.floor(dDist)) or "??"
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0), "  >> " .. mp.name)
                    im.TextColored(im.ImVec4(0.85, 0.85, 1.0, 1.0),
                        string.format("       Dest: %s  [%ds]", dStr, rem))
                end

            elseif onCooldown then
                im.TextColored(im.ImVec4(0.45, 0.45, 0.45, 1.0), "  [--] " .. mp.name)
                im.TextColored(im.ImVec4(0.40, 0.40, 0.40, 1.0),
                    string.format("       CD: %ds", math.ceil(missionCooldowns[mp.name])))

            else
                local dx  = mp.pos.x - playerPos.x
                local dy  = mp.pos.y - playerPos.y
                local dir = compassDir(dx, dy)
                im.TextColored(tc, string.format("  [%s] %s", tag, mp.name))
                im.TextColored(im.ImVec4(0.75, 0.75, 0.75, 1.0),
                    string.format("       %s  %s", dir, distStr))
            end
        end

        -- Quit button and debug section (shown only while a mission is active)
        if mission then
            im.Separator()
            im.PushStyleColor2(im.Col_Button,        im.ImVec4(0.55, 0.10, 0.10, 0.85))
            im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.75, 0.15, 0.15, 1.00))
            if im.Button("  [ QUIT MISSION ]  ") then
                cleanupMission(false)
            end
            im.PopStyleColor(2)

            im.Separator()
            im.TextColored(im.ImVec4(0.6, 0.6, 0.6, 1.0), "  -- debug --")
            im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                string.format("  t = %.1f s", mission.timer))

            local mtype = mission.point.type
            if mtype == CHASE then
                local tDist = getTargetDist(playerPos)
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  target: %s / %d m",
                        tDist and string.format("%.0f m", tDist) or "gone",
                        CHASE_ESCAPE_DISTANCE))

            elseif mtype == ESCAPE then
                local alive = countAlivePolice()
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  police: %d alive / %d spawned",
                        alive, mission.policeSpawned or 0))
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  time left: %.0f s",
                        math.max(0, ESCAPE_TIME_LIMIT - mission.timer)))

            elseif mtype == FOLLOW then
                local tDist = getTargetDist(playerPos)
                local oor   = mission.followOutOfRangeSecs or 0
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  target: %s  grace: %.1f/%.1fs",
                        tDist and string.format("%.0f m", tDist) or "gone",
                        oor, FOLLOW_GRACE))
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  progress: %.0f / %d s",
                        mission.timer, FOLLOW_DURATION))

            elseif mtype == ENDURE or mtype == REACH then
                local alive = countAlivePolice()
                local lim   = mtype == ENDURE and ENDURE_TIME_LIMIT or REACH_TIME_LIMIT
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  police: %d alive (recycles)", alive))
                im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                    string.format("  time left: %.0f s", math.max(0, lim - mission.timer)))
                if mtype == REACH and mission.point.destPos then
                    local dDist = playerPos:distance(mission.point.destPos)
                    im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0),
                        string.format("  dest: %.0f m", dDist))
                end
            end
        end
    end
    im.End()
end

-- ── Success conditions ─────────────────────────────────────────────────────────
local function checkChaseSuccess()
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            if v == nil then
                -- Vehicle removed from scene → counts as destroyed
            elseif not destroyedTargets[vd.id] then
                -- Not yet confirmed; ask VE side to check damage this frame
                v:queueLuaCommand(makeDamageCheckCmd(CHASE_DAMAGE_THRESH, vd.id))
                return false
            end
        end
    end
    return true
end

local function checkEscapeSuccess()
    local playerPos = getPlayerPos()
    if not playerPos then return false end
    if not mission or (mission.policeSpawned or 0) == 0 then return false end
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" then
            local v = be:getObjectByID(vd.id)
            if v and playerPos:distance(v:getPosition()) < ESCAPE_MIN_DISTANCE then
                return false
            end
        end
    end
    return true
end

-- Ticks the FOLLOW mission for one frame.
-- Returns "success", "fail:<reason>", or nil to keep going.
local function tickFollow(playerPos, dt)
    if not playerPos then return nil end

    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            -- Check if the VE callback already reported critical damage
            if destroyedTargets[vd.id] then
                return "fail:You damaged the target!"
            end

            local v = be:getObjectByID(vd.id)
            if not v then
                return "fail:The target vehicle was lost!"
            end

            -- Distance range check
            local dist = playerPos:distance(v:getPosition())
            if dist < FOLLOW_MIN_DIST or dist > FOLLOW_MAX_DIST then
                mission.followOutOfRangeSecs = (mission.followOutOfRangeSecs or 0) + dt
                if mission.followOutOfRangeSecs > FOLLOW_GRACE then
                    if dist < FOLLOW_MIN_DIST then
                        return "fail:Too close — you spooked the target!"
                    else
                        return "fail:Lost the target — too far away!"
                    end
                end
            else
                -- Back in range: reset the grace timer
                mission.followOutOfRangeSecs = 0
            end

            -- Periodically re-queue the VE-side damage check (it only fires once per queue)
            mission.followDmgTimer = (mission.followDmgTimer or 0) + dt
            if mission.followDmgTimer >= FOLLOW_DMG_INTERVAL then
                mission.followDmgTimer = 0
                v:queueLuaCommand(makeFollowDamageCheckCmd(FOLLOW_DAMAGE_THRESH, vd.id))
            end
        end
    end

    -- Success: timer reached the required duration AND player is currently in range
    if mission.timer >= FOLLOW_DURATION and (mission.followOutOfRangeSecs or 0) == 0 then
        return "success"
    end
    return nil
end

-- For ENDURE and REACH missions: police that drift beyond ENDURE_RECYCLE_DIST are
-- repaired and teleported far ahead of the player.  All police are spawned once at
-- mission start and recycled in-place thereafter — no new vehicles are ever created.
local function tickTeleportPolice(playerPos, dt)
    if not playerPos then return end
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    -- Rate-limit checks to avoid teleporting every single frame
    mission.recycleTimer = (mission.recycleTimer or 0) + dt
    if mission.recycleTimer < POLICE_TELEPORT_INTERVAL then return end
    mission.recycleTimer = 0

    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" then
            local v = be:getObjectByID(vd.id)
            if v and playerPos:distance(v:getPosition()) > ENDURE_RECYCLE_DIST then
                -- Repair and teleport far ahead of the player so it is waiting
                local angle  = math.random() * 2 * math.pi
                local d      = math.random(POLICE_TELEPORT_RADIUS.min, POLICE_TELEPORT_RADIUS.max)
                local newPos = vec3(
                    playerPos.x + math.cos(angle) * d,
                    playerPos.y + math.sin(angle) * d,
                    playerPos.z
                )
                v:setPosition(newPos)
                -- resetBrokenFlexMesh repairs deformation/damage from the VE side;
                -- resetBroken() does not exist on the GE-side BeamNGVehicle object.
                v:queueLuaCommand(
                    "obj:resetBrokenFlexMesh(); " ..
                    "ai.setMode('chase'); ai.setTargetObjectID(" .. tostring(playerID) .. ")"
                )
            end
        end
    end
end

-- Periodically queues a VE-side damage check on the player's vehicle.
-- If playerWrecked is already set, returns true (caller should fail the mission).
local function tickPlayerDamage(dt)
    if playerWrecked then return true end

    mission.playerDmgTimer = (mission.playerDmgTimer or 0) + dt
    if mission.playerDmgTimer >= PLAYER_DMG_CHECK_INTERVAL then
        mission.playerDmgTimer = 0
        local pv = getPlayerVehicle()
        if pv then
            pv:queueLuaCommand(makePlayerDamageCheckCmd(PLAYER_DAMAGE_THRESH))
        end
    end

    return false
end

-- ── Per-frame update ───────────────────────────────────────────────────────────
local function onUpdate(dt)
    -- ── Deferred initialisation ─────────────────────────────────────────────
    -- Wait for the map navigation graph to become available so that mission
    -- markers can be placed on valid roadways.  After INIT_TIMEOUT seconds,
    -- fall back to hardcoded positions.
    if not initialized then
        initTimer = initTimer + dt
        if tryInitMissions() then
            initialized = true
        elseif initTimer >= INIT_TIMEOUT then
            buildMissionPointsFallback()
            initialized = true
            log("I", "jonesingMissions",
                "Map graph not available — using fallback mission positions.")
        else
            return  -- skip rendering until positions are ready
        end
    end

    pulseTime = pulseTime + dt * PULSE_SPEED

    -- Resolve player position once per frame.  May be nil (spectator mode, etc.).
    local playerPos = getPlayerPos()

    -- Tick post-mission cooldowns
    for name, cd in pairs(missionCooldowns) do
        if cd > 0 then
            missionCooldowns[name] = math.max(0, cd - dt)
        end
    end

    -- ── Draw all mission markers ────────────────────────────────────────────
    for _, mp in ipairs(missionPoints) do
        local isActive   = mission and mission.point == mp
        local onCooldown = (missionCooldowns[mp.name] or 0) > 0

        -- While a mission is running, skip idle markers (no pillar clutter during gameplay)
        if not mission or isActive or onCooldown then
        local pulse      = 0.5 + 0.5 * math.sin(pulseTime)

        local col
        if isActive then
            col = ColorF(1.0, 1.0, 0.0, 0.60 + 0.40 * pulse)
        elseif onCooldown then
            col = ColorF(0.5, 0.5, 0.5, 0.25)
        else
            col = ColorF(mp.color.r, mp.color.g, mp.color.b,
                         mp.color.a * (0.55 + 0.45 * pulse))
        end

        drawBeacon(mp, col)

        -- Floating label above the beacon top
        local labelZ   = mp.pos.z + BEACON_ABOVE + 6
        local labelPos = vec3(mp.pos.x, mp.pos.y, labelZ)
        local label

        if isActive then
            local mtype = mp.type
            if mtype == CHASE then
                local tDist = getTargetDist(playerPos)
                label = string.format("%s  [%s]", mp.name,
                    tDist and string.format("%d m", math.floor(tDist)) or "??")
            elseif mtype == ESCAPE then
                label = string.format("%s  [%ds]", mp.name,
                    math.max(0, math.ceil(ESCAPE_TIME_LIMIT - mission.timer)))
            elseif mtype == FOLLOW then
                label = string.format("%s  [%d/%ds]", mp.name,
                    math.floor(math.min(mission.timer, FOLLOW_DURATION)), FOLLOW_DURATION)
            elseif mtype == ENDURE then
                label = string.format("%s  [%ds left]", mp.name,
                    math.max(0, math.ceil(ENDURE_TIME_LIMIT - mission.timer)))
            elseif mtype == REACH then
                local dDist = mp.destPos and playerPos and playerPos:distance(mp.destPos)
                label = string.format("%s  dest:%s", mp.name,
                    dDist and string.format("%dm", math.floor(dDist)) or "??")
            else
                label = mp.name
            end
        elseif onCooldown then
            label = string.format("%s  (CD: %ds)", mp.name,
                math.ceil(missionCooldowns[mp.name]))
        else
            local typeTags = {
                chase="CHASE", escape="ESCAPE", follow="FOLLOW",
                endure="ENDURE", reach="REACH",
            }
            label = string.format("[%s]  %s", typeTags[mp.type] or "?", mp.name)
        end

        debugDrawer:drawTextAdvanced(labelPos, label,
            ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 140))
        end  -- render this marker
    end  -- for _, mp

    -- ── Draw destination beacon for active REACH mission ────────────────────
    if mission and mission.point.type == REACH and mission.point.destPos then
        local pulse = 0.5 + 0.5 * math.sin(pulseTime * 1.5)
        drawDestBeacon(mission.point.destPos, pulse)

        -- Destination label
        local dp      = mission.point.destPos
        local dLabel  = vec3(dp.x, dp.y, dp.z + DEST_BEACON_ABOVE + 6)
        debugDrawer:drawTextAdvanced(dLabel, "[ DESTINATION ]",
            ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 80, 160))
    end

    -- ── Proximity check — start mission when player enters a marker zone ─────
    if not mission and playerPos then
        for _, mp in ipairs(missionPoints) do
            if (missionCooldowns[mp.name] or 0) <= 0 then
                local dx = playerPos.x - mp.pos.x
                local dy = playerPos.y - mp.pos.y
                if dx * dx + dy * dy <= mp.triggerRadiusSq then
                    startMission(mp)
                    break
                end
            end
        end
    end

    -- ── Tick active mission ─────────────────────────────────────────────────
    if mission then
        mission.timer = mission.timer + dt
        local mtype   = mission.point.type

        if mtype == CHASE then
            local tDist = getTargetDist(playerPos)
            if tDist and tDist > CHASE_ESCAPE_DISTANCE then
                cleanupMission(false, "The target got away!")
                return
            end
            if checkChaseSuccess() then
                cleanupMission(true)
            end

        elseif mtype == ESCAPE then
            -- Player vehicle wrecked → mission fail
            if tickPlayerDamage(dt) then
                cleanupMission(false, "Your vehicle was wrecked by the police!")
                return
            end
            if mission.timer >= ESCAPE_TIME_LIMIT then
                cleanupMission(false, "Time's up — you didn't shake them!")
                return
            end
            if checkEscapeSuccess() then
                cleanupMission(true)
            end

        elseif mtype == FOLLOW then
            local result = tickFollow(playerPos, dt)
            if result == "success" then
                cleanupMission(true)
            elseif result and result:sub(1, 5) == "fail:" then
                cleanupMission(false, result:sub(6))
                return
            end

        elseif mtype == ENDURE then
            -- Player vehicle wrecked → mission fail
            if tickPlayerDamage(dt) then
                cleanupMission(false, "Your vehicle was wrecked — you didn't survive!")
                return
            end
            tickTeleportPolice(playerPos, dt)
            if mission and mission.timer >= ENDURE_TIME_LIMIT then
                cleanupMission(true)
            end

        elseif mtype == REACH then
            -- Player vehicle wrecked → mission fail
            if tickPlayerDamage(dt) then
                cleanupMission(false, "Your vehicle was destroyed before reaching the destination!")
                return
            end
            tickTeleportPolice(playerPos, dt)
            -- tickTeleportPolice does not call cleanupMission; mission is always valid here
            if mission.timer >= REACH_TIME_LIMIT then
                cleanupMission(false, "Time's up — didn't reach the destination!")
                return
            end
            -- 2D proximity check to destination (same style as trigger zones)
            if playerPos and mission.point.destPos then
                local dx = playerPos.x - mission.point.destPos.x
                local dy = playerPos.y - mission.point.destPos.y
                if dx * dx + dy * dy <= REACH_RADIUS * REACH_RADIUS then
                    cleanupMission(true)
                end
            end
        end
    end

    -- Draw ImGui HUD (minimap-style compass panel)
    drawHUD()
end

-- ── Extension hooks ────────────────────────────────────────────────────────────
local function onExtensionLoaded()
    log("I", "jonesingMissions",
        "Jonesing GTA-like Mission System loaded — " .. #missionTemplates .. " mission templates registered.")
end

local function onExtensionUnloaded()
    cleanupMission(false)
    log("I", "jonesingMissions", "Jonesing Mission System unloaded.")
end

M.onUpdate            = onUpdate
M.onExtensionLoaded   = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

-- Called from VE-side via obj:sendGameEngineLua when a CHASE target is destroyed.
function M.reportTargetDamaged(vid)
    destroyedTargets[vid] = true
end

-- Called from VE-side when a FOLLOW target exceeds the damage threshold.
function M.reportFollowTargetDamaged(vid)
    destroyedTargets[vid] = true
end

-- Called from VE-side when the player's vehicle exceeds the damage threshold
-- during ESCAPE, ENDURE, or REACH missions.
function M.reportPlayerWrecked()
    playerWrecked = true
end

return M
