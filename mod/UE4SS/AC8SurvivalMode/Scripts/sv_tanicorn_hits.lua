-- sv_tanicorn_hits.lua : THE TANACORN's hit probe (2026-11-12). Test builds only: the user's dev install, and a TESTER=1 TANI=1
-- zip (tools/dev_only.py cuts it to this header in every other zip, as sv_tanicorn.lua).
-- Why: a tester on 0.74.65's ..._TANACORN zip: "if the Tanacorn is hit, everything immediately dies". The user's decision:
-- damage like the Alicorn (her hull can't be damaged, each part shot down on its own, she sinks at her core; sv_tanicorn.lua
-- TANI.armour). This logs what each hit does, so the next test shows whether the armour holds: from the first tick a hull of
-- ours is armoured (TANI.armoured: Ctrl+Y / Ctrl+R / Ctrl+L) and, on Ctrl+L's live hull, each part its watch has seen
-- (TANI.liveSeen), every tick (250 ms) their HealthInternal (health x 10). Reads only: nothing is damaged or changed (hard
-- rule 63). Each object kept by its address and name and checked before every read (hard rule 59).
-- Logged:
--   `tanicorn hits: start +T s: HULL <name> hp 50000/5000.0; <what decides where damage goes>` (the hull, and the first part
--     of each type: bCanBeDamaged, bIsInvincible, bCauseExplosionOnDeath, bIsInvincibleInducedExplosion, DamageRateToParent,
--     bIsReflectionDamageToParent, TimeToDeactivateAfterDeath; its induced explosion's radius, hit distance, parent-only and
--     damage);
--   `tanicorn hits: +T s Part_T5_3 (T5) hp 2000 -> 1520/200.0 (-480); by you/<name> 480` on every change (cap: change_cap a
--     hull; the downs and goings always), `... DOWN` when its health reaches 0;
--   `tanicorn hits: +T s Part_T5_3 (T5) GONE (its actor no longer there), its last read 1520/200.0 at +t s` (and `, +x s
--     after the HULL went down` once it has);
--   `tanicorn hits: +T s the HULL is DOWN: N of its parts up at that read, K down before it` (with the armour on: never);
--   `tanicorn hits: over (every object gone or the level left): N reads, C changes, D down, G gone`.
-- The test: Ctrl+L, wait for the +8 s look, then hit the HULL alone (lock its box); then one T5; then a VLS block, each a few
-- seconds apart. With the armour on, the hull's hp never moves, and each part goes DOWN alone, its neighbours' hp unchanged.
-- DEV ONLY BEGIN
do
local P = nil                                             -- the probe: { t0, objs = { [addr|name] = e }, n, changes, ... }
TANI.hits = { change_cap = 300 }
local function key(e) return tostring(e.a) .. "|" .. e.name end
local function same(e) return e and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end
local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end
local function hp(o)
    local h, mx
    pcall(function() h = tonumber(o.HealthInternal) end)
    pcall(function() mx = tonumber(o.MaxHealth) end)
    return h, mx
end
local FIELDS = { "bCanBeDamaged", "bIsInvincible", "bCauseExplosionOnDeath", "bIsInvincibleInducedExplosion", "DamageRateToParent",
                 "bIsReflectionDamageToParent", "TimeToDeactivateAfterDeath" }
