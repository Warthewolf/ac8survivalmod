-- sv_ai.lua: enemy pilots: tiers, kill log, ace hunting, kill pay.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- Question 2: PilotRank on each enemy (p from the plane list), called every 2 s while it is up.
-- CFG.tiers: this enemy's tier (by the round, sometimes one higher) and PilotRank, set once when it is first seen up.
enemyTier = nil
do
local tierSaid = {}
function enemyTier(p, round, flightTier)
    local tc = CFG.tiers
    if p.tier ~= nil or not tc.enabled or not round then return end
    local i = flightTier or TIER.pick(round)                 -- a fighter flight's was picked at its spawn
    local t = tc.list[i]
    p.tier = t
    local add = tc.rank_add[presetName()] or 0
    local want = math.max(1, math.min(5, t.rank + add, 5))
    local sk = spikeCfg(spikeLevel(round))
    if sk.rank_min then want = math.max(want, math.min(5, sk.rank_min)) end
    local ok0, r0 = pcall(function() return p.obj.PilotRank end)
    local okW, err = pcall(function() p.obj.PilotRank = want end)
    local key = round .. t.name
    if not tierSaid[key] or not okW then
        tierSaid[key] = true
        local lv = ""
        if t.ai_level and type(SV_PlaneLevel) == "function" then     -- the AI level the plane took from its desc
            local okL, l = pcall(function() return SV_PlaneLevel(addrOf(p.obj)) end)
            lv = string.format(", AI level %s (wanted %d)", okL and tostring(l) or "?", t.ai_level * 100)
        end
        log(string.format("tiers: round %d %s (%s): PilotRank %s -> %d%s%s", round, t.name, p.name, ok0 and tostring(r0) or "?",
            want, lv, okW and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end
end

-- CFG.maneuvers: post-stall permission for this enemy (p from the plane list), set once when it is first seen up:
-- its model must be listed and its tier (enemyTier, run first) must allow post-stall at all.
-- The first plane of each model logs what its blueprint had and what it reads after the write.
enemyManeuvers = nil
do
local maneuversSaid = {}
function enemyManeuvers(p, round)
    if p.maneuvers or not CFG.maneuvers.enabled then return end
    p.maneuvers = true
    local model = p.name:match("^BP_OP%d+_(%w+)_") or "?"
    local allow = false
    for _, m in ipairs(CFG.maneuvers.post_stall) do if m == model then allow = true end end
    if p.tier and not p.tier.post_stall then allow = false end
    local all = spikeCfg(spikeLevel(round)).post_stall_all      -- a difficulty spike: every airframe
    local fl = p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]
    if fl and fl.post_stall then all = true end                    -- (a top tier: on, whatever its blueprint)
    local function read()
        local okC, c = pcall(function() return p.obj.bCanManeuverPugachevsCobra end)
        local okK, k = pcall(function() return p.obj.bCanManeuverKulbit end)
        return string.format("cobra %s, kulbit %s", okC and tostring(c) or "?", okK and tostring(k) or "?")
    end
    local before = read()
    local ok, err = true, nil
    if all then
        allow = true
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = true
            p.obj.bCanManeuverKulbit = true
        end)
    elseif not allow then                   -- allowed models keep their blueprint's own (test 18: su33 cobra only)
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = false
            p.obj.bCanManeuverKulbit = false
        end)
    end
    local said = model .. (allow and "+" or "-") .. (all and "!" or "")
    if not maneuversSaid[said] then
        maneuversSaid[said] = true
        log(string.format("maneuvers: %s (%s) post-stall %s: was %s, now %s%s", model, p.name, allow and "allowed" or "off",
            before, read(), ok and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end
end

-- Kill log (for the learning layer later): every 2 s while an enemy is up its heading is kept, and when it goes down
-- the player's aspect, altitude and recent ammo use are logged. (K2_GetLastDamagedByAttacker never named anyone.)
function probeTrack(p)
    pcall(function() local f = p.obj:GetActorForwardVector(); p.fwd = { X = f.X, Y = f.Y, Z = f.Z } end)
end

local AMMO_SHORT = { [0] = "gun", "msl", "sp1", "sp2", "flr" }

-- AI watch (CFG.ai_watch; user, 2026-10-22: "they fly towards the airfield instead of targeting the player"): every
-- 2 s each enemy's AI state (blackboard key AIState, ELiveAIState) and target (blackboard key TargetActor), logged
-- when either changes, with its distance to the player and to the airfield. (AIStateComponent.LuaAssets is not the set
-- in use: it read LA_MoveAwayFromTarget_0000 on planes whose set was built with LA_SV_MoveAway.)
local AI_STATE = { [0] = "ReturnToWorld", "AvoidObstacle", "AvoidRangeAttack", "Wingman", "ReturnToUnit", "AttackAvoidance",
                   "EscapeFromPursuer", "Blackout", "Provoke", "MoveAwayFromTarget", "PursueTarget", "FollowFormation",
                   "Group", "Patrol", "UniqueAction", "CloudAvoidance", "Idle" }
function aiWatch(p, you)
    if not CFG.ai_watch then return end
    local st, tgt = "?", "?"
    pcall(function()
        local bb = p.obj.AIStateComponent.BlackboardComponent
        local okS, v = pcall(function() return bb:GetValueAsEnum(FName("AIState")) end)
        if okS and type(v) == "number" then st = AI_STATE[v] or tostring(v) end
        local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
        if okT then tgt = valid(t) and (nameOf(t):match("([^%.:]+)$") or "?") or "none" end
    end)
    if st .. "|" .. tgt == p.aiKey then return end
    p.aiKey = st .. "|" .. tgt
    local air = p.at and math.sqrt((p.at.X - AIRFIELD.X) ^ 2 + (p.at.Y - AIRFIELD.Y) ^ 2) / 100000
    log(string.format("ai: %s (%s) %s, target %s; %s km from you, %s km from the airfield", p.name, tostring(p.unit or "?"),
        st, tgt, (p.at and you) and string.format("%.1f", km(p.at, you)) or "?", air and string.format("%.1f", air) or "?"))
end

-- CFG.aces.flight <tier>.hunt: that tier's aircraft keep the player as their target (blackboard TargetActor)
function ACE.hunt(p)
    local fl = p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]   -- (its tier's)
    if not (fl and fl.hunt) then return end
    if fl.no_provoke then                       -- (every 2 s: an engagement order sets it again)
        pcall(function() if p.obj.bPermissionToProvoke then p.obj.bPermissionToProvoke = false end end)
        if not p.noProvokeSaid then
            p.noProvokeSaid = true
            local okR, v = pcall(function() return p.obj.bPermissionToProvoke end)
            log(string.format("aces: %s won't defend when tailed (bPermissionToProvoke %s)", p.name, okR and tostring(v) or "?"))
        end
    end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    local bb = p.obj.AIStateComponent.BlackboardComponent
    local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
    if okT and valid(t) and nameOf(t) == nameOf(pawn) then return end
    local ok = pcall(function() bb:SetValueAsObject(FName("TargetActor"), pawn) end)
    p.huntN = (p.huntN or 0) + 1
    if p.huntN == 1 or p.huntN % 30 == 0 then
        log(string.format("aces: %s back onto you (was %s)%s, %d times", p.name, okT and valid(t) and (nameOf(t):match("([^%.:]+)$") or "?") or "none",
            ok and "" or " (write failed)", p.huntN))
    end
end

-- Top-tier reversals (CFG.aces.flight <tier>.moves) and their geometry helpers
do
local function deg(a, b)                           -- the angle between two vectors, degrees
    local la = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    local lb = math.sqrt(b.X * b.X + b.Y * b.Y + b.Z * b.Z)
    if la == 0 or lb == 0 then return 0 end
    return math.deg(math.acos(math.max(-1, math.min(1, (a.X * b.X + a.Y * b.Y + a.Z * b.Z) / (la * lb)))))
end
local function vec(v) return { X = v.X, Y = v.Y, Z = v.Z } end
-- CFG.aces.flight <tier>.moves: the reversals (RE_SV_AceTurn_NN / RE_SV_AceKulbit_NN on the plane's pool flight)
function ACE.movesTick(now, D)
    if not (D and D.round and type(SV_Event) == "function") then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    local me
    D.aceMoveAt = D.aceMoveAt or {}
    for _, p in ipairs(planes) do
        local fl = not p.down and p.unit and p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]
        if fl and fl.moves and now >= (D.aceMoveAt[p.unit] or 0) and valid(p.obj) then
            local pn, pk = p.unit:match("^ERA_Unit_(%d+)_Dep_Air(%d)$")
            if pn then
                me = me or vec(pawn:K2_GetActorLocation())
                local at, fwd = vec(p.obj:K2_GetActorLocation()), vec(p.obj:GetActorForwardVector())
                local toMe = { X = me.X - at.X, Y = me.Y - at.Y, Z = me.Z - at.Z }
                local range = km(at, me) * 1000
                local offTail = deg({ X = -fwd.X, Y = -fwd.Y, Z = -fwd.Z }, toMe)
                if range <= 3000 and offTail <= 70 then
                    local kulbit = range <= 900
                    local ev = string.format("RE_SV_%s_%02d", kulbit and "AceKulbit" or "AceTurn", (tonumber(pn) - 1) * 3 + tonumber(pk) + 1)
                    local r = SV_Event(ev)
                    D.aceMoveAt[p.unit] = now + (kulbit and 12 or 20)
                    D.aceMoves = (D.aceMoves or 0) + 1
                    if D.aceMoves <= 5 or D.aceMoves % 20 == 0 then
                        log(string.format("aces: %s has you %.0f m behind it, %.0f deg off its tail: %s (%s), %d so far", p.name,
                            range, offTail, ev, tostring(r), D.aceMoves))
                    end
                end
            end
        end
    end
end

end

function probeKill(p, you)
    if not (CFG.probe.enabled and CFG.probe.kills) then return end
    local aspect, dz = "?", "?"
    if p.at and you and p.fwd then
        local tx, ty, tz = you.X - p.at.X, you.Y - p.at.Y, you.Z - p.at.Z
        local len = math.sqrt(tx * tx + ty * ty + tz * tz)
        if len > 0 then
            local c = (p.fwd.X * tx + p.fwd.Y * ty + p.fwd.Z * tz) / len      -- 1: you were ahead of it, -1: on its tail
            aspect = string.format("%.0f deg off its nose", math.deg(math.acos(math.max(-1, math.min(1, c)))))
        end
        dz = string.format("%+.1f km", (you.Z - p.at.Z) / 100000)
    end
    local used = {}                                                           -- ammo spent in the last ~6 s
    local h = PR.ammo
    for k = 0, 4 do
        local spent = 0
        for i = 2, #h do
            local a, b = h[i - 1][k], h[i][k]
            if a and b and a >= 0 and b >= 0 and b < a then spent = spent + (a - b) end
        end
        if spent > 0 then used[#used + 1] = AMMO_SHORT[k] .. " x" .. spent end
    end
    log(string.format("kill: %s; you were %s away, %s, altitude %s; you fired %s in the last 6 s",
        p.name, p.at and you and string.format("%.1f km", km(p.at, you)) or "?",
        aspect, dz, #used > 0 and table.concat(used, ", ") or "nothing seen"))
end

ZONE = { X = -707336.0, Y = -261895.0, HALF = 3700000.0 }   -- Mission 22's combat zone (80 km), 3 km margin
SV_ERR = { [0] = "the game spawned nothing", [-1] = "not in Survival's level", [-2] = "no such unit or aircraft",
                 [-3] = "its last flight is still up", [-4] = "bad arguments", [-5] = "game functions not found" }
D = nil                      -- the run in progress: { round, state, at, now, queue, spare, up, flown }
-- The run's money and purchases: { credits, earned, spent, bought = { [item] = n },
-- msg = { [item] = last result }, dirty (shop texts need updating) }. Reset when Survival's level loads.
RUN = { credits = 0, earned = 0, spent = 0, bought = {}, msg = {} }

function addCredits(n, why)
    if n <= 0 then return end
    RUN.credits, RUN.earned, RUN.dirty = RUN.credits + n, RUN.earned + n, true
    RUN.msg = {}            -- a shop result ("NOT ENOUGH ZOLLARS ...") is stale once the credits change
    log(string.format("credits: +%d (%s), now %d", n, why, RUN.credits))
end

-- Kill pay's multiplier now: CFG.credits.special_x in a special round, else 1.
function TIER.specialX() return (D and D.special) and (CFG.credits.special_x or 1) or 1 end

function nativeReady()
    return type(SV_Spawn) == "function" and type(SV_UnitAlive) == "function" and type(SV_SetAircraft) == "function"
end

---------------------------------------------------------------------------------------------------- round HUD
-- Survival's own HUD layer, built at run time (no widget asset). The game's HUD is laid out on a 3840x2160 canvas
-- (tools/re/HUD_LAYOUT.md), so ours is too: a stock widget blueprint with no script of its own
-- (WBP_HUD_NonGlowMessage_000, its parts collapsed) -> its root canvas -> ScaleBox (scale to fit) -> SizeBox
-- 3840x2160 -> our canvas. The rows copy the mission info panel (HUD typeface 37, spacing -70, white, opacity 0.55) and
-- sit under its TIME / SCORE stack; the callout copies the MessageLayerOne banner (text in a frame of 4 px bars).
-- UUserWidget is Abstract (constructing one directly is fatal in a shipping build), so the widget comes from
-- WidgetBlueprintLibrary.Create, the engine's CreateWidget; TextBlock / Image / CanvasPanel / ScaleBox / SizeBox are
-- concrete and made with StaticConstructObject in its WidgetTree. All of it runs in the one game-thread tick.
HUD_ASSET = { base = "/Game/Blueprints/UI/WBP/HUD4K/Campaign/WBP_HUD_NonGlowMessage_000.WBP_HUD_NonGlowMessage_000_C",
                   font = "/Game/UI/Font/UI_FontSet_ja.UI_FontSet_ja" }
DESIGN_W, DESIGN_H = 3840, 2160
VIS = { Visible = 0, Collapsed = 1, Hidden = 2, HitTestInvisible = 3, SelfHitTestInvisible = 4 }
H = nil                      -- the HUD layer: { widget, tree, font, rowSlots, round, next, banner, ... }
AF = {}                      -- the airfield: { full, base, hits, hp, down, downRound, attackRound } (section "airfield")
hudGen, hudTries, hudOff = 0, 0, false
hudSaid = {}

function hudLog(key, msg)    -- once per key per level
    if hudSaid[key] then return end
    hudSaid[key] = true
    log("hud: " .. msg)
end

function cdo(path) local o = StaticFindObject(path); return valid(o) and o or nil end

function toText(s)
    local tl = cdo("/Script/Engine.Default__KismetTextLibrary")
    if tl then
        local ok, t = pcall(function() return tl:Conv_StringToText(s) end)
        if ok and t ~= nil then return t end
    end
    return FText(s)
end

function newWidget(cls, name)
    local c = StaticFindObject("/Script/UMG." .. cls)
    if not valid(c) then error("class UMG." .. cls .. " not found") end
    hudGen = hudGen + 1
    local w = StaticConstructObject(c, H.tree, FName(string.format("SV_%s_%d", name, hudGen)))
    if not valid(w) then error("could not create a " .. cls) end
    return w
end

-- Puts w on a canvas: anchors a0..a1, offsets {left, top, right, bottom}, alignment; auto = size from the content.
function slotIn(canvas, w, a0, a1, off, align, auto)
    local s = canvas:AddChildToCanvas(w)
    s:SetAnchors({ Minimum = { X = a0[1], Y = a0[2] }, Maximum = { X = a1[1], Y = a1[2] } })
    s:SetAlignment({ X = align[1], Y = align[2] })
    s:SetAutoSize(auto and true or false)
    s:SetOffsets({ Left = off[1], Top = off[2], Right = off[3], Bottom = off[4] })
    return s
end
