--[[
    konstant a*  //  universal waypoint auto-driver
    record a path by driving it. save it. let the script drive it back.
    v1.0
]]

-- ============================================================
-- // cleanup guard (kill previous instance)
-- ============================================================
if _G.KAStarCleanup then
    pcall(_G.KAStarCleanup)
    _G.KAStarCleanup = nil
    task.wait(0.1)
end

-- ============================================================
-- // services
-- ============================================================
local Players            = game:GetService('Players')
local RunService         = game:GetService('RunService')
local TweenService       = game:GetService('TweenService')
local UserInputService   = game:GetService('UserInputService')
local HttpService        = game:GetService('HttpService')
local CoreGui            = game:GetService('CoreGui')
local MarketplaceService = game:GetService('MarketplaceService')

local VIM
pcall(function() VIM = game:GetService('VirtualInputManager') end)

local plr = Players.LocalPlayer

-- ============================================================
-- // config
-- ============================================================
local SAMPLE_DIST     = 0.75      -- studs between recorded samples
local SEG_WIDTH       = 0.45      -- path visual width
local SEG_HEIGHT      = 0.08      -- path visual thickness
local REWIND_RATE     = 26        -- samples per second while rewinding
local GHOST_EAT_DIST  = 6         -- new path eats red ghost segs within this
local LOOKAHEAD_MIN   = 10
local LOOKAHEAD_MAX   = 26
local OFFPATH_SOFT    = 12        -- studs: recovery mode
local OFFPATH_HARD    = 40        -- studs: abort
local ARRIVE_DIST     = 10
local OBST_TICK       = 0.12      -- obstacle scan interval
local OBST_CORRIDOR   = 4.5       -- lateral tolerance for "actually blocking"
local OBST_CLEAR_TIME = 0.5       -- rays must be clear this long to resume
local LEARN_ERR       = 6         -- bucket error above this = learn
local LEARN_FACTOR    = 0.90      -- speed factor applied per bad run
local LEARN_MIN       = 0.5
local BUCKET_SIZE     = 10        -- samples per learning bucket
local ROOT_FOLDER     = 'KonstantAStar'

-- ============================================================
-- // palette (konstant black/white)
-- ============================================================
local C = {
    BG0     = Color3.fromRGB(9, 9, 9),
    BG1     = Color3.fromRGB(15, 15, 15),
    BG2     = Color3.fromRGB(22, 22, 22),
    BG3     = Color3.fromRGB(30, 30, 30),
    BORDER  = Color3.fromRGB(42, 42, 42),
    BORDER2 = Color3.fromRGB(70, 70, 70),
    TEXT    = Color3.fromRGB(236, 236, 236),
    MUT     = Color3.fromRGB(138, 138, 138),
    DIM     = Color3.fromRGB(85, 85, 85),
    WHITE   = Color3.fromRGB(255, 255, 255),
    RED     = Color3.fromRGB(255, 82, 82),
    GREEN   = Color3.fromRGB(90, 255, 130),
    YELLOW  = Color3.fromRGB(255, 220, 90),
    PLAY    = Color3.fromRGB(240, 240, 240), -- playback path = white
}
local FONT  = Enum.Font.Code
local FONTB = Enum.Font.Code

-- ============================================================
-- // state
-- ============================================================
local S = {
    mode        = 'idle',   -- idle | recording | rewinding | playing
    samples     = {},       -- { {p=Vector3, s=number, n=Vector3} }
    segs        = {},       -- seg parts indexed by sample idx (seg i connects i -> i+1)
    ghosts      = {},       -- { {part=Part, pos=Vector3} } red overwritten segs
    dirty       = false,    -- ever rewound this session -> new segs yellow
    recStart    = 0,
    recDist     = 0,
    playData    = nil,      -- loaded path table during playback
    playFile    = nil,      -- filename during playback
    playIdx     = 1,        -- closest sample index
    playStart   = 0,
    driveMode   = 'seat',   -- seat | vim
    invertSteer = false,
    speedMult   = 1.0,
    blocked     = nil,      -- {name=, class=, since=}
    clearSince  = nil,
    stuckSince  = nil,
    bucketErr   = {},       -- bucket -> max cross-track error this run
    selFile     = nil,      -- selected file in load tab
    conns       = {},
    vimKeys     = {},       -- KeyCode -> bool currently pressed
}

local function bind(conn) table.insert(S.conns, conn) return conn end

-- ============================================================
-- // small helpers
-- ============================================================
local function char()  return plr.Character end
local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass('Humanoid')
end
local function hrp()
    local c = char()
    return c and c:FindFirstChild('HumanoidRootPart')
end
local function seat()
    local h = hum()
    return h and h.SeatPart
end
local function vehicleModel()
    local sp = seat()
    if not sp then return nil end
    local m, top = sp.Parent, nil
    while m and m ~= workspace do
        if m:IsA('Model') then top = m end
        m = m.Parent
    end
    return top
end
local function fmtTime(t)
    t = math.max(0, math.floor(t))
    return string.format('%02d:%02d', math.floor(t / 60), t % 60)
end
local function fmtDist(d)
    if d >= 1000 then return string.format('%.2f km', d / 1000 * 0.28) end
    return string.format('%d studs', math.floor(d))
end
local function mph(v) return math.floor(v * 0.625) end
local function sanitize(name)
    name = name:gsub('[^%w%-%_ ]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return #name > 0 and name or nil
end

-- ============================================================
-- // file io
-- ============================================================
local FS = {
    ok = (typeof(writefile) == 'function' and typeof(readfile) == 'function'
          and typeof(listfiles) == 'function' and typeof(isfolder) == 'function'
          and typeof(makefolder) == 'function'),
}
local gameFolder = ROOT_FOLDER .. '/' .. tostring(game.PlaceId)

function FS.ensure()
    if not FS.ok then return false end
    pcall(function()
        if not isfolder(ROOT_FOLDER) then makefolder(ROOT_FOLDER) end
        if not isfolder(gameFolder) then makefolder(gameFolder) end
    end)
    return true
end

function FS.save(name, data)
    if not FS.ensure() then return false end
    local ok = pcall(function()
        writefile(gameFolder .. '/' .. name .. '.json', HttpService:JSONEncode(data))
    end)
    return ok
end

function FS.load(fileName)
    if not FS.ok then return nil end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(fileName))
    end)
    return ok and data or nil
end

