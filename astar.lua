--[[
    konstant a*  //  universal waypoint auto-driver
    record a path by driving it. save it. let the script drive it back.
    v4.9.2 -- scan overlay: paint the grid on the ground (white = road,
           grey = drivable) to SEE coverage and road tags; richer scan
           stats (road / tested / rejected)
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
local LOOKAHEAD_MAX   = 34
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
    lastT       = 0,        -- last commanded throttle (hud display)
    lastS       = 0,        -- last commanded steer (hud display)
    acquired    = true,     -- reached the line at least once this drive
    invertSteer = false,
    licensed    = true,     -- roads-only routing (off = lawn shortcuts ok)
    routeDest   = nil,      -- destination Vector3 of the active route
    blockCells  = {},       -- "cx,cz" -> expiry: cells fenced off by reroutes
    speedMult   = 1.0,
    blocked     = nil,      -- {name=, class=, since=, pos=}
    caution     = nil,      -- distance to a far on-line obstacle (pre-slow)
    tight       = nil,      -- nearest side obstacle when boxed in (slow)
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
local netFolder = gameFolder .. '/network'

function FS.ensure()
    if not FS.ok then return false end
    pcall(function()
        if not isfolder(ROOT_FOLDER) then makefolder(ROOT_FOLDER) end
        if not isfolder(gameFolder) then makefolder(gameFolder) end
        if not isfolder(netFolder) then makefolder(netFolder) end
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

function FS.saveRoad(name, data)
    if not FS.ensure() then return false end
    return pcall(function()
        writefile(netFolder .. '/' .. name .. '.json', HttpService:JSONEncode(data))
    end)
end

function FS.netList()
    if not FS.ensure() then return {} end
    local out = {}
    pcall(function()
        for _, f in ipairs(listfiles(netFolder)) do
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
rayParams.RespectCanCollide = true -- decorations never block rays

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
    local st = btn:FindFirstChildOfClass('UIStroke')
    local stBase = st and st.Color
    btn.MouseEnter:Connect(function()
        tw(btn, { BackgroundColor3 = hot }, 0.12)
        if st then tw(st, { Color = C.BORDER2 }, 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        tw(btn, { BackgroundColor3 = base }, 0.18)
        if st then tw(st, { Color = stBase }, 0.18) end
    end)
    -- press flash
    btn.MouseButton1Down:Connect(function()
        tw(btn, { BackgroundColor3 = Color3.fromRGB(55, 55, 55) }, 0.05)
    end)
    btn.MouseButton1Up:Connect(function()
        tw(btn, { BackgroundColor3 = hot }, 0.2)
    end)
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
        corner(5), stroke(C.BORDER),
        vgradient(Color3.fromRGB(24, 24, 24), Color3.fromRGB(13, 13, 13)),
        new('Frame', { BackgroundColor3 = accent or C.WHITE, Size = UDim2.new(0, 2, 1, -10), Position = UDim2.new(0, 5, 0, 5), BorderSizePixel = 0 }),
        new('TextLabel', {
            BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.TEXT,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(1, -22, 1, 0),
            Text = '> ' .. string.lower(tostring(msg)), TextTransparency = 1,
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
local startRecording, endRecording, startPlayback, stopPlayback, routeAndDrive

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

local function saveRecording(name, asRoad)
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
        road = asRoad or nil,
    }
    local ok = asRoad and FS.saveRoad(name, data) or (not asRoad and FS.save(name, data))
    if ok then
        toast((asRoad and 'road segment "' or 'saved "') .. name .. '" — ' .. fmtDist(S.recDist), C.GREEN)
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
-- pwm: emulate analog control through digital keys. a key held for 30%
-- of every cycle reads as ~30% input to games that poll key state.
local PWM_CYCLE = 0.12
local function pwmOn(duty)
    if duty <= 0.03 then return false end
    if duty >= 0.93 then return true end
    return (os.clock() % PWM_CYCLE) / PWM_CYCLE < duty
end

local function applyDrive(throttle, steer)
    if S.invertSteer then steer = -steer end
    S.lastT, S.lastS = throttle, steer

    -- seat float writes (games whose chassis reads the seat directly)
    local sp = seat()
    if sp and sp:IsA('VehicleSeat') then
        pcall(function()
            sp.ThrottleFloat = throttle
            sp.SteerFloat = steer
        end)
    end

    -- pwm key simulation (games that read player input) -- both always
    -- active; whichever channel the game listens to wins
    vimKey(Enum.KeyCode.W, pwmOn(math.clamp(throttle, 0, 1)))
    vimKey(Enum.KeyCode.S, pwmOn(math.clamp(-throttle, 0, 1)))
    vimKey(Enum.KeyCode.D, pwmOn(math.clamp(steer, 0, 1)))
    vimKey(Enum.KeyCode.A, pwmOn(math.clamp(-steer, 0, 1)))
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

-- returns (blocking hit, distance) or nil. casts along BOTH the travel
-- direction and the expected path direction -- catches walls the route
-- bends toward before the nose is even aimed at them
local function scanAhead(sp, pts, idx)
    local spd = sp.AssemblyLinearVelocity.Magnitude
    local range = math.clamp(spd * 1.4, 14, 70)
    local vel = sp.AssemblyLinearVelocity
    local dirs = {}
    local fwd = sp.CFrame.LookVector
    if vel.Magnitude > 4 then fwd = vel.Unit end
    table.insert(dirs, fwd)
    local tp = pts[math.min(idx + 15, #pts)]
    local pd = Vector3.new(tp[1] - sp.Position.X, 0, tp[3] - sp.Position.Z)
    if pd.Magnitude > 2 then table.insert(dirs, pd.Unit) end
    local right = sp.CFrame.RightVector
    local origin = sp.Position + Vector3.new(0, 2, 0)

    refreshRayFilter({ playFolder })
    local best, bestD, bestP
    for _, dir in ipairs(dirs) do
        for _, off in ipairs({ 0, 1.6, -1.6 }) do
            local r = workspace:Raycast(origin + right * off, dir * range, rayParams)
            -- normal.Y > 0.6 = ground/slope, not a wall or object -- ignore
            if r and r.Instance and r.Instance.CanCollide and r.Normal.Y <= 0.6 then
                -- does the hit actually sit in the path corridor ahead?
                local hitP = r.Position
                local minLat = math.huge
                local hi = math.min(#pts, idx + 90)
                for i = idx, hi do
                    local d = (Vector3.new(pts[i][1], 0, pts[i][3]) - Vector3.new(hitP.X, 0, hitP.Z)).Magnitude
                    if d < minLat then minLat = d end
                end
                if minLat < OBST_CORRIDOR then
                    local dist = (hitP - sp.Position).Magnitude
                    if not bestD or dist < bestD then best, bestD, bestP = r.Instance, dist, hitP end
                end
            end
        end
    end
    return best, bestD, bestP
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

-- sharpest curvature (rad/stud) ahead and its distance -- used to brake
-- on a natural envelope BEFORE corners. long stride (6 samples) filters
-- recording noise so gentle bends don't read as sharp corners
local function maxCurvatureAhead(pts, idx, spd)
    -- scan the TRUE braking distance for the current speed. at 160
    -- studs/s (~100mph) stopping for a hairpin needs ~580 studs -- the
    -- scanner must see that far or braking starts too late
    local scanDist = math.clamp(spd * spd / 40 + 40, 40, 650)
    local stride = 6
    local acc, maxK, prevDir = 0, 0, nil
    local dAtMax = scanDist
    local i = idx
    while i + stride <= #pts and acc < scanDist do
        local seg = Vector3.new(pts[i + stride][1] - pts[i][1], 0, pts[i + stride][3] - pts[i][3])
        local len = seg.Magnitude
        if len > 0.3 then
            local dir = seg / len
            if prevDir then
                local turn = math.acos(math.clamp(dir:Dot(prevDir), -1, 1))
                local k = turn / len
                if k > maxK then maxK = k; dAtMax = acc end
            end
            prevDir = dir
        end
        acc = acc + len
        i = i + stride
    end
    return maxK, dAtMax
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

-- ============================================================
-- // road network (scan-by-driving) + a* routing
-- ============================================================
local Net = { segs = {}, nodes = nil, edges = nil, splits = nil }

function Net.load()
    Net.segs = FS.netList()
    Net.nodes, Net.edges, Net.splits = nil, nil, nil
    return #Net.segs
end

local function netPt(si, i)
    local p = Net.segs[si].data.points[i]
    return Vector3.new(p[1], p[2], p[3])
end

-- build graph: intersections between recorded road segments become nodes,
-- stretches between them become edges with arc-length costs
function Net.build()
    if Net.nodes then return true end
    if #Net.segs == 0 then return false end

    -- spatial hash so intersection detection isn't o(n^2) points
    local CELL = 8
    local hash = {}
    for si, seg in ipairs(Net.segs) do
        local pts = seg.data.points
        for i = 1, #pts, 2 do
            local k = math.floor(pts[i][1] / CELL) .. ',' .. math.floor(pts[i][3] / CELL)
            hash[k] = hash[k] or {}
            table.insert(hash[k], { si = si, i = i })
        end
    end

    -- find crossings: points of different segments within 7 studs
    local rawSplits = {}
    for si, seg in ipairs(Net.segs) do rawSplits[si] = { 1, #seg.data.points } end
    for si, seg in ipairs(Net.segs) do
        local pts = seg.data.points
        for i = 1, #pts, 2 do
            local cx, cz = math.floor(pts[i][1] / CELL), math.floor(pts[i][3] / CELL)
            for ox = -1, 1 do
                for oz = -1, 1 do
                    local bucket = hash[(cx + ox) .. ',' .. (cz + oz)]
                    if bucket then
                        for _, e in ipairs(bucket) do
                            if e.si > si and (netPt(si, i) - netPt(e.si, e.i)).Magnitude < 7 then
                                table.insert(rawSplits[si], i)
                                table.insert(rawSplits[e.si], e.i)
                            end
                        end
                    end
                end
            end
        end
    end

    -- collapse split indices bunched at the same junction
    Net.splits = {}
    for si, list in pairs(rawSplits) do
        table.sort(list)
        local out = {}
        for _, i in ipairs(list) do
            if #out == 0 or i - out[#out] > 15 then table.insert(out, i) end
        end
        local n = #Net.segs[si].data.points
        if out[#out] ~= n then
            if n - out[#out] <= 15 then out[#out] = n else table.insert(out, n) end
        end
        Net.splits[si] = out
    end

    -- nodes: cluster split positions across segments; edges between
    -- consecutive splits along each segment
    Net.nodes, Net.edges = {}, {}
    local function nodeAt(pos)
        for id, nd in ipairs(Net.nodes) do
            if (nd.pos - pos).Magnitude < 10 then return id end
        end
        table.insert(Net.nodes, { pos = pos, adj = {} })
        return #Net.nodes
    end
    for si, list in pairs(Net.splits) do
        local prevNode, prevIdx = nil, nil
        local pts = Net.segs[si].data.points
        for _, i in ipairs(list) do
            local id = nodeAt(netPt(si, i))
            if prevNode and i > prevIdx and id ~= prevNode then
                local len = 0
                for j = prevIdx, i - 1 do
                    len = len + (Vector3.new(pts[j + 1][1], pts[j + 1][2], pts[j + 1][3])
                               - Vector3.new(pts[j][1], pts[j][2], pts[j][3])).Magnitude
                end
                if len > 1 then
                    table.insert(Net.edges, { a = prevNode, b = id, si = si, i1 = prevIdx, i2 = i, len = len })
                    local ei = #Net.edges
                    table.insert(Net.nodes[prevNode].adj, ei)
                    table.insert(Net.nodes[id].adj, ei)
                end
            end
            prevNode, prevIdx = id, i
        end
    end
    return true
end

function Net.nearest(pos)
    local best
    for si, seg in ipairs(Net.segs) do
        local pts = seg.data.points
        for i = 1, #pts, 2 do
            local d = (Vector3.new(pts[i][1], pts[i][2], pts[i][3]) - pos).Magnitude
            if not best or d < best.d then best = { si = si, i = i, d = d } end
        end
    end
    return best
end

-- find the edge containing sample i of segment si. junction areas can
-- leave small index gaps owned by no edge (merged nodes) -- fall back
-- to the nearest edge on the same segment so routing never dead-ends
local function edgeContaining(si, i)
    local best, bestD
    for ei, e in ipairs(Net.edges) do
        if e.si == si then
            if i >= e.i1 and i <= e.i2 then return ei end
            local d = (i < e.i1) and (e.i1 - i) or (i - e.i2)
            if not bestD or d < bestD then bestD = d; best = ei end
        end
    end
    return best
end

local function subPts(si, iFrom, iTo)
    local pts = Net.segs[si].data.points
    local out = {}
    local step = iFrom <= iTo and 1 or -1
    for i = iFrom, iTo, step do
        local p = pts[i]
        table.insert(out, { p[1], p[2], p[3], p[4] or 16 })
    end
    return out
end

local function arcLen(si, i1, i2)
    if i1 > i2 then i1, i2 = i2, i1 end
    local pts = Net.segs[si].data.points
    local len = 0
    for j = i1, i2 - 1 do
        len = len + (Vector3.new(pts[j + 1][1], pts[j + 1][2], pts[j + 1][3])
                   - Vector3.new(pts[j][1], pts[j][2], pts[j][3])).Magnitude
    end
    return len
end

-- ============================================================
-- // map scanner (option 2): drivable-surface flood fill + grid a*
-- ============================================================
local Scan = {
    CELL = 6,
    grid = nil,      -- "cx,cz" -> surface y
    roads = {},      -- "cx,cz" -> true when surface belongs to workspace.roads
    roadCount = 0,
    count = 0,
    mats = {},       -- learned road-family materials
    running = false,
    checked = 0,
    frontier = nil, fHead = 1, fTail = 0,
    visited = nil,
    startedAt = 0,
    conn = nil,
    rp = nil,
}
local SCAN_BUDGET = 350          -- cells per frame (2-3 raycasts each)
local SCAN_MAX_CELLS = 900000    -- runaway guard

local function scanKey(cx, cz) return cx .. ',' .. cz end

-- swf keeps all road parts under workspace.roads -- perfect ground truth.
-- generic: any ancestor named "roads"/"road" tags the cell as road
local roadInstCache = setmetatable({}, { __mode = 'k' })
local function isRoadInst(inst)
    local c = roadInstCache[inst]
    if c ~= nil then return c end
    local m, road = inst, false
    while m and m ~= workspace do
        local nm = string.lower(m.Name)
        if nm == 'roads' or nm == 'road' then road = true break end
        m = m.Parent
    end
    roadInstCache[inst] = road
    return road
end

function Scan.loadFile()
    if not FS.ok then return false, 'no file api' end
    local okR, raw = pcall(readfile, gameFolder .. '/scan.json')
    if not okR or not raw or #raw < 10 then return false, 'no scan file' end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not ok then return false, 'scan file corrupted: ' .. tostring(data):sub(1, 50) end
    if not data or not data.cols then return false, 'scan file has no data' end
    Scan.grid, Scan.count, Scan.mats = {}, 0, {}
    Scan.roads, Scan.roadCount = {}, 0
    Scan.CELL = data.cell or 6
    for _, m in ipairs(data.mats or {}) do Scan.mats[m] = true end
    for cxs, runs in pairs(data.roads or {}) do
        local cx = tonumber(cxs)
        for _, run in ipairs(runs) do
            for i = 0, run[2] - 1 do
                Scan.roads[scanKey(cx, run[1] + i)] = true
                Scan.roadCount = Scan.roadCount + 1
            end
        end
    end
    for cxs, runs in pairs(data.cols) do
        local cx = tonumber(cxs)
        for _, run in ipairs(runs) do
            local cz0, n, y0, y1 = run[1], run[2], run[3], run[4]
            for i = 0, n - 1 do
                local t = (n > 1) and i / (n - 1) or 0
                Scan.grid[scanKey(cx, cz0 + i)] = y0 + (y1 - y0) * t
                Scan.count = Scan.count + 1
            end
        end
    end
    return Scan.count > 0
end

function Scan.saveFile()
    if not FS.ok or not Scan.grid then return false end
    local cols = {}
    for key, y in pairs(Scan.grid) do
        local cxs, czs = key:match('(-?%d+),(-?%d+)')
        local cx, cz = tonumber(cxs), tonumber(czs)
        cols[cx] = cols[cx] or {}
        table.insert(cols[cx], { cz, y })
    end
    local out = {}
    for cx, list in pairs(cols) do
        table.sort(list, function(a, b) return a[1] < b[1] end)
        local runs, run = {}, nil
        for _, e in ipairs(list) do
            -- runs must be SHORT and MONOTONIC: load reconstructs heights
            -- by lerp, and a rise-then-fall run lerps to wrong y values,
            -- which poisons future rescans (the 600k -> 300k shrink bug)
            local merged = false
            if run and e[1] == run.cz0 + run.n and run.n < 16
               and math.abs(e[2] - run.lastY) <= 1.0 then
                local d = e[2] - run.lastY
                if d == 0 or run.dir == 0 or (d > 0) == (run.dir > 0) then
                    run.n = run.n + 1
                    if d ~= 0 then run.dir = d end
                    run.lastY = e[2]
                    merged = true
                end
            end
            if not merged then
                if run then
                    table.insert(runs, { run.cz0, run.n,
                        math.floor(run.y0 * 10) / 10, math.floor(run.lastY * 10) / 10 })
                end
                run = { cz0 = e[1], n = 1, y0 = e[2], lastY = e[2], dir = 0 }
            end
        end
        if run then
            table.insert(runs, { run.cz0, run.n,
                math.floor(run.y0 * 10) / 10, math.floor(run.lastY * 10) / 10 })
        end
        out[tostring(cx)] = runs
    end
    -- road cells: simple run-length by column
    local roadOut = {}
    do
        local rcols = {}
        for key in pairs(Scan.roads) do
            local cxs, czs = key:match('(-?%d+),(-?%d+)')
            local cx, cz = tonumber(cxs), tonumber(czs)
            rcols[cx] = rcols[cx] or {}
            table.insert(rcols[cx], cz)
        end
        for cx, list in pairs(rcols) do
            table.sort(list)
            local runs, run = {}, nil
            for _, cz in ipairs(list) do
                if run and cz == run[1] + run[2] then
                    run[2] = run[2] + 1
                else
                    if run then table.insert(runs, run) end
                    run = { cz, 1 }
                end
            end
            if run then table.insert(runs, run) end
            roadOut[tostring(cx)] = runs
        end
    end
    local mats = {}
    for m in pairs(Scan.mats) do table.insert(mats, m) end
    return (pcall(function()
        writefile(gameFolder .. '/scan.json',
            HttpService:JSONEncode({ cell = Scan.CELL, mats = mats, cols = out, roads = roadOut }))
    end))
end

-- pothole healing: raycast noise leaves holes in the grid that force
-- stupid detours. any empty cell with 5+ drivable neighbors at a
-- consistent height is clearly drivable -- fill it
function Scan.fillHoles()
    if not Scan.grid then return 0 end
    local cand = {}
    for key, y in pairs(Scan.grid) do
        local cxs, czs = key:match('(-?%d+),(-?%d+)')
        local cx, cz = tonumber(cxs), tonumber(czs)
        for dx = -1, 1 do
            for dz = -1, 1 do
                if dx ~= 0 or dz ~= 0 then
                    local nk = scanKey(cx + dx, cz + dz)
                    if not Scan.grid[nk] then
                        local c = cand[nk]
                        if not c then c = { n = 0, sum = 0, lo = y, hi = y }; cand[nk] = c end
                        c.n = c.n + 1
                        c.sum = c.sum + y
                        if y < c.lo then c.lo = y end
                        if y > c.hi then c.hi = y end
                    end
                end
            end
        end
    end
    local filled = 0
    for nk, c in pairs(cand) do
        if c.n >= 5 and (c.hi - c.lo) <= 3 then
            Scan.grid[nk] = c.sum / c.n
            Scan.count = Scan.count + 1
            filled = filled + 1
        end
    end
    return filled
end

function Scan.available()
    if Scan.grid and Scan.count > 0 then return true end
    if Scan.loadFile() then
        pcall(Scan.fillHoles)
        return true
    end
    return false
end

local function scanPush(cx, cz, refY)
    Scan.fTail = Scan.fTail + 1
    Scan.frontier[Scan.fTail] = { cx, cz, refY }
end

function Scan.stop(save)
    Scan.running = false
    if Scan.conn then Scan.conn:Disconnect() Scan.conn = nil end
    if save and Scan.grid then
        local filled = 0
        pcall(function() filled = Scan.fillHoles() end)
        Scan.saveFile()
        toast(('scan saved — %d drivable cells (%d potholes healed)'):format(Scan.count, filled), C.GREEN)
    end
end

function Scan.step()
    if not Scan.running then return end
    local done = 0
    while done < SCAN_BUDGET do
        if Scan.fHead > Scan.fTail then
            Scan.stop(true)
            toast('scan complete — the whole connected surface is mapped', C.GREEN)
            return
        end
        local item = Scan.frontier[Scan.fHead]
        Scan.frontier[Scan.fHead] = nil
        Scan.fHead = Scan.fHead + 1
        local cx, cz, refY = item[1], item[2], item[3]
        local key = scanKey(cx, cz)
        if not Scan.visited[key] then
            Scan.visited[key] = true
            Scan.checked = Scan.checked + 1
            local wx, wz = cx * Scan.CELL, cz * Scan.CELL
            local hit = workspace:Raycast(Vector3.new(wx, refY + 30, wz), Vector3.new(0, -80, 0), Scan.rp)
            -- flat + height-continuous = drivable, ANY material (a car
            -- doesn't care). water rejected via a water-sensitive ray
            if hit and hit.Normal.Y >= 0.92 and math.abs(hit.Position.Y - refY) <= 5 then
                local wet = workspace:Raycast(Vector3.new(wx, refY + 30, wz), Vector3.new(0, -80, 0), Scan.rpWater)
                if wet and wet.Material == Enum.Material.Water then hit = nil end
            else
                hit = nil
            end
            if hit then
                -- clearance: nothing solid sitting on the surface
                local up = workspace:Raycast(hit.Position + Vector3.new(0, 0.7, 0), Vector3.new(0, 4.5, 0), Scan.rp)
                if not up then
                    local y = hit.Position.Y
                    if isRoadInst(hit.Instance) and not Scan.roads[key] then
                        Scan.roads[key] = true
                        Scan.roadCount = Scan.roadCount + 1
                    end
                    if not Scan.grid[key] then
                        Scan.grid[key] = y
                        Scan.count = Scan.count + 1
                        if Scan.count >= SCAN_MAX_CELLS then
                            Scan.stop(true)
                            toast('scan hit the cell cap — saved what we have', C.YELLOW)
                            return
                        end
                    end
                    scanPush(cx + 1, cz, y)
                    scanPush(cx - 1, cz, y)
                    scanPush(cx, cz + 1, y)
                    scanPush(cx, cz - 1, y)
                end
            end
        end
        done = done + 1
    end
end

function Scan.start()
    if Scan.running then toast('already scanning', C.RED) return end
    local r = hrp()
    if not r then toast('no character', C.RED) return end
    if not Scan.grid then Scan.loadFile() end
    Scan.grid = Scan.grid or {}

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    rp.RespectCanCollide = true -- non-collidable decor can't fake-block roads
    local excl = { pathFolder, playFolder }
    if char() then table.insert(excl, char()) end
    -- exclude vehicles/characters so parked cars don't poison road cells
    pcall(function()
        for _, m in ipairs(workspace:GetChildren()) do
            if m:IsA('Model') and (m:FindFirstChildWhichIsA('VehicleSeat', true)
               or m:FindFirstChildOfClass('Humanoid')) then
                table.insert(excl, m)
            end
        end
    end)
    rp.FilterDescendantsInstances = excl
    Scan.rp = rp
    local rpW = RaycastParams.new()
    rpW.FilterType = Enum.RaycastFilterType.Exclude
    rpW.IgnoreWater = false -- water-sensitive twin for underwater rejection
    rpW.RespectCanCollide = true
    rpW.FilterDescendantsInstances = excl
    Scan.rpWater = rpW

    local hit = workspace:Raycast(r.Position + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), rp)
    if not hit then toast('no ground under you — park on a road first', C.RED) return end
    if hit.Normal.Y < 0.9 then toast('surface too steep to seed from', C.RED) return end

    Scan.mats[hit.Material.Name] = true
    Scan.frontier, Scan.fHead, Scan.fTail = {}, 1, 0
    Scan.visited = {}
    Scan.checked = 0
    Scan.startedAt = os.clock()
    scanPush(math.floor(hit.Position.X / Scan.CELL + 0.5),
             math.floor(hit.Position.Z / Scan.CELL + 0.5), hit.Position.Y)
    Scan.running = true
    toast('scanning from here — surface: ' .. hit.Material.Name, C.GREEN)
    Scan.conn = bind(RunService.Heartbeat:Connect(Scan.step))
end

function Scan.clear()
    Scan.stop(false)
    Scan.grid, Scan.count, Scan.mats = nil, 0, {}
    Scan.roads, Scan.roadCount = {}, 0
    pcall(function() delfile(gameFolder .. '/scan.json') end)
    toast('scan wiped', C.MUT)
end

-- binary min-heap for grid a*
local function heapNew() return { n = 0 } end
local function heapPush(h, item)
    h.n = h.n + 1
    h[h.n] = item
    local i = h.n
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p][1] <= h[i][1] then break end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end
local function heapPop(h)
    if h.n == 0 then return nil end
    local top = h[1]
    h[1] = h[h.n]
    h[h.n] = nil
    h.n = h.n - 1
    local i = 1
    while true do
        local l, r2, m = i * 2, i * 2 + 1, i
        if l <= h.n and h[l][1] < h[m][1] then m = l end
        if r2 <= h.n and h[r2][1] < h[m][1] then m = r2 end
        if m == i then break end
        h[i], h[m] = h[m], h[i]
        i = m
    end
    return top
end

-- nearest scanned cell to a world position (spiral search)
function Scan.findCell(pos)
    local cx0 = math.floor(pos.X / Scan.CELL + 0.5)
    local cz0 = math.floor(pos.Z / Scan.CELL + 0.5)
    for ring = 0, 30 do
        local best
        for dx = -ring, ring do
            for dz = -ring, ring do
                if math.max(math.abs(dx), math.abs(dz)) == ring then
                    local y = Scan.grid[scanKey(cx0 + dx, cz0 + dz)]
                    if y and (not best or math.abs(y - pos.Y) < math.abs(best.y - pos.Y)) then
                        best = { cx = cx0 + dx, cz = cz0 + dz, y = y }
                    end
                end
            end
        end
        if best then return best end
    end
    return nil
end

-- grid a* + line-of-sight smoothing -> drivable polyline
function Scan.route(fromPos, toPos)
    if not Scan.available() then return nil, 'no scan for this game' end
    local grid, CELL = Scan.grid, Scan.CELL
    local sc = Scan.findCell(fromPos)
    if not sc then return nil, 'you are not near any scanned surface' end
    local gc = Scan.findCell(toPos)
    if not gc then return nil, 'destination not near any scanned surface' end

    local sKey, gKey = scanKey(sc.cx, sc.cz), scanKey(gc.cx, gc.cz)
    if sKey == gKey then return nil, 'already at the destination' end

    local dirs = {
        { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
        { 1, 1, 1.414 }, { 1, -1, 1.414 }, { -1, 1, 1.414 }, { -1, -1, 1.414 },
    }
    -- wall-hug penalty: a cell with missing neighbors borders something.
    -- the car has a body -- prefer the middle of open space, pay extra
    -- to squeeze along edges (still possible when it's the only way)
    local hugCache = {}
    local function hugPenalty(x, z, k2)
        local c = hugCache[k2]
        if c then return c end
        local n = 0
        for dx = -1, 1 do
            for dz = -1, 1 do
                if (dx ~= 0 or dz ~= 0) and grid[scanKey(x + dx, z + dz)] then n = n + 1 end
            end
        end
        c = (8 - n) * 0.7
        hugCache[k2] = c
        return c
    end
    -- start/goal stubs: the only places off-road driving is allowed when
    -- road tags exist (leaving a parking lot, arriving at the door)
    local function nearStub(x, z)
        return math.max(math.abs(x - sc.cx), math.abs(z - sc.cz)) <= 12
            or math.max(math.abs(x - gc.cx), math.abs(z - gc.cz)) <= 12
    end
    local function search(roadsOnly)
        local open = heapNew()
        local g, fr = { [sKey] = 0 }, {}
        heapPush(open, { 0, sc.cx, sc.cz })
        local expanded = 0
        while true do
            local cur = heapPop(open)
            if not cur then return nil end
            local cx, cz = cur[2], cur[3]
            local ck = scanKey(cx, cz)
            if ck == gKey then return fr end
            expanded = expanded + 1
            if expanded > 400000 then return nil end
            local cy = grid[ck]
            for _, d in ipairs(dirs) do
                local nx, nz = cx + d[1], cz + d[2]
                local nk = scanKey(nx, nz)
                local ny = grid[nk]
                if ny and math.abs(ny - cy) <= 4 then
                    -- no corner cutting on diagonals
                    if d[3] > 1 and not (grid[scanKey(cx + d[1], cz)] and grid[scanKey(cx, cz + d[2])]) then
                        ny = nil
                    end
                    -- roads-only: normal drivers stay on the pavement
                    if roadsOnly and ny and not Scan.roads[nk] and not nearStub(nx, nz) then
                        ny = nil
                    end
                    -- cells fenced off by dynamic reroutes (blocked obstacles)
                    if ny then
                        local bc = S.blockCells[nk]
                        if bc and bc > os.clock() then ny = nil end
                    end
                    if ny then
                        local mult = (roadsOnly or Scan.roads[nk]) and 1 or 1.9
                        local ng = g[ck] + d[3] * mult + hugPenalty(nx, nz, nk)
                        if not g[nk] or ng < g[nk] then
                            g[nk] = ng
                            fr[nk] = ck
                            heapPush(open, { ng + math.sqrt((gc.cx - nx) ^ 2 + (gc.cz - nz) ^ 2), nx, nz })
                        end
                    end
                end
            end
        end
    end
    -- licensed driver: roads-only when tags exist. unlicensed: free
    -- routing from the start. unrestricted always remains the last-resort
    -- fallback so a route is found whenever one physically exists
    local from, usedFree = nil, false
    if S.licensed and Scan.roadCount > 0 then from = search(true) end
    if not from then
        usedFree = S.licensed and Scan.roadCount > 0
        from = search(false)
    end
    if not from then return nil, 'no drivable route on the scan (disconnected area?)' end

    -- reconstruct cell chain
    local cells = {}
    local ck = gKey
    while ck do
        local cxs, czs = ck:match('(-?%d+),(-?%d+)')
        table.insert(cells, 1, { tonumber(cxs), tonumber(czs) })
        ck = from[ck]
    end

    -- corridor line-of-sight smoothing: the shortcut must be clear along
    -- a 3-cell-wide band (car body width), not just a center thread --
    -- otherwise smoothed lines graze trees and poles
    local function los(a, b)
        local dx, dz = b[1] - a[1], b[2] - a[2]
        local steps = math.max(math.abs(dx), math.abs(dz))
        if steps == 0 then return true end
        -- perpendicular offset in whole cells
        local len = math.sqrt(dx * dx + dz * dz)
        local px = math.floor(-dz / len + 0.5)
        local pz = math.floor(dx / len + 0.5)
        local prevY = grid[scanKey(a[1], a[2])]
        for s = 1, steps do
            local t = s / steps
            local x = math.floor(a[1] + dx * t + 0.5)
            local z = math.floor(a[2] + dz * t + 0.5)
            local y = grid[scanKey(x, z)]
            if not y or math.abs(y - prevY) > 4 then return false end
            -- smoothing must not straighten routes back through cells the
            -- reroute system fenced off
            local bc = S.blockCells[scanKey(x, z)]
            if bc and bc > os.clock() then return false end
            if not grid[scanKey(x + px, z + pz)] or not grid[scanKey(x - px, z - pz)] then
                return false
            end
            prevY = y
        end
        return true
    end
    local way = { cells[1] }
    local i = 1
    while i < #cells do
        local j = math.min(i + 40, #cells)
        while j > i + 1 and not los(cells[i], cells[j]) do j = j - 1 end
        table.insert(way, cells[j])
        i = j
    end

    -- emit drivable points every ~3 studs, default cruise 30 studs/s --
    -- the driver's corner anticipation shapes real speeds from geometry
    local pts = {}
    for wi = 1, #way - 1 do
        local a, b = way[wi], way[wi + 1]
        local ax, az = a[1] * CELL, a[2] * CELL
        local bx, bz = b[1] * CELL, b[2] * CELL
        local ay = grid[scanKey(a[1], a[2])]
        local by = grid[scanKey(b[1], b[2])]
        local segLen = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local steps = math.max(math.floor(segLen / 3), 1)
        -- cruise faster on tagged roads, careful off-road
        local segSpd = Scan.roads[scanKey(a[1], a[2])] and 48 or 22
        for s = (wi == 1 and 0 or 1), steps do
            local t = s / steps
            table.insert(pts, { ax + (bx - ax) * t, ay + (by - ay) * t + 1, az + (bz - az) * t, segSpd })
        end
    end
    return pts, nil, usedFree
end

-- a* over the road graph. from/to are world positions; virtual start and
-- goal nodes attach to the nearest point of their containing edge
function Net.route(fromPos, toPos)
    if not Net.build() then return nil, 'no road segments recorded yet' end
    local sN, gN = Net.nearest(fromPos), Net.nearest(toPos)
    if not sN or not gN then return nil, 'network empty' end
    -- coverage honesty: a destination far from every recorded road must
    -- NOT silently reroute to the closest old segment (bank hijack bug)
    if gN.d > 150 then
        return nil, ('destination is %d studs from any recorded road -- scan or record that area'):format(gN.d)
    end
    if sN.d > 400 then
        return nil, ('you are %d studs from any recorded road'):format(sN.d)
    end

    -- same-segment direct route: always valid, used as shortcut when on
    -- the same edge and as fallback whenever the graph can't help
    local function direct()
        if sN.si == gN.si then return subPts(sN.si, sN.i, gN.i) end
        return nil
    end

    local sE, gE = edgeContaining(sN.si, sN.i), edgeContaining(gN.si, gN.i)
    if not sE or not gE then
        local d = direct()
        if d then return d end
        return nil, 'network graph error'
    end

    if sE == gE then
        return subPts(sN.si, sN.i, gN.i)
    end

    local se, ge = Net.edges[sE], Net.edges[gE]
    local dist, prev, open, closed = {}, {}, {}, {}
    local function push(node, cost, from, viaEdge)
        if dist[node] and dist[node] <= cost then return end
        dist[node] = cost
        prev[node] = { from = from, edge = viaEdge }
        table.insert(open, node)
    end
    push(se.a, arcLen(se.si, se.i1, sN.i), 'START', sE)
    push(se.b, arcLen(se.si, sN.i, se.i2), 'START', sE)

    local found
    while #open > 0 do
        local bi, bf = nil, math.huge
        for oi, node in ipairs(open) do
            local f = dist[node] + (Net.nodes[node].pos - toPos).Magnitude
            if f < bf then bf = f; bi = oi end
        end
        local cur = table.remove(open, bi)
        if not closed[cur] then
            closed[cur] = true
            if cur == ge.a or cur == ge.b then
                found = cur
                break
            end
            for _, ei in ipairs(Net.nodes[cur].adj) do
                local e = Net.edges[ei]
                local nxt = (e.a == cur) and e.b or e.a
                if not closed[nxt] then
                    push(nxt, dist[cur] + e.len, cur, ei)
                end
            end
        end
    end
    if not found then
        local d = direct()
        if d then return d end
        return nil, 'no route found -- network disconnected?'
    end

    -- reconstruct node chain, then stitch polylines
    local chain = {}
    local cur = found
    while cur ~= 'START' do
        table.insert(chain, 1, { node = cur, edge = prev[cur].edge })
        cur = prev[cur].from
    end
    local route = {}
    local function append(list)
        for i = (#route > 0 and 2 or 1), #list do table.insert(route, list[i]) end
    end
    do -- start partial along sE
        local e = Net.edges[chain[1].edge]
        local targetIdx = (chain[1].node == e.a) and e.i1 or e.i2
        append(subPts(e.si, sN.i, targetIdx))
    end
    for ci = 2, #chain do -- full middle edges, oriented by entry node
        local e = Net.edges[chain[ci].edge]
        if e.a == chain[ci - 1].node then
            append(subPts(e.si, e.i1, e.i2))
        else
            append(subPts(e.si, e.i2, e.i1))
        end
    end
    do -- goal partial along gE
        local fromIdx = (found == ge.a) and ge.i1 or ge.i2
        append(subPts(ge.si, fromIdx, gN.i))
    end
    return route
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
    -- recorded paths need real length; routes may be legitimately tiny
    -- (destination 20 studs away is still a valid drive)
    local minPts = entry.isRoute and 2 or 8
    if not pts or #pts < minPts then toast('path file is empty or corrupt', C.RED) return end

    -- must start near the path (recorded paths only -- network routes
    -- start at the nearest road point and are acquired by driving to it)
    local here = sp.Position
    local startIdx, startDist = 1, math.huge
    for i = 1, #pts, 4 do
        local d = (Vector3.new(pts[i][1], pts[i][2], pts[i][3]) - here).Magnitude
        if d < startDist then startDist = d; startIdx = i end
    end
    if not entry.isRoute and startDist > OFFPATH_HARD then
        toast('too far from the path (' .. math.floor(startDist) .. ' studs) — get closer', C.RED)
        return
    end
    S.acquired = startDist < 12

    S.mode = 'playing'
    S.playData = data
    S.playFile = entry.file
    S.playIdx = startIdx
    S.playStart = os.clock()
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
    local reversingUntil = 0
    local endParkT = 0
    local steerHoldT = 0

    playConn = bind(RunService.Heartbeat:Connect(function(dt)
        if S.mode ~= 'playing' then return end
        local sp2 = seat()
        if not sp2 then
            stopPlayback('you left the vehicle')
            return
        end

        -- track the character root -- same reference point the recorder
        -- sampled, so playback measures against the exact recorded line
        local ref = hrp()
        local pos = (ref and ref.Position) or sp2.Position
        local spd = sp2.AssemblyLinearVelocity.Magnitude
        local idx, err = closestIdx(pts, S.playIdx, pos)
        S.playIdx = idx

        -- learning: track worst cross-track error per bucket
        local bucket = tostring(math.floor(idx / BUCKET_SIZE))
        if not S.bucketErr[bucket] or err > S.bucketErr[bucket] then
            S.bucketErr[bucket] = err
        end

        -- arrival check: generous window near the end, plus a "parked at
        -- destination" clause -- stopped close to the end counts as done
        local last = pts[#pts]
        local dEnd = (Vector3.new(last[1], last[2], last[3]) - pos).Magnitude
        local nearEnd = idx >= #pts - 10
        if (nearEnd and dEnd < 14) or dEnd < 7 then
            stopPlayback(nil, true)
            return
        end
        if nearEnd and dEnd < 25 and spd < 2.5 then
            endParkT = endParkT + dt
            if endParkT > 1.2 then
                stopPlayback(nil, true)
                return
            end
        else
            endParkT = 0
        end

        -- hard off-path abort -- only once the line has been acquired
        -- (network routes may legitimately begin far from the road)
        if err < 8 then S.acquired = true end
        if S.acquired and err > OFFPATH_HARD then
            stopPlayback('lost the path (' .. math.floor(err) .. ' studs off)')
            return
        elseif not S.acquired and err > 1500 then
            -- acquisition drives TO the route; only a truly broken state
            -- (wrong map region, teleport mid-drive) aborts before touch
            stopPlayback('lost before reaching the route')
            return
        end

        -- obstacle scan on a slow tick
        obstAcc = obstAcc + dt
        if obstAcc >= OBST_TICK then
            obstAcc = 0
            local blocker, bDist, bPos = scanAhead(sp2, pts, idx)
            -- two-zone response: far hit on the line = caution (slow down
            -- toward it), close hit = full brake-and-wait
            S.caution = nil
            if blocker and bDist and bDist > math.clamp(spd * 1.1, 12, 45) then
                S.caution = bDist
                blocker = nil
            end
            -- ambient tightness: short side rays -- narrow streets and
            -- cluttered spots get driven slowly
            do
                local f2 = Vector3.new(sp2.CFrame.LookVector.X, 0, sp2.CFrame.LookVector.Z)
                if f2.Magnitude > 0.1 then
                    f2 = f2.Unit
                    local hits, minD = 0, math.huge
                    for _, ang in ipairs({ -90, -40, 40, 90 }) do
                        local a = math.rad(ang)
                        local dirR = Vector3.new(
                            f2.X * math.cos(a) - f2.Z * math.sin(a), 0,
                            f2.X * math.sin(a) + f2.Z * math.cos(a))
                        local r2 = workspace:Raycast(sp2.Position + Vector3.new(0, 2, 0), dirR * 9, rayParams)
                        if r2 and r2.Instance.CanCollide and r2.Normal.Y <= 0.6 then
                            hits = hits + 1
                            local d2 = (r2.Position - sp2.Position).Magnitude
                            if d2 < minD then minD = d2 end
                        end
                    end
                    S.tight = (hits >= 2) and minD or nil
                end
            end
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
                S.blocked.pos = bPos -- fence around the HIT POINT, not the
                                     -- instance center (walls are long)
            elseif S.blocked then
                S.clearSince = S.clearSince or os.clock()
                if os.clock() - S.clearSince >= OBST_CLEAR_TIME then
                    S.blocked = nil
                    S.clearSince = nil
                end
            end
        end

        -- blocked: brake to a stop and hold (physics-assisted, additive)
        if S.blocked then
            if spd > 1.5 then
                applyDrive(-1, 0)
                local vel = sp2.AssemblyLinearVelocity
                local horiz = Vector3.new(vel.X, 0, vel.Z)
                if horiz.Magnitude > 0.5 then
                    local decel = math.min(horiz.Magnitude, 45 * dt)
                    sp2.AssemblyLinearVelocity = vel - horiz.Unit * decel
                end
            else
                applyDrive(0, 0)
            end
            setPlayStatus('waiting — ' .. string.lower(S.blocked.name)
                .. (S.blocked.class == 'traffic' and ' [traffic]' or ' [static]'), idx, #pts, spd, pts)
            -- dynamic fix: static blocker (not traffic) for 12s -> fence
            -- off its cells in the grid and recompute the route around it
            if S.blocked.class == 'static' and os.clock() - S.blocked.since > 12 then
                if S.routeDest and routeAndDrive then
                    local bp = S.blocked.pos
                    if not bp then pcall(function() bp = S.blocked.inst.Position end) end
                    if bp then
                        local bx = math.floor(bp.X / Scan.CELL + 0.5)
                        local bz = math.floor(bp.Z / Scan.CELL + 0.5)
                        for dx = -3, 3 do
                            for dz = -3, 3 do
                                S.blockCells[(bx + dx) .. ',' .. (bz + dz)] = os.clock() + 120
                            end
                        end
                    end
                    local dest = S.routeDest
                    toast('blocked 12s — rerouting around the obstacle', C.YELLOW)
                    stopPlayback(nil, false, true)
                    task.defer(routeAndDrive, dest)
                else
                    toast('blocked 15s+ by static geometry — path may be stale', C.YELLOW)
                    S.blocked.since = os.clock() -- don't spam
                end
            end
            return
        end

        -- stuck recovery: hardcoded reverse burst, then resume the path
        if os.clock() < reversingUntil then
            -- velocity-only reverse: NO keys -- some games (swf) shift
            -- gears on S, which wrecks the recovery
            applyDrive(0, 0)
            local lv = sp2.CFrame.LookVector
            local back = Vector3.new(-lv.X, 0, -lv.Z)
            if back.Magnitude > 0.1 then
                back = back.Unit
                local vel = sp2.AssemblyLinearVelocity
                if vel:Dot(back) < 10 then
                    sp2.AssemblyLinearVelocity = vel + back * (28 * dt)
                end
            end
            setPlayStatus('reversing -- unsticking', idx, #pts, spd, pts)
            return
        end

        -- pd pure pursuit steering:
        --  p: squared response -- small errors get micro corrections,
        --     real turns still reach full lock
        --  d: yaw-rate damping -- if already rotating toward the line,
        --     back off instead of piling on (kills overshoot spirals)
        local L = math.clamp(LOOKAHEAD_MIN + spd * 0.30, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
        local target = lookaheadPoint(pts, idx, L)
        local rel = sp2.CFrame:PointToObjectSpace(target)
        local angle = math.atan2(rel.X, -rel.Z)
        local steerDiv = math.rad(30) * (1 + spd / 50)
        -- soft-progressive response: keeps micro corrections small but
        -- restores mid-range authority (pure squaring choked real turns)
        local x = math.clamp(angle / steerDiv, -1, 1)
        local p = x * (0.4 + 0.6 * math.abs(x))
        local yawDamp = math.clamp(sp2.AssemblyAngularVelocity.Y * 0.42, -0.7, 0.7)

        -- predictive cross-track steering: correct based on where the
        -- velocity is carrying us, not where we are. drifting away ->
        -- counters early before going wide. converging fast -> eases off
        -- before crossing the line. like a human.
        local ct = 0
        local align = 1
        local latVelAbs = 0
        local acquiring = err > 6
        do
            local a = pts[idx]
            local b = pts[math.min(idx + 1, #pts)]
            local d = Vector3.new(b[1] - a[1], 0, b[3] - a[3])
            if d.Magnitude > 0.01 then
                d = d.Unit
                local rightOf = Vector3.new(-d.Z, 0, d.X)
                local lat = Vector3.new(pos.X - a[1], 0, pos.Z - a[3]):Dot(rightOf)
                local vel = sp2.AssemblyLinearVelocity
                local latVel = Vector3.new(vel.X, 0, vel.Z):Dot(rightOf)
                latVelAbs = math.abs(latVel)
                -- longer horizon while acquiring the line: counter-steer
                -- BEFORE crossing it, not after sailing past
                local predLat = lat + latVel * (acquiring and 0.6 or 0.35)
                -- soft deadzone: "somewhat below" the line, not surgically
                -- glued -- sub-quarter-stud offsets are left alone
                local mag = math.max(math.abs(predLat) - 0.25, 0)
                local effLat = (predLat >= 0 and 1 or -1) * mag
                ct = -math.clamp(effLat * 0.20 * (1 + math.abs(effLat) / 5), -0.8, 0.8)
                -- offset-aware speed softening: near the line, high-speed
                -- authority is cut (stability, no weave). genuinely off the
                -- line the softening fades out -- accuracy demands pull
                local soften = 1 / (1 + spd / 55)
                local offBlend = math.clamp((math.abs(effLat) - 1) / 3, 0, 1)
                ct = ct * (soften + (1 - soften) * offBlend)
            end
        end
        -- how aligned is the nose with the route ahead?
        do
            local toT = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
            if toT.Magnitude > 1 then
                local fwd = sp2.CFrame.LookVector
                align = Vector3.new(fwd.X, 0, fwd.Z).Unit:Dot(toT.Unit)
            end
        end
        -- demand-aware ceiling: corrections stay capped at speed (jerks
        -- become drifts), but when the ROAD demands a real turn the
        -- pursuit term is allowed through -- up to 0.75 even flat out
        local baseCap = math.clamp(1.25 - spd / 110, 0.35, 1)
        local steerCap = math.max(baseCap, math.min(0.75, math.abs(p)))
        local steer = math.clamp(p + yawDamp + ct, -steerCap, steerCap)
        -- acquiring the line while already pointing at it: stop sawing
        -- the wheel -- speed closes the gap, not steering. ONLY when not
        -- flying sideways: fast lateral convergence needs the prediction's
        -- full counter-steer authority to unwind before crossing
        if acquiring and align > 0.75 and latVelAbs < 8 then
            steer = steer * 0.5
        end

        -- target speed: recorded profile x multiplier x learned factor, curve slowdown
        local recSpd = pts[math.min(idx + 4, #pts)][4] or 16
        local learned = (S.playData.learned and S.playData.learned[bucket]) or 1
        local curveCut = 1 - math.min(math.abs(angle) / math.rad(60), 1) * 0.45
        local targetSpd = math.max(6, recSpd * S.speedMult * learned * curveCut)

        -- corner anticipation: natural braking envelope, like a driver who
        -- saw the turn coming. corner speed from grip physics; allowed
        -- speed NOW follows v = sqrt(vc^2 + 2*a*d) -- big early braking
        -- when fast, tapering off, corner speed reached ~12 studs early.
        -- k threshold ignores dull bends entirely (no fake slowdowns)
        local k, dCorner = maxCurvatureAhead(pts, idx, spd)
        if k > 0.0025 then
            -- 8% safety trim on corner speed: margin for obstacles instead
            -- of exiting every tight turn at the edge of control
            local vCorner = math.max(math.sqrt(26 / k) * 0.92, 11)
            local dBrake = math.max(dCorner - 12, 0)
            local vAllowed = math.sqrt(vCorner * vCorner + 2 * 22 * dBrake)
            targetSpd = math.min(targetSpd, vAllowed)
        end

        -- recovery mode: too far off line. pointing at the path already?
        -- merge back with SPEED, not steering. pointing away? slow down
        -- and let the controller bring the nose around first
        if err > OFFPATH_SOFT then
            if align > 0.75 then
                targetSpd = math.max(targetSpd, math.min(spd + 12, 30))
            else
                targetSpd = math.min(targetSpd, 10)
            end
        end

        -- ease into the destination like a driver, not a dart
        if dEnd < 60 then
            targetSpd = math.min(targetSpd, math.max(dEnd * 0.35, 6))
        end
        -- caution: something sits on the line ahead -- approach it slowly
        -- instead of driving into a panic stop
        if S.caution then
            targetSpd = math.min(targetSpd, math.max(S.caution * 0.35, 8))
        end
        -- tight spot: objects close on both sides -- creep through
        if S.tight then
            targetSpd = math.min(targetSpd, 10 + S.tight * 2.2)
        end
        -- sustained hard steering at speed = the correction is losing the
        -- race. slow = turn as long as you like; fast = brake INTO the
        -- correction until the wheel relaxes (spin-out prevention)
        if math.abs(steer) > 0.45 and spd > 25 then
            steerHoldT = steerHoldT + dt
        else
            steerHoldT = math.max(0, steerHoldT - dt * 2)
        end
        if steerHoldT > 0.6 then
            targetSpd = math.min(targetSpd, math.max(spd * 0.8, 14))
        end

        -- throttle: proportional band with a firm floor -- tiny pwm duties
        -- from small proportional values are why it sometimes crawled at
        -- 80% of target forever
        local throttle = math.clamp((targetSpd - spd) / 5, -1, 1)
        if spd < targetSpd * 0.5 then
            throttle = 1
        elseif spd < targetSpd - 1 and throttle < 0.45 then
            throttle = 0.45
        end
        applyDrive(throttle, steer)

        -- velocity assist: physics-level, additive (never a multiplier --
        -- works from a dead stop). fills whatever gap the game's own
        -- controls leave; contributes nothing once at target speed.
        do
            local vel = sp2.AssemblyLinearVelocity
            local horiz = Vector3.new(vel.X, 0, vel.Z)
            local flatT = Vector3.new(target.X - sp2.Position.X, 0, target.Z - sp2.Position.Z)
            if flatT.Magnitude > 0.5 then
                local dir = flatT.Unit
                if throttle > 0.05 and horiz.Magnitude < targetSpd then
                    local accel = math.min((targetSpd - horiz.Magnitude) * 2, 30)
                    sp2.AssemblyLinearVelocity = vel + dir * (accel * dt)
                elseif throttle < -0.05 and horiz.Magnitude > 1 then
                    local decel = math.min(horiz.Magnitude, math.min(-throttle * 40, 45) * dt)
                    sp2.AssemblyLinearVelocity = vel - horiz.Unit * decel
                end
            end
        end

        -- stuck detection -> reverse burst. ANY commanded-forward-but-not-
        -- moving counts, not just full throttle
        if throttle > 0.15 and spd < 2 then
            stuckT = stuckT + dt
            if stuckT > 3 then
                stuckT = 0
                reversingUntil = os.clock() + 1.4
                toast('vehicle appears stuck — reversing', C.YELLOW)
            end
        else
            stuckT = 0
        end

        setPlayStatus(nil, idx, #pts, spd, pts)
    end))
end

function stopPlayback(reason, arrived, quiet)
    if S.mode ~= 'playing' then return end
    S.mode = 'idle'
    if playConn then playConn:Disconnect() playConn = nil end
    releaseDrive()
    clearPlayPath()
    hidePlayHUD()
    if not quiet then S.routeDest = nil end

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
    elseif not quiet then
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
    Size = UDim2.new(0, 52, 0, 30),
    BackgroundColor3 = C.BG1,
    Text = 'k*',
    Font = FONTB, TextSize = 15, TextColor3 = C.TEXT,
    AutoButtonColor = false,
    Parent = gui,
}, { corner(6), stroke(C.BORDER), vgradient(Color3.fromRGB(26, 26, 26), Color3.fromRGB(12, 12, 12)) })
hoverable(kBtn, C.BG1, C.BG3)
-- live status dot on the k chip: dim=idle, green=recording,
-- white=driving, yellow=scanning/rewinding
local kDot = new('Frame', {
    BackgroundColor3 = C.DIM, BorderSizePixel = 0,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -7, 0.5, 0), Size = UDim2.new(0, 5, 0, 5),
    Parent = kBtn,
}, { corner(3) })
bind(RunService.Heartbeat:Connect(function()
    local c = C.DIM
    if S.mode == 'recording' then c = C.GREEN
    elseif S.mode == 'playing' then c = C.WHITE
    elseif S.mode == 'rewinding' then c = C.YELLOW end
    if Scan.running then c = C.YELLOW end
    kDot.BackgroundColor3 = c
end))

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
    Size = UDim2.new(0, 700, 0, 520),
    BackgroundColor3 = C.BG0,
    Parent = overlay,
}, { corner(10), stroke(C.BORDER), vgradient(Color3.fromRGB(21, 21, 21), Color3.fromRGB(7, 7, 7)) })
local panelScale = new('UIScale', { Scale = 1, Parent = panel })

-- title bar (fake wm window chrome)
local titleBar = new('Frame', {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), Parent = panel,
})
new('Frame', { -- accent dot
    BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
    Position = UDim2.new(0, 18, 0.5, -3), Size = UDim2.new(0, 6, 0, 6), Parent = titleBar,
}, { corner(3) })
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONTB, TextSize = 16, TextColor3 = C.TEXT,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 34, 0, 0), Size = UDim2.new(0, 140, 1, 0),
    Text = 'konstant a*', Parent = titleBar,
})
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 146, 0, 1), Size = UDim2.new(0, 260, 1, 0),
    Text = '// autodriver suite', Parent = titleBar,
})
for di = 1, 2 do -- wm deco squares
    new('Frame', {
        BackgroundColor3 = di == 1 and C.BG3 or C.BORDER, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -50 - (di - 1) * 16, 0.5, 0),
        Size = UDim2.new(0, 8, 0, 8), Parent = titleBar,
    }, { corner(2) })
end
new('Frame', { -- title divider
    BackgroundColor3 = C.BORDER, BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 1, -1), Size = UDim2.new(1, -24, 0, 1), Parent = titleBar,
})
local closeBtn = new('TextButton', {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
    Size = UDim2.new(0, 26, 0, 26), BackgroundColor3 = C.BG2,
    Font = FONT, TextSize = 13, TextColor3 = C.MUT, Text = 'x',
    AutoButtonColor = false, Parent = titleBar,
}, { corner(4), stroke(C.BORDER) })
hoverable(closeBtn, C.BG2, Color3.fromRGB(60, 25, 25))

-- workspace tabs (hyprland style: 1:record 2:load 3:scan)
local tabRow = new('Frame', {
    BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 54),
    Size = UDim2.new(1, -36, 0, 30), Parent = panel,
}, { new('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local tabs, tabBtns, tabFrames = { 'record', 'load', 'scan' }, {}, {}
local activeTab = 'record'

local content = new('Frame', {
    BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 94),
    Size = UDim2.new(1, -36, 1, -140), Parent = panel,
})

local function selectTab(name)
    activeTab = name
    for t, btn in pairs(tabBtns) do
        local on = (t == name)
        tw(btn, { BackgroundColor3 = on and C.BG3 or C.BG1, TextColor3 = on and C.TEXT or C.DIM }, 0.15)
        local u = btn:FindFirstChild('U')
        if u then
            tw(u, { Size = on and UDim2.new(1, -14, 0, 2) or UDim2.new(0, 0, 0, 2) }, 0.22)
        end
        tabFrames[t].Visible = on
    end
    if name == 'load' then refreshLoadList() end
    -- content slide-in
    local f = tabFrames[name]
    f.Position = UDim2.new(0, 0, 0, 14)
    tw(f, { Position = UDim2.new(0, 0, 0, 0) }, 0.24)
end

for i, t in ipairs(tabs) do
    local btn = new('TextButton', {
        Size = UDim2.new(0, 96, 1, 0), BackgroundColor3 = C.BG1,
        Font = FONT, TextSize = 12, TextColor3 = C.DIM,
        Text = i .. ':' .. t, AutoButtonColor = false, LayoutOrder = i,
        Parent = tabRow,
    }, { corner(5), stroke(C.BORDER) })
    new('Frame', { -- animated underline
        Name = 'U', BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3),
        Size = UDim2.new(0, 0, 0, 2), Parent = btn,
    }, { corner(1) })
    tabBtns[t] = btn
    tabFrames[t] = new('Frame', { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = false, Parent = content })
    btn.MouseButton1Click:Connect(function() selectTab(t) end)
end

-- waybar-style status bar (bottom of panel)
local statusBar = new('Frame', {
    BackgroundColor3 = C.BG1, Position = UDim2.new(0, 12, 1, -36),
    Size = UDim2.new(1, -24, 0, 26), Parent = panel,
}, { corner(5), stroke(C.BORDER), vgradient(Color3.fromRGB(20, 20, 20), Color3.fromRGB(13, 13, 13)) })
local sbLeft = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(0.6, 0, 1, 0),
    Text = '', Parent = statusBar,
})
local sbRight = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Right,
    Position = UDim2.new(0.4, 0, 0, 0), Size = UDim2.new(0.6, -10, 1, 0),
    Text = '', Parent = statusBar,
})
bind(RunService.Heartbeat:Connect(function()
    if not overlay.Visible then return end
    sbLeft.Text = 'mode ' .. S.mode .. (Scan.running and '  ·  scanning' or '')
    sbRight.Text = string.format('cells %s (%s road)  ·  v4.5  ·  %s',
        Scan.count > 0 and tostring(Scan.count) or '--',
        Scan.roadCount and Scan.roadCount > 0 and tostring(Scan.roadCount) or '--',
        os.date('%H:%M:%S'))
end))

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
        new('Frame', { -- header rule filling the rest of the row
            BackgroundColor3 = C.BORDER, BorderSizePixel = 0,
            Position = UDim2.new(0, 20 + #title * 7, 0, 15),
            Size = UDim2.new(1, -(32 + #title * 7), 0, 1), Parent = f,
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
        .. '3. hold R (or hud button) to rewind — car\n'
        .. '   and line both walk backwards\n'
        .. '   green = path / red = old / yellow = redone\n'
        .. '4. end path, then: save path = a to b route\n'
        .. '   save as road = network segment for a*\n\n'
        .. 'record each road once as a road segment,\n'
        .. 'then auto-drive to any coords (load tab).',
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
    Text = 'speed x (1 = normal)', Parent = loadRight,
})

local invBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 0, 168), Size = UDim2.new(0.5, -16, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    Text = 'invert steer: off', AutoButtonColor = false, Parent = loadRight,
}, { corner(4), stroke(C.BORDER) })
invBtn.MouseButton1Click:Connect(function()
    S.invertSteer = not S.invertSteer
    invBtn.Text = 'invert steer: ' .. (S.invertSteer and 'on' or 'off')
    invBtn.TextColor3 = S.invertSteer and C.TEXT or C.DIM
end)
-- licensed driver: on = roads only, off = lawn shortcuts allowed
local licBtn = new('TextButton', {
    Position = UDim2.new(0.5, 4, 0, 168), Size = UDim2.new(0.5, -16, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.TEXT,
    Text = 'licensed: on', AutoButtonColor = false, Parent = loadRight,
}, { corner(4), stroke(C.BORDER) })
licBtn.MouseButton1Click:Connect(function()
    S.licensed = not S.licensed
    licBtn.Text = 'licensed: ' .. (S.licensed and 'on' or 'off')
    licBtn.TextColor3 = S.licensed and C.TEXT or C.DIM
    toast(S.licensed and 'licensed driver — roads only' or 'unlicensed — shortcuts allowed', C.WHITE)
end)

-- network auto-drive section
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 12, 0, 200), Size = UDim2.new(1, -24, 0, 14),
    Text = '~/network auto-drive (a*)', Parent = loadRight,
})
local coordsBox = new('TextBox', {
    Position = UDim2.new(0, 12, 0, 218), Size = UDim2.new(0.56, -14, 0, 26),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 12, TextColor3 = C.TEXT,
    Text = '6398, 23, -42', PlaceholderText = 'x, y, z', ClearTextOnFocus = false,
    Parent = loadRight,
}, { corner(4), stroke(C.BORDER) })
local netGoBtn = new('TextButton', {
    Position = UDim2.new(0.56, 4, 0, 218), Size = UDim2.new(0.44, -16, 0, 26),
    BackgroundColor3 = C.BG3, Font = FONTB, TextSize = 12, TextColor3 = C.TEXT,
    Text = '> drive there', AutoButtonColor = false, Parent = loadRight,
}, { corner(4), stroke(C.BORDER2) })
hoverable(netGoBtn, C.BG3, Color3.fromRGB(45, 45, 45))
local netStatus = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 10, TextColor3 = C.DIM,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 12, 0, 250), Size = UDim2.new(1, -24, 0, 14),
    Text = 'network: not loaded', Parent = loadRight,
})

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

-- auto-drive: scan grid a* first, road network fallback. also called by
-- the dynamic reroute when a static obstacle fences off the current route
routeAndDrive = function(destV)
    local r = hrp()
    if not r then toast('no character', C.RED) return end
    toast('routing...', C.WHITE)
    task.spawn(function()
        local route, rerr, mode
        -- scan grid first: any scanned coordinate is reachable
        if Scan.available() then
            local ok, rt, er, usedFree = pcall(Scan.route, r.Position, destV)
            if ok and rt then
                route, mode = rt, 'scan'
                if usedFree then
                    toast('note: no road-only path — free route (check road tags / fences)', C.YELLOW)
                end
            else
                rerr = ok and er or ('scan error: ' .. tostring(rt):sub(1, 50))
            end
        end
        -- recorded road network as fallback
        if not route then
            local nSegs = Net.load()
            if nSegs > 0 then
                local ok, rt, er = pcall(Net.route, r.Position, destV)
                if ok and rt then
                    route, mode = rt, 'network'
                elseif not rerr then
                    rerr = ok and er or ('network error: ' .. tostring(rt):sub(1, 50))
                end
            elseif not rerr then
                rerr = 'no scan and no road segments — scan tab or record roads'
            end
        end
        if not route then
            toast(rerr or 'routing failed', C.RED)
            netStatus.Text = 'routing failed'
            return
        end
        -- final honesty gate: if the route ends far from the requested
        -- destination, the area isn't covered -- refuse instead of
        -- driving somewhere else and calling it arrival
        do
            local lastP = route[#route]
            local endGap = (Vector3.new(lastP[1], lastP[2], lastP[3]) - destV).Magnitude
            if endGap > 150 then
                toast(('route ends %d studs short — that area is not scanned yet, extend the scan toward it'):format(endGap), C.RED)
                netStatus.Text = string.format('coverage gap: %d studs', endGap)
                return
            end
        end
        netStatus.Text = string.format('routed via %s — %d points', mode, #route)
        -- final approach: short straight taper from the road exit to the
        -- exact destination (parking lots etc), slow speeds
        local lastP = route[#route]
        local lastV = Vector3.new(lastP[1], lastP[2], lastP[3])
        local gap = (destV - lastV).Magnitude
        if gap > 4 and gap < 120 then
            local n = math.max(math.floor(gap / 2), 2)
            for i = 1, n do
                local t = i / n
                local p = lastV:Lerp(destV, t)
                table.insert(route, { p.X, p.Y, p.Z, math.max(16 * (1 - t), 8) })
            end
        end
        if #route < 2 then toast('already at the destination', C.WHITE) return end
        S.speedMult = math.clamp(tonumber(multBox.Text) or 1, 0.3, 3)
        multBox.Text = tostring(S.speedMult)
        startPlayback({
            file = nil,
            isRoute = true,
            data = {
                name = string.format('route > %d, %d', destV.X, destV.Z),
                points = route, learned = {}, runs = 0,
                distance = 0,
            },
        })
        S.routeDest = destV -- after start (stopPlayback clears it otherwise)
    end)
end

netGoBtn.MouseButton1Click:Connect(function()
    local x, y, z = coordsBox.Text:match('(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)')
    if not x then toast('coords like: 6398, 23, -42', C.RED) return end
    routeAndDrive(Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
end)

-- ============================================================
-- // scan tab
-- ============================================================
local scanTab = tabFrames['scan']
local scanLeft = tile(scanTab, UDim2.new(0, 0, 0, 0), UDim2.new(0.5, -5, 1, 0), '~/scanner')
local scanRight = tile(scanTab, UDim2.new(0.5, 5, 0, 0), UDim2.new(0.5, -5, 1, 0), '~/how it works')

local scanStartBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 40),
    BackgroundColor3 = C.BG3, Font = FONTB, TextSize = 13, TextColor3 = C.TEXT,
    Text = '>  scan from here', AutoButtonColor = false, Parent = scanLeft,
}, { corner(5), stroke(C.BORDER2) })
hoverable(scanStartBtn, C.BG3, Color3.fromRGB(45, 45, 45))
local scanStopBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 0, 80), Size = UDim2.new(0.5, -16, 0, 26),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.TEXT,
    Text = 'stop + save', AutoButtonColor = false, Parent = scanLeft,
}, { corner(4), stroke(C.BORDER) })
local scanClearBtn = new('TextButton', {
    Position = UDim2.new(0.5, 4, 0, 80), Size = UDim2.new(0.5, -16, 0, 26),
    BackgroundColor3 = C.BG1, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    Text = 'wipe scan', AutoButtonColor = false, Parent = scanLeft,
}, { corner(4), stroke(C.BORDER) })
hoverable(scanStopBtn, C.BG2, Color3.fromRGB(45, 45, 45))
hoverable(scanClearBtn, C.BG1, Color3.fromRGB(55, 22, 22))
-- ground overlay: paints the grid around you (white = road tag,
-- grey = drivable) so scan coverage is visible instead of guessed
local scanPrevBtn = new('TextButton', {
    Position = UDim2.new(0, 12, 0, 112), Size = UDim2.new(1, -24, 0, 24),
    BackgroundColor3 = C.BG2, Font = FONT, TextSize = 11, TextColor3 = C.DIM,
    Text = 'scan overlay: off', AutoButtonColor = false, Parent = scanLeft,
}, { corner(4), stroke(C.BORDER) })
local scanStatus = new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    Position = UDim2.new(0, 12, 0, 146), Size = UDim2.new(1, -24, 1, -158),
    Text = 'state    idle\ncells    0\nchecked  0', Parent = scanLeft,
})

