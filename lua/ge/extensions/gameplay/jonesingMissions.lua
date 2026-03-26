-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- Jonesing GTA-like Mission System
--
-- Draws glowing mission-start markers at key map locations.  When the player
-- drives into a marker a mission begins:
--
--   CHASE  – a target vehicle spawns and flees; player must catch and destroy it.
--   ESCAPE – 10 police cars spawn around the player; player must outrun them all.

local M = {}

-- ── Mission types ──────────────────────────────────────────────────────────────
local CHASE  = "chase"
local ESCAPE = "escape"

-- ── Mission points ─────────────────────────────────────────────────────────────
-- Coordinates target the West Coast USA map.  Adjust pos/z to place markers at
-- interesting spots on whichever map you are playing.
-- color = { r, g, b, a } drawn in idle state.
local missionPoints = {
    {
        name          = "Downtown Chase",
        type          = CHASE,
        pos           = vec3(  100,  200, 25),
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.55 },
    },
    {
        name          = "Police Gauntlet",
        type          = ESCAPE,
        pos           = vec3( -300,  100, 20),
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.55 },
    },
    {
        name          = "Highway Pursuit",
        type          = CHASE,
        pos           = vec3(  500, -200, 30),
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.55 },
    },
    {
        name          = "Police Ambush",
        type          = ESCAPE,
        pos           = vec3( -100,  500, 22),
        triggerRadius = 12,
        color         = { r = 0.10, g = 0.40, b = 1.0, a = 0.55 },
    },
    {
        name          = "Industrial Pursuit",
        type          = CHASE,
        pos           = vec3(  300,  350, 28),
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.30, b = 0.10, a = 0.55 },
    },
}

-- ── Tuning constants ───────────────────────────────────────────────────────────
local PULSE_SPEED         = 1.5    -- marker pulse rate (radians / second)
local MISSION_TIME_LIMIT  = 120    -- seconds before failure
local ESCAPE_MIN_DISTANCE = 250    -- metres: all police beyond this = escaped
local CHASE_DAMAGE_THRESH = 0.75   -- getDamage() value that counts as "destroyed"
local CHASE_SPAWN_OFFSET  = 80     -- metres ahead of player to spawn the target
local POLICE_SPAWN_RADIUS = { min = 55, max = 80 }  -- ring around player
local POLICE_COUNT        = 10

-- ── State ──────────────────────────────────────────────────────────────────────
local pulseTime       = 0
local mission         = nil   -- active mission table, or nil when idle
local spawnedVehicles = {}    -- list of { id = <vehicleID>, role = "target"|"police" }

-- Pre-compute squared trigger radii so onUpdate avoids per-frame multiplications
for _, mp in ipairs(missionPoints) do
    mp.triggerRadiusSq = mp.triggerRadius * mp.triggerRadius
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

