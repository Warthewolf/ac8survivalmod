-- sv_escort_laser.lua: the ZFA-44 carriers' anti-missile laser (2026-11-07; tools/re/LASER_INTERCEPTOR.md "Built").
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order, right after sv_escort.lua and sv_escort_subs.lua
-- (sv_escort's family): a name another part uses is a global of this mod's Lua state, its own helpers stay local.
--
-- The VAMPIRES' planes (the ZFA-44 host, DT_NPC row CFG.allies.carrier.dt_npc) carry AC8's own anti-missile laser, the
-- Nightmare UAV's BP_SwingTLS_ForMSL, on a fire-control arm of Survival's (BP_FCS_SV_ZfaTLS: the ships' CIWS arm with that
-- weapon, its launcher at the host's gun socket, its AI searching missiles only) in fire-control slot 3. The build makes
-- the arm, its fire-control row (laser_fcs_row in laser_fcs_table) and the host's laser twin (laser_row: dt_npc's row with
-- slot 3 that row) (tools/build_survival_world.py build_zfa_laser, build_survival.py build_npc_rows); here, every game:
--   ZLAS.zfaRow(npc, mine, addRow, row)  (sv_escort.lua ESC.setup, the main menu) the host's DT_NPC row: with
--                                         CFG.allies.carrier.zfa.laser on and laser_fcs_row in the game's DT_NPC_FCS
--                                         (FindRow + AddRow from Survival's table, its FCSBlueprintClass never read: hard
--                                         rule 29), row made from laser_row's struct; else the plain one. -> in, its note
--   ZLAS.arms(plane, unit)               (sv_escort.lua dressTick, settle_s after a carrier flight's plane is seen) its
--                                         fire control's systems, once a plane (laser_arms_log a run at most):
--                                         `zfa laser: <unit> plane <addr> fire control: 0 <system> <weapon>; ...`
--   ZLAS.tick()                          (ESC.tick) the interceptions (the build's WID_tls WeaponIntercept trigger adds 1 to
--                                         laser_flag): `carrier: the ZFA-44s' lasers have shot down N missiles (+d)`
ZLAS = { armed = false, r = nil }
do
local function zc() return ((CFG.allies or {}).carrier or {}).zfa or {} end
local function run()
    if not ZLAS.r or ZLAS.r.D ~= D then ZLAS.r = { D = D, hits = 0, said = {}, n = 0 } end
    return ZLAS.r
end
local function short(o)                                   -- "BP_SwingTLS_ForMSL" from "... .BP_SwingTLS_ForMSL_C"
    local n = nameOf(o):match("([%w_]+)$") or "?"
    return (n:gsub("_C_%d+$", ""):gsub("_C$", ""))
end

-- ((2026-11-07) the user: the ZFA-44s' boxes read "SU-47") the host's own model row first (CFG.allies.carrier.zfa.model,
-- the allied Su-47's but its name: "ZFA-44"), from Survival's DT_SV_ModelRows into the game's DT_NPC_Model, as the shoal's
-- (sv_fishing.lua FISH.setup): the host row names it. -> in, why not
function ZLAS.zfaModel()
    local m = zc().model
    if type(m) ~= "string" or m == "" then return true, "no model of its own" end
    local mt, w1 = loadObject(ACE.model_table)
    local mr, w2 = loadObject(ACE.model_rows)
    if not (mt and mr) then return false, "the model tables didn't load (" .. tostring(w1 or w2) .. ")" end
    for _, t in ipairs({ mt, mr }) do pin(t, nameOf(t)) end
    local _, have = dtCall(mt, "FindRow", m)
    if have == nil then
        local _, r = dtCall(mr, "FindRow", m)
        if r == nil then return false, m .. " not in " .. nameOf(mr) end
        dtCall(mt, "AddRow", m, r)
        _, have = dtCall(mt, "FindRow", m)
    end
    if have == nil then return false, m .. " NOT added to DT_NPC_Model" end
    return true, m .. " in DT_NPC_Model"
end

function ZLAS.zfaRow(npc, mine, addRow, row)
    ZLAS.armed = false
    local z = zc()
    local okM, why = ZLAS.zfaModel()                       -- (its model before its row: the row names it)
    if not okM then return false, " (its model row " .. tostring(why) .. ": no ZFA-44 host)" end
    if z.laser == false then return addRow(row), " (laser off: the plain host)" end
    local function plain(why) return addRow(row), " (no laser: " .. why .. ")" end
    local fr, lr = tostring(z.laser_fcs_row), tostring(z.laser_row)
    local _, have = dtCall(npc, "FindRow", row)
    if have ~= nil then                                    -- (in already: which one, by its laser slot, laser_slot)
        local cur, key = nil, "NpcFCSId" .. tostring(math.floor(tonumber(z.laser_slot) or 1))
        pcall(function() cur = have[key]:ToString() end)
        ZLAS.armed = cur == fr
        return true, ZLAS.armed and " (already in, with the laser)" or " (already in, no laser)"
    end
    local fcsT, why1 = loadObject(FCS_TABLE)
    if not fcsT then return plain("DT_NPC_FCS not loaded: " .. tostring(why1)) end
    local mineT, why2 = loadObject(tostring(z.laser_fcs_table))
    if not mineT then return plain(tostring(z.laser_fcs_table) .. " not loaded: " .. tostring(why2)) end
    for _, t in ipairs({ fcsT, mineT }) do pin(t, nameOf(t)) end
    local _, inF = dtCall(fcsT, "FindRow", fr)
    if inF == nil then
        local _, r = dtCall(mineT, "FindRow", fr)          -- (passed on whole: its soft class never read, hard rule 29)
        if r == nil then return plain(fr .. " not in " .. nameOf(mineT)) end
        dtCall(fcsT, "AddRow", fr, r)
        _, inF = dtCall(fcsT, "FindRow", fr)
        if inF == nil then return plain(fr .. " NOT added to DT_NPC_FCS") end
    end
    local _, tr = dtCall(mine, "FindRow", lr)
    if tr == nil then return plain(lr .. " not in " .. nameOf(mine)) end
    dtCall(npc, "AddRow", row, tr)
    local _, got = dtCall(npc, "FindRow", row)
    if got == nil then return plain(row .. " from " .. lr .. " NOT added") end
    ZLAS.armed = true
    return true, string.format(" (with the anti-missile laser: %s's struct, its slot %s %s in place of the gun, that row in DT_NPC_FCS)", lr,
        tostring(z.laser_slot or 1), fr)
end

function ZLAS.arms(o, unit)
    local a = addrOf(o)
    local R = run()
    if not a or R.said[a] then return end
    R.said[a] = true
    R.n = R.n + 1
    if R.n > (tonumber(zc().laser_arms_log) or 40) then return end
    local okC, fcs = pcall(function() return o.FireControlSystemComponent end)
    if not (okC and valid(fcs)) then
        log(string.format("zfa laser: %s plane %s: no fire control read", tostring(unit), tostring(a)))
        return
    end
    local slots, k, at = {}, 0, nil
    local okA, errA = pcall(function()
        fcs.AllArms:ForEach(function(_, e)
            k = k + 1
            local arm, txt = e:get(), "-"
            if valid(arm) then
                local sys, w, cls = "?", nil, nil
                pcall(function() sys = arm.SystemName:ToString() end)
                pcall(function() local pm = arm.ProjectileModule; if valid(pm) and valid(pm.WeaponClass) then w = short(pm.WeaponClass) end end)
                pcall(function() cls = nameOf(arm:GetClass()) end)
                txt = sys .. (w and (" " .. w) or "")
                if cls and cls:find("/Game/Mods/SurvivalMode/", 1, true) then txt, at = txt .. " (Survival's arm)", k - 1 end
            end
            slots[#slots + 1] = string.format("%d %s", k - 1, txt)
        end)
    end)
    log(string.format("zfa laser: %s plane %s fire control: %s%s", tostring(unit), tostring(a),
        #slots > 0 and table.concat(slots, "; ") or ("none read" .. (okA and "" or (" (" .. tostring(errA) .. ")"))),
        at and string.format(" -> the laser in slot %d", at) or (ZLAS.armed and " -> NO laser arm" or "")))
end

function ZLAS.tick()
    if ZLAS.drive then                                     -- ((0.74.12) the laser made sure: below, every game, armed or not)
        local okD, errD = pcall(ZLAS.drive)
        if not okD then logOnce("zfa laser drive", "zfa laser: error " .. tostring(errD)) end
    end
    if D and ZLAS.summary and ZLAS.lastRound ~= D.round then
        local line = ZLAS.lastRound and ZLAS.summary() or nil
        if line then log(string.format("carrier: round %s: %s", tostring(ZLAS.lastRound), line)) end
        ZLAS.lastRound = D.round
    end
    if not (ZLAS.armed and D) then return end
    local t = svFlags()
    local n = t and t[tostring(zc().laser_flag)]
    if type(n) ~= "number" then return end
    local R = run()
    if n < R.hits then R.hits = n end                      -- (a new level's flags)
    if n > R.hits then
        log(string.format("carrier: the ZFA-44s' lasers have shot down %d missile%s (+%d)", n, n == 1 and "" or "s", n - R.hits))
        R.hits = n
    end
end
end

---------------------------------------------------------------------------------------------------- the laser made sure
-- ((0.74.12) the user: "Make sure that you swap the guns out for the Laser Interceptor. The Laser Interceptor HAS to work,
-- no exceptions". The 0.74.10 game: the arm was on every ZFA-44 (slot 3) and nothing was ever shot down) The laser arm is
-- in the gun's slot now (the build's ZFA_TLS_SLOT 1: no gun), and Survival makes sure of it, every game:
--   * the game's own shots (every TLS anti-missile laser the game makes, LiveTLSSwingforMissile, a ZFA-44's: an ally's)
--     hit every time: its InterceptPercentage (0.3 stock) laser_chance, its cone laser_angle, its reach laser_range_m;
--     on that laser's instance only, never its class (the Nightmare UAV's stays as shipped)
--     `zfa laser: <plane>'s own fire control fired its laser (...): chance 0.30 -> 1.00, ...`
--   * Survival's own: each ZFA-44 alive fires at the nearest enemy missile within laser_range_m (HIT.msl: every missile
--     but the player's; an enemy's: its shooter's faction isn't ours, or it homes on one of ours), one every
--     laser_shot_s: the laser's own beam (laser_beam_fx, its length to the missile) from the plane, its fire sound;
--     laser_swing_s on, the missile is shot down: the TLS's air burst (laser_kill_fx) and hit sound where it is, and the
--     missile made harmless the way the STORE's ECM does (no lock, no damage: never destroyed from Lua, hard lesson of
--     2026-10-25), its life cut short (laser_timeout: the game's own end of a missile)
--     `zfa laser: <plane> fires at <missile> d m (from <shooter>, at <target>)`, `zfa laser: <missile> shot down ...`
--   * a missile the game's own laser is on is left to it, then made harmless the same way at the swing's end
-- laser_drive = false: only the game's own fire control (and its own 30 %).
ZLAS.newL, ZLAS.fx = {}, {}
pcall(NotifyOnNewObject, "/Script/Live.LiveTLSSwingforMissile", function(o)
    if #ZLAS.newL < 32 then ZLAS.newL[#ZLAS.newL + 1] = o end
end)
do
local ALPHA = 1                                          -- (ELiveFaction Alpha: the players' side; the enemies' world data is 2)
local function zc() return ((CFG.allies or {}).carrier or {}).zfa or {} end
local function num(v, d) v = tonumber(v); if v == nil then return d end; return v end
local function D_() return ZLAS.d and ZLAS.d.D == D and ZLAS.d or nil end
local function st()
    local s = D_()
    if not s then
        s = { D = D, claims = {}, busy = {}, shots = 0, kills = 0, own = 0, said = 0, loaded = {}, pending = {} }
        ZLAS.d = s
    end
    return s
end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function short(o)
    local n = nameOf(o):match("([%w_]+)$") or "?"
    return (n:gsub("_C_%d+$", ""):gsub("_C$", ""))
end
local function faction(o)
    local ok, f = pcall(function() return o:GetFaction() end)
    return ok and tonumber(f) or nil
end
-- the assets (loaded once a level each, one a tick before they're needed)
local A = {}
local function asset(path)
    if type(path) ~= "string" or path == "" then return nil end
    local full = path .. "." .. path:match("[^/]+$")
    local o = A[full]
    if o ~= nil and liveObj(o) then return o end
    A[full] = nil
    o = loadObject(full)
    if o ~= nil and valid(o) then A[full] = o; return o end
    return nil
end
local function assetList()
    local z = zc()
    return { z.laser_beam_fx, z.laser_kill_fx, z.laser_fire_sound, z.laser_hit_sound }
end
-- a sound where something is (Wwise's PostEventAtLocation; two signatures tried, the first that works kept)
local function sound(path, where)
    if zc().laser_sound == false or not where then return end
    local s = st()
    if s.soundBad then return end
    local ev, ak = asset(path), StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
    if not (ev and valid(ak) and liveObj(survivalPC)) then return end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    local tries = {
        function() return ak:PostEventAtLocation(ev, where, rot, survivalPC) end,
        function() return ak:PostEventAtLocation(ev, where, rot, "", survivalPC) end,
    }
    local okAny, errs = false, {}
    for i = (s.soundWay or 1), (s.soundWay or #tries) do
        local ok, err = pcall(tries[i])
        if ok then s.soundWay, okAny = i, true; break end
        errs[#errs + 1] = tostring(err)
    end
    if not okAny then
        s.soundBad = true
        log("zfa laser: its sounds can't be played (" .. table.concat(errs, "; ") .. "): the beam and the burst without them")
    end
end
-- a Niagara system at `where` turned `rot`, its beam length `len` (cm) if given, switched off `life` seconds on
local function fx(path, where, rot, len, life)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = asset(path)
    if not (valid(lib) and sys and liveObj(survivalPC) and where) then return false end
    local ok, err = pcall(function()
        local comp = lib:SpawnSystemAtLocation(survivalPC, sys, where, rot or { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = 1, Y = 1, Z = 1 }, true, true, 0, true)
        if comp and comp:IsValid() then
            if len then
                pcall(function() comp:SetVariableFloat(FName("User.BeamLength"), len) end)
                pcall(function() comp:SetVariableFloat(FName("BeamLength"), len) end)
            end
            ZLAS.fx[#ZLAS.fx + 1] = { comp = comp, offAt = os.clock() + (life or 1) }
        end
    end)
    if not ok then logOnce("zfa laser fx", "zfa laser: an effect failed (" .. tostring(path) .. "): " .. tostring(err)) end
    return ok
end
local function fxTick(all)
    local keep = {}
    for _, e in ipairs(ZLAS.fx) do
        local alive = false
        pcall(function() alive = e.comp:IsValid() end)
        if alive and not e.offDone and (all or os.clock() >= e.offAt) then
            pcall(function() e.comp:Deactivate() end)      -- (auto-destroyed once what's out has faded)
            e.offDone = true
        end
        if alive and not e.offDone then keep[#keep + 1] = e end
    end
    ZLAS.fx = keep
end
local function aim(a, b)                                 -- the rotation from a to b, and how far (cm)
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local h = math.sqrt(dx * dx + dy * dy)
    return { Pitch = math.deg(math.atan(dz, h)), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }, math.sqrt(h * h + dz * dz)
end
-- an enemy's missile? (its shooter's faction isn't ours; that unread, it homes on one of ours) cached on the HIT.msl entry
local function enemy(m)
    if m.zEnemy ~= nil then return m.zEnemy end
    local f
    for _, get in ipairs({ function() return m.obj:GetOwner() end, function() return m.obj.Instigator end }) do
        local ok, w = pcall(get)
        if ok and w and liveAddr(w) then f = faction(w); if f then break end end
    end
    if f and f ~= 0 then m.zEnemy = (f ~= ALPHA); return m.zEnemy end
    local ok, t = pcall(function() return m.obj.TargetToHome end)
    if ok and t and liveAddr(t) then
        local tf = faction(t)
        if tf then m.zEnemy = (tf == ALPHA); return m.zEnemy end
    end
    return nil                                           -- (not known yet: asked again next tick)
end
local function gone(o)
    if not liveAddr(o) then return true end
    local ok, d = pcall(function() return o:IsDestroyed() end)
    return ok and d == true
end
-- shot down: harmless now whatever else happens (the ECM's way), its life cut, the burst where it is
local function kill(c, s, why)
    local o, where = c.m.obj, c.m.zAt
    if gone(o) then
        c.m.zDone = true
        if s.said < num(zc().laser_log_n, 40) then
            s.said = s.said + 1
            log(string.format("zfa laser: %s was gone before the swing's end (%s): hit something, or the game's own laser had it", c.name, why))
        end
        return false
    end
    pcall(function() o.bIsHoming = false end)
    pcall(function() o.damage = 0 end)
    local cut = false
    if zc().laser_timeout ~= false then cut = pcall(function() o.LifeTime = 0.05 end) end
    where = at(o) or where
    fx(zc().laser_kill_fx, where, nil, nil, 3)
    sound(zc().laser_hit_sound, where)
    c.m.zDone, c.m.zKilledAt = true, os.clock()
    s.kills = s.kills + 1
    if s.said < num(zc().laser_log_n, 40) or s.kills % 10 == 0 then
        s.said = s.said + 1
        log(string.format("zfa laser: %s shot down (%s; %d so far): no lock, no damage%s", c.name, why, s.kills,
            cut and ", its life cut" or ""))
    end
    s.pending[#s.pending + 1] = { o = o, name = c.name, due = os.clock() + 1.5 }
    return true
end

-- the game's own lasers: each one made sure as it appears (a ZFA-44's only)
local function ownLasers(s)
    local q = ZLAS.newL
    if #q == 0 then return end
    ZLAS.newL = {}
    local z = zc()
    for _, o in ipairs(q) do
        if liveAddr(o) and not nameOf(o):find("Default__", 1, true) then
            local okW, w = pcall(function() return o:GetOwner() end)
            local f = okW and w and liveAddr(w) and faction(w)
            if f == ALPHA or f == nil then
                local was = nil
                pcall(function() was = o.InterceptPercentage end)
                local r = num(z.laser_range_m, 3000) * 100
                pcall(function() o.InterceptPercentage = num(z.laser_chance, 1.0) end)
                pcall(function() o.InterceptAngle = num(z.laser_angle, 180) end)
                pcall(function() o.InterceptDistanceSquared = r * r end)
                s.own = s.own + 1
                local tgt = nil
                pcall(function() local t = o.MissileToIntercept; if t and liveAddr(t) then tgt = t end end)
                s.ownL = s.ownL or {}
                s.ownL[#s.ownL + 1] = { o = o, due = os.clock() + num(z.laser_swing_s, 0.35) + 2.0, tgt = tgt }
                if s.own <= 10 or s.own % 25 == 0 then
                    log(string.format("zfa laser: %s's own fire control fired its laser (%s, %d so far): chance %s -> %.2f, cone %g deg, reach %g m%s",
                        w and short(w) or "?", short(o), s.own, tostring(was), num(z.laser_chance, 1.0), num(z.laser_angle, 180),
                        num(z.laser_range_m, 3000), tgt and (", on " .. short(tgt)) or ""))
                end
            end
        end
    end
end
-- the missiles the game's own lasers are on: claimed (Survival doesn't fire at them too), made sure at the swing's end
local function ownClaims(s, now)
    local keep = {}
    for _, e in ipairs(s.ownL or {}) do
        if liveAddr(e.o) then
            pcall(function() local t = e.o.MissileToIntercept; if t and liveAddr(t) then e.tgt = t end end)
        end
        if e.tgt then
            local a = addrOf(e.tgt)
            for _, m in ipairs((HIT and HIT.msl) or {}) do
                if addrOf(m.obj) == a and not m.zDone and not s.claims[a] then
                    s.claims[a] = { m = m, name = m.name or short(e.tgt), due = e.due, own = true }
                end
            end
        end
        if os.clock() < e.due then keep[#keep + 1] = e end
    end
    s.ownL = keep
end

function ZLAS.drive(now)
    local z = zc()
    if z.laser == false or z.laser_drive == false or not D then return end
    if (levelTorn and levelTorn()) or not liveObj(survivalPC) then return end
    local s = st()
    fxTick(false)
    ownLasers(s)
    -- the ZFA-44s alive
    local ps = {}
    for u, l in pairs(ESC.planes or {}) do
        if ESC.kindOf(u) == "zfa" then
            for _, e in ipairs(l) do
                if liveAddr(e.obj) == e.addr then
                    local okH, h = pcall(function() return e.obj.HealthInternal end)
                    if not (okH and type(h) == "number" and h <= 0) then
                        local p = at(e.obj)
                        if p then ps[#ps + 1] = { o = e.obj, a = e.addr, at = p, unit = u } end
                    end
                end
            end
        end
    end
    if #ps == 0 then return end
    for _, path in ipairs(assetList()) do               -- (loaded before the first shot: one a tick)
        if not s.loaded[path] then s.loaded[path] = true; asset(path); break end
    end
    ownClaims(s, now)
    local clock = os.clock()
    -- the claims due: shot down
    for a, c in pairs(s.claims) do
        if clock >= c.due then
            s.claims[a] = nil
            if not c.m.zDone then kill(c, s, c.own and "the game's own laser's swing over" or ("by " .. c.by)) end
        end
    end
    -- the missiles gone after their cut: logged (does a cut life end it?)
    for i = #s.pending, 1, -1 do
        local e = s.pending[i]
        if gone(e.o) then
            table.remove(s.pending, i)
            if not s.cutSaid then s.cutSaid = true; log("zfa laser: " .. e.name .. " gone after its life was cut (the game's own end of a missile)") end
        elseif clock >= e.due then
            table.remove(s.pending, i)
            if not s.cutSaid then s.cutSaid = true; log("zfa laser: " .. e.name .. " still flying 1.5 s after its life was cut: harmless (no lock, no damage) until it runs out") end
        end
    end
    -- the enemy missiles within reach of one of them
    local range = num(z.laser_range_m, 3000) * 100
    local ms = {}
    for _, m in ipairs((HIT and HIT.msl) or {}) do
        if not m.zDone and not s.claims[addrOf(m.obj) or 0] and liveAddr(m.obj) then
            local e = enemy(m)
            if e then
                local p = at(m.obj)
                if p then m.zAt = p; ms[#ms + 1] = m end
            end
        end
    end
    if #ms == 0 then return end
    local shot = num(z.laser_shot_s, 1.0)
    for _, p in ipairs(ps) do
        if clock >= (s.busy[p.a] or 0) then
            local best, bd = nil, range
            for _, m in ipairs(ms) do
                if not m.zClaimed then
                    local d = dist(p.at, m.zAt)
                    if d <= bd and not gone(m.obj) then best, bd = m, d end
                end
            end
            if best then
                best.zClaimed = true
                local ma = addrOf(best.obj)
                local nm = (best.name or short(best.obj)) .. "@" .. tostring(ma)
                s.claims[ma] = { m = best, name = nm, due = clock + num(z.laser_swing_s, 0.35), by = short(p.o) }
                s.busy[p.a] = clock + shot
                s.shots = s.shots + 1
                local rot, len = aim(p.at, best.zAt)
                fx(z.laser_beam_fx, p.at, rot, len, num(z.laser_beam_s, 0.6))
                sound(z.laser_fire_sound, p.at)
                if s.said < num(z.laser_log_n, 40) then
                    s.said = s.said + 1
                    local tgt = "?"
                    pcall(function() local t = best.obj.TargetToHome; if t and liveAddr(t) then tgt = short(t) end end)
                    log(string.format("zfa laser: %s (%s) fires at %s %.0f m off (from %s, at %s): beam %.0f m, yaw %.0f pitch %.0f",
                        short(p.o), p.unit, nm, bd / 100, tostring(best.from or "?"), tgt, len / 100, rot.Yaw, rot.Pitch))
                end
            end
        end
    end
end

-- the run's total, at the end of each round (sv_escort.lua's round end calls nothing: ZLAS.tick logs it when it changes)
function ZLAS.summary()
    local s = D_()
    if not s or (s.shots == 0 and s.own == 0) then return nil end
    return string.format("the ZFA-44s' lasers: %d shots of Survival's, %d of their own fire control, %d missiles shot down",
        s.shots, s.own, s.kills)
end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS.zfa_laser = function() ZLAS.d, ZLAS.newL, ZLAS.fx = nil, {}, {} end   -- (nothing of the old level touched)
end
end
