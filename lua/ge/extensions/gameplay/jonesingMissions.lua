-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- Jonesing GTA-like Mission System
--
-- Draws GTA-style glowing beacon columns at key map locations.  When the player
-- drives into a marker a mission begins:
--
--   CHASE  – a target vehicle spawns and flees; player must catch and destroy it.
--   ESCAPE – 10 police cars spawn around the player; player must outrun them all.
--
-- An ImGui HUD panel (top-left) shows every mission with a compass direction and
-- distance so the player can navigate to them from anywhere on the map.

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
}

-- ── Tuning constants ───────────────────────────────────────────────────────────
local PULSE_SPEED           = 1.5    -- marker pulse rate (radians / second)
local ESCAPE_TIME_LIMIT     = 120    -- seconds before ESCAPE mission fails
local MISSION_COOLDOWN      = 10     -- seconds before the same marker can re-trigger
local ESCAPE_MIN_DISTANCE   = 250    -- metres: all police beyond this = escaped
local CHASE_DAMAGE_THRESH   = 0.75   -- getDamage() value that counts as "destroyed"
local CHASE_ESCAPE_DISTANCE = 300    -- metres: target beyond this = got away (CHASE fail)
local CHASE_SPAWN_OFFSET    = 80     -- metres ahead of player to spawn the target
local POLICE_SPAWN_RADIUS   = { min = 40, max = 60 }  -- ring around player
local POLICE_COUNT          = 3      -- kept small for performance

-- Beacon visual constants
-- The beacon is a sky-high vertical column extending deep below and far above the
-- marker Z so it punches through the deepest valley terrain and is visible from
-- anywhere on the map.  The trigger uses a flat 2D (X,Y) check so altitude
-- difference between the player and the marker never prevents a mission starting.
local BEACON_BELOW        = 500    -- metres below the defined marker Z — pierces any terrain depth
local BEACON_ABOVE        = 2000   -- metres above the defined marker Z — visible from across the map
local BEACON_STEPS        = 20     -- number of sphere slices in the vertical pillar (denser = more solid)
local BEACON_PILLAR_R     = 5.0    -- radius of the pillar spheres (wider for long-range visibility)
local BEACON_RING_SEGS    = 16     -- segments in the ground-level trigger ring

-- HUD constants
local HUD_WINDOW_WIDTH    = 255    -- width of the ImGui compass panel (pixels)
local DIST_KM_THRESHOLD   = 1000   -- metres; distances above this are shown in km

-- ── State ──────────────────────────────────────────────────────────────────────
local pulseTime         = 0
local mission           = nil   -- active mission table, or nil when idle
local spawnedVehicles   = {}    -- list of { id = <vehicleID>, role = "target"|"police" }
local missionCooldowns  = {}    -- mp.name -> seconds remaining on cooldown
local destroyedTargets  = {}    -- [vehicleID] = true when VE reports damage >= threshold

-- Pre-compute per-marker values that are constant between frames
for _, mp in ipairs(missionPoints) do
    mp.triggerRadiusSq          = mp.triggerRadius * mp.triggerRadius
    missionCooldowns[mp.name]   = 0
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
-- Forward declaration: cleanupMission is defined later but referenced by drawHUD
-- (the quit button) which must be declared first.
local cleanupMission

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

-- Returns an 8-point compass abbreviation for a world-space (dx, dy) vector.
-- Axis convention: +X = East, +Y = North (standard BeamNG world coordinates).
local function compassDir(dx, dy)
    local angle = math.atan2(dy, dx) * (180 / math.pi)
    if angle < 0 then angle = angle + 360 end
    local dirs = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
    local idx   = (math.floor((angle + 22.5) / 45) % 8) + 1
    return dirs[idx]
end

-- ── Beacon rendering ───────────────────────────────────────────────────────────
-- Draws a GTA-style vertical beacon column.  The column extends BEACON_BELOW m
-- below and BEACON_ABOVE m above the marker's defined Z coordinate, so it is
-- always visible from ground-level cameras and does not fully hide in terrain
-- on the overhead map.
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
        debugDrawer:drawSphere(vec3(rx, ry, cz), 1.2, col)
    end

    -- Vertical pillar of spheres from bottom to top (tapers slightly toward cap)
    for s = 0, BEACON_STEPS do
        local t = s / BEACON_STEPS
        local z = botZ + t * (topZ - botZ)
        local r = BEACON_PILLAR_R * (1.0 - t * 0.45)
        debugDrawer:drawSphere(vec3(cx, cy, z), r, col)
    end

    -- Large cap sphere at the very top — clearly visible from far away
    debugDrawer:drawSphere(vec3(cx, cy, topZ), mp.triggerRadius * 0.45, col)
