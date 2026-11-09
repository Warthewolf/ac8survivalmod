-- sv_escort_waves.lua: CHARLENE's enemy waves, their flights and their size for the room (2026-11-09). Part of AC8 Survival
-- Mode's runtime, run by main.lua in order after sv_escort_dive; a name another part uses is a global of this mod's Lua
-- state, its own helpers stay local.
--   ESC.waveFlights(want, aliveOf, noneUp)   (sv_escort.lua wavesTick) free pool flights for a wave of `want` aircraft
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
-- free flights for a wave of `want` aircraft (a random mix of the sizes that still fit): the flights, the aircraft
function ESC.waveFlights(want, aliveOf, noneUp)
    local pend = {}
    for _, q in ipairs(D.queue or {}) do pend[q] = true end
    for i = (D.wave or 1), #(D.waves or {}) do for _, q in ipairs(D.waves[i] or {}) do pend[q] = true end end
    local bySize, sizes = {}, {}
    for _, u in ipairs(CFG.pool or {}) do
        if not D.up[u] and not pend[u] and not (PROBE_OF and PROBE_OF[u]) and poolIndex(u)
            and not (ROLE and ROLE.sitsOut and ROLE.sitsOut(u)) and noneUp(aliveOf(u)) then
            local n = flightSize(u)
            if not bySize[n] then bySize[n] = {}; sizes[#sizes + 1] = n end
            table.insert(bySize[n], u)
        end
    end
    local out, got = {}, 0
    while true do
        local fit = {}
        for _, n in ipairs(sizes) do if n <= want - got and #bySize[n] > 0 then fit[#fit + 1] = n end end
        if #fit == 0 then break end
        local n = fit[math.random(#fit)]
        out[#out + 1], got = table.remove(bySize[n], math.random(#bySize[n])), got + n
    end
    return out, got
end
end