function FS.list()
    if not FS.ensure() then return {} end
    local out = {}
    pcall(function()
        for _, f in ipairs(listfiles(gameFolder)) do
            if f:sub(-5) == '.json' then
                local data = FS.load(f)
                if data and data.points then
                    table.insert(out, { file = f, data = data })
                end
            end
        end
    end)
    table.sort(out, function(a, b) return (a.data.name or '') < (b.data.name or '') end)
    return out
end

function FS.delete(fileName)
    pcall(function() delfile(fileName) end)
end

local gameName = 'this game'
pcall(function()
    gameName = MarketplaceService:GetProductInfo(game.PlaceId).Name
end)

-- ============================================================
-- // path visuals
-- ============================================================
local pathFolder = Instance.new('Folder')
pathFolder.Name = 'KAStarPath'
pathFolder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshRayFilter(extra)
    local list = { pathFolder }
    if char() then table.insert(list, char()) end
    local vm = vehicleModel()
    if vm then table.insert(list, vm) end
    if extra then for _, e in ipairs(extra) do table.insert(list, e) end end
    rayParams.FilterDescendantsInstances = list
end

local function groundSnap(pos)
    refreshRayFilter()
    local r = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), rayParams)
    if r then return r.Position, r.Normal end
    return pos, Vector3.new(0, 1, 0)
end

local function makeSeg(p1, p2, color, parent)
    local dist = (p2 - p1).Magnitude
    if dist < 0.05 then return nil end
    local part = Instance.new('Part')
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = 0.25
    part.Size = Vector3.new(SEG_WIDTH, SEG_HEIGHT, dist + 0.1)
    part.CFrame = CFrame.lookAt((p1 + p2) / 2 + Vector3.new(0, SEG_HEIGHT, 0), p2 + Vector3.new(0, SEG_HEIGHT, 0))
    part.Parent = parent or pathFolder
    return part
end

local function clearSegs()
    for _, s in pairs(S.segs) do if s then pcall(function() s:Destroy() end) end end
    S.segs = {}
end

local function clearGhosts()
    for _, g in ipairs(S.ghosts) do pcall(function() g.part:Destroy() end) end
    S.ghosts = {}
end

local playFolder = Instance.new('Folder')
playFolder.Name = 'KAStarPlayPath'
playFolder.Parent = workspace
local function clearPlayPath()
    for _, c in ipairs(playFolder:GetChildren()) do c:Destroy() end
end

-- ============================================================
-- // ui bootstrap (helpers)
-- ============================================================
local gui = Instance.new('ScreenGui')
gui.Name = 'KonstantAStarGui'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = plr:WaitForChild('PlayerGui') end

local function new(cls, props, kids)
    local o = Instance.new(cls)
    for k, v in pairs(props or {}) do
        if k ~= 'Parent' then o[k] = v end
    end
    for _, kid in ipairs(kids or {}) do kid.Parent = o end
    if props and props.Parent then o.Parent = props.Parent end
    return o
end

local function stroke(color, thick)
    return new('UIStroke', { Color = color or C.BORDER, Thickness = thick or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function corner(r)
    return new('UICorner', { CornerRadius = UDim.new(0, r or 4) })
end
local function vgradient(top, bottom)
    return new('UIGradient', {
        Rotation = 90,
        Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(1, bottom) }),
    })