end

-- ── ImGui HUD panel ────────────────────────────────────────────────────────────
-- Draws a compact compass panel in the top-left corner showing every mission
-- point with its type, name, compass direction and distance.  This acts as the
-- minimap / navigation guide so the player can find missions while driving.

-- Returns the distance (metres) from the player to the first alive CHASE target,
-- or nil if there is none (not a CHASE mission, or target already destroyed/gone).
local function getChaseTargetDist(playerPos)
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            if v then
                return playerPos:distance(v:getPosition())
            end
        end
    end
    return nil
end

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
                               and (math.floor(dist) .. " m")
                               or  string.format("%.1f km", dist / DIST_KM_THRESHOLD)

            if isActive then
                if mp.type == CHASE then
                    -- Show distance to the fleeing target instead of a countdown
                    local tDist = getChaseTargetDist(playerPos)
                    local tStr  = tDist and (math.floor(tDist) .. " m") or "??"
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0),
                        "  >> " .. mp.name)
                    im.TextColored(im.ImVec4(1.0, 0.65, 0.0, 1.0),
                        "       Target: " .. tStr .. " / " .. CHASE_ESCAPE_DISTANCE .. " m limit")
                else
                    -- ESCAPE: show countdown timer
                    local rem = math.max(0, math.ceil(ESCAPE_TIME_LIMIT - mission.timer))
                    im.TextColored(im.ImVec4(1.0, 1.0, 0.0, 1.0),
                        "  >> " .. mp.name .. "  [" .. rem .. "s]")
                end

            elseif onCooldown then
                im.TextColored(im.ImVec4(0.45, 0.45, 0.45, 1.0),
                    "  [--] " .. mp.name)
                im.TextColored(im.ImVec4(0.40, 0.40, 0.40, 1.0),
                    "       CD: " .. math.ceil(missionCooldowns[mp.name]) .. "s")

            else
                local typeTag = mp.type == CHASE and "C" or "E"
                local dx      = mp.pos.x - playerPos.x
                local dy      = mp.pos.y - playerPos.y
                local dir     = compassDir(dx, dy)
                local tc      = mp.type == CHASE
                                and im.ImVec4(1.0, 0.55, 0.15, 1.0)
                                or  im.ImVec4(0.25, 0.55, 1.0,  1.0)

                im.TextColored(tc, "  [" .. typeTag .. "] " .. mp.name)
                im.TextColored(im.ImVec4(0.75, 0.75, 0.75, 1.0),
                    "       " .. dir .. "  " .. distStr)
            end
        end

        -- Quit button — only shown while a mission is active
        if mission then
            im.Separator()
            im.PushStyleColor2(im.Col_Button,        im.ImVec4(0.55, 0.10, 0.10, 0.85))
            im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.75, 0.15, 0.15, 1.00))
            if im.Button("  [ QUIT MISSION ]  ") then
                cleanupMission(false)
            end
            im.PopStyleColor(2)
        end
    end
    im.End()
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

    -- core_vehicles.spawnNewVehicle returns the vehicle object (userdata), not a number.
    -- Extract the numeric ID via :getID() and use the object directly.
    local targetVeh = core_vehicles.spawnNewVehicle("etk800", {
        pos    = spawnPos,
        rot    = quat(0, 0, 0, 1),
        config = "vehicles/etk800/etk800.pc",
        color  = "0.1 0.3 0.9 1",
    })

    if targetVeh then
        local targetID = targetVeh:getID()
        table.insert(spawnedVehicles, { id = targetID, role = "target" })
        -- Tell the target vehicle's AI to flee from the player (VE context)
        targetVeh:queueLuaCommand(
            "ai.setMode('flee'); " ..
            "ai.setTargetObjectID(" .. tostring(playerID) .. ")"
        )
        -- Queue a VE-side periodic damage monitor.  When damage >= threshold it
        -- calls back to GE via sendGameEngineLua so we never touch getDamage() from
        -- the GE side (it does not exist there).
        targetVeh:queueLuaCommand(string.format([[
            local function _jmDmgCheck()
                if obj:getDamage() >= %f then
                    obj:sendGameEngineLua("extensions.gameplay_jonesingMissions.reportTargetDamaged(%d)")
                end
            end
            _jmDmgCheck()
        ]], CHASE_DAMAGE_THRESH, targetID))
        -- Re-enter the player vehicle so the camera does not follow the spawned AI
        be:enterVehicle(0, playerVeh)
    end

    notify("info",
        "MISSION: " .. point.name,
        "Catch and DESTROY the fleeing vehicle!  Don't let it escape past " .. CHASE_ESCAPE_DISTANCE .. " m!"
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

        -- core_vehicles.spawnNewVehicle returns the vehicle object (userdata), not a number.
        -- Use etk800 (confirmed available); sunburst police.pc config does not ship in
        -- the base game and causes a crash.  White/grey colouring differentiates them
        -- visually from the blue CHASE target.
        local policeVeh = core_vehicles.spawnNewVehicle("etk800", {
            pos   = spawnPos,
            rot   = quat(0, 0, 0, 1),
            color = "0.85 0.85 0.85 1",
        })

        if policeVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            table.insert(spawnedVehicles, { id = policeVeh:getID(), role = "police" })
            -- Tell the police AI to chase the player (VE context)
            policeVeh:queueLuaCommand(
                "ai.setMode('chase'); " ..
                "ai.setTargetObjectID(" .. tostring(playerID) .. ")"
            )
        end
    end

    -- Re-enter the player vehicle after all police spawn so the camera stays on the player
    be:enterVehicle(0, playerVeh)

    notify("warning",
        "MISSION: " .. point.name,
        "WANTED!  Escape from ALL " .. POLICE_COUNT .. " police vehicles!  You have " .. ESCAPE_TIME_LIMIT .. "s."
    )
end

-- ── Mission lifecycle ──────────────────────────────────────────────────────────
local function startMission(point)
    if mission then return end  -- already in a mission

    local playerPos = getPlayerPos()
    if not playerPos then return end

    spawnedVehicles = {}
    mission = { point = point, timer = 0, policeSpawned = 0 }

    if point.type == CHASE then
        startChase(point, playerPos)
    elseif point.type == ESCAPE then
        startEscape(point, playerPos)
    end
end

cleanupMission = function(success, failMsg)
    if not mission then return end

    -- Start a cooldown so the player does not re-trigger by staying in the zone
    missionCooldowns[mission.point.name] = MISSION_COOLDOWN

    -- Despawn all mission-spawned vehicles
    for _, vd in ipairs(spawnedVehicles) do
        if be:getObjectByID(vd.id) then
            be:deleteObjectByID(vd.id)
        end
    end
    spawnedVehicles   = {}
    destroyedTargets  = {}

    if success then
        notify("success", "Mission Complete!", "Well done!  '" .. mission.point.name .. "' completed!")
    else
        notify("error", "Mission Failed!", failMsg or ("'" .. mission.point.name .. "' failed."))
    end

    mission = nil
end

-- ── Success conditions ─────────────────────────────────────────────────────────
local function checkChaseSuccess()
    -- Returns true when every spawned target has been confirmed destroyed.
    -- Damage is read on the VE side (where getDamage() exists) via queueLuaCommand;
    -- reportTargetDamaged() is called back from VE into GE when the threshold is met.
    -- If the object is gone entirely (fell off the map) we also count it as destroyed.
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            if v == nil then
                -- Vehicle removed from the scene → counts as destroyed
            elseif not destroyedTargets[vd.id] then
                -- Not yet confirmed; ask VE side to check damage this frame
                v:queueLuaCommand(string.format(
                    "if obj:getDamage()>=%f then" ..
                    " obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportTargetDamaged(%d)')" ..
                    " end",
                    CHASE_DAMAGE_THRESH, vd.id
                ))
                return false  -- still alive
            end
        end
    end
    return true
end

local function checkEscapeSuccess()
    local playerPos = getPlayerPos()
    if not playerPos then return false end

    -- Guard: if no police actually spawned (e.g. model load error), don't grant
    -- instant success — abort the mission instead.
    if not mission or (mission.policeSpawned or 0) == 0 then
        return false
    end

    -- Returns true when every surviving police vehicle is beyond the escape distance.
    -- Police that have been destroyed / removed from the scene are ignored.
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

    -- Tick post-mission cooldowns
    for name, cd in pairs(missionCooldowns) do
        if cd > 0 then
            missionCooldowns[name] = math.max(0, cd - dt)
        end
    end

    -- Draw all mission markers as tall GTA-style beacon columns
    for _, mp in ipairs(missionPoints) do
        local isActive   = mission and mission.point == mp
        local onCooldown = (missionCooldowns[mp.name] or 0) > 0
        local pulse      = 0.5 + 0.5 * math.sin(pulseTime)

        local col
        if isActive then
            -- Active beacon: yellow, bright and fully pulsing
            col = ColorF(1.0, 1.0, 0.0, 0.60 + 0.40 * pulse)
        elseif onCooldown then
            -- Cooling down: muted grey
            col = ColorF(0.5, 0.5, 0.5, 0.25)
        else
            -- Idle: type colour with gentle pulse
            col = ColorF(
                mp.color.r,
                mp.color.g,
                mp.color.b,
                mp.color.a * (0.55 + 0.45 * pulse)
            )
        end

        drawBeacon(mp, col)

        -- Floating label above the top of the beacon column.
        -- Positioned well above terrain so the background box never obscures
        -- ground-level geometry.  depthTest=false keeps it on top of everything.
        local labelZ   = mp.pos.z + BEACON_ABOVE + 8
        local labelPos = vec3(mp.pos.x, mp.pos.y, labelZ)
        local label
        if isActive then
            if mp.type == CHASE then
                local tDist = getChaseTargetDist(playerPos)
                label = mp.name .. "  [" .. (tDist and (math.floor(tDist) .. " m") or "??") .. "]"
            else
                label = mp.name .. "  [" .. math.max(0, math.ceil(ESCAPE_TIME_LIMIT - mission.timer)) .. "s]"
            end
        elseif onCooldown then
            label = mp.name .. "  (CD: " .. math.ceil(missionCooldowns[mp.name]) .. "s)"
        else
            local typeTag = mp.type == CHASE and "CHASE" or "ESCAPE"
            label = "[" .. typeTag .. "]  " .. mp.name
        end
        -- Plain Lua string (no String() wrapper); semi-transparent background
        debugDrawer:drawTextAdvanced(labelPos, label, ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 140))
    end

    -- Proximity check: start a mission when the player drives into a marker.
    -- Uses a flat 2D (X,Y) distance so height difference never prevents triggering
    -- ("infinite height" hitbox — the beacon column stretches from deep underground
    -- to 2000 m in the sky, so the trigger zone matches its visual footprint).
    -- (skipped if the marker is on cooldown or another mission is active)
    if not mission then
        local playerPos = getPlayerPos()
        if playerPos then
            for _, mp in ipairs(missionPoints) do
                local onCooldown = (missionCooldowns[mp.name] or 0) > 0
                if not onCooldown then
                    local dx = playerPos.x - mp.pos.x
                    local dy = playerPos.y - mp.pos.y
                    if dx * dx + dy * dy <= mp.triggerRadiusSq then
                        startMission(mp)
                        break
                    end
                end
            end
        end
    end

    -- Tick the active mission
    if mission then
        mission.timer = mission.timer + dt

        if mission.point.type == CHASE then
            -- CHASE: fail when the target gets too far away; no time limit
            local chasePlayerPos = getPlayerPos()
            if chasePlayerPos then
                local tDist = getChaseTargetDist(chasePlayerPos)
                if tDist and tDist > CHASE_ESCAPE_DISTANCE then
                    cleanupMission(false, "The target got away!")
                    return
                end
            end
            if checkChaseSuccess() then
                cleanupMission(true)
            end

        elseif mission.point.type == ESCAPE then
            -- ESCAPE: fail when the time limit expires
            if mission.timer >= ESCAPE_TIME_LIMIT then
                cleanupMission(false)
                return
            end
            if checkEscapeSuccess() then
                cleanupMission(true)
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

-- Called from VE-side via obj:sendGameEngineLua when a target's damage reaches the
-- destruction threshold.  Sets a flag that checkChaseSuccess reads each frame.
function M.reportTargetDamaged(vid)
    destroyedTargets[vid] = true
end

return M