local prevFolder = Instance.new('Folder')
prevFolder.Name = 'KAStarScanPreview'
prevFolder.Parent = workspace
local scanPrevOn, prevAcc = false, 0
scanPrevBtn.MouseButton1Click:Connect(function()
    scanPrevOn = not scanPrevOn
    scanPrevBtn.Text = 'scan overlay: ' .. (scanPrevOn and 'on' or 'off')
    scanPrevBtn.TextColor3 = scanPrevOn and C.TEXT or C.DIM
    if not scanPrevOn then prevFolder:ClearAllChildren() end
    if scanPrevOn and not Scan.available() then
        toast('no scan to preview', C.RED)
    end
end)
bind(RunService.Heartbeat:Connect(function(dt)
    if not scanPrevOn then return end
    prevAcc = prevAcc + dt
    if prevAcc < 2 then return end
    prevAcc = 0
    prevFolder:ClearAllChildren()
    local r = hrp()
    if not r or not Scan.grid then return end
    local cx0 = math.floor(r.Position.X / Scan.CELL + 0.5)
    local cz0 = math.floor(r.Position.Z / Scan.CELL + 0.5)
    local made = 0
    for dx = -20, 20 do
        for dz = -20, 20 do
            local k = (cx0 + dx) .. ',' .. (cz0 + dz)
            local y = Scan.grid[k]
            if y and made < 1700 then
                made = made + 1
                local p = Instance.new('Part')
                p.Anchored = true
                p.CanCollide = false
                p.CanQuery = false
                p.CanTouch = false
                p.CastShadow = false
                p.Material = Enum.Material.Neon
                p.Transparency = 0.68
                p.Color = Scan.roads[k] and C.WHITE or Color3.fromRGB(85, 85, 85)
                p.Size = Vector3.new(Scan.CELL - 0.8, 0.12, Scan.CELL - 0.8)
                p.CFrame = CFrame.new((cx0 + dx) * Scan.CELL, y + 0.15, (cz0 + dz) * Scan.CELL)
                p.Parent = prevFolder
            end
        end
    end
end))
new('TextLabel', {
    BackgroundTransparency = 1, Font = FONT, TextSize = 11.5, TextColor3 = C.MUT,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true, LineHeight = 1.35,
    Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 1, -44),
    Text = 'park on a road, hit scan. it learns the\n'
        .. 'surface under you and flood-fills every\n'
        .. 'connected drivable cell -- streets, lots,\n'
        .. 'everything touching the road system.\n\n'
        .. 'saves to scan.json. rejoin-proof. scan\n'
        .. 'again anywhere to extend (it merges).\n\n'
        .. 'auto-drive uses the scan first, recorded\n'
        .. 'road segments as fallback. any scanned\n'
        .. 'coordinate becomes reachable.',
    Parent = scanRight,
})

