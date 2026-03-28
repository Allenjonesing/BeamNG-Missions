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
--   ENDURE – police recycle endlessly; survive the full time limit.
--   REACH  – escape recycling police and drive to a destination column of light.
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

-- ── Mission points ─────────────────────────────────────────────────────────────
-- Coordinates target the West Coast USA map.  Adjust pos/z to place markers at
-- interesting spots on whichever map you are playing.
-- color = { r, g, b, a } drawn in idle state.
local missionPoints = {
    -- ── Existing missions ─────────────────────────────────────────────────────
    {
        name          = "Downtown Chase",
        type          = CHASE,
        pos           = vec3(  100,  200, 25),
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.70 },
    },
    {
        name          = "Police Gauntlet",
        type          = ESCAPE,
        pos           = vec3( -300,  100, 20),
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.70 },
    },
    {
        name          = "Highway Pursuit",
        type          = CHASE,
        pos           = vec3(  500, -200, 30),
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.70 },
    },
    {
        name          = "Police Ambush",
        type          = ESCAPE,
        pos           = vec3( -100,  500, 22),
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.70 },
    },
    {
        name          = "Industrial Pursuit",
        type          = CHASE,
        pos           = vec3(  300,  350, 28),
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.70 },
    },
    -- ── New missions ──────────────────────────────────────────────────────────
    {
        -- FOLLOW: stay 15–60 m behind the yellow car for 60 s without hitting it
        name          = "Surveillance",
        type          = FOLLOW,
        pos           = vec3(  200, -100, 25),
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.85, b = 0.60, a = 0.70 },
    },
    {
        -- ENDURE: recycling police never stop coming — survive 60 s
        name          = "Gauntlet Run",
        type          = ENDURE,
        pos           = vec3( -200,  350, 22),
        triggerRadius = 12,
        color         = { r = 0.70, g = 0.10, b = 0.90, a = 0.70 },
    },
    {
        -- REACH: escape recycling police and reach the white destination beacon
        name          = "Breakout",
        type          = REACH,
        pos           = vec3(  400,  100, 28),
        destPos       = vec3( -400, -300, 25),
        triggerRadius = 12,
        color         = { r = 0.85, g = 0.90, b = 1.00, a = 0.70 },
    },
}

-- ── Tuning constants ───────────────────────────────────────────────────────────
local PULSE_SPEED           = 1.5    -- marker pulse rate (radians / second)
local ESCAPE_TIME_LIMIT     = 120    -- seconds before ESCAPE mission fails
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
local FOLLOW_DURATION       = 60     -- seconds of sustained in-range following = success
local FOLLOW_DAMAGE_THRESH  = 0.30   -- damage to followed vehicle that triggers failure
local FOLLOW_DMG_INTERVAL   = 1.0    -- seconds between VE-side damage re-checks

-- ENDURE mission tuning
local ENDURE_TIME_LIMIT     = 60     -- seconds to survive recycling police = success
local ENDURE_RECYCLE_DIST   = 300    -- police beyond this from the player are replaced
local ENDURE_RECYCLE_DELAY  = 5.0    -- minimum seconds between recycling spawns

-- REACH mission tuning
local REACH_TIME_LIMIT      = 120    -- seconds to reach destination before failing
local REACH_RADIUS          = 20     -- metres: arriving within this of destPos = success

-- Beacon visual constants — compact pillars, clearly visible without overwhelming
local BEACON_BELOW        = 40     -- metres below marker Z — pierces shallow terrain
local BEACON_ABOVE        = 80     -- metres above marker Z — visible from ~500 m
local BEACON_STEPS        = 12     -- sphere slices in the vertical pillar
local BEACON_PILLAR_R     = 2.5    -- radius of pillar spheres (m)
local BEACON_RING_SEGS    = 12     -- segments in the ground-level trigger ring

-- Destination beacon (REACH mission) — brighter and distinct from mission markers
local DEST_BEACON_BELOW   = 40
local DEST_BEACON_ABOVE   = 80
local DEST_BEACON_STEPS   = 12
local DEST_BEACON_R       = 3.0
local DEST_BEACON_RING    = 12

-- HUD constants
local HUD_WINDOW_WIDTH    = 275
local DIST_KM_THRESHOLD   = 1000   -- metres; above this shown in km

