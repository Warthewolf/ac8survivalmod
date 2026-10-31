-- sv_audit.lua: the run's audits, in the log only (no gameplay).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (... sv_coop, sv_down, sv_audit, sv_main); a name another
-- part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- audits
-- The user's loggers of 2026-10-31 ("What other loggers could we add?" ... "All of them"), each its own lines, every
-- report_s (CFG.log.audit, [log.audit]):
--   targets: who the enemy aircraft aim at (their blackboard's TargetActor, looked at every sample_s): you, each other
--     co-op player by name (their plane here: COOP.slotOfAddr), the allies' aircraft, anything else, nothing; and each
--     player's damage taken in that time (health looked at as often: drops and the share lost);
--   pay audit: every pay on this game by kind (kills, round bonuses, specials, other), and on a co-op joiner each kill paid
--     within suspect_s of this game tearing copies down itself (COOP.tornRecently: a torn copy paid as a kill; Alyssa's
--     log of 2026-10-31: 290 Z "by you" after the host's restart), logged at once;
--   sync: co-op's sync health (sv_coop.lua COOP.syncReport): a joiner's copies, bound to the host's ids or not, strays,
--     asks for the whole picture and their answers, teardowns; on the host the asks it answered.
-- The crash breadcrumbs, the missile outcomes, the fleet's turrets and the Spaceport's waves are the native runtime's,
-- sv_weaponlog.lua's and sv_spaceport.lua's. Only addresses, numbers and text are kept between looks.
AUDIT = {}
do
local function cfg() return CFG.log and CFG.log.audit or {} end
local function short(o) return ((nameOf(o):match("([%w_]+)$") or "?"):gsub("_C_%d+$", ""):gsub("_C$", "")) end

-- one player's health, in % of their whole: you from your plane, the others from their stream (COOP.players)
local function myHp(pawn)
    local ok, v = pcall(function() return pawn.HealthInternal / (pawn.MaxHealth * 10) * 100 end)
    return ok and type(v) == "number" and v or nil
end

local T = { looks = 0, planes = 0, at = {}, dmg = {}, hp = {} }
local function sample(pawn)
    local pawnAddr = addrOf(pawn)
    local allies = {}
    pcall(function()
        for _, a in ipairs(ALLY.state().planes or {}) do if valid(a.obj) then local x = addrOf(a.obj); if x then allies[x] = true end end end
    end)
    T.looks = T.looks + 1
    for _, p in ipairs(planes or {}) do
        if not p.down and p.unit and valid(p.obj) then
            local bb = aiBlackboard(p)
            if bb then
                T.planes = T.planes + 1
                local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
                local who = "nothing"
                if okT and valid(t) then
                    local a = addrOf(t)
                    local slot = a and COOP and COOP.open and COOP.slotOfAddr and COOP.slotOfAddr(a)
                    if a and a == pawnAddr then who = "you"
                    elseif slot then who = (COOP.name and COOP.name(slot)) or ("player " .. (slot + 1))
                    elseif a and allies[a] then who = "allies"
                    else who = "other (" .. short(t) .. ")" end
                end
                T.at[who] = (T.at[who] or 0) + 1
            end
        end
    end
    local hp = { you = myHp(pawn) }
    if COOP and COOP.open and COOP.players then
        for _, e in ipairs(COOP.players()) do
            if not e.isMe and e.slot and type(e.hpPct) == "number" then hp[(COOP.name and COOP.name(e.slot)) or ("player " .. (e.slot + 1))] = e.hpPct end
        end
    end
    for name, v in pairs(hp) do
        local was = T.hp[name]
        if was and v < was - 0.5 then
            local d = T.dmg[name] or { looks = 0, pct = 0 }
            d.looks, d.pct = d.looks + 1, d.pct + (was - v)
            T.dmg[name] = d
        end
        T.hp[name] = v
    end
end

local function targetsReport(secs)
    if T.looks == 0 then return end
    local parts, others = {}, 0
    for who, n in pairs(T.at) do
        if who:find("^other") then others = others + n
        else parts[#parts + 1] = { who = who, n = n } end
    end
    table.sort(parts, function(a, b) return a.n > b.n end)
    local t = {}
    for _, x in ipairs(parts) do t[#t + 1] = string.format("%s %.1f", x.who, x.n / T.looks) end
    if others > 0 then
        local top, topN = nil, 0
        for who, n in pairs(T.at) do if who:find("^other") and n > topN then top, topN = who, n end end
        t[#t + 1] = string.format("others %.1f (most %s)", others / T.looks, top:match("%((.-)%)") or "?")
    end
    local d = {}
    for name, x in pairs(T.dmg) do d[#d + 1] = string.format("%s -%.0f%% in %d looks", name, x.pct, x.looks) end
    table.sort(d)
    log(string.format("targets: last %d s (%d looks, %.1f enemy aircraft on average): aiming at %s; damage taken: %s", secs,
        T.looks, T.planes / T.looks, #t > 0 and table.concat(t, ", ") or "-", #d > 0 and table.concat(d, ", ") or "none"))
    T.looks, T.planes, T.at, T.dmg = 0, 0, {}, {}
end

-- the pay audit (every pay through the global addCredits: sv_ai.lua's, under sv_coop.lua's)
local P = { n = 0, sum = 0, by = {}, suspect = 0, suspectSum = 0 }
local function kindOf(why, n)
    local w = tostring(why):lower()
    for _, k in ipairs({ "spaceport", "landing craft", "landing repelled", "fleet", "garrison", "ladon", "alicorn", "anomaly",
                         "valka", "glitch", "shuttle", "troop" }) do       -- (first: "landing craft down (lane A)" isn't a kill)
        if w:find(k, 1, true) then return "specials" end
    end
    if w:find(" down (", 1, true) then return "kills" end
    if w:find("cleared", 1, true) then return "round bonuses" end
    return n < 0 and "spent" or "other"
end
function AUDIT.pay(n, why)
    if cfg().enabled == false or type(n) ~= "number" or n == 0 then return end
    local kind = kindOf(why, n)
    P.n, P.sum = P.n + 1, P.sum + n
    local b = P.by[kind] or { n = 0, sum = 0 }
    b.n, b.sum = b.n + 1, b.sum + n
    P.by[kind] = b
    if kind == "kills" and COOP and COOP.client and COOP.client() and COOP.tornRecently then
        local recent, tw = COOP.tornRecently(tonumber(cfg().suspect_s) or 5)
        if recent then
            P.suspect, P.suspectSum = P.suspect + 1, P.suspectSum + n
            log(string.format("pay audit: +%d (%s) within %s s of this game tearing copies down (%s): maybe a torn copy paid as a kill",
                n, tostring(why), tostring(cfg().suspect_s or 5), tostring(tw or "?")))
        end
    end
end
do
    local rawAdd = addCredits
    if type(rawAdd) == "function" then
        addCredits = function(n, why)
            pcall(AUDIT.pay, n, why)
            return rawAdd(n, why)
        end
    end
end
local function payReport(secs)
    if P.n == 0 then return end
    local t = {}
    for kind, b in pairs(P.by) do t[#t + 1] = string.format("%s %d (%+d)", kind, b.n, b.sum) end
    table.sort(t)
    log(string.format("pay audit: last %d s: %+d Z in %d pays: %s%s", secs, P.sum, P.n, table.concat(t, ", "),
        P.suspect > 0 and string.format("; %d kill pays (%+d) right after a teardown here", P.suspect, P.suspectSum) or ""))
    P.n, P.sum, P.by, P.suspect, P.suspectSum = 0, 0, {}, 0, 0
end

function AUDIT.tick(now)
    local c = cfg()
    if c.enabled == false or not D or not now then return end
    if now >= (AUDIT.sampleAt or 0) then
        AUDIT.sampleAt = now + (tonumber(c.sample_s) or 5)
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        if pawn and valid(pawn) then
            local ok, err = pcall(sample, pawn)
            if not ok and not AUDIT.sampleErr then AUDIT.sampleErr = true; log("targets: error " .. tostring(err)) end
        end
    end
    AUDIT.reportAt = AUDIT.reportAt or (now + (tonumber(c.report_s) or 60))
    if now >= AUDIT.reportAt then
        local secs = math.floor((tonumber(c.report_s) or 60) + 0.5)
        AUDIT.reportAt = now + (tonumber(c.report_s) or 60)
        pcall(targetsReport, secs)
        pcall(payReport, secs)
        if COOP and COOP.open and COOP.syncReport then
            local ok, line = pcall(COOP.syncReport)
            if ok and line then log("sync: last " .. secs .. " s: " .. line) end
        end
    end
end
end
