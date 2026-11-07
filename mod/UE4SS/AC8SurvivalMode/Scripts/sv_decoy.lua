-- sv_decoy.lua: THE DECOY, a special round (user, 2026-11-06; tools/re/DECOY.md has the research, the build and the test
-- checklist).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order (after sv_spaceport); a name another part uses
-- is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- A Marker UAV far north (the bait, SV_Unit_DecoyBait: AC8's OP0033_uavst with its Tonitrus Spear guidance laser, an
-- ALiveAIAirshipLaserPod child) paints the airfield (RE_SV_DecoyBaitLaser onto the dummy SV_Unit_DecoyBaitMark) and is
-- pinged on the minimap. Once it's down (or bait_timeout_s on) the trap springs: up to max_total Spear UAVs
-- (SV_Unit_DecoyUav_NN, one Marker UAV each on a weaponless row) come round the players, each locking its closest
-- player: its own invisible mark (SV_Unit_DecoyMark_NN) is kept on that player's plane (attached, else moved each tick)
-- and its laser put on the mark (RE_SV_DecoyLaserOn_NN). The laser searches lock_delay_s; then that player has lock_s
-- (8 s) to shoot the UAV down, or the Tonitrus Spear is called onto them (RE_SV_DecoySpear_<s>: Mission 19's rod,
-- LiveFireOneShotWeapon at "Player" from one of four virtual shooters SV_Unit_DecoySpear_<s>, its impact counted in the
-- flag SV_DecoySpearHit; led by the player's velocity through the rod's PredictionTime). The 8 s are Lua's own (no
-- stock lock is that short). A UAV shot down cancels its strike. relock_s after a call it locks its closest player
-- again. The trap ends with all of them down, every living player inside safe_km of the runway, or trap_s.
--
-- Co-op (host-authoritative, as every enemy): the host spawns the bait, the marks, the launchers and the UAVs (its
-- spawns go to every game, sv_coop.lua), decides who each UAV locks and when a UAV is down, and tells every joiner
-- ("dk": the round's state, each lock's UAV and target slot, each cancel). Every game puts its own copy's laser on its
-- own copy of the mark, kept on that player's plane there (the records are each game's own: sv_coop.lua KEEP_EVENTS
-- "^RE_SV_Decoy"). Only the targeted player's game runs the 8 s, the radio and the strike (RE_SV_DecoySpear_* and
-- RE_SV_DecoyKill name "Player": that game's own plane); there the UAV counts as down once the host's kill came or this
-- game has sent a killing hit on its copy (COOP.killSent: the copy waits at the 1 HP floor for the host). A strike that
-- downs a co-op player puts them DOWN through the revives' floor like any other kill (sv_down.lua).
DECOY = { G = {}, R = {}, W = {}, rq = {}, rodNew = {}, rods = {}, said = {}, Q = { by = {}, n = {} }, unitSet = {},
          st = { locks = 0, struck = 0, hits = 0, cancelled = 0 }, rx = { at = -1, n = 0 } }

do
local function cfg() return (CFG.specials and CFG.specials.decoy) or {} end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function clockNow() return (D and D.now) or os.clock() end
local function mySlot() return (COOP and COOP.open and COOP.slot) or 0 end
local function isHost() return COOP ~= nil and type(COOP.host) == "function" and COOP.host() == true end
local function isClient() return COOP ~= nil and type(COOP.client) == "function" and COOP.client() == true end
local function said(key, msg) if not DECOY.said[key] then DECOY.said[key] = true; log(msg) end end
local function errText(r) return r == 1 and "fired" or ("not fired: " .. tostring((SV_ERR and SV_ERR[r]) or r)) end
local function dist3(a, b) local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z; return math.sqrt(dx * dx + dy * dy + dz * dz) end
local function dist2(a, x, y) local dx, dy = a.X - x, a.Y - y; return math.sqrt(dx * dx + dy * dy) end
local function maxUavs() return math.max(1, math.min(99, math.floor(num(cfg().uavs, 35)))) end
local function maxTotal() return math.max(0, math.min(maxUavs(), math.floor(num(cfg().max_total, 35)))) end

---------------------------------------------------------------------------------------------------- names
-- (tools/survival_events.py builds them; names ending in digits are stored split there, hard rule 17)
function DECOY.uav(k) return string.format("%s%02d", tostring(cfg().uav_prefix or "SV_Unit_DecoyUav_"), k) end
function DECOY.mark(k) return string.format("%s%02d", tostring(cfg().mark_prefix or "SV_Unit_DecoyMark_"), k) end
function DECOY.spear(s) return tostring(cfg().spear_prefix or "SV_Unit_DecoySpear_") .. tostring(s) end
local function evLaserOn(k) return string.format("RE_SV_DecoyLaserOn_%02d", k) end
local function evLaserOff(k) return string.format("RE_SV_DecoyLaserOff_%02d", k) end
local function evSpear(s) return "RE_SV_DecoySpear_" .. tostring(s) end
-- (the build's fallback for a mark that neither attaches nor moves: Mission 22's teleport onto this game's player)
local function evMarkOnMe(k) return string.format("RE_SV_DecoyMarkOnMe_%02d", k) end
-- (bait_ping and bait_laser_off aren't in the build contract of 2026-11-06: tools/re/DECOY.md "names Lua asks for";
-- a build without them answers "no such unit" and the round goes on without the ping)
DECOY.EV = { bait_laser = "RE_SV_DecoyBaitLaser", bait_laser_off = "RE_SV_DecoyBaitLaserOff",
             bait_ping = "RE_SV_DecoyBaitPing", kill = "RE_SV_DecoyKill" }
DECOY.RADIO = { lock = "RE_SV_DecoyRadio_Lock", imminent = "RE_SV_DecoyRadio_Imminent", incoming = "RE_SV_DecoyRadio_Incoming",
                hit = "RE_SV_DecoyRadio_Hit", brief = "RE_SV_DecoyRadio_Brief" }
DECOY.HIT_FLAG = "SV_DecoySpearHit"
local EV, RADIO = DECOY.EV, DECOY.RADIO

-- every unit of the round (the bait, its mark, each UAV and its mark, the launchers)
function DECOY.units()
    local c = cfg()
    local out = { tostring(c.bait_unit or "SV_Unit_DecoyBait"), tostring(c.bait_mark or "SV_Unit_DecoyBaitMark") }
    for k = 1, maxUavs() do out[#out + 1] = DECOY.uav(k); out[#out + 1] = DECOY.mark(k) end
    for s = 1, math.max(1, math.floor(num(c.spears, 4))) do out[#out + 1] = DECOY.spear(s) end
    return out
end
for _, u in ipairs(DECOY.units()) do DECOY.unitSet[u] = true end
function DECOY.isUnit(u) return type(u) == "string" and DECOY.unitSet[u] == true end
-- each object SV_Spawn makes for them recorded by sv_rounds.lua's feed (SPC.CLEAN_OBJ[unit]: the host's and a joiner's
-- copies alike), so the bodies, pods and marks are found without a walk, and the specials' clean-up takes them down
if type(SPC) == "table" and type(SPC.cleanWatch) == "table" then
    for u in pairs(DECOY.unitSet) do SPC.cleanWatch[u] = true end
end
-- (sv_rounds.lua SPC.cleanUnitsOf("decoy")) the ones spawned in this level and still on the spawner's list here
function DECOY.cleanUnits()
    local out = {}
    for _, u in ipairs(DECOY.units()) do
        if SPC and SPC.seenUnits and SPC.seenUnits[u] then out[#out + 1] = u end
    end
    return out
end
-- (sv_rounds.lua SPC.cleanLabel) a unit's name in the log
function DECOY.label(u)
    if not DECOY.isUnit(u) then return nil end
    local c = cfg()
    local nm = tostring(c.name or "THE DECOY")
    if u == c.bait_unit then return nm .. "'s bait (" .. u .. ")" end
    if u == c.bait_mark then return nm .. "'s bait mark (" .. u .. ")" end
    local k = u:match("(%d+)$")
    if u:find(tostring(c.mark_prefix), 1, true) == 1 then return nm .. "'s mark " .. tostring(tonumber(k)) .. " (" .. u .. ")" end
    if u:find(tostring(c.spear_prefix), 1, true) == 1 then return nm .. "'s Spear launcher " .. tostring(k) .. " (" .. u .. ")" end
    return nm .. "'s UAV " .. tostring(tonumber(k)) .. " (" .. u .. ")"
end

---------------------------------------------------------------------------------------------------- objects
local function objs(unit) local l = SPC and SPC.CLEAN_OBJ and SPC.CLEAN_OBJ[unit]; return type(l) == "table" and l or {} end
local function shortName(o) local n = nameOf(o); return n:match("([^%.:]+)$") or n end
local function isPod(o) return shortName(o):lower():find("laser", 1, true) ~= nil end
local function health(o) local ok, h = pcall(function() return o.HealthInternal end); return (ok and type(h) == "number") and h or nil end
local function locOf(o)
    if not liveObj(o) then return nil end
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function velOf(o)
    if not liveObj(o) then return nil end
    local ok, v = pcall(function() local q = o:GetVelocity(); return { X = q.X, Y = q.Y, Z = q.Z } end)
    return ok and v or nil
end
-- the first live object of a unit: its body (not the laser pod), its pod, or anything (a mark)
local function firstOf(unit, want)
    for _, o in ipairs(objs(unit)) do
        if liveObj(o) then
            local pod = isPod(o)
            if want == "any" or (want == "pod") == pod then return o end
        end
    end
    return nil
end
-- rec (a UAV or the bait): its body and pod found once (kept with liveObj on every read, LEVEL_DROPS forgets them)
local function findParts(rec, unit)
    if not rec.bodySeen then
        local b = firstOf(unit, "body")
        if b then rec.body, rec.bodySeen, rec.bodyAddr = b, true, addrOf(b) end
    end
    if rec.pod == nil or not liveObj(rec.pod) then rec.pod = firstOf(unit, "pod") end
end
-- seen and now dead (health 0) or gone
local function bodyDown(rec)
    if not rec.bodySeen then return false end
    local b = rec.body
    if not (b and liveObj(b)) then return true end
    local h = health(b)
    return h ~= nil and h <= 0
end
-- a finished UAV's parts off (its laser pod, its mark): hidden, no collision, no lock-on, never killed (a copy's kill is
-- the host's; a pod or a mark isn't anyone's kill)
local function switchOff(o)
    if not liveObj(o) then return end
    local h = health(o)
    if h ~= nil and h <= 0 then return end
    for f, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }) do
        pcall(function() o[f] = v end)
    end
    pcall(function() o:SetActive(false, false, false) end)
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    pcall(function() o:SetActorTickEnabled(false) end)
end

-- (the host's or solo) an object taken down with no attacker, as sv_rounds.lua's clean-up does (mortal, no floor,
-- ModifyHealth, else ApplyDamage): nobody's kill, and a co-op host's "dn" takes every joiner's copy down with it
local function finishOff(o)
    if not liveObj(o) then return false end
    local h = health(o)
    if not h or h <= 0 then return false end
    pcall(function() o:SetIsInvincible(false) end)
    pcall(function() o.bIsInvincible = false end)
    pcall(function() o.MinHealth = 0.0 end)
    pcall(function() o:SetMinHealth(0.0) end)
    pcall(function() o:ModifyHealth(-(h / 10 + 1000), nil, true) end)
    local h1 = health(o)
    if h1 and h1 > 0 then
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if gs and valid(gs) then pcall(function() gs:ApplyDamage(o, 100000000.0, nil, nil, nil) end) end
        h1 = health(o)
    end
    return h1 ~= nil and h1 <= 0
end

local function fire(ev)
    if type(SV_Event) ~= "function" then return -5 end
    local ok, r = pcall(SV_Event, ev)
    return ok and r or -5
end

-- SV_Spawn of one of the round's units (pose: X, Y, Z cm and yaw, or the world data's place), its objects recorded
-- (spawningUnit: sv_rounds.lua's feed; the co-op host's spawn goes to every joiner, sv_coop.lua). A unit still on the
-- spawner's list from a run before (-3) is taken off it (SV_Recycle force 1) and spawned again.
local function spawnUnit(unit, p)
    if type(SV_Spawn) ~= "function" then return -5 end
    local function go()
        spawningUnit = unit
        local ok, r
        if p then ok, r = pcall(SV_Spawn, unit, p.X, p.Y, p.Z, p.yaw or 0) else ok, r = pcall(SV_Spawn, unit) end
        spawningUnit = nil
        return ok and r or -5
    end
    local r = go()
    if r == -3 and type(SV_Recycle) == "function" then
        crumb("decoy: SV_Recycle " .. unit .. " (still up from before)")
        local okR, rr = pcall(SV_Recycle, unit, 1)
        log(string.format("decoy: %s still on the spawner's list from before: taken off (SV_Recycle %s), spawned again", unit,
            okR and tostring(rr) or ("error " .. tostring(rr))))
        r = go()
    end
    return type(r) == "number" and r or -5
end
DECOY.spawnUnit = spawnUnit

---------------------------------------------------------------------------------------------------- the players
local function myPawn()
    if not liveObj(survivalPC) then return nil end
    local ok, p = pcall(function() return survivalPC.Pawn end)
    if ok and p ~= nil and liveObj(p) then return p end
    return nil
end
-- ((2026-11-07) the user, after a run ended on one 5% hit: "heavy damage") A judged Spear hit takes hit.damage_pct of
-- your MaxHealth (HealthInternal is x10, written as the STORE's repair does: ModifyHealth does nothing on the player,
-- tools/re/KILLS_HEALTH_DEATH.md 1); one that would leave nothing is RE_SV_DecoyKill (the game's own death) unless
-- hit.can_kill is false (then 1 HP left); damage_pct 100 or more: the kill as before. What it did, for the log.
function DECOY.hurtMe(c)
    c = c or cfg()
    local h = type(c.hit) == "table" and c.hit or {}
    local pct = num(h.damage_pct, 50)
    local pawn = myPawn()
    local function kill(why) return why .. ": " .. EV.kill .. " " .. errText(fire(EV.kill)) end
    if pct >= 100 then return kill("damage_pct " .. pct) end
    if not pawn then return kill("your plane not found") end
    local okH, hi = pcall(function() return pawn.HealthInternal end)
    local okM, mh = pcall(function() return pawn.MaxHealth end)
    if not (okH and okM and type(hi) == "number" and type(mh) == "number" and mh > 0) then return kill("your health unreadable") end
    local dmg = math.floor(mh * 10 * math.max(0, pct) / 100 + 0.5)
    local left = hi - dmg
    if left <= 0 then
        if h.can_kill ~= false then
            return kill(string.format("%.0f%% of your %.0f HP with %.0f HP left: lethal", pct, mh, hi / 10))
        end
        left = math.min(hi, 10)                             -- (can_kill false: 1 HP left)
    end
    local okW = pcall(function() pawn.HealthInternal = left end)
    return string.format("-%.0f HP (%.0f%% of your %.0f), %.0f HP left%s", (hi - left) / 10, pct, mh, left / 10,
        okW and "" or " (NOT written)")
end

-- every player this game knows of (sv_coop.lua COOP.players: you first; solo or the Offline edition, you alone):
-- { slot, obj, at, alive, down, onAirfield, fresh, isMe }
function DECOY.players()
    if COOP and type(COOP.players) == "function" then
        local ok, l = pcall(COOP.players)
        if ok and type(l) == "table" and #l > 0 then return l end
    end
    local pawn = myPawn()
    if not pawn then return {} end
    local okA, at = pcall(playerLocation)
    return { { slot = mySlot(), obj = pawn, addr = addrOf(pawn), at = okA and at or nil, alive = true, fresh = true, isMe = true } }
end
local function bySlot(players, slot)
    for _, e in ipairs(players or {}) do if e.slot == slot then return e end end
    return nil
end
local function myEntry(players)
    for _, e in ipairs(players or DECOY.players()) do if e.isMe then return e end end
    return nil
end
local function myHealth()
    local p = myPawn()
    return p and health(p) or nil
end
local function whoText(slot) return slot == mySlot() and "you" or ("player " .. (tonumber(slot) or 0) + 1) end

-- inside the safe circle round the runway (no spawns, no locks, no strikes there)
function DECOY.inSafe(at, c)
    c = c or cfg()
    if type(at) ~= "table" then return false end
    local sa = type(c.safe_at) == "table" and c.safe_at or {}
    return dist2(at, num(sa[1], AIRFIELD and AIRFIELD.X or 0), num(sa[2], AIRFIELD and AIRFIELD.Y or 0)) < num(c.safe_km, 5) * 100000
end
-- a player a UAV may lock: alive, not DOWN, in the mission, out of the safe circle and off the airfield
function DECOY.validTarget(e, c)
    c = c or cfg()
    return type(e) == "table" and type(e.at) == "table" and e.alive ~= false and not e.down and e.fresh ~= false
        and e.inLevel ~= false and not e.onAirfield and not DECOY.inSafe(e.at, c)
end
-- the valid player closest to pos, and how far (cm)
function DECOY.closest(pos, players, c)
    local best, bd = nil, nil
    for _, e in ipairs(players or {}) do
        if DECOY.validTarget(e, c) then
            local d = dist3(pos, e.at)
            if not bd or d < bd then best, bd = e, d end
        end
    end
    return best, bd
end
-- UAVs up (their positions) within near_km of at
function DECOY.nearCount(at, ups, c)
    c = c or cfg()
    local n, r = 0, num(c.near_km, 8) * 100000
    for _, q in ipairs(ups or {}) do if dist3(at, q) <= r then n = n + 1 end end
    return n
end
-- Survival's combat zone (Mission 22's: 80 x 80 km round (-707336, -261895); tools/re/COMONA_MAP.md)
local ZONE = { X = -707336, Y = -261895, half = 4000000 }
-- a spot for a new UAV round player position `you`: spawn_km from it at any bearing, within alt_m of its height
-- (min_alt_m to max_alt_m), out of the safe circle, edge_km inside the zone, gap_km from every UAV up (ups); its yaw
-- facing the player. nil when 12 tries found none. rnd: math.random's kind (the test's own)
function DECOY.spawnSpot(you, ups, c, rnd)
    c, rnd = c or cfg(), rnd or math.random
    local sk = type(c.spawn_km) == "table" and c.spawn_km or {}
    local lo, hi = num(sk[1], 2.5), num(sk[2], 5)
    if hi < lo then lo, hi = hi, lo end
    local edge = math.max(0, ZONE.half - num(c.edge_km, 2) * 100000)
    local gap = num(c.gap_km, 1.5) * 100000
    local zlo, zhi = num(c.min_alt_m, 600) * 100, num(c.max_alt_m, 9000) * 100
    for _ = 1, 12 do
        local b = rnd() * 2 * math.pi
        local d = (lo + rnd() * (hi - lo)) * 100000
        local z = (you.Z or 0) + (rnd() * 2 - 1) * num(c.alt_m, 1000) * 100
        local p = { X = you.X + math.cos(b) * d, Y = you.Y + math.sin(b) * d, Z = math.max(zlo, math.min(zhi, z)) }
        local ok = not DECOY.inSafe(p, c) and math.abs(p.X - ZONE.X) <= edge and math.abs(p.Y - ZONE.Y) <= edge
        if ok then for _, q in ipairs(ups or {}) do if dist3(p, q) < gap then ok = false; break end end end
        if ok then
            p.yaw = math.deg(math.atan(you.Y - p.Y, you.X - p.X))
            return p
        end
    end
    return nil
