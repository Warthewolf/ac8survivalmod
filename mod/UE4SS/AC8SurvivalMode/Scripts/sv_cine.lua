-- sv_cine.lua: THE TANACORN's rise cinematic, its camera keys and a director to place them (the user, 2026-11-11: "if
-- there's a way for you to make a directors thing, maybe so i can visualise where I want to put the cinematic camera,
-- also look into turning the HUD off during the cinematic too"; docs/re/CINEMATIC.md). Part of AC8 Survival Mode's
-- runtime, run by main.lua in MODULES' order after sv_fleet: a name another part uses is a global of this mod's Lua
-- state, its own helpers stay local. The whole part is one test-only block, which tools/strip_test_only.py takes out of
-- every release and tester zip (only this header is left there). sv_tanicorn.lua's TANI (the hull's class, the rise's
-- rate) is read at run time only, never at load.
--
-- The camera keys: config\rise_camera.txt next to survival.ini (made with today's camera when it's missing; each save
-- keeps the one before as rise_camera.prev.txt), CINE.keys, sorted by time, each { t = seconds into the rise, at =
-- { f, s, u } where the camera stands and look = { f, s, u } the point it looks at, in metres in her rest frame
-- (forward, starboard, up from her rest midships at the waterline: the hull actor's place and forward), fov = degrees }.
-- The rise moves her about that place, so a key's spot is fixed in the world for the whole rise.
--   CINE.play(R[, hooks])  the cinematic of the rise R (sv_tanicorn.lua's: its hull R.o, rest place R.x / R.y / R.z cm),
--                          started as she rises: a CameraActor at every key's spot turned onto its look point (its FOV
--                          on its CameraComponent), the view on the first at once, then at each key's time a blend to the
--                          next (SetViewTargetWithBlend, `blend` of the file) lasting until that key's time, on the rise's
--                          own clock (hooks.clock(): seconds into the rise, nil before she plays; without it the rig's
--                          GetPosition) at hooks.rate (her play rate); the view given back if the game takes it.
--                          Survival's HUD held (sv_hud.lua HUD.hold) and the game's hidden (the first route of the
--                          file's `hud` that takes). -> true, "keyed"; false, why (no camera made: the caller's own then).
--                          In director mode it only keeps the rise's frame and clock for Ctrl+E -> false, "director".
--   CINE.stop(why)         the view back on your plane, both HUDs back, the cameras destroyed once the view is off them.
--   CINE.director()        nil, or { speed = director_speed } while director mode is on (the rise's rate then).
--   CINE.active()          "cinematic", "preview" or nil.
-- Test keys (Ctrl+), in a Survival run and not on a co-op joiner:
--   D   director mode on / off: a flash at every camera key's spot every 2 s (AC8's Mission 23 far flash, x3) and a line a
--       key in the log; the rise plays without the cinematic, at director_speed, so you can fly round her and record
--   E   a camera key from your view (the camera manager's place, its forward, a look point 500 m along it, its FOV) at
--       the rise's time (with no rise playing: the last key recorded + 1 s), into the keys (one within 0.25 s of it
--       replaced) and saved at once: `CAMERA KEY n AT t S`
--   V   the keys previewed, a press each: the view on that key's camera (HUD off but its callout `KEY n OF m AT t S`);
--       after the last, the view back on your plane
--   W   a new take: the keys to rise_camera.prev.txt, today's camera back
-- Logged: `cine: ...`; sv_hud.lua's `hud: held (...)`, `hud: ... let go`.
-- TEST ONLY BEGIN (the rise's cinematic and its director: test builds only; docs/re/CINEMATIC.md)
CINE = {}
do
local cfg = {
    file = "rise_camera.txt", prev = "rise_camera.prev.txt",
    -- the file's settings (`name = value` lines), their defaults: the director's rise rate; the blend between keys (linear,
    -- cubic, easein, easeout, easeinout: EViewTargetBlendFunction); the routes tried in order to hide the game's HUD
    director_speed = 0.35, blend = "cubic", hud = { "widgets", "cheat", "showhud" },
    blend_exp = 2.0,                   -- (the ease blends' exponent)
    first_blend_s = 0,                 -- (your plane to the first key: at once)
    back_blend_s = 1.0,                -- (the last key back to your plane, as the rise's own camera did)
    late_blend_s = 0.25,               -- (a key whose time has passed already: reached this fast)
    replace_s = 0.25, look_m = 500, step_s = 1.0, max_keys = 32,
    max_s = 180,                       -- (a cinematic still up this long after it started: stopped)
    marker = "/Game/VFX/Mission/Mission023/NS_ms23FarFlash", marker_scale = 3, marker_every_s = 2,
    -- the game's HUD widgets (route `widgets`): the HUD actor's own (ALiveHUDBase / ALiveHUD) and the live roots by class
    -- (the flight HUD, drawn into a render texture, and its message layer: docs/re/HUD_LAYOUT.md)
    hud_fields = { "GlowWidgetPtr", "NonGlowFrontWidgetPtr", "NonGlowBackWidgetPtr", "NonGlowWidget", "HUDMessageWidget" },
    hud_classes = { "WBP_HUD_Chronicle_MainFlight_000_C", "WBP_HUD_SubWidgets_Message_000_C" },
}
CINE.cfg = cfg
-- today's camera (tools/tanicorn/export_tanacorn.py RISE_CAM, baked into the rig's SOC_Cam): t, the place and the point
-- looked at in UE's axes from her rest (x forward, y starboard: as f, s, u here), FOV 55 (TANI.rise.cam_fov)
CINE.DEFAULTS = {
    { t = 0, at = { 700, -650, 12 }, look = { 300, 0, 40 }, fov = 55 },
    { t = 5, at = { 680, -660, 14 }, look = { 200, 0, 70 }, fov = 55 },
    { t = 9, at = { 640, -700, 16 }, look = { 80, 0, 15 }, fov = 55 },
    { t = 15, at = { 600, -720, 18 }, look = { 40, 0, 10 }, fov = 55 },
}
local BLEND = { linear = 0, cubic = 1, easein = 2, easeout = 3, easeinout = 4 }
local ROUTES = { widgets = true, cheat = true, showhud = true }
local HOLD_CINE, HOLD_PV = "the rise's cinematic", "the camera preview"
-- play: the cinematic; R: the rise kept for Ctrl+E (play's, or a director rise's); pv: the preview; trash: cameras to go
local S = { keys = nil, set = nil, dirty = false, dir = false, play = nil, R = nil, pv = nil, trash = {}, lastRec = nil,
            run = nil, hull = nil, markAt = 0, markSaid = nil }
CINE.S = S

local function copyKey(k) return { t = k.t, at = { k.at[1], k.at[2], k.at[3] }, look = { k.look[1], k.look[2], k.look[3] }, fov = k.fov } end
local function copyKeys(l) local o = {}; for i, k in ipairs(l) do o[i] = copyKey(k) end; return o end
local function defaultSet() return { director_speed = cfg.director_speed, blend = cfg.blend, hud = { table.unpack(cfg.hud) } } end
local function num(v)                                    -- a number as the file writes it: at most 2 decimals
    local s = string.format("%.2f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end
local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end

---------------------------------------------------------------------------------------------------- the file
local function dirOf() return type(SCRIPT_DIR) == "string" and (SCRIPT_DIR .. "..\\config\\") or nil end
local function readFile(name)
    local d = dirOf()
    if not d then return nil, "no mod folder" end
    local f = io.open(d .. name, "rb")
    if not f then return nil, "missing" end
    local ok, s = pcall(function() return f:read("a") end)
    f:close()
    if not ok then return nil, tostring(s) end
    return s
end
local function writeFile(name, text)
    local d = dirOf()
    if not d then return false, "no mod folder" end
    local f, err = io.open(d .. name, "wb")
    if not f then return false, tostring(err) end
    local ok, r, e2 = pcall(f.write, f, text)
    f:close()
    if ok and r ~= nil then return true, "" end
    return false, tostring(ok and e2 or r)
end

-- (quoted lines, as sv_config_subs.lua's header)
local HEADER = table.concat({
    "; AC8 Survival Mode: THE TANACORN's rise camera (test builds; docs/re/CINEMATIC.md)",
    "; =====================================================================================================================",
    "; The cinematic cuts to the first key's camera as she starts to rise, then blends to each next key, getting there at",
    "; its time. One key a line, 8 numbers (spaces or commas between them):",
    ";   t                      seconds into the rise: 0 her bow still under, out at 0.8, standing 120 m up at 5, the slam",
    ";                          at 9, at rest at 15",
    ";   at_f  at_s  at_u       where the camera stands, metres from her middle at the waterline (where she rests):",
    ";                          f forward (+ towards her bow, - her stern), s starboard (+ her right side, - her left side),",
    ";                          u up (+ above the sea)",
    ";   look_f look_s look_u   the point it looks at, the same way",
    ";   fov                    its field of view, degrees (55: wide as today's; smaller zooms in)",
    "; Lines starting with ; are notes. A line that isn't 8 numbers is skipped (the game's log says which).",
    "; In game (test keys): Ctrl+D director mode, Ctrl+R the rise, Ctrl+E records a key from your view, Ctrl+V shows",
    "; the keys one by one, Ctrl+W starts again from today's camera (this file kept as rise_camera.prev.txt).",
    "; Settings: director_speed (the rise's speed in director mode), blend (linear, cubic, easein, easeout, easeinout),",
    "; hud (how the game's HUD is hidden, tried in order until one works: widgets, cheat, showhud; or none).",
}, "\n")

local function setting(set, k, v)
    if k == "director_speed" then
        local x = tonumber(v)
        if not x or x < 0.05 or x > 4 then return false, "director_speed must be a number from 0.05 to 4" end
        set.director_speed = x
    elseif k == "blend" then
        v = v:lower():gsub("[%s_%-]", "")
        if BLEND[v] == nil then return false, "blend must be linear, cubic, easein, easeout or easeinout" end
        set.blend = v
    elseif k == "hud" then
        local l = {}
        for w in v:lower():gmatch("[%a]+") do
            if w ~= "none" then
                if not ROUTES[w] then return false, "hud routes are widgets, cheat, showhud (or none): not " .. w end
                l[#l + 1] = w
            end
        end
        set.hud = l
    else
        return false, "no setting " .. k
    end
    return true
end

-- k into keys, sorted by t; a key within replace_s of it replaced. -> its index (nil: full), whether it replaced one
function CINE.add(keys, k)
    local replaced = false
    for i = #keys, 1, -1 do
        if math.abs(keys[i].t - k.t) <= cfg.replace_s then table.remove(keys, i); replaced = true end
    end
    if #keys >= cfg.max_keys then return nil, replaced end
    keys[#keys + 1] = k
    table.sort(keys, function(a, b) return a.t < b.t end)
    for i, x in ipairs(keys) do if x == k then return i, replaced end end
    return nil, replaced
end

-- a file's text -> its keys (sorted), its settings (over the defaults), its bad lines { { line = n, why = s } }
function CINE.parse(text)
    local keys, set, bad, n = {}, defaultSet(), {}, 0
    for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local l = line:gsub("\r$", ""):gsub("[;#].*$", "")
        l = l:match("^%s*(.-)%s*$")
        if l ~= "" then
            local k, v = l:match("^([%a_][%w_]*)%s*=%s*(.-)$")
            if k then
                local ok, why = setting(set, k:lower(), v)
                if not ok then bad[#bad + 1] = { line = n, why = why } end
            else
                local x = {}
                for w in l:gmatch("[^%s,]+") do x[#x + 1] = tonumber(w) or false end
                local why = nil
                if #x ~= 8 then why = string.format("%d values, not 8", #x) end
                for i = 1, #x do if x[i] == false and not why then why = "value " .. i .. " isn't a number" end end
                if not why then
                    if x[1] < 0 or x[1] > 3600 then why = "t must be 0 to 3600 s"
                    elseif x[8] < 5 or x[8] > 170 then why = "fov must be 5 to 170 degrees" end
                    for i = 2, 7 do if not why and math.abs(x[i]) > 50000 then why = "a place over 50 km from her" end end
                end
                if why then
                    bad[#bad + 1] = { line = n, why = why }
                else
                    local i = CINE.add(keys, { t = x[1], at = { x[2], x[3], x[4] }, look = { x[5], x[6], x[7] }, fov = x[8] })
                    if not i then bad[#bad + 1] = { line = n, why = cfg.max_keys .. " keys already" } end
                end
            end
        end
    end
    return keys, set, bad
end

-- the file's text for keys and settings
function CINE.text(keys, set)
    set = set or defaultSet()
    local out = { HEADER, "director_speed = " .. num(set.director_speed), "blend = " .. set.blend,
                  "hud = " .. (#set.hud > 0 and table.concat(set.hud, " ") or "none"), "",
                  ";  t      at_f     at_s     at_u     look_f   look_s   look_u   fov" }
    for _, k in ipairs(keys) do
        out[#out + 1] = string.format("%-8s %-8s %-8s %-8s %-8s %-8s %-8s %s", num(k.t), num(k.at[1]), num(k.at[2]),
            num(k.at[3]), num(k.look[1]), num(k.look[2]), num(k.look[3]), num(k.fov))
    end
    return table.concat(out, "\n") .. "\n"
end

local function keyTimes(keys)
    local t = {}
    for _, k in ipairs(keys) do t[#t + 1] = num(k.t) end
    return table.concat(t, ", ")
end

-- the keys from the file (again at each rise, Ctrl+D and the preview's first press: an edit counts without a restart;
-- not while the last save failed: the keys in memory are the newer). Missing: today's camera, the file made.
function CINE.load(why)
    if S.dirty and S.keys then return false, "kept (the last save failed)" end
    local text, err = readFile(cfg.file)
    local keys, set, bad = {}, defaultSet(), {}
    if text then keys, set, bad = CINE.parse(text) end
    for _, b in ipairs(bad) do log(string.format("cine: config\\%s line %d skipped: %s", cfg.file, b.line, b.why)) end
    local from
    if #keys == 0 then
        keys = copyKeys(CINE.DEFAULTS)
        from = text and "no key in it: today's camera" or ("today's camera (the file " .. tostring(err) .. ")")
        if not text and err == "missing" then
            local okW, whyW = writeFile(cfg.file, CINE.text(keys, set))
            from = from .. (okW and ", the file made" or (", the file NOT made: " .. tostring(whyW)))
        end
    else
        from = string.format("%d keys", #keys)
    end
    S.keys, S.set = keys, set
    CINE.keys = keys
    log(string.format("cine: keys (%s) from config\\%s: %s at %s s; director speed %s, blend %s, the game's HUD by %s",
        tostring(why), cfg.file, from, keyTimes(keys), num(set.director_speed), set.blend,
        #set.hud > 0 and table.concat(set.hud, ", ") or "none"))
    return true, from
end

-- keys saved, the file before kept as the .prev
function CINE.save(keys, why)
    local old = readFile(cfg.file)
    if old then writeFile(cfg.prev, old) end
    local ok, err = writeFile(cfg.file, CINE.text(keys, S.set))
    S.dirty = not ok
    log(string.format("cine: %d keys saved to config\\%s (%s)%s", #keys, cfg.file, tostring(why),
        ok and (old and (", the one before kept as " .. cfg.prev) or "") or (": NOT saved (" .. tostring(err) .. ")")))
    return ok, err
end

---------------------------------------------------------------------------------------------------- her frame
-- her rest frame: { x, y, z (cm), fx, fy (her forward, level, unit) } from an actor (and its rest place, when given)
local function frameOf(o, x, y, z, fwd)
    local f = fwd
    if not f then pcall(function() local v = o:GetActorForwardVector(); f = { X = v.X, Y = v.Y } end) end
    if not (x and y and z) then pcall(function() local l = o:K2_GetActorLocation(); x, y, z = l.X, l.Y, l.Z end) end
    if not (x and y and z) then return nil, "her place not read" end
    local h = f and math.sqrt(f.X * f.X + f.Y * f.Y) or 0
    if h < 1e-6 then return nil, "her forward not read" end
    return { x = x, y = y, z = z, fx = f.X / h, fy = f.Y / h }
end
-- { f, s, u } m in a frame -> the world (cm), and back
function CINE.world(F, p)
    return { X = F.x + (F.fx * p[1] - F.fy * p[2]) * 100, Y = F.y + (F.fy * p[1] + F.fx * p[2]) * 100, Z = F.z + p[3] * 100 }
end
function CINE.toFrame(F, w)
    local dx, dy, dz = (w.X - F.x) / 100, (w.Y - F.y) / 100, (w.Z - F.z) / 100
    return { dx * F.fx + dy * F.fy, dy * F.fx - dx * F.fy, dz }
end
-- the rotator looking along (dx, dy, dz), and its quaternion (FRotator::Quaternion, roll 0)
function CINE.aim(dx, dy, dz)
    return { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
end
local function quat(r)
    local p, y = math.rad(r.Pitch) / 2, math.rad(r.Yaw) / 2
    return { X = math.sin(p) * math.sin(y), Y = -math.sin(p) * math.cos(y), Z = math.cos(p) * math.sin(y), W = math.cos(p) * math.cos(y) }
end

local function sameObj(o, name) return o ~= nil and liveAddr(o) ~= nil and (name == nil or nameOf(o) == name) end
-- the frame of the rise kept (R: its own rest place) or, without one, of a hull of ours in the level (TANI.hull.class)
local function frameNow()
    local T = S.play or S.R
    if T then
        if T.F then return T.F, "the rise's" end
        local R = T.R
        if R and sameObj(R.o, R.name) then
            local F = frameOf(R.o, R.x, R.y, R.z, R.fwd)
            if F then T.F = F; return F, "the rise's" end
        end
    end
    if not (S.hull and sameObj(S.hull.o, S.hull.name)) then
        S.hull = nil
        local cls = type(TANI) == "table" and TANI.hull and TANI.hull.class
        if cls then
            for _, o in ipairs(FindAllOf(cls) or {}) do
                if valid(o) and not nameOf(o):find("Default__", 1, true) then S.hull = { o = o, name = nameOf(o) } end
            end
        end
    end
    if not S.hull then return nil, "no TANACORN up (Ctrl+Y or Ctrl+R first)" end
    local F, why = frameOf(S.hull.o)
    return F, F and "the hull's in the level" or why
end

---------------------------------------------------------------------------------------------------- cameras
local function spawnCam(F, k)
    local gs, ccls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.CameraActor")
    if not (valid(gs) and valid(ccls) and liveObj(survivalPC)) then return nil, "no GameplayStatics / CameraActor class / player controller" end
    local at, to = CINE.world(F, k.at), CINE.world(F, k.look)
    local dx, dy, dz = to.X - at.X, to.Y - at.Y, to.Z - at.Z
    if dx * dx + dy * dy + dz * dz < 1 then dx, dy, dz = F.fx * 100, F.fy * 100, 0 end   -- (its look point on it: her forward)
    local rot = CINE.aim(dx, dy, dz)
    local t = { Rotation = quat(rot), Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, ccls, t, 1, nil, 1) end)
    if not (okB and a and valid(a)) then return nil, "the spawn gave nothing (" .. tostring(okB and a or "error") .. ")" end
    pcall(function() gs:FinishSpawningActor(a, t, 1) end)
    if not valid(a) then return nil, "not finished" end
    local okR = pcall(function() a:K2_SetActorRotation(rot, true) end)
    pcall(function() a.CameraComponent.bConstrainAspectRatio = false end)
    local okF = pcall(function() a.CameraComponent:SetFieldOfView(k.fov) end)
    local off = "?"                                       -- (its forward read back against where it should look)
    pcall(function()
        local v, n = a:GetActorForwardVector(), math.sqrt(dx * dx + dy * dy + dz * dz)
        local c = (v.X * dx + v.Y * dy + v.Z * dz) / n
        off = string.format("%.1f", math.deg(math.acos(math.max(-1, math.min(1, c)))))
    end)
    return { o = a, name = nameOf(a), at = at, rot = rot, off = off, rotOk = okR, fovOk = okF }
end
local function trash(c, after)
    if c then S.trash[#S.trash + 1] = { o = c.o, name = c.name, at = os.clock() + (after or 0) } end
end
local function binTick(now, all)
    for i = #S.trash, 1, -1 do
        local e = S.trash[i]
        if all or now >= e.at then
            table.remove(S.trash, i)
            if sameObj(e.o, e.name) then pcall(function() e.o:K2_DestroyActor() end) end
        end
    end
end
local function blendFn() return BLEND[S.set and S.set.blend or cfg.blend] or 1 end
local function viewOn(o, blend, lock)
    if not liveObj(survivalPC) then return false end
    return pcall(function() survivalPC:SetViewTargetWithBlend(o, blend, blendFn(), cfg.blend_exp, lock == true) end)
end
local function viewBack(blend)
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    if not valid(pawn) then return false end
    return viewOn(pawn, blend, true)                      -- (the outgoing camera locked: it can go while the view leaves it)
end
-- the view back on o if the game took it (GetViewTarget names the target a blend is going to): -> whether it was
local function viewKeep(o)
    local okT, vt = pcall(function() return survivalPC:GetViewTarget() end)
    if okT and vt ~= nil and addrOf(vt) ~= addrOf(o) then viewOn(o, 0, false); return true end
    return false
end

---------------------------------------------------------------------------------------------------- the game's HUD
-- Routes, each put back exactly as it was (only what is still as this left it):
--   widgets  the HUD actor's root widgets and the flight HUD's live roots (docs/re/HUD_LAYOUT.md: drawn into a render
--            texture, never in the viewport) SetVisibility Hidden, each one's own visibility back after
--   cheat    the game's HUD modes (ELiveHUDMode: EverythingDisabled, then RestoreToDefault) through the player
--            controller's LiveCheatManager, only when the game made one (a shipping game has none: never made here)
--   showhud  the HUD actor's bShowHUD off (AHUD: its canvas drawing; it may only freeze the texture), its value back
-- Held while the cinematic or the preview holds it; seen again each tick, and hidden again if the game showed it.
local GH = { holders = {}, route = nil, items = nil, cheat = nil, show = nil, reverts = 0, dropped = false }
CINE.GH = GH
local function hudActor()
    local hud
    pcall(function() hud = survivalPC:GetHUD() end)
    if not valid(hud) then pcall(function() hud = survivalPC.MyHUD end) end
    return valid(hud) and hud or nil
end
local function hudWidgets()
    local out, seen = {}, {}
    local mine = H and H.widget and addrOf(H.widget)
    local function add(w, what)
        if w == nil or not liveObj(w) then return end
        local a = addrOf(w)
        if not a or seen[a] or a == mine then return end
        seen[a] = true
        local okV, v = pcall(function() return w:GetVisibility() end)
        if okV and type(v) == "number" and v ~= VIS.Collapsed and v ~= VIS.Hidden then
            out[#out + 1] = { o = w, name = nameOf(w), old = v, what = what }
        end
    end
    local hud = hudActor()
    if hud then
        for _, f in ipairs(cfg.hud_fields) do pcall(function() local w = hud[f]; add(w, f .. " " .. short(w)) end) end
    end
    for _, c in ipairs(cfg.hud_classes) do
        for _, w in ipairs(FindAllOf(c) or {}) do if liveWidget(w) then add(w, c:gsub("_C$", "")) end end
    end
    return out
end
local TRY = {}
function TRY.widgets()
    local list, took, names = hudWidgets(), {}, {}
    for _, e in ipairs(list) do
        pcall(function() e.o:SetVisibility(VIS.Hidden) end)
        local okR, v = pcall(function() return e.o:GetVisibility() end)
        if okR and v == VIS.Hidden then took[#took + 1] = e; names[#names + 1] = e.what end
    end
    if #took == 0 then return false, #list == 0 and "no HUD widget found" or (#list .. " found, none took") end
    GH.items = took
    return true, string.format("%d of %d widgets hidden: %s", #took, #list, table.concat(names, ", "))
end
function TRY.cheat()
    local cm
    pcall(function() cm = survivalPC.CheatManager end)
    if not valid(cm) then return false, "no cheat manager" end
    if not pcall(function() cm:ChangeHUDType(2) end) then return false, "ChangeHUDType failed" end   -- (EverythingDisabled)
    GH.cheat = { o = cm, name = nameOf(cm) }
    return true, "LiveCheatManager ChangeHUDType EverythingDisabled"
end
function TRY.showhud()
    local hud = hudActor()
    if not hud then return false, "no HUD actor" end
    local okR, old = pcall(function() return hud.bShowHUD end)
    if not okR or type(old) ~= "boolean" then return false, "bShowHUD not read" end
    if old == false then return false, "bShowHUD off already" end
    pcall(function() hud.bShowHUD = false end)
    local okB, v = pcall(function() return hud.bShowHUD end)
    if not (okB and v == false) then return false, "bShowHUD didn't take" end
    GH.show = { o = hud, name = nameOf(hud), old = old }
    return true, short(hud) .. " bShowHUD off"
end
local function ghudHide(holder)
    GH.holders[holder] = true
    if GH.route then return true end
    local tried = {}
    for _, r in ipairs((S.set and S.set.hud) or cfg.hud) do
        local ok, why = false, "no route " .. tostring(r)
        if TRY[r] then
            local okC, a, b = pcall(TRY[r])
            if okC then ok, why = a, b else why = "error " .. tostring(a) end
        end
        if ok then
            GH.route, GH.reverts = r, 0
            log(string.format("cine: the game's HUD hidden by %s (%s)%s", r, tostring(why),
                #tried > 0 and ("; before it " .. table.concat(tried, "; ")) or ""))
            return true
        end
        tried[#tried + 1] = r .. ": " .. tostring(why)
    end
    GH.route = "none"
    log("cine: the game's HUD NOT hidden (" .. (#tried > 0 and table.concat(tried, "; ") or "no route in the file's hud") .. ")")
    return false
end
local function ghudPut(why)                               -- every route's change put back (what is still as it was left)
    local back, of = 0, 0
    for _, e in ipairs(GH.items or {}) do
        of = of + 1
        if sameObj(e.o, e.name) then
            local okV, v = pcall(function() return e.o:GetVisibility() end)
            if okV and v == VIS.Hidden and pcall(function() e.o:SetVisibility(e.old) end) then back = back + 1 end
        end
    end
    local parts = {}
    if GH.items then parts[#parts + 1] = string.format("%d of %d widgets back", back, of) end
    if GH.cheat then
        local okC = sameObj(GH.cheat.o, GH.cheat.name) and pcall(function() GH.cheat.o:ChangeHUDType(3) end)   -- (RestoreToDefault)
        parts[#parts + 1] = okC and "ChangeHUDType RestoreToDefault" or "the cheat manager gone"
    end
    if GH.show then
        local s, okS = GH.show, false
        if sameObj(s.o, s.name) then
            local okR, v = pcall(function() return s.o.bShowHUD end)
            if okR and v == false then okS = pcall(function() s.o.bShowHUD = s.old end) end
        end
        parts[#parts + 1] = okS and "bShowHUD back on" or "bShowHUD left (its HUD gone or changed)"
    end
    if GH.route and GH.route ~= "none" then
        log(string.format("cine: the game's HUD back (%s; %s; hidden again %d times while held)", why,
            #parts > 0 and table.concat(parts, ", ") or "nothing to put back", GH.reverts))
    end
    GH.route, GH.items, GH.cheat, GH.show, GH.dropped = nil, nil, nil, nil, false
end
local function ghudShow(holder, why)
    GH.holders[holder] = nil
    if next(GH.holders) == nil and GH.route then ghudPut(why or holder) end
end
local function ghudKeep()                                 -- hidden again if the game showed it
    for _, e in ipairs(GH.items or {}) do
        if sameObj(e.o, e.name) then
            local okV, v = pcall(function() return e.o:GetVisibility() end)
            if okV and v ~= VIS.Hidden then
                GH.reverts = GH.reverts + 1
                if GH.reverts == 1 then log(string.format("cine: the game showed its %s again (visibility %s): hidden again", e.what, tostring(v))) end
                pcall(function() e.o:SetVisibility(VIS.Hidden) end)
            end
        end
    end
    local s = GH.show
    if s and sameObj(s.o, s.name) then
        local okR, v = pcall(function() return s.o.bShowHUD end)
        if okR and v == true then GH.reverts = GH.reverts + 1; pcall(function() s.o.bShowHUD = false end) end
    end
end

---------------------------------------------------------------------------------------------------- the cinematic
local function rateOf(T)
    local h, R = T.hooks or {}, T.R or {}
    local r = h.rate
    if type(r) == "function" then local ok, v = pcall(r); r = ok and v or nil end
    r = tonumber(r) or tonumber(R.rate) or (S.dir and S.set and S.set.director_speed)
        or (type(TANI) == "table" and TANI.rise and tonumber(TANI.rise.rate)) or 1
    return math.max(0.05, r)
end
-- seconds into the rise, or nil before she plays (hooks.clock, else her rig's own position, else the clock since R.t1)
local function clockOf(T)
    local h, R = T.hooks or {}, T.R or {}
    if h.clock then
        local ok, t = pcall(h.clock)
        if ok then return type(t) == "number" and t or nil end
        logOnce("cine clock", "cine: the rise's clock hook failed: " .. tostring(t) .. " (its first: not logged again)")
        return nil
    end
    if not R.playing then return nil end
    local ok, p = pcall(function() return R.rig:GetPosition() end)
    if ok and type(p) == "number" then return p end
    return R.t1 and (os.clock() - R.t1) * rateOf(T) or nil
end

function CINE.director() return S.dir and { speed = (S.set and S.set.director_speed) or cfg.director_speed } or nil end
function CINE.active() return S.play and "cinematic" or (S.pv and "preview") or nil end

local function pvEnd(why)
    local P = S.pv
    if not P then return end
    S.pv = nil
    local back = viewBack(0)
    trash(P.cam, 0.5)
    HUD.hold(false, HOLD_PV)
    ghudShow(HOLD_PV, why)
    log(string.format("cine: preview over (%s): %s", tostring(why), back and "the view back on your plane" or "the view NOT given back (no plane)"))
end

function CINE.stop(why)
    local P = S.play
    if not P then
        if S.R then S.R = nil; log("cine: the rise's frame let go (" .. tostring(why) .. ")") end
        return false
    end
    S.play, S.R = nil, nil
    local back = viewBack(cfg.back_blend_s)
    for _, c in ipairs(P.cams) do trash(c, cfg.back_blend_s + 0.5) end
    HUD.hold(false, HOLD_CINE)
    ghudShow(HOLD_CINE, why)
    log(string.format("cine: cinematic over (%s): %s; keys reached %d of %d; the view taken back by the game %d times",
        tostring(why), back and string.format("the view back on your plane (%.1f s)", cfg.back_blend_s) or "the view NOT given back (no plane)",
        P.cur, #P.keys, P.reverts))
    return true
end

-- everything of a run gone or ending: put back what is still there
local function stopAll(why)
    CINE.stop(why)
    pvEnd(why)
    HUD.hold(false, HOLD_CINE); HUD.hold(false, HOLD_PV)
    GH.holders = {}
    if GH.route then ghudPut(why) end
    binTick(os.clock(), true)
    S.R, S.run = nil, nil
end

function CINE.play(R, hooks)
    hooks = hooks or {}
    if S.play then CINE.stop("a new rise") end
    if S.pv then pvEnd("a rise") end
    if S.run ~= D then stopAll("a new run") end
    S.run = D
    CINE.load("the rise")
    local T = { R = R, hooks = hooks, run = D }
    local F, whyF = nil, "no rise"
    if type(R) == "table" and R.o and sameObj(R.o, R.name) then F, whyF = frameOf(R.o, R.x, R.y, R.z, R.fwd) end
    T.F = F
    if S.dir then
        S.R = T
        log(string.format("cine: director mode: the rise plays without the cinematic%s; Ctrl+E records a key at her time",
            F and string.format(", her frame at (%.0f, %.0f, %.0f) facing (%.2f, %.2f)", F.x, F.y, F.z, F.fx, F.fy) or (" (her frame: " .. tostring(whyF) .. ")")))
        return false, "director"
    end
    if not F then log("cine: no cinematic: " .. tostring(whyF)); return false, whyF end
    T.keys, T.cams, T.cur, T.reverts, T.at, T.blends = copyKeys(S.keys), {}, 1, 0, os.clock(), {}
    local lines = {}
    for i, k in ipairs(T.keys) do
        local c, why = spawnCam(F, k)
        if not c then
            for _, m in ipairs(T.cams) do trash(m, 0) end
            binTick(os.clock(), true)
            log(string.format("cine: no cinematic: key %d's camera %s", i, tostring(why)))
            return false, "camera " .. i .. ": " .. tostring(why)
        end
        T.cams[i] = c
        lines[#lines + 1] = string.format("%d at %s s (%.0f, %.0f, %.0f) yaw %.0f pitch %.1f, read back %s deg off%s",
            i, num(k.t), c.at.X, c.at.Y, c.at.Z, c.rot.Yaw, c.rot.Pitch, c.off, c.fovOk and "" or ", FOV NOT set")
    end
    local okV = viewOn(T.cams[1].o, cfg.first_blend_s, false)
    S.play, S.R = T, T
    HUD.hold(true, HOLD_CINE)
    ghudHide(HOLD_CINE)
    log(string.format("cine: cinematic of %d keys (%s blends, rate %.2f): the view on key 1%s; cameras %s", #T.keys,
        S.set.blend, rateOf(T), okV and "" or " (SetViewTargetWithBlend FAILED)", table.concat(lines, "; ")))
    return true, "keyed"
end

-- the blends, on the rise's clock t: to the first key still to come, over the time left to it (at its rate)
local function drive(T, t)
    local n, j = #T.keys, #T.keys
    for i = 1, n do if T.keys[i].t > t then j = i; break end end
    if j <= T.cur then return end
    local left = T.keys[j].t - t
    local blend = left > 0 and left / rateOf(T) or cfg.late_blend_s
    T.cur = j
    local ok = viewOn(T.cams[j].o, blend, false)
    T.blends[#T.blends + 1] = { i = j, t = t, blend = blend }
    log(string.format("cine: +%.2f s: to key %d of %d (at %s s) over %.2f s%s", t, j, n, num(T.keys[j].t), blend,
        ok and "" or " (SetViewTargetWithBlend FAILED)"))
end

---------------------------------------------------------------------------------------------------- the director
local function ready(k)
    if not (D and D.now) or not nativeReady() then log("cine: Ctrl+" .. k .. " outside a Survival run"); return false end
    if COOP and COOP.client and COOP.client() then log("cine: Ctrl+" .. k .. ": the host's (you're a joiner)"); return false end
    if S.run ~= D then stopAll("a new run") end
    S.run = D
    return true
end
local FX = {}
local function fxAt(path, where, sc)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (valid(lib) and liveObj(survivalPC)) then return false end
    if FX[path] == nil or not liveObj(FX[path]) then
        local o = loadObject(path .. "." .. path:match("[^/]+$"))
        FX[path] = (o ~= nil and valid(o)) and o or nil
        if FX[path] then pin(FX[path], "the director's marker") end
    end
    if not FX[path] then return false end
    local ok, c = pcall(function()
        return lib:SpawnSystemAtLocation(survivalPC, FX[path], where, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc },
            true, true, 0, false)
    end)
    return ok and c ~= nil and valid(c)
end
local function listKeys(F, why)
    local you = playerLocation()
    for i, k in ipairs(S.keys) do
        local w = F and CINE.world(F, k.at)
        local far = (w and you) and string.format("; %.2f km from you", math.sqrt((w.X - you.X) ^ 2 + (w.Y - you.Y) ^ 2 + (w.Z - you.Z) ^ 2) / 100000) or ""
        log(string.format("cine: key %d of %d (%s) at %s s: camera (%s, %s, %s) m from her middle (%s), looking at (%s, %s, %s), fov %s%s",
            i, #S.keys, why, num(k.t), num(k.at[1]), num(k.at[2]), num(k.at[3]),
            k.at[2] < 0 and "her port side" or (k.at[2] > 0 and "her starboard side" or "on her line"),
            num(k.look[1]), num(k.look[2]), num(k.look[3]), num(k.fov), far))
    end
end
local function markers(now)
    if now < S.markAt then return end
    S.markAt = now + cfg.marker_every_s
    local F, why = frameNow()
    if not F then
        if S.markSaid ~= "wait" then S.markSaid = "wait"; log("cine: the markers wait: " .. tostring(why)) end
        return
    end
    local up = 0
    for _, k in ipairs(S.keys) do if fxAt(cfg.marker, CINE.world(F, k.at), cfg.marker_scale) then up = up + 1 end end
    if S.markSaid ~= "up" then
        S.markSaid = "up"
        log(string.format("cine: markers at the %d cameras' spots (%s x%s, every %s s; %s frame): %d up", #S.keys,
            cfg.marker:match("[^/]+$"), num(cfg.marker_scale), num(cfg.marker_every_s), why, up))
        listKeys(F, "the markers")
    end
end

testKey("D", "sv_cine.lua's director", function()
    if not ready("D") then return end
    S.dir = not S.dir
    if S.dir then
        CINE.load("Ctrl+D")
        S.markAt, S.markSaid = 0, nil
        log(string.format("cine: Ctrl+D, director mode ON: a flash at each of the %d cameras' spots every %s s; the next Ctrl+R "
            .. "rises at %sx without the cinematic: fly round her, Ctrl+E records a key from your view at her time",
            #S.keys, num(cfg.marker_every_s), num(S.set.director_speed)))
        hudCallout("DIRECTOR MODE ON", string.format("NEXT RISE %sX, NO CINEMATIC", num(S.set.director_speed)))
    else
        log(string.format("cine: Ctrl+D, director mode OFF: the next Ctrl+R plays the cinematic (%d keys)", #(S.keys or {})))
        hudCallout("DIRECTOR MODE OFF", string.format("%d CAMERA KEYS", #(S.keys or {})))
    end
end)

-- your view: its place, its direction, its FOV, and where the direction came from
local function yourView()
    local pcm
    pcall(function() pcm = survivalPC.PlayerCameraManager end)
    if not valid(pcm) then return nil, "no camera manager" end
    local okL, l = pcall(function() local v = pcm:GetCameraLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (okL and l) then return nil, "GetCameraLocation not read" end
    local fwd, how = nil, nil
    local okA, a = pcall(function() local v = pcm:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    local onIt = okA and a and math.sqrt((a.X - l.X) ^ 2 + (a.Y - l.Y) ^ 2 + (a.Z - l.Z) ^ 2) <= 100
    if onIt then
        pcall(function() local v = pcm:GetActorForwardVector(); fwd = { X = v.X, Y = v.Y, Z = v.Z } end)
        how = "the camera manager's forward"
    end
    if not fwd then                                       -- (the manager's actor not on the view: its rotation, as given)
        pcall(function()
            local m = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
            local v = m:GetForwardVector(pcm:GetCameraRotation())
            fwd = { X = v.X, Y = v.Y, Z = v.Z }
        end)
        how = "GetForwardVector(GetCameraRotation())" .. (okA and " (the manager's actor off the view)" or "")
    end
    if not fwd then
        pcall(function() local v = survivalPC.Pawn:GetActorForwardVector(); fwd = { X = v.X, Y = v.Y, Z = v.Z } end)
        how = "your plane's forward (the view's not read)"
    end
    local n = fwd and math.sqrt(fwd.X ^ 2 + fwd.Y ^ 2 + fwd.Z ^ 2) or 0
    if n < 1e-6 then return nil, "the view's direction not read" end
    local fov = 55
    pcall(function() local v = pcm:GetFOVAngle(); if type(v) == "number" and v > 1 then fov = v end end)
    return { at = l, dir = { X = fwd.X / n, Y = fwd.Y / n, Z = fwd.Z / n }, fov = fov, how = how }
end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

testKey("E", "sv_cine.lua's camera key", function()
    if not ready("E") then return end
    if S.play then log("cine: Ctrl+E: the cinematic has the view (record in director mode: Ctrl+D, then Ctrl+R)"); return end
    if S.pv then log("cine: Ctrl+E: previewing (the view is a key's camera): Ctrl+V to its end first"); return end
    if not S.keys then CINE.load("Ctrl+E") end
    local F, src = frameNow()
    if not F then log("cine: Ctrl+E: " .. tostring(src)); return end
    local t, when = nil, nil
    if S.R then t = clockOf(S.R) end
    if t then
        when = "the rise's time"
    else
        t = (S.lastRec or -cfg.step_s) + cfg.step_s
        when = S.lastRec and string.format("no rise playing: the last key recorded (%s s) + %s s", num(S.lastRec), num(cfg.step_s))
            or "no rise playing, none recorded yet: 0 s"
    end
    t = math.floor(t * 100 + 0.5) / 100
    local v, why = yourView()
    if not v then log("cine: Ctrl+E: " .. tostring(why)); return end
    local lk = { X = v.at.X + v.dir.X * cfg.look_m * 100, Y = v.at.Y + v.dir.Y * cfg.look_m * 100, Z = v.at.Z + v.dir.Z * cfg.look_m * 100 }
    local a, b = CINE.toFrame(F, v.at), CINE.toFrame(F, lk)
    local k = { t = t, at = { r1(a[1]), r1(a[2]), r1(a[3]) }, look = { r1(b[1]), r1(b[2]), r1(b[3]) }, fov = r1(v.fov) }
    local i, replaced = CINE.add(S.keys, k)
    if not i then log(string.format("cine: Ctrl+E: %d keys already: not added", cfg.max_keys)); return end
    S.lastRec = t
    CINE.save(S.keys, "Ctrl+E")
    log(string.format("cine: Ctrl+E, camera key %d of %d at %s s (%s)%s: at (%s, %s, %s) m, looking at (%s, %s, %s) m (%s m along "
        .. "%s), fov %s; %s frame", i, #S.keys, num(t), when, replaced and ", replacing the key within " .. num(cfg.replace_s) .. " s" or "",
        num(k.at[1]), num(k.at[2]), num(k.at[3]), num(k.look[1]), num(k.look[2]), num(k.look[3]), num(cfg.look_m), v.how,
        num(k.fov), src))
    hudCallout(string.format("CAMERA KEY %d AT %.1f S", i, t), replaced and "REPLACED THE ONE THERE" or nil)
end)

testKey("V", "sv_cine.lua's camera preview", function()
    if not ready("V") then return end
    if S.play then log("cine: Ctrl+V: the cinematic has the view"); return end
    if not S.pv then CINE.load("Ctrl+V") end
    local i = (S.pv and S.pv.i or 0) + 1
    if i > #S.keys then
        pvEnd("past the last key")
        hudCallout("CAMERA PREVIEW OVER", string.format("%d KEYS", #S.keys))
        return
    end
    local F, src = frameNow()
    if not F then log("cine: Ctrl+V: " .. tostring(src)); pvEnd("no frame"); return end
    local k = S.keys[i]
    local c, why = spawnCam(F, k)
    if not c then log(string.format("cine: Ctrl+V: key %d's camera %s", i, tostring(why))); pvEnd("no camera"); return end
    local old = S.pv and S.pv.cam
    local okV = viewOn(c.o, 0, false)
    trash(old, 0.5)
    S.pv = { i = i, cam = c }
    HUD.hold(true, HOLD_PV, { callouts = true })
    ghudHide(HOLD_PV)
    log(string.format("cine: Ctrl+V, key %d of %d at %s s: the view on its camera at (%.0f, %.0f, %.0f) yaw %.0f pitch %.1f "
        .. "(read back %s deg off), fov %s%s; %s frame", i, #S.keys, num(k.t), c.at.X, c.at.Y, c.at.Z, c.rot.Yaw, c.rot.Pitch,
        c.off, num(k.fov), okV and "" or " (SetViewTargetWithBlend FAILED)", src))
    hudCallout(string.format("KEY %d OF %d AT %.1f S", i, #S.keys, k.t), i == #S.keys and "CTRL+V AGAIN: BACK TO YOUR PLANE" or nil)
end)

testKey("W", "sv_cine.lua's new take", function()
    if not ready("W") then return end
    if S.play then log("cine: Ctrl+W: not while the cinematic plays"); return end
    if S.pv then pvEnd("Ctrl+W") end
    if not S.keys then CINE.load("Ctrl+W") end
    local okP, whyP = writeFile(cfg.prev, CINE.text(S.keys, S.set))
    local was = #S.keys
    S.keys = copyKeys(CINE.DEFAULTS)
    CINE.keys = S.keys
    local okS = CINE.save(S.keys, "Ctrl+W, a new take")
    S.lastRec = nil
    log(string.format("cine: Ctrl+W, a new take: the %d keys %s config\\%s, today's camera back (%d keys)%s", was,
        okP and "kept in" or ("NOT kept (" .. tostring(whyP) .. ") in"), cfg.prev, #S.keys, okS and "" or " (NOT saved)"))
    hudCallout("NEW TAKE", string.format("%d KEYS KEPT IN %s", was, cfg.prev:upper()))
end)

TEST_TICKS[#TEST_TICKS + 1] = { name = "cine", fn = function(now)
    if (S.play or S.pv or S.R or GH.route or #S.trash > 0) and S.run ~= D then stopAll("the run's over") end
    binTick(now)
    if GH.dropped and GH.route then ghudPut("the level before it was torn down") end
    local paused = type(gamePaused) == "function" and gamePaused(survivalPC) == true
    local T = S.play
    if T then
        local R = T.R
        if type(R) == "table" and R.back then CINE.stop("the rise is over"); T = nil
        elseif now - T.at > cfg.max_s then CINE.stop(string.format("still up after %d s", cfg.max_s)); T = nil end
    end
    if T then
        local t = clockOf(T)
        if t then drive(T, t) end
        local cam = T.cams[T.cur]
        if not sameObj(cam.o, cam.name) then
            CINE.stop("key " .. T.cur .. "'s camera is gone")
        elseif not paused then
            if viewKeep(cam.o) then
                T.reverts = T.reverts + 1
                if T.reverts == 1 then log("cine: the game took the view: given back to key " .. T.cur .. "'s camera") end
            end
        end
    end
    if S.pv and not paused then
        if sameObj(S.pv.cam.o, S.pv.cam.name) then viewKeep(S.pv.cam.o) else pvEnd("its camera is gone") end
    end
    if GH.route and not paused then ghudKeep() end
    if S.dir and S.keys then markers(now) end
end }
if type(LEVEL_DROPS) == "table" then                       -- (the level's objects forgotten, none of them touched; the
    LEVEL_DROPS["cine"] = function()                       -- game's HUD widgets kept to be put back next run if alive)
        S.play, S.pv, S.R, S.hull, S.trash = nil, nil, nil, nil, {}
        HUD.hold(false, HOLD_CINE); HUD.hold(false, HOLD_PV)
        GH.holders, GH.cheat, GH.show = {}, nil, nil
        if GH.route then GH.dropped = true end
        FX = {}
    end
end
CINE.load("loaded")
end
-- TEST ONLY END