end
local function tw(o, props, t, style)
    local tween = TweenService:Create(o, TweenInfo.new(t or 0.22, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props)
    tween:Play()
    return tween
end
local function hoverable(btn, base, hot)
    btn.MouseEnter:Connect(function() tw(btn, { BackgroundColor3 = hot }, 0.12) end)
    btn.MouseLeave:Connect(function() tw(btn, { BackgroundColor3 = base }, 0.18) end)
end

-- // toast system
local toastHolder = new('Frame', {
    Name = 'Toasts', BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -14, 1, -14),
    Size = UDim2.new(0, 300, 0, 400),
    Parent = gui,
}, {
    new('UIListLayout', { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local function toast(msg, accent)
    local t = new('Frame', {
        BackgroundColor3 = C.BG1, Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1, Parent = toastHolder,
    }, {
        corner(4), stroke(C.BORDER),
        new('Frame', { BackgroundColor3 = accent or C.WHITE, Size = UDim2.new(0, 2, 1, -10), Position = UDim2.new(0, 5, 0, 5), BorderSizePixel = 0 }),
        new('TextLabel', {
            BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.TEXT,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(1, -22, 1, 0),
            Text = string.lower(tostring(msg)), TextTransparency = 1,
        }),
    })
    local lbl = t:FindFirstChildOfClass('TextLabel')
    tw(t, { BackgroundTransparency = 0.08 }, 0.2)
    tw(lbl, { TextTransparency = 0 }, 0.2)
    task.delay(3.2, function()
        tw(t, { BackgroundTransparency = 1 }, 0.3)
        tw(lbl, { TextTransparency = 1 }, 0.3)
        task.delay(0.35, function() t:Destroy() end)
    end)
end

-- ============================================================
-- // forward declarations (ui <-> logic cross refs)
-- ============================================================
local openOverlay, closeOverlay, showSaveDialog, refreshLoadList
local showRecordHUD, hideRecordHUD, showPlayHUD, hidePlayHUD
local setRecStatus, setPlayStatus
local startRecording, endRecording, startPlayback, stopPlayback

-- ============================================================
-- // recorder
-- ============================================================
local recConn, rewindHeld

function startRecording()
    if S.mode ~= 'idle' then return end
    local root = hrp()
    if not root then toast('no character found', C.RED) return end

    S.mode = 'recording'
    S.samples = {}
    S.ghosts = {}
    S.dirty = false
    S.recDist = 0
    S.recStart = os.clock()
    clearSegs()

    local gp, gn = groundSnap(root.Position)
    table.insert(S.samples, { p = gp, s = 0, n = gn })

    recConn = bind(RunService.Heartbeat:Connect(function()
        if S.mode ~= 'recording' then return end
        local r = hrp()
        if not r then return end
        local last = S.samples[#S.samples]
        local flat = r.Position
        if (flat - last.p).Magnitude < SAMPLE_DIST then return end

        local gp2, gn2 = groundSnap(r.Position)
        local spd = r.AssemblyLinearVelocity.Magnitude
        local sp = seat()
        if sp then spd = sp.AssemblyLinearVelocity.Magnitude end

        table.insert(S.samples, { p = gp2, s = spd, n = gn2 })
        local i = #S.samples - 1
        S.recDist = S.recDist + (gp2 - last.p).Magnitude
        S.segs[i] = makeSeg(last.p, gp2, S.dirty and C.YELLOW or C.GREEN)

        -- eat red ghosts the new path passes over
        if #S.ghosts > 0 then
            for gi = #S.ghosts, 1, -1 do
                if (S.ghosts[gi].pos - gp2).Magnitude < GHOST_EAT_DIST then
                    pcall(function() S.ghosts[gi].part:Destroy() end)
                    table.remove(S.ghosts, gi)
                end
            end
        end
    end))

    closeOverlay()
    showRecordHUD()
    toast('recording path — drive to your destination', C.GREEN)
end

-- rewind: hold to walk backwards through samples, popping them into ghosts
local function rewindStep(dt)
    local n = #S.samples
    if n <= 2 then return end
    local pop = math.max(1, math.floor(REWIND_RATE * dt))
    for _ = 1, pop do
        n = #S.samples
        if n <= 2 then break end
        -- seg n-1 connects sample n-1 -> n; it becomes a ghost
        local segIdx = n - 1
        local sSeg = S.segs[segIdx]
        if sSeg then
            sSeg.Color = C.RED
            table.insert(S.ghosts, { part = sSeg, pos = S.samples[n].p })
            S.segs[segIdx] = nil
        end
        S.recDist = math.max(0, S.recDist - (S.samples[n].p - S.samples[n - 1].p).Magnitude)
        table.remove(S.samples, n)
    end
    S.dirty = true
    -- teleport player/vehicle to the new tail
    local tail = S.samples[#S.samples]
    local vm = vehicleModel()
    if vm then
        local pivot = vm:GetPivot()
        vm:PivotTo(CFrame.new(tail.p + Vector3.new(0, 3, 0)) * (pivot - pivot.Position))
        for _, p in ipairs(vm:GetDescendants()) do
            if p:IsA('BasePart') then
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    else
        local r = hrp()
        if r then
            r.CFrame = CFrame.new(tail.p + Vector3.new(0, 3.5, 0)) * (r.CFrame - r.CFrame.Position)
            r.AssemblyLinearVelocity = Vector3.zero
        end
    end
end

local rewindConn
local function setRewind(held)
    rewindHeld = held
    if held and S.mode == 'recording' then
        S.mode = 'rewinding'
        if rewindConn then rewindConn:Disconnect() end
        rewindConn = bind(RunService.Heartbeat:Connect(function(dt)
            if rewindHeld and S.mode == 'rewinding' then rewindStep(dt) end
        end))
    elseif not held and S.mode == 'rewinding' then
        if rewindConn then rewindConn:Disconnect() rewindConn = nil end
        S.mode = 'recording'
    end
end

function endRecording()
    if S.mode ~= 'recording' and S.mode ~= 'rewinding' then return end
    if rewindConn then rewindConn:Disconnect() rewindConn = nil end
    if recConn then recConn:Disconnect() recConn = nil end
    S.mode = 'idle'
    hideRecordHUD()
    if #S.samples < 8 then
        toast('path too short — discarded', C.RED)
        clearSegs()
        clearGhosts()
        return
    end
    showSaveDialog()
end

local function discardRecording()
    clearSegs()
    clearGhosts()
    S.samples = {}
    toast('path discarded', C.MUT)
end

local function saveRecording(name)
    name = sanitize(name)
    if not name then toast('give the path a name first', C.RED) return false end
    if not FS.ok then toast('executor has no file api — cannot save', C.RED) return false end

    local pts = {}
    for _, s in ipairs(S.samples) do
        table.insert(pts, { s.p.X, s.p.Y, s.p.Z, math.floor(s.s * 10) / 10 })
    end
    local data = {
        name = name,
        placeId = game.PlaceId,
        game = gameName,
        created = os.date('%Y-%m-%d %H:%M'),
        distance = math.floor(S.recDist),
        runs = 0,
        learned = {},
        points = pts,
    }
    if FS.save(name, data) then
        toast('saved "' .. name .. '" — ' .. fmtDist(S.recDist), C.GREEN)
        clearSegs()
        clearGhosts()
        S.samples = {}
        refreshLoadList()
        return true
    end
    toast('save failed', C.RED)
    return false
end

-- ============================================================
-- // vim key control
-- ============================================================
local function vimKey(kc, down)
    if not VIM then return end
    if S.vimKeys[kc] == down then return end
    S.vimKeys[kc] = down
    pcall(function() VIM:SendKeyEvent(down, kc, false, game) end)
end
local function vimRelease()
    for kc, down in pairs(S.vimKeys) do
        if down then vimKey(kc, false) end
    end
end
local function applyDrive(throttle, steer)
    if S.invertSteer then steer = -steer end
    local sp = seat()
    if S.driveMode == 'seat' and sp and sp:IsA('VehicleSeat') then
        pcall(function()
            sp.ThrottleFloat = throttle
            sp.SteerFloat = steer
            sp.Throttle = throttle > 0.15 and 1 or (throttle < -0.15 and -1 or 0)
            sp.Steer = steer > 0.3 and 1 or (steer < -0.3 and -1 or 0)
        end)
    else
        vimKey(Enum.KeyCode.W, throttle > 0.15)
        vimKey(Enum.KeyCode.S, throttle < -0.15)
        vimKey(Enum.KeyCode.D, steer > 0.35)
        vimKey(Enum.KeyCode.A, steer < -0.35)
    end
end
local function releaseDrive()
    local sp = seat()
    if sp and sp:IsA('VehicleSeat') then
        pcall(function()
            sp.ThrottleFloat = 0; sp.SteerFloat = 0
            sp.Throttle = 0; sp.Steer = 0
        end)
    end
    vimRelease()
end

-- ============================================================
-- // obstacle detection (brake-and-wait)
-- ============================================================
local classCache = {}
local function classifyBlocker(inst)
    if classCache[inst] ~= nil then return classCache[inst] end
    local m = inst
    local class = 'static'
    while m and m ~= workspace do
        if m:IsA('Model') then
            if m:FindFirstChildOfClass('Humanoid') or m:FindFirstChildWhichIsA('VehicleSeat', true)
               or Players:GetPlayerFromCharacter(m) then
                class = 'traffic'
                break
            end
        end
        m = m.Parent
    end
    classCache[inst] = class
    task.delay(10, function() classCache[inst] = nil end)
    return class
end

-- returns blocking hit or nil. pts = path points, idx = current closest index
local function scanAhead(sp, pts, idx)
    local spd = sp.AssemblyLinearVelocity.Magnitude
    local range = math.clamp(spd * 1.4, 14, 70)
    local fwd = sp.CFrame.LookVector
    local vel = sp.AssemblyLinearVelocity
    if vel.Magnitude > 4 then fwd = vel.Unit end
    local right = sp.CFrame.RightVector
    local origin = sp.Position + Vector3.new(0, 2, 0)

    refreshRayFilter({ playFolder })
    for _, off in ipairs({ 0, 1.6, -1.6 }) do
        local r = workspace:Raycast(origin + right * off, fwd * range, rayParams)
        -- normal.Y > 0.6 = ground/slope, not a wall or object -- ignore
        if r and r.Instance and r.Instance.CanCollide and r.Normal.Y <= 0.6 then
            -- stage 2: does the hit actually sit in the path corridor ahead?
            local hitP = r.Position
            local minLat = math.huge
            local hi = math.min(#pts, idx + 90)
            for i = idx, hi do
                local d = (Vector3.new(pts[i][1], 0, pts[i][3]) - Vector3.new(hitP.X, 0, hitP.Z)).Magnitude
                if d < minLat then minLat = d end
            end
            if minLat < OBST_CORRIDOR then
                return r.Instance
            end
        end
    end
    return nil
end

-- ============================================================
-- // playback (pure pursuit + learning)
-- ============================================================
local playConn, obstAcc

local function closestIdx(pts, from, pos)
    local best, bestD = from, math.huge
    local lo = math.max(1, from - 20)
    local hi = math.min(#pts, from + 80)
    for i = lo, hi do
        local d = (Vector3.new(pts[i][1], pts[i][2], pts[i][3]) - pos).Magnitude
        if d < bestD then bestD = d; best = i end
    end
    return best, bestD
end

local function lookaheadPoint(pts, idx, dist)
    local acc = 0
    for i = idx, #pts - 1 do
        local a = Vector3.new(pts[i][1], pts[i][2], pts[i][3])
        local b = Vector3.new(pts[i + 1][1], pts[i + 1][2], pts[i + 1][3])
        acc = acc + (b - a).Magnitude
        if acc >= dist then return b, i + 1 end
    end
    local last = pts[#pts]
    return Vector3.new(last[1], last[2], last[3]), #pts
end

local function drawPlayPath(pts)
    clearPlayPath()
    -- draw every other segment to keep part count sane on long paths
    for i = 1, #pts - 2, 2 do
        local a = Vector3.new(pts[i][1], pts[i][2], pts[i][3])
        local b = Vector3.new(pts[i + 2][1], pts[i + 2][2], pts[i + 2][3])
        local seg = makeSeg(a, b, C.PLAY, playFolder)
        if seg then seg.Transparency = 0.55 end
    end
end

function startPlayback(entry)
    if S.mode ~= 'idle' then toast('busy — end the current session first', C.RED) return end
    local h = hum()
    local sp = seat()
    if not h or not sp then
        toast('sit in a vehicle first', C.RED)
        return
    end
    local data = entry.data
    local pts = data.points
    if not pts or #pts < 8 then toast('path file is empty or corrupt', C.RED) return end

    -- must start near the path
    local here = sp.Position
    local startIdx, startDist = 1, math.huge
    for i = 1, #pts, 4 do
        local d = (Vector3.new(pts[i][1], pts[i][2], pts[i][3]) - here).Magnitude
        if d < startDist then startDist = d; startIdx = i end
    end
    if startDist > OFFPATH_HARD then
        toast('too far from the path (' .. math.floor(startDist) .. ' studs) — get closer', C.RED)
        return
    end

    S.mode = 'playing'
    S.playData = data
    S.playFile = entry.file
    S.playIdx = startIdx
    S.playStart = os.clock()
    S.driveMode = 'seat'
    S.blocked = nil
    S.clearSince = nil
    S.stuckSince = nil
    S.bucketErr = {}
    obstAcc = 0

    -- total remaining distance for eta
    local totalDist = 0
    for i = startIdx, #pts - 1 do
        totalDist = totalDist + (Vector3.new(pts[i + 1][1], pts[i + 1][2], pts[i + 1][3])
                               - Vector3.new(pts[i][1], pts[i][2], pts[i][3])).Magnitude
    end

    drawPlayPath(pts)
    closeOverlay()
    showPlayHUD(data.name)
    toast('driving "' .. tostring(data.name) .. '" — ' .. fmtDist(totalDist), C.GREEN)

    local lastMoveCheck, stuckT = os.clock(), 0

    playConn = bind(RunService.Heartbeat:Connect(function(dt)
        if S.mode ~= 'playing' then return end
        local sp2 = seat()
        if not sp2 then
            stopPlayback('you left the vehicle')
            return
        end

        local pos = sp2.Position
        local spd = sp2.AssemblyLinearVelocity.Magnitude
        local idx, err = closestIdx(pts, S.playIdx, pos)
        S.playIdx = idx

        -- learning: track worst cross-track error per bucket
        local bucket = tostring(math.floor(idx / BUCKET_SIZE))
        if not S.bucketErr[bucket] or err > S.bucketErr[bucket] then
            S.bucketErr[bucket] = err
        end

        -- arrival check
        local last = pts[#pts]
        local dEnd = (Vector3.new(last[1], last[2], last[3]) - pos).Magnitude
        if idx >= #pts - 3 and dEnd < ARRIVE_DIST then
            stopPlayback(nil, true)
            return
        end

        -- hard off-path abort
        if err > OFFPATH_HARD then
            stopPlayback('lost the path (' .. math.floor(err) .. ' studs off)')
            return
        end

        -- obstacle scan on a slow tick
        obstAcc = obstAcc + dt
        if obstAcc >= OBST_TICK then
            obstAcc = 0
            local blocker = scanAhead(sp2, pts, idx)
            if blocker then
                S.clearSince = nil
                if not S.blocked or S.blocked.inst ~= blocker then
                    S.blocked = {
                        inst = blocker,
                        name = blocker.Name,
                        class = classifyBlocker(blocker),
                        since = os.clock(),
                    }
                end
            elseif S.blocked then
                S.clearSince = S.clearSince or os.clock()
                if os.clock() - S.clearSince >= OBST_CLEAR_TIME then
                    S.blocked = nil
                    S.clearSince = nil
                end
            end
        end

        -- blocked: brake to a stop and hold
        if S.blocked then
            if spd > 1.5 then
                applyDrive(-1, 0)
            else
                applyDrive(0, 0)
            end
            setPlayStatus('waiting — ' .. string.lower(S.blocked.name)
                .. (S.blocked.class == 'traffic' and ' [traffic]' or ' [static]'), idx, #pts, spd, pts)
            if S.blocked.class == 'static' and os.clock() - S.blocked.since > 15 then
                toast('blocked 15s+ by static geometry — path may be stale', C.YELLOW)
                S.blocked.since = os.clock() -- don't spam
            end
            return
        end

        -- pure pursuit steering
        local L = math.clamp(LOOKAHEAD_MIN + spd * 0.30, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
        local target = lookaheadPoint(pts, idx, L)
        local rel = sp2.CFrame:PointToObjectSpace(target)
        local angle = math.atan2(rel.X, -rel.Z)
        local steer = math.clamp(angle / math.rad(30), -1, 1)

        -- target speed: recorded profile x multiplier x learned factor, curve slowdown
        local recSpd = pts[math.min(idx + 4, #pts)][4] or 16
        local learned = (S.playData.learned and S.playData.learned[bucket]) or 1
        local curveCut = 1 - math.min(math.abs(angle) / math.rad(60), 1) * 0.5
        local targetSpd = math.max(6, recSpd * S.speedMult * learned * curveCut)

        -- recovery mode: too far off line
        if err > OFFPATH_SOFT then
            targetSpd = math.min(targetSpd, 10)
            steer = math.clamp(steer * 1.6, -1, 1)
        end

        local throttle = math.clamp((targetSpd - spd) / 8, -1, 1)
        applyDrive(throttle, steer)

        -- stuck detection -> vim fallback
        if throttle > 0.7 and spd < 1.5 then
            stuckT = stuckT + dt
            if stuckT > 2 and S.driveMode == 'seat' then
                S.driveMode = 'vim'
                stuckT = 0
                toast('seat control not moving vehicle — switching to key simulation', C.YELLOW)
            elseif stuckT > 6 then
                stuckT = 0
                toast('vehicle appears stuck', C.YELLOW)
            end
        else
            stuckT = 0
        end

        setPlayStatus(nil, idx, #pts, spd, pts)
    end))
end

function stopPlayback(reason, arrived)
    if S.mode ~= 'playing' then return end
    S.mode = 'idle'
    if playConn then playConn:Disconnect() playConn = nil end
    releaseDrive()
    clearPlayPath()
    hidePlayHUD()

    if arrived then
        local t = os.clock() - S.playStart
        toast('arrived — ' .. fmtTime(t), C.GREEN)
        -- learning pass: soften segments that ran wide
        local data = S.playData
        if data and S.playFile then
            data.learned = data.learned or {}
            local adjusted = 0
            for bucket, e in pairs(S.bucketErr) do
                if e > LEARN_ERR then
                    local cur = data.learned[bucket] or 1
                    data.learned[bucket] = math.max(LEARN_MIN, cur * LEARN_FACTOR)
                    adjusted = adjusted + 1
                end
            end
            data.runs = (data.runs or 0) + 1
            local fname = S.playFile:match('([^/\\]+)%.json$')
            if fname then FS.save(fname, data) end
            if adjusted > 0 then
                toast('learned: slowed ' .. adjusted .. ' rough segment' .. (adjusted > 1 and 's' or ''), C.WHITE)
            end
        end
    elseif reason then
        toast(reason, C.RED)
    else
        toast('playback ended', C.MUT)
    end
    S.playData = nil
    S.playFile = nil
end

-- ============================================================
-- // ui: k icon
-- ============================================================
local kBtn = new('TextButton', {
    Name = 'KIcon',
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 10),
    Size = UDim2.new(0, 36, 0, 36),
    BackgroundColor3 = C.BG1,
    Text = 'K',
    Font = FONTB, TextSize = 18, TextColor3 = C.TEXT,
    AutoButtonColor = false,
    Parent = gui,
}, { corner(6), stroke(C.BORDER), vgradient(Color3.fromRGB(26, 26, 26), Color3.fromRGB(12, 12, 12)) })
hoverable(kBtn, C.BG1, C.BG3)

-- ============================================================
-- // ui: fullscreen overlay + panel
-- ============================================================
local overlay = new('Frame', {
    Name = 'Overlay', Visible = false,
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Parent = gui,
})

local panel = new('Frame', {
    Name = 'Panel',
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 620, 0, 420),
    BackgroundColor3 = C.BG0,
    Parent = overlay,
}, { corner(8), stroke(C.BORDER), vgradient(Color3.fromRGB(20, 20, 20), Color3.fromRGB(8, 8, 8)) })
local panelScale = new('UIScale', { Scale = 1, Parent = panel })

-- title bar
local titleBar = new('Frame', {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = panel,
})
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONTB, TextSize = 16, TextColor3 = C.TEXT,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(0, 140, 1, 0),
    Text = 'konstant a*', Parent = titleBar,
})
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 128, 0, 1), Size = UDim2.new(0, 220, 1, 0),
    Text = '// waypoint autodriver', Parent = titleBar,
})
new('Frame', { -- title divider
    BackgroundColor3 = C.BORDER, BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 1, -1), Size = UDim2.new(1, -24, 0, 1), Parent = titleBar,
})
local closeBtn = new('TextButton', {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.new(0, 26, 0, 26), BackgroundColor3 = C.BG2,
    Font = FONT, TextSize = 13, TextColor3 = C.MUT, Text = 'x',
    AutoButtonColor = false, Parent = titleBar,
}, { corner(4), stroke(C.BORDER) })
hoverable(closeBtn, C.BG2, Color3.fromRGB(60, 25, 25))

-- tab chips (hyprland workspace style)
local tabRow = new('Frame', {
    BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 52),
    Size = UDim2.new(1, -36, 0, 26), Parent = panel,
}, { new('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local tabs, tabBtns, tabFrames = { 'record', 'load' }, {}, {}
local activeTab = 'record'

local content = new('Frame', {
    BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 88),
    Size = UDim2.new(1, -36, 1, -106), Parent = panel,
})

local function selectTab(name)
    activeTab = name
    for t, btn in pairs(tabBtns) do
        local on = (t == name)
        tw(btn, { BackgroundColor3 = on and C.BG3 or C.BG1, TextColor3 = on and C.TEXT or C.DIM }, 0.15)
        btn:FindFirstChildOfClass('UIStroke').Color = on and C.BORDER2 or C.BORDER
        tabFrames[t].Visible = on
    end
    if name == 'load' then refreshLoadList() end
end

for i, t in ipairs(tabs) do
    local btn = new('TextButton', {
        Size = UDim2.new(0, 88, 1, 0), BackgroundColor3 = C.BG1,
        Font = FONT, TextSize = 12, TextColor3 = C.DIM,
        Text = '[ ' .. t .. ' ]', AutoButtonColor = false, LayoutOrder = i,
        Parent = tabRow,
    }, { corner(4), stroke(C.BORDER) })
    tabBtns[t] = btn
    tabFrames[t] = new('Frame', { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = false, Parent = content })
    btn.MouseButton1Click:Connect(function() selectTab(t) end)
end

-- // tile helper (bordered box, hyprland gaps vibe)
local function tile(parent, pos, size, title)
    local f = new('Frame', {
        BackgroundColor3 = C.BG1, Position = pos, Size = size, Parent = parent,
    }, { corner(6), stroke(C.BORDER), vgradient(Color3.fromRGB(19, 19, 19), Color3.fromRGB(12, 12, 12)) })
    if title then
        new('TextLabel', {
            BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 14),
            Text = title, Parent = f,
        })
    end
    return f
end

-- ============================================================
-- // record tab
-- ============================================================
local recTab = tabFrames['record']
local recLeft = tile(recTab, UDim2.new(0, 0, 0, 0), UDim2.new(0.5, -5, 1, 0), '~/session')
local recRight = tile(recTab, UDim2.new(0.5, 5, 0, 0), UDim2.new(0.5, -5, 1, 0), '~/manual')

local startBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 44),
    BackgroundColor3 = C.BG3, Font = FONTB, TextSize = 14, TextColor3 = C.TEXT,
    Text = '>  start path', AutoButtonColor = false, Parent = recLeft,
}, { corner(5), stroke(C.BORDER2) })
hoverable(startBtn, C.BG3, Color3.fromRGB(45, 45, 45))

local recInfo = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    Position = UDim2.new(0, 12, 0, 90), Size = UDim2.new(1, -24, 1, -102),
    Text = 'state    idle\npoints   0\ndist     0 studs\ngame     ' .. string.lower(gameName):sub(1, 24),
    Parent = recLeft,
})

new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11.5, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true, LineHeight = 1.35,
    Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 1, -44),
    Text = '1. start path — ui minimizes, hud appears\n'
        .. '2. drive or walk to your destination\n'
        .. '3. hold rewind to back up and redo a section\n'
        .. '   green = path / red = old / yellow = redone\n'
        .. '4. end path at the destination, name it, save\n\n'
        .. 'paths save to workspace/' .. ROOT_FOLDER .. '/\n'
        .. 'and only show up in this game.',
    Parent = recRight,
})