end
-- ((2026-11-07) the user: "Tonitrus spears should also be able to miss the players sometimes") a judged strike's chance
-- to hit: hit.chance on your held line, falling to 0 at dodge_m off it (a hard break buys odds, never a sure escape)
function DECOY.hitChance(offM)
    local h = cfg().hit or {}
    local ch, dodge = math.max(0, math.min(1, num(h.chance, 0.6))), math.max(1, num(h.dodge_m, 200))
    if type(offM) ~= "number" then return 0 end
    return math.max(0, ch * (1 - offM / dodge))
end
-- where the Spear should land: at + vel x fall_s (cm, cm/s)
function DECOY.leadPoint(at, vel, fall)
    if type(at) ~= "table" then return nil end
    vel, fall = vel or { X = 0, Y = 0, Z = 0 }, num(fall, 0)
    return { X = at.X + num(vel.X, 0) * fall, Y = at.Y + num(vel.Y, 0) * fall, Z = at.Z + num(vel.Z, 0) * fall }
end

---------------------------------------------------------------------------------------------------- the radio
-- each game's own lines (KEEP_EVENTS): gap_s between any two, each its own cooldown (radio.<id>_s), none while you're down
-- at the airfield; force: the trap's brief, through both
function DECOY.say(id, now, force)
    local rc = cfg().radio or {}
    local ev = RADIO[id]
    if rc.enabled == false or not ev or type(SV_Event) ~= "function" then return false end
    local Q = DECOY.Q
    now = now or clockNow()
    if not force then
        if Q.at and now - Q.at < num(rc.gap_s, 2.5) and now >= Q.at then return false end
        local last = Q.by[id]
        if last and now - last < num(rc[id .. "_s"], 0) and now >= last then return false end
    end
    local okA, onAf = pcall(playerOnAirfield)
    if okA and onAf == true and not force then return false end
    local r = fire(ev)
    Q.at, Q.by[id] = now, now
    Q.n[id] = (Q.n[id] or 0) + 1
    if Q.n[id] <= 3 or Q.n[id] % 10 == 0 then
        log(string.format("decoy: radio %s (%s %s; %d this run)", id, ev, errText(r), Q.n[id]))
    end
    return r == 1
end