-- ── State ──────────────────────────────────────────────────────────────────────
local pulseTime         = 0
local mission           = nil   -- active mission table, or nil when idle
local spawnedVehicles   = {}    -- { id = <vehicleID>, role = "target"|"police" }
local missionCooldowns  = {}    -- mp.name -> seconds remaining on cooldown
local destroyedTargets  = {}    -- [vehicleID] = true when VE reports damage >= threshold

-- Pre-compute per-marker values that are constant between frames
for _, mp in ipairs(missionPoints) do
    mp.triggerRadiusSq        = mp.triggerRadius * mp.triggerRadius
    missionCooldowns[mp.name] = 0
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

    -- Vertical pillar (tapers slightly toward the top)
    for s = 0, BEACON_STEPS do
        local t = s / BEACON_STEPS
        local z = botZ + t * (topZ - botZ)
        local r = BEACON_PILLAR_R * (1.0 - t * 0.45)
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

    -- Full vertical pillar (same style as mission markers — bottom to top)
    for s = 0, DEST_BEACON_STEPS do
        local t = s / DEST_BEACON_STEPS
        local z = botZ + t * (topZ - botZ)
        local r = DEST_BEACON_R * (1.0 - t * 0.45)
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
            string.format("%s is fleeing — destroy it before it gets %d m away!", CHASE_TARGET_MODEL, CHASE_ESCAPE_DISTANCE))
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
        string.format("WANTED!  %d police unit%s pursuing you!  Escape them all!", spawned, spawned ~= 1 and "s" or ""))
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
            string.format("Follow the yellow car!  Stay %d–%d m away for %d s without hitting it.",
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
        string.format("ENDURE!  Police never stop coming.  Survive %d seconds!", ENDURE_TIME_LIMIT))
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
        string.format("Reach the destination!  Police recycle endlessly.  You have %d seconds.", REACH_TIME_LIMIT))
end

-- ── Mission lifecycle ──────────────────────────────────────────────────────────
local function startMission(point)
    if mission then return end

    local playerPos = getPlayerPos()
    if not playerPos then return end

    spawnedVehicles = {}
    mission = { point = point, timer = 0, policeSpawned = 0 }

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

-- Removes police that are too far or gone from spawnedVehicles, then spawns
-- replacements (rate-limited) to keep the pressure on.
-- Used by both ENDURE and REACH missions.
local function tickRecyclePolice(playerPos, dt)
    if not playerPos then return end
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    -- Cull police that are too far away or no longer in the scene
    local survivors = {}
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role ~= "police" then
            table.insert(survivors, vd)
        else
            local v = be:getObjectByID(vd.id)
            if v and playerPos:distance(v:getPosition()) < ENDURE_RECYCLE_DIST then
                table.insert(survivors, vd)
            else
                -- Delete the vehicle object so it doesn't linger
                local obj = scenetree.findObjectById(vd.id)
                if obj then obj:delete() end
            end
        end
    end
    spawnedVehicles = survivors

    -- Count alive police in the current list
    local aliveCount = 0
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" then aliveCount = aliveCount + 1 end
    end

    -- Spawn replacements when below quota, subject to the rate limit
    mission.recycleTimer = (mission.recycleTimer or 0) + dt
    if aliveCount < POLICE_COUNT and mission.recycleTimer >= ENDURE_RECYCLE_DELAY then
        mission.recycleTimer = 0
        local needed     = POLICE_COUNT - aliveCount
        local newSpawned = 0
        for i = 1, needed do
            local pVeh = spawnPoliceVehicle(playerPos, playerID)
            if pVeh then
                mission.policeSpawned = (mission.policeSpawned or 0) + 1
                table.insert(spawnedVehicles, { id = pVeh:getID(), role = "police" })
                newSpawned = newSpawned + 1
            end
        end
        if newSpawned > 0 then
            be:enterVehicle(0, playerVeh)  -- reassert camera on the player vehicle
            notify("warning", "Reinforcements!",
                string.format("%d more unit%s dispatched!", newSpawned, newSpawned > 1 and "s" or ""))
        end
    end
end

-- ── Per-frame update ───────────────────────────────────────────────────────────
local function onUpdate(dt)
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
            tickRecyclePolice(playerPos, dt)
            if mission and mission.timer >= ENDURE_TIME_LIMIT then
                cleanupMission(true)
            end

        elseif mtype == REACH then
            tickRecyclePolice(playerPos, dt)
            -- tickRecyclePolice does not call cleanupMission; mission is always valid here
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
        "Jonesing GTA-like Mission System loaded — " .. #missionPoints .. " mission points active.")
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

return M