-- ============================================================
-- // load tab
-- ============================================================
local loadTab = tabFrames['load']
local loadLeft = tile(loadTab, UDim2.new(0, 0, 0, 0), UDim2.new(0.5, -5, 1, 0), '~/paths')
local loadRight = tile(loadTab, UDim2.new(0.5, 5, 0, 0), UDim2.new(0.5, -5, 1, 0), '~/drive')

local listScroll = new('ScrollingFrame', {
    BackgroundTransparency = 1, BorderSizePixel = 0,
    Position = UDim2.new(0, 8, 0, 28), Size = UDim2.new(1, -16, 1, -36),
    CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 3, ScrollBarImageColor3 = C.BORDER2,
    Parent = loadLeft,
}, { new('UIListLayout', { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

local detailLbl = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 0, 96),
    Text = 'no path selected', Parent = loadRight,
})

local multBox = new('TextBox', {
    Position = UDim2.new(0, 12, 0, 134), Size = UDim2.new(0, 70, 0, 26),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 12, TextColor3 = C.TEXT,
    Text = '1.0', PlaceholderText = 'speed x', ClearTextOnFocus = false,
    Parent = loadRight,
}, { corner(4), stroke(C.BORDER) })
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 90, 0, 134), Size = UDim2.new(0, 120, 0, 26),
    Text = 'speed mult', Parent = loadRight,
})

local invBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 0, 168), Size = UDim2.new(1, -24, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    Text = 'invert steer: off', AutoButtonColor = false, Parent = loadRight,
}, { corner(4), stroke(C.BORDER) })
invBtn.MouseButton1Click:Connect(function()
    S.invertSteer = not S.invertSteer
    invBtn.Text = 'invert steer: ' .. (S.invertSteer and 'on' or 'off')
    invBtn.TextColor3 = S.invertSteer and C.TEXT or C.DIM
end)

local goBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 1, -78), Size = UDim2.new(1, -24, 0, 40),
    BackgroundColor3 = C.BG3, Font = FONTB, TextSize = 14, TextColor3 = C.TEXT,
    Text = '>  start drive', AutoButtonColor = false, Parent = loadRight,
}, { corner(5), stroke(C.BORDER2) })
hoverable(goBtn, C.BG3, Color3.fromRGB(45, 45, 45))

local delBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 1, -32), Size = UDim2.new(1, -24, 0, 24),
    BackgroundColor3 = C.BG1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    Text = 'delete path', AutoButtonColor = false, Parent = loadRight,
}, { corner(4), stroke(C.BORDER) })
hoverable(delBtn, C.BG1, Color3.fromRGB(55, 22, 22))

local listEntries = {}
function refreshLoadList()
    for _, c in ipairs(listScroll:GetChildren()) do
        if c:IsA('TextButton') then c:Destroy() end
    end
    listEntries = FS.list()
    S.selFile = nil
    detailLbl.Text = #listEntries == 0 and 'no saved paths for this game yet' or 'no path selected'
    for i, entry in ipairs(listEntries) do
        local row = new('TextButton', {
            Size = UDim2.new(1, -6, 0, 30), BackgroundColor3 = C.BG2,
            Font = FONT, TextSize = 12, TextColor3 = C.MUT,
            TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false,
            Text = '  ' .. tostring(entry.data.name), LayoutOrder = i,
            Parent = listScroll,
        }, { corner(4), stroke(C.BORDER) })
        row.MouseButton1Click:Connect(function()
            S.selFile = entry
            for _, c in ipairs(listScroll:GetChildren()) do
                if c:IsA('TextButton') then
                    c.BackgroundColor3 = C.BG2
                    c.TextColor3 = C.MUT
                end
            end
            row.BackgroundColor3 = C.BG3
            row.TextColor3 = C.TEXT
            local d = entry.data
            detailLbl.Text = table.concat({
                'name     ' .. tostring(d.name),
                'dist     ' .. fmtDist(d.distance or 0),
                'points   ' .. #d.points,
                'runs     ' .. tostring(d.runs or 0),
                'created  ' .. tostring(d.created or '?'),
            }, '\n')
        end)
    end
