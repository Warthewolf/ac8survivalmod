-- sv_cine.lua: THE TANACORN's rise cinematic, its camera keys and a director to place them (the user, 2026-11-11: "if
-- there's a way for you to make a directors thing, maybe so i can visualise where I want to put the cinematic camera,
-- also look into turning the HUD off during the cinematic too"; docs/re/CINEMATIC.md). Part of AC8 Survival Mode's
-- runtime, run by main.lua in MODULES' order after sv_fleet: a name another part uses is a global of this mod's Lua
-- state, its own helpers stay local. The whole part is one test-only block: tools/strip_test_only.py takes it out of
-- every zip but a TESTER=1 one (only this header is left there). A TESTER=1 zip keeps the whole director: its keys work
-- there, and the camera file is made at their first use or a rise, never at start. sv_tanicorn.lua's TANI (the hulls' classes,
-- the rise's rate and hold) is read at run time only, never at load.
--
-- The camera keys: config\rise_camera.txt next to survival.ini (today's camera while it's missing; the file made at the
-- first Ctrl+D / E / V / W or rise). Each save keeps the file before as rise_camera.prev.txt (one save's undo), a hand
-- edit a save would write over as rise_camera.edited.txt, and Ctrl+W the whole take as rise_camera.take_<date>_<time>.txt
-- (never written again). CINE.keys, sorted by time, each { t = seconds into the rise, at = { f, s, u } where the camera
-- stands and look = { f, s, u } the point it looks at, in metres in her rest frame (forward, starboard, up from her rest
-- midships at the waterline: the hull actor's place and forward), fov = degrees, roll = degrees (nil: level), cut = true
-- (the view cuts to it at its time) }. The rise moves her about that place, so a key's spot is fixed in the world.
--   CINE.play(R[, hooks])  the cinematic of the rise R (sv_tanicorn.lua's: its hull R.o, rest place R.x / R.y / R.z cm, its
--                          rig R.rig), started as she rises: the keys' path (blend smooth: one curve through them, each
--                          column a monotone cubic as export_tanacorn.py bakes today's camera, a CameraActor about every
--                          0.5 s of it, linear blends between them, each next one started a tick before the view gets
--                          there so it never stops; another blend: a CameraActor a key, that blend between them; a cut
--                          key: the view cut to it at its time), the view on the first over enter_blend s, on the rise's
--                          own clock (hooks.clock(): seconds into the rise, nil before she plays; without it the rig's
--                          GetPosition) at hooks.rate (her play rate); the view given back if the game takes it.
--                          Survival's HUD held (sv_hud.lua HUD.hold; its callouts still shown with callouts = on), the
--                          game's hidden (the first route of the file's `hud` that takes) and the target boxes (boxes).
--                          -> true, "keyed"; false, why (no camera made: the caller's own then). In director mode it only
--                          keeps the rise's frame and clock for Ctrl+E -> false, "director".
--   CINE.stop(why)         the view back on your plane, both HUDs and the boxes back, the cameras destroyed once the view
--                          is off them (the level torn down: CINE.leave's, nothing touched).
--   CINE.leave(why)        the level left (sv_main.lua runLeft): what can outlive it put back at once (the game's HUD
--                          widgets), the view and the cameras left to the level; nothing touched once it's torn down.
--   CINE.director()        nil, or { speed = director_speed } while director mode is on (the rise's rate then).
--   CINE.active()          "cinematic", "preview" or nil.
-- Test keys (Ctrl+), in a Survival run and not on a co-op joiner:
--   D   director mode on / off: a flash at every camera key's spot every 2 s (AC8's Mission 23 far flash, x3) and a line a
--       key in the log; the rise plays without the cinematic, at director_speed, so you can fly round her and record.
--       In a preview: the preview over, your plane back.
--   E   a camera key from your view (the camera manager's place, its forward and roll, a look point 500 m along it, its
--       FOV) at the rise's time (in her hold: 0 s; with no rise: the last key recorded + 1 s), into the keys (one within
--       0.25 s of it replaced) and saved at once: `CAMERA KEY n AT t S`. In a preview: the preview over.
--   V   the keys previewed, a press each: the view on that key's camera (HUD off but its callout `KEY n OF m AT t S`);
--       after the last your plane back, and so after 20 s with no press, your plane gone or changed, or you down
--   W   a new take: the keys kept in rise_camera.take_<date>_<time>.txt, today's camera back
-- Logged: `cine: ...`; sv_hud.lua's `hud: held (...)`, `hud: ... let go`.
-- TEST ONLY BEGIN (the rise's cinematic and its director: test builds only; docs/re/CINEMATIC.md)
CINE = {}
do
local cfg = {
    file = "rise_camera.txt", prev = "rise_camera.prev.txt", edited = "rise_camera.edited.txt",
    take = "rise_camera.take_%s.txt",
    -- the file's settings (`name = value` lines), their defaults: the director's rise rate; the blend (smooth, or one a
    -- key: linear, cubic, easein, easeout, easeinout: EViewTargetBlendFunction); your plane to the first key (s, 0: a
    -- cut; today's riseCine blends TANI.rise.blend_s, 1 s); Survival's callouts over it; the target boxes (hide: all,
    -- hers: only hers, keep); the routes tried in order to hide the game's HUD
    director_speed = 0.35, blend = "smooth", enter_blend = 1.0, callouts = true, boxes = "hide",
    hud = { "distortion", "widgets", "cheat", "showhud" },
    blend_exp = 2.0,                   -- (the ease blends' exponent)
    back_blend_s = 1.0,                -- (the last key back to your plane, as the rise's own camera did)
    late_blend_s = 0.25,               -- (a camera whose time has passed already: reached this fast)
    sample_s = 0.5,                    -- (blend smooth: a camera about every this many seconds of the rise, each key one)
    max_cams = 64,                     -- (... at most this many in all: a longer path gets them further apart)
    lead_s = 0.35,                     -- (each next blend started this long (real time) before the view gets to the camera
                                       --  it's going to: over one 250 ms tick, so the view never stops; a cut, half that)
    replace_s = 0.25, look_m = 500, step_s = 1.0, max_keys = 32,
    max_s = 180,                       -- (a cinematic still up this long after it started: stopped)
    preview_s = 20,                    -- (a preview with no Ctrl+V this long: over)
    hull_every_s = 10,                 -- (no hull of ours: looked for again at most this often, or at a key press)
    hold_s = 1.5,                      -- (her hold before she plays, when TANI.rise.hold_s can't be read)
    dist_pad_s = 2, dist_refresh_s = 5, -- (route distortion: its blackout this much past the time it's wanted, renewed)
    marker = "/Game/VFX/Mission/Mission023/NS_ms23FarFlash", marker_scale = 3, marker_every_s = 2,
    -- the game's HUD widgets (route `widgets`): the HUD actor's own (ALiveHUDBase / ALiveHUD) and the live roots by class
    -- (the flight HUD, drawn into a render texture, and its message layer: docs/re/HUD_LAYOUT.md)
    hud_fields = { "GlowWidgetPtr", "NonGlowFrontWidgetPtr", "NonGlowBackWidgetPtr", "NonGlowWidget", "HUDMessageWidget" },
    hud_classes = { "WBP_HUD_Chronicle_MainFlight_000_C", "WBP_HUD_SubWidgets_Message_000_C" },
    -- the target boxes' actors by class (only when the HUD's TargetContainerManager can't be read: once, at the hide)
    box_classes = { "ChronicleTargetContainerActorBP_C", "LiveTargetContainerActor" },
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
local BLEND = { smooth = 0, linear = 0, cubic = 1, easein = 2, easeout = 3, easeinout = 4 }   -- (smooth: linear, sampled)
local ROUTES = { distortion = true, widgets = true, cheat = true, showhud = true }
local BOXES = { hide = true, hers = true, keep = true }
local HOLD_CINE, HOLD_PV = "the rise's cinematic", "the camera preview"
-- play: the cinematic; R: the rise kept for Ctrl+E (play's, or a director rise's); pv: the preview; trash: cameras to go;
-- text: the file's text as last read or written (a hand edit since: the file's text differs)
local S = { keys = nil, set = nil, text = nil, dirty = false, dir = false, play = nil, R = nil, pv = nil, trash = {},
            lastRec = nil, run = nil, hull = nil, hullAt = 0, markAt = 0, markSaid = nil }
CINE.S = S

local function copyKey(k)
    return { t = k.t, at = { k.at[1], k.at[2], k.at[3] }, look = { k.look[1], k.look[2], k.look[3] }, fov = k.fov,
             roll = k.roll, cut = k.cut }
end
local function copyKeys(l) local o = {}; for i, k in ipairs(l) do o[i] = copyKey(k) end; return o end
local function defaultSet()
    return { director_speed = cfg.director_speed, blend = cfg.blend, enter_blend = cfg.enter_blend, callouts = cfg.callouts,
             boxes = cfg.boxes, hud = { table.unpack(cfg.hud) } }
end
local function num(v)                                    -- a number as the file writes it: at most 2 decimals
    local s = string.format("%.2f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end
local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end
local function isDown()                                  -- (co-op's DOWN: the spectator has your view, sv_down.lua)
    local ok, v = pcall(function() return DOWN and DOWN.me and DOWN.me() end)
    return ok and v == true
end

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
    "; The cinematic blends from your plane to the first key's camera as she starts to rise, then moves on through every",
    "; key, getting to each at its time. One key a line, 8 numbers (spaces or commas between them), then two you may add:",
    ";   t                      seconds into the rise: 0 her bow still under, out at 0.8, standing 120 m up at 5, the slam",
    ";                          at 9, at rest at 15",
    ";   at_f  at_s  at_u       where the camera stands, metres from her middle at the waterline (where she rests):",
    ";                          f forward (+ towards her bow, - her stern), s starboard (+ her right side, - her left side),",
    ";                          u up (+ above the sea)",
    ";   look_f look_s look_u   the point it looks at, the same way",
    ";   fov                    its field of view, degrees (55: wide as today's; smaller zooms in)",
    ";   roll                   (may be left out: level) the camera's bank, degrees (+ its right side down)",
    ";   cut                    (may be left out) the word cut: the view cuts to this key at its time, not moving there",
    "; Lines starting with ; are notes. A line that isn't a key is skipped, and a key within 0.25 s of a line above it",
    "; replaces that line (the game's log names both).",
    "; In game (test keys): Ctrl+D director mode, Ctrl+R the rise, Ctrl+E records a key from your view, Ctrl+V shows the",
    "; keys one by one (Ctrl+D back to your plane), Ctrl+W starts again from today's camera (this take kept as",
    "; rise_camera.take_<date>_<time>.txt). Each save keeps the file before as rise_camera.prev.txt.",
    "; Settings: director_speed (the rise's speed in director mode); blend (smooth: one smooth path through every key, as",
    "; today's camera moves; or one blend a key: linear, cubic, easein, easeout, easeinout); enter_blend (seconds from your",
    "; plane to the first key, 0 a cut); callouts (on: Survival's callouts still shown over it; off); boxes (hide: no",
    "; target box; hers: only hers off; keep); hud (how the game's HUD is hidden, tried in order until one works:",
    "; distortion, widgets, cheat, showhud; or none).",
}, "\n")

local function onOff(v)
    v = v:lower()
    if v == "on" or v == "true" or v == "yes" or v == "1" then return true end
    if v == "off" or v == "false" or v == "no" or v == "0" then return false end
    return nil
end
local function setting(set, k, v)
    if k == "director_speed" then
        local x = tonumber(v)
        if not x or x < 0.05 or x > 4 then return false, "director_speed must be a number from 0.05 to 4" end
        set.director_speed = x
    elseif k == "blend" then
        v = v:lower():gsub("[%s_%-]", "")
        if BLEND[v] == nil then return false, "blend must be smooth, linear, cubic, easein, easeout or easeinout" end
        set.blend = v
    elseif k == "enter_blend" then
        local x = tonumber(v)
        if not x or x < 0 or x > 10 then return false, "enter_blend must be a number from 0 to 10 (seconds)" end
        set.enter_blend = x
    elseif k == "callouts" then
        local b = onOff(v)
        if b == nil then return false, "callouts must be on or off" end
        set.callouts = b
    elseif k == "boxes" then
        v = v:lower()
        if not BOXES[v] then return false, "boxes must be hide, hers or keep" end
        set.boxes = v
    elseif k == "hud" then
        local l = {}
        for w in v:lower():gmatch("[%a]+") do
            if w ~= "none" then
                if not ROUTES[w] then return false, "hud routes are distortion, widgets, cheat, showhud (or none): not " .. w end
                l[#l + 1] = w
            end
        end
        set.hud = l
    else
        return false, "no setting " .. k
    end
    return true
end

-- k into keys, sorted by t; every key within replace_s of it taken out. -> its index (nil: full), the keys taken out (nil:
-- none)
function CINE.add(keys, k)
    local removed = nil
    for i = #keys, 1, -1 do
        if math.abs(keys[i].t - k.t) <= cfg.replace_s then
            removed = removed or {}
            removed[#removed + 1] = table.remove(keys, i)
        end
    end
    if #keys >= cfg.max_keys then return nil, removed end
    keys[#keys + 1] = k
    table.sort(keys, function(a, b) return a.t < b.t end)
    for i, x in ipairs(keys) do if x == k then return i, removed end end
    return nil, removed
end

-- a file's text -> its keys (sorted), its settings (over the defaults), its lines not taken { { line = n, why = s,
-- replaces = the line it replaced (or nil: skipped) } }
function CINE.parse(text)
    local keys, set, bad, n, lineOf = {}, defaultSet(), {}, 0, {}
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
                local words, x, cut = {}, {}, false
                for w in l:gmatch("[^%s,]+") do words[#words + 1] = w end
                if #words > 0 and words[#words]:lower() == "cut" then cut = true; words[#words] = nil end
                for i, w in ipairs(words) do x[i] = tonumber(w) or false end
                local why = nil
                if #x ~= 8 and #x ~= 9 then why = string.format("%d values, not 8 (9 with its roll)", #x) end
                for i = 1, #x do if x[i] == false and not why then why = "value " .. i .. " isn't a number" end end
                if not why then
                    if x[1] < 0 or x[1] > 3600 then why = "t must be 0 to 3600 s"
                    elseif x[8] < 5 or x[8] > 170 then why = "fov must be 5 to 170 degrees"
                    elseif x[9] and math.abs(x[9]) > 180 then why = "roll must be -180 to 180 degrees" end
                    for i = 2, 7 do if not why and math.abs(x[i]) > 50000 then why = "a place over 50 km from her" end end
                end
                if why then
                    bad[#bad + 1] = { line = n, why = why }
                else
                    local key = { t = x[1], at = { x[2], x[3], x[4] }, look = { x[5], x[6], x[7] }, fov = x[8],
                                  roll = (x[9] and x[9] ~= 0) and x[9] or nil, cut = cut or nil }
                    local i, removed = CINE.add(keys, key)
                    for _, r in ipairs(removed or {}) do
                        bad[#bad + 1] = { line = n, replaces = lineOf[r],
                                          why = string.format("replaces line %s (within %s s of it)", tostring(lineOf[r]), num(cfg.replace_s)) }
                    end
                    if i then lineOf[key] = n else bad[#bad + 1] = { line = n, why = cfg.max_keys .. " keys already" } end
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
                  "enter_blend = " .. num(set.enter_blend), "callouts = " .. (set.callouts and "on" or "off"),
                  "boxes = " .. set.boxes, "hud = " .. (#set.hud > 0 and table.concat(set.hud, " ") or "none"), "",
                  ";  t      at_f     at_s     at_u     look_f   look_s   look_u   fov      (roll)   (cut)" }
    for _, k in ipairs(keys) do
        local roll = (k.roll and k.roll ~= 0) and num(k.roll) or nil
        local l = string.format("%-8s %-8s %-8s %-8s %-8s %-8s %-8s %s", num(k.t), num(k.at[1]), num(k.at[2]),
            num(k.at[3]), num(k.look[1]), num(k.look[2]), num(k.look[3]), (roll or k.cut) and string.format("%-8s", num(k.fov)) or num(k.fov))
        if roll then l = l .. " " .. (k.cut and string.format("%-8s", roll) or roll) end
        if k.cut then l = l .. " cut" end
        out[#out + 1] = l
    end
    return table.concat(out, "\n") .. "\n"
end

local function keyTimes(keys)
    local t = {}
    for _, k in ipairs(keys) do t[#t + 1] = num(k.t) .. (k.cut and " (cut)" or "") end
    return table.concat(t, ", ")
end

-- the keys from the file (again at each rise, Ctrl+D and the preview's first press, and at a Ctrl+E when the file was
-- changed since: an edit counts without a restart; not while the last save failed: the keys in memory are the newer).
-- Missing: today's camera, the file made when `make` (a director key or a rise: never at start).
function CINE.load(why, make)
    if S.dirty and S.keys then return false, "kept (the last save failed)" end
    local text, err = readFile(cfg.file)
    local keys, set, bad = {}, defaultSet(), {}
    if text then keys, set, bad = CINE.parse(text) end
    for _, b in ipairs(bad) do
        if b.replaces then
            log(string.format("cine: config\\%s line %d replaces line %d (within %s s of it): line %d not taken", cfg.file, b.line,
                b.replaces, num(cfg.replace_s), b.replaces))
        else
            log(string.format("cine: config\\%s line %d skipped: %s", cfg.file, b.line, b.why))
        end
    end
    S.text = text
    local from
    if #keys == 0 then
        keys = copyKeys(CINE.DEFAULTS)
        from = text and "no key in it: today's camera" or ("today's camera (the file " .. tostring(err) .. ")")
        if not text and err == "missing" then
            if make then
                local body = CINE.text(keys, set)
                local okW, whyW = writeFile(cfg.file, body)
                if okW then S.text = body end
                from = from .. (okW and ", the file made" or (", the file NOT made: " .. tostring(whyW)))
            else
                from = from .. ", made at the director's first use"
            end
        end
    else
        from = string.format("%d keys", #keys)
    end
    S.keys, S.set = keys, set
    CINE.keys = keys
    log(string.format("cine: keys (%s) from config\\%s: %s; at %s s; director speed %s, blend %s, enter %s s, callouts %s, "
        .. "boxes %s, the game's HUD by %s", tostring(why), cfg.file, from, keyTimes(keys), num(set.director_speed), set.blend,
        num(set.enter_blend), set.callouts and "on" or "off", set.boxes, #set.hud > 0 and table.concat(set.hud, ", ") or "none"))
    return true, from
end

-- keys saved; the file before kept as the .prev (and as the .edited when it was changed since it was read or written)
function CINE.save(keys, why)
    local old = readFile(cfg.file)
    local notes = {}
    if old and old ~= S.text then
        local okE = writeFile(cfg.edited, old)
        notes[#notes + 1] = okE and ("the file was changed since it was read: that one kept as " .. cfg.edited)
            or ("the file was changed since it was read and NOT kept as " .. cfg.edited)
    end
    if old then
        local okP = writeFile(cfg.prev, old)
        notes[#notes + 1] = okP and ("the one before kept as " .. cfg.prev) or ("the one before NOT kept as " .. cfg.prev)
    end
    local body = CINE.text(keys, S.set)
    local ok, err = writeFile(cfg.file, body)
    S.dirty = not ok
    if ok then S.text = body end
    log(string.format("cine: %d keys saved to config\\%s (%s)%s%s", #keys, cfg.file, tostring(why),
        ok and "" or (": NOT saved (" .. tostring(err) .. ")"), #notes > 0 and ("; " .. table.concat(notes, "; ")) or ""))
    return ok, err
end

-- a new take's file name (rise_camera.take_<date>_<time>.txt), one that isn't there yet
local function takeName()
    local stamp = "?"
    pcall(function() stamp = os.date("%Y%m%d_%H%M%S") end)
    local name = string.format(cfg.take, stamp)
    for i = 2, 99 do
        if not readFile(name) then return name end
        name = string.format(cfg.take, stamp .. "_" .. i)
    end
    return name
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
-- the rotator looking along (dx, dy, dz) with its roll (deg, + its right side down), and its quaternion
-- (FRotator::Quaternion)
function CINE.aim(dx, dy, dz, roll)
    return { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = roll or 0 }
end
function CINE.quat(r)
    local p, y, w = math.rad(r.Pitch) / 2, math.rad(r.Yaw) / 2, math.rad(r.Roll or 0) / 2
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(w), math.cos(w)
    return { X = cr * sp * sy - sr * cp * cy, Y = -cr * sp * cy - sr * cp * sy, Z = cr * cp * sy - sr * sp * cy,
             W = cr * cp * cy + sr * sp * sy }
end
-- the roll (deg) of a view looking along f whose up is u: u on a level view's up and right (FRotationMatrix's rows: up
-- = cos(roll) up0 + sin(roll) right0); nil when u can't say
function CINE.rollOf(f, u)
    local p, y = math.atan(f.Z, math.sqrt(f.X * f.X + f.Y * f.Y)), math.atan(f.Y, f.X)
    local sp, cp, sy, cy = math.sin(p), math.cos(p), math.sin(y), math.cos(y)
    local onUp = u.X * (-sp * cy) + u.Y * (-sp * sy) + u.Z * cp
    local onRight = u.X * (-sy) + u.Y * cy
    if math.abs(onUp) + math.abs(onRight) < 1e-6 then return nil end
    return math.deg(math.atan(onRight, onUp))
end

local function sameObj(o, name) return o ~= nil and liveAddr(o) ~= nil and (name == nil or nameOf(o) == name) end
local function hullClasses()                              -- (either kind of hull of ours, as sv_tanicorn.lua's ourHulls)
    local out = {}
    if type(TANI) == "table" then
        if type(TANI.hull) == "table" and TANI.hull.class then out[#out + 1] = TANI.hull.class end
        if type(TANI.live) == "table" and TANI.live.class then out[#out + 1] = TANI.live.class end
    end
    return out
end
-- the frame of the rise kept (R: its own rest place) or, without one, of a hull of ours in the level (Ctrl+Y's drawn
-- hull or Ctrl+L's live one; looked for at most every hull_every_s while there's none, at once when `force`: a key
-- press). -> the frame, where it's from (or why there's none), the hull { o, name }
local function frameNow(force)
    local T = S.play or S.R
    if T then
        local R = T.R
        local her = (type(R) == "table" and R.o ~= nil) and { o = R.o, name = R.name } or nil
        if T.F then return T.F, "the rise's", her end
        if her and sameObj(R.o, R.name) then
            local F = frameOf(R.o, R.x, R.y, R.z, R.fwd)
            if F then T.F = F; return F, "the rise's", her end
        end
    end
    if not (S.hull and sameObj(S.hull.o, S.hull.name)) then
        S.hull = nil
        local now = os.clock()
        if force or now >= S.hullAt then
            S.hullAt = now + cfg.hull_every_s
            for _, cls in ipairs(hullClasses()) do
                for _, o in ipairs(FindAllOf(cls) or {}) do
                    if valid(o) and not nameOf(o):find("Default__", 1, true) then S.hull = { o = o, name = nameOf(o) } end
                end
            end
            if S.hull then S.hullAt = 0 end
        end
    end
    if not S.hull then return nil, "no TANACORN up (Ctrl+Y, Ctrl+L or Ctrl+R first)" end
    local F, why = frameOf(S.hull.o)
    return F, F and "the hull's in the level" or why, S.hull
end

---------------------------------------------------------------------------------------------------- cameras
-- a CameraActor at k's spot (her frame F) turned onto its look point, rolled, with its FOV
local function spawnCam(F, k)
    local gs, ccls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.CameraActor")
    if not (valid(gs) and valid(ccls) and liveObj(survivalPC)) then return nil, "no GameplayStatics / CameraActor class / player controller" end
    local at, to = CINE.world(F, k.at), CINE.world(F, k.look)
    local dx, dy, dz = to.X - at.X, to.Y - at.Y, to.Z - at.Z
    if dx * dx + dy * dy + dz * dz < 1 then dx, dy, dz = F.fx * 100, F.fy * 100, 0 end   -- (its look point on it: her forward)
    local rot = CINE.aim(dx, dy, dz, k.roll)
    local t = { Rotation = CINE.quat(rot), Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
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
-- the view onto o over blend s (fn: EViewTargetBlendFunction); lock: the view it leaves held as it was (bLockOutgoing:
-- APlayerCameraManager then blends from the last frame's view, as SetViewTarget took it; unlocked, it updates the old
-- view target every frame, so a blend that cuts into another starts from that one's camera, not from the view on screen)
local function viewOn(o, blend, lock, fn)
    if not liveObj(survivalPC) then return false end
    return pcall(function() survivalPC:SetViewTargetWithBlend(o, blend, fn or 0, cfg.blend_exp, lock == true) end)
end
local function viewBack(blend)
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    if not valid(pawn) then return false end
    return viewOn(pawn, blend, true, 1)                   -- (cubic, the outgoing camera locked: it can go as the view leaves)
end
-- the view back on o if the game took it (GetViewTarget names the target a blend is going to): -> whether it was
local function viewKeep(o)
    local okT, vt = pcall(function() return survivalPC:GetViewTarget() end)
    if okT and vt ~= nil and addrOf(vt) ~= addrOf(o) then viewOn(o, 0, false); return true end
    return false
end

---------------------------------------------------------------------------------------------------- the game's HUD
-- Routes, each put back exactly as it was (only what is still as this left it):
--   distortion  the game's own HUD blackout: ALiveHUD BeginHUDDistortion (FLiveHUDDirationStartInfo, UseHideHUD, no
--               distortion; a lightning strike's way, sv_anomalies_dev.lua), HideHUDTime the time it's wanted plus
--               dist_pad_s, renewed while it's held; EndHUDDistortion after (else ResetHUDDistortion)
--   widgets     the HUD actor's root widgets and the flight HUD's live roots (docs/re/HUD_LAYOUT.md: drawn into a render
--               texture, never in the viewport) SetVisibility Hidden, each one's own visibility back after
--   cheat       the game's HUD modes (ELiveHUDMode: EverythingDisabled, then RestoreToDefault) through the player
--               controller's LiveCheatManager, only when the game made one (a shipping game has none: never made here)
--   showhud     the HUD actor's bShowHUD off (AHUD: its canvas drawing; it may only freeze the texture), its value back
-- With them the target boxes (the file's boxes): hers off (her bShowHUDBox), and with `hide` every target box (AC8's 3D
-- billboard actors, ALiveTargetContainerActor, not widgets: no route reaches them) SetActorHiddenInGame, each one's own
-- bHidden kept. Held while the cinematic or the preview holds it; seen again each tick, and hidden again if the game
-- showed it.
local GH = { holders = {}, route = nil, items = nil, cheat = nil, show = nil, dist = nil, her = nil, boxes = nil,
             reverts = 0, dropped = false }
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
local function distBegin(hud, secs)
    return pcall(function()
        hud:BeginHUDDistortion({ NeedUpdateDistortion = false, MinDistortionScale = 0, MaxDistortionScale = 0,
            HideContainerTime = 0, ShowContainerTime = 0, UseHideHUD = true, BeginHideHUDTime = 0, HideHUDTime = secs,
            DistortionMask = 0 })
    end)
end
local TRY = {}
function TRY.distortion(o)
    local hud = hudActor()
    if not hud then return false, "no HUD actor" end
    local secs = math.max(1, tonumber(o and o.need) or cfg.dist_refresh_s) + cfg.dist_pad_s
    local ok, err = distBegin(hud, secs)
    if not ok then return false, "BeginHUDDistortion failed (" .. tostring(err) .. ")" end
    GH.dist = { o = hud, name = nameOf(hud), untilAt = os.clock() + secs, renewed = 0 }
    return true, string.format("%s BeginHUDDistortion: UseHideHUD, HideHUDTime %s s, no distortion", short(hud), num(secs))
end
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
-- the blackout made to last secs more from now, when it would end before that
local function distMore(secs, why)
    local d = GH.dist
    if not (d and sameObj(d.o, d.name)) then return end
    local now = os.clock()
    if now + secs <= d.untilAt - 0.5 then return end
    local s = secs + cfg.dist_pad_s
    if distBegin(d.o, s) then
        d.untilAt, d.renewed = now + s, d.renewed + 1
        if d.renewed == 1 then log(string.format("cine: the HUD's blackout renewed for %s s (%s; its first: not logged again)", num(s), why)) end
    end
end

-- the target boxes: { o, a, active } each, from the HUD's TargetContainerManager (TargetContainers: a target -> its box;
-- ContainerPool: the spares; docs/re/MINIMAP_MARKERS.md 1d), else (scan) by class; -> the list, whether the manager read
local function hiddenOf(o)
    local ok, v = pcall(function() return o.bHidden end)
    if ok and type(v) == "boolean" then return v end
    return nil
end
local function boxList(scan)
    local out, seen, viaMgr = {}, {}, false
    local function add(c, active)
        if c == nil or not liveObj(c) then return end
        local a = addrOf(c)
        if not a then return end
        if seen[a] then if active then seen[a].active = true end return end
        seen[a] = { o = c, a = a, active = active == true }
        out[#out + 1] = seen[a]
    end
    local hud, mgr = hudActor(), nil
    if hud then pcall(function() mgr = hud.TargetContainerManager end) end
    if mgr ~= nil and valid(mgr) then
        local okM = pcall(function()
            mgr.TargetContainers:ForEach(function(_, v) local okV, c = pcall(function() return v:get() end); if okV then add(c, true) end end)
        end)
        local okP = pcall(function()
            mgr.ContainerPool:ForEach(function(_, e) local okE, c = pcall(function() return e:get() end); if okE then add(c, false) end end)
        end)
        viaMgr = okM or okP
    end
    if not viaMgr and scan then
        for _, cls in ipairs(cfg.box_classes) do
            for _, c in ipairs(FindAllOf(cls) or {}) do
                if valid(c) and not nameOf(c):find("Default__", 1, true) then add(c, true) end
            end
            if #out > 0 then break end
        end
    end
    return out, viaMgr
end
local function boxHideNew(list)                           -- each box shown now and not yet ours: hidden, kept -> how many
    local B, n = GH.boxes, 0
    for _, e in ipairs(list) do
        if not B.by[e.a] and hiddenOf(e.o) ~= true and pcall(function() e.o:SetActorHiddenInGame(true) end) then
            local rec = { o = e.o, name = nameOf(e.o), a = e.a }
            B.by[e.a], B.list[#B.list + 1], n = rec, rec, n + 1
        end
    end
    return n
end
local function boxesOff()
    local list, viaMgr = boxList(true)
    local spares, sparesHidden = 0, 0
    for _, e in ipairs(list) do
        if not e.active then spares = spares + 1; if hiddenOf(e.o) == true then sparesHidden = sparesHidden + 1 end end
    end
    -- (the pool keeps its spares hidden itself: a box that's a spare again at the put-back is left so)
    GH.boxes = { list = {}, by = {}, viaMgr = viaMgr, reverts = 0, late = 0, sparesHidden = viaMgr and spares > 0 and sparesHidden == spares }
    local n = boxHideNew(list)
    log(string.format("cine: the target boxes: %d hidden of %d (%s; %d spares, %d of them hidden already)", n, #list,
        viaMgr and "the HUD's TargetContainerManager" or "found by class: the manager not read", spares, sparesHidden))
end
local function boxesKeep()
    local B = GH.boxes
    if not B then return end
    for _, r in ipairs(B.list) do
        if sameObj(r.o, r.name) and hiddenOf(r.o) == false then
            B.reverts = B.reverts + 1
            if B.reverts == 1 then log("cine: the game showed a target box again (" .. short(r.o) .. "): hidden again") end
            pcall(function() r.o:SetActorHiddenInGame(true) end)
        end
    end
    if B.viaMgr then B.late = B.late + boxHideNew((boxList(false))) end   -- (a new target's box, or a spare taken)
end
local function boxesPut()
    local B = GH.boxes
    if not B then return nil end
    local active = {}
    if B.sparesHidden then for _, e in ipairs((boxList(false))) do if e.active then active[e.a] = true end end end
    local back, spare = 0, 0
    for _, r in ipairs(B.list) do
        if sameObj(r.o, r.name) and hiddenOf(r.o) ~= false then
            if B.sparesHidden and not active[r.a] then spare = spare + 1
            elseif pcall(function() r.o:SetActorHiddenInGame(false) end) then back = back + 1 end
        end
    end
    return string.format("%d of %d target boxes back%s (%d more hidden while held, %d shown again by the game)", back, #B.list,
        spare > 0 and string.format(", %d left hidden as spares", spare) or "", B.late, B.reverts)
end
local function herOff(her)                                -- her own box (bShowHUDBox: ALiveAIGameObject's, reflected)
    if not (her and sameObj(her.o, her.name)) then return end
    local okR, v = pcall(function() return her.o.bShowHUDBox end)
    if not (okR and v == true) then return end
    pcall(function() her.o.bShowHUDBox = false end)
    local okB, b = pcall(function() return her.o.bShowHUDBox end)
    if okB and b == false then
        GH.her = { o = her.o, name = her.name }
        log("cine: her target box off (" .. short(her.o) .. " bShowHUDBox)")
    end
end

local function ghudHide(holder, o)
    o = o or {}
    GH.holders[holder] = true
    local set = S.set or defaultSet()
    if set.boxes ~= "keep" and not GH.her then herOff(o.her) end
    if set.boxes == "hide" and not GH.boxes then boxesOff() end
    if GH.route then
        if GH.route == "distortion" and o.need then distMore(o.need, holder) end
        return GH.route ~= "none"
    end
    local tried = {}
    for _, r in ipairs(set.hud) do
        local ok, why = false, "no route " .. tostring(r)
        if TRY[r] then
            local okC, a, b = pcall(TRY[r], o)
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
    if GH.dist then
        local d, how = GH.dist, "its HUD actor gone"
        if sameObj(d.o, d.name) then
            if pcall(function() d.o:EndHUDDistortion() end) then how = "EndHUDDistortion"
            elseif pcall(function() d.o:ResetHUDDistortion() end) then how = "ResetHUDDistortion"
            else how = "EndHUDDistortion and ResetHUDDistortion FAILED" end
        end
        parts[#parts + 1] = string.format("the blackout over (%s%s)", how, d.renewed > 0 and string.format(", renewed %d times", d.renewed) or "")
    end
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
    if GH.her then
        local h, okH = GH.her, false
        if sameObj(h.o, h.name) then
            local okR, v = pcall(function() return h.o.bShowHUDBox end)
            if okR and v == false then okH = pcall(function() h.o.bShowHUDBox = true end) end
        end
        parts[#parts + 1] = okH and "her box back" or "her box left (her hull gone or changed)"
    end
    local bx = boxesPut()
    if bx then parts[#parts + 1] = bx end
    if (GH.route and GH.route ~= "none") or #parts > 0 then
        log(string.format("cine: the game's HUD back (%s; %s; hidden again %d times while held)", why,
            #parts > 0 and table.concat(parts, ", ") or "nothing to put back", GH.reverts))
    end
    GH.route, GH.items, GH.cheat, GH.show, GH.dist, GH.her, GH.boxes, GH.dropped = nil, nil, nil, nil, nil, nil, nil, false
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
    if GH.dist and os.clock() > GH.dist.untilAt - 1 then distMore(cfg.dist_refresh_s, "still held") end
    boxesKeep()
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
-- seconds into the rise, or nil before she plays (hooks.clock, else her rig's own position, else the clock since R.t1);
-- nil at once once the rise is over or her hull or rig is gone: never a call on a freed rig (hard rule 59)
local function clockOf(T)
    local h, R = T.hooks or {}, T.R or {}
    if R.back or not sameObj(R.o, R.name) or (R.rig ~= nil and not liveObj(R.rig)) then return nil end
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

-- monotone cubic (Fritsch-Carlson, flat at both ends) through (ts, vs) at t: tools/tanicorn/export_tanacorn.py pchip()
function CINE.pchip(ts, vs, t)
    local n = #ts
    if n == 0 then return nil end
    if n == 1 or t <= ts[1] then return vs[1] end
    if t >= ts[n] then return vs[n] end
    local h, d, m = {}, {}, {}
    for i = 1, n - 1 do h[i] = ts[i + 1] - ts[i]; d[i] = (vs[i + 1] - vs[i]) / h[i] end
    for i = 1, n do m[i] = 0 end
    for i = 2, n - 1 do
        if d[i - 1] * d[i] > 0 then
            local w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        end
    end
    local k = 1
    for i = 1, n - 1 do if ts[i] <= t then k = i end end
    local s = (t - ts[k]) / h[k]
    return (2 * s ^ 3 - 3 * s ^ 2 + 1) * vs[k] + (s ^ 3 - 2 * s ^ 2 + s) * h[k] * m[k]
        + (-2 * s ^ 3 + 3 * s ^ 2) * vs[k + 1] + (s ^ 3 - s ^ 2) * h[k] * m[k + 1]
end
-- the cameras' path through keys: { { t, at, look, fov, roll, cut, key = its key's index (nil between keys) } }, and the
-- spacing used. smooth: each run of keys (a cut key starts a new one) on monotone cubics, every column on its own as
-- export_tanacorn.py bakes RISE_CAM (the roll unwrapped), a camera about every `step` s (each key one, at most max_cams
-- in all); otherwise the keys themselves. The view waits on a run's last camera until the next run's cut.
function CINE.path(keys, smooth, step)
    local out = {}
    if not smooth then
        for i, k in ipairs(keys) do
            out[i] = { t = k.t, at = { k.at[1], k.at[2], k.at[3] }, look = { k.look[1], k.look[2], k.look[3] }, fov = k.fov,
                       roll = k.roll or 0, cut = (k.cut and i > 1) or nil, key = i }
        end
        return out, nil
    end
    local runs, cur = {}, nil
    for i, k in ipairs(keys) do
        if not cur or (k.cut and i > 1) then cur = {}; runs[#runs + 1] = cur end
        cur[#cur + 1] = i
    end
    local function count(st)
        local n = 0
        for _, run in ipairs(runs) do
            n = n + 1
            for j = 1, #run - 1 do n = n + math.max(1, math.ceil((keys[run[j + 1]].t - keys[run[j]].t) / st - 1e-9)) end
        end
        return n
    end
    step = math.max(0.05, tonumber(step) or cfg.sample_s)
    for _ = 1, 60 do if count(step) <= cfg.max_cams then break end step = step * 1.25 end
    for ri, run in ipairs(runs) do
        local ts, col = {}, {}
        for c = 1, 8 do col[c] = {} end
        for j, i in ipairs(run) do
            local k = keys[i]
            ts[j] = k.t
            col[1][j], col[2][j], col[3][j] = k.at[1], k.at[2], k.at[3]
            col[4][j], col[5][j], col[6][j] = k.look[1], k.look[2], k.look[3]
            col[7][j] = k.fov
            local r = k.roll or 0
            if j > 1 then                                 -- (the shorter way round)
                while r - col[8][j - 1] > 180 do r = r - 360 end
                while r - col[8][j - 1] < -180 do r = r + 360 end
            end
            col[8][j] = r
        end
        local function sample(t, key, cut)
            local v = {}
            for c = 1, 8 do v[c] = CINE.pchip(ts, col[c], t) end
            return { t = t, at = { v[1], v[2], v[3] }, look = { v[4], v[5], v[6] }, fov = v[7], roll = v[8], key = key, cut = cut }
        end
        for j = 1, #run do
            out[#out + 1] = sample(ts[j], run[j], (j == 1 and ri > 1) or nil)
            if j < #run then
                local h = ts[j + 1] - ts[j]
                local parts = math.max(1, math.ceil(h / step - 1e-9))
                for p = 1, parts - 1 do out[#out + 1] = sample(ts[j] + h * p / parts) end
            end
        end
    end
    return out, step
end

local function pvEnd(why, say)
    local P = S.pv
    if not P then return end
    S.pv = nil
    local back = (not isDown()) and viewBack(0)
    trash(P.cam, 0.5)
    HUD.hold(false, HOLD_PV)
    ghudShow(HOLD_PV, why)
    log(string.format("cine: preview over (%s): %s", tostring(why), back and "the view back on your plane"
        or (isDown() and "the view left to the spectator (you're down)" or "the view NOT given back (no plane)")))
    if say then hudCallout("CAMERA PREVIEW OVER", say) end
end

function CINE.stop(why)
    if type(levelTorn) == "function" and levelTorn() then return CINE.leave(why) end   -- (torn down: forgotten, untouched)
    local P = S.play
    if not P then
        if S.R then S.R = nil; log("cine: the rise's frame let go (" .. tostring(why) .. ")") end
        return false
    end
    S.play, S.R = nil, nil
    local down = isDown()
    local back = (not down) and viewBack(cfg.back_blend_s)
    for _, c in ipairs(P.cams) do trash(c, cfg.back_blend_s + 0.5) end
    HUD.hold(false, HOLD_CINE)
    ghudShow(HOLD_CINE, why)
    log(string.format("cine: cinematic over (%s): %s; %d blends, %d cuts, on camera %d of %d; held at a camera %d times "
        .. "(worst %.2f s); the view taken back by the game %d times", tostring(why),
        back and string.format("the view back on your plane (%.1f s)", cfg.back_blend_s)
            or (down and "the view left to the spectator (you're down)" or "the view NOT given back (no plane)"),
        #P.blends, P.cuts, P.cur, #P.path, P.holds, P.worst, P.reverts))
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
    if S.dir then S.dir = false; log("cine: director mode OFF (" .. tostring(why) .. ")") end
    S.R, S.run, S.hull, S.hullAt = nil, nil, nil, 0
end

function CINE.play(R, hooks)
    hooks = hooks or {}
    if S.play then CINE.stop("a new rise") end
    if S.pv then pvEnd("a rise") end
    if S.run ~= D then stopAll("a new run") end
    S.run = D
    CINE.load("the rise", true)
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
    local set = S.set
    local smooth = set.blend == "smooth"
    T.keys = copyKeys(S.keys)
    T.path, T.step = CINE.path(T.keys, smooth, cfg.sample_s)
    T.fn = BLEND[set.blend] or 0
    T.cams, T.cur, T.reverts, T.at, T.blends, T.holds, T.worst, T.cuts = {}, 1, 0, os.clock(), {}, 0, 0, 0
    local worst, fovs, lines = 0, 0, {}
    for i, p in ipairs(T.path) do
        local c, why = spawnCam(F, p)
        if not c then
            for _, m in ipairs(T.cams) do trash(m, 0) end
            binTick(os.clock(), true)
            log(string.format("cine: no cinematic: camera %d's %s", i, tostring(why)))
            return false, "camera " .. i .. ": " .. tostring(why)
        end
        T.cams[i] = c
        worst = math.max(worst, tonumber(c.off) or 0)
        if c.fovOk then fovs = fovs + 1 end
        if p.key then
            lines[#lines + 1] = string.format("key %d at %s s: camera %d at (%.0f, %.0f, %.0f) yaw %.0f pitch %.1f roll %.1f fov %s%s",
                p.key, num(p.t), i, c.at.X, c.at.Y, c.at.Z, c.rot.Yaw, c.rot.Pitch, c.rot.Roll, num(p.fov), p.cut and ", a cut" or "")
        end
    end
    local enter = (T.keys[1] and T.keys[1].cut) and 0 or set.enter_blend
    local okV = viewOn(T.cams[1].o, enter, false, 1)
    S.play, S.R = T, T
    HUD.hold(true, HOLD_CINE, { callouts = set.callouts })
    local hold = cfg.hold_s
    if type(TANI) == "table" and type(TANI.rise) == "table" and tonumber(TANI.rise.hold_s) then hold = tonumber(TANI.rise.hold_s) end
    ghudHide(HOLD_CINE, { need = hold + enter + T.path[#T.path].t / rateOf(T) + cfg.back_blend_s, her = { o = R.o, name = R.name } })
    log(string.format("cine: cinematic of %d keys: %d cameras (%s), rate %.2f: the view on camera 1 %s%s; read back worst "
        .. "%.1f deg off, FOV set on %d of %d; %s", #T.keys, #T.path,
        smooth and string.format("smooth: one about every %s s through the keys, linear blends", num(T.step)) or (set.blend .. " blends, one a key"),
        rateOf(T), enter > 0 and string.format("over %s s from your plane", num(enter)) or "at once (a cut)",
        okV and "" or " (SetViewTargetWithBlend FAILED)", worst, fovs, #T.path, table.concat(lines, "; ")))
    return true, "keyed"
end

-- the view along the path on the rise's clock t: the blend to each next camera started once the view is within lead_s
-- (real time) of the one it's going to, so it never stops there, over the time left to the new one at her rate, with
-- the camera it leaves locked (the blend from the view on screen); a cut camera reached by a cut at its time (to half a
-- lead), the blend after it in the same tick unlocked (its last frame's view is the one before the cut); before a cut
-- the view waits on the camera before it
local function drive(T, t)
    local P, n, r = T.path, #T.path, rateOf(T)
    local lead = cfg.lead_s * r
    local function cutAfter(i) for x = i + 1, n do if P[x].cut then return x end end return nil end
    local c, cutNow = cutAfter(T.cur), false
    if c and t + lead / 2 >= P[c].t then
        local ok = viewOn(T.cams[c].o, 0, false)
        T.cur, cutNow, T.cuts = c, true, T.cuts + 1
        T.blends[#T.blends + 1] = { i = c, t = t, blend = 0, lock = false, cut = true }
        log(string.format("cine: +%.2f s: cut to camera %d of %d (key %s at %s s)%s", t, c, n, tostring(P[c].key), num(P[c].t),
            ok and "" or " (SetViewTargetWithBlend FAILED)"))
        c = cutAfter(c)
    end
    local j = n
    for i = 1, n do if P[i].t > t + lead then j = i; break end end
    if c and j >= c then j = c - 1 end
    if j <= T.cur then return end
    local hold = (t - P[T.cur].t) / r                    -- (> 0: the view got to its camera and waited there this long)
    if not cutNow and hold > 0.001 then T.holds, T.worst = T.holds + 1, math.max(T.worst, hold) end
    local blend = (P[j].t - t) / r
    if blend <= 0 then blend = cfg.late_blend_s end
    local ok = viewOn(T.cams[j].o, blend, not cutNow, T.fn)
    T.blends[#T.blends + 1] = { i = j, t = t, blend = blend, lock = not cutNow }
    T.cur = j
    if P[j].key or not ok then
        log(string.format("cine: +%.2f s: to camera %d of %d%s over %.2f s%s", t, j, n,
            P[j].key and string.format(" (key %d at %s s)", P[j].key, num(P[j].t)) or "", blend, ok and "" or " (SetViewTargetWithBlend FAILED)"))
    end
end

-- the level left (sv_main.lua runLeft, beside SKY.restore: no tick of this part follows, D is gone): what can outlive
-- the level put back now (the game's HUD widgets: the flight HUD's outer is the game instance; with them every other
-- route and box change whose object is still alive), the view and the cameras left to the level, everything forgotten.
-- Once it's torn down (levelTorn: LEVEL_DROPS ran): only forgotten, nothing touched.
local FX = {}
local function drop(why)                                  -- (the level's objects forgotten, none of them touched; the
    S.play, S.pv, S.R, S.hull, S.hullAt, S.trash = nil, nil, nil, nil, 0, {}   -- game's HUD widgets kept to be put back
    HUD.hold(false, HOLD_CINE); HUD.hold(false, HOLD_PV)                     -- next run if alive)
    GH.holders, GH.cheat, GH.show, GH.dist, GH.her, GH.boxes = {}, nil, nil, nil, nil, nil
    if GH.route then if GH.items then GH.dropped = true else GH.route = nil end end
    if S.dir then S.dir = false; log("cine: director mode OFF (" .. tostring(why or "the level torn down") .. ")") end
    FX = {}
end
function CINE.leave(why)
    why = tostring(why or "the level was left")
    if type(levelTorn) == "function" and levelTorn() then drop(why); return false end
    local had = CINE.active() or (GH.route and "the game's HUD hidden") or (S.dir and "director mode") or nil
    S.play, S.pv, S.R, S.hull, S.hullAt, S.trash = nil, nil, nil, nil, 0, {}
    HUD.hold(false, HOLD_CINE); HUD.hold(false, HOLD_PV)
    GH.holders = {}
    if GH.route then ghudPut(why) end
    if S.dir then S.dir = false end
    S.run = nil
    FX = {}
    if had then log(string.format("cine: the level was left (%s) with %s: the game's HUD put back, the view and the cameras left to the level", why, had)) end
    return had ~= nil
end

---------------------------------------------------------------------------------------------------- the director
local function ready(k)
    if not (D and D.now) or not nativeReady() then log("cine: Ctrl+" .. k .. " outside a Survival run"); return false end
    if COOP and COOP.client and COOP.client() then log("cine: Ctrl+" .. k .. ": the host's (you're a joiner)"); return false end
    if S.run ~= D then stopAll("a new run") end
    S.run = D
    return true
end
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
        log(string.format("cine: key %d of %d (%s) at %s s: camera (%s, %s, %s) m from her middle (%s), looking at (%s, %s, %s), fov %s%s%s%s",
            i, #S.keys, why, num(k.t), num(k.at[1]), num(k.at[2]), num(k.at[3]),
            k.at[2] < 0 and "her port side" or (k.at[2] > 0 and "her starboard side" or "on her line"),
            num(k.look[1]), num(k.look[2]), num(k.look[3]), num(k.fov), k.roll and (", roll " .. num(k.roll)) or "",
            k.cut and ", a cut" or "", far))
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
    if S.pv then pvEnd("Ctrl+D", "BACK ON YOUR PLANE"); return end
    S.dir = not S.dir
    if S.dir then
        CINE.load("Ctrl+D", true)
        S.markAt, S.markSaid, S.hullAt = 0, nil, 0
        log(string.format("cine: Ctrl+D, director mode ON: a flash at each of the %d cameras' spots every %s s; the next Ctrl+R "
            .. "rises at %sx without the cinematic: fly round her, Ctrl+E records a key from your view at her time",
            #S.keys, num(cfg.marker_every_s), num(S.set.director_speed)))
        hudCallout("DIRECTOR MODE ON", string.format("NEXT RISE %sX, NO CINEMATIC", num(S.set.director_speed)))
    else
        log(string.format("cine: Ctrl+D, director mode OFF: the next Ctrl+R plays the cinematic (%d keys)", #(S.keys or {})))
        hudCallout("DIRECTOR MODE OFF", string.format("%d CAMERA KEYS", #(S.keys or {})))
    end
end)

-- your view: its place, its direction, its roll (nil: not read), its FOV, and where the direction came from
local function yourView()
    local pcm
    pcall(function() pcm = survivalPC.PlayerCameraManager end)
    if not valid(pcm) then return nil, "no camera manager" end
    local okL, l = pcall(function() local v = pcm:GetCameraLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (okL and l) then return nil, "GetCameraLocation not read" end
    local fwd, up, how = nil, nil, nil
    local okA, a = pcall(function() local v = pcm:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    local onIt = okA and a and math.sqrt((a.X - l.X) ^ 2 + (a.Y - l.Y) ^ 2 + (a.Z - l.Z) ^ 2) <= 100
    if onIt then
        pcall(function() local v = pcm:GetActorForwardVector(); fwd = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() local v = pcm:GetActorUpVector(); up = { X = v.X, Y = v.Y, Z = v.Z } end)
        how = "the camera manager's forward"
    end
    if not fwd then                                       -- (the manager's actor not on the view: its rotation, as given)
        up = nil
        local m = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
        local okR, r = pcall(function() return pcm:GetCameraRotation() end)
        if okR and r ~= nil and m ~= nil then
            pcall(function() local v = m:GetForwardVector(r); fwd = { X = v.X, Y = v.Y, Z = v.Z } end)
            pcall(function() local v = m:GetUpVector(r); up = { X = v.X, Y = v.Y, Z = v.Z } end)
        end
        how = "GetForwardVector(GetCameraRotation())" .. (okA and " (the manager's actor off the view)" or "")
    end
    if not fwd then
        up = nil
        pcall(function() local v = survivalPC.Pawn:GetActorForwardVector(); fwd = { X = v.X, Y = v.Y, Z = v.Z } end)
        how = "your plane's forward (the view's not read)"
    end
    local n = fwd and math.sqrt(fwd.X ^ 2 + fwd.Y ^ 2 + fwd.Z ^ 2) or 0
    if n < 1e-6 then return nil, "the view's direction not read" end
    local dir = { X = fwd.X / n, Y = fwd.Y / n, Z = fwd.Z / n }
    local roll = up and CINE.rollOf(dir, up) or nil
    local fov = 55
    pcall(function() local v = pcm:GetFOVAngle(); if type(v) == "number" and v > 1 then fov = v end end)
    return { at = l, dir = dir, roll = roll, fov = fov, how = how }
end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

testKey("E", "sv_cine.lua's camera key", function()
    if not ready("E") then return end
    if S.play then
        log("cine: Ctrl+E: the cinematic has the view (record in director mode: Ctrl+D, then Ctrl+R)")
        hudCallout("CTRL+E: THE CINEMATIC HAS THE VIEW", "RECORD IN DIRECTOR MODE (CTRL+D)")
        return
    end
    if S.pv then pvEnd("Ctrl+E", "CTRL+E AGAIN: RECORD A KEY"); return end
    if not S.keys then CINE.load("Ctrl+E", true)
    elseif not S.dirty and readFile(cfg.file) ~= S.text then CINE.load("Ctrl+E: the file was changed since it was read", true) end
    local F, src = frameNow(true)
    if not F then log("cine: Ctrl+E: " .. tostring(src)); hudCallout("CTRL+E: NO TANACORN UP", "CTRL+Y, CTRL+L OR CTRL+R FIRST"); return end
    local t, when = nil, nil
    if S.R then
        local R = S.R.R or {}
        t = clockOf(S.R)
        if t then when = "the rise's time"
        elseif not R.back and sameObj(R.o, R.name) and not R.playing then t, when = 0, "her hold: 0 s (she hasn't started rising)" end
    end
    if not t then
        t = (S.lastRec or -cfg.step_s) + cfg.step_s
        when = S.lastRec and string.format("no rise playing: the last key recorded (%s s) + %s s", num(S.lastRec), num(cfg.step_s))
            or "no rise playing, none recorded yet: 0 s"
    end
    t = math.floor(t * 100 + 0.5) / 100
    local v, why = yourView()
    if not v then log("cine: Ctrl+E: " .. tostring(why)); return end
    local lk = { X = v.at.X + v.dir.X * cfg.look_m * 100, Y = v.at.Y + v.dir.Y * cfg.look_m * 100, Z = v.at.Z + v.dir.Z * cfg.look_m * 100 }
    local a, b = CINE.toFrame(F, v.at), CINE.toFrame(F, lk)
    local roll = v.roll and r1(v.roll) or 0
    local k = { t = t, at = { r1(a[1]), r1(a[2]), r1(a[3]) }, look = { r1(b[1]), r1(b[2]), r1(b[3]) }, fov = r1(v.fov),
                roll = roll ~= 0 and roll or nil }
    local i, replaced = CINE.add(S.keys, k)
    if not i then log(string.format("cine: Ctrl+E: %d keys already: not added", cfg.max_keys)); return end
    S.lastRec = t
    CINE.save(S.keys, "Ctrl+E")
    log(string.format("cine: Ctrl+E, camera key %d of %d at %s s (%s)%s: at (%s, %s, %s) m, looking at (%s, %s, %s) m (%s m along "
        .. "%s), %s, fov %s; %s frame", i, #S.keys, num(t), when, replaced and ", replacing the key within " .. num(cfg.replace_s) .. " s" or "",
        num(k.at[1]), num(k.at[2]), num(k.at[3]), num(k.look[1]), num(k.look[2]), num(k.look[3]), num(cfg.look_m), v.how,
        v.roll and ("roll " .. num(roll)) or "roll NOT read: recorded level", num(k.fov), src))
    hudCallout(string.format("CAMERA KEY %d AT %.1f S", i, t), replaced and "REPLACED THE ONE THERE"
        or (k.roll and string.format("ROLL %.0f DEG", k.roll)) or nil)
end)

testKey("V", "sv_cine.lua's camera preview", function()
    if not ready("V") then return end
    if S.play then log("cine: Ctrl+V: the cinematic has the view"); return end
    if isDown() then
        log("cine: Ctrl+V: you're down (the spectator has the view)")
        hudCallout("CTRL+V: NOT WHILE YOU'RE DOWN")
        return
    end
    local pawn
    pcall(function() pawn = survivalPC.Pawn end)
    if not S.pv then
        if not (pawn ~= nil and valid(pawn)) then log("cine: Ctrl+V: no plane of yours"); return end
        CINE.load("Ctrl+V", true)
    end
    local i = (S.pv and S.pv.i or 0) + 1
    if i > #S.keys then pvEnd("past the last key", string.format("%d KEYS: BACK ON YOUR PLANE", #S.keys)); return end
    local F, src, her = frameNow(true)
    if not F then
        log("cine: Ctrl+V: " .. tostring(src))
        pvEnd("no frame")
        hudCallout("CTRL+V: NO TANACORN UP", "CTRL+Y, CTRL+L OR CTRL+R FIRST")
        return
    end
    local k = S.keys[i]
    local c, why = spawnCam(F, k)
    if not c then log(string.format("cine: Ctrl+V: key %d's camera %s", i, tostring(why))); pvEnd("no camera"); return end
    local old = S.pv and S.pv.cam
    local okV = viewOn(c.o, 0, false)
    trash(old, 0.5)
    S.pv = { i = i, cam = c, at = os.clock(), pawn = (S.pv and S.pv.pawn) or addrOf(pawn),   -- (your plane at the first
             pawnName = (S.pv and S.pv.pawnName) or nameOf(pawn) }                         --  press: its address and name)
    HUD.hold(true, HOLD_PV, { callouts = true })
    ghudHide(HOLD_PV, { need = cfg.preview_s, her = her })
    log(string.format("cine: Ctrl+V, key %d of %d at %s s: the view on its camera at (%.0f, %.0f, %.0f) yaw %.0f pitch %.1f "
        .. "roll %.1f (read back %s deg off), fov %s%s%s; %s frame", i, #S.keys, num(k.t), c.at.X, c.at.Y, c.at.Z, c.rot.Yaw,
        c.rot.Pitch, c.rot.Roll, c.off, num(k.fov), k.cut and ", a cut" or "", okV and "" or " (SetViewTargetWithBlend FAILED)", src))
    hudCallout(string.format("KEY %d OF %d AT %.1f S%s", i, #S.keys, k.t, k.cut and " (A CUT)" or ""),
        i == #S.keys and "CTRL+V OR CTRL+D: BACK TO YOUR PLANE" or "CTRL+D: BACK TO YOUR PLANE")
end)

testKey("W", "sv_cine.lua's new take", function()
    if not ready("W") then return end
    if S.play then log("cine: Ctrl+W: not while the cinematic plays"); return end
    if S.pv then pvEnd("Ctrl+W") end
    if not S.keys then CINE.load("Ctrl+W", true) end
    local disk = readFile(cfg.file)
    local text = (disk and not S.dirty) and disk or CINE.text(S.keys, S.set)   -- (the take as the file has it, edits too)
    local kept = #(CINE.parse(text))
    local name = takeName()
    local okT, whyT = writeFile(name, text)
    if not okT then
        log(string.format("cine: Ctrl+W: the take NOT kept in config\\%s (%s): no new take, your %d keys stay", name, tostring(whyT), kept))
        hudCallout("NEW TAKE NOT STARTED", "THE OLD ONE COULDN'T BE KEPT")
        return
    end
    S.text = disk                                         -- (kept in the take: no .edited copy of it)
    S.keys = copyKeys(CINE.DEFAULTS)
    CINE.keys = S.keys
    local okS = CINE.save(S.keys, "Ctrl+W, a new take")
    S.lastRec = nil
    log(string.format("cine: Ctrl+W, a new take: the %d keys kept in config\\%s (never written again), today's camera back "
        .. "(%d keys)%s", kept, name, #S.keys, okS and "" or " (NOT saved)"))
    hudCallout("NEW TAKE", string.format("%d KEYS KEPT IN %s", kept, name:upper()))
end)

TEST_TICKS[#TEST_TICKS + 1] = { name = "cine", fn = function(now)
    if (S.play or S.pv or S.R or S.dir or GH.route or #S.trash > 0) and S.run ~= D then stopAll("the run's over") end
    binTick(now)
    if GH.dropped and GH.route then ghudPut("the level before it was torn down") end
    local paused = type(gamePaused) == "function" and gamePaused(survivalPC) == true
    local down = isDown()
    if S.R and S.R ~= S.play then                         -- (a director rise's frame, let go once it's over)
        local R = S.R.R
        local gone = type(R) ~= "table" and "no rise" or (R.back and "the rise is over") or (not sameObj(R.o, R.name) and "her hull is gone")
        if gone then S.R = nil; log("cine: the rise's frame let go (" .. gone .. ")") end
    end
    local T = S.play
    if T then
        local R = T.R
        if type(R) == "table" and R.back then CINE.stop("the rise is over"); T = nil
        elseif now - T.at > cfg.max_s then CINE.stop(string.format("still up after %d s", cfg.max_s)); T = nil
        elseif down then CINE.stop("you're down: the spectator's view"); T = nil end
    end
    if T then
        local t = clockOf(T)
        if t then drive(T, t) end
        local cam = T.cams[T.cur]
        if not sameObj(cam.o, cam.name) then
            CINE.stop("camera " .. T.cur .. " is gone")
        elseif not paused then
            if viewKeep(cam.o) then
                T.reverts = T.reverts + 1
                if T.reverts == 1 then log("cine: the game took the view: given back to camera " .. T.cur) end
            end
        end
    end
    local P = S.pv
    if P then
        if paused then P.at = P.at + (now - (P.tickAt or now)) end   -- (its clock held while paused)
        P.tickAt = now
        local pawn
        pcall(function() pawn = survivalPC.Pawn end)
        if down then pvEnd("you're down: the spectator's view")
        elseif not (pawn ~= nil and valid(pawn)) or addrOf(pawn) ~= P.pawn or nameOf(pawn) ~= P.pawnName then   -- (rule 59)
            pvEnd("your plane changed or is gone")
        elseif now - P.at > cfg.preview_s then pvEnd(string.format("no Ctrl+V for %d s", cfg.preview_s), "BACK ON YOUR PLANE")
        elseif not paused then
            if sameObj(P.cam.o, P.cam.name) then viewKeep(P.cam.o) else pvEnd("its camera is gone") end
        end
    end
    if GH.route and not paused then ghudKeep() end
    if S.dir and S.keys then markers(now) end
end }
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["cine"] = drop end
CINE.load("loaded")
end
-- TEST ONLY END
