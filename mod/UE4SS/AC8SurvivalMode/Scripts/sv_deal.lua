-- sv_deal.lua: THE DEAL, WAR & HAYTHORN's offers between rounds (the user's design of 2026-11-23; the user's dev install
-- only for now). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order after sv_audit: a name another
-- part uses is a global of this mod's Lua state, its own helpers stay local. The whole part is one dev-install-only block
-- (its markers below), which tools/strip_test_only.py takes out of every release zip and tools/dev_only.py out of every
-- TESTER zip (TANACORN ones too): only this header is left there, its settings (CFG.specials.deal) with it.
--
-- How it plays (the user, 2026-11-23):
--   * In a break between rounds, by chance (chance, 35 %), WAR & HAYTHORN's allied F/A-18F (SV_Unit_DealHornet) comes up
--     beside you, with the event zoom onto it (RE_SV_DealCam). War (back seat, does the talking) offers ONE deal, its
--     target coming in the NEXT round: a Podarge transport (SV_Unit_DealPodarge, Mission 12's Norn), a tip-off on an
--     enemy fleet (the Spaceport round's own ships, sv_spaceport.lua SPORT.fleet), or three C-130s carrying goods for
--     Emblem Direct (SV_Unit_DealCargo). The break is held while the deal is on (D.at pushed back).
--   * Everyone answers on AC8's own Yes / No (Mission 8's, tools/survival_events_deal.py: RE_SV_DealAsk, the answer in
--     the flag SV_DealAns), on each player's game; Ctrl+A / Ctrl+X still work. The most votes win; a tie is NO.
--   * YES: the target comes deals_after_s into the next round, paid per target down and a bonus for all of them
--     (pay.*; the host's addCredits, shared in co-op); one left at the round's end, or targets_s on, escapes unpaid.
--   * NO: a 20 % chance War is pissed off (anger.no_chance): 5 Marker Drones (THE DECOY's Spear UAVs, sv_decoy.lua
--     DECOY.angerStart) come in the next round. Nobody answering: 7 of them, a new flight in each of the next 2 rounds.
--   * After the result, the Hornet turns away out of the area (RE_SV_DealLeave) and is taken off leave_s on.
-- Voices: subtitles only, speakers WAR and HAYTHORN; their lines live here while the part is the dev install's.
--
-- Co-op (host-authoritative; AGENTS.md "Guards on what other games send"):
--   "dl|<id>|<kind>|<secs left>|<yes>|<no>"   the host's open vote, to everyone: reliable as it opens and as a vote
--                                             comes in, every resend_s unreliable
--   "vt|<id>|<1 yes / 0 no>"                  a joiner's answer, to the host
--   "dr|<id>|<yes>|<no>|<1 taken / 0 not>"     the host's result, to everyone, reliable
--   The host's lines reach the joiners as its subtitles do, its callouts as "co", the Hornet, the targets and the drones
--   as its spawns do; RE_SV_DealAsk is each game's own (sv_coop.lua KEEP_EVENTS), the camera and the paths are the host's,
--   forwarded.
-- Log lines: `deal: offered in the break after round R (<kind>, ...)`, `deal: the Hornet: ...`, `deal: vote N open ...`,
-- `deal: vote N closed (<why>): YES y, NO n: TAKEN|REFUSED (<rule>)`, `deal: round R: <kind> up ...`, `deal: <kind>:
-- target down ...`, `deal: <kind> over (...)`, `deal: War's anger ...`, `deal: the Hornet taken off (...)`.
-- Test key (dev): Ctrl+H, the deal offered now (a break or a round).
-- DEV ONLY BEGIN (THE DEAL: the user's dev install only; docs/re/DEAL.md)
CFG.specials.deal = {
    enabled = true,
    chance = 0.35,                            -- a break's chance of a deal (the user: 35 %)
    from_round = 1,                           -- the first break that can have one (after this round)
    offer_after_s = 4,                        -- into the break (never while you're in the STORE)
    hold_break = true,                        -- the next round waits for the deal's vote and result
    deals = { podarge = 1, fleet = 1, cargo = 1 },   -- each deal's weight (0: never offered)
    intro_max_s = 14,                         -- the vote opens once War's introduction is said, this long at most
    vote_s = 30,
    allow_change = true,
    resend_s = 2,
    keys = { yes = "A", no = "X", ctrl = true },
    -- (radio_key / radio_text: the radio line War's question is asked with, AC8's Yes / No under it; text only)
    prompt = { enabled = true, event = "RE_SV_DealAsk", flag = "SV_DealAns", question = "SV_Deal_Question",
               radio_key = "SV_Radio_DealAsk", radio_text = "WAR: Do we have a deal? YES or NO.",
               -- ((2026-11-23) the user: "Change Mission 22's entry from 4 to 30 seconds while a Survival run is on")
               -- the stock question War's line names (ms22_01_AWACS_Yes_No_Q, DT_YesNo's NewRow_19, 4 s): its
               -- AnswerTimeLimit answer_s while a run is on (the box shut a little before the vote), the shipped 4 s
               -- back as the run ends or the level goes; in the table and in the Yes / No system's own map
               stock_id = "ms22_01_AWACS_Yes_No_Q", stock_row = "NewRow_19", answer_s = 26,
               rows = "/Game/Mods/SurvivalMode/Data/DT_SV_YesNo.DT_SV_YesNo", table = "/Game/Datatables/YesOrNo/DT_YesNo.DT_YesNo" },
    result_row_s = 8,
    leave_after_s = 7,
    -- (dt_npc: its DT_NPC row, DT_SV_NpcRows' allied F/A-18F, added at the main menu: without it the unit spawns no plane,
    -- "up, 0 aircraft" (the user, 2026-11-23: "War and Haythorns Super Hornet never appears"))
    hornet = { unit = "SV_Unit_DealHornet", name_key = "SV_DealHornet", name = "WAR & HAYTHORN", row = "", dt_npc = "SV_Deal_F18f",
               ahead_m = 1500, side_m = 700, up_m = 150, up_landed_m = 700, leave_s = 25,
               cam_event = "RE_SV_DealCam", cam_after_s = 1.0, leave_event = "RE_SV_DealLeave" },
    targets_after_s = 15,                     -- into the deal's round
    targets_s = 420,                          -- a target still up this long after it came escapes
    watch_s = 2,
    targets = {
        podarge = { units = { "SV_Unit_DealPodarge" }, go = "RE_SV_DealPodargeGo", per = 6000, per_round = 300 },
        cargo = { units = { "SV_Unit_DealCargo" }, go = "RE_SV_DealCargoGo", per = 2000, per_round = 100 },
        -- ((2026-11-23) the user: "you're also supposed to spawn a fleet in a random ocean location") SPORT.fleet's first
        -- groups (a Wasp, 2 Aegis, 2 boats each) moved to a random spot at sea: ring_km from the airfield, open water
        -- (traced: nothing above sea_z + 5 m) clear_km all round it, a random heading; its groups group_km apart, each laid
        -- out as the Spaceport's (Aegis 1.5 km ahead 450 m aside, boats 4 km ahead 350 m aside); no spot in `tries`:
        -- where the Spaceport has them
        fleet = { groups = 2, per = 1200, per_round = 60, ring_km = { 15, 34 }, clear_km = 3, tries = 40, sea_z = 350,
                  group_km = 3, z = { wasp = 0, aegis = 300, boat = 0 },
                  lay = { aegis = { 1.5, 0.45 }, boat = { 4.0, 0.35 } } },
    },
    pay = { all_bonus = 3000, all_bonus_per_round = 150 },
    anger = { no_chance = 0.20, no_drones = 5, silent_drones = 7, silent_rounds = 2, after_s = 20 },
    text = { row_open = "THE DEAL: CTRL+%s YES / CTRL+%s NO   YES %d  NO %d   %s%s", you = "   YOU: %s",
             taken = "THE DEAL: TAKEN (YES %d / NO %d)", refused = "THE DEAL: REFUSED (YES %d / NO %d)",
             callout = "THE DEAL", callout_sub = "WAR & HAYTHORN: YES OR NO?",
             row_target = "THE DEAL: %s %d / %d DOWN",
             name = { podarge = "PODARGE", fleet = "ENEMY FLEET", cargo = "EMBLEM DIRECT CARGO" },
             arrive = { podarge = "PODARGE INBOUND", fleet = "ENEMY FLEET SPOTTED", cargo = "EMBLEM DIRECT CARGO INBOUND" },
             arrive_sub = { podarge = "WAR'S TIP: A PODARGE FROM THE WEST", fleet = "WAR'S TIP: AN ENEMY FLEET AT SEA, %s, %d KM",
                            cargo = "WAR'S TIP: 3 C-130s FROM THE NORTH" },
             paid = "THE DEAL PAID", paid_sub = "+%d ZOLLARS",
             escaped = "THE DEAL: TARGET ESCAPED", escaped_sub = "%d OF %d DOWN",
             anger = "WAR IS ANGRY", anger_sub = "MARKER DRONES INBOUND: SHOOT THEM DOWN" },
    colors = { WAR = { 1.0, 0.48, 0.30 }, HAYTHORN = { 0.62, 0.86, 0.66 } },
    -- (subtitles only, the user: "SPEAKER|text"; each list one exchange or one line; once a run each, as every speaker's)
    lines = {
        intro = { { "HAYTHORN|All pilots, friendly Super Hornet on your wing. Callsign's on the box. Weapons tight on us.",
                    "WAR|Hi! I'm War, back seat. I don't fly. I negotiate." },
                  { "WAR|Hello down there! Well. Over there. Haythorn, which way is down?",
                    "HAYTHORN|Ignore her. WAR & HAYTHORN, friendly F/A-18F, joining you." },
                  { "HAYTHORN|Friendly Hornet coming up on your flank. Don't shoot.",
                    "WAR|I'm the one with the clipboard. Well. Tablet. Same thing." },
                  { "WAR|Is this thing on? It's War. Haythorn's driving, I'm talking.",
                    "HAYTHORN|That's the arrangement." } },
        ask_podarge = { { "WAR|Here's a tip. A Podarge transport crosses your sector next round, slow and full of somebody else's money. Want its route?" },
                        { "WAR|A Podarge is moving cargo through here next round. Big, fat, badly escorted. Yes or no?" } },
        ask_fleet = { { "WAR|I know where an enemy fleet will be next round. Lots of ships, all very sinkable. Want the tip-off?" },
                      { "WAR|Haythorn spotted a fleet forming up off the spaceport. I can point you at it next round. Deal?" } },
        ask_cargo = { { "WAR|Three C-130s with goods for Emblem Direct pass through next round. They don't have to arrive. Interested?" },
                      { "WAR|Emblem Direct has a delivery coming: three C-130s, next round. I hate their shipping department. Yes or no?" } },
        yes = { { "WAR|Deal! It'll be there next round. Don't keep it waiting." },
                { "WAR|That's a yes! Haythorn, write it down.", "HAYTHORN|I'm flying the plane, War." },
                { "WAR|Pleasure doing business. Next round, it's all yours." } },
        no = { { "WAR|No? Fine. Safe and boring. I respect it. I don't like it, but I respect it." },
               { "WAR|No deal. Haythorn, they said no.", "HAYTHORN|I heard." },
               { "WAR|Your loss. The offer's off the table." } },
        tie = { { "WAR|Split crew? Then it's no deal. I don't do coin flips, I do contracts." },
                { "WAR|A tie. Ties go to no. House rules. My house." } },
        none = { { "WAR|Nobody? Really? Silence is rude, pilots. I'll remember this." } },
        angry_no = { { "WAR|You know what? No. Haythorn, send them the drones.", "HAYTHORN|War...", "WAR|Send. Them. The drones." },
                     { "WAR|You turned me down. I don't take that well. Look up next round." } },
        angry_silent = { { "WAR|Ignoring me? Fine. I have friends with lasers. They'll visit you for the next two rounds." } },
        anger_up = { { "WAR|Remember me? Those drones are mine. Shoot them down before they paint you." },
                     { "HAYTHORN|Marker drones inbound. War's still upset." } },
        leave = { { "HAYTHORN|That's our cue. Hornet's breaking off.", "WAR|Bye! I'm waving! ...Can they see me waving?" },
                  { "HAYTHORN|WAR & HAYTHORN leaving the area. Good hunting." },
                  { "WAR|We're off. Haythorn has a thing.", "HAYTHORN|Fuel. The thing is fuel." } },
        arrive_podarge = { { "WAR|There's your Podarge, as promised. Coming in from the west. Go get it." } },
        arrive_fleet = { { "WAR|The fleet's out at sea, right where I said it'd be. Happy hunting." } },
        arrive_cargo = { { "WAR|Emblem Direct's C-130s, from the north, right on time. Make sure they're late." } },
        paid = { { "WAR|Contract fulfilled. The money's in your account. Pleasure, as always." },
                 { "WAR|Told you it'd pay. Money's sent. War out." } },
        escaped = { { "WAR|And it got away. I gave you a perfectly good target, pilots." } },
    },
}
-- (shipped defaults, as if they'd been in CFG when CFG_DEFAULTS was taken: not a setting edited for the leaderboard, not a
-- difference the co-op host sends)
if type(CFG_DEFAULTS) == "table" and type(CFG_DEFAULTS.specials) == "table" and deepCopy then
    CFG_DEFAULTS.specials.deal = deepCopy(CFG.specials.deal)
end
do
    local sc = CFG.hud and CFG.hud.subs
    local dc = type(CFG_DEFAULTS) == "table" and CFG_DEFAULTS.hud and CFG_DEFAULTS.hud.subs
    for who, col in pairs(CFG.specials.deal.colors) do
        if sc and type(sc.colors) == "table" and sc.colors[who] == nil then sc.colors[who] = { col[1], col[2], col[3] } end
        if dc and type(dc.colors) == "table" and dc.colors[who] == nil then dc.colors[who] = { col[1], col[2], col[3] } end
    end
end

DEAL = { V = nil, J = nil, won = nil, nextId = 0 }
do
local function cfg() return CFG.specials.deal end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local MAX_SLOTS = 24
local S = { round = nil, roundAt = nil, rolled = false, clock = 0, last = nil, noHornetSaid = false, sendAt = 0,
            breakRound = nil, breakAt = nil }
DEAL.T, DEAL.ANG = nil, {}                 -- (the host's: the deal's targets; War's anger to come, by round)
local function isHost() return not (COOP and COOP.client and COOP.client()) end   -- (solo: this game is the room)
local function linked() return COOP and COOP.host and COOP.host() and COOP.msg end
local function mySlot() return (COOP and COOP.open and COOP.slot) or 0 end
local function paused() return gamePaused and survivalPC and gamePaused(survivalPC) == true end
local function players()
    local n = 1
    if COOP and COOP.open and COOP.players then
        local ok, l = pcall(COOP.players)
        if ok and type(l) == "table" then n = math.max(1, #l) end
    end
    return n
end
local function count(votes)
    local y, n = 0, 0
    for _, v in pairs(votes) do if v == 1 then y = y + 1 elseif v == 0 then n = n + 1 end end
    return y, n
end
local function mmss(s) s = math.max(0, math.ceil(s)); return string.format("%d:%02d", s // 60, s % 60) end
-- a whole number in [lo, hi], from another game's text; else nil
local function whole(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

-- an exchange (a list of "SPEAKER|text" lines) said whole, one of `opts` none of whose lines are said yet; whether any went
local function say(key, opts)
    if not (SUB and SUB.say) or type(opts) ~= "table" then return false end
    local fresh = {}
    for _, x in ipairs(opts) do if type(x) == "table" and (not SUB.fresh or SUB.fresh(x)) then fresh[#fresh + 1] = x end end
    if #fresh == 0 then log("deal: no " .. key .. " line left to say this run"); return false end
    local any = false
    for _, line in ipairs(fresh[math.random(#fresh)]) do
        local who, text = tostring(line):match("^([^|]+)|(.+)$")
        if who and SUB.say(who, text) then any = true end
    end
    return any
end

---------------------------------------------------------------------------------------------------- the Hornet
local function hornetOff(why)
    local h = cfg().hornet
    S.hornetOffAt = nil
    if not S.hornetUp then return end
    S.hornetUp = false
    local r = "no SV_Recycle"
    if type(SV_Recycle) == "function" then
        local ok, v = pcall(SV_Recycle, h.unit, 1)
        r = ok and tostring(v) or ("error " .. tostring(v))
    end
    log(string.format("deal: the Hornet taken off (%s; SV_Recycle %s)", tostring(why), r))
end
-- (the host) WAR & HAYTHORN's F/A-18F up beside you, flying your way; whether it came up
local function hornetUp()
    local h = cfg().hornet
    if type(SV_Spawn) ~= "function" then return false end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    local at, yaw, kmh = nil, 0, 0
    if pawn and valid(pawn) then
        pcall(function()
            local v, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
            at, yaw = { X = v.X, Y = v.Y, Z = v.Z }, r.Yaw or 0
            local w = pawn:GetVelocity()
            kmh = math.sqrt(w.X * w.X + w.Y * w.Y + w.Z * w.Z) * 0.036
        end)
    end
    local up = (kmh < 120) and num(h.up_landed_m, 700) or num(h.up_m, 150)      -- (on the ground: well above the runway)
    if type(SV_SetText) == "function" then pcall(SV_SetText, h.name_key, h.name) end
    if h.row and h.row ~= "" and type(SV_SetAircraft) == "function" then pcall(SV_SetAircraft, h.unit, h.row) end
    if ALLY and ALLY.unit then ALLY.unit[h.unit] = "air" end         -- (an ally's: no kill credit, as VOID WATCHER 1)
    local okS, r
    if at then
        local a = math.rad(yaw)
        local fx, fy = math.cos(a), math.sin(a)                          -- (ahead; right is (-fy, fx))
        local x = at.X + fx * h.ahead_m * 100 - fy * h.side_m * 100
        local y = at.Y + fy * h.ahead_m * 100 + fx * h.side_m * 100
        okS, r = pcall(SV_Spawn, h.unit, x, y, at.Z + up * 100, yaw % 360)
    else
        okS, r = pcall(SV_Spawn, h.unit)
    end
    r = okS and tonumber(r) or -4
    if r > 0 then
        S.hornetUp, S.camAt = true, S.clock + num(h.cam_after_s, 1)
        log(string.format("deal: the Hornet: %s up%s (%s)", h.unit, at and string.format(" %.1f km ahead of you", h.ahead_m / 1000) or "",
            h.name))
        return true
    end
    if not S.noHornetSaid then
        S.noHornetSaid = true
        log(string.format("deal: the Hornet: %s not spawned (%s): the deal goes on without the plane (logged once a run)",
            h.unit, okS and (SV_ERR and SV_ERR[r] or tostring(r)) or ("error " .. tostring(r))))
    end
    return false
end

---------------------------------------------------------------------------------------------------- the host's vote
local function sendOpen(V, reliable)
    if not linked() then return end
    local y, n = count(V.votes)
    local left = math.max(0, (V.closeAt or S.clock) - S.clock)
    if reliable then COOP.msg(nil, "dl", V.id, V.kind, string.format("%.0f", left), y, n)
    elseif sendTo then sendTo(nil, false, "dl", V.id, V.kind, string.format("%.0f", left), y, n) end
end
local function fire(ev)
    if type(SV_Event) ~= "function" or not ev then return "no SV_Event" end
    local ok, r = pcall(SV_Event, ev)
    return ok and (r == 1 and "fired" or ("NOT fired: " .. tostring(SV_ERR and SV_ERR[r] or r))) or ("error " .. tostring(r))
end
local function aliveOf(unit)
    if type(SV_UnitAlive) ~= "function" then return nil end
    local ok, n = pcall(SV_UnitAlive, unit)
    n = ok and tonumber(n) or nil
    if n == -7 then return 0 end                            -- (SV_NOT_SPAWNED: none up)
    return (n and n >= 0) and n or nil
end
local function fleetReady() return SPORT and type(SPORT.fleet) == "function" and ALLY and ALLY.fleetReady == true end
-- ((2026-11-23, the autotest) SV_UnitAlive counts every object of a unit, its parts too: the Podarge 38, the C-130s 9)
-- A target is a BODY: its objects caught as they're made in its spawn (spawningUnit set, as sv_spaceport.lua's spawn:
-- its ships' objects and turret orders, co-op's ground objects, come with it), the planes among them (LiveAIPlane: the
-- Norn's body, each C-130), else a ship's hull (the one that isn't a turret: sv_spaceport.lua's rule); each one down
-- when it's gone (its address another object's: hard rule 59) or at 0 health.
local CAP = nil
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o) if CAP and #CAP < 200 then CAP[#CAP + 1] = o end end)
local TURRET = { "mk15", "mk41", "mk45", "artillery", "_sam", "aagun", "turret", "vls", "ciws" }
local planeCls
local function isPlane(o)
    if not (planeCls and valid(planeCls)) then planeCls = StaticFindObject("/Script/Live.LiveAIPlane") end
    local ok, r = pcall(function() return o:IsA(planeCls) end)
    return ok and r == true
end
local function isTurret(o)
    local low = nameOf(o):lower()
    for _, k in ipairs(TURRET) do if low:find(k, 1, true) then return true end end
    return false
end
local function bodiesOf(objs)
    local planes, hulls = {}, {}
    for _, o in ipairs(objs) do
        local a = liveAddr and liveAddr(o)
        if a then
            local e = { o = o, a = a, name = nameOf(o) }
            if isPlane(o) then planes[#planes + 1] = e elseif not isTurret(o) then hulls[#hulls + 1] = e end
        end
    end
    if #planes > 0 then return planes end
    return (#hulls > 0) and { hulls[1] } or {}
end
local function bodyUp(e)
    if not (liveAddr and liveAddr(e.o) == e.a and nameOf(e.o) == e.name) then return false end
    local ok, h = pcall(function() return e.o.HealthInternal end)
    return not (ok and type(h) == "number" and h <= 0)
end
local function spawnCaught(u, pose)
    CAP = {}
    spawningUnit = u
    local ok, r
    if pose then ok, r = pcall(SV_Spawn, u, pose.X, pose.Y, pose.Z, pose.yaw) else ok, r = pcall(SV_Spawn, u) end
    spawningUnit = nil
    local objs = CAP
    CAP = nil
    return ok and tonumber(r) or -4, objs
end
-- the deal's units: { unit, ... } for its kind
local function unitsOf(kind)
    local t = cfg().targets[kind] or {}
    if kind ~= "fleet" then return t.units or {} end
    local out, want = {}, {}
    for i, g in ipairs(SPORT.GROUPS or {}) do if i <= num(t.groups, 2) then want[g] = true end end
    for _, sh in ipairs(SPORT.fleet()) do if sh.kind ~= "ford" and want[sh.group] then out[#out + 1] = sh end end
    return out
end
-- the fleet's spot at sea: the ground's height under (x, y) (nil: nothing hit, open water), as sv_solg.lua's
local kis
local function groundZ(x, y)
    if not valid(kis) then kis = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not (valid(kis) and valid(survivalPC)) then return nil end
    local hit, z = {}, nil
    pcall(function()
        kis:LineTraceSingle(survivalPC, { X = x, Y = y, Z = 1000000 }, { X = x, Y = y, Z = -100000 }, 0, true, {}, 0,
            hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    pcall(function() local h = hit.OutHit or hit; local l = h.ImpactPoint or h.Location; if l and l.Z then z = l.Z end end)
    return z
end
local function atSea(x, y, f)
    local top = num(f.sea_z, 350) + 500
    local r = num(f.clear_km, 3) * 100000
    for k = 0, 8 do
        local a = k * math.pi / 4
        local px, py = x + (k == 0 and 0 or math.cos(a) * r), y + (k == 0 and 0 or math.sin(a) * r)
        local z = groundZ(px, py)
        if z and z > top then return false end
    end
    return true
end
local COMPASS = { "NORTH", "NORTH EAST", "EAST", "SOUTH EAST", "SOUTH", "SOUTH WEST", "WEST", "NORTH WEST" }
-- { x, y, yaw, tries, where (compass from the airfield), km } or nil
local function seaSpot()
    local f = cfg().targets.fleet or {}
    local af = AIRFIELD or { X = 1609639.0, Y = -436414.0 }
    local lo, hi = num((f.ring_km or {})[1], 15), num((f.ring_km or {})[2], 34)
    for t = 1, math.max(1, math.floor(num(f.tries, 40))) do
        local a, d = math.random() * 2 * math.pi, (lo + (hi - lo) * math.random()) * 100000
        local x, y = af.X + math.cos(a) * d, af.Y + math.sin(a) * d
        if atSea(x, y, f) then
            local deg = (math.deg(math.atan(x - af.X, -(y - af.Y))) + 360) % 360     -- (north is -y)
            return { x = x, y = y, yaw = math.random() * 360, tries = t, where = COMPASS[math.floor((deg + 22.5) / 45) % 8 + 1],
                     km = math.floor(d / 100000 + 0.5) }
        end
    end
    return nil
end
-- each fleet ship's pose round the spot: a group's Wasp at its centre, its Aegis and boats ahead either side
local function fleetPoses(spot, units)
    local f = cfg().targets.fleet or {}
    local yr = math.rad(spot.yaw)
    local ux, uy = math.cos(yr), math.sin(yr)                  -- (ahead; aside is (-uy, ux))
    local out, gi, side = {}, {}, {}
    local groups = {}
    for _, sh in ipairs(units) do
        if not gi[sh.group] then groups[#groups + 1] = sh.group; gi[sh.group] = #groups end
    end
    for _, sh in ipairs(units) do
        local g = gi[sh.group]
        local off = (g - (#groups + 1) / 2) * num(f.group_km, 3) * 100000   -- (the groups abreast)
        local cx, cy = spot.x - uy * off, spot.y + ux * off
        local ahead, aside = 0, 0
        local lay = (f.lay or {})[sh.kind]
        if lay then
            local key = sh.group .. sh.kind
            side[key] = (side[key] or 0) + 1
            ahead, aside = num(lay[1], 0) * 100000, num(lay[2], 0) * 100000 * (side[key] % 2 == 1 and 1 or -1)
        end
        out[sh.unit] = { X = cx + ux * ahead - uy * aside, Y = cy + uy * ahead + ux * aside,
                         Z = num((f.z or {})[sh.kind], 0), yaw = spot.yaw }
    end
    return out
end
-- a deal to offer: by the weights, the fleet only when its ships' rows are in
local function pickDeal()
    local c, bag, sum = cfg(), {}, 0
    for _, k in ipairs({ "podarge", "fleet", "cargo" }) do
        local w = num(c.deals[k], 0)
        if w > 0 and (k ~= "fleet" or fleetReady()) then bag[#bag + 1], sum = { k, w }, sum + w end
    end
    if sum <= 0 then return nil end
    local r = math.random() * sum
    for _, e in ipairs(bag) do r = r - e[2]; if r <= 0 then return e[1] end end
    return bag[#bag][1]
end

-- (the host) the offer: the Hornet up, War's introduction; the vote opens after it
local function offer(kind, why)
    local c = cfg()
    DEAL.nextId = DEAL.nextId + 1
    local target = D.round + 1                -- (the NEXT round: in a break D.round is the one just cleared)
    local V = { id = DEAL.nextId, round = target, kind = kind, phase = "intro", at = S.clock, votes = {} }
    DEAL.V = V
    S.rolled = true
    local plane = hornetUp()
    say("intro", c.lines.intro)
    local left = (SUB and SUB.left) and num(SUB.left(D.now or S.clock), 0) or 0
    V.openAt = S.clock + math.min(c.intro_max_s, left + 0.5)
    log(string.format("deal: offered in the break after round %d (%s, %s): its target in round %d; the Hornet %s, the vote opens in %.0f s",
        D.round, tostring(kind), why, target, plane and "up" or "not up", V.openAt - S.clock))
end

local function openVote(V)
    local c = cfg()
    say("ask", c.lines["ask_" .. V.kind] or {})
    V.phase, V.closeAt = "open", S.clock + c.vote_s
    hudCallout(c.text.callout, c.text.callout_sub)
    log(string.format("deal: vote %d open for %d s (%d player%s)", V.id, c.vote_s, players(), players() == 1 and "" or "s"))
    sendOpen(V, true)
    S.sendAt = S.clock + c.resend_s
end

-- War's anger: n drones in each of `rounds` rounds from `from`
local function angerLater(from, n, rounds, why)
    for k = 0, math.max(1, rounds) - 1 do DEAL.ANG[#DEAL.ANG + 1] = { round = from + k, n = n, why = why } end
    log(string.format("deal: War's anger (%s): %d Marker Drones in round%s %d%s", why, n, rounds > 1 and "s" or "", from,
        rounds > 1 and string.format(" to %d", from + rounds - 1) or ""))
end

local function closeVote(V, why)
    local c = cfg()
    local y, n = count(V.votes)
    local taken = y > n
    local silent = y == 0 and n == 0
    local rule = silent and "nobody answered" or (y == n) and "a tie is no" or "the most votes"
    V.phase, V.yes, V.no, V.taken, V.resultUntil = "closed", y, n, taken, S.clock + c.result_row_s
    log(string.format("deal: vote %d closed (%s): YES %d, NO %d: %s (%s)", V.id, why, y, n, taken and "TAKEN" or "REFUSED", rule))
    if linked() then COOP.msg(nil, "dr", V.id, y, n, taken and 1 or 0) end
    local a = c.anger
    if taken then
        say("yes", c.lines.yes)
        DEAL.T = { kind = V.kind, round = V.round, state = "due", id = V.id }
    elseif silent then
        say("angry_silent", c.lines.angry_silent)
        angerLater(V.round, math.floor(num(a.silent_drones, 7)), math.floor(num(a.silent_rounds, 2)), "nobody answered")
    else
        say((y == n) and "tie" or "no", (y == n) and c.lines.tie or c.lines.no)
        local roll = math.random()
        if roll < num(a.no_chance, 0.2) then
            V.angry = true
            angerLater(V.round, math.floor(num(a.no_drones, 5)), 1, string.format("refused, rolled %.2f", roll))
        else
            log(string.format("deal: refused; War lets it go (rolled %.2f, chance %.2f)", roll, num(a.no_chance, 0.2)))
        end
    end
    V.leaveAt = S.clock + c.leave_after_s
end
-- (the host) a vote: slot's answer (1 yes, 0 no) to the open vote id
local function record(slot, id, v)
    local V = DEAL.V
    if not (V and V.phase == "open" and V.id == id) then return false end
    if V.votes[slot] ~= nil and not cfg().allow_change then return false end
    if V.votes[slot] == v then return true end
    V.votes[slot] = v
    log(string.format("deal: player %d votes %s", slot + 1, v == 1 and "YES" or "NO"))
    sendOpen(V, true)
    return true
end

---------------------------------------------------------------------------------------------------- the targets
local function recycle(unit)
    if type(SV_Recycle) ~= "function" then return "no SV_Recycle" end
    local ok, v = pcall(SV_Recycle, unit, 1)
    return ok and tostring(v) or ("error " .. tostring(v))
end
local function payFor(t, n) return math.max(0, math.floor((num(t.per, 0) + num(t.per_round, 0) * (D.round or 0)) * n + 0.5)) end
local function targetsUp(T)
    local c = cfg()
    local units = unitsOf(T.kind)
    T.units, T.total, T.down, T.paid = {}, 0, 0, 0
    if T.kind == "fleet" and not fleetReady() then
        log("deal: the fleet's ships' rows aren't in (ALLY.fleetReady): no fleet this time")
        T.state = "done"
        return
    end
    if T.kind == "fleet" and D.special and D.special.kind == "spaceport" then
        log("deal: the fleet's ships are the Spaceport round's: the tip-off waits for the next round")
        T.round = D.round + 1
        T.state = "due"
        return
    end
    local said = {}
    T.bodies = {}
    local poses, spot = {}, nil
    if T.kind == "fleet" then
        spot = seaSpot()
        if spot then
            poses = fleetPoses(spot, units)
            T.where, T.km = spot.where, spot.km
            log(string.format("deal: the fleet's spot at sea: (%.1f, %.1f) km, %s of the airfield %d km, heading %.0f (try %d)",
                spot.x / 100000, spot.y / 100000, spot.where, spot.km, spot.yaw, spot.tries))
        else
            log("deal: no open water found for the fleet: where the Spaceport has its ships")
            T.where, T.km = "OFF THE SPACEPORT", 0
        end
        local l = {}
        for _, sh in ipairs(units) do l[#l + 1] = sh.unit end
        units = l
    end
    for _, u in ipairs(units) do
        local r, objs = spawnCaught(u, poses[u])
        local b = (r > 0) and bodiesOf(objs) or {}
        said[#said + 1] = string.format("%s %s", u, r > 0 and string.format("%d objects, %d bod%s", r, #b, #b == 1 and "y" or "ies")
            or ("not spawned: " .. tostring(SV_ERR and SV_ERR[r] or r)))
        if r > 0 then
            T.units[#T.units + 1] = u
            if #b == 0 then b = { { unit = u } } end          -- (no body caught: the unit's own count, all of it down)
            for _, e in ipairs(b) do e.unit = u; T.bodies[#T.bodies + 1] = e end
        end
    end
    T.total = #T.bodies
    T.state, T.at, T.goAt, T.watchAt = (T.total > 0) and "up" or "done", S.clock, S.clock + 1.0, S.clock + 3
    log(string.format("deal: round %d: %s up (%d): %s", D.round, T.kind, T.total, table.concat(said, ", ")))
    if T.total > 0 then
        local sub = c.text.arrive_sub[T.kind] or ""
        if T.kind == "fleet" then
            sub = T.km and T.km > 0 and string.format(sub, T.where or "?", T.km) or "WAR'S TIP: AN ENEMY FLEET OFF THE SPACEPORT"
        end
        hudCallout(c.text.arrive[T.kind] or "THE DEAL", sub)
        say("arrive", c.lines["arrive_" .. T.kind] or {})
    end
end
local function targetsOver(T, why)
    local c = cfg()
    T.state = "done"
    local left = T.total - T.down
    for _, u in ipairs(T.units or {}) do recycle(u) end
    if T.total > 0 and T.down >= T.total then
        local bonus = math.floor(num(c.pay.all_bonus, 0) + num(c.pay.all_bonus_per_round, 0) * (D.round or 0) + 0.5)
        if bonus > 0 then addCredits(bonus, "the deal's bonus (" .. T.kind .. " all down)") end
        local sum = T.paid + bonus
        hudCallout(c.text.paid, string.format(c.text.paid_sub, specialPay and specialPay(sum) or sum))
        say("paid", c.lines.paid)
    elseif T.total > 0 then
        hudCallout(c.text.escaped, string.format(c.text.escaped_sub, T.down, T.total))
        say("escaped", c.lines.escaped)
    end
    if LB and LB.special then pcall(LB.special, "deal_" .. T.kind, T.total > 0 and T.down >= T.total, S.clock - (T.at or S.clock)) end
    log(string.format("deal: %s over (%s): %d of %d down, %d left (taken off unpaid), +%d paid", T.kind, why, T.down, T.total, left, T.paid))
end
local function targetsTick()
    local T, c = DEAL.T, cfg()
    if not T or T.state == "done" then DEAL.T = (T and T.state == "done") and nil or T; return end
    local fighting = D.state ~= "wait" and D.round == T.round
    if T.state == "due" then
        if D.round > T.round then log(string.format("deal: round %d passed without its %s: dropped", T.round, T.kind)); DEAL.T = nil; return end
        if fighting then
            S.roundAt = S.roundAt or S.clock
            if S.clock - S.roundAt >= num(c.targets_after_s, 15) then targetsUp(T) end
        end
        return
    end
    if T.goAt and S.clock >= T.goAt then
        T.goAt = nil
        local go = (c.targets[T.kind] or {}).go
        if go then log(string.format("deal: %s onto its route (%s %s)", T.kind, go, fire(go))) end
    end
    if not fighting then targetsOver(T, "the round's over"); return end
    if S.clock - T.at >= num(c.targets_s, 420) then targetsOver(T, "its time ran out"); return end
    if S.clock < T.watchAt then return end
    T.watchAt = S.clock + math.max(1, num(c.watch_s, 2))
    local t = c.targets[T.kind] or {}
    for _, e in ipairs(T.bodies) do
        if not e.down then
            local up
            if e.o then up = bodyUp(e) else up = (aliveOf(e.unit) or 1) > 0 end
            if not up then
                e.down, T.down = true, T.down + 1
                local p = payFor(t, 1)
                if p > 0 then addCredits(p, "the deal's " .. T.kind .. " target down"); T.paid = T.paid + p end
                log(string.format("deal: %s: a target down (%s %s; %d of %d), +%d", T.kind, e.unit, e.name or "(its unit)", T.down, T.total, p))
            end
        end
    end
    if T.down >= T.total then targetsOver(T, "all down") end
end
local function angerTick()
    local c = cfg()
    if D.state == "wait" or #DEAL.ANG == 0 then return end
    S.roundAt = S.roundAt or S.clock
    for i = #DEAL.ANG, 1, -1 do
        local A = DEAL.ANG[i]
        if A.round < D.round then
            table.remove(DEAL.ANG, i)
            log(string.format("deal: War's anger for round %d dropped (passed)", A.round))
        elseif A.round == D.round and S.clock - S.roundAt >= num(c.anger.after_s, 20) then
            if D.special and D.special.kind == "decoy" then
                A.round = D.round + 1
                log("deal: War's anger waits: this round is THE DECOY's own")
            elseif not (DECOY and DECOY.angerStart) then
                table.remove(DEAL.ANG, i)
                log("deal: War's anger dropped: no DECOY part")
            elseif DECOY.A then
                A.round = D.round + 1
                log("deal: War's anger waits: her last drones are still up")
            else
                table.remove(DEAL.ANG, i)
                if DECOY.angerStart(A.n, A.why) then
                    hudCallout(c.text.anger, c.text.anger_sub)
                    say("anger_up", c.lines.anger_up)
                end
            end
        end
    end
end

local function hostTick()
    local c = cfg()
    if D.round ~= S.round then S.round, S.roundAt, S.rolled = D.round, nil, false end
    if not S.roundAt and D.state ~= "wait" then S.roundAt = S.clock end
    local V = DEAL.V
    if V and V.phase == "intro" and S.clock >= V.openAt then openVote(V)
    elseif V and V.phase == "open" then
        local y, n = count(V.votes)
        if S.clock >= V.closeAt then closeVote(V, "the clock ran out")
        elseif y + n >= players() then closeVote(V, "everyone answered")
        elseif S.clock >= S.sendAt then S.sendAt = S.clock + c.resend_s; sendOpen(V, false) end
    elseif V and V.phase == "closed" and V.leaveAt and S.clock >= V.leaveAt then
        V.leaveAt = nil
        if S.hornetUp then
            say("leave", c.lines.leave)
            log(string.format("deal: the Hornet turns away (%s %s)", c.hornet.leave_event, fire(c.hornet.leave_event)))
            S.hornetOffAt = S.clock + c.hornet.leave_s
        end
    end
    if S.camAt and S.clock >= S.camAt then
        S.camAt = nil
        log(string.format("deal: the event zoom onto the Hornet (%s %s)", c.hornet.cam_event, fire(c.hornet.cam_event)))
    end
    if S.hornetOffAt and S.clock >= S.hornetOffAt then hornetOff("its leave_s after it turned away") end
    -- the break held while the deal's on (the next round's start pushed back; D.at is the round clock's)
    if c.hold_break and V and D.state == "wait" and D.at and D.now and (V.phase ~= "closed" or (V.leaveAt and S.clock < V.leaveAt)) then
        local need = (V.phase == "intro" and (V.openAt - S.clock) + c.vote_s or V.phase == "open" and (V.closeAt - S.clock)
            or (V.leaveAt - S.clock)) + 4
        if D.at < D.now + need then
            if not V.heldSaid then V.heldSaid = true; log(string.format("deal: the break held for the deal (%.0f s more)", D.now + need - D.at)) end
            D.at = D.now + need
        end
    end
    pcall(targetsTick)
    pcall(angerTick)
    -- the offer: once a break, by chance, offer_after_s into it, never in the STORE, never with a deal or its target on
    if D.state ~= "wait" then S.breakRound, S.breakAt = nil, nil; return end
    if S.breakRound ~= D.round then S.breakRound, S.breakAt, S.rolled = D.round, S.clock, false end
    if S.rolled or (V and V.phase ~= "closed") or DEAL.T then return end
    if D.round < num(c.from_round, 1) or S.clock - S.breakAt < c.offer_after_s then return end
    if SPC and SPC.storeShut and not SPC.storeShut(D.now or S.clock) then return end
    S.rolled = true
    local roll = math.random()
    if roll >= num(c.chance, 0.35) then
        log(string.format("deal: the break after round %d: no offer (rolled %.2f, chance %.2f)", D.round, roll, num(c.chance, 0.35)))
        return
    end
    local kind = pickDeal()
    if not kind then log("deal: no deal to offer (every weight 0)"); return end
    offer(kind, string.format("chance %.2f, rolled %.2f", num(c.chance, 0.35), roll))
end
---------------------------------------------------------------------------------------------------- a joiner's view
local function joinerTick()
    local J = DEAL.J
    if J and J.phase == "open" and S.clock > J.closeAt + 10 then
        log(string.format("deal: vote %d: no result from the host 10 s after its close: dropped", J.id))
        DEAL.J = nil
    end
end
-- (a joiner) the host's "dl" / "dr" (sv_coop_migration.lua hands them here)
function DEAL.fromHost(k, f)
    if not D then return end
    local id = whole(f[2], 1, 1000000)
    if not id then return end
    if k == "dl" then
        local kind = tostring(f[3] or "")                -- (a special's kind: a short word, never cut to one)
        local left = tonumber(f[4])
        local y, n = whole(f[5], 0, MAX_SLOTS), whole(f[6], 0, MAX_SLOTS)
        if not (#kind <= 16 and kind:match("^[%w_]+$") and left and left == left and left >= 0 and left <= 120 and y and n) then return end
        local J = DEAL.J
        if not (J and J.id == id) then
            J = { id = id, kind = kind, phase = "open" }
            DEAL.J = J
            log(string.format("deal: the host's vote %d open (%s, %.0f s left)", id, kind, left))   -- (its callout: the host's "co")
        end
        if J.phase == "open" then J.closeAt, J.yes, J.no = S.clock + left, y, n end
    elseif k == "dr" then
        local y, n, t = whole(f[3], 0, MAX_SLOTS), whole(f[4], 0, MAX_SLOTS), whole(f[5], 0, 1)
        if not (y and n and t) then return end
        local J = DEAL.J
        if not J or J.id ~= id then J = { id = id }; DEAL.J = J end
        if J.phase == "closed" then return end
        J.phase, J.yes, J.no, J.taken, J.resultUntil = "closed", y, n, t == 1, S.clock + cfg().result_row_s
        log(string.format("deal: the host's vote %d closed: YES %d, NO %d: %s", id, y, n, J.taken and "TAKEN" or "REFUSED"))
    end
end
-- (the host) a joiner's "vt"
function DEAL.onVote(from, f)
    if not (COOP and COOP.slotOk and COOP.slotOk(from)) or from == mySlot() then return end
    local id, v = whole(f[2], 1, 1000000), whole(f[3], 0, 1)
    if id and v then record(from, id, v) end
end

-- this player's answer (the keys): 1 yes, 0 no
function DEAL.vote(v)
    if not D then return end
    if isHost() then
        local V = DEAL.V
        if V and V.phase == "open" then record(mySlot(), V.id, v) end
        return
    end
    local J = DEAL.J
    if not (J and J.phase == "open" and S.clock <= J.closeAt) then return end
    if J.mine ~= nil and not cfg().allow_change then return end
    if J.mine == v then return end
    J.mine = v
    if COOP and COOP.msg then COOP.msg(0, "vt", J.id, v) end
    log(string.format("deal: your vote on %d: %s (sent to the host)", J.id, v == 1 and "YES" or "NO"))
end

-- AC8's own Yes / No on this game: asked once a vote, its answer read back (cfg().prompt)
local ASK = { id = nil }
local function promptTick()
    local p = cfg().prompt
    if not (p and p.enabled ~= false and type(SV_Event) == "function") then return end
    local V = isHost() and DEAL.V or DEAL.J
    local open = V and V.phase == "open"
    if not open then ASK.id = nil; return end
    if ASK.id ~= V.id then                               -- (a new vote: asked)
        if p.radio_key and type(SV_SetText) == "function" then pcall(SV_SetText, p.radio_key, p.radio_text or "") end
        local r = SV_Event(p.event)
        ASK.id, ASK.sawZero, ASK.done = V.id, false, false
        log(string.format("deal: AC8's Yes / No asked for vote %d (%s %s)", V.id, p.event, r == 1 and "fired" or ("NOT fired: " .. tostring(SV_ERR and SV_ERR[r] or r))))
        return
    end
    if ASK.done then return end
    local a = (svFlags and svFlags() or {})[p.flag]
    if a == nil then return end
    if a == 0 then ASK.sawZero = true; return end        -- (asked, no answer yet: an old answer never read as this one's)
    if not ASK.sawZero then return end
    ASK.done = true
    if a == 1 or a == 2 then
        log(string.format("deal: you answered %s on AC8's Yes / No (vote %d)", a == 1 and "YES" or "NO", V.id))
        DEAL.vote(a == 1 and 1 or 0)
    else
        log(string.format("deal: no answer on AC8's Yes / No (vote %d): silent", V.id))
    end
end
DEAL.promptTick = promptTick

-- Mission 22's question's time while a run is on (cfg().prompt.stock_*, answer_s), put back after
local YT = { on = false, orig = nil, map = nil }
local function sameId(v, want)
    local ok, sv = pcall(function() return v:ToString() end)
    if not ok then sv = tostring(v) end
    return sv == want
end
-- the Yes / No system's own entry for the question (LiveYesNoRadioWorldSubsystem.YesNoDataMap_), or nil and why
local function ynEntry(id)
    local ss = FindFirstOf and FindFirstOf("LiveYesNoRadioWorldSubsystem")
    if not (ss and valid(ss)) then return nil, "no Yes / No system" end
    local found, n = nil, 0
    local ok, err = pcall(function()
        ss.YesNoDataMap_:ForEach(function(k, v)
            n = n + 1
            local okK, key = pcall(function() return k:get() end)
            if okK and sameId(key, id) then found = v:get() end
        end)
    end)
    if not ok then return nil, "its map not read: " .. tostring(err) end
    if not found then return nil, string.format("not in its map (%d entries)", n) end
    return found, n
end
-- (findOnly: from the world's construction, where nothing may be loaded: the table only if it's in memory already)
function DEAL.yesnoTime(on, findOnly, why)
    local p = cfg().prompt
    if not (p and p.stock_id and p.stock_row) or on == YT.on then return end
    local path = "/Game/Datatables/YesOrNo/DT_YesNo.DT_YesNo"
    local dt = StaticFindObject(path)
    if not (dt and valid(dt)) then dt = (not findOnly) and loadObject(path) or nil end
    if not dt then
        if findOnly then log("deal: DT_YesNo isn't loaded as Survival's world is made: the answer time at the run's start") end
        return
    end
    local said = {}
    if dt then
        local _, r = dtCall(dt, "FindRow", p.stock_row)
        if r ~= nil and sameId(r.YesNoID, p.stock_id) then
            -- ((2026-11-23, the 1st try: read back 4.0 after RemoveRow / AddRow) every step logged; the field set on
            -- what FindRow gives (a live view of the row, if UE4SS gives one) and through RemoveRow / AddRow
            if on then YT.orig = YT.orig or r.AnswerTimeLimit end
            local want = on and num(p.answer_s, 26) or (YT.orig or 4)
            local okSet, eSet = pcall(function() r.AnswerTimeLimit = want end)
            local _, live = dtCall(dt, "FindRow", p.stock_row)
            local step = string.format("FindRow gave a %s; set %s; read again %s", type(r), okSet and "ok" or ("failed: " .. tostring(eSet)),
                tostring(live and live.AnswerTimeLimit))
            if not (live and math.abs((tonumber(live.AnswerTimeLimit) or 0) - want) < 0.01) then
                local okR, rr = dtCall(dt, "RemoveRow", p.stock_row)
                local _, gone = dtCall(dt, "FindRow", p.stock_row)
                local okA, ra = dtCall(dt, "AddRow", p.stock_row, r)
                step = step .. string.format("; RemoveRow %s %s, the row %s after; AddRow %s %s", tostring(okR), tostring(rr),
                    gone == nil and "gone" or "STILL THERE", tostring(okA), tostring(ra))
            end
            local _, back = dtCall(dt, "FindRow", p.stock_row)
            said[#said + 1] = string.format("DT_YesNo %s %s s (%s)", p.stock_row, tostring(back and back.AnswerTimeLimit), step)
        else
            said[#said + 1] = "DT_YesNo's " .. p.stock_row .. " isn't " .. p.stock_id .. ": not changed"
        end
    else
        said[#said + 1] = "DT_YesNo not loaded"
    end
    local e, why = ynEntry(p.stock_id)
    if e then
        local ok = pcall(function()
            if on then YT.mapOrig = YT.mapOrig or e.AnswerTimeLimit end
            e.AnswerTimeLimit = on and num(p.answer_s, 26) or (YT.mapOrig or 4)
        end)
        local okB, b = pcall(function() return e.AnswerTimeLimit end)
        said[#said + 1] = string.format("the Yes / No system's map %s (%d entries)", ok and (tostring(okB and b or "?") .. " s") or "not written", why)
    else
        said[#said + 1] = "the Yes / No system's map: " .. tostring(why)
    end
    YT.on = on
    log(string.format("deal: %s's answer time %s (%s): %s", p.stock_id, on and "lengthened for the run" or "back to the shipped",
        tostring(why or "the run"), table.concat(said, "; ")))
end
-- (sv_main.lua, at the main menu: before the level loads, as the DT_NPC rows) the question's row (DT_SV_YesNo) into
-- the game's DT_YesNo: AC8's Yes / No shows only a question it has a row for (the autotest of 2026-11-23)
function DEAL.setup()
    local p = cfg().prompt
    if DEAL.setupDone or not (p and p.enabled ~= false) then return end
    if not (gameInstance and gameInstance()) then return end
    DEAL.setupTries = (DEAL.setupTries or 0) + 1
    local mine, game = loadObject(p.rows), loadObject(p.table)
    if not (mine and game) then
        if DEAL.setupTries >= 20 then
            DEAL.setupDone, DEAL.rowOk = true, false
            log("deal: DT_YesNo or DT_SV_YesNo didn't load: AC8's Yes / No won't show (the keys still vote)")
        end
        return
    end
    DEAL.setupDone = true
    pin(mine, nameOf(mine)); pin(game, nameOf(game))
    local _, have = dtCall(game, "FindRow", p.question)
    if have == nil then
        local _, r = dtCall(mine, "FindRow", p.question)
        if r ~= nil then dtCall(game, "AddRow", p.question, r); _, have = dtCall(game, "FindRow", p.question) end
    end
    DEAL.rowOk = have ~= nil
    log(string.format("deal: the question's row %s %s", p.question, DEAL.rowOk and "in DT_YesNo" or "NOT added: AC8's Yes / No won't show"))
    -- the Hornet's plane: its DT_NPC row (as ESC.setup's escorts')
    local hr = cfg().hornet.dt_npc
    local npc, rows = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    if type(hr) == "string" and npc and rows then
        local _, h = dtCall(npc, "FindRow", hr)
        if h == nil then
            local _, r = dtCall(rows, "FindRow", hr)
            if r ~= nil then dtCall(npc, "AddRow", hr, r); _, h = dtCall(npc, "FindRow", hr) end
        end
        DEAL.hornetRowOk = h ~= nil
        log(string.format("deal: the Hornet's row %s %s", hr, DEAL.hornetRowOk and "in DT_NPC" or "NOT added: its unit will spawn no plane"))
    else
        log("deal: the Hornet's row: DT_NPC or DT_SV_NpcRows didn't load")
    end
end

-- the NEXT row (sv_hud.lua): the offer while it's open, the result a little after; else nil
function DEAL.row()
    local c = cfg()
    if not (D and c.enabled) then return nil end
    local T = isHost() and DEAL.T
    if T and T.state == "up" then return string.format(c.text.row_target, c.text.name[T.kind] or T.kind, T.down, T.total) end
    local V = isHost() and DEAL.V or DEAL.J
    if not V then return nil end
    if V.phase == "open" then
        local y, n, mine
        if isHost() then y, n = count(V.votes); mine = V.votes[mySlot()] else y, n, mine = V.yes or 0, V.no or 0, V.mine end
        return string.format(c.text.row_open, c.keys.yes, c.keys.no, y, n, mmss((V.closeAt or S.clock) - S.clock),
            mine ~= nil and string.format(c.text.you, mine == 1 and "YES" or "NO") or "")
    elseif V.phase == "closed" and V.resultUntil and S.clock < V.resultUntil then
        return string.format(V.taken and c.text.taken or c.text.refused, V.yes or 0, V.no or 0)
    end
    return nil
end

---------------------------------------------------------------------------------------------------- the tick and the keys
-- (sv_main.lua's test ticks, every game, in a run) the clock holds while the game is paused
function DEAL.tick(clock)
    if not cfg().enabled then return end
    if not D then
        if YT.on then pcall(DEAL.yesnoTime, false, false, "the run ended") end
        if S.hornetUp then S.hornetUp = false end
        DEAL.V, DEAL.J, DEAL.T, DEAL.ANG, S.round, S.noHornetSaid = nil, nil, nil, {}, nil, false
        S.last, S.D, S.hornetOffAt, S.camAt = nil, nil, nil, nil
        return
    end
    if S.D ~= D then                                    -- (a new run: nothing of the last one's carried over)
        if S.D ~= nil and (DEAL.V or DEAL.J or DEAL.T) then log("deal: a new run: the last run's deal dropped") end
        S.D, DEAL.V, DEAL.J, DEAL.T, DEAL.ANG, S.round, S.hornetOffAt, S.camAt = D, nil, nil, nil, {}, nil, nil, nil
        if S.hornetUp then hornetOff("a new run") end
    end
    if not YT.on then pcall(DEAL.yesnoTime, true, false, "the run started") end
    local dt = S.last and math.max(0, math.min(1, clock - S.last)) or 0
    S.last = clock
    if not paused() then S.clock = S.clock + dt end
    if isHost() then hostTick() else joinerTick() end
    pcall(promptTick)
end
-- (the test key) the deal offered now, whatever the round
function DEAL.offerNow()
    if not D then log("deal: Ctrl+H outside a Survival run"); return end
    if not isHost() then log("deal: Ctrl+H on a joiner: the host offers the deal"); return end
    if DEAL.V and DEAL.V.phase ~= "closed" then log("deal: Ctrl+H: a deal is on already"); return end
    S.round, S.rolled = D.round, true
    offer(pickDeal() or "podarge", "Ctrl+H")
end

local function bind(name, fn)
    local k = cfg().keys
    if type(RegisterKeyBind) ~= "function" or not Key or Key[name] == nil then
        log("deal: key " .. tostring(name) .. " not bound (no such key in UE4SS's Key table)")
        return false
    end
    local key = Key[name]
    if k.ctrl and TEST_KEYS then
        if TEST_KEYS[key] then log(string.format("test: Ctrl+%s is bound twice: both run on a press (%s, sv_deal.lua)", name, tostring(TEST_KEYS[key]))) end
        TEST_KEYS[key] = "sv_deal.lua's vote"
    end
    local mods = (k.ctrl and ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    return pcall(RegisterKeyBind, key, mods, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then log("deal: key error " .. tostring(err)) end
        end)
    end)
end
if cfg().enabled then
    bind(cfg().keys.yes, function() DEAL.vote(1) end)
    bind(cfg().keys.no, function() DEAL.vote(0) end)
    if testKey then testKey("H", "sv_deal.lua's offer now", DEAL.offerNow) end
end
if TEST_TICKS then TEST_TICKS[#TEST_TICKS + 1] = { name = "deal", fn = function(now) DEAL.tick(now) end } end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the deal's answer time"] = function() if YT.on then pcall(DEAL.yesnoTime, false, false, "the level dropped") end end
end
-- ((2026-11-23, the autotest: the table at 26 s from the run's start, the box still shut at 4 s) the Yes / No system
-- copies DT_YesNo as the level's world is made: the time set as Survival's world is constructed (before that)
pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    if not cfg().enabled then return end
    local n = nameOf(w)
    if n:find("PL_SurvivalMode", 1, true) and not YT.on then
        local ok, err = pcall(DEAL.yesnoTime, true, true, "as Survival's world is made")
        if not ok then log("deal: the answer time at the world's making: error " .. tostring(err)) end
    end
end)
end
-- DEV ONLY END