end

goBtn.MouseButton1Click:Connect(function()
    if not S.selFile then toast('select a path first', C.RED) return end
    S.speedMult = math.clamp(tonumber(multBox.Text) or 1, 0.3, 3)
    multBox.Text = tostring(S.speedMult)
    startPlayback(S.selFile)
end)

delBtn.MouseButton1Click:Connect(function()
    if not S.selFile then toast('select a path first', C.RED) return end
    FS.delete(S.selFile.file)
    toast('deleted "' .. tostring(S.selFile.data.name) .. '"', C.MUT)
    refreshLoadList()
end)

-- ============================================================
-- // save dialog (modal over panel)
-- ============================================================
local saveModal = new('Frame', {
    Visible = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
    Size = UDim2.new(1, 0, 1, 0), ZIndex = 10, Parent = panel,
}, { corner(8) })
local saveBox = new('Frame', {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 340, 0, 160), BackgroundColor3 = C.BG1, ZIndex = 11,
    Parent = saveModal,
}, { corner(6), stroke(C.BORDER2), vgradient(Color3.fromRGB(24, 24, 24), Color3.fromRGB(12, 12, 12)) })
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONTB, TextSize = 13, TextColor3 = C.TEXT,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
    Position = UDim2.new(0, 16, 0, 12), Size = UDim2.new(1, -32, 0, 20),
    Text = 'save path', Parent = saveBox,
})
local saveSub = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
    Position = UDim2.new(0, 16, 0, 32), Size = UDim2.new(1, -32, 0, 16),
    Text = '', Parent = saveBox,
})
local nameBox = new('TextBox', {
    Position = UDim2.new(0, 16, 0, 58), Size = UDim2.new(1, -32, 0, 30),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 13, TextColor3 = C.TEXT,
    PlaceholderText = 'path name (e.g. "spawn to gas station")', PlaceholderColor3 = C.DIM,
    Text = '', ClearTextOnFocus = false, ZIndex = 11, Parent = saveBox,
}, { corner(4), stroke(C.BORDER) })
local saveOk = new('TextButton', {
    Position = UDim2.new(0, 16, 1, -46), Size = UDim2.new(0.5, -22, 0, 32),
    BackgroundColor3 = C.BG3, Font = FONTB, TextSize = 12, TextColor3 = C.TEXT,
    Text = 'save', AutoButtonColor = false, ZIndex = 11, Parent = saveBox,
}, { corner(4), stroke(C.BORDER2) })
local saveNo = new('TextButton', {
    Position = UDim2.new(0.5, 6, 1, -46), Size = UDim2.new(0.5, -22, 0, 32),
    BackgroundColor3 = C.BG1, Font = FONT, TextSize = 12, TextColor3 = C.DIM,
    Text = 'discard', AutoButtonColor = false, ZIndex = 11, Parent = saveBox,
}, { corner(4), stroke(C.BORDER) })
hoverable(saveOk, C.BG3, Color3.fromRGB(45, 45, 45))
hoverable(saveNo, C.BG1, Color3.fromRGB(55, 22, 22))