local IES = { "ExplosionRadius", "HitDistance", "bIsExplosionDamageParentOnly", "damage" }
local function fieldsOf(o)                                -- (plain values only: no soft reference, hard rule 29)
    local t = {}
    for _, f in ipairs(FIELDS) do
        local ok, v = pcall(function() return o[f] end)
        t[#t + 1] = f .. " " .. (ok and tostring(v) or "?")
    end
    local ie = "none"
    pcall(function()
        local x = o.DamagedStateComponent.InducedExplosionSystem
        if valid(x) then
            local p = {}
            for _, f in ipairs(IES) do
                local ok, v = pcall(function() return x[f] end)
                p[#p + 1] = f .. " " .. (ok and tostring(v) or "?")
            end
            ie = table.concat(p, ", ")
        end
    end)
    return table.concat(t, ", ") .. "; its induced explosion: " .. ie
end
local function who(o)                                     -- its DamageHistoryMap (sv_fishing.lua FISH.who)
    if not (FISH and FISH.who) then return "?" end
    local ok, w = pcall(FISH.who, o)
    return ok and tostring(w) or "?"
end
local function add(now, o, a, name, label, kind, type_)
    local e = { o = o, a = a, name = name, label = label, kind = kind, type_ = type_ }
    if P.objs[key(e)] then return end
    P.objs[key(e)] = e
    P.n = P.n + 1
    e.h, e.mx = hp(o)
    e.at = now
    if kind == "hull" or not P.typeSaid[type_ or "?"] then
        P.typeSaid[type_ or "?"] = true
        log(string.format("tanicorn hits: start +%.1f s: %s hp %s/%s; %s", now - P.t0, label, tostring(e.h), tostring(e.mx),
            fieldsOf(o)))
    end
end
local function since(now) return string.format("+%.1f s", now - P.t0) end
local function afterHull(now) return P.hullDownAt and string.format(", %+.1f s after the HULL went down", now - P.hullDownAt) or "" end
local function over(why)
    if not P then return end
    log(string.format("tanicorn hits: over (%s): %d objects watched, %d reads, %d changes, %d down, %d gone", why, P.n, P.reads,
        P.changes, P.downs, P.gones))
    P = nil
end
-- ((2026-11-12, the review) closed with the level: levelDrop runs as the gate closes, before any test tick could see it)
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["tanicorn hits"] = function() if P then over("the level left") end end end
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn hits", fn = function(now)
    if not (TANI and TANI.armoured) then return end
    if P and (not D or (levelTorn and levelTorn())) then over("the level left"); return end   -- (a backstop)
    if not D then return end
    if P and P.D ~= D then over("a new run") end         -- (a restart in the same level: a new D, the world kept)
    local hulls = {}
    for _, h in ipairs(TANI.armoured) do if same(h) then hulls[#hulls + 1] = h end end
    if not P then
        if #hulls == 0 then return end                    -- (a probe starts with a hull of ours up, its clock from there)
        P = { t0 = now, D = D, objs = {}, n = 0, reads = 0, changes = 0, downs = 0, gones = 0, typeSaid = {} }
    end
    for _, h in ipairs(hulls) do add(now, h.o, h.a, h.name, "HULL " .. short(h.o), "hull", nil) end
    local seen = TANI.liveSeen and TANI.liveSeen()
    for s, e in pairs(seen or {}) do
        if same(e) then add(now, e.o, e.a, e.name, "Part_" .. s .. " (" .. tostring(e.key) .. ")", "part", e.key) end
    end
    local live = 0
    for _, e in pairs(P.objs) do
        if not e.gone then
            if not same(e) then
                e.gone = true
                P.gones = P.gones + 1
                log(string.format("tanicorn hits: %s %s GONE (its actor no longer there), its last read %s/%s at +%.1f s%s", since(now),
                    e.label, tostring(e.h), tostring(e.mx), (e.readAt or e.at) - P.t0, afterHull(now)))
            else
                live = live + 1
                local h, mx = hp(e.o)
                P.reads = P.reads + 1
                if h and e.h and h ~= e.h then
                    P.changes = P.changes + 1
                    if P.changes <= TANI.hits.change_cap or (h <= 0 and not e.down) then
                        log(string.format("tanicorn hits: %s %s hp %s -> %s/%s (%+.0f)%s; by %s", since(now), e.label, tostring(e.h),
                            tostring(h), tostring(mx or e.mx), h - e.h + 0.0, (h <= 0 and not e.down) and " DOWN" or "", who(e.o)))
                    elseif P.changes == TANI.hits.change_cap + 1 then
                        log("tanicorn hits: more changes than change_cap: only the downs and goings from here")
                    end
                end
                if h and h <= 0 and not e.down then
                    e.down = true
                    P.downs = P.downs + 1
                    if e.kind == "hull" then
                        P.hullDownAt = now
                        local up, before = 0, 0
                        for _, x in pairs(P.objs) do
                            if x.kind == "part" then
                                if x.down then before = before + 1 elseif not x.gone then up = up + 1 end
                            end
                        end
                        log(string.format("tanicorn hits: %s the HULL is DOWN: %d of its parts up at that read, %d down before it",
                            since(now), up, before))
                    end
                end
                if h then e.h, e.readAt = h, now end
                if mx then e.mx = mx end
            end
        end
    end
    if live == 0 and P.n > 0 then over("every object gone") end
end }
end
-- DEV ONLY END