scanStartBtn.MouseButton1Click:Connect(function() Scan.start() end)
scanStopBtn.MouseButton1Click:Connect(function() Scan.stop(true) end)
scanClearBtn.MouseButton1Click:Connect(function() Scan.clear() end)

bind(RunService.Heartbeat:Connect(function()
    if not scanStatus.Parent then return end
    if Scan.running or Scan.count > 0 then
        scanStatus.Text = string.format(
            'state    %s\ncells    %d drivable\nroad     %d tagged\ntested   %d (rejected %d)\nfrontier %d\ntime     %s',
            Scan.running and 'scanning...' or 'idle (saved)',
            Scan.count, Scan.roadCount, Scan.checked,
            math.max(Scan.checked - Scan.count, 0),
            Scan.running and (Scan.fTail - Scan.fHead + 1) or 0,
            Scan.running and fmtTime(os.clock() - Scan.startedAt) or '--:--')
    end
end))

-- ============================================================
-- // save dialog (modal over panel)
-- ============================================================
local saveModal = new('Frame', {
    Visible = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
    Size = UDim2.new(1, 0, 1, 0), ZIndex = 10, Parent = panel,
}, { corner(8) })
local saveBox = new('Frame', {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 340, 0, 202), BackgroundColor3 = C.BG1, ZIndex = 11,
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
    Position = UDim2.new(0, 16, 1, -88), Size = UDim2.new(0.5, -22, 0, 32),
    BackgroundColor3 = C.BG3, Font = FONTB, TextSize = 12, TextColor3 = C.TEXT,
    Text = 'save path', AutoButtonColor = false, ZIndex = 11, Parent = saveBox,
}, { corner(4), stroke(C.BORDER2) })
local saveNo = new('TextButton', {
    Position = UDim2.new(0.5, 6, 1, -88), Size = UDim2.new(0.5, -22, 0, 32),
    BackgroundColor3 = C.BG1, Font = FONT, TextSize = 12, TextColor3 = C.DIM,
    Text = 'discard', AutoButtonColor = false, ZIndex = 11, Parent = saveBox,
}, { corner(4), stroke(C.BORDER) })
local saveRoadBtn = new('TextButton', {
    Position = UDim2.new(0, 16, 1, -46), Size = UDim2.new(1, -32, 0, 32),
    BackgroundColor3 = C.BG2, Font = FONTB, TextSize = 12, TextColor3 = C.TEXT,
    Text = 'save as road segment  (network)', AutoButtonColor = false, ZIndex = 11, Parent = saveBox,
}, { corner(4), stroke(C.BORDER2) })
hoverable(saveOk, C.BG3, Color3.fromRGB(45, 45, 45))
hoverable(saveNo, C.BG1, Color3.fromRGB(55, 22, 22))
hoverable(saveRoadBtn, C.BG2, Color3.fromRGB(45, 45, 45))

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
saveRoadBtn.MouseButton1Click:Connect(function()
    if saveRecording(nameBox.Text, true) then
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
new('Frame', { -- left accent bar
    BackgroundColor3 = C.GREEN, BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(0, 2, 1, -20), Parent = recHud,
})
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

-- rewind keybind: hold R while recording (textboxes excluded)
bind(UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.R and S.mode == 'recording' then
        rewindBtn.TextColor3 = C.YELLOW
        setRewind(true)
    end
end))
bind(UserInputService.InputEnded:Connect(function(inp)
    if inp.KeyCode == Enum.KeyCode.R and S.mode == 'rewinding' then
        rewindBtn.TextColor3 = C.MUT
        setRewind(false)
    end
end))

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
new('Frame', { -- left accent bar
    BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(0, 2, 1, -20), Parent = playHud,
})
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
    local line = status or string.format('ctl      t %+.2f  s %+.2f', S.lastT, S.lastS)
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
    pcall(function()
        local pf = workspace:FindFirstChild('KAStarScanPreview')
        if pf then pf:Destroy() end
    end)
    pcall(function() gui:Destroy() end)
end

if not FS.ok then
    toast('warning: executor lacks file api — saving disabled', C.YELLOW)
end
toast('konstant a* loaded — click the k icon', C.WHITE)

-- auto-load the scan on startup so rejoining never needs a rescan.
-- failures surface loudly so they can actually be fixed
task.spawn(function()
    task.wait(1.5)
    if not FS.ok then return end
    if Scan.count > 0 then return end
    local ok, why = Scan.loadFile()
    if ok then
        pcall(Scan.fillHoles)
        toast(('scan loaded from disk — %d cells (%d road)'):format(Scan.count, Scan.roadCount), C.GREEN)
    elseif why ~= 'no scan file' then
        toast('scan auto-load failed: ' .. tostring(why), C.RED)
    end
end)