function showSaveDialog()
    openOverlay()
    saveSub.Text = fmtDist(S.recDist) .. ' - ' .. #S.samples .. ' points - ' .. fmtTime(os.clock() - S.recStart)
    nameBox.Text = ''
    saveModal.Visible = true
end
saveOk.MouseButton1Click:Connect(function()
    if saveRecording(nameBox.Text) then
        saveModal.Visible = false
        selectTab('load')
    end
end)
saveNo.MouseButton1Click:Connect(function()
    discardRecording()
    saveModal.Visible = false
end)

-- ============================================================
-- // record hud (top right, minimized mode)
-- ============================================================
local recHud = new('Frame', {
    Visible = false, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 320, 0, 14), Size = UDim2.new(0, 240, 0, 148),
    BackgroundColor3 = C.BG0, Parent = gui,
}, { corner(6), stroke(C.BORDER), vgradient(Color3.fromRGB(18, 18, 18), Color3.fromRGB(9, 9, 9)) })
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONTB, TextSize = 12, TextColor3 = C.TEXT,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 16),
    Text = 'recording', Parent = recHud,
})
new('Frame', {
    BackgroundColor3 = C.GREEN, BorderSizePixel = 0,
    Position = UDim2.new(1, -18, 0, 12), Size = UDim2.new(0, 7, 0, 7), Parent = recHud,
}, { corner(4) })
local recHudInfo = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 0, 52),
    Text = '', Parent = recHud,
})
local rewindBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 1, -58), Size = UDim2.new(0.5, -16, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.MUT,
    Text = '<< hold rewind', AutoButtonColor = false, Parent = recHud,
}, { corner(4), stroke(C.BORDER) })
local endBtn = new('TextButton', {
    Position = UDim2.new(0.5, 4, 1, -58), Size = UDim2.new(0.5, -16, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.TEXT,
    Text = 'end path', AutoButtonColor = false, Parent = recHud,
}, { corner(4), stroke(C.BORDER2) })
hoverable(endBtn, C.BG2, Color3.fromRGB(45, 45, 45))
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 10, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 12, 1, -28), Size = UDim2.new(1, -24, 0, 16),
    Text = 'end path at your destination', Parent = recHud,
})

rewindBtn.MouseButton1Down:Connect(function()
    rewindBtn.TextColor3 = C.YELLOW
    setRewind(true)
end)
local function relRewind()
    rewindBtn.TextColor3 = C.MUT
    setRewind(false)
end
rewindBtn.MouseButton1Up:Connect(relRewind)
rewindBtn.MouseLeave:Connect(relRewind)
endBtn.MouseButton1Click:Connect(endRecording)

