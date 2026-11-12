-- sv_deal.lua: THE DEAL, a Yes / No vote that steers a special round (the user's design of 2026-11-11; the user's dev
-- install only for now). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order after sv_audit (its
-- addCredits wrap is the outermost): a name another part uses is a global of this mod's Lua state, its own helpers stay
-- local. The whole part is one dev-install-only block (its markers below), which tools/strip_test_only.py takes out of every release zip and
-- tools/dev_only.py out of every TESTER zip (TANACORN ones too): only this header is left there, its settings
-- (CFG.specials.deal) with it.
--
-- How it plays (the user, 2026-11-11 / 2026-11-12):
--   * By chance, on some specials only (CFG.specials.deal.kinds: a chance per special kind; a kind not listed never gets
--     it), offer_after_s into the special's round, WAR & HAYTHORN's allied F/A-18F joins the players (War in the back
--     seat, no flight experience, does the talking; Haythorn flies). War offers a deal: the special goes on with higher
--     stakes (YES) or as it is (NO).
--   * Every player votes, solo too: Ctrl+A YES, Ctrl+X NO (CFG.specials.deal.keys; UE4SS's binds are keyboard only), for
--     vote_s (30 s). The NEXT row shows the offer, the tally and the clock. The vote closes when everyone has answered or
--     the clock runs out. The most votes win; a tie is NO; no answer isn't counted (nobody answering: NO).
--   * War calls the result, then the Hornet leaves, with subtitles saying so; it's taken off leave_s after
--     (SV_Recycle: on a timer, hard rule 4, not at a path's end).
--   * A deal taken pays extra (the user: "It'll pay extra cash"): when the round is cleared, each game is paid the
--     zollars it earned from the deal's close to the clear again x (pay.kills_x - 1), its own (COOP.payOwn), and the
--     host's bonus (pay.bonus + pay.bonus_per_round x the round) goes to everyone (addCredits: co-op's "cr").
--     What YES does to the round itself is the user's call still (CFG.specials.deal.stakes: none yet).
-- Voices: subtitles only (the user), speakers WAR and HAYTHORN. Their lines live here while the part is the dev
-- install's; when it ships they move to config/subtitles.ini (python -I tools/subtitles.py merge).
-- The Yes / No prompt is Survival's own (the HUD's NEXT row and two key binds). The game's own Yes / No radio prompt
-- (LiveActivateYesNoExecution, Mission 8; ULiveYesNoRadioWorldSubsystem) is still to be read from the game's files: it
-- may replace the keys once its answer can be read back (docs/re/DEAL.md 3).
-- The Hornet: CFG.specials.deal.hornet.unit, an allied world-data unit with its name key, still to be built
-- (tools/survival_events*.py, as VOID WATCHER 1's): until a build has it, SV_Spawn answers "no such unit" and the deal
-- goes on without the plane (logged once a run).
--
-- Co-op (host-authoritative; AGENTS.md "Guards on what other games send"):
--   "dl|<id>|<kind>|<secs left>|<yes>|<no>"   the host's open vote, to everyone: reliable as it opens and as a vote
--                                             comes in, every resend_s unreliable
--   "vt|<id>|<1 yes / 0 no>"                  a joiner's answer, to the host (the last one before the close counts while
--                                             allow_change; else the first)
--   "dr|<id>|<yes>|<no>|<1 taken / 0 not>"     the host's result, to everyone, reliable
--   The host's War lines reach the joiners as its other subtitles do (SUB.say's "sb"), the Hornet as its spawns do.
-- Log lines: `deal: offered on round R (<kind>, chance C): ...`, `deal: the Hornet: ...`, `deal: vote N open for S s
-- (P players)`, `deal: player S votes YES|NO`, `deal: vote N closed (<why>): YES y, NO n: TAKEN|REFUSED (<rule>)`,
-- `deal: round R cleared with the deal: +X (earned E x ...) + bonus B`, `deal: the Hornet taken off (...)`.
-- Test key (dev): Ctrl+H, the deal offered now, any round, any special (none needed).
-- DEV ONLY BEGIN (THE DEAL: the user's dev install only; docs/re/DEAL.md)
CFG.specials.deal = {
    enabled = true,
    -- (D1, the user: "Only some", "It comes by chance"; which kinds and their chances are still the user's call)
    kinds = { anomaly = 0.35, ladon = 0.35, alicorn = 0.35, glitch = 0.35, valka = 0.35, spaceport = 0.35 },
    offer_after_s = 45,                       -- into the special's round (its first fighting)
    intro_max_s = 14,                         -- the vote opens once War's introduction is said, this long at most
    vote_s = 30,                              -- (D3, the user)
    allow_change = true,                      -- (D3: open; a player's last answer before the close counts)
    resend_s = 2,
    keys = { yes = "A", no = "X", ctrl = true },
    result_row_s = 8,                         -- the result on the NEXT row this long
    leave_after_s = 7,                        -- the leaving lines this long after the result
    hornet = { unit = "SV_Unit_DealHornet", name_key = "SV_DealHornet", name = "WAR & HAYTHORN",
               row = "",                      -- (an NPC mission row for SV_SetAircraft; "": the unit's own F/A-18F)
               ahead_m = 1500, side_m = 700, up_m = 150, leave_s = 25 },
    pay = { kills_x = 2.0, bonus = 5000, bonus_per_round = 250 },    -- (D2: extra cash; the amounts a proposal)
    stakes = {},                              -- (D2: what YES does to each special kind: the user's call, none yet)
    text = { row_open = "THE DEAL: CTRL+%s YES / CTRL+%s NO   YES %d  NO %d   %s%s", you = "   YOU: %s",
             taken = "THE DEAL: TAKEN (YES %d / NO %d)", refused = "THE DEAL: REFUSED (YES %d / NO %d)",
             callout = "THE DEAL", callout_sub = "WAR & HAYTHORN: YES OR NO? CTRL+%s / CTRL+%s",
             paid = "THE DEAL PAID", paid_sub = "+%d ZOLLARS" },
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
        ask = { { "WAR|So. You're winning this anyway. Want to make it interesting? Higher stakes, bigger payout. Yes or no?" },
                { "WAR|Here's my offer: we raise the stakes on this fight, and you get paid extra for it. Do we have a deal?" },
                { "WAR|I've got a proposition. It gets harder, you get richer. Vote now. Haythorn has all day, I don't." },
                { "WAR|Quick one, pilots: carry on as it is, or up the stakes for a fatter paycheck? Yes or no." } },
        yes = { { "WAR|Ha! Deal. Stakes are up, the pay's up. Try not to die, it voids the contract." },
                { "WAR|That's a yes! Haythorn, write it down.", "HAYTHORN|I'm flying the plane, War." },
                { "WAR|Pleasure doing business. It's going to get loud out there. Loud means money." } },
        no = { { "WAR|No? Fine. Safe and boring. I respect it. I don't like it, but I respect it." },
               { "WAR|No deal. Haythorn, they said no.", "HAYTHORN|I heard." },
               { "WAR|Your loss. The offer's off the table." } },
        tie = { { "WAR|Split crew? Then it's no deal. I don't do coin flips, I do contracts." },
                { "WAR|A tie. Ties go to no. House rules. My house." } },
        none = { { "WAR|Nobody? Really? I'll take the silence as a no." } },
        leave = { { "HAYTHORN|That's our cue. Hornet's breaking off.", "WAR|Bye! I'm waving! ...Can they see me waving?" },
                  { "HAYTHORN|WAR & HAYTHORN leaving the area. Good hunting." },
                  { "WAR|We're off. Haythorn has a thing.", "HAYTHORN|Fuel. The thing is fuel." } },
        paid = { { "WAR|Contract fulfilled. The money's in your account. Pleasure, as always." },
                 { "WAR|Told you it'd pay. Money's sent. War out." } },
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
local S = { round = nil, roundAt = nil, rolled = false, clock = 0, last = nil, noHornetSaid = false, sendAt = 0 }
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
    local at, yaw = nil, 0
    if pawn and valid(pawn) then
        pcall(function()
            local v, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
            at, yaw = { X = v.X, Y = v.Y, Z = v.Z }, r.Yaw or 0
        end)
    end
    if type(SV_SetText) == "function" then pcall(SV_SetText, h.name_key, h.name) end
    if h.row and h.row ~= "" and type(SV_SetAircraft) == "function" then pcall(SV_SetAircraft, h.unit, h.row) end
    if ALLY and ALLY.unit then ALLY.unit[h.unit] = "air" end         -- (an ally's: no kill credit, as VOID WATCHER 1)
    local okS, r
    if at then
        local a = math.rad(yaw)
        local fx, fy = math.cos(a), math.sin(a)                          -- (ahead; right is (-fy, fx))
        local x = at.X + fx * h.ahead_m * 100 - fy * h.side_m * 100
        local y = at.Y + fy * h.ahead_m * 100 + fx * h.side_m * 100
        okS, r = pcall(SV_Spawn, h.unit, x, y, at.Z + h.up_m * 100, yaw % 360)
    else
        okS, r = pcall(SV_Spawn, h.unit)
    end
    r = okS and tonumber(r) or -4
    if r > 0 then
        S.hornetUp = true
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

-- (the host) the offer: the Hornet up, War's introduction; the vote opens after it (openTick)
local function offer(kind, why)
    local c = cfg()
    DEAL.nextId = DEAL.nextId + 1
    local V = { id = DEAL.nextId, round = D.round, kind = kind, phase = "intro", at = S.clock, votes = {} }
    DEAL.V = V
    S.rolled = true
    local plane = hornetUp()
    say("intro", c.lines.intro)
    local left = (SUB and SUB.left) and num(SUB.left(D.now or S.clock), 0) or 0
    V.openAt = S.clock + math.min(c.intro_max_s, left + 0.5)
    log(string.format("deal: offered on round %d (%s, %s): the Hornet %s, the vote opens in %.0f s", D.round, tostring(kind),
        why, plane and "up" or "not up", V.openAt - S.clock))
end

local function openVote(V)
    local c = cfg()
    say("ask", c.lines.ask)
    V.phase, V.closeAt = "open", S.clock + c.vote_s
    hudCallout(c.text.callout, string.format(c.text.callout_sub, c.keys.yes, c.keys.no))
    log(string.format("deal: vote %d open for %d s (%d player%s)", V.id, c.vote_s, players(), players() == 1 and "" or "s"))
    sendOpen(V, true)
    S.sendAt = S.clock + c.resend_s
end

local function closeVote(V, why)
    local c = cfg()
    local y, n = count(V.votes)
    local taken = y > n
    local rule = (y == 0 and n == 0) and "nobody answered: no" or (y == n) and "a tie is no" or "the most votes"
    V.phase, V.yes, V.no, V.taken, V.resultUntil = "closed", y, n, taken, S.clock + c.result_row_s
    log(string.format("deal: vote %d closed (%s): YES %d, NO %d: %s (%s)", V.id, why, y, n, taken and "TAKEN" or "REFUSED", rule))
    if linked() then COOP.msg(nil, "dr", V.id, y, n, taken and 1 or 0) end
    if taken then
        say("yes", c.lines.yes)
        DEAL.won = { round = V.round, id = V.id, earned = 0 }
        local st = c.stakes[V.kind]
        log(string.format("deal: the stakes for %s: %s", tostring(V.kind), st and "applied" or "none yet (the user's call)"))
    else
        say((y == 0 and n == 0) and "none" or (y == n) and "tie" or "no", (y == 0 and n == 0) and c.lines.none
            or (y == n) and c.lines.tie or c.lines.no)
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

local function hostTick()
    local c = cfg()
    if D.round ~= S.round then S.round, S.roundAt, S.rolled = D.round, nil, false end
    if not S.roundAt and D.state ~= "wait" and D.special then S.roundAt = S.clock end
    local V = DEAL.V
    if V and V.phase == "intro" and S.clock >= V.openAt then openVote(V)
    elseif V and V.phase == "open" then
        local y, n = count(V.votes)
        if S.clock >= V.closeAt then closeVote(V, "the clock ran out")
        elseif y + n >= players() then closeVote(V, "everyone answered")
        elseif S.clock >= S.sendAt then S.sendAt = S.clock + c.resend_s; sendOpen(V, false) end
    elseif V and V.phase == "closed" and V.leaveAt and S.clock >= V.leaveAt then
        V.leaveAt = nil
        say("leave", c.lines.leave)
        if S.hornetUp then S.hornetOffAt = S.clock + c.hornet.leave_s end
    end
    if S.hornetOffAt and S.clock >= S.hornetOffAt then hornetOff("its leave_s after the leaving lines") end
    -- the offer: once a round, on a special the dice let have it, offer_after_s into its round, never in the STORE
    if V and V.phase ~= "closed" then return end
    if S.rolled or not (D.special and S.roundAt) or D.state == "wait" then return end
    if S.clock - S.roundAt < c.offer_after_s then return end
    if SPC and SPC.storeShut and not SPC.storeShut(D.now or S.clock) then return end
    S.rolled = true
    local kind = D.special.kind
    local chance = num(c.kinds[kind], 0)
    local roll = math.random()
    if roll >= chance then
        if chance > 0 then log(string.format("deal: round %d (%s): no offer (rolled %.2f, chance %.2f)", D.round, kind, roll, chance)) end
        return
    end
    offer(kind, string.format("chance %.2f, rolled %.2f", chance, roll))
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
        if J.taken then DEAL.won = { round = D.round, id = id, earned = 0 } end
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

-- the NEXT row (sv_hud.lua): the offer while it's open, the result a little after; else nil
function DEAL.row()
    local c = cfg()
    if not (D and c.enabled) then return nil end
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

---------------------------------------------------------------------------------------------------- the pay
-- every game: what it earns while a deal it took is on, the round's own clear bonus and the deal's own pay left out
local rawAdd = addCredits
addCredits = function(n, why)
    local W = DEAL.won
    if W and D and D.round == W.round and D.state ~= "wait" and type(n) == "number" and n > 0 then
        local w = tostring(why or "")
        if not (w:find("cleared", 1, true) or w:find("the deal", 1, true)) then W.earned = W.earned + n end
    end
    return rawAdd(n, why)
end
local function payTick()
    local W = DEAL.won
    if not (W and D) then return end
    if D.round ~= W.round then
        log(string.format("deal: round %d never cleared with the deal on (now round %s): not paid", W.round, tostring(D.round)))
        DEAL.won = nil
        return
    end
    if D.state ~= "wait" then return end
    DEAL.won = nil
    local p = cfg().pay
    local extra = math.floor(W.earned * (num(p.kills_x, 1) - 1) + 0.5)
    local bonus = isHost() and math.floor(num(p.bonus, 0) + num(p.bonus_per_round, 0) * W.round) or 0
    if extra > 0 then
        if COOP and COOP.payOwn and COOP.open then COOP.payOwn(extra, "the deal's extra") else rawAdd(extra, "the deal's extra") end
    end
    if bonus > 0 then addCredits(bonus, "the deal's bonus") end
    log(string.format("deal: round %d cleared with the deal: +%d (earned %d x %.2f more) + bonus %d%s", W.round, extra, W.earned,
        num(p.kills_x, 1) - 1, bonus, isHost() and "" or " (the host's, sent)"))
    local c = cfg()
    if isHost() then
        say("paid", c.lines.paid)
        -- (this game's own sum: each joiner shows its own)
        local show = (COOP and COOP.open and COOP.localCallout) or hudCallout
        show(c.text.paid, string.format(c.text.paid_sub, extra + bonus))
    elseif COOP and COOP.localCallout and extra > 0 then
        COOP.localCallout(c.text.paid, string.format(c.text.paid_sub, extra))
    end
end

---------------------------------------------------------------------------------------------------- the tick and the keys
-- (sv_main.lua's test ticks, every game, in a run) the clock holds while the game is paused
function DEAL.tick(clock)
    if not cfg().enabled then return end
    if not D then
        if S.hornetUp then S.hornetUp = false end
        DEAL.V, DEAL.J, DEAL.won, S.round, S.noHornetSaid = nil, nil, nil, nil, false
        S.last, S.D, S.hornetOffAt = nil, nil, nil
        return
    end
    if S.D ~= D then                                    -- (a new run: nothing of the last one's carried over)
        if S.D ~= nil and (DEAL.V or DEAL.J or DEAL.won) then log("deal: a new run: the last run's deal dropped") end
        S.D, DEAL.V, DEAL.J, DEAL.won, S.round, S.hornetOffAt = D, nil, nil, nil, nil, nil
        if S.hornetUp then hornetOff("a new run") end
    end
    local dt = S.last and math.max(0, math.min(1, clock - S.last)) or 0
    S.last = clock
    if not paused() then S.clock = S.clock + dt end
    if isHost() then hostTick() else joinerTick() end
    payTick()
end
-- (the test key) the deal offered now, whatever the round
function DEAL.offerNow()
    if not D then log("deal: Ctrl+H outside a Survival run"); return end
    if not isHost() then log("deal: Ctrl+H on a joiner: the host offers the deal"); return end
    if DEAL.V and DEAL.V.phase ~= "closed" then log("deal: Ctrl+H: a deal is on already"); return end
    S.round = D.round
    offer(D.special and D.special.kind or "none", "Ctrl+H")
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
end
-- DEV ONLY END