-- ── Mission start helpers ──────────────────────────────────────────────────────
local function startChase(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end  -- guard against invalid player ID

    -- Spawn the fleeing vehicle at the player's elevation to avoid going underground
    local offset   = vec3(math.random(-40, 40), CHASE_SPAWN_OFFSET, 0)
    local spawnPos = vec3(playerPos.x + offset.x, playerPos.y + offset.y, playerPos.z)

    local id = core_vehicles.spawnNewVehicle("etk800", {
        pos    = spawnPos,
        rot    = quat(0, 0, 0, 1),
        config = "vehicles/etk800/etk800.pc",
        color  = "0.1 0.3 0.9 1",
    })

    if id then
        table.insert(spawnedVehicles, { id = id, role = "target" })
        local targetVeh = be:getObjectByID(id)
        if targetVeh then
            -- Tell the target vehicle's AI to flee from the player (VE context)
            targetVeh:queueLuaCommand(
                "ai.setMode('flee'); " ..
                "ai.setTargetObjectID(" .. tostring(playerID) .. ")"
            )
        end
    end

    notify("info",
        "MISSION: " .. point.name,
        "Catch and DESTROY the fleeing vehicle!  You have " .. MISSION_TIME_LIMIT .. "s."
    )
end

local function startEscape(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end  -- guard against invalid player ID

    for i = 1, POLICE_COUNT do
        local angle    = (i / POLICE_COUNT) * 2 * math.pi
        local dist     = POLICE_SPAWN_RADIUS.min + math.random(0, POLICE_SPAWN_RADIUS.max - POLICE_SPAWN_RADIUS.min)
        -- Spawn at the player's elevation to avoid going underground
        local spawnPos = vec3(
            playerPos.x + math.cos(angle) * dist,
            playerPos.y + math.sin(angle) * dist,
            playerPos.z
        )

        local id = core_vehicles.spawnNewVehicle("sunburst", {
            pos    = spawnPos,
            rot    = quat(0, 0, 0, 1),
            config = "vehicles/sunburst/police.pc",
            color  = "1 1 1 1",
        })

        if id then
            table.insert(spawnedVehicles, { id = id, role = "police" })
            local policeVeh = be:getObjectByID(id)
            if policeVeh then
                -- Tell the police AI to chase the player (VE context)
                policeVeh:queueLuaCommand(
                    "ai.setMode('chase'); " ..
                    "ai.setTargetObjectID(" .. tostring(playerID) .. ")"
                )
            end
        end
    end

    notify("warning",
        "MISSION: " .. point.name,
        "WANTED!  Escape from ALL " .. POLICE_COUNT .. " police vehicles!  You have " .. MISSION_TIME_LIMIT .. "s."
    )
end

-- ── Mission lifecycle ──────────────────────────────────────────────────────────
local function startMission(point)
    if mission then return end  -- already in a mission

    local playerPos = getPlayerPos()
    if not playerPos then return end

    spawnedVehicles = {}
    mission = { point = point, timer = 0 }

    if point.type == CHASE then
        startChase(point, playerPos)
    elseif point.type == ESCAPE then
        startEscape(point, playerPos)
    end
end

local function cleanupMission(success)
    if not mission then return end

    -- Despawn all mission-spawned vehicles
    for _, vd in ipairs(spawnedVehicles) do
        if be:getObjectByID(vd.id) then
            be:deleteObjectByID(vd.id)
        end
    end
    spawnedVehicles = {}

    if success then
        notify("success", "Mission Complete!", "Well done!  '" .. mission.point.name .. "' completed!")
    else
        notify("error",   "Mission Failed!",   "'" .. mission.point.name .. "' failed.")
    end

    mission = nil
end

-- ── Success conditions ─────────────────────────────────────────────────────────
local function checkChaseSuccess()
    -- Returns true when every spawned target vehicle is destroyed or gone
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            -- If the object is gone (fell off map, etc.) count it as destroyed
            if v and v:getDamage() < CHASE_DAMAGE_THRESH then
                return false  -- target still alive
            end
        end
    end
    return true
end

local function checkEscapeSuccess()
    local playerPos = getPlayerPos()
    if not playerPos then return false end

    -- Returns true when every police vehicle is beyond the escape distance.
    -- A police vehicle that has been destroyed / gone from the scene is ignored.
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" then
            local v = be:getObjectByID(vd.id)
            if v and playerPos:distance(v:getPosition()) < ESCAPE_MIN_DISTANCE then
                return false  -- police still too close
            end
        end
    end
    return true
end

-- ── Per-frame update ───────────────────────────────────────────────────────────
local function onUpdate(dt)
    pulseTime = pulseTime + dt * PULSE_SPEED

    -- Draw all mission markers
    for _, mp in ipairs(missionPoints) do
        local isActive = mission and mission.point == mp
        local pulse    = 0.5 + 0.5 * math.sin(pulseTime)

        local radius, col
        if isActive then
            -- Active marker: yellow, larger and more opaque, pulsing
            radius = mp.triggerRadius * (1.0 + 0.25 * pulse)
            col    = ColorF(1.0, 1.0, 0.0, 0.65 + 0.35 * pulse)
        else
            -- Idle marker: type-coloured with gentle pulse
            radius = mp.triggerRadius
            col    = ColorF(
                mp.color.r,
                mp.color.g,
                mp.color.b,
                mp.color.a * (0.6 + 0.4 * pulse)
            )
        end

        debugDrawer:drawSphere(mp.pos, radius, col)

        -- Label floating above the sphere
        local labelPos = vec3(mp.pos.x, mp.pos.y, mp.pos.z + radius + 3)
        local label
        if isActive then
            label = mp.name .. "  [" .. math.max(0, math.ceil(MISSION_TIME_LIMIT - mission.timer)) .. "s]"
        else
            local typeTag = mp.type == CHASE and "CHASE" or "ESCAPE"
            label = "[" .. typeTag .. "]  " .. mp.name
        end
        debugDrawer:drawTextAdvanced(labelPos, String(label), ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 192))
    end

    -- Proximity check: start a mission when the player drives into a marker
    if not mission then
        local playerPos = getPlayerPos()
        if playerPos then
            for _, mp in ipairs(missionPoints) do
                if playerPos:squaredDistance(mp.pos) <= mp.triggerRadiusSq then
                    startMission(mp)
                    break
                end
            end
        end
    end

    -- Tick the active mission
    if mission then
        mission.timer = mission.timer + dt

        if mission.timer >= MISSION_TIME_LIMIT then
            cleanupMission(false)
            return
        end

        local success = false
        if mission.point.type == CHASE then
            success = checkChaseSuccess()
        elseif mission.point.type == ESCAPE then
            success = checkEscapeSuccess()
        end

        if success then
            cleanupMission(true)
        end
    end
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

return M