function showRecordHUD()
    recHud.Visible = true
    recHud.Position = UDim2.new(1, 320, 0, 14)
    tw(recHud, { Position = UDim2.new(1, -14, 0, 14) }, 0.3)
end
function hideRecordHUD()
    tw(recHud, { Position = UDim2.new(1, 320, 0, 14) }, 0.25)
    task.delay(0.3, function() recHud.Visible = false end)
end

-- ============================================================
-- // playback hud
-- ============================================================
local playHud = new('Frame', {
    Visible = false, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 320, 0, 14), Size = UDim2.new(0, 240, 0, 158),
    BackgroundColor3 = C.BG0, Parent = gui,
}, { corner(6), stroke(C.BORDER), vgradient(Color3.fromRGB(18, 18, 18), Color3.fromRGB(9, 9, 9)) })
local playTitle = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONTB, TextSize = 12, TextColor3 = C.TEXT,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -46, 0, 16),
    Text = 'driving', Parent = playHud,
})
new('Frame', {
    BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
    Position = UDim2.new(1, -18, 0, 12), Size = UDim2.new(0, 7, 0, 7), Parent = playHud,
}, { corner(4) })
local progBg = new('Frame', {
    BackgroundColor3 = C.BG2, BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 5), Parent = playHud,
}, { corner(3) })
local progFill = new('Frame', {
    BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
    Size = UDim2.new(0, 0, 1, 0), Parent = progBg,
}, { corner(3) })
local playInfo = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    Position = UDim2.new(0, 12, 0, 46), Size = UDim2.new(1, -24, 0, 66),
    Text = '', Parent = playHud,
})
local playEndBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 1, -34), Size = UDim2.new(1, -24, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.TEXT,
    Text = 'end drive', AutoButtonColor = false, Parent = playHud,
}, { corner(4), stroke(C.BORDER2) })
hoverable(playEndBtn, C.BG2, Color3.fromRGB(55, 22, 22))
playEndBtn.MouseButton1Click:Connect(function() stopPlayback('ended manually') end)

function showPlayHUD(name)
    playTitle.Text = 'driving: ' .. string.lower(tostring(name))
    playHud.Visible = true
    playHud.Position = UDim2.new(1, 320, 0, 14)
    tw(playHud, { Position = UDim2.new(1, -14, 0, 14) }, 0.3)
end
function hidePlayHUD()
    tw(playHud, { Position = UDim2.new(1, 320, 0, 14) }, 0.25)
    task.delay(0.3, function() playHud.Visible = false end)
end

function setPlayStatus(status, idx, total, spd, pts)
    local prog = math.clamp(idx / total, 0, 1)
    progFill.Size = UDim2.new(prog, 0, 1, 0)
    -- eta: remaining points * avg segment length / current speed
    local remaining = 0
    do
        local step = math.max(1, math.floor((total - idx) / 40))
        local lastP = Vector3.new(pts[idx][1], pts[idx][2], pts[idx][3])
        for i = idx + step, total, step do
            local p = Vector3.new(pts[i][1], pts[i][2], pts[i][3])
            remaining = remaining + (p - lastP).Magnitude
            lastP = p
        end
    end
    local eta = spd > 2 and fmtTime(remaining / spd) or '--:--'
    local line = status or ('mode     ' .. S.driveMode)
    playInfo.Text = string.format('%d%%  -  %s\nspeed    %d mph\neta      %s\ntime     %s',
        math.floor(prog * 100), fmtDist(remaining), mph(spd), eta, fmtTime(os.clock() - S.playStart))
        .. '\n' .. line
end

-- ============================================================
-- // record hud updater
-- ============================================================
bind(RunService.Heartbeat:Connect(function()
    if S.mode == 'recording' or S.mode == 'rewinding' then
        local t = os.clock() - S.recStart
        recHudInfo.Text = string.format('time     %s\ndist     %s\npoints   %d%s',
            fmtTime(t), fmtDist(S.recDist), #S.samples,
            S.mode == 'rewinding' and '\n<< rewinding' or '')
        recInfo.Text = 'state    ' .. S.mode .. '\npoints   ' .. #S.samples
            .. '\ndist     ' .. fmtDist(S.recDist) .. '\ngame     ' .. string.lower(gameName):sub(1, 24)
    end
end))

-- ============================================================
-- // overlay open/close
-- ============================================================
local overlayOpen = false
function openOverlay()
    if overlayOpen then return end
    overlayOpen = true
    overlay.Visible = true
    panelScale.Scale = 0.93
    panel.BackgroundTransparency = 0
    tw(overlay, { BackgroundTransparency = 0.42 }, 0.25)
    tw(panelScale, { Scale = 1 }, 0.28, Enum.EasingStyle.Back)
    tw(kBtn, { TextColor3 = C.WHITE }, 0.2)
end
function closeOverlay()
    if not overlayOpen then return end
    overlayOpen = false
    tw(overlay, { BackgroundTransparency = 1 }, 0.22)
    tw(panelScale, { Scale = 0.95 }, 0.22)
    tw(kBtn, { TextColor3 = C.TEXT }, 0.2)
    task.delay(0.24, function()
        if not overlayOpen then overlay.Visible = false end
    end)
end

kBtn.MouseButton1Click:Connect(function()
    if overlayOpen then closeOverlay() else openOverlay() end
end)
closeBtn.MouseButton1Click:Connect(closeOverlay)

startBtn.MouseButton1Click:Connect(function()
    if S.mode == 'idle' then
        startRecording()
    else
        toast('already busy — end the current session first', C.RED)
    end
end)

selectTab('record')

-- ============================================================
-- // cleanup registration
-- ============================================================
_G.KAStarCleanup = function()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    if recConn then pcall(function() recConn:Disconnect() end) end
    if rewindConn then pcall(function() rewindConn:Disconnect() end) end
    if playConn then pcall(function() playConn:Disconnect() end) end
    pcall(releaseDrive)
    pcall(clearSegs)
    pcall(clearGhosts)
    pcall(clearPlayPath)
    pcall(function() pathFolder:Destroy() end)
    pcall(function() playFolder:Destroy() end)
    pcall(function() gui:Destroy() end)
end

if not FS.ok then
    toast('warning: executor lacks file api — saving disabled', C.YELLOW)
end
toast('konstant a* loaded — click the k icon', C.WHITE)
