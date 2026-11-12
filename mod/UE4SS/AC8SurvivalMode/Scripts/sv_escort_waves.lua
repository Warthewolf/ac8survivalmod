-- sv_escort_waves.lua: CHARLENE's enemy waves, their flights and their size for the room (2026-11-09). Part of AC8 Survival
-- Mode's runtime, run by main.lua in order after sv_escort_dive; a name another part uses is a global of this mod's Lua
-- state, its own helpers stay local.
--   ESC.waveFlights(want, aliveOf, noneUp, lo, top)   (sv_escort.lua wavesTick) free pool flights for a wave of `want`
--                                             aircraft (as near it as they make; under lo: the fewest from lo up to top):
--                                             the flights, their aircraft, and every free flight's aircraft
--   ESC.roomMore(n, capKey)                   the user (2026-11-09): "With the enemies in escort charlene, we need to scale
--                                             the enemies by players": n for the host's room as a round's aircraft are
--                                             (COOP.more: [coop] aircraft_per_player more for each player past the first,
--                                             within CFG.coop[capKey] if given; solo or a joiner: n). sv_escort.lua scales
--                                             attack.max (her attackers at once) and the waves' min_n, max_n and max_up
--                                             (within [coop] max_up) with it; the round's own flights are scaled already
--                                             (sv_rounds.lua startRound). CFG.specials.escort.coop_scale = false: as solo.

do
function ESC.roomMore(n, capKey)
    local ok, m = true, n
    if CFG.specials.escort.coop_scale ~= false and COOP and COOP.more then ok, m = pcall(COOP.more, n, capKey) end
    return (ok and type(m) == "number") and math.floor(m) or n
end
-- free flights for a wave of `want` aircraft, a random mix of the sizes: as many aircraft as the free flights can make up
-- to `want` (each flight drawn keeps that total within reach), and when that's under lo, the fewest from lo up to top.
-- (2026-11-12: a mix drawn flight by flight took a 2-ship first for a wave of 4 with no other 2-ship free and made 2,
-- under min_n: the wave held 5 s with 4- and 6-ships free; a wave of 10 made 8, of 6 made 4.) The flights, the aircraft,
-- and the free flights' aircraft (for the hold's log: none free, or free ones that make no wave from lo up to top).
function ESC.waveFlights(want, aliveOf, noneUp, lo, top)
    local pend = {}
    for _, q in ipairs(D.queue or {}) do pend[q] = true end
    for i = (D.wave or 1), #(D.waves or {}) do for _, q in ipairs(D.waves[i] or {}) do pend[q] = true end end
    local bySize, sizes, free = {}, {}, 0
    for _, u in ipairs(CFG.pool or {}) do
        if not D.up[u] and not pend[u] and not (PROBE_OF and PROBE_OF[u]) and poolIndex(u)
            and not (ROLE and ROLE.sitsOut and ROLE.sitsOut(u)) and noneUp(aliveOf(u)) then
            local n = flightSize(u)
            if not bySize[n] then bySize[n] = {}; sizes[#sizes + 1] = n end
            table.insert(bySize[n], u)
            free = free + n
        end
    end
    top = math.max(want, top or want)
    local function reach(skip)                      -- (the totals the free flights make, up to top: one of size skip set aside)
        local r = { [0] = true }
        for _, n in ipairs(sizes) do
            if n > 0 then
                for _ = 1, #bySize[n] - (n == skip and 1 or 0) do
                    for s = top, n, -1 do if r[s - n] then r[s] = true end end
                end
            end
        end
        return r
    end
    local r0, goal = reach(nil), 0
    for s = want, 0, -1 do if r0[s] then goal = s; break end end
    if goal < (lo or 0) then
        for s = lo, top do if r0[s] then goal = s; break end end
    end
    local out, got = {}, 0
    while got < goal do
        local fit = {}
        for _, n in ipairs(sizes) do
            if n > 0 and n <= goal - got and #bySize[n] > 0 and reach(n)[goal - got - n] then fit[#fit + 1] = n end
        end
        if #fit == 0 then break end
        local n = fit[math.random(#fit)]
        out[#out + 1], got = table.remove(bySize[n], math.random(#bySize[n])), got + n
    end
    return out, got, free
end
end