---------------------------------------------------------------------------------------------------- the laser pods
-- a pod's search and designate phases (instance values: the stock pod's class is left as shipped): its search
-- lock_delay_s, its hold designate_s (past the strike; the bait's past its whole wait, hold); the first pod's values
-- logged once a session
-- (the bait's laser holds through its whole wait: its clock + 2 min, an hour with no clock)
local function baitHold() local t = num(cfg().bait_timeout_s, 240); return t > 0 and t + 120 or 3600 end
local function tunePod(pod, hold)
    if not (pod and liveObj(pod)) then return end
    local c = cfg()
    local want = { SearchPhaseTime = num(c.lock_delay_s, 1.5), DesignatePhaseTime = math.max(num(c.designate_s, 40), num(hold, 0)) }
    local parts = {}
    for f, v in pairs(want) do
        local okR, was = pcall(function() return pod[f] end)
        local okW = pcall(function() pod[f] = v end)
        parts[#parts + 1] = string.format("%s %s -> %s", f, okR and tostring(was) or "?", okW and tostring(v) or "NOT set")
    end
    table.sort(parts)
    said("pod", "decoy: a laser pod's phases on its instance (" .. shortName(pod) .. "): " .. table.concat(parts, ", "))
end

---------------------------------------------------------------------------------------------------- the marks
-- (every game) the mark kept on the plane it marks: K2_AttachToActor first; if it didn't hold (the mark more than
-- 150 m off the plane at the next look) every mark is moved onto its plane each tick instead (DECOY.markMode, once a
-- level, logged which works); if a move doesn't hold either (the mark 150 m or more from where it was put, a look on),
-- a mark on this game's own plane is put there by the build's teleport each tick (RE_SV_DecoyMarkOnMe_<nn>, Mission
-- 22's onto "Player": each game's own, kept local in co-op), one on another player's plane still moved
local function detach(g)
    if g.mode == "attach" and g.mark and liveObj(g.mark) then
        pcall(function() g.mark:K2_DetachFromActor(1, 1, 1) end)
    end
end
local function moveMark(g, plane)
    local at = locOf(plane)
    if not (at and g.mark and liveObj(g.mark)) then return false end
    local ok = pcall(function() g.mark:K2_SetActorLocation(at, false, {}, true) end)
    g.movedTo = ok and at or nil
    return ok
end
local function teleportMark(g)
    local r = fire(evMarkOnMe(g.k))
    if not g.tpSaid then
        g.tpSaid = true
        log(string.format("decoy: UAV %d's mark onto your plane by the build's teleport (%s %s), each tick", g.k, evMarkOnMe(g.k), errText(r)))
    end
    return r == 1
end
-- (DECOY.markMode "move", until a move is known to hold) a look on from a move: the mark where it was put, or the game
-- put it back
local function checkMove(g)
    if DECOY.moveHeld or DECOY.markMode ~= "move" or not g.movedTo then return end
    local a = locOf(g.mark)
    if not a then return end
    local off = dist3(a, g.movedTo) / 100
    if off < 150 then
        DECOY.moveHeld = true
        log(string.format("decoy: marks moved onto their planes each tick hold (%.0f m from where one was put, a look on)", off))
    else
        DECOY.markMode = "teleport"
        log(string.format("decoy: a mark moved onto its plane didn't hold either (%.0f m from where it was put, a look on): marks "
            .. "on your plane by the build's teleport (RE_SV_DecoyMarkOnMe_<nn>) from now on, other players' still moved", off))
    end
end
local function placeMark(g, mark, plane)
    g.mark, g.plane, g.planeAddr = mark, plane, addrOf(plane)
    if DECOY.markMode == "teleport" then             -- (neither holds: moved, and the build's teleport for your own)
        g.mode = "move"
        moveMark(g, plane)
        if g.slot == mySlot() then teleportMark(g) end
        return
    end
    if DECOY.markMode == nil then                   -- (not known yet: the mark put 1 km over the plane first, so an attach
        local at = locOf(plane)                     -- that doesn't hold shows at the check, wherever the mark came)
        if at then pcall(function() mark:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z + 100000 }, false, {}, true) end) end
    end
    if DECOY.markMode ~= "move" then
        local ok = pcall(function() mark:K2_AttachToActor(plane, FName("None"), 2, 2, 1, false) end)
        if ok then g.mode, g.checkAt = "attach", os.clock() + 0.25; return end
        if not DECOY.markMode then
            DECOY.markMode = "move"
            log("decoy: marks follow their planes by a move each tick (K2_AttachToActor failed)")
        end
    end
    g.mode = "move"
    moveMark(g, plane)
end
local function followMark(g, players)
    if not (g.mark and liveObj(g.mark)) then return end
    local e = bySlot(players, g.slot)
    local plane = e and e.obj
    if not (plane and liveObj(plane)) then return end
    if addrOf(plane) ~= g.planeAddr then            -- (their plane changed: a new sortie, SECOND CHANCE)
        detach(g)
        placeMark(g, g.mark, plane)
        return
    end
    if g.mode == "attach" and (DECOY.markMode == "move" or DECOY.markMode == "teleport") then   -- (another mark found the
        detach(g)                                                                                -- attach doesn't hold)
        g.mode = "move"
    end
    if g.mode == "move" then
        checkMove(g)
        if DECOY.markMode == "teleport" and g.slot == mySlot() then teleportMark(g) else moveMark(g, plane) end
        return
    end
    if os.clock() < (g.checkAt or 0) then return end
    g.checkAt = os.clock() + 2
    local a, b = locOf(g.mark), locOf(plane)
    local off = (a and b) and dist3(a, b) / 100 or nil
    if DECOY.markMode == nil and off then
        if off <= 150 then
            DECOY.markMode = "attach"
            log(string.format("decoy: marks follow their planes attached (K2_AttachToActor held: %.0f m off a moment on)", off))
        else
            DECOY.markMode = "move"
            log(string.format("decoy: marks follow their planes by a move each tick (K2_AttachToActor didn't hold: %.0f m off)", off))
            detach(g)
            g.mode = "move"
            moveMark(g, plane)
            return
        end
    end
    local okP, par = pcall(function() return g.mark:GetAttachParentActor() end)
    if not (okP and par ~= nil and addrOf(par) == g.planeAddr) then placeMark(g, g.mark, plane) end   -- (dropped: again)
end

---------------------------------------------------------------------------------------------------- locks (every game)
-- DECOY.G[k]: UAV k's lock as this game has it { seq, slot, at, armed, laser, mark, plane, offAt }; DECOY.R[k]: a lock on
-- this game's player, its 8 s { seq, at, strikeAt, state = count | struck | cancelled, body }. seq: the host's count, so a
-- repeat or an older lock is never taken.
local function dropLock(k, why, quiet)
    local g = DECOY.G[k]
    if g then
        if g.laser then fire(evLaserOff(k)) end
        detach(g)
        DECOY.G[k] = nil
    end
    local r = DECOY.R[k]
    if r and r.state == "count" then
        r.state = "cancelled"
        DECOY.st.cancelled = DECOY.st.cancelled + 1
        if not quiet then
            log(string.format("decoy: UAV %d's lock on you cancelled %.1f s in (%s): no strike", k, clockNow() - (r.at or clockNow()), tostring(why)))
        end
    end
end
function DECOY.applyLock(k, slot, seq, now)
    local g = DECOY.G[k]
    if g and g.seq and seq <= g.seq then return false end
    if g then dropLock(k, "a new lock", true) end
    DECOY.G[k] = { k = k, seq = seq, slot = slot, at = now or clockNow(), armed = false }
    return true
end
function DECOY.applyCancel(k, why) dropLock(k, why) end
local function startRunner(k, g, now)
    local c = cfg()
    DECOY.R[k] = { k = k, seq = g.seq, at = now, strikeAt = now + num(c.lock_delay_s, 1.5) + num(c.lock_s, 8), state = "count",
                   body = g.body, bodyAddr = g.body and addrOf(g.body) }
    DECOY.st.locks = DECOY.st.locks + 1
    DECOY.say("lock", now)
    log(string.format("decoy: UAV %d locks you: the Spear in %.1f s unless it's down (lock %d this run)", k,
        num(c.lock_delay_s, 1.5) + num(c.lock_s, 8), DECOY.st.locks))
end
-- a lock's laser on, once this game has the UAV, its mark and the plane it marks (a joiner's copies may come a moment
-- after the host's "dk"): arm_wait_s at most
local function armLock(k, g, now, players)
    local body, mark = firstOf(DECOY.uav(k), "body"), firstOf(DECOY.mark(k), "any")
    local e = bySlot(players, g.slot)
    local plane = e and e.obj
    if not (body and mark and plane and liveObj(plane)) then return false end
    g.body = body
    placeMark(g, mark, plane)
    tunePod(firstOf(DECOY.uav(k), "pod"))
    local r = fire(evLaserOn(k))
    g.armed, g.laser, g.armAt = true, r == 1, now
    g.offAt = now + num(cfg().lock_delay_s, 1.5) + num(cfg().lock_s, 8) + 1
    log(string.format("decoy: UAV %d's laser on %s (%s %s), its mark %s", k, whoText(g.slot), evLaserOn(k), errText(r),
        g.mode == "attach" and "attached to the plane" or "moved onto the plane"))
    if g.slot == mySlot() then startRunner(k, g, now) end
    return true
end
local function locksTick(now, players)
    local wait = num(cfg().arm_wait_s, 10)
    for k, g in pairs(DECOY.G) do
        if not g.armed then
            if now - g.at > wait or now < g.at - 60 then
                log(string.format("decoy: UAV %d's lock on %s not put on here in %.0f s (its UAV, its mark or that plane isn't "
                    .. "here): dropped", k, whoText(g.slot), wait))
                DECOY.G[k] = nil
            else
                armLock(k, g, now, players)
            end
        elseif now >= (g.offAt or now) + 5 or now < g.at - 60 then   -- (its call long past: the mark let go, the next
            dropLock(k, "its call is past", true)                    -- lock a fresh one)
        else
            followMark(g, players)
            if g.laser and now >= (g.offAt or now) then
                fire(evLaserOff(k))
                g.laser = false
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- the Spear (this game's player)
-- the rods (Mission 19's BP_RodsFromGod, ALiveMeteoriteImpact) as they're made (the callback only keeps them: the tick
-- reads them on the game thread)
pcall(NotifyOnNewObject, "/Script/Live.LiveMeteoriteImpact", function(o)
    local q = DECOY.rodNew
    if #q < 32 then q[#q + 1] = o end
end)
-- ((2026-11-07) Alyssa's test of 0.74.0: every rod fell 1.0-2.3 s after its call, not 3 s, so the 3 s lead put it
-- 1-1.5 km ahead of her; lead.learn: the fall measured at each impact, the median of the last learn_n (min_s .. max_s))
DECOY.falls = {}
function DECOY.fallS()
    local ld = cfg().lead or {}
    local base = num(ld.fall_s, 1.6)
    if ld.learn == false or #DECOY.falls < 2 then return base end
    local t = {}
    for i, v in ipairs(DECOY.falls) do t[i] = v end
    table.sort(t)
    return math.max(num(ld.min_s, 0.8), math.min(num(ld.max_s, 3.0), t[math.floor((#t + 1) / 2)]))
end
-- ((2026-11-07) the clouds: each rod opens a "blast" in the sky's clouds as it lands (its BlastEffectInfo, type Impact,
-- at 115.6 km) with the sky's ExplosionEffect, which Comona's sky leaves unset: the clouds warped back and forth with
-- every strike (Alyssa's test; the user: "in a previous mod we built, this happened and we were able to fix it"). That
-- mod's fix (the user's own work: AGENTS.md's exception): the blast at the clouds' height and the sky's
-- ExplosionEffect set as Mission 30's big one, a little wider, on the level's sky, its blended sky and its time-of-day
-- key frames, again every every_s while the Spear is about (the blending copies them back); every value put back as it
-- was once it's quiet (restore_after_s), at a run's start over; never on a level torn down (dropped, LEVEL_DROPS).
-- clouds.mode "off": no blast at all (Type Disable on each rod); "stock": left alone.
DECOY.cl = { orig = {}, at = -100 }
local BLAST_FIELDS = { radius_km = "RadiusInKm", weld_km = "WeldRadiusInKm", fade_km = "FadeDistanceInKm", whirl = "Whirl",
                       push = "Push", cirrus_fade_km = "CirrusExtraFadeDistanceInKm", expand_s = "ExpansionDuration",
                       expand_p1 = "ExpansiondParam1", expand_p2 = "ExpansiondParam2", contract_s = "ContractionDuration",
                       contract_p1 = "ContractionParam1" }
local function ccfg() return cfg().clouds or {} end
local function skyActor(now)
    local okV, V = pcall(function() return SKY and SKY.viewCached and SKY.viewCached(now) end)
    local a = okV and type(V) == "table" and V.actor or nil
    return (a and liveObj(a)) and a or nil
end
local function skyAssets(a)
    local list = {}
    local function add(o, label) if o and liveObj(o) then list[#list + 1] = { o = o, label = label } end end
    local okS, sky = pcall(function() return a.CloudlySkyParamsAsset end)
    if okS then add(sky, "sky") end
    local okB, bl = pcall(function() return a.CloudlyInterpolatedSkyParamsAsset end)
    if okB then add(bl, "blended sky") end
    local okQ, seq = pcall(function() return a.CloudlySequencerAsset end)
    if okQ and seq and liveObj(seq) then
        pcall(function()
            seq.KeyFrames:ForEach(function(i, e)
                local okK, sp = pcall(function() return e:get().SkyParams end)
                if okK then add(sp, "key frame " .. tostring(i)) end
            end)
        end)
    end
    return list
end
-- the blast's height (m): height_m, else midway between the sky's two lowest cloud layers
function DECOY.cloudHeightM(a)
    local c = ccfg()
    if tonumber(c.height_m) then return tonumber(c.height_m) end
    if DECOY.cl.heightM then return DECOY.cl.heightM end
    local hs = {}
    local okS, sky = pcall(function() return a and a.CloudlySkyParamsAsset end)
    if okS and sky then
        for i = 0, 2 do
            local ok, h, en = pcall(function() local l = sky.Data["CloudLayer" .. i]; return tonumber(l.StartHeightInKm), l.Enable end)
            if ok and h and (en == nil or en == true or i == 0) then hs[#hs + 1] = h end
        end
    end
    table.sort(hs)
    if #hs >= 2 then DECOY.cl.heightM = (hs[1] + hs[2]) * 500 elseif #hs == 1 then DECOY.cl.heightM = hs[1] * 1000 + 500 end
    if DECOY.cl.heightM then
        said("cloud height", string.format("decoy: the clouds' layers start at %s km: the Spear's blast opens them at %.0f m",
            table.concat(hs, ", "), DECOY.cl.heightM))
    end
    return DECOY.cl.heightM or 2000
end
local function rodBlast(o, a)
    local mode = ccfg().mode or "hole"
    if mode == "stock" or not liveObj(o) then return end
    local ok = pcall(function()
        local b = o.BlastEffectInfo
        if mode == "off" then
            if tonumber(b.Type) ~= 0 then b.Type = 0 end
        else
            local hm = DECOY.cloudHeightM(a)
            if tonumber(b.Type) ~= 1 then b.Type = 1 end
            if math.abs((tonumber(b.HeightInMeter) or -1) - hm) > 0.5 then b.HeightInMeter = hm end
            if (tonumber(b.HeightLimitMaxInMeters) or 0) < 500000 then b.HeightLimitMaxInMeters = 500000 end
        end
    end)
    local okR, ty, h = pcall(function() return tonumber(o.BlastEffectInfo.Type), tonumber(o.BlastEffectInfo.HeightInMeter) end)
    said("rod blast " .. mode, string.format("decoy: the Spear's rods' cloud blast %s: %s (reads type %s, at %s m; %s)",
        mode == "off" and "off" or "at the clouds", ok and "set" or "NOT set", okR and tostring(ty) or "?", okR and tostring(h) or "?",
        shortName(o)))
end
-- the sky's ExplosionEffect as wanted, every original kept once (by the asset's address and the field)
function DECOY.cloudsApply(now)
    local c = ccfg()
    if (c.mode or "hole") ~= "hole" then return 0 end
    local a = skyActor(now)
    if not a then said("no sky", "decoy: no sky actor found: the cloud blast not set"); return 0 end
    DECOY.cl.at = now
    local good, bad, n = 0, 0, 0
    for _, it in ipairs(skyAssets(a)) do
        local okE, st = pcall(function() return it.o.Data.ExplosionEffect end)
        if okE and st then
            n = n + 1
            local ad = addrOf(it.o)
            local g0, b0 = good, bad
            for key, field in pairs(BLAST_FIELDS) do
                local want = tonumber(c[key])
                if want then
                    local okR, cur = pcall(function() return st[field] end)
                    if okR and type(cur) == "number" then
                        local id = tostring(ad) .. "|" .. field
                        if DECOY.cl.orig[id] == nil then DECOY.cl.orig[id] = { o = it.o, addr = ad, field = field, v = cur } end
                        if math.abs(cur - want) > 1e-4 then pcall(function() st[field] = want end) end
                        local okB, back = pcall(function() return st[field] end)
                        if okB and type(back) == "number" and math.abs(back - want) < 1e-4 then good = good + 1 else bad = bad + 1 end
                    end
                end
            end
            said("blast " .. tostring(ad), string.format("decoy: the %s's cloud blast (%s) set for the Spear: %d fields as wanted%s",
                it.label, shortName(it.o), good - g0, bad > b0 and string.format(", %d would not change", bad - b0) or ""))
        end
    end
    if n == 0 then said("no blast", "decoy: the sky has no ExplosionEffect the Spear's blast could use") end
    return good
end
-- every value the clouds' fix changed put back (only objects still alive: a level torn down drops them, LEVEL_DROPS)
function DECOY.cloudsRestore(why)
    local back, gone = 0, 0
    for id, e in pairs(DECOY.cl.orig) do
        if e.o and liveObj(e.o) and addrOf(e.o) == e.addr then
            pcall(function() e.o.Data.ExplosionEffect[e.field] = e.v end)
            back = back + 1
        else
            gone = gone + 1
        end
        DECOY.cl.orig[id] = nil
    end
    if back + gone > 0 then
        log(string.format("decoy: the sky's cloud blast put back (%s): %d values%s", tostring(why), back,
            gone > 0 and string.format(", %d of objects gone", gone) or ""))
    end
end
-- ((2026-11-07) the Spear's blast: Mission 25's cutscene Rods-from-God explosion (the stock Niagara systems
-- /Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_*, the user's texture list's: "can you add that into the Tonitrus Spear
-- that we're using in this build"), spawned where a strike lands: blast.air (the explosion and its shock wave) on a
-- judged strike at the player's height, blast.ground (with the sand smoke and the ring) where a rod lands on the airfield.
-- Each game's own (visual only), auto-destroyed when done.
DECOY.bl = { sys = {} }
local function blastSys(path)
    local full = path .. "." .. (path:match("[^/]+$") or "")
    local o = DECOY.bl.sys[full]
    if o ~= nil and liveObj(o) then return o end
    local okL, lo, why = pcall(loadObject, full)
    o = okL and lo or nil
    DECOY.bl.sys[full] = o
    if not o then said("blast " .. full, "decoy: the Spear's blast " .. full .. " didn't load: " .. tostring(okL and why or lo)) end
    return o
end
function DECOY.blast(at, kind)
    local b = cfg().blast or {}
    if b.enabled == false or not at then return 0 end
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (lib and valid(lib) and liveObj(survivalPC)) then return 0 end
    local s, n = num(b.scale, 1), 0
    for _, path in ipairs((kind == "ground" and b.ground) or b.air or {}) do
        local sys = blastSys(path)
        if sys and pcall(function()
            lib:SpawnSystemAtLocation(survivalPC, sys, { X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = 0, Roll = 0 },
                { X = s, Y = s, Z = s }, true, true, 0, true)
        end) then n = n + 1 end
    end
    said("blast said " .. tostring(kind), string.format("decoy: the Spear's %s blast (Mission 25's cutscene explosion): %d of %d systems spawned",
        tostring(kind), n, #((kind == "ground" and b.ground) or b.air or {})))
    return n
end
-- the bait's Spear on the airfield (its laser on the mark there: the game's own strike once it's down), which Survival's
-- airfield never counted: from the bait's end, every rod made after it is watched; one that stops (lands) within
-- bait_strike.within_km of the mark, or none seen landing wait_s on after a new rod showed, takes bait_strike.damage off
-- the airfield (the host's or solo: AF is the host's) and plays the ground blast there (every game)
function DECOY.baitStrikeStart(now)
    local c = cfg().bait_strike or {}
    if c.enabled == false then return end
    local m = firstOf(cfg().bait_mark)
    local at = m and locOf(m)
    local sa = cfg().safe_at or { 1610476, -436142 }
    local known = {}
    for _, o in ipairs(DECOY.rods) do if liveObj(o) then known[addrOf(o)] = true end end
    DECOY.bs = { at = now, mark = at or { X = sa[1], Y = sa[2], Z = 500 }, known = known, seen = {}, untilAt = now + num(c.wait_s, 8) }
    log(string.format("decoy: the bait's Spear on the airfield watched (its mark at %.1f, %.1f km; %d rods already made)",
        DECOY.bs.mark.X / 100000, DECOY.bs.mark.Y / 100000, (function() local k = 0; for _ in pairs(known) do k = k + 1 end; return k end)()))
end
local function baitStrikeLand(now, at, how)
    local c = cfg().bait_strike or {}
    local B = DECOY.bs
    DECOY.bs = nil
    local dmg, applied = math.floor(num(c.damage, 40)), false
    if not isClient() and CFG.airfield.enabled and AF and not AF.down and AF.bomb then
        AF.bomb = AF.bomb + dmg
        applied = true
    end
    DECOY.blast({ X = at.X, Y = at.Y, Z = math.max(500, at.Z or 500) }, "ground")
    if applied then hudCallout(CFG.hud.text.dc_af_hit or "THE AIRFIELD IS HIT", CFG.hud.text.dc_af_hit_sub or "A TONITRUS SPEAR STRIKE") end
    log(string.format("decoy: the bait's Spear landed on the airfield (%s) %.1f s after the bait's end, %.0f m from its mark: %s",
        how, now - B.at, dist2(at, B.mark.X, B.mark.Y) / 100, applied and string.format("-%d airfield", dmg)
            or (isClient() and "the host's airfield takes the damage" or "the airfield not damaged (off or down)")))
end
local function baitStrikeTick(now)
    local B = DECOY.bs
    if not B then return end
    local c = cfg().bait_strike or {}
    local within = num(c.within_km, 2.5) * 100000
    for _, o in ipairs(DECOY.rods) do
        local a = liveObj(o) and addrOf(o)
        if a and not B.known[a] then
            local at = locOf(o)
            local e = B.seen[a]
            if at then
                if not e then
                    B.seen[a] = { at = at, t = now, moved = false }
                    B.newAt = B.newAt or now
                elseif dist3(at, e.at) < 100 then             -- (stopped: landed; its first place not a pooled one's)
                    if e.moved or at.Z < 500000 then
                        if dist2(at, B.mark.X, B.mark.Y) <= within then return baitStrikeLand(now, at, "a rod stopped there") end
                        B.known[a] = true                     -- (it landed elsewhere: not the airfield's)
                    end
                else
                    e.at, e.t, e.moved = at, now, true
                end
            end
        end
    end
    if B.newAt and now >= B.newAt + num(c.wait_s, 8) then return baitStrikeLand(now, B.mark, "none seen landing: at its mark") end
    if now >= B.untilAt + 10 then
        log("decoy: no Spear on the airfield seen after the bait's end")
        DECOY.bs = nil
    end
end
-- ((2026-11-07) the height: the stock rod has no HeightLimitAreas, so it ends at sea level whatever its target's height
-- (her plane at 4-7 km: every rod fell kilometres below her). A rod that has an area gets it at the target's height
-- (min = max = it) before each strike; an empty array is never grown from Lua (UE4SS can't add an element safely):
-- then the hit is judged (hit.judge, watchTick)
local function rodArea(o, zm)
    if not liveObj(o) then return false, "gone" end
    local okN, n = pcall(function() return o.HeightLimitAreas:GetArrayNum() end)
    if not okN then return false, "no HeightLimitAreas" end
    if (tonumber(n) or 0) < 1 then return false, "empty (the stock rod's)" end
    pcall(function() local el = o.HeightLimitAreas[1]; el.HeightLimitRangeMinInMeters = zm - 1; el.HeightLimitRangeMaxInMeters = zm + 1 end)
    local okR, mn, mx = pcall(function()
        local el = o.HeightLimitAreas[1]
        return tonumber(el.HeightLimitRangeMinInMeters), tonumber(el.HeightLimitRangeMaxInMeters)
    end)
    if okR and mn and mx and math.abs(mn - (zm - 1)) < 0.05 and math.abs(mx - (zm + 1)) < 0.05 then return true end
    return false, "reads back " .. tostring(mn) .. " / " .. tostring(mx)
end
local function readNum(o, k) local ok, v = pcall(function() return o[k] end); return ok and tostring(v) or "?" end
-- each rod led by the fall (lead: its PredictionTime on the instance, the fall learnt; the stock rod's is 0, no lead),
-- its cloud blast set, its height area at zm (m) when it has one; pooled ones again before each strike
local function leadRod(o, zm)
    if not liveObj(o) then return end
    rodBlast(o, skyActor(clockNow()))
    if zm then
        local okA, why = rodArea(o, zm)
        said("area " .. tostring(okA), string.format("decoy: the Spear's rod's height area %s (%s)",
            okA and string.format("set to %.0f m", zm) or ("NOT set: " .. tostring(why) .. "; the hit is judged by Lua"), shortName(o)))
    end
    if not DECOY.vlSaid then                           -- (for the next test: where the rods come from, what they hurt)
        DECOY.vlSaid = true
        local okL, use, l = pcall(function() return o.bUseVirtualLauncherLocation, o.VirtualLauncherLocation end)
        log(string.format("decoy: the Spear's rod: virtual launcher %s at %s; damage radius %s, strike %s %%, graze %s %%",
            okL and tostring(use) or "?", (okL and l) and string.format("(%.1f, %.1f, %.1f) km", (l.X or 0) / 100000, (l.Y or 0) / 100000,
            (l.Z or 0) / 100000) or "?", readNum(o, "DamageRadius"), readNum(o, "StrikeRadiusPercentage"), readNum(o, "GrazeRadiusPercentage")))
    end
    local ld = cfg().lead or {}
    if ld.enabled == false then return end
    local want = DECOY.fallS()
    local okR, was = pcall(function() return o.PredictionTime end)
    if okR and type(was) == "number" and math.abs(was - want) < 0.01 then return end
    local okW = pcall(function() o.PredictionTime = want end)
    said("lead " .. string.format("%.1f", want), string.format("decoy: the Spear's rods led by the fall: PredictionTime %s -> %s s (%s, an instance)",
        okR and tostring(was) or "?", okW and string.format("%.2f", want) or "NOT set", shortName(o)))
end
local function rodsTick()
    local q = DECOY.rodNew
    if #q > 0 then
        DECOY.rodNew = {}
        for _, o in ipairs(q) do
            if liveObj(o) and shortName(o):find("RodsFromGod", 1, true) then
                leadRod(o)
                local a, keep = addrOf(o), {}
                for _, x in ipairs(DECOY.rods) do if liveObj(x) and addrOf(x) ~= a then keep[#keep + 1] = x end end
                if #keep >= 16 then table.remove(keep, 1) end
                keep[#keep + 1] = o
                DECOY.rods = keep
            end
        end
    end
end
local function nextSpear()
    local n = math.max(1, math.floor(num(cfg().spears, 4)))
    DECOY.spearI = ((DECOY.spearI or 0) % n) + 1
    return DECOY.spearI
end
-- the Spear onto this game's player (k: the UAV whose lock it is, 0 for the test; s: a launcher, else the next in turn)
function DECOY.strike(k, r, now, s)
    local c = cfg()
    r.state, r.struckAt = "struck", now
    DECOY.st.struck = DECOY.st.struck + 1
    local players = DECOY.players()
    local me = myEntry(players)
    local pawn = me and me.obj
    local at, vel, hp0 = me and me.at, velOf(pawn), myHealth()
    local fallS = DECOY.fallS()
    local zm = at and (at.Z + ((vel and vel.Z) or 0) * fallS) / 100 or nil
    for _, o in ipairs(DECOY.rods) do leadRod(o, zm) end
    pcall(DECOY.cloudsApply, now)
    local f = (type(svFlags) == "function" and svFlags()) or {}
    local n0 = tonumber(f[DECOY.HIT_FLAG]) or 0
    local tries, res, ev = {}, -5, nil
    local first = s or nextSpear()
    local n = math.max(1, math.floor(num(c.spears, 4)))
    for i = 0, n - 1 do                               -- (a launcher that refuses: the next one)
        local x = ((first - 1 + i) % n) + 1
        ev = evSpear(x)
        res = fire(ev)
        tries[#tries + 1] = ev .. " " .. errText(res)
        if res == 1 or s then break end
    end
    local ld = c.lead or {}
    local aim = (ld.enabled ~= false and at) and DECOY.leadPoint(at, vel, fallS) or at
    local speed = vel and math.sqrt(vel.X ^ 2 + vel.Y ^ 2 + vel.Z ^ 2) / 100 or nil
    log(string.format("decoy: the Spear called on you (%s): %s; you at %s, %s; aimed %s",
        k > 0 and string.format("UAV %d's lock, %.1f s", k, now - (r.at or now)) or "the test key", table.concat(tries, ", "),
        at and string.format("(%.1f, %.1f) km, alt %.1f km", at.X / 100000, at.Y / 100000, at.Z / 100000) or "?",
        speed and string.format("%.0f m/s", speed) or "speed ?",
        (aim and at and aim ~= at) and string.format("%.0f m ahead of you (the rod's own lead, %.1f s)", dist3(aim, at) / 100, fallS)
            or "at you (no lead)"))
    if res == 1 then DECOY.say("incoming", now) end
    DECOY.W[#DECOY.W + 1] = { k = k, at = now, n0 = n0, hp0 = hp0, untilAt = now + num(c.impact_wait_s, 8), trace = r.trace,
                             fired = res == 1, pos0 = at, vel0 = vel }
    return res
end
local function runnersTick(now, players)
    local c = cfg()
    local soonest = nil
    local me = myEntry(players)
    local meDown = (DOWN and DOWN.me and DOWN.me() == true) or (me ~= nil and me.alive == false)
    for k, r in pairs(DECOY.R) do
        if r.state == "count" then
            local body = r.body
            local h = (body and liveObj(body)) and health(body) or nil
            local down = not (body and liveObj(body)) or (h ~= nil and h <= 0)
            local sent = not down and isClient() and COOP.killSent and r.bodyAddr and COOP.killSent(r.bodyAddr) == true
            if down or sent then
                r.state = "cancelled"
                DECOY.st.cancelled = DECOY.st.cancelled + 1
                log(string.format("decoy: UAV %d %s %.1f s into its lock on you: strike cancelled", k,
                    sent and "taken down by your hit (the host's kill to come)" or "down", now - r.at))
                local g = DECOY.G[k]
                if g and g.laser then fire(evLaserOff(k)); g.laser = false end
            elseif meDown then
                r.state = "cancelled"
                log(string.format("decoy: UAV %d's lock on you dropped: you're down", k))
            elseif now >= r.strikeAt then
                if me and me.at and DECOY.inSafe(me.at, c) then
                    r.state = "cancelled"
                    log(string.format("decoy: UAV %d's strike not called: you're inside the safe circle", k))
                else
                    DECOY.strike(k, r, now)
                end
            elseif not soonest or r.strikeAt < soonest.strikeAt then
                soonest = r
            end
        end
        if r.state ~= "count" and now - (r.struckAt or r.at) > 30 then DECOY.R[k] = nil end
    end
    if soonest and not soonest.imminentSaid and now >= soonest.strikeAt - num(c.imminent_s, 3) then
        soonest.imminentSaid = true
        DECOY.say("imminent", now)
    end
end
-- each Spear called here: its impact (SV_DecoySpearHit up), your health then and a second on, the radio's hit when it
-- hurt you, the sure kill (sure_kill) once it lands
local function watchTick(now)
    local W = DECOY.W
    if #W == 0 then return end
    local c = cfg()
    local f = (type(svFlags) == "function" and svFlags()) or {}
    local n = tonumber(f[DECOY.HIT_FLAG])
    for i = #W, 1, -1 do
        local w = W[i]
        if w.trace then                               -- (the test key's: each rod's place every tick)
            local me = myEntry()
            local you = me and me.at
            for _, o in ipairs(DECOY.rods) do
                local at = locOf(o)
                if at then
                    log(string.format("test: the Spear's rod %s at (%.2f, %.2f) km, alt %.2f km%s", shortName(o), at.X / 100000,
                        at.Y / 100000, at.Z / 100000, you and string.format(", %.2f km from you", dist3(at, you) / 100000) or ""))
                end
            end
        end
        if n and n > w.n0 and not w.hitAt then
            w.hitAt, w.hpHit = now, myHealth()
            DECOY.st.hits = DECOY.st.hits + 1
            log(string.format("decoy: the Spear's impact (%s %d -> %d) %.1f s after the call: your health %s -> %s", DECOY.HIT_FLAG,
                w.n0, n, now - w.at, w.hp0 and string.format("%.0f", w.hp0 / 10) or "?", w.hpHit and string.format("%.0f", w.hpHit / 10) or "?"))
            local dt = now - w.at
            local ld = c.lead or {}
            if ld.learn ~= false and dt > 0.2 and dt < 6 and n == w.n0 + 1 then   -- (one rod landed: its fall)
                local F = DECOY.falls
                F[#F + 1] = dt
                while #F > math.max(1, math.floor(num(ld.learn_n, 7))) do table.remove(F, 1) end
            end
            local meDown = DOWN and DOWN.me and DOWN.me() == true
            local hurt = w.hp0 and w.hpHit and w.hpHit < w.hp0
            if c.sure_kill == true and not meDown and (w.hpHit or 1) > 0 then
                log("decoy: the Spear's sure kill (" .. EV.kill .. " " .. errText(fire(EV.kill)) .. ")")
            elseif not hurt and not meDown and (w.hpHit or 1) > 0 and w.pos0 and (c.hit or {}).judge ~= false then
                -- ((2026-11-07) the hit judged: the stock rod ends at sea level, never at a plane's height, so a strike
                -- you didn't fly out of hits: where you'd be by now on the line you held at the call, against where you are)
                local me = myEntry()
                local cur = me and me.at
                local pred = DECOY.leadPoint(w.pos0, w.vel0, dt)
                local off = (cur and pred) and dist3(cur, pred) / 100 or nil
                local p = (off and not DECOY.inSafe(cur, c)) and DECOY.hitChance(off) or 0
                local roll = math.random()
                local how = string.format("%s m off the line you held, a %.0f%% chance, rolled %.0f%%",
                    off and string.format("%.0f", off) or "?", p * 100, roll * 100)
                if roll < p then
                    DECOY.st.judged = (DECOY.st.judged or 0) + 1
                    DECOY.blast(cur or pred, "air")
                    log(string.format("decoy: the Spear hits you (judged: %s): %s", how, DECOY.hurtMe(c)))
                    DECOY.say("hit", now)
                else
                    DECOY.blast(pred, "air")                -- (where it came down: on the line you left)
                    DECOY.st.missed = (DECOY.st.missed or 0) + 1
                    log(string.format("decoy: the Spear missed you (judged: %s)", how))
                end
            end
            w.afterAt = now + 1
        end
        if w.hitAt and now >= (w.afterAt or now) then
            local h = myHealth()
            log(string.format("decoy: a second after the Spear's impact: your health %s (%s before the call)",
                h and string.format("%.0f", h / 10) or "?", w.hp0 and string.format("%.0f", w.hp0 / 10) or "?"))
            if h and w.hp0 and h < w.hp0 then DECOY.say("hit", now) end
            table.remove(W, i)
        elseif not w.hitAt and (now >= w.untilAt or now < w.at - 60) then
            local h = myHealth()
            log(string.format("decoy: no Spear impact seen %.0f s after the call%s (your health %s -> %s)", now - w.at,
                w.fired and "" or " (the call wasn't fired)", w.hp0 and string.format("%.0f", w.hp0 / 10) or "?",
                h and string.format("%.0f", h / 10) or "?"))
            table.remove(W, i)
        end
    end
end

---------------------------------------------------------------------------------------------------- recycles (every game)
-- a UAV down (the host's, or a joiner's copy on the host's word): its pod and its mark off, then its unit and its mark's
-- off the spawner's list (SV_Recycle: force 1 while the pod or the mark keeps it "alive"), one a recycle_gap_s (the
-- runtime holds 64 deferred destroys: a burst past that destroys at once)
function DECOY.recycleLater(units, why, after)
    local now = clockNow()
    for _, u in ipairs(units or {}) do
        local dup = false
        for _, e in ipairs(DECOY.rq) do if e.unit == u then dup = true end end
        if not dup then DECOY.rq[#DECOY.rq + 1] = { unit = u, at = now + num(after, num(cfg().recycle_after_s, 4)), why = why } end
    end
end
local function recycleTick(now)
    local q = DECOY.rq
    if #q == 0 or type(SV_UnitAlive) ~= "function" or type(SV_Recycle) ~= "function" then return end
    if DECOY.rqAt and now < DECOY.rqAt and now >= DECOY.rqAt - 60 then return end
    for i, e in ipairs(q) do
        if now >= e.at or now < e.at - 120 then
            table.remove(q, i)
            DECOY.rqAt = now + num(cfg().recycle_gap_s, 1)
            for _, o in ipairs(objs(e.unit)) do if isPod(o) or e.unit:find(tostring(cfg().mark_prefix), 1, true) == 1 then switchOff(o) end end
            local n = SV_UnitAlive(e.unit)
            local r = "nothing to do"
            if n > 0 or n == 0 then
                crumb("decoy: SV_Recycle " .. e.unit .. " " .. (n > 0 and 1 or 0))
                local okR, rr = pcall(SV_Recycle, e.unit, n > 0 and 1 or 0)
                r = "SV_Recycle " .. (okR and tostring(rr) or ("error " .. tostring(rr)))
                if okR and rr == 1 and SPC and SPC.seenUnits then SPC.seenUnits[e.unit] = nil end
            end
            DECOY.recycled = (DECOY.recycled or 0) + 1
            if DECOY.recycled <= 4 or DECOY.recycled % 10 == 0 then
                log(string.format("decoy: %s off the spawner's list (%s; %d alive): %s (%d so far)", DECOY.label(e.unit) or e.unit,
                    tostring(e.why), n, r, DECOY.recycled))
            end
            return
        end
    end
end

---------------------------------------------------------------------------------------------------- the round (the host's, or solo)
local function upCount(s)
    local n = 0
    for _, U in pairs(s.u or {}) do if U.state == "up" then n = n + 1 end end
    return n
end
local function nextFree(s)
    for k = 1, maxUavs() do if not s.used[k] then return k end end
    return nil
end
local function payOf(base, per) return math.max(0, math.floor(num(base, 0) + num(per, 0) * ((D and D.round) or 0) + 0.5)) end
-- the round's state to every joiner (sent as it changes, and every 10 s anyway): "dk|s|<state>|<spawned>|<down>|<up>|<max>"
local function share(s, now, force)
    if not (isHost() and COOP.msg) then return end
    local key = string.format("%s|%d|%d|%d|%d", s.state, s.spawned or 0, s.down or 0, upCount(s), maxTotal())
    if not force and key == s.sharedKey and now < (s.shareAt or 0) then return end
    s.sharedKey, s.shareAt = key, now + 10
    COOP.msg(nil, "dk", "s", s.state, s.spawned or 0, s.down or 0, upCount(s), maxTotal())
end
-- every living player out of the fight (each down at the airfield): the bait's clock waits
local function everyoneDown()
    local okA, on = pcall(playerOnAirfield)
    if not (okA and on == true) then return false end
    local okO, others = pcall(othersFlying)
    return not okO or (others or 0) == 0
end

-- the round's units in this build's world data (SV_UnitAlive -2 for a unit it hasn't), with the native spawner: asked
-- once a level (seven asks), not while the level isn't up
function DECOY.unitsHere()
    local c = cfg()
    if type(nativeReady) == "function" and not nativeReady() then return false end
    if DECOY.have == nil then
        if type(SV_UnitAlive) ~= "function" then return false end
        local miss = {}
        for _, u in ipairs({ c.bait_unit, c.bait_mark, DECOY.uav(1), DECOY.uav(maxUavs()), DECOY.mark(1), DECOY.mark(maxUavs()),
                             DECOY.spear(1) }) do
            local ok, r = pcall(SV_UnitAlive, u)
            if not ok or r == -1 or r == -5 or r == -6 then return false end      -- (not in the level yet: asked again)
            if r == -2 then miss[#miss + 1] = tostring(u) end
        end
        DECOY.have = #miss == 0
        log(DECOY.have and string.format("special: THE DECOY's units are in this build's world data (the bait, %d UAVs and "
            .. "their marks, the Spear's launchers)", maxUavs())
            or ("special: no DECOY round: this build's world data has no " .. table.concat(miss, ", ")))
    end
    return DECOY.have
end
-- (the main menu, sv_main.lua's setup pass; every game) the trap UAVs' DT_NPC row (dt_npc, DT_SV_NpcRows' weaponless
-- Marker UAV) into the game's DT_NPC before the level loads (hard rule 20; a unit whose row the game hasn't doesn't
-- spawn), as the shoal's (sv_fishing.lua FISH.setup). DECOY.rowOk: in (else no DECOY round)
function DECOY.setup()
    if DECOY.setupDone or not gameInstance() then return end
    local c = cfg()
    if type(c.dt_npc) ~= "string" then DECOY.setupDone, DECOY.rowOk = true, true; return end
    DECOY.setupTries = (DECOY.setupTries or 0) + 1
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    if not (npc and mine) then
        if DECOY.setupTries >= 20 then
            DECOY.setupDone, DECOY.rowOk = true, false
            log("decoy: the row tables didn't load: no DECOY round this session")
        end
        return
    end
    DECOY.setupDone = true
    for _, t in ipairs({ npc, mine }) do pin(t, nameOf(t)) end
    local _, have = dtCall(npc, "FindRow", c.dt_npc)
    if have == nil then
        local _, r = dtCall(mine, "FindRow", c.dt_npc)
        if r ~= nil then dtCall(npc, "AddRow", c.dt_npc, r); _, have = dtCall(npc, "FindRow", c.dt_npc) end
    end
    DECOY.rowOk = have ~= nil
    log(string.format("decoy: the trap UAVs' row %s %s", c.dt_npc, DECOY.rowOk and "in DT_NPC" or "NOT added: no DECOY round this session"))
end
-- whether THE DECOY can come now (SPC.kinds.decoy.ready: the specials' bag and draw, SPC.canStart): switched on, its
-- units here and its UAVs' row in DT_NPC, and once a run (RUN.specialAt.decoy: set as its round starts; the test key's
-- force goes past it)
function DECOY.ready()
    local c = cfg()
    if c.enabled == false then said("off", "special: no DECOY round: switched off ([specials.decoy] enabled)"); return false end
    if type(c.dt_npc) == "string" and DECOY.rowOk ~= true then
        said("row", string.format("special: no DECOY round: its UAVs' DT_NPC row %s isn't in (%s)", c.dt_npc,
            DECOY.rowOk == false and "not added at the main menu" or "the main menu's setup hasn't run"))
        return false
    end
    if c.once_per_run ~= false and not DECOY.forced and RUN and type(RUN.specialAt) == "table" and RUN.specialAt.decoy then
        return false
    end
    return DECOY.unitsHere()
end

function DECOY.spawn(now)
    local c, t = cfg(), CFG.hud.text
    if c.enabled == false or not DECOY.unitsHere() then
        log("special: no DECOY round (" .. (DECOY.have == false and "its units aren't in the world data" or "switched off, or no native spawner") .. ")")
        return false
    end
    local s = D.special
    s.state, s.at, s.baitAt, s.baitClock, s.baitSeen = "bait", now, now, 0, now
    s.u, s.used, s.spawned, s.down, s.seq, s.locks = {}, {}, 0, 0, 0, 0
    s.bait = { unit = c.bait_unit }
    DECOY.forced = nil
    local rb = spawnUnit(c.bait_unit)
    if rb <= 0 then
        log("special: THE DECOY's bait " .. tostring(c.bait_unit) .. " not spawned (" .. tostring((SV_ERR and SV_ERR[rb]) or rb) .. ")")
        return false
    end
    local rm = spawnUnit(c.bait_mark)
    local sp = {}
    for i = 1, math.max(1, math.floor(num(c.spears, 4))) do
        local r = spawnUnit(DECOY.spear(i))
        sp[#sp + 1] = tostring(r)
    end
    hudCallout(t.dc_go, t.dc_go_sub)
    log(string.format("special: round %d, THE DECOY: the bait up (%s: %d), its mark at the airfield (%s: %d), the Spear's launchers %s",
        D.round, c.bait_unit, rb, c.bait_mark, rm, table.concat(sp, " ")))
    share(s, now, true)
    return true
end

local function startTrap(now, s, why)
    local c, t = cfg(), CFG.hud.text
    s.state, s.trapAt, s.nextSpawnAt = "trap", now, now + 1
    hudCallout(t.dc_trap, t.dc_trap_sub)
    DECOY.say("brief", now, true)
    log(string.format("special: THE DECOY's trap springs (%s): up to %d Spear UAVs round the players, %d up at most, each "
        .. "locking its closest player for %.1f s", why, maxTotal(), math.floor(num(c.max_up, 12)), num(c.lock_s, 8)))
    share(s, now, true)
end

local function baitTick(now, s)
    local c, t = cfg(), CFG.hud.text
    local B = s.bait
    findParts(B, c.bait_unit)
    local you = playerLocation()
    local at = B.body and locOf(B.body)
    s.baitKm = (at and you) and dist3(at, you) / 100000 or s.baitKm
    if not B.laser and B.body and not B.laserTried then
        local mark = firstOf(c.bait_mark, "any")
        if mark then
            tunePod(B.pod, baitHold())
            local r = fire(EV.bait_laser)
            B.laser, B.laserTried = r == 1, true
            log(string.format("special: THE DECOY's bait lasing the airfield (%s %s)", EV.bait_laser, errText(r)))
        end
    end
    if now >= (B.pingAt or 0) then
        B.pingAt = now + math.max(3, num(c.ping_every_s, 12))
        local r = fire(EV.bait_ping)
        B.pings = (B.pings or 0) + 1
        if B.pings == 1 then log(string.format("special: THE DECOY's bait pinged on the minimap every %.0f s (%s %s)",
            math.max(3, num(c.ping_every_s, 12)), EV.bait_ping, errText(r))) end
    end
    local dt = math.max(0, now - (s.baitSeen or now))
    s.baitSeen = now
    if not everyoneDown() then s.baitClock = (s.baitClock or 0) + dt end
    if bodyDown(B) then
        local pay = payOf(c.pay and c.pay.bait, c.pay and c.pay.bait_per_round)
        addCredits(pay, "THE DECOY's bait (the RECON DRONE) shot down")
        if LB and LB.stat then pcall(LB.stat, "air", 1) end
        hudCallout(t.dc_bait_down, string.format(t.dc_bait_down_sub, specialPay and specialPay(pay) or pay))
        log(string.format("special: THE DECOY's bait shot down %.0f s after it showed: +%d", now - s.baitAt, pay))
        fire(EV.bait_laser_off)
        s.baitDown = true
        pcall(DECOY.baitStrikeStart, now)
        startTrap(now, s, "the bait shot down")
    elseif not B.bodySeen and now - s.baitAt > 15 and not B.missSaid then
        B.missSaid = true
        log("special: THE DECOY's bait: no body seen 15 s after its spawn (its objects weren't recorded): it springs on its clock")
    end
    if s.state == "bait" and num(c.bait_timeout_s, 0) > 0 and s.baitClock >= num(c.bait_timeout_s, 0) then
        fire(EV.bait_laser_off)
        if COOP and COOP.takenOff then pcall(COOP.takenOff, c.bait_unit) end   -- (nobody's: unpaid on every game)
        for _, p in ipairs(planes or {}) do            -- (off the round's list first: no kill, no pay, no stats)
            if p.unit == c.bait_unit and not p.down then p.down, p.cleaned = true, true end
        end
        s.baitLeft = true
        local gone = B.body and finishOff(B.body)
        if B.pod then switchOff(B.pod) end
        DECOY.recycleLater({ c.bait_unit }, "its time up", 4)
        log(string.format("special: THE DECOY's bait taken off (%s)", gone and "finished off, nobody's kill" or "not finished off: hidden at the round's end"))
        startTrap(now, s, string.format("the bait not shot down in %.0f s: it leaves, unpaid", s.baitClock))
    end
end

-- ((2026-11-07) Alyssa's test: every UAV kept its own lock and locked again relock_s 6 after each strike, so with four or
-- five up the Spear fell every 2-4 s, four at once. Now at most locks_per_player locks on a player at a time (the user:
-- "Only two UAV's can lock onto a player at a time"), each starting lock_gap_s after the last one on them (so their
-- strikes come that far apart at least; a cancel frees the next sooner), each UAV relock_s after its own strike)
DECOY.nextLock = {}
local function locksOn(s, slot, now)
    local n = 0
    for _, V in pairs(s.u or {}) do
        if V.slot == slot and V.strikeAt and now < V.strikeAt + 0.5 then n = n + 1 end
    end
    return n
end
local function cancelLock(U, why)
    if isHost() and COOP.msg then COOP.msg(nil, "dk", "c", U.k, why) end
    DECOY.applyCancel(U.k, why)
    if U.slot ~= nil and why ~= "end" then
        local t = clockNow() + num(cfg().lock_gap_s, 4)
        if (DECOY.nextLock[U.slot] or 0) > t then DECOY.nextLock[U.slot] = t end
    end
    U.slot = nil
end
local function assignLock(now, s, U, e, d)
    local c = cfg()
    s.seq, s.locks = (s.seq or 0) + 1, (s.locks or 0) + 1
    U.slot, U.seq, U.lockAt = e.slot, s.seq, now
    U.strikeAt = now + num(c.lock_delay_s, 1.5) + num(c.lock_s, 8)
    U.relockAt = U.strikeAt + num(c.relock_s, 15)
    DECOY.nextLock[e.slot] = now + num(c.lock_gap_s, 4)
    if s.locks <= 6 or s.locks % 10 == 0 then
        log(string.format("decoy: UAV %d locks %s (%.1f km; lock %d this trap)", U.k, whoText(e.slot), (d or 0) / 100000, s.locks))
    end
    if isHost() and COOP.msg then COOP.msg(nil, "dk", "l", U.k, e.slot, U.seq) end
    DECOY.applyLock(U.k, e.slot, U.seq, now)
end
local function lockTick(now, s, U, players)
    local c = cfg()
    if U.slot then
        if now < U.strikeAt then                     -- (its player out of reach before the call: off it)
            local e = bySlot(players, U.slot)
            if not DECOY.validTarget(e, c) then
                cancelLock(U, (e and e.at and DECOY.inSafe(e.at, c)) and "safe" or "gone")
                U.relockAt = now + 1
            end
            return
        end
        if now < U.relockAt then return end
        U.slot = nil
    end
    if not U.pos or now < U.at + num(c.lock_after_s, 2) or now < (U.relockAt or 0) then return end
    local e, d = DECOY.closest(U.pos, players, c)
    if e and locksOn(s, e.slot, now) < math.max(1, math.floor(num(c.locks_per_player, 2)))
        and now >= (DECOY.nextLock[e.slot] or 0) then
        assignLock(now, s, U, e, d)
    end
end
local function uavDown(now, s, U)
    local c = cfg()
    U.state, U.downAt = "down", now
    s.down = (s.down or 0) + 1
    cancelLock(U, "down")                            -- (to every joiner too, locked or not: their copies' recycle)
    local pay = payOf(c.pay and c.pay.uav, c.pay and c.pay.uav_per_round)
    -- (never " down (" in a special's pay: sv_coop.lua reads that as a kill's, each game's own, neither split nor sent)
    addCredits(pay, string.format("a Spear UAV shot down: THE DECOY, %d of %d", s.down, maxTotal()))
    if LB and LB.stat then pcall(LB.stat, "air", 1) end
    log(string.format("special: THE DECOY's UAV %d shot down %.0f s after it showed: +%d; %d of %d down, %d up", U.k, now - U.at,
        pay, s.down, maxTotal(), upCount(s)))
    DECOY.recycleLater({ U.unit, U.mark }, "UAV " .. U.k .. " down")
end
local function spawnTick(now, s, players, ups)
    local c = cfg()
    if now < (s.nextSpawnAt or 0) then return end
    s.nextSpawnAt = now + math.max(1, num(c.spawn_every_s, 4))
    local up, total = upCount(s), maxTotal()
    local cand = {}
    for _, e in ipairs(players) do if DECOY.validTarget(e, c) then cand[#cand + 1] = e end end
    for i = #cand, 2, -1 do local j = math.random(i); cand[i], cand[j] = cand[j], cand[i] end
    for _, e in ipairs(cand) do
        if s.spawned >= total or up >= math.floor(num(c.max_up, 12)) then return end
        if DECOY.nearCount(e.at, ups, c) < math.floor(num(c.per_player_max, 4)) then
            local k = nextFree(s)
            if not k then return end
            local p = DECOY.spawnSpot(e.at, ups, c)
            if p then
                s.used[k] = true
                local unit = DECOY.uav(k)
                local r = spawnUnit(unit, p)
                if r > 0 then
                    local rm = spawnUnit(DECOY.mark(k), { X = e.at.X, Y = e.at.Y, Z = e.at.Z, yaw = 0 })
                    s.u[k] = { k = k, unit = unit, mark = DECOY.mark(k), at = now, state = "up", near = e.slot, pos = p }
                    s.spawned, up = s.spawned + 1, up + 1
                    ups[#ups + 1] = p
                    log(string.format("special: THE DECOY's UAV %d up by %s at (%.1f, %.1f) km, alt %.1f km, %.1f km from them "
                        .. "(%s: %d, its mark %d); %d of %d so far, %d up", k, whoText(e.slot), p.X / 100000, p.Y / 100000,
                        p.Z / 100000, dist3(p, e.at) / 100000, unit, r, rm, s.spawned, total, up))
                else
                    log(string.format("special: THE DECOY's UAV %d not spawned (%s: %s): the next one", k, unit,
                        tostring((SV_ERR and SV_ERR[r]) or r)))
                end
            end
        end
    end
end
-- why the trap ends now, or nil: "all down" (every UAV that could come is down), "safe" (every living player inside
-- the safe circle for safe_hold_s, from safe_after_s into it), "time" (trap_s)
function DECOY.endWhy(s, players, now, c)
    c = c or cfg()
    local up = upCount(s)
    if up == 0 and (s.spawned >= maxTotal() or nextFree(s) == nil) then return "all down" end
    if now - s.trapAt >= num(c.trap_s, 300) then return "time" end
    local living, safe = 0, 0
    for _, e in ipairs(players or {}) do
        if e.alive ~= false and not e.down and type(e.at) == "table" then
            living = living + 1
            if e.onAirfield or DECOY.inSafe(e.at, c) then safe = safe + 1 end
        end
    end
    if living > 0 and safe == living and now - s.trapAt >= num(c.safe_after_s, 30) then
        s.safeSince = s.safeSince or now
        if now - s.safeSince >= num(c.safe_hold_s, 5) then return "safe" end
    else
        s.safeSince = nil
    end
    return nil
end
local function endTrap(now, s, why)
    local c, t = cfg(), CFG.hud.text
    s.state, s.endWhy, s.endAt = "done", why, now
    local left = 0
    for _, U in pairs(s.u or {}) do
        if U.slot then cancelLock(U, "end") end
        if U.state == "up" then
            left = left + 1
            U.state = "left"
            if COOP and COOP.takenOff then pcall(COOP.takenOff, U.unit) end
        end
    end
    for k in pairs(DECOY.G) do dropLock(k, "the trap's over", true) end
    local pay = payOf(c.reward, c.reward_per_round)
    if why == "safe" then pay = math.floor(pay * num(c.reward_safe_x, 0.5) + 0.5) end
    if pay > 0 then addCredits(pay, "THE DECOY's trap over (" .. why .. ")") end
    if LB and LB.special then pcall(LB.special, "decoy", why ~= "safe", now - (s.at or now)) end
    hudCallout(why == "safe" and t.dc_done_safe or why == "time" and t.dc_done_time or t.dc_done,
        string.format(t.dc_done_sub, specialPay and specialPay(pay) or pay))
    log(string.format("special: THE DECOY's trap over (%s) %.0f s in: %d Spear UAVs came, %d shot down, %d left (taken off "
        .. "unpaid), %d locks; the bait %s; +%d", why, now - (s.trapAt or now), s.spawned or 0, s.down or 0, left, s.locks or 0,
        s.baitDown and "shot down" or "not shot down", pay))
    local st = DECOY.st
    log(string.format("decoy: this game's locks this run: %d on you, %d Spear calls (%d impacts seen), %d cancelled",
        st.locks, st.struck, st.hits, st.cancelled))
    share(s, now, true)
end

-- (SPC.kinds.decoy.tick, every tick of its round)
function DECOY.hostTick(now, s)
    if s.state == "bait" then baitTick(now, s)
    elseif s.state == "trap" and now >= (s.trapNext or 0) then
        s.trapNext = now + 0.5
        local c = cfg()
        local players = DECOY.players()
        local ups = {}
        for _, U in pairs(s.u) do
            if U.state == "up" then
                findParts(U, U.unit)
                if bodyDown(U) then
                    uavDown(now, s, U)
                elseif not U.bodySeen and now - U.at > 10 then
                    U.state = "lost"
                    log(string.format("special: THE DECOY's UAV %d: no body seen 10 s after its spawn: taken off", U.k))
                    if U.slot then cancelLock(U, "gone") end
                    DECOY.recycleLater({ U.unit, U.mark }, "UAV " .. U.k .. " never seen", 1)
                else
                    local at = U.body and locOf(U.body)
                    if at then U.pos = at end
                    if U.pos then ups[#ups + 1] = U.pos end
                    lockTick(now, s, U, players)
                end
            end
        end
        spawnTick(now, s, players, ups)
        local why = DECOY.endWhy(s, players, now, c)
        if why then endTrap(now, s, why) end
    end
    if s.state == "bait" or s.state == "trap" then share(s, now, false) end
end
function DECOY.busy(s) return s ~= nil and (s.state == "bait" or s.state == "trap") end
-- (SPC.kinds.decoy.over: the round's end) a trap still on is ended here (it holds the round, so only an odd end gets here)
function DECOY.roundOver(now, s)
    if s and (s.state == "bait" or s.state == "trap") then
        if s.state == "bait" then s.trapAt = now end
        endTrap(now, s, "the round's over")
    end
end
function DECOY.row(s, t)
    if s.state == "bait" then return s.baitKm and string.format(t.dc_row_bait, s.baitKm) or nil end
    if s.state == "trap" then return string.format(t.dc_row, upCount(s), s.down or 0, math.max(0, maxTotal() - (s.spawned or 0))) end
    return nil
end

---------------------------------------------------------------------------------------------------- co-op
-- what the host sends ("dk"), checked: every number whole and in range, words from fixed sets; nil for anything else
local STATES = { bait = true, trap = true, done = true }
local WHYS = { down = true, safe = true, gone = true, ["end"] = true }
function DECOY.parse(f)
    if type(f) ~= "table" or f[1] ~= "dk" then return nil end
    local function int(v, lo, hi)
        v = tonumber(v)
        if v and v == v and v == math.floor(v) and v >= lo and v <= hi then return math.floor(v) end
        return nil
    end
    local kind = f[2]
    if kind == "s" then
        local st = tostring(f[3] or ""):sub(1, 8)
        local sp, dn, up, mx = int(f[4], 0, 99), int(f[5], 0, 99), int(f[6], 0, 99), int(f[7], 0, 99)
        if not (STATES[st] and sp and dn and up and mx) then return nil end
        return { kind = "s", state = st, spawned = sp, down = dn, up = up, max = mx }
    elseif kind == "l" then
        local k, slot, seq = int(f[3], 1, maxUavs()), int(f[4], 0, 23), int(f[5], 1, 1000000)
        if not (k and slot and seq) then return nil end
        if COOP and type(COOP.slotOk) == "function" and not COOP.slotOk(slot) then return nil end
        return { kind = "l", k = k, slot = slot, seq = seq }
    elseif kind == "c" then
        local k, why = int(f[3], 1, maxUavs()), tostring(f[4] or ""):sub(1, 8)
        if not (k and WHYS[why]) then return nil end
        return { kind = "c", k = k, why = why }
    end
    return nil
end
-- (a joiner: sv_coop.lua's onJoinerMessage, the host's alone) the round's state, a lock, a cancel; at most 40 a second
function DECOY.fromHost(f)
    if not (D and isClient()) then return end
    local t0 = os.clock()
    local rx = DECOY.rx
    if t0 - rx.at >= 1 then rx.at, rx.n = t0, 0 end
    rx.n = rx.n + 1
    if rx.n > 40 then said("rx", "decoy: more than 40 of the host's \"dk\" in a second: the rest dropped"); return end
    local m = DECOY.parse(f)
    if not m then said("bad", "decoy: a \"dk\" from the host not understood: dropped"); return end
    local now = clockNow()
    if m.kind == "s" then
        local was = DECOY.cs and DECOY.cs.state
        DECOY.cs = { state = m.state, spawned = m.spawned, down = m.down, up = m.up, max = m.max, got = os.clock() }
        if m.state ~= was then
            log(string.format("decoy: the host's DECOY round: %s (%d of %d UAVs came, %d down, %d up)", m.state, m.spawned, m.max,
                m.down, m.up))
            if m.state == "bait" then DECOY.jb = { at = now } end
            if m.state == "trap" then
                DECOY.say("brief", now, true)
                if DECOY.jb and DECOY.jb.laser then fire(EV.bait_laser_off) end
                pcall(DECOY.baitStrikeStart, now)          -- ((2026-11-07) the bait's strike's blast here too; its damage the host's)
            end
            if m.state == "done" then
                for k in pairs(DECOY.G) do dropLock(k, "the host's trap is over", true) end
                local st = DECOY.st
                log(string.format("decoy: this game's locks this run: %d on you, %d Spear calls (%d impacts seen), %d cancelled",
                    st.locks, st.struck, st.hits, st.cancelled))
            end
        end
    elseif m.kind == "l" then
        if DECOY.applyLock(m.k, m.slot, m.seq, now) and m.slot == mySlot() then
            log(string.format("decoy: the host's UAV %d locks you (lock %d)", m.k, m.seq))
        end
    elseif m.kind == "c" then
        DECOY.applyCancel(m.k, "the host's: " .. m.why)
        if m.why == "down" then DECOY.recycleLater({ DECOY.uav(m.k), DECOY.mark(m.k) }, "the host's UAV " .. m.k .. " down",
            num(cfg().recycle_after_s, 4) + 2) end
    end
end
-- (the host: sv_coop.lua hostSync, a joiner asking for the whole picture) the round's state and the locks before their call
function DECOY.syncTo(to)
    local s = D and D.special
    if not (s and s.kind == "decoy" and DECOY.busy(s) and isHost() and COOP.msg) then return end
    COOP.msg(to, "dk", "s", s.state, s.spawned or 0, s.down or 0, upCount(s), maxTotal())
    local n = 0
    for k, U in pairs(s.u or {}) do
        if U.state == "up" and U.slot and D.now and D.now < (U.strikeAt or 0) then
            COOP.msg(to, "dk", "l", k, U.slot, U.seq)
            n = n + 1
        end
    end
    log(string.format("coop: THE DECOY's %s sent to player %d (%d locks on)", s.state, (to or 0) + 1, n))
end
-- (a joiner) the host's bait here: its laser on this game's mark, its ping on this game's copy
local function joinerTick(now)
    local cs, jb = DECOY.cs, DECOY.jb
    if not (cs and jb and cs.state == "bait" and isClient()) then return end
    local c = cfg()
    jb.body = (jb.body and liveObj(jb.body)) and jb.body or firstOf(c.bait_unit, "body")
    if not jb.laserTried and jb.body and firstOf(c.bait_mark, "any") then
        jb.laserTried = true
        tunePod(firstOf(c.bait_unit, "pod"), baitHold())
        local r = fire(EV.bait_laser)
        jb.laser = r == 1
        log(string.format("decoy: the host's bait lasing the airfield here (%s %s)", EV.bait_laser, errText(r)))
    end
    if jb.body and now >= (jb.pingAt or 0) then
        jb.pingAt = now + math.max(3, num(c.ping_every_s, 12))
        fire(EV.bait_ping)
    end
end
-- (a joiner's NEXT row) the host's round, from its "dk|s" (20 s fresh at most)
function DECOY.clientRow(t)
    local cs = DECOY.cs
    if not (cs and isClient() and os.clock() - (cs.got or 0) <= 20) then return nil end
    if cs.state == "bait" then
        local jb, you = DECOY.jb, playerLocation()
        local at = jb and jb.body and locOf(jb.body)
        return (at and you) and string.format(t.dc_row_bait, dist3(at, you) / 100000) or nil
    end
    if cs.state == "trap" then return string.format(t.dc_row, cs.up, cs.down, math.max(0, cs.max - cs.spawned)) end
    return nil
end

---------------------------------------------------------------------------------------------------- every game's tick
-- this game's run starts over (a new D): its locks and watches forgotten (the marks let go), the radio's clocks too
local function resetRun()
    pcall(DECOY.cloudsRestore, "the run starts over")
    DECOY.bs = nil
    DECOY.nextLock, DECOY.falls = {}, {}
    for _, g in pairs(DECOY.G) do detach(g) end
    DECOY.G, DECOY.R, DECOY.W, DECOY.cs, DECOY.jb, DECOY.spearI = {}, {}, {}, nil, nil, nil
    DECOY.Q = { by = {}, n = {} }
    DECOY.st = { locks = 0, struck = 0, hits = 0, cancelled = 0 }
end
-- (sv_main.lua probeTickB, every game, on the round clock)
function DECOY.tick(now)
    if not (D and now) then return end
    if DECOY.runD ~= D then
        if DECOY.runD ~= nil then resetRun() end
        DECOY.runD = D
    end
    rodsTick()
    if next(DECOY.G) or next(DECOY.R) then
        local players = DECOY.players()
        locksTick(now, players)
        runnersTick(now, players)
    end
    watchTick(now)
    local okB, errB = pcall(baitStrikeTick, now)
    if not okB then said("bait strike err", "decoy: the bait strike's watch error " .. tostring(errB)) end
    joinerTick(now)
    recycleTick(now)
    if DECOY.testTick then DECOY.testTick(now) end
    -- the clouds' fix while the Spear is about (a trap on, a strike due, the test), put back once it's quiet
    local busy = (DECOY.cs and DECOY.cs.state == "trap") or next(DECOY.R) ~= nil or #DECOY.W > 0 or DECOY.test ~= nil
    if busy then
        if #DECOY.rods > 0 and now - (DECOY.cl.at or -100) >= math.max(1, num(ccfg().every_s, 5)) then pcall(DECOY.cloudsApply, now) end
        DECOY.cl.quietAt = nil
    elseif next(DECOY.cl.orig) ~= nil then
        DECOY.cl.quietAt = DECOY.cl.quietAt or now
        if now - DECOY.cl.quietAt >= num(ccfg().restore_after_s, 60) then pcall(DECOY.cloudsRestore, "the Spear quiet") end
    end
end

-- (sv_core.lua levelDrop: the level torn down) every object kept here forgotten, none touched
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the decoy"] = function()
        DECOY.G, DECOY.R, DECOY.W, DECOY.rq, DECOY.rods, DECOY.rodNew = {}, {}, {}, {}, {}, {}
        DECOY.cs, DECOY.jb, DECOY.have, DECOY.markMode, DECOY.runD, DECOY.rqAt, DECOY.test = nil, nil, nil, nil, nil, nil, nil
        DECOY.moveHeld = nil
        DECOY.spearI = nil
        DECOY.cl = { orig = {}, at = -100 }                -- (the sky's objects are the level's: dropped, never put back)
        DECOY.nextLock, DECOY.vlSaid, DECOY.falls = {}, nil, {}
        DECOY.bl, DECOY.bs = { sys = {} }, nil
    end
end

-- the round's kind (sv_anomalies.lua SPC.kinds: its callout's sub, its aircraft, ready, its fighters, spawn, tick, busy,
-- its end and its NEXT row)
if type(SPC) == "table" and type(SPC.kinds) == "table" then
    -- ((2026-11-07) the user: "make sure that in the GONE FISHIN round and THE DECOY that normal aircraft arent
    -- spawning": fighter_share 0, the bait and the trap's UAVs alone)
    SPC.kinds.decoy = {
        sub = "dc_sub", aircraft = 1,
        ready = function() return DECOY.ready() end,
        budget = function(budget)
            local x = math.max(0, math.min(1, num(cfg().fighter_share, 0)))
            return math.max(0, math.floor((tonumber(budget) or 0) * x / 2 + 0.5) * 2)
        end,
        spawn = function(now) return DECOY.spawn(now) end,
        tick = function(now, s) return DECOY.hostTick(now, s) end,
        busy = function(s) return DECOY.busy(s) end,
        over = function(now, s) return DECOY.roundOver(now, s) end,
        row = function(s, t) return DECOY.row(s, t) end,
    }
end

-- TEST ONLY BEGIN
-- The research's two tests and the round, by key (each makes its run unranked: LB.testKey):
--   Ctrl+=          the Spear alone (Key.OEM_PLUS): launcher 1 (spawned first when it isn't up), RE_SV_DecoySpear_1 at
--                   you; each rod's place every tick, the impact flag, your health before and after (`test: the Spear's
--                   rod ...`)
--   Ctrl+BACKSPACE  one lock: UAV 1 spawned 3 km ahead of you at your height, its mark on you, its laser on you, then
--                   the 8 s: shoot it down for `strike cancelled`, or leave it for `the Spear called on you`
--   Ctrl+-          THE DECOY next round (Key.OEM_MINUS; in the break: in 3 s), once a run or not
-- (were Ctrl+PAGE_UP / PAGE_DOWN / HOME, which GONE FISHIN', THE FESTIVAL and the day-night arc took on 2026-11-07)
local function testStart(kind)
    if not (D and D.now) then log("test: THE DECOY's key outside a Survival run"); return end
    local now = D.now
    local sp = DECOY.spear(1)
    local n = type(SV_UnitAlive) == "function" and SV_UnitAlive(sp) or -5
    local wait = 0
    if n <= 0 then
        local r = spawnUnit(sp)
        log(string.format("test: THE DECOY's Spear launcher 1 (%s) spawned for the test: %s", sp, tostring(r)))
        wait = 1.5
    end
    if kind == 1 then
        DECOY.test = { kind = 1, at = now + wait }
        hudCallout("TEST: THE SPEAR", "CALLED ON YOU")
        log("test: Ctrl+=, the Spear at you from launcher 1" .. (wait > 0 and " in 1.5 s" or ""))
        return
    end
    local pawn = myPawn()
    local you = playerLocation()
    if not (pawn and you) then log("test: Ctrl+BACKSPACE: no plane of yours"); return end
    local okF, fw = pcall(function() local v = pawn:GetActorForwardVector(); return { X = v.X, Y = v.Y } end)
    if not okF then fw = { X = 1, Y = 0 } end
    local l = math.sqrt(fw.X ^ 2 + fw.Y ^ 2)
    if l < 0.01 then fw, l = { X = 1, Y = 0 }, 1 end
    local p = { X = you.X + fw.X / l * 300000, Y = you.Y + fw.Y / l * 300000, Z = you.Z }
    p.yaw = math.deg(math.atan(you.Y - p.Y, you.X - p.X))
    dropLock(1, "the test again", true)
    local r = spawnUnit(DECOY.uav(1), p)
    local rm = spawnUnit(DECOY.mark(1), { X = you.X, Y = you.Y, Z = you.Z, yaw = 0 })
    DECOY.testSeq = (DECOY.testSeq or 1000) + 1
    DECOY.test = { kind = 2, at = now + math.max(2, wait), seq = DECOY.testSeq }
    hudCallout("TEST: ONE SPEAR UAV", r > 0 and "3 KM AHEAD: IT LOCKS YOU IN 2 S" or "COULD NOT SPAWN")
    log(string.format("test: Ctrl+BACKSPACE, one Spear UAV 3 km ahead of you (%s: %s, its mark %s: %s); its lock in 2 s",
        DECOY.uav(1), tostring(r), DECOY.mark(1), tostring(rm)))
end
function DECOY.testTick(now)
    local T = DECOY.test
    if not T or now < (T.at or 0) then return end
    DECOY.test = nil
    if T.kind == 1 then
        DECOY.strike(0, { at = now, trace = true }, now, 1)
    elseif T.kind == 2 then
        DECOY.applyLock(1, mySlot(), T.seq, now)
        log("test: UAV 1's lock on you starts now (its laser once it and its mark are here)")
    end
end
if type(testKey) == "function" then
    testKey("OEM_PLUS", "sv_decoy.lua's Spear test", function() testStart(1) end)
    testKey("BACKSPACE", "sv_decoy.lua's one-lock test", function() testStart(2) end)
    testKey("OEM_MINUS", "sv_decoy.lua's THE DECOY next", function()
        if not (D and D.now) then log("test: Ctrl+- outside a Survival run"); return end
        D.forceSpecial, DECOY.forced = "decoy", true
        local soon = D.state == "wait"
        if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
        hudCallout("TEST: RECON DRONE", soon and "STARTING NOW" or "NEXT ROUND")
        log(string.format("test: Ctrl+-, round %d is THE DECOY (%s)", D.round + 1, soon and "starting in 3 s" or "after this round"))
    end)
end
-- TEST ONLY END
end
