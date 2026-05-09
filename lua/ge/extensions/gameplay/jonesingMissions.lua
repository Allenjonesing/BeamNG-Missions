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
-- A larger ImGui HUD panel now sits left-middle, with a right-middle radar,
-- bottom-center objective banner, custom loader overlay, target arrows, pause-hidden UI, camera-relative radar, roads overlay,
-- pause-safe mission timers, and one-unlocked-mission-per-type tier progression.

local M = {}

-- BeamNG ImGui is usually exposed as ui_imgui in extensions.
-- Keep the old global fallback so the file remains version-tolerant.
im = rawget(_G, "ui_imgui") or rawget(_G, "im")


-- ── Mission types ──────────────────────────────────────────────────────────────
CHASE = "chase"
ESCAPE = "escape"
FOLLOW = "follow"
ENDURE = "endure"
REACH = "reach"
RALLY = "rally"
RACE = "race"
CRUISE = "cruise"

-- ── Mission templates ──────────────────────────────────────────────────────────
-- Positions are assigned at runtime from the map navigation graph.  The fallback
-- coordinates target West Coast USA.
missionTemplates = {
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
    {
        name          = "Checkpoint Blitz",
        type          = RALLY,
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.85, b = 0.0, a = 0.70 },
        needsDest     = true,
        waypointCount = 5,
        fallbackPos   = vec3(  250, -250, 26),
        fallbackDest  = vec3( -200,  200, 22),
    },
    {
        name          = "Street Kings",
        type          = RACE,
        triggerRadius = 12,
        color         = { r = 1.0, g = 0.35, b = 0.15, a = 0.70 },
        waypointCount = 5,
        fallbackPos   = vec3(  320, -120, 24),
    },
    {
        name          = "Cross Country",
        type          = CRUISE,
        triggerRadius = 12,
        color         = { r = 0.45, g = 0.85, b = 0.45, a = 0.70 },
        needsDest     = true,
        fallbackPos   = vec3( -400,  150, 24),
        fallbackDest  = vec3(  500,  400, 30),
    },
}

-- ── Tuning constants ───────────────────────────────────────────────────────────
PULSE_SPEED = 1.5    -- marker pulse rate (radians / second)
ESCAPE_TIME_LIMIT = 120    -- seconds before ESCAPE mission fails
MISSION_COOLDOWN = 10     -- seconds before the same marker can re-trigger
ESCAPE_MIN_DISTANCE = 500    -- metres: all police beyond this = escaped (ESCAPE win)
CHASE_DAMAGE_THRESH = 0.50   -- damage fraction that counts as "destroyed"
CHASE_ESCAPE_DISTANCE = 300    -- metres: target beyond this = got away (CHASE fail)
CHASE_SPAWN_OFFSET = 50     -- metres ahead of player to spawn the target
CHASE_TARGET_MODEL = "etk800"
CHASE_STOPPED_SPEED = 3.0    -- m/s: below this the target is considered stopped
CHASE_STOPPED_COOLDOWN = 10.0   -- seconds after spawn before stopped-time starts counting
CHASE_STOPPED_NEAR_DISTANCE = 15.0 -- metres: player must be this close before immobilization counts
CHASE_STOPPED_TIME = 5.0    -- seconds: target stopped this long = destroyed / immobilized
CHASE_SPEED_INTERVAL = 0.5    -- seconds between speed checks
POLICE_SPAWN_RADIUS = { min = 100, max = 200 }
POLICE_COUNT = 4      -- 4 feels more GTA-like without murdering performance
POLICE_SPAWN_ATTEMPTS = 5      -- fewer attempts; bad .pc paths get expensive during mission start

-- Vehicle config notes:
-- * model = the vehicle folder name.
-- * config = path to a .pc file. This must actually exist in your BeamNG install/mods.
-- * If one of these paths is wrong, the spawn attempt may fail or appear as a plain/default car.
POLICE_VARIANTS = {
    { model = "fullsize", config = "vehicles/fullsize/police.pc",             label = "Grand Marshal Police" },
    { model = "roamer",   config = "vehicles/roamer/police.pc",               label = "Roamer Police SUV" },
    { model = "sunburst2", config = "vehicles/sunburst2/police.pc",           label = "Sunburst Police" },

    -- ETK 800 police config names vary by version/mod setup, so try several.
    { model = "etk800",   config = "vehicles/etk800/844_police.pc",            label = "ETK 844 Police" },
    { model = "etk800",   config = "vehicles/etk800/854_police_A.pc",          label = "ETK 854 Police A" },
    { model = "etk800",   config = "vehicles/etk800/854_police_A_alt.pc",      label = "ETK 854 Police Alt" },
}
-- FOLLOW mission tuning
FOLLOW_SPAWN_DIST = 10      -- metres: target spawns right next to player for identification
FOLLOW_MIN_DIST = 20     -- metres: too close = out-of-range
FOLLOW_MAX_DIST = 100    -- metres: too far  = out-of-range
FOLLOW_GRACE = 10.0   -- seconds the player can be out-of-range before failing
FOLLOW_IMMUNITY = 20.0   -- seconds at mission start before "too close" detection activates
FOLLOW_DURATION = 120     -- seconds of sustained in-range following = success
FOLLOW_DAMAGE_THRESH = 0.10   -- damage to followed vehicle that triggers failure
FOLLOW_DMG_INTERVAL = 1.0    -- seconds between VE-side damage re-checks

-- ENDURE mission tuning
ENDURE_TIME_LIMIT = 120     -- seconds to survive recycling police = success
ENDURE_RECYCLE_DIST = 300    -- police beyond this from the player are teleported back
POLICE_TELEPORT_RADIUS = { min = 200, max = 300 }   -- far-ahead recycle placement; grace prevents instant re-recycle
POLICE_TELEPORT_INTERVAL = 2.5    -- seconds between recycle-teleport checks

-- REACH mission tuning
REACH_TIME_LIMIT = 180    -- seconds to reach destination before failing
REACH_RADIUS = 20     -- metres: arriving within this of destPos = success

-- RALLY mission tuning (multi-checkpoint point-to-point)
RALLY_CHECKPOINT_COUNT = 5       -- total waypoints to reach
RALLY_BASE_TIME = 60      -- seconds for the first checkpoint
RALLY_BONUS_TIME = 30      -- seconds added per checkpoint reached
RALLY_CHECKPOINT_RADIUS = 25      -- metres: arriving within this of a waypoint = hit
RALLY_WAYPOINT_SPREAD = 400     -- metres: max distance between successive waypoints

-- RACE mission tuning (AI racers + ordered checkpoints, no timer)
RACE_CHECKPOINT_COUNT = 5       -- total checkpoints in the street race
RACE_CHECKPOINT_RADIUS = 25      -- metres: arriving within this of a waypoint = hit
RACE_RACER_COUNT = 3       -- number of AI racers spawned for the event
RACE_SPAWN_RADIUS = { min = 3, max = 10 }
RACE_AI_SPEED = 22      -- m/s (~79 km/h): keeps racers competitive while still road-following reliably
RACE_AI_REFRESH_INTERVAL = 0.75
RALLY_MIN_CHECKPOINT_DISTANCE = 140 -- metres between sequential rally/race checkpoints
RACE_VARIANTS = {
    { model = "etk800",   label = "ETK 800",          color = "0.90 0.20 0.10 1" },
    { model = "covet",    label = "Covet",            color = "0.20 0.85 0.35 1" },
    { model = "bolide",   label = "Civetta Bolide",   color = "0.95 0.15 0.15 1" },
}

-- CRUISE mission tuning (single far destination, no police, player chooses route)
CRUISE_TIME_LIMIT = 300     -- seconds to reach the destination
CRUISE_RADIUS = 25      -- metres: arriving within this of destPos = success

-- Player damage tracking (ESCAPE / ENDURE / REACH fail condition)
PLAYER_DAMAGE_THRESH = 0.70   -- player vehicle wrecked at this damage level
PLAYER_DMG_CHECK_INTERVAL = 1.0    -- seconds between VE-side player damage checks
DRIVER_SEAT_CHECK_INTERVAL = 0.85   -- seconds between player/body/driver-seat health probes
WANTED_RECYCLE_INTERVAL = 2.0    -- seconds between wanted police recycle checks
WANTED_RECYCLE_DISTANCE = 300    -- wanted police farther than this are recycled ahead
POLICE_RECYCLE_GRACE = 10.0   -- seconds after spawn/teleport before a police unit may recycle again
PLAYER_IMMOBILE_SPEED = 2.0    -- m/s; below this counts as immobilized/stuck
PLAYER_IMMOBILE_TIME = 10.0    -- seconds immobilized near police before failing
PLAYER_BUSTED_DISTANCE = 10     -- metres; closest police must be within this to bust immobilized player

-- Beacon visual constants — dense pillar so spheres overlap and form a solid column
BEACON_BELOW = 3      -- metres below marker Z — avoid burying pillars below road surfaces
BEACON_ABOVE = 200    -- metres above marker Z — huge GTA-style sky pillar
BEACON_STEPS = 16    -- fewer slices; cheaper debugDrawer pillar
BEACON_PILLAR_R = 4.0    -- radius of pillar spheres (m)
BEACON_RING_SEGS = 12     -- segments in the ground-level trigger ring

-- Destination beacon (REACH mission) — brighter and distinct from mission markers (larger radius)
DEST_BEACON_BELOW = 3
DEST_BEACON_ABOVE = 200
DEST_BEACON_STEPS = 16
DEST_BEACON_R = 4.8   -- larger than BEACON_PILLAR_R so it stands out
DEST_BEACON_RING = 12

-- Road placement tuning
MIN_MISSION_SPACING = 200    -- metres between mission markers
INIT_TIMEOUT = 5.0    -- seconds to wait for map data before using fallback positions

-- HUD constants
HUD_WINDOW_WIDTH = 540
HUD_SCALE = 1.50
RADAR_WINDOW_SIZE = 320
RADAR_RANGE_METERS = 250
RADAR_ROAD_DRAW_LIMIT = 120
DIST_KM_THRESHOLD = 1000   -- metres; above this shown in km
AUTOSAVE_PATH = "/settings/jonesingMissions.autosave.json"

-- ── State ──────────────────────────────────────────────────────────────────────
pulseTime = 0
mission = nil   -- active mission table, or nil when idle
spawnedVehicles = {}    -- { id = <vehicleID>, role = "target"|"police" }
missionCooldowns = {}    -- mp.name -> seconds remaining on cooldown
destroyedTargets = {}    -- [vehicleID] = true when VE reports damage >= threshold
playerWrecked = false -- set by VE callback when player damage >= threshold
targetLastPos = nil   -- vec3: last-known position of chase target for speed estimation
targetStoppedSecs = 0     -- seconds the chase target has been stationary
targetSpeedTimer = 0     -- accumulator for speed check interval
missionPoints = {}    -- populated at init from templates + road positions
initialized = false -- true once mission positions have been assigned
initTimer = 0     -- seconds spent waiting for map data
loaderHideTimer = 0     -- keeps loader visible briefly after heavy spawn work
hudMsgTimer = 0     -- throttles built-in guihooks HUD fallback
focusReturnTimer = 0     -- repeatedly returns focus to player after AI spawns
loaderActive = false -- custom ImGui loader overlay; survives when built-in loader fails
loaderLabel = "Loading..."
bigBannerText = ""
bigBannerTimer = 0
missionCompletedByType = {} -- runtime unlocks: only next tier for each type is visible
templateTiersReady = false
lastSimClock = nil
missionStartHome = nil
radarRoadPositions = {}
radarRoadSegments = {}
getPlayerVehicle = nil -- forward declaration used by helpers above the concrete function

function sanitizeMissionProgress(data)
    local out = {}
    if type(data) ~= "table" then return out end
    for _, tpl in ipairs(missionTemplates) do
        local value = math.max(0, math.floor(tonumber(data[tpl.type]) or 0))
        if value > (out[tpl.type] or 0) then
            out[tpl.type] = value
        end
    end
    return out
end

function saveAutosave(reason)
    if not jsonWriteFile then return false end
    local payload = {
        version = 1,
        reason = reason or "autosave",
        savedAt = os and os.time and os.time() or nil,
        missionCompletedByType = sanitizeMissionProgress(missionCompletedByType),
    }

    local ok, wrote = pcall(jsonWriteFile, AUTOSAVE_PATH, payload, true)
    if ok and wrote ~= false then
        return true
    end

    log("W", "jonesingMissions", "Autosave failed: " .. tostring(reason or "autosave"))
    return false
end

function loadAutosave()
    if not jsonReadFile then return false end

    local ok, data = pcall(jsonReadFile, AUTOSAVE_PATH)
    if not ok or type(data) ~= "table" then
        missionCompletedByType = {}
        return false
    end

    missionCompletedByType = sanitizeMissionProgress(data.missionCompletedByType)
    return true
end

function asVec3(pos)
    if not pos or type(pos.x) ~= "number" or type(pos.y) ~= "number" or type(pos.z) ~= "number" then
        return nil
    end
    return vec3(pos.x, pos.y, pos.z)
end


-- ── Road position finding ──────────────────────────────────────────────────────
-- Collects positions from the map navigation graph (road network) and returns
-- `count` positions that are at least `minSpacing` metres apart.  Returns nil if
-- the map graph is unavailable or has too few nodes.
function findRandomRoadPositions(count, minSpacing)
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

    -- Prefer actual traffic/navigation road nodes with reasonable spacing and avoid extreme/off-map Zs.
    -- Some maps expose service/hidden graph nodes; narrow filtering reduces inaccessible pillars.
    -- When graph node data exposes radius/width, avoid tiny shoulder/path nodes that can put missions
    -- in alleys, dirt paths, or inaccessible map graph leftovers.
    local filtered = {}
    if type(gp.graph) == "table" then
        for _, nodeData in pairs(gp.graph) do
            if type(nodeData) == "table" and nodeData.pos then
                local p = nodeData.pos
                local radius = tonumber(nodeData.radius or nodeData.drivability or nodeData.width or 4) or 4
                if p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
                   and p.z > -200 and p.z < 2000 and radius >= 2.5 then
                    table.insert(filtered, vec3(p.x, p.y, p.z))
                end
            end
        end
    end
    if #filtered == 0 then
        for _, p in ipairs(allPositions) do
            if p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" and p.z > -200 and p.z < 2000 then
                table.insert(filtered, vec3(p.x, p.y, p.z))
            end
        end
    end
    allPositions = filtered

    -- Cache raw road/navigation data for the radar overlay.
    radarRoadPositions = {}
    for i, p in ipairs(allPositions) do
        radarRoadPositions[i] = p
    end

    radarRoadSegments = {}
    if type(gp.graph) == "table" then
        local seen = {}
        for fromNode, links in pairs(gp.graph) do
            if type(links) == "table" then
                for toNode, linkData in pairs(links) do
                    local keyA = tostring(fromNode)
                    local keyB = tostring(toNode)
                    local edgeKey = (keyA < keyB) and (keyA .. ":" .. keyB) or (keyB .. ":" .. keyA)
                    if not seen[edgeKey] then
                        local fromPos = nil
                        local toPos = nil

                        if type(linkData) == "table" then
                            fromPos = asVec3(linkData.inPos)
                            toPos = asVec3(linkData.outPos)
                        end
                        if not fromPos and type(gp.positions) == "table" then fromPos = asVec3(gp.positions[fromNode]) end
                        if not toPos and type(gp.positions) == "table" then toPos = asVec3(gp.positions[toNode]) end

                        if fromPos and toPos and fromPos:distance(toPos) <= 120 then
                            table.insert(radarRoadSegments, { a = fromPos, b = toPos })
                            seen[edgeKey] = true
                        end
                    end
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


-- Assign sequential runtime tiers per mission type, based on template order.
-- Only tier N+1 is visible where N is the number completed for that mission type.
function ensureTemplateTiers()
    if templateTiersReady then return end
    local counts = {}
    for _, tpl in ipairs(missionTemplates) do
        counts[tpl.type] = (counts[tpl.type] or 0) + 1
        tpl.tier = tpl.tier or counts[tpl.type]
        tpl.difficulty = tpl.difficulty or (tpl.tier == 1 and "Easy" or (tpl.tier == 2 and "Medium" or "Hard"))
    end
    templateTiersReady = true
end


function missionDisplayName(mp)
    if not mp then return "Mission" end
    local tier = mp.tier or 1
    local diff = mp.difficulty or (tier == 1 and "Easy" or (tier == 2 and "Medium" or "Hard"))
    return string.format("%s  [T%d / %s]", tostring(mp.name or "Mission"), tier, diff)
end

function activeMissionTemplates()
    ensureTemplateTiers()
    local active = {}
    for _, tpl in ipairs(missionTemplates) do
        local nextTier = (missionCompletedByType[tpl.type] or 0) + 1
        if tpl.tier == nextTier then
            table.insert(active, tpl)
        end
    end
    return active
end

-- Best-effort ground snapping.  BeamNG APIs differ by version/map, so every call is protected.
function snapToGround(pos, refPos)
    if not pos then return pos end
    local x, y = pos.x, pos.y
    local baseZ = (refPos and refPos.z) or pos.z or 0

    -- Best available road/terrain height. The nav graph Z is usually road-level, so
    -- never bury the marker far below that unless a height probe is clearly valid.
    local best = nil
    local probes = {
        function() return core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(x, y) end,
        function() return be and be.getSurfaceHeightBelow and be:getSurfaceHeightBelow(vec3(x, y, baseZ + 80)) end,
        function() return be and be.getSurfaceHeightBelow and be:getSurfaceHeightBelow(vec3(x, y, pos.z + 80)) end,
    }
    for _, fn in ipairs(probes) do
        local ok, h = pcall(fn)
        if ok and type(h) == "number" and h > -10000 and h < 10000 then
            -- Ignore terrain probes that are wildly below/above the road graph node; bridges and
            -- overpasses otherwise get shoved into the ground underneath.
            if math.abs(h - pos.z) < 12 then
                best = h
                break
            end
        end
    end
    if not best then best = pos.z end
    return vec3(x, y, best + 0.75)
end

function findRoadSpawnPositionNear(origin, minDist, maxDist)
    if not origin then return nil end

    local candidates = {}
    local pool = radarRoadPositions

    if not pool or #pool == 0 then
        local ok, gp = pcall(function() return map and map.getGraphpath and map.getGraphpath() end)
        if ok and gp and type(gp.positions) == "table" then
            pool = {}
            for _, pos in pairs(gp.positions) do
                if pos and type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
                    table.insert(pool, vec3(pos.x, pos.y, pos.z))
                end
            end
        end
    end

    if not pool or #pool == 0 then return nil end

    for _, pos in ipairs(pool) do
        local dist = origin:distance(pos)
        if dist >= minDist and dist <= maxDist then
            table.insert(candidates, pos)
        end
    end

    if #candidates == 0 then return nil end
    return snapToGround(candidates[math.random(1, #candidates)], origin)
end

-- Screen-size helpers.  Never hardcode 1920x1080 positions; BeamNG can run at any resolution.
function getDisplaySize()
    if im then
        local probes = {
            function() local io = im.GetIO and im.GetIO(); return io and io.DisplaySize end,
            function() local vp = im.GetMainViewport and im.GetMainViewport(); return vp and (vp.WorkSize or vp.Size) end,
        }
        for _, fn in ipairs(probes) do
            local ok, size = pcall(fn)
            if ok and size and type(size.x) == "number" and type(size.y) == "number" and size.x > 100 and size.y > 100 then
                return size.x, size.y
            end
        end
    end
    return 1920, 1080
end

function anchoredPos(anchor, w, h, marginX, marginY)
    local sw, sh = getDisplaySize()
    marginX, marginY = marginX or 24, marginY or 24
    if anchor == "leftMiddle" then
        return im.ImVec2(marginX, math.max(marginY, (sh - h) * 0.50))
    elseif anchor == "rightMiddle" then
        return im.ImVec2(math.max(marginX, sw - w - marginX), math.max(marginY, (sh - h) * 0.50))
    elseif anchor == "bottomCenter" then
        return im.ImVec2(math.max(marginX, (sw - w) * 0.50), math.max(marginY, sh - h - marginY))
    elseif anchor == "topCenter" then
        return im.ImVec2(math.max(marginX, (sw - w) * 0.50), marginY)
    elseif anchor == "center" then
        return im.ImVec2(math.max(marginX, (sw - w) * 0.50), math.max(marginY, (sh - h) * 0.50))
    end
    return im.ImVec2(marginX, marginY)
end

function isGamePaused()
    local pauseProbes = {
        function() return be and be.isPaused and be:isPaused() end,
        function() return be and be.getPaused and be:getPaused() end,
        function() return core_time and core_time.isPaused and core_time.isPaused() end,
        function() return gameplay and gameplay.paused end,
        function() return extensions and extensions.core_gamestate and extensions.core_gamestate.state and extensions.core_gamestate.state.paused end,
    }
    for _, fn in ipairs(pauseProbes) do
        local ok, paused = pcall(fn)
        if ok and paused == true then return true end
    end
    return false
end

local function isMapOrMenuOpen()
    local state = extensions and extensions.core_gamestate and extensions.core_gamestate.state
    if type(state) ~= "table" then return false end

    -- BeamNG exposes menu/map state with different keys across versions/builds.
    -- Probe a compatibility list so missions reliably freeze while map/menu UI is open.
    local boolKeys = {
        "menuOpen", "isMenuOpen",
        "bigMap", "bigMapOpen", "bigmapOpen", "bigMapActive", "isBigMapOpen",
        "mapOpen", "isMapOpen",
        "mapVisible", "isMapVisible", "bigMapVisible", "isBigMapVisible",
        "menuVisible", "isMenuVisible",
        "uiMenuOpen", "uiMapOpen"
    }
    for _, key in ipairs(boolKeys) do
        if state[key] == true then return true end
    end

    local rawState = tostring(state.state or state.currentState or "")
    if rawState ~= "" then
        local s = string.lower(rawState)
        local stateTokens = {
            "menu", "mainmenu", "pausemenu",
            "bigmap", "big_map",
            "mapview", "map_view", "worldmap", "world_map",
        }
        if s == "map" then return true end
        for _, token in ipairs(stateTokens) do
            if string.find(s, token, 1, true) then
                return true
            end
        end
    end
    return false
end

local function isMissionUpdateBlocked()
    return isGamePaused() or isMapOrMenuOpen()
end

-- BeamNG extension callbacks usually provide both real dt and sim dt.
-- Sim dt is the important one: it becomes 0 when paused and is scaled by slow-motion.
-- If this build only passes one value, fall back to known sim-clock probes.
function getSafeMissionDt(dtReal, dtSim)
    -- Hard pause guard. If the sim is paused, mission time is frozen.
    if isMissionUpdateBlocked() then return 0 end

    if type(dtSim) == "number" then
        return math.max(0, math.min(dtSim, 0.10))
    end

    dtReal = math.max(0, math.min(dtReal or 0, 0.10))
    local clock = nil
    local probes = {
        function() return be and be.getSimulationTime and be:getSimulationTime() end,
        function() return be and be.getSimTime and be:getSimTime() end,
        function() return Engine and Engine.getSimulationTime and Engine.getSimulationTime() end,
        function() return Sim and Sim.getCurrentTime and Sim.getCurrentTime() end,
        function() return TorqueScriptLua and TorqueScriptLua.getSimTime and TorqueScriptLua.getSimTime() end,
    }
    for _, fn in ipairs(probes) do
        local ok, v = pcall(fn)
        if ok and type(v) == "number" then clock = v break end
    end
    if clock then
        local out = 0
        if lastSimClock then out = math.max(0, math.min(clock - lastSimClock, 0.10)) end
        lastSimClock = clock
        return out
    end
    return dtReal
end

function setBigBanner(text, seconds)
    bigBannerText = text or ""
    bigBannerTimer = math.max(bigBannerTimer or 0, seconds or 3.0)
end

function saveMissionStartHome()
    local pv = getPlayerVehicle and getPlayerVehicle()
    if not pv then return end
    local pos = pv:getPosition()
    local rot = nil
    pcall(function() rot = pv:getRotation() end)
    missionStartHome = { id = pv:getID(), pos = vec3(pos.x, pos.y, pos.z + 0.35), rot = rot }

    -- Best-effort hooks for BeamNG's recovery/home system.  BeamNG exposes these
    -- differently across versions, so we try the common names but keep our own
    -- missionStartHome copy as a fallback/reference.
    pcall(function() if core_recovery and core_recovery.setHome then core_recovery.setHome(pv:getID()) end end)
    pcall(function() if core_recovery and core_recovery.saveHome then core_recovery.saveHome(pv:getID()) end end)
    pcall(function() if core_recovery and core_recovery.setSpawnPoint then core_recovery.setSpawnPoint(pv:getID(), missionStartHome.pos, missionStartHome.rot) end end)
    pcall(function() if core_recovery and core_recovery.setVehicleHome then core_recovery.setVehicleHome(pv:getID(), missionStartHome.pos, missionStartHome.rot) end end)
    pcall(function() if gameplay_recovery and gameplay_recovery.setHome then gameplay_recovery.setHome(pv:getID()) end end)
    pcall(function() if gameplay_recovery and gameplay_recovery.saveHome then gameplay_recovery.saveHome(pv:getID()) end end)
end

function recoverPlayerToMissionStart()
    local pv = getPlayerVehicle and getPlayerVehicle()
    if not pv or not missionStartHome or not missionStartHome.pos then return end
    local p = missionStartHome.pos
    pcall(function() if missionStartHome.rot and pv.setRotation then pv:setRotation(missionStartHome.rot) end end)
    pcall(function() pv:setPosition(p) end)

    -- IMPORTANT: do not write throttle/brake/reverse/parkingbrake input here.
    -- The previous build could leave the vehicle stuck in full reverse/full throttle.
    -- This only clears momentum/physics; it never writes throttle/brake/reverse inputs.
    pv:queueLuaCommand([[
        local zero = vec3({0,0,0})
        pcall(function() obj:setVelocity(zero) end)
        pcall(function() obj:setAngularVelocity(zero) end)
        pcall(function() obj:resetBrokenFlexMesh() end)
        pcall(function() obj:resetPhysics() end)
    ]])
end

function stopPlayerVehicle()
    local pv = getPlayerVehicle and getPlayerVehicle()
    if not pv then return end
    local pos = pv:getPosition()

    -- Save/recovery-home behavior is kept, but all direct input events are removed.
    pcall(function() pv:setPosition(vec3(pos.x, pos.y, pos.z + 0.35)) end)
    pv:queueLuaCommand([[
        local zero = vec3({0,0,0})
        pcall(function() obj:setVelocity(zero) end)
        pcall(function() obj:setAngularVelocity(zero) end)
        pcall(function() obj:resetBrokenFlexMesh() end)
        pcall(function() obj:resetPhysics() end)
    ]])
end

-- Counts how many positions are needed (one per mission plus one extra per REACH for destPos).
function countNeededPositions()
    local n = 0
    for _, tpl in ipairs(activeMissionTemplates()) do
        n = n + 1
        if tpl.needsDest then n = n + 1 end
    end
    return n
end

-- Builds the missionPoints table from templates using the given list of road positions.
function buildMissionPointsFromPositions(positions)
    missionPoints = {}
    local idx = 1
    for _, tpl in ipairs(activeMissionTemplates()) do
        local mp = {
            name          = tpl.name,
            type          = tpl.type,
            triggerRadius = tpl.triggerRadius,
            color         = tpl.color,
            tier          = tpl.tier,
            difficulty    = tpl.difficulty,
            pos           = snapToGround(positions[idx]),
        }
        idx = idx + 1
        if tpl.needsDest then
            mp.destPos = snapToGround(positions[idx])
            idx = idx + 1
        end
        mp.triggerRadiusSq        = mp.triggerRadius * mp.triggerRadius
        missionCooldowns[mp.name] = 0
        table.insert(missionPoints, mp)
    end
end

-- Builds the missionPoints table using hardcoded fallback coordinates.
function buildMissionPointsFallback()
    missionPoints = {}
    for _, tpl in ipairs(activeMissionTemplates()) do
        local mp = {
            name          = tpl.name,
            type          = tpl.type,
            triggerRadius = tpl.triggerRadius,
            color         = tpl.color,
            tier          = tpl.tier,
            difficulty    = tpl.difficulty,
            pos           = snapToGround(tpl.fallbackPos),
        }
        if tpl.needsDest then
            mp.destPos = snapToGround(tpl.fallbackDest)
        end
        mp.triggerRadiusSq        = mp.triggerRadius * mp.triggerRadius
        missionCooldowns[mp.name] = 0
        table.insert(missionPoints, mp)
    end
end

-- Attempts to place missions on valid road positions.  Returns true on success.
function tryInitMissions()
    -- Keep mission markers fixed and stable across map loads/session reloads.
    -- Dynamic graph placement was intentionally disabled because it relocated marker
    -- coordinates between loads, which broke player waypoint consistency.
    buildMissionPointsFallback()
    if #missionPoints > 0 then
        log("I", "jonesingMissions",
            "Placed " .. #missionPoints .. " missions using fixed fallback positions.")
        return true
    end
    log("W", "jonesingMissions", "Failed to build fallback mission positions.")
    return false
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
getPlayerVehicle = function()
    return be:getPlayerVehicle(0)
end

function forcePlayerFocus()
    local pv = getPlayerVehicle()
    if not pv then return end

    -- Spawning vehicles can steal focus in BeamNG.  Re-enter the original player
    -- vehicle for several frames after spawning so the camera/focus snaps back.
    pcall(function() be:enterVehicle(0, pv) end)

    if core_camera and core_camera.setByName then
        pcall(function() core_camera.setByName(0, "orbit") end)
    end
end

function armFocusReturn(seconds)
    focusReturnTimer = math.max(focusReturnTimer or 0, seconds or 1.0)
end

function showLoader(label)
    loaderActive = true
    loaderLabel = label or "Loading..."
    if guihooks then
        -- Keep BeamNG's built-in loading hook, but do not depend on it.
        guihooks.trigger('setLoading', { loading = true, label = loaderLabel })
        guihooks.message(loaderLabel, 1.0, "jonesingMissionLoader")
    end
end

function hideLoaderSoon(seconds)
    loaderHideTimer = math.max(loaderHideTimer or 0, seconds or 0.75)
end

function getPlayerPos()
    local v = getPlayerVehicle()
    if not v then return nil end
    return v:getPosition()
end

function getVehicleSpeed(veh)
    if not veh then return nil end
    local probes = {
        function() local v = veh:getVelocity(); return v and v:length() end,
        function() local v = veh:getVelocity(); return v and math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end,
        function() return veh.getVelocityLength and veh:getVelocityLength() end,
    }
    for _, fn in ipairs(probes) do
        local ok, v = pcall(fn)
        if ok and type(v) == 'number' then return v end
    end
    return nil
end

function addSpawnedVehicle(id, role)
    if not id then return end
    local vd = { id = id, role = role }
    if role == "police" then vd.recycleCooldown = POLICE_RECYCLE_GRACE end
    table.insert(spawnedVehicles, vd)
end

function notify(msgType, title, msg)
    guihooks.trigger("toastrMsg", { type = msgType, title = title, msg = msg })
end

-- Builds the VE-side Lua command string that checks vehicle damage and fires a GE
-- callback.  obj:getDamage() is wrapped in pcall because the method was removed in
-- newer BeamNG versions; the fallback reads obj.damage as a direct field.
function makeDamageCheckCmd(threshold, vehicleId)
    return string.format([[
        local function readDamage()
            local d = 0
            local ok, v = pcall(function() return obj:getDamage() end)
            if ok and type(v) == 'number' then d = math.max(d, v) end
            if type(obj.damage) == 'number' then d = math.max(d, obj.damage) end
            if damageTracker and damageTracker.getDamageData then
                local ok2, dd = pcall(damageTracker.getDamageData)
                if ok2 and type(dd) == 'table' then
                    d = math.max(d, tonumber(dd.damage) or 0, tonumber(dd.deformGroupDamage) or 0)
                end
            end
            return d
        end
        if readDamage() >= %f then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportTargetDamaged(%d)')
        end
    ]], threshold, vehicleId)
end

-- Same as above but fires reportFollowTargetDamaged (FOLLOW missions).
function makeFollowDamageCheckCmd(threshold, vehicleId)
    return string.format([[
        local function readDamage()
            local d = 0
            local ok, v = pcall(function() return obj:getDamage() end)
            if ok and type(v) == 'number' then d = math.max(d, v) end
            if type(obj.damage) == 'number' then d = math.max(d, obj.damage) end
            if damageTracker and damageTracker.getDamageData then
                local ok2, dd = pcall(damageTracker.getDamageData)
                if ok2 and type(dd) == 'table' then
                    d = math.max(d, tonumber(dd.damage) or 0, tonumber(dd.deformGroupDamage) or 0)
                end
            end
            return d
        end
        if readDamage() >= %f then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportFollowTargetDamaged(%d)')
        end
    ]], threshold, vehicleId)
end

-- VE-side command that checks the *player* vehicle's damage and fires
-- reportPlayerWrecked when the threshold is exceeded (ESCAPE/ENDURE/REACH).
function makePlayerDamageCheckCmd(threshold)
    return string.format([[
        local d = 0
        local ok, v = pcall(function() return obj:getDamage() end)
        if ok and type(v) == 'number' then d = math.max(d, v) end
        if type(obj.damage) == 'number' then d = math.max(d, obj.damage) end
        if damageTracker and damageTracker.getDamageData then
            local ok2, dd = pcall(damageTracker.getDamageData)
            if ok2 and type(dd) == 'table' then
                d = math.max(d, tonumber(dd.damage) or 0, tonumber(dd.deformGroupDamage) or 0)
            end
        end
        if d >= %f then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportPlayerWrecked()')
        end
    ]], threshold)
end



-- Experimental player-body/driver-seat health probe. This is intentionally safe:
-- if the current BeamNG build does not expose node/local position data here, it reports nothing.
-- Later, when the pedestrian/unicycle body has its own health, this can be replaced with a real body HP callback.
function makeDriverSeatHealthProbeCmd()
    return [[
        local severity = 0
        local function bump(v) if type(v) == 'number' and v > severity then severity = v end end

        -- Driver/body HP is still a placeholder, but this now reacts to real vehicle damage
        -- and cockpit/seat-ish deformation when BeamNG exposes those values. Later this can
        -- be replaced by the unicycle/pedestrian body damage callbacks.
        local okD, d = pcall(function() return obj:getDamage() end)
        if okD and type(d) == 'number' then bump(d * 0.85) end
        if type(obj.damage) == 'number' then bump(obj.damage * 0.85) end

        if damageTracker and damageTracker.getDamageData then
            local ok, dd = pcall(damageTracker.getDamageData)
            if ok and type(dd) == 'table' then
                bump((tonumber(dd.damage) or 0) * 0.85)
                bump((tonumber(dd.deformGroupDamage) or 0) * 0.60)
                bump((tonumber(dd.beamDamage) or 0) * 0.60)
                for k, v in pairs(dd) do
                    local key = tostring(k):lower()
                    if key:find('seat') or key:find('driver') or key:find('steer') or key:find('dash') or key:find('cabin') or key:find('cockpit') then
                        bump((tonumber(v) or 0) * 1.15)
                    end
                end
            end
        end

        -- Try node/group deformation hints if exposed. This is best-effort only.
        if v and v.data and type(v.data.nodes) == 'table' then
            for nid, n in pairs(v.data.nodes) do
                local name = tostring(n.name or n.cid or n.partOrigin or ''):lower()
                if name:find('seat') or name:find('driver') or name:find('steer') or name:find('dash') then
                    if type(n.nodeWeight) == 'number' and n.nodeWeight <= 0 then bump(1) end
                    if type(n.damage) == 'number' then bump(n.damage) end
                end
            end
        end

        if severity > 0.025 then
            obj:sendGameEngineLua('extensions.gameplay_jonesingMissions.reportDriverSeatCrush(' .. tostring(severity) .. ')')
        end
    ]]
end

-- Returns an 8-point compass abbreviation for a world-space (dx, dy) vector.
-- Axis convention: +X = East, +Y = North (standard BeamNG world coordinates).
function compassDir(dx, dy)
    local angle = math.atan2(dy, dx) * (180 / math.pi)
    if angle < 0 then angle = angle + 360 end
    local dirs = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
    local idx   = (math.floor((angle + 22.5) / 45) % 8) + 1
    return dirs[idx]
end

-- Spawns one police/pursuer at a random position around playerPos and sets its AI.
-- Returns the spawned vehicle object, or nil on failure.
function buildSpawnOptions(choice, spawnPos)
    local opts = {
        pos = spawnPos,
        rot = quat(0, 0, 0, 1),
        autoEnterVehicle = false,
    }
    if choice and choice.config and choice.config ~= "" then
        opts.config = choice.config
    end
    if choice and choice.color and choice.color ~= "" then
        opts.color = choice.color
    end
    return opts
end

-- Spawns one police/pursuer at a random position around playerPos and sets its AI.
-- Returns the spawned vehicle object, or nil on failure.
function spawnPoliceVehicle(playerPos, playerID)
    if not POLICE_VARIANTS or #POLICE_VARIANTS == 0 then
        log("E", "jonesingMissions", "POLICE_VARIANTS is missing or empty.")
        return nil
    end

    local angle = math.random() * 2 * math.pi
    local dist = math.random(POLICE_SPAWN_RADIUS.min, POLICE_SPAWN_RADIUS.max)
    local fallbackPos = vec3(
        playerPos.x + math.cos(angle) * dist,
        playerPos.y + math.sin(angle) * dist,
        playerPos.z + 1.5
    )
    local spawnPos = findRoadSpawnPositionNear(playerPos, POLICE_SPAWN_RADIUS.min, POLICE_SPAWN_RADIUS.max)
        or snapToGround(fallbackPos, playerPos)

    -- Try random variants rather than trusting one config path.
    -- This is important because police .pc names vary between BeamNG versions and mods.
    for attempt = 1, POLICE_SPAWN_ATTEMPTS do
        local choice = POLICE_VARIANTS[math.random(1, #POLICE_VARIANTS)]
        if choice and choice.model then
            log("I", "jonesingMissions",
                string.format("Police spawn attempt %d/%d: %s model=%s config=%s",
                    attempt, POLICE_SPAWN_ATTEMPTS,
                    tostring(choice.label or "?"),
                    tostring(choice.model),
                    tostring(choice.config)))

            local veh = core_vehicles.spawnNewVehicle(choice.model, buildSpawnOptions(choice, spawnPos))
            if veh then
                veh:queueLuaCommand(
                    "ai.setMode('chase'); " ..
                    "ai.setTargetObjectID(" .. tostring(playerID) .. "); " ..
                    "ai.driveInLane('off')"
                )

                forcePlayerFocus()
                armFocusReturn(1.5)

                log("I", "jonesingMissions",
                    "Spawned police vehicle: " .. tostring(choice.label or choice.model) ..
                    " config=" .. tostring(choice.config))
                return veh
            end

            log("W", "jonesingMissions",
                "Police spawn failed for model=" .. tostring(choice.model) ..
                " config=" .. tostring(choice.config))
        end
    end

    log("E", "jonesingMissions", "All police spawn attempts failed.")
    return nil
end

-- ── Beacon rendering ───────────────────────────────────────────────────────────
function adaptiveLabelZ(basePos, playerPos, above)
    if not basePos then return above end
    if not playerPos then return basePos.z + above + 6 end
    local d = basePos:distance(playerPos)
    -- Keep text lower when close, higher when far, so it remains camera-readable.
    return basePos.z + math.max(14, math.min(above + 10, d * 0.18))
end

-- Draws a GTA-style vertical beacon column.
function drawBeacon(mp, col)
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
function drawDestBeacon(destPos, pulse)
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

cleanupMission = nil
wantedLevelForMission = nil

-- ── Mission start helpers ──────────────────────────────────────────────────────
function startChase(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    local offset   = vec3(math.random(-40, 40), CHASE_SPAWN_OFFSET, 0)
    local fallbackPos = vec3(playerPos.x + offset.x, playerPos.y + offset.y, playerPos.z)
    local spawnPos = findRoadSpawnPositionNear(playerPos, math.max(10, CHASE_SPAWN_OFFSET), math.max(60, CHASE_SPAWN_OFFSET + 70))
        or snapToGround(fallbackPos, playerPos)

    -- core_vehicles.spawnNewVehicle returns the vehicle object (userdata), not a number.
    local targetVeh = core_vehicles.spawnNewVehicle(CHASE_TARGET_MODEL, {
        pos    = spawnPos,
        rot    = quat(0, 0, 0, 1),
        config = "vehicles/etk800/etk800.pc",
        color  = "0.1 0.3 0.9 1",
        autoEnterVehicle = false,
    })

    if targetVeh then
        local targetID = targetVeh:getID()
        addSpawnedVehicle(targetID, "target")
        targetVeh:queueLuaCommand(
            "ai.setMode('flee'); ai.setTargetObjectID(" .. tostring(playerID) .. ")"
        )
        -- VE-side damage monitor; fires GE callback when threshold is reached
        targetVeh:queueLuaCommand(makeDamageCheckCmd(CHASE_DAMAGE_THRESH, targetID))
        -- Chase shows wanted stars, so it should actually create wanted police too.
        for i = 1, wantedLevelForMission(CHASE) do
            local pVeh = spawnPoliceVehicle(playerPos, playerID)
            if pVeh then
                mission.policeSpawned = (mission.policeSpawned or 0) + 1
                addSpawnedVehicle(pVeh:getID(), "police")
            end
        end
        mission.recycleTimer = 0
        mission.chaseStoppedCooldown = CHASE_STOPPED_COOLDOWN
        forcePlayerFocus()
        armFocusReturn(1.5)
        notify("info",
            "MISSION: " .. missionDisplayName(point),
            string.format(
                "A suspect vehicle is fleeing! Chase it down and wreck it before it escapes beyond %d m. "
                .. "Ram it, block it — do whatever it takes to stop it!",
                CHASE_ESCAPE_DISTANCE))
    else
        notify("error", "Spawn Failed", "Could not spawn chase target — mission aborted.")
        cleanupMission(false, "Target failed to spawn.")
    end
end

function startEscape(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    for i = 1, POLICE_COUNT do
        local pVeh = spawnPoliceVehicle(playerPos, playerID)
        if pVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            addSpawnedVehicle(pVeh:getID(), "police")
        end
    end
    forcePlayerFocus()
    armFocusReturn(1.5)

    local spawned = mission.policeSpawned or 0
    if spawned == 0 then
        notify("error", "Spawn Failed", "No police vehicles could spawn — mission aborted.")
        cleanupMission(false, "Police failed to spawn.")
        return
    end
    notify("warning",
        "MISSION: " .. missionDisplayName(point),
        string.format(
            "You've been spotted! %d police unit%s in hot pursuit! "
            .. "Put %d m between you and every officer to shake them. "
            .. "You have %d seconds — and if they wreck your vehicle, it's over!",
            spawned, spawned ~= 1 and "s are" or " is",
            ESCAPE_MIN_DISTANCE, ESCAPE_TIME_LIMIT))

end

function startFollow(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end

    -- Spawn the target vehicle very close (~5 m) so the player can identify it
    local angle    = math.random() * 2 * math.pi
    local fallbackPos = vec3(
        playerPos.x + math.cos(angle) * FOLLOW_SPAWN_DIST,
        playerPos.y + math.sin(angle) * FOLLOW_SPAWN_DIST,
        playerPos.z
    )
    local spawnPos = findRoadSpawnPositionNear(playerPos, math.max(5, FOLLOW_SPAWN_DIST), math.max(40, FOLLOW_SPAWN_DIST + 35))
        or snapToGround(fallbackPos, playerPos)

    local targetVeh = core_vehicles.spawnNewVehicle("etk800", {
        pos   = spawnPos,
        rot   = quat(0, 0, 0, 1),
        color = "0.9 0.7 0.1 1",  -- yellow-gold so the player can identify it
        autoEnterVehicle = false,
    })

    if targetVeh then
        local targetID = targetVeh:getID()
        addSpawnedVehicle(targetID, "target")
        -- traffic mode: vehicle drives on roads as if it were a civilian
        targetVeh:queueLuaCommand("ai.setMode('traffic')")
        -- Initial VE-side damage check; re-queued every FOLLOW_DMG_INTERVAL seconds
        targetVeh:queueLuaCommand(makeFollowDamageCheckCmd(FOLLOW_DAMAGE_THRESH, targetID))
        forcePlayerFocus()
        armFocusReturn(1.5)
        mission.followImmunityTimer = 0
        notify("info",
            "MISSION: " .. missionDisplayName(point),
            string.format(
                "An undercover target just appeared near you — the yellow vehicle! "
                .. "You have %d seconds to identify them before they merge into traffic. "
                .. "Then stay between %d m and %d m for %d seconds. "
                .. "Don't collide with them or the operation is compromised!",
                math.floor(FOLLOW_IMMUNITY), FOLLOW_MIN_DIST, FOLLOW_MAX_DIST, FOLLOW_DURATION))
    else
        notify("error", "Spawn Failed", "Could not spawn follow target — mission aborted.")
        cleanupMission(false, "Target failed to spawn.")
    end
end

function startEndure(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    for i = 1, POLICE_COUNT do
        local pVeh = spawnPoliceVehicle(playerPos, playerID)
        if pVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            addSpawnedVehicle(pVeh:getID(), "police")
        end
    end
    forcePlayerFocus()
    armFocusReturn(1.5)

    local spawned = mission.policeSpawned or 0
    if spawned == 0 then
        notify("error", "Spawn Failed", "No police could spawn — mission aborted.")
        cleanupMission(false, "Police failed to spawn.")
        return
    end
    mission.recycleTimer = 0
    notify("warning",
        "MISSION: " .. missionDisplayName(point),
        string.format(
            "You're surrounded and reinforcements are endless! Survive for %d seconds as police "
            .. "units swarm your position. If your vehicle is wrecked, it's all over — stay mobile "
            .. "and stay alive!",
            ENDURE_TIME_LIMIT))
            
end

function startReach(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    for i = 1, POLICE_COUNT do
        local pVeh = spawnPoliceVehicle(playerPos, playerID)
        if pVeh then
            mission.policeSpawned = (mission.policeSpawned or 0) + 1
            addSpawnedVehicle(pVeh:getID(), "police")
        end
    end
    forcePlayerFocus()
    armFocusReturn(1.5)

    local spawned = mission.policeSpawned or 0
    if spawned == 0 then
        notify("error", "Spawn Failed", "No police could spawn — mission aborted.")
        cleanupMission(false, "Police failed to spawn.")
        return
    end
    mission.recycleTimer = 0
    notify("warning",
        "MISSION: " .. missionDisplayName(point),
        string.format(
            "The extraction point is marked — get there in %d seconds! Police will pursue "
            .. "relentlessly and won't give up. If your vehicle is destroyed before you arrive, "
            .. "the mission fails!",
            REACH_TIME_LIMIT))

end

-- Generates `count` random waypoints around a starting position, each within
-- RALLY_WAYPOINT_SPREAD of the previous.  Uses the road graph if available,
-- otherwise falls back to purely random offsets.
function generateRallyWaypoints(startPos, count)
    local waypoints = {}
    local prevPos   = startPos

    -- Build a sequential route from one nearby road point to the next so checkpoints
    -- progress along roads instead of jumping to unrelated random graph nodes.
    for i = 1, count do
        local wp = findRoadSpawnPositionNear(prevPos, RALLY_MIN_CHECKPOINT_DISTANCE, RALLY_WAYPOINT_SPREAD)

        -- Fallback: random offset if no road point can be found for this segment.
        if not wp then
            log("W", "jonesingMissions",
                "Checkpoint " .. tostring(i) .. " could not find nearby road position; using random fallback.")
            local angle  = math.random() * 2 * math.pi
            local dist   = math.random(150, RALLY_WAYPOINT_SPREAD)
            wp = vec3(
                prevPos.x + math.cos(angle) * dist,
                prevPos.y + math.sin(angle) * dist,
                prevPos.z
            )
        end

        table.insert(waypoints, wp)
        prevPos = wp
    end

    return waypoints
end

function startRally(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end

    local waypointCount = point.waypointCount or RALLY_CHECKPOINT_COUNT
    mission.rallyWaypoints   = generateRallyWaypoints(playerPos, waypointCount)
    mission.rallyCurrentIdx  = 1
    mission.rallyTimeLeft    = RALLY_BASE_TIME
    forcePlayerFocus()
    armFocusReturn(0.5)
    notify("info",
        "MISSION: " .. missionDisplayName(point),
        string.format(
            "A %d-checkpoint rally awaits! Reach each checkpoint within the time limit. "
            .. "Each checkpoint adds %d bonus seconds. Miss the deadline and you fail!",
            waypointCount, RALLY_BONUS_TIME))
end

function startCruise(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end

    forcePlayerFocus()
    armFocusReturn(0.5)
    notify("info",
        "MISSION: " .. missionDisplayName(point),
        string.format(
            "A far-off destination is marked on the map — get there however you want! "
            .. "No police, no pressure, just %d seconds to make the drive. "
            .. "Choose your own route and enjoy the ride!",
            CRUISE_TIME_LIMIT))
end

function tableSize(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function freezeRaceBaitVehicle(veh)
    if not veh then return end
    veh:queueLuaCommand([[
        pcall(function() ai.setMode('disabled') end)
        pcall(function() electrics.values.throttle = 0 end)
        pcall(function() electrics.values.brake = 1 end)
        pcall(function() electrics.values.parkingbrake = 1 end)
        local zero = vec3({0,0,0})
        pcall(function() obj:setVelocity(zero) end)
        pcall(function() obj:setAngularVelocity(zero) end)
    ]])
end

function spawnRaceBaitVehicle(waypoint, racerIndex)
    if not waypoint then return nil end

    -- This bait vehicle exists only so race AI can use the same reliable
    -- object-chase behavior as police. It is buried slightly below the checkpoint
    -- and frozen so the racer has an object ID to chase without a visible target car
    -- sitting in the road.
    local baitPos = vec3({
        waypoint.x,
        waypoint.y,
        waypoint.z - 4.0
    })

    local veh = core_vehicles.spawnNewVehicle("covet", {
        pos = baitPos,
        rot = quat(0, 0, 0, 1),
        color = "0 0 0 0",
        autoEnterVehicle = false,
    })

    if veh then
        freezeRaceBaitVehicle(veh)
        log("I", "jonesingMissions",
            string.format("Race bait spawned for racer %s at checkpoint target", tostring(racerIndex or "?")))
    else
        log("W", "jonesingMissions", "Race bait spawn failed.")
    end

    return veh
end

function moveRaceBaitToWaypoint(baitId, waypoint)
    if not baitId or not waypoint then return end

    local bait = scenetree.findObjectById(baitId) or be:getObjectByID(baitId)
    if not bait then return end

    local baitPos = vec3({
        waypoint.x,
        waypoint.y,
        waypoint.z - 4.0
    })

    pcall(function() bait:setPosition(baitPos) end)
    freezeRaceBaitVehicle(bait)
end

function queueRaceChaseBaitAI(veh, baitId)
    if not veh or not baitId then return end

    -- This intentionally mirrors the working police logic: chase an object ID,
    -- drive out of lane, and be aggressive. The bait car is moved per-racer to
    -- that racer's next checkpoint.
    veh:queueLuaCommand(
        "pcall(function() ai.setMode('chase') end); " ..
        "pcall(function() ai.setTargetObjectID(" .. tostring(baitId) .. ") end); " ..
        "pcall(function() ai.driveInLane('on') end); " ..
        "pcall(function() ai.setSpeedMode('set') end); " ..
        "pcall(function() ai.setSpeed(" .. tostring(RACE_AI_SPEED) .. ") end); " ..
        "pcall(function() ai.setAggressionMode('off') end); " ..
        "pcall(function() ai.setParameters({turnForceCoef = 1.6, awarenessForceCoef = 1.0}) end)"
    )
end

function spawnRaceVehicle(playerVeh, racerIndex)
    if not playerVeh then return nil end
    if not RACE_VARIANTS or #RACE_VARIANTS == 0 then
        log("E", "jonesingMissions", "RACE_VARIANTS is missing or empty.")
        return nil
    end

    local choice = RACE_VARIANTS[((racerIndex - 1) % #RACE_VARIANTS) + 1]
    if not choice or not choice.model then return nil end

    local playerPos = playerVeh:getPosition()
    local rot = quat(0, 0, 0, 1)
    pcall(function() rot = playerVeh:getRotation() end)

    -- Spawn racers right beside/behind the player. The marker already put the
    -- player on the route, so avoid road-node searches that fail on Grid/Test Map.
    local sideOffsets = { -4, 4, -8, 8, -12, 12 }
    local side = sideOffsets[racerIndex] or ((racerIndex - 1) * 4)
    local back = 4 + (math.floor((racerIndex - 1) / 2) * 4)

    local right = vec3({1, 0, 0})
    local forward = vec3({0, 1, 0})
    pcall(function()
        right = rot * vec3({1, 0, 0})
        forward = rot * vec3({0, 1, 0})
    end)

    local spawnPos = vec3({
        playerPos.x + right.x * side - forward.x * back,
        playerPos.y + right.y * side - forward.y * back,
        playerPos.z + 0.75
    })

    log("I", "jonesingMissions",
        string.format("Race spawn: %s model=%s beside player",
            tostring(choice.label or "?"),
            tostring(choice.model)))

    return core_vehicles.spawnNewVehicle(choice.model, {
        pos = spawnPos,
        rot = rot,
        color = choice.color,
        autoEnterVehicle = false,
    })
end

function startRace(point, playerPos)
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end

    local waypointCount = point.waypointCount or RACE_CHECKPOINT_COUNT

    mission.rallyWaypoints = generateRallyWaypoints(playerPos, waypointCount)
    mission.rallyCurrentIdx = 1
    mission.raceRacers = {}
    mission.raceFinishCount = 0

    for i = 1, RACE_RACER_COUNT do
        local veh = spawnRaceVehicle(playerVeh, i)
        local firstWp = mission.rallyWaypoints and mission.rallyWaypoints[1]
        local bait = spawnRaceBaitVehicle(firstWp, i)

        if veh and bait then
            local vid = veh:getID()
            local baitId = bait:getID()
            if vid and baitId then
                addSpawnedVehicle(vid, "racer")
                addSpawnedVehicle(baitId, "raceBait")
                mission.raceRacers[vid] = {
                    idx = 1,
                    finished = false,
                    baitId = baitId,
                    lastAiTargetIdx = 0,
                    aiRefreshTimer = RACE_AI_REFRESH_INTERVAL,
                }
                moveRaceBaitToWaypoint(baitId, firstWp)
                queueRaceChaseBaitAI(veh, baitId)
                mission.raceRacers[vid].lastAiTargetIdx = 1
            end
        elseif veh then
            local vid = veh:getID()
            if vid then addSpawnedVehicle(vid, "racer") end
        elseif bait then
            local baitId = bait:getID()
            if baitId then addSpawnedVehicle(baitId, "raceBait") end
        end
    end

    local racerCount = tableSize(mission.raceRacers or {})

    if racerCount == 0 then
        cleanupMission(false, "No race opponents or race bait targets could spawn.")
        return
    end

    forcePlayerFocus()
    armFocusReturn(1.5)

    notify("info",
        "MISSION: " .. missionDisplayName(point),
        string.format(
            "A %d-checkpoint street race is on! %d rival%s are chasing hidden checkpoint bait targets. " ..
            "No timer: first to the final checkpoint wins.",
            waypointCount,
            racerCount,
            racerCount == 1 and "" or "s"
        )
    )
end

-- ── Mission lifecycle ──────────────────────────────────────────────────────────
function runMissionStart(point, playerPos)
    stopPlayerVehicle()
    if     point.type == CHASE  then startChase (point, playerPos)
    elseif point.type == ESCAPE then startEscape(point, playerPos)
    elseif point.type == FOLLOW then startFollow(point, playerPos)
    elseif point.type == ENDURE then startEndure(point, playerPos)
    elseif point.type == REACH  then startReach (point, playerPos)
    elseif point.type == RALLY  then startRally (point, playerPos)
    elseif point.type == RACE   then startRace  (point, playerPos)
    elseif point.type == CRUISE then startCruise(point, playerPos)
    end

    if mission then
        mission.starting = false
        mission.started = true
        mission.timer = 0
    end

    forcePlayerFocus()
    armFocusReturn(2.0)
    hideLoaderSoon(0.85)
end

-- ── Mission lifecycle ──────────────────────────────────────────────────────────
function startMission(point)
    if mission then return end

    local playerPos = getPlayerPos()
    if not playerPos then return end

    spawnedVehicles   = {}
    destroyedTargets  = {}
    playerWrecked     = false
    targetLastPos     = nil
    targetStoppedSecs = 0
    targetSpeedTimer  = 0

    mission = {
        point = point,
        timer = 0,
        policeSpawned = 0,
        playerDmgTimer = 0,
        starting = true,
        started = false,
        startDelay = 0.25,
        playerImmobilizedTimer = 0,
    }

    -- Capture this exact location as the mission-start recovery/home point, then
    -- reset the vehicle there at 0 mph so high-speed pillar entries do not carry
    -- momentum into the mission.
    saveMissionStartHome()
    stopPlayerVehicle()
    recoverPlayerToMissionStart()
    showLoader("Starting " .. missionDisplayName(point) .. "...")
    setBigBanner("MISSION STARTING: " .. missionDisplayName(point), 2.0)
    forcePlayerFocus()
end

function tickPendingMissionStart(dt, playerPos)
    if not mission or not mission.starting then return false end
    if isMissionUpdateBlocked() then return true end

    -- Do not let success/fail logic run while the target/police have not spawned yet.
    mission.startDelay = (mission.startDelay or 0) - dt
    showLoader("Starting " .. tostring(mission.point.name) .. "...")
    forcePlayerFocus()

    if mission.startDelay <= 0 then
        runMissionStart(mission.point, playerPos or getPlayerPos())
    end

    return true
end

function cleanupMission(success, failMsg)
    if not mission then return end

    local completedType = mission.point and mission.point.type
    local completedName = mission.point and mission.point.name or "Mission"
    missionCooldowns[completedName] = MISSION_COOLDOWN

    -- Despawn all mission-spawned vehicles.
    -- scenetree.findObjectById is used for deletion; be:deleteObjectByID does not exist.
    for _, vd in ipairs(spawnedVehicles) do
        local vehObj = scenetree.findObjectById(vd.id)
        if vehObj then vehObj:delete() end
    end
    spawnedVehicles  = {}
    destroyedTargets = {}
    playerWrecked    = false
    targetLastPos    = nil
    targetStoppedSecs = 0
    targetSpeedTimer = 0
    loaderHideTimer = 0
    focusReturnTimer = 0
    if guihooks then guihooks.trigger('setLoading', { loading = false }); loaderActive = false end

    if success then
        missionCompletedByType[completedType] = (missionCompletedByType[completedType] or 0) + 1
        saveAutosave("mission_complete")
        notify("success", "Mission Complete!", "Well done!  '" .. completedName .. "' completed!")
        setBigBanner("MISSION COMPLETE", 3.0)
        -- Rebuild available markers so the next harder mission of this type unlocks.
        initialized = false
        initTimer = 0
    else
        notify("error", "Mission Failed!", failMsg or ("'" .. completedName .. "' failed."))
        setBigBanner("MISSION FAILED: " .. tostring(failMsg or completedName), 4.0)
    end

    mission = nil
end

-- ── Shared HUD helpers ─────────────────────────────────────────────────────────
-- Returns the distance from the player to the first alive "target" vehicle, or nil.
function getTargetDist(playerPos)
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
function countAlivePolice()
    local n = 0
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" and be:getObjectByID(vd.id) then
            n = n + 1
        end
    end
    return n
end

-- Returns the ImGui type-tag string and colour for a mission type.
function typeStyle(mtype)
    if mtype == CHASE  then return "C", im.ImVec4(1.0,  0.55, 0.15, 1.0) end
    if mtype == ESCAPE then return "E", im.ImVec4(0.25, 0.55, 1.0,  1.0) end
    if mtype == FOLLOW then return "F", im.ImVec4(0.10, 0.90, 0.55, 1.0) end
    if mtype == ENDURE then return "N", im.ImVec4(0.75, 0.20, 1.0,  1.0) end
    if mtype == REACH  then return "R", im.ImVec4(0.85, 0.85, 1.0,  1.0) end
    if mtype == RALLY  then return "Y", im.ImVec4(1.0,  0.85, 0.0,  1.0) end
    if mtype == RACE   then return "S", im.ImVec4(1.0,  0.35, 0.15, 1.0) end
    if mtype == CRUISE then return "D", im.ImVec4(0.45, 0.85, 0.45, 1.0) end
    return "?", im.ImVec4(1.0, 1.0, 1.0, 1.0)
end


function formatMeters(dist)
    if not dist then return "??" end
    if dist < DIST_KM_THRESHOLD then
        return string.format("%d m", math.floor(dist))
    end
    return string.format("%.1f km", dist / DIST_KM_THRESHOLD)
end

function getRoleVehicleInfo(playerPos, role)
    if not playerPos then return nil end
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == role then
            local v = be:getObjectByID(vd.id)
            if v then
                local pos = v:getPosition()
                return {
                    vehicle = v,
                    pos = pos,
                    dist = playerPos:distance(pos),
                    dir = compassDir(pos.x - playerPos.x, pos.y - playerPos.y),
                }
            end
        end
    end
    return nil
end

function getClosestPoliceInfo(playerPos)
    if not playerPos then return nil end
    local best = nil
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" then
            local v = be:getObjectByID(vd.id)
            if v then
                local pos = v:getPosition()
                local dist = playerPos:distance(pos)
                if not best or dist < best.dist then
                    best = {
                        vehicle = v,
                        pos = pos,
                        dist = dist,
                        dir = compassDir(pos.x - playerPos.x, pos.y - playerPos.y),
                    }
                end
            end
        end
    end
    return best
end

function getClosestRacerInfo(playerPos)
    if not playerPos then return nil end
    local best = nil
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "racer" then
            local v = be:getObjectByID(vd.id)
            if v then
                local pos = v:getPosition()
                local dist = playerPos:distance(pos)
                if not best or dist < best.dist then
                    best = {
                        vehicle = v,
                        pos = pos,
                        dist = dist,
                        dir = compassDir(pos.x - playerPos.x, pos.y - playerPos.y),
                    }
                end
            end
        end
    end
    return best
end

wantedLevelForMission = function(mtype)
    if mtype == CHASE then return 2 end
    if mtype == ESCAPE then return 3 end
    if mtype == ENDURE then return 4 end
    if mtype == REACH then return 3 end
    return 0
end

function wantedStars(level)
    local s = ""
    for i = 1, 5 do
        s = s .. (i <= level and "*" or "-")
    end
    return s
end

function missionInstruction(mtype)
    if mtype == CHASE then return "Wreck or immobilize the target." end
    if mtype == ESCAPE then return "Put distance between you and every officer." end
    if mtype == FOLLOW then return "Stay close, but do not hit the target." end
    if mtype == ENDURE then return "Survive until the timer reaches zero." end
    if mtype == REACH then return "Reach the destination before time runs out." end
    if mtype == RALLY then return "Hit each checkpoint before the timer expires." end
    if mtype == RACE then return "Beat the AI racers to the final checkpoint." end
    if mtype == CRUISE then return "Drive to the destination your own way." end
    return "Complete the mission objective."
end

-- ── ImGui HUD panel ────────────────────────────────────────────────────────────
function drawHUD()
    if not im then return end
    local playerPos = getPlayerPos()
    if not playerPos then return end

    local width = mission and HUD_WINDOW_WIDTH or HUD_WINDOW_WIDTH
    im.SetNextWindowSize(im.ImVec2(width, 0), im.Cond_Always)
    im.SetNextWindowPos(anchoredPos("leftMiddle", width, 520, 24, 24), im.Cond_Always)
    im.SetNextWindowBgAlpha(0.86)

    local winFlags = bit.bor(
        im.WindowFlags_NoTitleBar,
        im.WindowFlags_NoResize,
        im.WindowFlags_NoMove,
        im.WindowFlags_NoSavedSettings,
        im.WindowFlags_NoScrollbar
    )

    local drawn = im.Begin("##jonesingMissionInfo", nil, winFlags)
    if drawn then
        if im.SetWindowFontScale then im.SetWindowFontScale(HUD_SCALE) end
        if mission then
            local mp    = mission.point
            local mtype = mp.type
            local tag, tc = typeStyle(mtype)
            local stars = wantedStars(wantedLevelForMission(mtype))

            im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0), "  JONESING MISSIONS")
            im.Separator()
            im.TextColored(tc, string.format("  [%s] %s", tag, missionDisplayName(mp)))
            im.TextColored(im.ImVec4(1.0, 0.85, 0.25, 1.0), "  Difficulty: " .. tostring(mp.difficulty or "Easy"))
            im.TextColored(im.ImVec4(0.85, 0.85, 0.85, 1.0), "  " .. missionInstruction(mtype))

            if wantedLevelForMission(mtype) > 0 then
                im.TextColored(im.ImVec4(1.0, 0.15, 0.10, 1.0), "  WANTED  " .. stars)
            end
            im.Separator()

            if mtype == CHASE then
                local info = getRoleVehicleInfo(playerPos, "target")
                im.TextColored(im.ImVec4(1.0, 0.65, 0.0, 1.0),
                    string.format("  Target: %s %s / %d m max",
                        info and info.dir or "??",
                        info and formatMeters(info.dist) or "gone",
                        CHASE_ESCAPE_DISTANCE))
                im.TextColored(im.ImVec4(1.0, 0.4, 0.4, 1.0),
                    string.format("  Immobilized: %.1f / %.0f s", targetStoppedSecs, CHASE_STOPPED_TIME))

            elseif mtype == ESCAPE then
                local rem = math.max(0, math.ceil(ESCAPE_TIME_LIMIT - mission.timer))
                local closest = getClosestPoliceInfo(playerPos)
                im.TextColored(im.ImVec4(1.0, 0.4, 0.4, 1.0), string.format("  Time left: %d s", rem))
                im.TextColored(im.ImVec4(0.9, 0.9, 1.0, 1.0),
                    string.format("  Police: %d alive / %d spawned", countAlivePolice(), mission.policeSpawned or 0))
                im.TextColored(im.ImVec4(0.9, 0.9, 1.0, 1.0),
                    string.format("  Closest unit: %s %s", closest and closest.dir or "??", closest and formatMeters(closest.dist) or "none"))
                im.TextColored(im.ImVec4(0.75, 0.75, 0.75, 1.0),
                    string.format("  Escape distance: %d m from all units", ESCAPE_MIN_DISTANCE))

            elseif mtype == FOLLOW then
                local info = getRoleVehicleInfo(playerPos, "target")
                local prog = math.floor(math.min(mission.timer, FOLLOW_DURATION))
                local immune = (mission.followImmunityTimer or 0) < FOLLOW_IMMUNITY
                im.TextColored(im.ImVec4(0.10, 1.0, 0.65, 1.0),
                    string.format("  Target: %s %s", info and info.dir or "??", info and formatMeters(info.dist) or "gone"))
                im.TextColored(im.ImVec4(0.10, 1.0, 0.65, 1.0),
                    string.format("  Progress: %d / %d s", prog, FOLLOW_DURATION))
                im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0),
                    string.format("  Safe range: %d - %d m", FOLLOW_MIN_DIST, FOLLOW_MAX_DIST))
                if immune then
                    im.TextColored(im.ImVec4(0.5, 1.0, 0.5, 1.0),
                        string.format("  Identify grace: %d s", math.ceil(FOLLOW_IMMUNITY - (mission.followImmunityTimer or 0))))
                elseif (mission.followOutOfRangeSecs or 0) > 0 then
                    im.TextColored(im.ImVec4(1.0, 0.35, 0.35, 1.0),
                        string.format("  Out of range: %.1f / %.1f s", mission.followOutOfRangeSecs or 0, FOLLOW_GRACE))
                end

            elseif mtype == ENDURE then
                local rem = math.max(0, math.ceil(ENDURE_TIME_LIMIT - mission.timer))
                local closest = getClosestPoliceInfo(playerPos)
                im.TextColored(im.ImVec4(1.0, 0.4, 0.4, 1.0), string.format("  Survive: %d s", rem))
                im.TextColored(im.ImVec4(0.9, 0.9, 1.0, 1.0),
                    string.format("  Police: %d alive / %d spawned", countAlivePolice(), mission.policeSpawned or 0))
                im.TextColored(im.ImVec4(0.9, 0.9, 1.0, 1.0),
                    string.format("  Closest unit: %s %s", closest and closest.dir or "??", closest and formatMeters(closest.dist) or "none"))
                im.TextColored(im.ImVec4(0.75, 0.75, 0.75, 1.0), "  Units recycle when they fall too far behind.")

            elseif mtype == REACH then
                local rem = math.max(0, math.ceil(REACH_TIME_LIMIT - mission.timer))
                local dDist = mp.destPos and playerPos:distance(mp.destPos)
                local dDir = mp.destPos and compassDir(mp.destPos.x - playerPos.x, mp.destPos.y - playerPos.y) or "??"
                local closest = getClosestPoliceInfo(playerPos)
                im.TextColored(im.ImVec4(0.85, 0.85, 1.0, 1.0),
                    string.format("  Destination: %s %s", dDir, formatMeters(dDist)))
                im.TextColored(im.ImVec4(1.0, 0.4, 0.4, 1.0), string.format("  Time left: %d s", rem))
                im.TextColored(im.ImVec4(0.9, 0.9, 1.0, 1.0),
                    string.format("  Closest police: %s %s", closest and closest.dir or "??", closest and formatMeters(closest.dist) or "none"))

            elseif mtype == RALLY then
                local idx   = mission.rallyCurrentIdx or 1
                local total = mission.rallyWaypoints and #mission.rallyWaypoints or 0
                local tLeft = math.max(0, math.ceil(mission.rallyTimeLeft or 0))
                im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0), string.format("  Checkpoint: %d / %d", idx, total))
                if mission.rallyWaypoints and idx <= total then
                    local wp = mission.rallyWaypoints[idx]
                    local wDist = playerPos:distance(wp)
                    local wDir = compassDir(wp.x - playerPos.x, wp.y - playerPos.y)
                    im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0),
                        string.format("  Next CP: %s %s", wDir, formatMeters(wDist)))
                end
                im.TextColored(im.ImVec4(1.0, 0.4, 0.4, 1.0), string.format("  Time left: %d s", tLeft))

            elseif mtype == RACE then
                local idx   = mission.rallyCurrentIdx or 1
                local total = mission.rallyWaypoints and #mission.rallyWaypoints or 0
                local closest = getClosestRacerInfo(playerPos)
                im.TextColored(im.ImVec4(1.0, 0.45, 0.20, 1.0), string.format("  Checkpoint: %d / %d", idx, total))
                if mission.rallyWaypoints and idx <= total then
                    local wp = mission.rallyWaypoints[idx]
                    local wDist = playerPos:distance(wp)
                    local wDir = compassDir(wp.x - playerPos.x, wp.y - playerPos.y)
                    im.TextColored(im.ImVec4(1.0, 0.45, 0.20, 1.0), string.format("  Next CP: %s %s", wDir, formatMeters(wDist)))
                end
                im.TextColored(im.ImVec4(0.95, 0.85, 0.85, 1.0), string.format("  Rivals: %d", tableSize(mission.raceRacers or {})))
                im.TextColored(im.ImVec4(0.95, 0.85, 0.85, 1.0), string.format("  Closest rival: %s %s", closest and closest.dir or "??", closest and formatMeters(closest.dist) or "none"))

            elseif mtype == CRUISE then
                local rem = math.max(0, math.ceil(CRUISE_TIME_LIMIT - mission.timer))
                local dDist = mp.destPos and playerPos:distance(mp.destPos)
                local dDir = mp.destPos and compassDir(mp.destPos.x - playerPos.x, mp.destPos.y - playerPos.y) or "??"
                im.TextColored(im.ImVec4(0.45, 0.85, 0.45, 1.0),
                    string.format("  Destination: %s %s", dDir, formatMeters(dDist)))
                im.TextColored(im.ImVec4(1.0, 0.4, 0.4, 1.0), string.format("  Time left: %d s", rem))
            end

            im.Separator()
            if im.Button("  [ QUIT MISSION ]  ") then
                cleanupMission(false, "Mission aborted by player.")
            end
            im.TextColored(im.ImVec4(0.55, 0.55, 0.55, 1.0), "  Backspace also quits")
        else
            im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0), "  JONESING MISSIONS")
            im.Separator()
            im.TextColored(im.ImVec4(0.75, 0.75, 0.75, 1.0), "  Drive into a pillar to start a mission.")

            -- Idle mode: compact list of nearby/available missions.
            for _, mp in ipairs(missionPoints) do
                local onCooldown = (missionCooldowns[mp.name] or 0) > 0
                local dist = playerPos:distance(mp.pos)
                local dir = compassDir(mp.pos.x - playerPos.x, mp.pos.y - playerPos.y)
                local tag, tc = typeStyle(mp.type)

                if onCooldown then
                    im.TextColored(im.ImVec4(0.45, 0.45, 0.45, 1.0),
                        string.format("  [--] %s  CD:%ds", mp.name, math.ceil(missionCooldowns[mp.name])))
                else
                    im.TextColored(tc, string.format("  [%s] %s", tag, missionDisplayName(mp)))
                    im.TextColored(im.ImVec4(0.72, 0.72, 0.72, 1.0),
                        string.format("       %s  %s", dir, formatMeters(dist)))
                end
            end
        end
    end
    im.End()
end


imguiColor = nil

function drawLoaderOverlay()
    if not im or not loaderActive then return end
    im.SetNextWindowSize(im.ImVec2(520, 120), im.Cond_Always)
    im.SetNextWindowPos(anchoredPos("center", 520, 120, 24, 24), im.Cond_Always)
    im.SetNextWindowBgAlpha(0.92)
    local flags = bit.bor(im.WindowFlags_NoTitleBar, im.WindowFlags_NoResize, im.WindowFlags_NoMove, im.WindowFlags_NoSavedSettings)
    if im.Begin("##jonesingLoaderOverlay", nil, flags) then
        if im.SetWindowFontScale then im.SetWindowFontScale(1.65) end
        im.TextColored(im.ImVec4(1.0, 0.85, 0.10, 1.0), "  LOADING / SPAWNING TRAFFIC")
        im.Separator()
        im.TextColored(im.ImVec4(0.9, 0.9, 0.9, 1.0), "  " .. tostring(loaderLabel or "Please wait..."))
    end
    im.End()
end

function drawBottomBanner(playerPos)
    if not im then return end
    local text = bigBannerText
    if (not text or text == "") and mission and not mission.starting then
        text = string.upper(mission.point.type) .. " - " .. missionInstruction(mission.point.type)
    end
    if not text or text == "" then return end
    im.SetNextWindowSize(im.ImVec2(900, 100), im.Cond_Always)
    im.SetNextWindowPos(anchoredPos("bottomCenter", 900, 100, 24, 42), im.Cond_Always)
    im.SetNextWindowBgAlpha(0.78)
    local flags = bit.bor(im.WindowFlags_NoTitleBar, im.WindowFlags_NoResize, im.WindowFlags_NoMove, im.WindowFlags_NoSavedSettings)
    if im.Begin("##jonesingBottomBanner", nil, flags) then
        if im.SetWindowFontScale then im.SetWindowFontScale(1.85) end
        im.TextColored(im.ImVec4(1.0, 0.85, 0.0, 1.0), "  " .. text)
    end
    im.End()
end

function imguiColor(r, g, b, a)
    if im and im.GetColorU32 then
        local ok, c = pcall(function() return im.GetColorU32(im.ImVec4(r, g, b, a or 1)) end)
        if ok then return c end
    end
    return 0xffffffff
end

function addRadarBlip(items, label, pos, color, playerPos)
    if not pos or not playerPos then return end
    table.insert(items, { label = label, pos = pos, color = color or {1,1,1,1}, dist = playerPos:distance(pos) })
end

function drawRadarGlyph(sx, sy, text, color)
    if not im or not im.SetCursorScreenPos then return end
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    pcall(function()
        im.SetCursorScreenPos(im.ImVec2(sx - 4, sy - 8))
        im.TextColored(im.ImVec4(0.05, 0.05, 0.05, a), tostring(text or "*"))
        im.SetCursorScreenPos(im.ImVec2(sx - 5, sy - 9))
        im.TextColored(im.ImVec4(r, g, b, a), tostring(text or "*"))
    end)
end

function drawRadarPoint(drawList, cx, cy, px, py, radius, item)
    local r, g, b, a = item.color[1], item.color[2], item.color[3], item.color[4] or 1
    local edge = math.sqrt(px * px + py * py)
    if edge > radius then
        local k = radius / edge
        px, py = px * k, py * k
    end
    local sx, sy = cx + px, cy + py
    local col = imguiColor(r, g, b, a)
    local edgeCol = imguiColor(0.08, 0.08, 0.08, 0.95)

    -- Draw-list blips are pretty, but some BeamNG ImGui builds silently ignore a few
    -- draw-list calls. Also render a text glyph fallback at the same position.
    if drawList then
        pcall(function() drawList:AddCircleFilled(im.ImVec2(sx, sy), 12.0, edgeCol, 18) end)
        pcall(function() drawList:AddCircleFilled(im.ImVec2(sx, sy), 10.0, col, 18) end)
        pcall(function() drawList:AddCircle(im.ImVec2(sx, sy), 11.5, imguiColor(1,1,1,0.95), 18, 2.0) end)
        pcall(function() drawList:AddText(im.ImVec2(sx - 4, sy - 8), imguiColor(0.05,0.05,0.05,1), tostring(item.label or "*")) end)
        pcall(function() drawList:AddText(im.ImVec2(sx - 5, sy - 9), imguiColor(1,1,1,1), tostring(item.label or "*")) end)
        pcall(function() drawList:AddCircle(im.ImVec2(sx, sy), 14.0, imguiColor(r, g, b, 0.35), 18, 1.5) end)
    end
    drawRadarGlyph(sx, sy, item.label or "*", { r, g, b, a })
end

function drawRadarPlayerGlyph(cx, cy)
    if not im or not im.SetCursorScreenPos then return end
    pcall(function()
        im.SetCursorScreenPos(im.ImVec2(cx - 8, cy - 11))
        im.TextColored(im.ImVec4(0.05, 0.05, 0.05, 1.0), "^")
        im.SetCursorScreenPos(im.ImVec2(cx - 9, cy - 12))
        im.TextColored(im.ImVec4(0.20, 1.0, 0.30, 1.0), "^")
        im.SetCursorScreenPos(im.ImVec2(cx - 11, cy + 10))
        im.TextColored(im.ImVec4(0.20, 1.0, 0.30, 1.0), "YOU")
    end)
end

function getCameraForwardVectorFallback()
    local probes = {
        function() return core_camera and core_camera.getForward and core_camera.getForward() end,
        function() return core_camera and core_camera.getForwardVector and core_camera.getForwardVector() end,
        function() return commands and commands.getCameraForward and commands.getCameraForward() end,
    }
    for _, fn in ipairs(probes) do
        local ok, v = pcall(fn)
        if ok and v and type(v.x) == 'number' and type(v.y) == 'number' then return v end
    end
    local pv = getPlayerVehicle and getPlayerVehicle()
    if pv and pv.getDirectionVector then
        local ok, v = pcall(function() return pv:getDirectionVector() end)
        if ok and v then return v end
    end
    return vec3(0, 1, 0)
end

function drawRadarRoadOverlay(drawList, cx, cy, radius, playerPos, heading)
    if not drawList or not playerPos then return end
    local roadCol = imguiColor(0.55, 0.62, 0.68, 0.55)
    local scale = radius / RADAR_RANGE_METERS
    local drawn = 0
    if radarRoadSegments and #radarRoadSegments > 0 then
        for _, seg in ipairs(radarRoadSegments) do
            if drawn >= RADAR_ROAD_DRAW_LIMIT then break end
            local adx = seg.a.x - playerPos.x
            local ady = seg.a.y - playerPos.y
            local bdx = seg.b.x - playerPos.x
            local bdy = seg.b.y - playerPos.y
            local adist = math.sqrt(adx * adx + ady * ady)
            local bdist = math.sqrt(bdx * bdx + bdy * bdy)
            if adist < RADAR_RANGE_METERS or bdist < RADAR_RANGE_METERS then
                local aang = math.atan2(ady, adx) - heading
                local bang = math.atan2(bdy, bdx) - heading
                local apx = -math.sin(aang) * math.min(adist, RADAR_RANGE_METERS) * scale
                local apy = -math.cos(aang) * math.min(adist, RADAR_RANGE_METERS) * scale
                local bpx = -math.sin(bang) * math.min(bdist, RADAR_RANGE_METERS) * scale
                local bpy = -math.cos(bang) * math.min(bdist, RADAR_RANGE_METERS) * scale
                pcall(function()
                    drawList:AddLine(im.ImVec2(cx + apx, cy + apy), im.ImVec2(cx + bpx, cy + bpy), roadCol, 2.0)
                end)
                drawn = drawn + 1
            end
        end
        return
    end

    if not radarRoadPositions or #radarRoadPositions == 0 then return end
    for _, rp in ipairs(radarRoadPositions) do
        if drawn >= RADAR_ROAD_DRAW_LIMIT then break end
        local dx = rp.x - playerPos.x
        local dy = rp.y - playerPos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < RADAR_RANGE_METERS then
            local ang = math.atan2(dy, dx) - heading
            local px = -math.sin(ang) * dist * scale
            local py = -math.cos(ang) * dist * scale
            pcall(function()
                drawList:AddRectFilled(im.ImVec2(cx + px - 1.5, cy + py - 1.5), im.ImVec2(cx + px + 1.5, cy + py + 1.5), roadCol, 1)
            end)
            drawn = drawn + 1
        end
    end
end


function drawPlayerRadarArrow(drawList, cx, cy, radarHeading)
    if not drawList then return end
    local pv = getPlayerVehicle and getPlayerVehicle()
    local dir = nil
    if pv and pv.getDirectionVector then
        local ok, v = pcall(function() return pv:getDirectionVector() end)
        if ok and v and type(v.x) == 'number' and type(v.y) == 'number' then dir = v end
    end
    dir = dir or vec3(0, 1, 0)
    local carHeading = math.atan2(dir.y, dir.x)
    local rel = carHeading - (radarHeading or 0)
    local function rotPoint(x, y)
        -- local arrow points upward; rotate by car direction relative to camera-relative radar
        local ca, sa = math.cos(rel - math.pi * 0.5), math.sin(rel - math.pi * 0.5)
        return im.ImVec2(cx + x * ca - y * sa, cy + x * sa + y * ca)
    end
    local pcol = imguiColor(0.20, 1.0, 0.30, 1.0)
    pcall(function() drawList:AddTriangleFilled(rotPoint(0, -15), rotPoint(-9, 10), rotPoint(9, 10), pcol) end)
    pcall(function() drawList:AddCircleFilled(im.ImVec2(cx, cy), 5.5, imguiColor(0.05, 0.10, 0.05, 0.95), 18) end)
    pcall(function() drawList:AddCircle(im.ImVec2(cx, cy), 14, imguiColor(1,1,1,0.95), 20, 2.0) end)
    pcall(function() drawList:AddText(im.ImVec2(cx - 24, cy + 18), imguiColor(0.70,1.0,0.70,1.0), 'YOU') end)
end

function compassFromAngle(angle)
    return compassDir(math.cos(angle), math.sin(angle))
end

function drawRadar(playerPos)
    if not im or not playerPos then return end
    local w, h = RADAR_WINDOW_SIZE, RADAR_WINDOW_SIZE
    im.SetNextWindowSize(im.ImVec2(w, h), im.Cond_Always)
    im.SetNextWindowPos(anchoredPos("rightMiddle", w, h, 28, 24), im.Cond_Always)
    im.SetNextWindowBgAlpha(0.90)
    local flags = bit.bor(im.WindowFlags_NoTitleBar, im.WindowFlags_NoResize, im.WindowFlags_NoMove, im.WindowFlags_NoSavedSettings, im.WindowFlags_NoScrollbar)
    if im.Begin("##jonesingRadar", nil, flags) then
        local drawList = im.GetWindowDrawList and im.GetWindowDrawList()
        local pos = im.GetWindowPos and im.GetWindowPos() or im.ImVec2(0,0)
        local cx = pos.x + w * 0.5
        local cy = pos.y + h * 0.53
        local radius = (w * 0.5) - 28

        if drawList then
            local bg = imguiColor(0.02, 0.03, 0.04, 0.96)
            local ring = imguiColor(0.65, 0.85, 1.0, 0.95)
            local soft = imguiColor(0.65, 0.85, 1.0, 0.40)
            pcall(function() drawList:AddCircleFilled(im.ImVec2(cx, cy), radius + 8, bg, 64) end)
            pcall(function() drawList:AddCircle(im.ImVec2(cx, cy), radius, ring, 64, 2.5) end)
            pcall(function() drawList:AddCircle(im.ImVec2(cx, cy), radius * 0.50, soft, 48, 1.5) end)
            pcall(function() drawList:AddLine(im.ImVec2(cx - radius, cy), im.ImVec2(cx + radius, cy), soft, 1.5) end)
            pcall(function() drawList:AddLine(im.ImVec2(cx, cy - radius), im.ImVec2(cx, cy + radius), soft, 1.5) end)
        end

        local camDir = getCameraForwardVectorFallback()
        local heading = math.atan2(camDir.y, camDir.x)
        local topDir = compassFromAngle(heading)
        local rightDir = compassFromAngle(heading - math.pi * 0.5)
        local bottomDir = compassFromAngle(heading + math.pi)
        local leftDir = compassFromAngle(heading + math.pi * 0.5)
        if drawList then
            drawRadarRoadOverlay(drawList, cx, cy, radius, playerPos, heading)
            -- Player marker points in the CAR'S facing direction, while the radar itself remains camera-relative.
            drawPlayerRadarArrow(drawList, cx, cy, heading)
        end
        drawRadarPlayerGlyph(cx, cy)

        local items = {}
        if mission then
            local mtype = mission.point.type
            if mtype == CHASE or mtype == FOLLOW then
                local info = getRoleVehicleInfo(playerPos, "target")
                if info then addRadarBlip(items, "T", info.pos, {1.0, 0.85, 0.0, 1.0}, playerPos) end
            end
            for _, vd in ipairs(spawnedVehicles) do
                if vd.role == "police" then
                    local v = be:getObjectByID(vd.id)
                    if v then addRadarBlip(items, "P", v:getPosition(), {1.0, 0.12, 0.08, 1.0}, playerPos) end
                end
                if vd.role == "racer" then
                    local v = be:getObjectByID(vd.id)
                    if v then addRadarBlip(items, "R", v:getPosition(), {1.0, 0.35, 0.15, 1.0}, playerPos) end
                end
            end
            if mission.point.destPos then
                addRadarBlip(items, "D", mission.point.destPos, {0.55, 0.8, 1.0, 1.0}, playerPos)
            end
            if mission.rallyWaypoints and mission.rallyCurrentIdx then
                addRadarBlip(items, "C", mission.rallyWaypoints[mission.rallyCurrentIdx], {1.0, 0.85, 0.0, 1.0}, playerPos)
            end
        else
            for _, mp in ipairs(missionPoints) do
                if (missionCooldowns[mp.name] or 0) <= 0 then
                    local tag = select(1, typeStyle(mp.type)) or "M"
                    -- Use simple colors by mission type; ImVec4 introspection is unreliable in BeamNG Lua.
                    local c = {0.9, 0.9, 0.9, 1.0}
                    if mp.type == CHASE then c = {1.0,0.45,0.10,1.0}
                    elseif mp.type == ESCAPE then c = {0.25,0.55,1.0,1.0}
                    elseif mp.type == FOLLOW then c = {0.10,0.90,0.55,1.0}
                    elseif mp.type == ENDURE then c = {0.75,0.20,1.0,1.0}
                    elseif mp.type == REACH then c = {0.85,0.85,1.0,1.0}
                    elseif mp.type == RALLY then c = {1.0,0.85,0.0,1.0}
                    elseif mp.type == RACE then c = {1.0,0.35,0.15,1.0}
                    elseif mp.type == CRUISE then c = {0.45,0.85,0.45,1.0} end
                    addRadarBlip(items, tag, mp.pos, c, playerPos)
                end
            end
        end

        -- Camera-relative radar: world targets rotate so radar-up is where the camera is facing.
        local scale = radius / RADAR_RANGE_METERS
        for _, item in ipairs(items) do
            local dx = item.pos.x - playerPos.x
            local dy = item.pos.y - playerPos.y
            -- Rotate world coordinates so the player's forward direction is radar-up.
            local ang = math.atan2(dy, dx) - heading
            local dist = math.min(item.dist or math.sqrt(dx*dx+dy*dy), RADAR_RANGE_METERS)
            local px = -math.sin(ang) * dist * scale
            local py = -math.cos(ang) * dist * scale
            if drawList then drawRadarPoint(drawList, cx, cy, px, py, radius, item) end
        end

        if im.SetWindowFontScale then im.SetWindowFontScale(1.05) end
        im.SetCursorPos(im.ImVec2(16, 10))
        im.TextColored(im.ImVec4(0.70, 0.90, 1.0, 1.0), "RADAR")
        im.SetCursorPos(im.ImVec2(w * 0.50 - 6, 26))
        im.TextColored(im.ImVec4(0.65, 0.85, 1.0, 0.95), topDir)
        im.SetCursorPos(im.ImVec2(w * 0.50 - 5, h - 42))
        im.TextColored(im.ImVec4(0.65, 0.85, 1.0, 0.70), bottomDir)
        im.SetCursorPos(im.ImVec2(24, h * 0.53 - 9))
        im.TextColored(im.ImVec4(0.65, 0.85, 1.0, 0.70), leftDir)
        im.SetCursorPos(im.ImVec2(w - 32, h * 0.53 - 9))
        im.TextColored(im.ImVec4(0.65, 0.85, 1.0, 0.70), rightDir)
        im.SetCursorPos(im.ImVec2(16, h - 28))
        im.TextColored(im.ImVec4(0.78, 0.78, 0.78, 1.0), string.format("Range %dm  Blips:%d", RADAR_RANGE_METERS, #items))
    end
    im.End()
end

function drawTargetArrows(playerPos)
    if not mission or not playerPos then return end
    if mission.point.type ~= CHASE and mission.point.type ~= FOLLOW then return end
    local pulse = 0.5 + 0.5 * math.sin(pulseTime * 5.0)
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            if v then
                local p = v:getPosition()
                local d = playerPos:distance(p)
                -- Keep the marker close to the car. It grows mildly with distance, but it no longer
                -- floats 40m above the target or spams unreadable text at close range.
                local h = math.max(1.7, math.min(4.5, d * 0.010)) + pulse * 0.35
                local size = math.max(0.65, math.min(1.55, d * 0.0045))
                local top = vec3(p.x, p.y, p.z + h + size)
                local apex = vec3(p.x, p.y, p.z + h - size * 0.65)
                local c1 = vec3(p.x + size, p.y, p.z + h + size * 0.35)
                local c2 = vec3(p.x - size, p.y, p.z + h + size * 0.35)
                local c3 = vec3(p.x, p.y + size, p.z + h + size * 0.35)
                local c4 = vec3(p.x, p.y - size, p.z + h + size * 0.35)
                local col = ColorF(1.0, 0.85, 0.0, 0.72 + 0.28 * pulse)
                -- Inverted pyramid / pointer made from debug lines + small spheres; much more readable
                -- than large floating text and compatible with more BeamNG debugDrawer builds.
                pcall(function() debugDrawer:drawLine(c1, apex, col) end)
                pcall(function() debugDrawer:drawLine(c2, apex, col) end)
                pcall(function() debugDrawer:drawLine(c3, apex, col) end)
                pcall(function() debugDrawer:drawLine(c4, apex, col) end)
                pcall(function() debugDrawer:drawLine(c1, c3, col) end)
                pcall(function() debugDrawer:drawLine(c3, c2, col) end)
                pcall(function() debugDrawer:drawLine(c2, c4, col) end)
                pcall(function() debugDrawer:drawLine(c4, c1, col) end)
                debugDrawer:drawSphere(apex, size * 0.22, col)
                debugDrawer:drawSphere(top, size * 0.18, col)
            end
        end
    end
end

function drawJonesingUI()
    -- Hide all custom UI while paused/menu is open. This keeps the pause/menu screen clean.
    if isGamePaused() then return end
    local playerPos = getPlayerPos()
    drawHUD()
    drawRadar(playerPos)
    drawBottomBanner(playerPos)
    drawLoaderOverlay()
end

-- ── Success conditions ─────────────────────────────────────────────────────────
-- Chase success: target is destroyed (damage threshold) OR target has been
-- immobilised for CHASE_STOPPED_TIME seconds (speed near zero).
function checkChaseSuccess()
    -- Startup guard: never pass chase before the target exists.
    if not mission or mission.starting or not mission.started then
        return false
    end

    if targetStoppedSecs >= CHASE_STOPPED_TIME then
        return true
    end

    local sawTarget = false
    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            sawTarget = true

            if destroyedTargets[vd.id] then
                return true
            end

            local v = be:getObjectByID(vd.id)
            if not v then
                -- Target existed and is now gone/despawned: count as destroyed.
                return true
            end

            -- Re-queue the VE-side damage check, but don't assume success until the callback reports it.
            v:queueLuaCommand(makeDamageCheckCmd(CHASE_DAMAGE_THRESH, vd.id))
            return false
        end
    end

    -- No target has ever been registered yet. This caused the auto-pass bug.
    return false
end

-- Tracks the chase target's speed by comparing positions between frames.
-- Updates targetStoppedSecs (accumulated time the target has been near-stationary).
function tickChaseTargetSpeed(dt)
    if mission and (mission.chaseStoppedCooldown or 0) > 0 then
        mission.chaseStoppedCooldown = math.max(0, (mission.chaseStoppedCooldown or 0) - dt)
        targetLastPos = nil
        targetStoppedSecs = 0
        return
    end

    targetSpeedTimer = targetSpeedTimer + dt
    if targetSpeedTimer < CHASE_SPEED_INTERVAL then return end
    targetSpeedTimer = 0

    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "target" then
            local v = be:getObjectByID(vd.id)
            if not v then return end
            local pos = v:getPosition()
            local playerPos = getPlayerPos()
            if not playerPos or playerPos:distance(pos) > CHASE_STOPPED_NEAR_DISTANCE then
                targetStoppedSecs = 0
                targetLastPos = pos
                return
            end
            if targetLastPos then
                local moved = pos:distance(targetLastPos)
                local speed = moved / CHASE_SPEED_INTERVAL  -- metres per second
                if speed < CHASE_STOPPED_SPEED then
                    targetStoppedSecs = targetStoppedSecs + CHASE_SPEED_INTERVAL
                else
                    targetStoppedSecs = 0
                end
            end
            targetLastPos = pos
            return
        end
    end
end

function checkEscapeSuccess()
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
function tickFollow(playerPos, dt)
    if not playerPos then return nil end

    -- Immunity period: no "too close" detection for the first FOLLOW_IMMUNITY seconds
    mission.followImmunityTimer = (mission.followImmunityTimer or 0) + dt
    local immune = mission.followImmunityTimer < FOLLOW_IMMUNITY

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

            -- Distance range check (skip normal "too close" warning during immunity).
            -- Hard-contact/ramming range fails immediately after the identify grace. This catches
            -- the common case where BeamNG damage callbacks don't fire quickly enough.
            local dist = playerPos:distance(v:getPosition())
            if not immune and dist < 6 then
                return "fail:You hit the target!"
            end
            local outOfRange = false
            if not immune and dist < FOLLOW_MIN_DIST then
                outOfRange = true
            elseif dist > FOLLOW_MAX_DIST then
                outOfRange = true
            end

            if outOfRange then
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
-- Teleport position is biased ahead of the player's facing direction so police don't
-- visibly pop in right beside the camera.
function tickTeleportPolice(playerPos, dt)
    if not mission or not playerPos then return end
    local playerVeh = getPlayerVehicle()
    if not playerVeh then return end
    local playerID = playerVeh:getID()
    if not playerID then return end

    mission.recycleTimer = (mission.recycleTimer or 0) + dt
    if mission.recycleTimer < POLICE_TELEPORT_INTERVAL then return end
    mission.recycleTimer = 0

    local playerDir = nil
    pcall(function() playerDir = playerVeh:getDirectionVector() end)
    if not playerDir then playerDir = vec3(0, 1, 0) end
    local basePlayerAngle = math.atan2(playerDir.y, playerDir.x)

    for _, vd in ipairs(spawnedVehicles) do
        if vd.role == "police" then
            vd.recycleCooldown = math.max(0, (vd.recycleCooldown or 0) - POLICE_TELEPORT_INTERVAL)
            local v = be:getObjectByID(vd.id)
            if v then
                local dist = playerPos:distance(v:getPosition())
                -- Important: recycled units are intentionally placed beyond ENDURE_RECYCLE_DIST.
                -- Without this grace, they immediately qualify for recycling again and can get
                -- stuck in a teleport/despawn-looking loop before their AI can settle.
                if dist > ENDURE_RECYCLE_DIST and (vd.recycleCooldown or 0) <= 0 then
                    local d = math.random(POLICE_TELEPORT_RADIUS.min, POLICE_TELEPORT_RADIUS.max)
                    local spreadAng = (math.random() - 0.5) * math.pi * 0.55
                    local a = basePlayerAngle + spreadAng
                    local fallbackPos = vec3(playerPos.x + math.cos(a) * d, playerPos.y + math.sin(a) * d, playerPos.z + 1.5)
                    local newPos = findRoadSpawnPositionNear(playerPos, POLICE_TELEPORT_RADIUS.min, POLICE_TELEPORT_RADIUS.max)
                        or snapToGround(fallbackPos, playerPos)
                    pcall(function() v:setPosition(newPos) end)
                    vd.recycleCooldown = POLICE_RECYCLE_GRACE
                    v:queueLuaCommand(
                        "obj:resetBrokenFlexMesh(); " ..
                        "pcall(function() obj:setVelocity(vec3({0,0,0})) end); " ..
                        "pcall(function() obj:setAngularVelocity(vec3({0,0,0})) end); " ..
                        "ai.setMode('chase'); ai.setTargetObjectID(" .. tostring(playerID) .. "); ai.driveInLane('off')"
                    )
                end
            end
        end
    end
end

-- Periodically queues a VE-side damage check on the player's vehicle.
-- If playerWrecked is already set, returns true (caller should fail the mission).
function tickPlayerDamage(dt)
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


function tickPoliceBustedFail(playerPos, dt)
    if not mission or not playerPos then return false end
    local mtype = mission.point and mission.point.type
    if not wantedLevelForMission or wantedLevelForMission(mtype) <= 0 then
        mission.playerImmobilizedTimer = 0
        return false
    end

    local closest = getClosestPoliceInfo(playerPos)
    local pv = getPlayerVehicle and getPlayerVehicle()
    local speed = getVehicleSpeed(pv)
    local bustedRange = closest and closest.dist and closest.dist <= PLAYER_BUSTED_DISTANCE
    local immobile = speed ~= nil and speed <= PLAYER_IMMOBILE_SPEED

    if bustedRange and immobile then
        mission.playerImmobilizedTimer = (mission.playerImmobilizedTimer or 0) + dt
    else
        mission.playerImmobilizedTimer = math.max(0, (mission.playerImmobilizedTimer or 0) - dt * 2.0)
    end

    if (mission.playerImmobilizedTimer or 0) >= PLAYER_IMMOBILE_TIME then
        return true
    end
    return false
end

function showMissionHudMessage(dt, playerPos)
    if not mission or not playerPos or mission.starting then return end

    hudMsgTimer = (hudMsgTimer or 0) + dt
    if hudMsgTimer < 1.0 then return end
    hudMsgTimer = 0

    local mp = mission.point
    local mtype = mp.type
    local text = string.upper(mtype) .. " | " .. tostring(mp.name) .. " | " .. missionInstruction(mtype)

    if mtype == CHASE then
        text = string.format("CHASE | %s | Target %s | %s", mp.name, formatMeters(getTargetDist(playerPos)), missionInstruction(mtype))
    elseif mtype == ESCAPE then
        local closest = getClosestPoliceInfo(playerPos)
        text = string.format("ESCAPE | %s | %ds | Closest police %s | %s", mp.name, math.max(0, math.ceil(ESCAPE_TIME_LIMIT - mission.timer)), closest and formatMeters(closest.dist) or "none", missionInstruction(mtype))
    elseif mtype == ENDURE then
        local closest = getClosestPoliceInfo(playerPos)
        text = string.format("ENDURE | %s | %ds | Closest police %s | %s", mp.name, math.max(0, math.ceil(ENDURE_TIME_LIMIT - mission.timer)), closest and formatMeters(closest.dist) or "none", missionInstruction(mtype))
    elseif (mtype == REACH or mtype == CRUISE) and mp.destPos then
        local limit = (mtype == REACH) and REACH_TIME_LIMIT or CRUISE_TIME_LIMIT
        text = string.format("%s | %s | Dest %s | %ds", string.upper(mtype), mp.name, formatMeters(playerPos:distance(mp.destPos)), math.max(0, math.ceil(limit - mission.timer)))
    elseif mtype == RALLY and mission.rallyWaypoints then
        local idx = mission.rallyCurrentIdx or 1
        local wp = mission.rallyWaypoints[idx]
        text = string.format("RALLY | %s | CP %d/%d | %s | %ds", mp.name, idx, #mission.rallyWaypoints, wp and formatMeters(playerPos:distance(wp)) or "??", math.max(0, math.ceil(mission.rallyTimeLeft or 0)))
    elseif mtype == RACE and mission.rallyWaypoints then
        local idx = mission.rallyCurrentIdx or 1
        local wp = mission.rallyWaypoints[idx]
        text = string.format("RACE | %s | CP %d/%d | %s | First to the finish", mp.name, idx, #mission.rallyWaypoints, wp and formatMeters(playerPos:distance(wp)) or "??")
    end

    if guihooks then guihooks.message(text, 1.2, "jonesingMissionHud") end
end

M._frameOps = {}

function M._frameOps.tickMissionCooldowns(dt)
    for name, cd in pairs(missionCooldowns) do
        if cd > 0 then
            missionCooldowns[name] = math.max(0, cd - dt)
        end
    end
end

function M._frameOps.drawMissionMarkers(playerPos)
    for _, mp in ipairs(missionPoints) do
        local isActive   = mission and mission.point == mp
        local onCooldown = (missionCooldowns[mp.name] or 0) > 0

        if (not mission and not onCooldown) or (onCooldown and not isActive) then
            local pulse = 0.5 + 0.5 * math.sin(pulseTime)

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

            local labelZ   = adaptiveLabelZ(mp.pos, playerPos, BEACON_ABOVE)
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
                elseif mtype == RALLY then
                    local idx   = mission.rallyCurrentIdx or 1
                    local total = mission.rallyWaypoints and #mission.rallyWaypoints or 0
                    label = string.format("%s  CP %d/%d  [%ds]", mp.name,
                        idx, total, math.max(0, math.ceil(mission.rallyTimeLeft or 0)))
                elseif mtype == RACE then
                    local idx   = mission.rallyCurrentIdx or 1
                    local total = mission.rallyWaypoints and #mission.rallyWaypoints or 0
                    label = string.format("%s  CP %d/%d  [RACE]", mp.name, idx, total)
                elseif mtype == CRUISE then
                    local dDist = mp.destPos and playerPos and playerPos:distance(mp.destPos)
                    label = string.format("%s  dest:%s  [%ds]", mp.name,
                        dDist and string.format("%dm", math.floor(dDist)) or "??",
                        math.max(0, math.ceil(CRUISE_TIME_LIMIT - mission.timer)))
                else
                    label = mp.name
                end
            elseif onCooldown then
                label = string.format("%s  (CD: %ds)", mp.name,
                    math.ceil(missionCooldowns[mp.name]))
            else
                local typeTags = {
                    chase="CHASE", escape="ESCAPE", follow="FOLLOW",
                    endure="ENDURE", reach="REACH", rally="RALLY", race="RACE", cruise="CRUISE",
                }
                label = string.format("[%s]  %s", typeTags[mp.type] or "?", missionDisplayName(mp))
            end

            debugDrawer:drawTextAdvanced(labelPos, label,
                ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 140))
        end
    end

    if mission and (mission.point.type == REACH or mission.point.type == CRUISE)
       and mission.point.destPos then
        local pulse = 0.5 + 0.5 * math.sin(pulseTime * 1.5)
        drawDestBeacon(mission.point.destPos, pulse)

        local dp     = mission.point.destPos
        local dLabel = vec3(dp.x, dp.y, adaptiveLabelZ(dp, playerPos, DEST_BEACON_ABOVE))
        debugDrawer:drawTextAdvanced(dLabel, "[ DESTINATION ]",
            ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 80, 160))
    end

    if mission and (mission.point.type == RALLY or mission.point.type == RACE) and mission.rallyWaypoints then
        local idx = mission.rallyCurrentIdx or 1
        local wp  = mission.rallyWaypoints[idx]
        if wp then
            local pulse = 0.5 + 0.5 * math.sin(pulseTime * 2.0)
            drawDestBeacon(wp, pulse)
            local wLabel = vec3(wp.x, wp.y, adaptiveLabelZ(wp, playerPos, DEST_BEACON_ABOVE))
            debugDrawer:drawTextAdvanced(wLabel,
                string.format("[ CP %d/%d ]", idx, #mission.rallyWaypoints),
                ColorF(1, 1, 0.6, 1), true, false, ColorI(40, 30, 0, 160))
        end
    end
end

function M._frameOps.tryStartNearbyMission(playerPos)
    if mission or not playerPos then return end

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

function M._frameOps.updateActiveMission(dt, playerPos)
    if not mission then return false end

    if mission.starting or not mission.started then
        drawJonesingUI()
        return true
    end

    mission.timer = mission.timer + dt
    local mtype   = mission.point.type

    if wantedLevelForMission and wantedLevelForMission(mtype) > 0 and mtype ~= ESCAPE then
        tickTeleportPolice(playerPos, dt)
    end
    if tickPoliceBustedFail(playerPos, dt) then
        cleanupMission(false, "Busted — immobilized with police close by!")
        return true
    end

    if tickPlayerDamage(dt) then
        cleanupMission(false, "Your vehicle was wrecked!")
        return true
    end

    if (not isMissionUpdateBlocked()) and im and im.IsKeyPressed and im.IsKeyPressed(im.Key_Backspace) then
        cleanupMission(false, "Mission aborted by player.")
        return true
    end

    if mtype == CHASE then
        tickChaseTargetSpeed(dt)
        local tDist = getTargetDist(playerPos)
        if tDist and tDist > CHASE_ESCAPE_DISTANCE then
            cleanupMission(false, "The target got away!")
            return true
        end
        if checkChaseSuccess() then
            cleanupMission(true)
        end

    elseif mtype == ESCAPE then
        if mission.timer >= ESCAPE_TIME_LIMIT then
            cleanupMission(false, "Time's up — you didn't shake them!")
            return true
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
            return true
        end

    elseif mtype == ENDURE then
        if tickPlayerDamage(dt) then
            cleanupMission(false, "Your vehicle was wrecked — you didn't survive!")
            return true
        end
        tickTeleportPolice(playerPos, dt)
        if mission and mission.timer >= ENDURE_TIME_LIMIT then
            cleanupMission(true)
        end

    elseif mtype == REACH then
        if tickPlayerDamage(dt) then
            cleanupMission(false, "Your vehicle was destroyed before reaching the destination!")
            return true
        end
        tickTeleportPolice(playerPos, dt)
        if mission.timer >= REACH_TIME_LIMIT then
            cleanupMission(false, "Time's up — didn't reach the destination!")
            return true
        end
        if playerPos and mission.point.destPos then
            local dx = playerPos.x - mission.point.destPos.x
            local dy = playerPos.y - mission.point.destPos.y
            if dx * dx + dy * dy <= REACH_RADIUS * REACH_RADIUS then
                cleanupMission(true)
            end
        end

    elseif mtype == RALLY then
        mission.rallyTimeLeft = (mission.rallyTimeLeft or RALLY_BASE_TIME) - dt
        if mission.rallyTimeLeft <= 0 then
            cleanupMission(false, "Time's up — you didn't reach the next checkpoint!")
            return true
        end
        if playerPos and mission.rallyWaypoints then
            local idx = mission.rallyCurrentIdx or 1
            local wp  = mission.rallyWaypoints[idx]
            if wp then
                local dx = playerPos.x - wp.x
                local dy = playerPos.y - wp.y
                if dx * dx + dy * dy <= RALLY_CHECKPOINT_RADIUS * RALLY_CHECKPOINT_RADIUS then
                    local total = #mission.rallyWaypoints
                    if idx >= total then
                        cleanupMission(true)
                    else
                        mission.rallyCurrentIdx = idx + 1
                        mission.rallyTimeLeft   = (mission.rallyTimeLeft or 0) + RALLY_BONUS_TIME
                        notify("info", "Checkpoint!",
                            string.format("Checkpoint %d/%d reached! +%ds — keep going!",
                                idx, total, RALLY_BONUS_TIME))
                    end
                end
            end
        end

    elseif mtype == RACE then
        if mission.raceRacers then
            for vid, state in pairs(mission.raceRacers) do
                if not state.finished then
                    local v = be:getObjectByID(vid)
                    if v then
                        local idx = state.idx or 1
                        local wp = mission.rallyWaypoints and mission.rallyWaypoints[idx]
                        if wp then
                            state.aiRefreshTimer = math.max(0, state.aiRefreshTimer - dt)
                            if state.lastAiTargetIdx ~= idx or state.aiRefreshTimer <= 0 then
                                moveRaceBaitToWaypoint(state.baitId, wp)
                                queueRaceChaseBaitAI(v, state.baitId)
                                state.lastAiTargetIdx = idx
                                state.aiRefreshTimer = RACE_AI_REFRESH_INTERVAL
                            end
                            local pos = v:getPosition()
                            local dx = pos.x - wp.x
                            local dy = pos.y - wp.y
                            if dx * dx + dy * dy <= RACE_CHECKPOINT_RADIUS * RACE_CHECKPOINT_RADIUS then
                                if idx >= #mission.rallyWaypoints then
                                    state.finished = true
                                    cleanupMission(false, "A rival racer reached the finish line first!")
                                    return true
                                else
                                    state.idx = idx + 1
                                    state.lastAiTargetIdx = 0
                                    state.aiRefreshTimer = 0
                                    local nextWp = mission.rallyWaypoints[state.idx]
                                    if nextWp then
                                        moveRaceBaitToWaypoint(state.baitId, nextWp)
                                        queueRaceChaseBaitAI(v, state.baitId)
                                        state.lastAiTargetIdx = state.idx
                                        state.aiRefreshTimer = RACE_AI_REFRESH_INTERVAL
                                    end
                                end
                            end
                        end
                    else
                        state.finished = true
                    end
                end
            end
        end

        if playerPos and mission.rallyWaypoints then
            local idx = mission.rallyCurrentIdx or 1
            local wp  = mission.rallyWaypoints[idx]
            if wp then
                local dx = playerPos.x - wp.x
                local dy = playerPos.y - wp.y
                if dx * dx + dy * dy <= RACE_CHECKPOINT_RADIUS * RACE_CHECKPOINT_RADIUS then
                    local total = #mission.rallyWaypoints
                    if idx >= total then
                        cleanupMission(true)
                    else
                        mission.rallyCurrentIdx = idx + 1
                        notify("info", "Checkpoint!",
                            string.format("Checkpoint %d/%d reached — stay ahead!", idx, total))
                    end
                end
            end
        end

    elseif mtype == CRUISE then
        if mission.timer >= CRUISE_TIME_LIMIT then
            cleanupMission(false, "Time's up — you didn't reach the destination!")
            return true
        end
        if playerPos and mission.point.destPos then
            local dx = playerPos.x - mission.point.destPos.x
            local dy = playerPos.y - mission.point.destPos.y
            if dx * dx + dy * dy <= CRUISE_RADIUS * CRUISE_RADIUS then
                cleanupMission(true)
            end
        end
    end

    return false
end

-- ── Per-frame update ───────────────────────────────────────────────────────────
function M.onUpdate(dt, dtSim)
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
            return  -- defer all mission updates until positions are ready
        end
    end

    local rawDt = dt or 0
    local simDt = getSafeMissionDt(rawDt, dtSim)
    dt = simDt

    pulseTime = pulseTime + rawDt * PULSE_SPEED

    -- Resolve player position once per frame.  May be nil (spectator mode, etc.).
    local playerPos = getPlayerPos()

    if focusReturnTimer and focusReturnTimer > 0 then
        focusReturnTimer = math.max(0, focusReturnTimer - dt)
        forcePlayerFocus()
    end

    if loaderHideTimer and loaderHideTimer > 0 then
        loaderHideTimer = math.max(0, loaderHideTimer - rawDt)
        if loaderHideTimer <= 0 and guihooks then
            guihooks.trigger('setLoading', { loading = false }); loaderActive = false
        end
    end

    if bigBannerTimer and bigBannerTimer > 0 then
        bigBannerTimer = math.max(0, bigBannerTimer - rawDt)
        if bigBannerTimer <= 0 then bigBannerText = "" end
    end

    if tickPendingMissionStart(dt, playerPos) then
        drawJonesingUI()
        return
    end

    M._frameOps.tickMissionCooldowns(dt)
    M._frameOps.drawMissionMarkers(playerPos)
    if isMissionUpdateBlocked() then
        return
    end
    M._frameOps.tryStartNearbyMission(playerPos)
    if M._frameOps.updateActiveMission(dt, playerPos) then
        return
    end

    showMissionHudMessage(dt, playerPos)

    -- Draw ImGui HUD/radar/banner/loader
    drawTargetArrows(playerPos)
    drawJonesingUI()
end

-- ── Extension hooks ────────────────────────────────────────────────────────────
function onExtensionLoaded()
    loadAutosave()
    initialized = false
    initTimer = 0
    log("I", "jonesingMissions",
        "Jonesing GTA-like Mission System loaded — " .. #missionTemplates .. " total templates registered; runtime tiers enabled.")
end

function onExtensionUnloaded()
    saveAutosave("extension_unload")
    cleanupMission(false)
    log("I", "jonesingMissions", "Jonesing Mission System unloaded.")
end

-- Do not export drawJonesingUI as onGui; onUpdate already draws it. Exporting both can make BeamNG treat HP/radar like separate app windows.
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

function M.setPlayerBodyHealth(percent)
    return false
end

function M.resetPlayerBodyHealth()
    return false
end

function M.reportDriverSeatCrush(severity)
    return false
end

function M.saveAutosave()
    return saveAutosave("manual_save")
end

function M.loadAutosave()
    local loaded = loadAutosave()
    initialized = false
    initTimer = 0
    return loaded
end

return M
