-- sv_coop_migration.lua: Survival COOP, host migration, the rest of the runtime wrapped for co-op, and the co-op tick.
-- Piece 5 of 5 of sv_coop.lua (sv_coop.lua, sv_coop_joiner.lua, sv_coop_planes.lua, sv_coop_sync.lua,
-- sv_coop_migration.lua), split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_coop.lua's do block, continued: this piece's own helpers stay local to it)
local M = COOP.M                                   -- (sv_coop.lua's M, handed on)
local crumb = crumb or function() end  -- (as in sv_coop.lua)

---------------------------------------------------------------------------------------------------- host migration
-- (the user, 2026-10-31: "can we also set up a Host Migration system? so if the Host does leave, it automatically
-- tries to find the next best host"; their choices: the round in play starts again, the allies and defences are built
-- again, the best connection takes over.) While it's up, the host ranks its joiners by their link (round trip and the
-- share resent; players in the mission first) and tells everyone the order with each one's Steam ID ("sq"), and the
-- allies and defences up ("al"); before its level reloads at a run's end it says how long it'll be away ("hl"). A
-- joiner whose host has been silent [coop.migration] after_s goes down that order: if the first is itself it becomes
-- the host (it opens as host looking for everyone's Steam ID, takes over the run: the round in play again after
-- break_s, held up to wait_s while the others come back, the allies and defences built again), else it joins that one,
-- the next after link_s. Planes keep their owner (P.sid): one back in another slot has its plane moved with them
-- (SV_CoopSwapPP), a slot that's someone else's has the old plane set aside, hidden (never destroyed mid-level).
do
local ITEM_OK = { AAGun = true, SAM = true, Ciws = true, Wingmen = true, Moonchild = true, ShipAegis = true, VoidWatcher = true,
                  ZfaCarrier = true }
local function mig() return cfg().migration or {} end
local function sidOk(v) return type(v) == "string" and v:match("^%d+$") ~= nil and #v >= 15 and #v <= 20 end
function M.mySid()
    if not M.mySidV and type(SV_CoopInfo) == "function" then
        local v = tostring(SV_CoopInfo() or ""):match("me=(%d+)")
        if sidOk(v) then M.mySidV = v end
    end
    return M.mySidV
end
-- (the host) each linked game's Steam ID and link: { [slot] = { sid, rtt (ms), loss (share resent), up } }
function M.linkQuality()
    local q = {}
    local s = type(SV_CoopPeerIds) == "function" and tostring(SV_CoopPeerIds() or "") or ""
    for slot, sid, rtt, tx, rs, up in s:gmatch("(%d+):(%d+):(%-?%d+):(%d+):(%d+):([01])") do
        q[tonumber(slot)] = { sid = sid, rtt = tonumber(rtt), loss = tonumber(rs) / math.max(1, tonumber(tx)), up = up == "1" }
    end
    return q
end
-- (the host) the allies and defences up: "item:buyer's Steam ID" (0: yours, or none known), sorted
local function allyList()
    local R, out = ALLY and ALLY.run, {}
    if not R then return "" end
    for _, a in pairs(R.up or {}) do
        local item = a.kind == "ship" and ("Ship" .. tostring(a.key)) or (a.ally == "wingmen" and "Wingmen")
            or (a.ally == "awacs" and "VoidWatcher") or "Moonchild"
        local b = a.buyer and M.roster[a.buyer] and M.roster[a.buyer].sid or "0"
        -- ((0.73.78, plan G5) not VOID WATCHER 1 once its service is over: a new host doesn't bring a retired one back)
        if ITEM_OK[item] and not a.home then out[#out + 1] = item .. ":" .. b end
    end
    -- ((2026-11-06) the ZFA-44 carriers out: sv_escort.lua, rebuilt by a new host as the allies are)
    if ESC and ESC.carrierList then
        local okE, list = pcall(ESC.carrierList)
        for _, buyer in ipairs(okE and list or {}) do
            local b = buyer and M.roster[buyer] and M.roster[buyer].sid or "0"
            out[#out + 1] = "ZfaCarrier:" .. b
        end
    end
    local dc = R.defCount or {}
    for kind, item in pairs({ aa = "AAGun", sam = "SAM", ciws = "Ciws" }) do
        for _ = 1, math.min(8, tonumber(dc[kind]) or 0) do out[#out + 1] = item .. ":0" end
    end
    table.sort(out)
    return table.concat(out, ",")
end
-- (the host, every 5 s) the line of succession and the allies up, sent when they change and every 30 s
local function hostShare(now)
    if now < (M.sqAt or 0) then return end
    M.sqAt = now + 5
    local me = M.mySid()
    if not me then return end
    if M.roster[0] then M.roster[0].sid = me end
    local q, list = M.linkQuality(), {}
    for s, r in pairs(M.roster) do
        local l = s ~= COOP.slot and q[s]
        if l and sidOk(l.sid) then
            r.sid = l.sid
            local P = M.peers[s]
            if l.up then
                list[#list + 1] = { s = s, sid = l.sid, score = (l.rtt >= 0 and l.rtt or 999) + 2000 * l.loss + ((P and P.fresh) and 0 or 10000) }
            end
        end
    end
    table.sort(list, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.s < b.s end)
    local parts, said = {}, {}
    for _, e in ipairs(list) do parts[#parts + 1] = e.s .. ":" .. e.sid; said[#said + 1] = string.format("%d (%.0f)", e.s + 1, e.score) end
    local order = table.concat(parts, ",")
    if order ~= M.sqSent or now >= (M.sqAgain or 0) then
        M.sqSent, M.sqAgain = order, now + 30
        send(true, "sq", me, order)
        if order ~= M.sqSaid then
            M.sqSaid = order
            log("coop: migration: the next hosts, best link first: " .. (#said > 0 and table.concat(said, ", ") or "none"))
        end
    end
    local al = allyList()
    if al ~= M.alSent or now >= (M.alAgain or 0) then M.alSent, M.alAgain = al, now + 30; send(true, "al", al) end
end
-- (the host) before its level reloads (a run's end): away for up to secs, the joiners wait that long
function COOP.hostAway(secs)
    if COOP.host() then send(true, "hl", string.format("%d", math.floor(secs))) end
end
-- (a joiner) the host's line of succession, allies, time away
function M.onSuccession(f)
    if not sidOk(f[2]) then return end
    local list = {}
    for s, sid in tostring(f[3] or ""):gmatch("(%d+):(%d+)") do
        local n = tonumber(s)
        if slotOk(n) and n ~= 0 and sidOk(sid) and #list < MAX_SLOT then list[#list + 1] = { slot = n, sid = sid } end
    end
    M.succ, M.hostSid = list, f[2]
    if M.roster[0] then M.roster[0].sid = f[2] end
end
function M.onAllies(f)
    local list = {}
    for item, sid in tostring(f[2] or ""):gmatch("(%a+):(%d+)") do
        if ITEM_OK[item] and #list < 40 then list[#list + 1] = { item = item, sid = sid ~= "0" and sid or nil } end
    end
    M.allyList = list
end
function M.onHostAway(f)
    local secs = tonumber(f[2])
    if secs and secs > 0 and secs <= 300 then
        M.hostAwayUntil = os.clock() + secs
        log(string.format("coop: migration: the host's reloading, waited for up to %d s", secs))
    end
end
-- a player's plane here set aside, hidden and unbound (a live player plane is never destroyed mid-level). (0.73.77) The
-- rejoin's M.setAside: tick and collision off, moved up, and a real one moved out of its slot in the runtime: kept there,
-- the next player's real plane in that slot (SV_CoopSpawnPP) destroyed it, the crash this rule keeps away
function M.retirePeer(s, why)
    local P = M.peers[s]
    M.peers[s] = nil
    if not (P and P.obj and valid(P.obj)) then return end
    if not M.setAside(s, P, why) then
        pcall(function() P.obj:SetActorHiddenInGame(true) end)
        pcall(function() P.obj:SetActorEnableCollision(false) end)
        if type(SV_CoopPeer) == "function" then SV_CoopPeer(s, 0) end
        local radar = M.radarOff(P)
        log(string.format("coop: player %d's plane here set aside, hidden (%s)%s", s + 1, why, radar and ("; " .. radar) or ""))
    end
end
-- (every tick, before the planes) each player's real plane in their slot: one in another moves with them (from this
-- game's own slot too: it was theirs before this game took it), one that's another player's now is set aside; one left
-- in this game's own slot is hidden at once (its slot's never ticked) and set aside 10 s on if its player hasn't turned
-- up. (An AI stand-in is its slot's unit, SV_Unit_CoopPeer<A-X>: it stays, flown from whoever has the slot now.)
function M.slotFix()
    local me = COOP.slot
    for s, r in pairs(M.roster) do
        local sid, P = r.sid, M.peers[s]
        if s ~= me and sidOk(sid) and not (P and P.sid == sid) then
            local moved = false
            for t, Q in pairs(M.peers) do
                if t ~= s and Q.real and Q.sid == sid and Q.obj then
                    M.peers[s], M.peers[t] = Q, P
                    if type(SV_CoopSwapPP) == "function" then SV_CoopSwapPP(s, t); M.slotSwapped(s, t) end   -- ((0.73.77) what's kept per slot too)
                    Q.shown, Q.ownSlotAt = nil, nil
                    if P then P.shown = nil end
                    log(string.format("coop: player %d is back as player %d: their plane here moved with them", t + 1, s + 1))
                    moved = true
                    break
                end
            end
            if not moved and P and P.real and P.obj and P.sid and P.sid ~= sid then M.retirePeer(s, "the slot is another player's now") end
        end
    end
    local P = me and M.peers[me]
    if P and P.real and P.obj then
        if not P.ownSlotAt then
            P.ownSlotAt = os.clock()
            pcall(function() P.obj:SetActorHiddenInGame(true) end)
            pcall(M.radarOff, P)                         -- ((0.73.83) its blip too)
        elseif os.clock() - P.ownSlotAt >= 10 then
            M.retirePeer(me, "it was in this game's slot, and its player isn't back")
        end
    end
end
local function sidName(sid)
    for _, r in pairs(M.roster) do if r.sid == sid and r.name and r.name ~= "" then return r.name end end
    return nil
end
local becomeHost
local function nextCandidate(now)
    local mg = M.mig
    mg.i = mg.i + 1
    local e = mg.list[mg.i]
    if not e then
        log("coop: migration: none of the next hosts answered; looking for a host as before")
        callout("CO-OP: NO NEW HOST FOUND", "LOOKING FOR A HOST AS BEFORE")
        M.mig, M.hostLostAt = nil, nil
        COOP.reopen("join", "host migration: no next host answered", (mg.oldSid and (mg.oldSid .. ",") or "") .. tostring(cfg().partner or "auto"))
        return
    end
    mg.cand, mg.candAt, mg.candName = e, now, mg.names[e.sid] or ("PLAYER " .. (e.slot + 1))
    if e.sid == M.mySid() then return becomeHost(now) end
    log(string.format("coop: migration: joining %s, the next host (%d of %d in line)", mg.candName, mg.i, #mg.list))
    callout("CO-OP: " .. string.upper(mg.candName) .. " TAKES OVER", "JOINING THEIR GAME...")
    COOP.reopen("join", "host migration", e.sid)
end
becomeHost = function(now)
    local mg, me, c = M.mig, M.mySid(), mig()
    local partners, expect = {}, {}
    for _, e in ipairs(mg.list) do
        if e.sid ~= me then partners[#partners + 1] = e.sid; expect[e.sid] = mg.names[e.sid] or ("PLAYER " .. (e.slot + 1)) end
    end
    partners[#partners + 1] = "auto"
    log(string.format("coop: migration: this game is the next host (%d of %d in line); the others are joining it", mg.i, #mg.list))
    COOP.reopen("host", "host migration", table.concat(partners, ","))
    mg.hosting, mg.expect, mg.hostAt = true, expect, now
    if LB and LB.coopTakeover then pcall(LB.coopTakeover) end   -- ((0.73.77, plan H2) the co-op run's record goes on here)
    killAllCopies("host migration")
    M.retirePeer(0, "the old host's: you're the host now")
    -- the round: the one in play again (between rounds, the next), break_s on and once everyone's back (joinWaiting).
    -- A new D: the next co-op tick sets everything up as a new level's (the units, the copies, "rs").
    local old = D
    local first = (mg.state == "wait") and (mg.round or 0) or math.max(0, (mg.round or 1) - 1)
    D = { round = first, startRound = old and old.startRound or (first + 1), state = "wait", at = ((old and old.now) or 0) + (c.break_s or 15),
          now = old and old.now, queue = {}, spare = {}, up = {}, flown = {}, announced = false, perf = old and old.perf }
    M.rnd = nil
    mg.rebuild, mg.rebuildAt = {}, now + 5
    for _, a in ipairs(M.allyList or {}) do mg.rebuild[#mg.rebuild + 1] = { item = a.item, sid = a.sid, tries = 0 } end
    log(string.format("coop: migration: round %d starts again once everyone's back (up to %d s), %d allies and defences to build again",
        first + 1, c.wait_s or 60, #mg.rebuild))
    callout("YOU ARE THE NEW HOST", string.format("ROUND %d STARTS ONCE EVERYONE'S BACK", first + 1))
end
-- (a host by migration) the allies and defences again, then done
local function afterTakeover(now)
    local mg, c = M.mig, mig()
    if mg.rebuild and now >= (mg.rebuildAt or 0) then
        mg.rebuildAt = now + 3
        for i = #mg.rebuild, 1, -1 do
            local a = mg.rebuild[i]
            local buyer = nil
            for s, r in pairs(M.roster) do if s ~= COOP.slot and a.sid and r.sid == a.sid then buyer = s end end
            local it = CFG.shop and CFG.shop.items and CFG.shop.items[a.item]
            local kind = it and (it.role == "aa" or it.role == "sam" or it.role == "ciws") and it.role or nil
            local okB, ok, msg = false, false, "NOT AVAILABLE"
            if type(shopBuildFor) == "function" then okB, ok, msg = pcall(shopBuildFor, buyer, a.item, 0, kind) end
            a.tries = a.tries + 1
            if okB and ok then
                table.remove(mg.rebuild, i)
                log(string.format("coop: migration: %s built again%s: %s", a.item, buyer and (" for player " .. (buyer + 1)) or "", tostring(msg)))
            elseif a.tries >= 10 then
                table.remove(mg.rebuild, i)
                log(string.format("coop: migration: %s NOT built again (%s)", a.item, okB and tostring(msg) or ("error " .. tostring(ok))))
            end
        end
        if #mg.rebuild == 0 then mg.rebuild = nil end
    end
    if not mg.rebuild and now - (mg.hostAt or now) >= (c.wait_s or 60) then
        log(string.format("coop: migration over: %d players with this game as the host", playerCount()))
        M.migratedFrom, M.mig = mg.oldSid, nil
    end
end
-- (a host by migration that nobody joined, hearing another host: its own link had dropped and the old host is still
-- there) it joins it again. Whether it did.
function M.migStepBack()
    local old = (M.mig and M.mig.hosting and M.mig.oldSid) or M.migratedFrom
    if not old then return false end
    log("coop: migration: nobody joined this game and another host is there: joining it again (this game's link had dropped)")
    callout("CO-OP: THE HOST'S STILL THERE", "JOINING THEM AGAIN")
    M.mig, M.migratedFrom, M.hostLostAt = nil, nil, nil
    COOP.reopen("join", "host migration undone", old .. "," .. tostring(cfg().partner or "auto"))
    return true
end
-- every tick: the host shares, a joiner watches its host, a migration goes on
function M.migTick(now)
    local c = mig()
    if not c.enabled or tostring(cfg().transport or "steam") ~= "steam" then return end
    if COOP.host() then
        hostShare(now)
        if M.mig and M.mig.hosting then afterTakeover(now) end
        return
    end
    if not (COOP.client() and D) then return end
    local mg = M.mig
    if mg then
        if M.state == "linked" then
            log(string.format("coop: migration: linked to %s, the new host", tostring(mg.candName)))
            callout("CO-OP: NEW HOST", string.upper(tostring(mg.candName)) .. " IS HOSTING")
            M.mig, M.hostLostAt = nil, nil
        elseif now - (mg.candAt or now) >= (c.link_s or 20) then
            log(string.format("coop: migration: %s didn't answer in %d s", tostring(mg.candName), c.link_s or 20))
            nextCandidate(now)
        end
        return
    end
    if not (M.hostLostAt and M.succ and #M.succ > 0) then return end
    local wait = c.after_s or 30
    if M.hostAwayUntil and M.hostAwayUntil > M.hostLostAt then wait = math.max(wait, M.hostAwayUntil - M.hostLostAt) end
    if now - M.hostLostAt < wait then return end
    local list, names = {}, {}
    for _, e in ipairs(M.succ) do
        if e.sid ~= M.hostSid then list[#list + 1] = e; names[e.sid] = sidName(e.sid) or ((M.roster[e.slot] or {}).name) end
    end
    if M.mySid() then names[M.mySid()] = M.myName end
    local oldName = playerName(0)
    M.mig = { list = list, names = names, i = 0, oldSid = M.hostSid, round = D.round, state = D.state, at = now }
    log(string.format("coop: migration: the host (%s) silent %.0f s: going down the line of %d", oldName, now - M.hostLostAt, #list))
    callout("CO-OP: " .. string.upper(oldName) .. " (HOST) IS GONE", "FINDING THE NEXT HOST...")
    nextCandidate(now)
end
end

local function onHostMessage(from, f)
    local k = f[1]
    if k == "hi" then
        local ver, rt, row, name = short(f[2], 32), short(f[3], 16), short(f[4], 64), short(f[5], 32)
        local code = short(f[6], 16):match("^%w+$") or ""          -- (their airframe's code: COOP2MP T3)
        local lo = loadoutOk(f[7]) and f[7] or ""                  -- (their loadout: COOP2MP T4b)
        local pt = paintOk(f[8]) and f[8] or ""                    -- (their paint: T5)
        local ac = acClean(f[9])                                    -- (their aircraft's name)
        -- ((0.73.80) a plane with no stock code: its blueprint class's path (a player plane's, /Game/ only) and stock base)
        local cls = M.clsOk(f[10], code) and f[10] or ""
        local base = M.baseOk(f[11]) and f[11]:lower() or ""
        if not name or name == "" then name = (M.linkNames and M.linkNames[from]) or ("PLAYER " .. (from + 1)) end
        local first, was = not M.roster[from], M.roster[from] and M.roster[from].row
        local q = M.linkQuality and M.linkQuality()[from]                -- (their Steam ID, from their link: host migration)
        M.roster[from] = { row = row or "", ver = ver, name = name, code = code, lo = lo, paint = pt, ac = ac,
                           sid = q and q.sid ~= "0" and q.sid or nil, cls = cls, base = base }
        if first then
            log(string.format("coop: player %d is %s, Survival %s, runtime %s, flies %s", from + 1, tostring(name), tostring(ver),
                tostring(rt), (row and row ~= "") and row or "(not yet: no plane)"))
            callout(string.upper(tostring(name)) .. " JOINED", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            if ver ~= VERSION then
                log("coop: WARNING: player " .. (from + 1) .. " runs Survival " .. tostring(ver) .. ", you " .. VERSION)
                callout("CO-OP VERSION MISMATCH", string.upper(tostring(name)) .. " HAS " .. tostring(ver))
            end
            -- (a zip unpacked with the game open leaves the old main.dll in place; SV_Version() answers the build's own
            -- version from runtime 0.28.4: before it, a fixed "0.27.0" for every build)
            local mine = type(SV_Version) == "function" and SV_Version() or nil
            if mine and rt and rt ~= "" and rt ~= "?" and rt ~= mine then
                log("coop: WARNING: player " .. (from + 1) .. " runs runtime " .. tostring(rt) .. ", you " .. tostring(mine)
                    .. " (their dlls/main.dll is another build's: unzip again with the game closed)")
                callout("CO-OP RUNTIME MISMATCH", string.upper(tostring(name)) .. " HAS MAIN.DLL " .. tostring(rt))
            end
            local okS, errS = pcall(M.sendSettings, from)
            if not okS then log("coop: settings not sent: " .. tostring(errS)) end
        elseif row and row ~= "" and row ~= was then
            local P = M.peers[from]
            log(string.format("coop: player %d flies %s%s", from + 1, row, (P and P.obj and P.row and P.row ~= standInRow(row))
                and string.format(" (their plane here stays %s until their next sortie)", P.row) or ""))
        end
        hostRosterSelf()
    elseif k == "jn" then hostSync(from)
    elseif k == "ht" then hostHit(from, tonumber(f[2]) or 0, tonumber(f[3]) or 0)
    elseif k == "ab" then onBuildAsk(from, f)            -- a joiner's ally / defence bought: built here, for everyone
    elseif k == "ao" then onOrder(f, false)              -- a joiner changed the allies' orders
    elseif k == "fx" then M.fxFromJoiner(from, f)       -- a joiner's shots: its plane here fires them, the others told
    elseif (k == "dw" or k == "rv") and DOWN and DOWN.onHost then DOWN.onHost(from, f)   -- (down, a revive: sv_down.lua)
    elseif k == "lb" and LB and LB.coopMsg then LB.coopMsg(f, from)   -- ((0.73.77, plan H2) a joiner's leaderboard name)
    elseif k == "in" then                                -- a joiner's intensity (sv_director.lua P4), once a second
        local i, c = inNum(f[2], 100), inNum(f[3], 100)
        local now = os.clock()
        M.ints = M.ints or {}
        local last = M.ints[from]
        if slotOk(from) and from ~= COOP.slot and i and c and not (last and now - last.at < IN_MIN_GAP_S) then
            M.ints[from] = { i = i, c = c, hp = inNum(f[4], 100), m = inNum(f[5], IN_MSL_MAX), at = now }
        end
    end
end

local function onJoinerMessage(f)
    local k = f[1]
    if k == "cf" then M.onSettings(f)
    elseif k == "fx" then M.fxFromHost(f)               -- a player's shots (the host's, or a joiner's relayed)
    elseif k == "ak" or k == "ax" or k == "ar" then onBuildAnswer(f)   -- the host's say on your ally / defence
    elseif k == "ag" then onOrder(f, true)               -- the allies' orders (the room's: the host's)
    elseif k == "sq" then M.onSuccession(f)              -- host migration: the next hosts, best link first
    elseif k == "al" then M.onAllies(f)                  -- host migration: the allies and defences up
    elseif k == "hl" then M.onHostAway(f)                -- host migration: the host's reloading (a run's end)
    elseif k == "lb" and LB and LB.coopMsg then LB.coopMsg(f)   -- ((0.73.77, plan H2) the co-op run's squad: sv_leaderboard.lua)
    elseif k == "hq" then                                -- the host has no hello from you (peerTick): again, once a second
        if os.clock() >= (M.hqAt or 0) then
            M.hqAt = os.clock() + 1
            sendHi()
            once("hq", "coop: the host asked for your hello (it had none from you): sent")
        end
    elseif (k == "dw" or k == "rb" or k == "rx" or k == "ro" or k == "rc") and DOWN and DOWN.onJoiner then
        -- ((0.73.77, plan A9) the host's run-over while this level still loads: it comes again with the host's picture,
        -- asked for once this game's plane is in the level)
        if k == "ro" and not D then log("coop: the host's run is over (round " .. short(f[2], 8) .. "); this level is still loading: it comes again once it's in") end
        DOWN.onJoiner(f)                                 -- (sv_down.lua)
    elseif k == "rnd" then
        local lv = tonumber(f[8])                         -- (the intensity director's level, P4: a whole 0-3, else none)
        if not (lv and lv == math.floor(lv) and lv >= 0 and lv <= #SPIKE_SUFFIX) then lv = nil end
        local gp = tonumber(f[9])                         -- (AB.L..IN's phase, P7: 1-3, else none)
        if not (gp == 1 or gp == 2 or gp == 3) then gp = nil end
        local sk = tostring(f[11] or ""):match("^%a+$")    -- ((0.73.77, plan D3) the round's special there: a word, or none)
        if sk and #sk > 16 then sk = nil end
        -- ((0.73.77, D4) the special in play there and its state: two words, or none)
        local hk, hst = tostring(f[12] or ""):match("^(%a+):(%a+)$")
        local hs = (hk and #hk <= 16 and #hst <= 16) and { kind = hk, state = hst } or nil
        M.rnd = { round = tonumber(f[2]) or 0, state = f[3], secs = tonumber(f[4]) or 0, wave = tonumber(f[5]) or 0,
                  waves = tonumber(f[6]) or 0, alive = tonumber(f[7]) or 0, level = lv, glitchPhase = gp, got = os.clock(),
                  allies = roomAlliesOf(f[10]), special = sk, hostSpecial = hs }
        -- ((0.73.78, plan G5) the room's VOID WATCHER 1 purchases (the host's count): this game's STORE prices it from it,
        -- as the host checks a joiner's ask)
        local vb = tonumber(f[13])
        if vb and vb == math.floor(vb) and vb >= 0 and vb <= 999 and RUN and RUN.bought and (RUN.bought.VoidWatcher or 0) ~= vb then
            RUN.bought.VoidWatcher, RUN.dirty = vb, true
            log(string.format("coop: VOID WATCHER 1 bought %d times in the room (the host's count): the STORE's price here from it", vb))
        end
        -- ((0.73.78) the room's other allies and defences (f14, "<item>:<n>,...;<kind>:<n>,..."): this game's STORE
        -- prices them from the host's counts, as the host checks a joiner's ask (sv_shop.lua shopBuildFor)
        -- ((0.74.0) field 15: the host's GONE FISHIN' round (the arc's F): kept in RUN, so a migration keeps it here)
        local af = tonumber(f[15])
        if af and af == math.floor(af) and af >= 0 and af <= 100000 and RUN and SKY and SKY.arcSet then
            if af > 0 then SKY.arcSet(af, "the host's")
            elseif RUN.arcF then RUN.arcF = nil; log("coop: the host's run has no GONE FISHIN' (rnd field 15): the arc off here") end
        end
        local fa, fd = tostring(f[14] or ""):match("^([%w:,]*);([%a%d:,]*)$")
        if fa and RUN and RUN.bought then
            local seen = {}
            for nm, n in fa:gmatch("(%a+):(%d+)") do seen[nm] = math.min(999, tonumber(n)) end
            for _, nm in ipairs(M.ROOM_ITEMS) do
                local n = seen[nm] or 0
                if (RUN.bought[nm] or 0) ~= n then
                    RUN.bought[nm], RUN.dirty = n, true
                    log(string.format("coop: %s bought %d times in the room (the host's count): the STORE's price here from it", nm, n))
                end
            end
            RUN.defences = RUN.defences or { built = 0, bought = {} }
            local dseen = {}
            for kd, n in fd:gmatch("(%a+):(%d+)") do dseen[kd] = math.min(999, tonumber(n)) end
            for kd, n in pairs(dseen) do
                if (RUN.defences.bought[kd] or 0) ~= n then
                    RUN.defences.bought[kd], RUN.dirty = n, true
                    log(string.format("coop: the airfield's %s built %d times in the room (the host's count): its price here from it", kd, n))
                end
            end
        end
    elseif k == "pi" then
        local s = tonumber(f[2])
        if not slotOk(s) then return end
        f[3], f[4], f[5] = short(f[3], 64), short(f[4], 32), short(f[5], 32)
        local first, was = not M.roster[s], M.roster[s] and M.roster[s].row
        local sid = tostring(f[10] or ""):match("^%d+$")
        local code = short(f[6], 16):match("^%w+$") or ""
        M.roster[s] = { row = f[3], ver = f[4], name = f[5], code = code,
                        lo = loadoutOk(f[7]) and f[7] or "", paint = paintOk(f[8]) and f[8] or "", ac = acClean(f[9]),
                        sid = (sid and #sid >= 15 and #sid <= 20) and sid or nil,
                        -- ((0.73.80) after the Steam ID: a plane with no stock code's class path and stock base)
                        cls = M.clsOk(f[11], code) and f[11] or "", base = M.baseOk(f[12]) and f[12]:lower() or "" }
        if not first and s ~= COOP.slot and f[3] and f[3] ~= "" and f[3] ~= was then
            local P = M.peers[s]
            log(string.format("coop: player %d flies %s%s", s + 1, f[3], (P and P.obj and P.row and P.row ~= standInRow(f[3]))
                and string.format(" (their plane here stays %s until their next sortie)", P.row) or ""))
        end
        if first and s ~= COOP.slot then
            log(string.format("coop: player %d is %s (Survival %s, flies %s)", s + 1, tostring(f[5]), tostring(f[4]), tostring(f[3])))
            if s == 0 then
                callout("CO-OP LINKED", string.upper(tostring(f[5])) .. " IS HOSTING")
                if f[4] ~= VERSION then callout("CO-OP VERSION MISMATCH", "YOU " .. VERSION .. ", THE HOST " .. tostring(f[4])) end
            else
                callout(string.upper(tostring(f[5])) .. " JOINED", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            end
        end
    elseif k == "po" then
        local s = tonumber(f[2])
        if s and M.roster[s] then
            callout(string.upper(playerName(s)) .. " LEFT", nil)
            M.roster[s] = nil
        end
        if slotOk(s) then M.markLeft(s, "left") end       -- ((0.73.77, plan C1) back in another aircraft: a new plane here)
    elseif k == "rj" then                                -- ((0.73.77) a player's game started over: the same, plan C1)
        local s = tonumber(f[2])
        if slotOk(s) then M.markLeft(s, "started their game over") end
    elseif k == "af" and AF then
        local down = f[4] == "1"
        AF.hp, AF.full, RUN.dirty = tonumber(f[2]) or AF.hp, tonumber(f[3]) or AF.full, true
        local mx = tonumber(f[5])                         -- (the host's maximum: the bar is out of it, not this game's own)
        if mx and mx > 0 and mx ~= AF.max then
            log(string.format("coop: the host's airfield maximum %d here (this game's own setup had %s)", mx, tostring(AF.max)))
            AF.max = mx
        end
        if down ~= (AF.down or false) then
            AF.down = down
            if type(SV_Event) == "function" then SV_Event(down and "RE_SV_AirfieldClose" or "RE_SV_AirfieldOpen") end
            log("coop: the host's airfield is " .. (down and "down: landing closed" or "back up: landing open"))
        end
    elseif k == "co" then
        if cfg().callouts then M.noMirror = true; pcall(hudCallout, short(f[2], 120), f[3] ~= "" and short(f[3], 120) or nil, f[4] == "1"); M.noMirror = false end
    elseif k == "tl" then                                -- a tell (sv_tells.lua): an id this game knows, a number
        local id, a = short(f[2], 32), tonumber(f[3])
        local now = os.clock()
        if now - (M.tlAt or -1) >= 1 then M.tlAt, M.tlN = now, 0 end
        M.tlN = M.tlN + 1                                -- (at most TL_PER_S a second; tells are dropped, never queued:
        if M.tlN <= TL_PER_S and TELL and TELL.known(id) and levelReady()   -- a late one misleads; [coop] callouts is the
            and (a == nil or finite(a, 1e6)) then                           -- host's banners, tells are radio lines)
            local okT, errT = pcall(TELL.play, id, a, "the host")
            if not okT then once("tl", "coop: tell error " .. tostring(errT)) end
        end
    elseif k == "dv" then                                -- the director's event on this game's copies (COOP.dispatch)
        local ev, unit, delay = short(f[2], 64), short(f[3], 96), tonumber(f[4])
        local now = os.clock()
        if now - (M.dvAt or -1) >= 1 then M.dvAt, M.dvN = now, 0 end
        M.dvN = M.dvN + 1                                -- (dropped, never queued past the delay: a late shot misleads)
        local why = (M.dvN > DV_PER_S and "more than " .. DV_PER_S .. " a second") or (not dvName(ev) and "not a director event")
            or (not (delay and finite(delay, 1e6)) and "a bad delay") or (not (D and rawEvent and levelReady()) and "this level isn't ready")
            or (not dvCopy(ev, unit) and "no live copy of it here") or nil
        if why then
            once("dv" .. why, "coop: the host's director event " .. ev .. " dropped (" .. why .. ")")
        else
            M.dvQ = M.dvQ or {}
            if #M.dvQ < 32 then M.dvQ[#M.dvQ + 1] = { at = now + math.max(0, math.min(DV_MAX_S, delay)), name = ev, unit = unit } end
        end
    elseif k == "cr" then
        local n = tonumber(f[2]) or 0
        if finite(n, math.huge) and n > 0 and n <= CREDITS_MAX then
            if M.noDownBonus() then log("revive: the host's round bonus (" .. math.floor(n) .. ") not paid: you're down (down_round_bonus off)")
            else addCredits(math.floor(n), short(f[3], 80) .. " (the host's round)") end
        end
    elseif k == "sp" then
        local unit, pose, ops = short(f[2], 96), nil, {}
        if f[3] and f[3] ~= "-" then
            local p = {}
            for v in f[3]:gmatch("[^,]+") do p[#p + 1] = tonumber(v) end
            if #p == 4 and finite(p[1], 1e10) and finite(p[2], 1e10) and finite(p[3], 1e10) and finite(p[4], 1e6) then pose = p end
        end
        if f[4] and f[4] ~= "-" then
            for op in f[4]:gmatch("[^;]+") do
                local row, idx = op:match("^(.-)@(-?%d+)$")
                if row then ops[#ops + 1] = { row = row, idx = tonumber(idx) } end
            end
        end
        local gen = tonumber(f[6]) or 0
        local rp = M.rep
        local rep = rp ~= nil and not rp.done                 -- ((0.73.73) part of the host's picture: a repair's)
        if rep then rp.units[unit] = { gen = gen, alive = {}, galive = {} } end
        M.spawnQ[#M.spawnQ + 1] = { unit = unit, pose = pose, ops = ops, level = tonumber(f[5]), gen = gen, rep = rep }
    elseif k == "bd" then
        local unit, gen, ord, id = short(f[2], 96), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        if not M.bdLast or (M.bdLastN or 0) > 512 then M.bdLast, M.bdLastN = {}, 0 end   -- (the last generation's
        local bl = M.bdLast[unit]                                                         -- ids per unit: strayTick's
        if not bl or bl.gen ~= gen then                                                   -- bound line; capped)
            if not bl then M.bdLastN = M.bdLastN + 1 end
            bl = { gen = gen, n = 0 }; M.bdLast[unit] = bl
        end
        bl.n = bl.n + 1
        if not (gen and ord and id) then return end
        M.dead[id] = nil                                 -- ((0.73.73) named by the host now: up, until its "dn" says not)
        repNote(unit, gen, id, ord, nil)
        local cu = M.cunits[unit]
        if not cu or cu.gen ~= gen then
            -- (its spawn here still to come, queued or not yet sent: kept for it, not dropped. The co-op run of 2026-10-30:
            -- a joiner still loading as the host's round came in got 1 bind of 4, and its other copies flew on by their own
            -- AI. (0.73.73) Never as an empty flight of that generation in M.cunits: it took the place of the copies still up
            -- here, which doSpawn then never took down, and the host's spawn was refused: "its last flight is still up")
            pendKeep(unit, gen, "binds", ord, id)
            return
        end
        local o, c = cu.planes[ord], M.copies[id]
        -- (0.73.73 review) a copy kept through a repair (rs|j) may have been freed since: bindCopy calls into it
        -- (SetMinHealth), which a pcall can't catch on a freed object: checked live first, as "gd" does
        local oa = o and live(o)
        if o and not oa then cu.planes[ord] = nil; o = nil end
        if o and M.rep and not M.rep.done and not (c and c.addr == oa) then M.rep.rebound = M.rep.rebound + 1 end
        cu.binds[ord] = id
        if o then bindCopy(id, o, unit, ord) end
    elseif k == "gd" then                                -- a ship's, vehicle's or part's id (hostGround)
        local unit, gen, key, id = short(f[2], 96), tonumber(f[3]), short(f[4], 96), tonumber(f[5])
        if not (gen and id and id >= 1 and id <= 65535 and id == math.floor(id)) then return end
        M.dead[id] = nil                                 -- ((0.73.73) as a plane's "bd")
        repNote(unit, gen, id, nil, key)
        local cu = M.cunits[unit]
        if not cu or cu.gen ~= gen then pendKeep(unit, gen, "gbinds", key, id); return end   -- (as a plane's "bd")
        cu.gbinds = cu.gbinds or {}
        cu.gbinds[key] = id
        local o = cu.gobjs and cu.gobjs[key]
        if o and live(o) then bindGround(id, o, unit, key) end
    elseif k == "hp" then
        -- ((0.73.77, plan A2) never onto a copy that's down here: 0.73.76 wrote the host's health back onto wrecks,
        -- invisible enemies with target boxes no hit could finish; each one skipped is counted for the sync report)
        for id, h in (f[2] or ""):gmatch("(%d+):(%-?%d+)") do
            local c = M.copies[tonumber(id)]
            h = tonumber(h)
            -- ((code review of 2026-11-07, finding 6) never onto this game's copy of SAL's boat: an older host sends it)
            if c and FISH and FISH.isBoat and FISH.isBoat(c.unit) then c = nil end
            if c and h and h > 0 and live(c.obj) then
                local own = health(c.obj)
                if own and own <= 0 then
                    M.cnt.hpDead = M.cnt.hpDead + 1
                elseif own then
                    local v = math.min(math.max(h, 1), 2147483647)
                    -- ((0.73.79) a hit here not yet sent (it landed since clientTick's last look) stays on it: 0.73.78
                    -- wrote the host's health over it and set what's expected to match, so clientTick never saw the
                    -- loss and it was never sent. And for a moment after a hit was sent, the host's health from before
                    -- it landed doesn't put the copy back up (it flickered back to full on every hit)
                    local pend = (not c.ally and c.exp and own < c.exp) and (c.exp - own) or 0
                    if pend == 0 and v > own and c.sentAt and c.sentFrom and v <= c.sentFrom   -- (no more than it had
                        and os.clock() - c.sentAt < HP_HOLD_S then                               -- before: from before it)
                        c.hp = v                               -- (held: the host's next "hp" has your hit in it)
                        M.cnt.hpHeld = (M.cnt.hpHeld or 0) + 1
                    else
                        local w = v - pend
                        if pend > 0 and w < FLOOR_IN then w = FLOOR_IN end
                        pcall(function() c.obj.HealthInternal = w end)
                        c.exp, c.hp = v, v                     -- (hp: the host's own, an ally's copy put back to it)
                        if w > FLOOR_IN then floorDone(c) end  -- (off the floor: the host's has more than you sent)
                    end
                end
            end
        end
    elseif k == "dn" then
        local id = tonumber(f[2])
        if id then
            M.dead[id] = true
            local rp = M.rep
            local r = rp and not rp.done and rp.ids[id]       -- (the host's picture: down there)
            local pu = r and rp.units[r.unit]
            if pu then if r.ord then pu.alive[r.ord] = nil else pu.galive[r.key] = nil end end
            local c = M.copies[id]
            if c then
                -- ((0.73.77, economy C1) who made the kill, named by the host (field 4: a player's slot; a, s, d: the allies,
                -- the allied ships, the airfield's defences): this game's pay for it goes by it (KILL.by, M.killerOf))
                if f[3] ~= "r" and c.addr and f[4] and f[4] ~= "" then
                    M.killer = M.killer or {}
                    M.killer[c.addr] = { code = short(f[4], 2), at = os.clock() }
                end
                floorDone(c)                                   -- ((0.73.77, A6) its wait at the floor, if it had one)
                -- ((0.73.73) forced: the host's is down, invincible here or not; "dn|<id>|r", a death the host's picture
                -- repeats, is long since: not this game's kill. Off its flight's planes here: strayTick counted it a stray)
                -- ((0.73.80) yours (the host named this game's player): with your plane as its cause, M.dnKill)
                M.dnKill(id, c, f)
                M.copies[id] = nil
                local cu = c.unit and M.cunits[c.unit]
                if cu and c.ord and cu.planes[c.ord] and addrOf(cu.planes[c.ord]) == c.addr then cu.planes[c.ord] = nil end
                if cu and c.key and cu.gobjs and cu.gobjs[c.key] and addrOf(cu.gobjs[c.key]) == c.addr then cu.gobjs[c.key] = nil end
            end
        end
    elseif k == "ev" then
        local unit = (f[3] and f[3] ~= "") and short(f[3], 96) or nil   -- ((0.73.73) a replay for that unit's fresh copy)
        if mirroredEvent(f[2]) and D and rawEvent and not levelReady() then    -- (held until this level is ready)
            M.evQ = M.evQ or {}
            if #M.evQ < 64 then M.evQ[#M.evQ + 1] = { name = short(f[2], 64), at = os.clock(), unit = unit } end
        elseif mirroredEvent(f[2]) and D and rawEvent and not keptThrough(unit, f[2]) then
            hostEvent(f[2])
        end
    elseif k == "wd" and COOP.client() then              -- ((review of 27097b9, finding 3) a flight the host took off: COOP.withdrawn
        local unit = short(f[2], 96)
        if unit ~= "" and flightWithdrawn then
            log(string.format("coop: the host took %s off (withdrawn, no despawn event): %d of its copies here off, unpaid",
                unit, flightWithdrawn(unit)))
        end
    elseif k == "db" and COOP.client() then              -- ((0.73.77, I2: S9) the host's penalty: off your zollars too
        local n = tonumber(f[2]) or 0
        if finite(n, math.huge) and n > 0 and n <= CREDITS_MAX and SPORT and SPORT.debit then
            SPORT.debit(math.floor(n), short(f[3], 80), true)
        end
    elseif k == "dk" and COOP.client() then              -- (THE DECOY: its round, each UAV's lock and cancel: sv_decoy.lua)
        if DECOY and DECOY.fromHost then
            local okDk, errDk = pcall(DECOY.fromHost, f)
            if not okDk then once("dk", "coop: the host's DECOY message not read: " .. tostring(errDk)) end
        end
    elseif k == "sb" and COOP.client() then              -- ((0.74.0) a subtitle line of the host's round: SUB.say)
        local secs = tonumber(f[4])
        if SUB and SUB.sayHere and f[3] and f[3] ~= "" and (secs == nil or finite(secs, 60)) and levelReady() then
            SUB.sayHere(short(f[2], 32), short(f[3], 160), (secs and secs > 0) and math.max(1, math.min(20, secs)) or nil)
        end
    elseif (k == "fh" or k == "fsx" or k == "fw" or k == "fwe") and COOP.client() then   -- ((0.74.0) GONE FISHIN' and THE
        if FISH and FISH.fromHost then                                                    -- FESTIVAL: sv_fishing.lua
            local okF, errF = pcall(FISH.fromHost, k, f)
            if not okF then once("fish" .. k, "coop: the host's " .. k .. " not read: " .. tostring(errF)) end
        end
    elseif k == "spx" and COOP.client() then             -- ((0.73.77, I7: S12) the host's Spaceport: its row, a retake due)
        if SPORT and SPORT.fromHost then
            local okS, errS = pcall(SPORT.fromHost, short(f[2], 400))
            if not okS then once("spx", "coop: the host's Spaceport state not read: " .. tostring(errS)) end
        end
    elseif k == "es" and COOP.client() then              -- ((2026-11-06) THE ESCORT's state, the ZFA-44 carriers: sv_escort.lua
        if ESC and ESC.onHost then
            local okE, errE = pcall(ESC.onHost, f)
            if not okE then once("es", "coop: the host's escort state not read: " .. tostring(errE)) end
        end
    elseif k == "vm" and COOP.client() then              -- ((0.73.76) the host's VALKA mood: the red sky and her song here too)
        M.valkaHere(f[2] == "1", "the host's")           -- ((0.73.77) said when it can't be here too: D2)
    elseif k == "vr" and COOP.client() then              -- ((0.73.76) she shows: her X-02S on this game's copy of her)
        local unit = short(f[2], 96)
        if D and unit == (CFG.specials.valka and CFG.specials.valka.unit) then M.vr = { unit = unit, at = os.clock(), st = {} } end
    elseif k == "rz" then                                -- ((0.73.73) the end of the host's picture: what's here settled)
        if M.rep and not M.rep.done then repairDone("rz") end
    elseif k == "rs" then
        M.cnt.rsGot = M.cnt.rsGot + 1
        -- ((0.73.73) "rs|j": the host's answer to this game's own "jn", a repair: nothing torn down, no new run here,
        -- nobody DOWN brought back, the round's records kept)
        if f[2] == "j" then return onResync() end
        -- "rs|n": the host's new run; "rs|m": a host by migration in its level (the same run, the round in play again);
        -- a bare "rs" (before 0.73.73): the host's new run, or its answer to this game's own "jn" of the last 15 s
        local resync = f[2] == "m" or ((f[2] == nil or f[2] == "") and M.jnAt ~= nil and os.clock() - M.jnAt < 15)
        M.evQ, M.dvQ, M.holdQ = nil, nil, nil
        -- ((0.73.77, plan D2) VALKA's mood off here: the host's picture says it again if she's still up there)
        if M.vmHere then M.valkaHere(false, resync and (f[2] == "m" and "a new host's level" or "the host's resync") or "the host's run started over") end
        killAllCopies(resync and (f[2] == "m" and "a new host's level" or "the host's resync") or "the host's run started over")
        -- ((0.73.73) only the host's new run brings a player who's DOWN back: Shazzy, A02 11:26:02, "revive: back (the host's
        -- run started over) after 81 s down" on the answer to his own "jn", and A09, A10, A12 the same)
        if not resync and DOWN and DOWN.reset then pcall(DOWN.reset, "the host's run started over") end
        -- (the measurements, sv_stats.lua: the open round ends here, not at the host's next round number; the host's new run
        -- ends the run's records too)
        if STATS and D then pcall(STATS.hostReset, D.now, resync) end
        -- (the host's new run: the money and gear start over here too)
        if D and not resync and type(newRunHere) == "function" then
            local okN, errN = pcall(newRunHere, "the host's run started over")
            if not okN then log("run: error " .. tostring(errN)) end
        end
        if D then D.round, D.state, M.rnd = 0, "wait", nil end
    end
end

local function onSys(from, what, f)
    if what == "joined" or what == "paired" or what == "restart" or what == "up" or what == "left" then
        M.lostAt[from] = nil                              -- ((0.73.80) linked again, or gone: no lost link held for them)
        -- ((review of 0.73.80) a rejoin or a game started over: their last states are from before it)
        if what ~= "up" then M.stateAt[from], M.freshAt[from] = nil, nil end
    end
    if what == "joined" then                              -- (host) a joiner linked: its "hi" names it
        log("coop: player " .. (from + 1) .. " linked")
    elseif what == "paired" or what == "restart" then      -- (joiner) the host; (either) a game started over
        if from == 0 then M.hostLostAt = nil end          -- (host migration: the host's back, or a new one)
        sendHi()
        if COOP.client() and D then killAllCopies("new link"); M.jnAt = os.clock(); send(true, "jn") end
        if COOP.host() and what == "restart" then
            M.roster[from] = nil
            -- ((0.73.77, plan C1) their game started over: back in another aircraft, their plane here goes; the joiners too)
            M.markLeft(from, "started their game over")
            send(true, "rj", from)
        end
    elseif what == "slot" then
        COOP.slot = tonumber(f[3])
        log("coop: you are player " .. tostring((COOP.slot or -1) + 1))
    elseif what == "lost" then
        M.wasLost = M.wasLost or {}
        M.wasLost[from] = true
        callout("CO-OP LINK LOST", string.upper(playerName(from)))
        if from == 0 and COOP.client() then M.hostLostAt = M.hostLostAt or os.clock() end   -- (host migration's clock)
        if COOP.host() and from ~= COOP.slot then M.noteLost(from) end   -- ((0.73.80) in the mission or loading: the round's hold)
    elseif what == "up" then
        if from == 0 then M.hostLostAt = nil end
        if M.wasLost and M.wasLost[from] then             -- (the first "up" comes right after "paired" / "joined")
            M.wasLost[from] = nil
            callout("CO-OP LINK BACK", string.upper(playerName(from)))
            -- (a joiner says hello again: the host may have dropped it meanwhile, its roster entry gone, and this game
            -- can't tell; the co-op run of 2026-10-31)
            if COOP.client() then sendHi() end
            if COOP.client() and D then killAllCopies("link back"); M.jnAt = os.clock(); send(true, "jn") end
        end
    elseif what == "left" then
        callout(string.upper(playerName(from)) .. " LEFT", nil)
        M.roster[from] = nil
        local P = M.peers[from]
        if P and P.obj then
            pcall(function() P.obj:SetActorHiddenInGame(true) end); P.shown = false
            local radar = M.radarOff(P)                  -- ((0.73.83) its blip too)
            if radar then log(string.format("coop: player %d's plane hidden (left): %s", from + 1, radar)) end
        end
        if COOP.host() then send(true, "po", from) end
        if from ~= 0 then M.markLeft(from, "left") end     -- ((0.73.77, plan C1) a rejoin in another aircraft: a new plane)
    elseif what == "full" then
        callout("CO-OP: THE HOST'S GAME IS FULL", nil)
    elseif what == "badver" then                          -- (joiner, runtime 0.32.6) the host runs another build
        local hv = upperText(f[3], 32)
        log(string.format("coop: the host runs Survival %s, this game %s: another build doesn't link (update to the host's)",
            tostring(f[3] or "?"), VERSION))
        callout("CO-OP: THE HOST HAS " .. (hv ~= "" and hv or "ANOTHER BUILD"), "UPDATE SURVIVAL TO JOIN (YOU HAVE " .. upperText(VERSION, 32) .. ")")
    elseif what == "refused" then                         -- (host) a joiner of another build turned away (coop.c)
        local nm, jv = upperText(f[3], 20), upperText(f[4], 32)
        log(string.format("coop: %s tried to join with Survival %s (yours %s): refused", tostring(f[3] or "?"), tostring(f[4] or "?"), VERSION))
        callout("REFUSED " .. (nm ~= "" and nm or "A PLAYER"), "THEY HAVE " .. (jv ~= "" and jv or "ANOTHER BUILD") .. ": UPDATE TO " .. upperText(VERSION, 32))
    elseif what == "samerole" then
        if COOP.host() and playerCount() <= 1 and M.migStepBack and M.migStepBack() then
            -- (a host by migration that nobody joined hears another host: its own link had dropped, the old host's
            -- still there; it joins it again)
        elseif M.auto and COOP.host() and playerCount() <= 1 and not D then   -- (an automatic host, alone, not in a run)
            log("coop: another host found; this game was hosting only because it found none (role auto): joining")
            COOP.reopen("join", "another host found")
            callout("CO-OP: ANOTHER HOST FOUND", "JOINING THEM")
        elseif M.auto then
            callout("CO-OP: TWO HOSTS", "RETRY FROM THE MENU TO JOIN THE OTHER")
        else
            callout("CO-OP: TWO HOSTS", "ONLY ONE OF YOU PICKS HOST: THE OTHERS PICK SURVIVAL CO-OP: JOIN")
        end
    end
end

local function onMessage(raw)
    local slot, body = raw:match("^(%d+)|(.*)$")     -- ("<sender's slot>|...": the slot in decimal from runtime 0.24.0)
    local from = tonumber(slot) or 0
    body = body or raw
    local f = split(body)
    for i = 2, #f do f[i] = f[i]:gsub("%c", "") end
    if f[1] == "sys" then
        log("coop: player " .. (from + 1) .. ": " .. body)
        return onSys(from, f[2], f)
    end
    if COOP.host() then return onHostMessage(from, f) end
    if from == 0 then return onJoinerMessage(f) end
end

---------------------------------------------------------------------------------------------------- the rest of the runtime, wrapped
local rawRoundsTick, rawAirfieldTick, rawBombTick = roundsTick, airfieldTick, bombTick
local function mirrored(fn, ...)                    -- the host's own round logic: its callouts and bonuses go out
    M.mirror = M.mirror + 1
    local ok, err = pcall(fn, ...)
    M.mirror = M.mirror - 1
    if not ok then error(err, 0) end
end
roundsTick = function(now)
    if COOP.client() then return clientRounds(now) end
    return mirrored(rawRoundsTick, now)
end
airfieldTick = function(tick)
    if COOP.client() then return end                -- (the host's airfield: "af")
    return mirrored(rawAirfieldTick, tick)
end
bombTick = function(tick)
    if COOP.client() then return end                -- (the host's bombers bomb the host's airfield)
    return mirrored(rawBombTick, tick)
end
-- (0.73.77, plan D3) A joiner's special rounds are the host's. Its music (sv_flights.lua musicTick: the round's special
-- from specialFor) followed this game's own dice (RUN.specialPick, rolled here for rounds the host decided), so the
-- host's special rounds played a normal round's music here and the other way round, and the log named specials the host
-- never had. The host sends its round's special in "rnd" (field 11); a joiner's specialFor answers from it (none for a
-- round the host hasn't said). M.roundSpecial (the host's "rnd"): the round's special as specialFor has it, never
-- rolling a round's dice before its time (a run started at a later round would have its first round's rolled here).
do
local rawSpecialFor = specialFor
specialFor = function(round)
    if not COOP.client() then return rawSpecialFor(round) end
    local r = M.rnd
    if not (r and r.round == round) then return nil end
    if M.spSaid ~= round then
        M.spSaid = round
        log(string.format("coop: round %d is %s on the host: a %s round's music here", round,
            r.special and ("its " .. r.special .. " special") or "a normal round", r.special and "special" or "normal"))
    end
    return r.special
end
function M.roundSpecial(round)
    local sp = CFG.specials
    if type(sp) == "table" and sp.enabled and sp.random and type(sp.rotation) == "table" and #sp.rotation > 0 then
        local pick = RUN and RUN.specialPick
        local retake = RUN and RUN.sport and RUN.sport.retakeRound == round
        if not retake and not (pick and pick[round] ~= nil) then return nil end   -- (not picked yet: not rolled here)
    end
    return rawSpecialFor(round)
end
end
local rawCallout = hudCallout
hudCallout = function(text, sub, big)
    rawCallout(text, sub, big)
    if COOP.host() and M.mirror > 0 and not M.noMirror and cfg().callouts then send(true, "co", text or "", sub or "", big and 1 or 0) end
end
-- ((0.74.0) a subtitle line of the host's round logic goes to every joiner too, "sb", as a callout's "co"; SUB.sayHere never)
if SUB and SUB.say then
    local rawSay = SUB.say
    SUB.say = function(speaker, text, secs)
        local ok = rawSay(speaker, text, secs)
        if ok and COOP.host() and M.mirror > 0 and not M.noMirror then
            send(true, "sb", tostring(speaker or ""):sub(1, 32), tostring(text or ""):sub(1, 160), string.format("%.1f", tonumber(secs) or 0))
        end
        return ok
    end
end
local rawAddCredits = addCredits
-- (a round's bonus while you're DOWN, sv_down.lua: paid unless [coop.revive] down_round_bonus is off)
function M.noDownBonus()
    local rv = CFG.coop and CFG.coop.revive
    return DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true and type(rv) == "table" and rv.down_round_bonus == false
end
addCredits = function(n, why)
    if M.ownPay then return rawAddCredits(n, why) end   -- ((0.74.0) COOP.payOwn: this game's own, whole, never sent)
    local bonus = M.mirror > 0 and type(why) == "string" and not why:find(" down %(") and n > 0
    -- ((0.73.78, economy C3) a special's pay split: the host pays and sends each player's share, so every game pays the
    -- same, the joiners from "cr" as before; specialPay (sv_ai.lua) shows the same on the special's callout)
    if COOP.host() and bonus and M.specialPay(why) then
        local x = COOP.specialShare()
        if x < 1 then
            local whole = n
            n = specialPay(whole)
            why = string.format("%s, co-op share x%.2f of %d (%d players)", why, x, whole, playerCount())
        end
    end
    if COOP.host() and bonus and M.noDownBonus() then
        log("revive: the round's bonus (" .. tostring(n) .. ") not paid: you're down (down_round_bonus off)")
    else
        rawAddCredits(n, why)
    end
    if COOP.host() and bonus then send(true, "cr", n, why) end
end
local rawLogPlane = logPlane
logPlane = function(o, unit, k)
    local slot = unit and SLOT_OF[unit]
    if slot and M.unitSlot[unit] then slot = M.unitSlot[unit] end   -- ((0.73.77) a free unit flown for another player: plan C4)
    if slot then
        local ok, err = pcall(COOP.peerPlane, o, slot)
        if not ok then log("coop: player plane error " .. tostring(err)) end
        return
    end
    rawLogPlane(o, unit, k)
    if COOP.open and unit and valid(o) and inSurvival(o) then
        local ok, err = pcall(COOP.host() and hostPlane or clientPlane, o, unit)
        if not ok then log("coop: plane error " .. tostring(err)) end
    end
end
local rawRead = KILL.read
KILL.read = function(p)
    rawRead(p)
    local a = p and valid(p.obj) and addrOf(p.obj)
    local j = a and M.joinHits and M.joinHits[a]
    if j and j > 0 then
        p.dmg = p.dmg or {}
        p.dmg.wingmate = math.max(p.dmg.wingmate or 0, j)
    end
end
local rawSide = KILL.side
KILL.side = function(o, pawnAddr)
    local a = addrOf(o)
    if a then for _, P in pairs(M.peers) do if P.addr and P.addr == a then return "wingmate" end end end
    return rawSide(o, pawnAddr)
end
-- (0.73.77, economy C1) the player (or side) the host named for plane p's kill: the host's own (hostKiller), a joiner's
-- from its "dn" (M.killer); nil when none was named (a copy lost here on its own, an older host: as before)
function M.killerOf(p)
    local a = p and (p.addr or (live(p.obj) and addrOf(p.obj)))
    if not a then return nil end
    if COOP.host() then
        for _, e in pairs(M.byId) do
            if e.addr == a then local okK, kl = pcall(hostKiller, e); return okK and kl or nil end
        end
        return nil
    end
    local k = M.killer and M.killer[a]
    if not k then return nil end
    local s = tonumber(k.code)
    if s and slotOk(s) then return { slot = s } end
    for side, code in pairs(KILL_SIDE_CODE) do if code == k.code then return { side = side } end end
    return nil
end
-- every game pays a kill by the player the host named: its own x1, a teammate's x COOP.teamShare() (sv_main.lua
-- creditKill: p.killer, the teammate's slot, for its line); a side's (allies, ships, defences) x ally_x as before.
-- p.hostNamed on a joiner (its kills line says so).
local rawBy = KILL.by
KILL.by = function(p)
    local kl = COOP.open and M.killerOf(p) or nil
    if kl then
        p.killer, p.hostNamed = kl.slot, COOP.client() or nil
        if kl.slot then return kl.slot == (COOP.slot or 0) and "you" or "wingmate" end
        return kl.side
    end
    if rawBy then return rawBy(p) end
    return "you"
end
-- (0.73.77, economy C1, approved 2026-11-03) a teammate's kill pays min(team_x, 1 / (players - 1)) of a kill on every
-- game, the host's as a joiner's: 0.5 with 2 or 3 players, 0.33 with 4, 0.25 with 5 (CFG.credits.team_x, the host's
-- setting), so the others' kills add about one more of your own however many fly
function COOP.teamShare()
    local cap = tonumber(CFG.credits and CFG.credits.team_x) or 0.5
    local n = COOP.open and playerCount() or 1
    return math.min(cap, 1 / math.max(1, n - 1))
end
-- (0.73.78, economy C3, approved 2026-11-03) a special's reward in co-op pays each player x players ^ -special_split
-- (CFG.credits.special_split, the host's setting, 0-1): 0.5 = 1 / sqrt(players), 0.71 with 2, 0.58 with 3, 0.5 with 4,
-- 0.45 with 5; 1 solo or alone. Every game paid the whole reward before, so a special put N rewards into the run.
function COOP.specialShare()
    local e = tonumber(CFG.credits and CFG.credits.special_split) or 0.5
    local n = COOP.open and playerCount() or 1
    if n <= 1 or not (e > 0) then return 1 end
    return math.min(1, n ^ -math.min(e, 1))
end
-- a pay of the host's round logic that is a special's (its reward, or what it pays as it goes: landing craft, the
-- spaceport's fleet, ballast tanks, rockets ...): every one the joiners are sent ("cr") but the round's bonus
function M.specialPay(why) return type(why) == "string" and not why:find("^round %d+ cleared") end
-- ((0.73.78) the allies priced room-wide besides VOID WATCHER 1 (its own count is "rnd" field 13): the host's counts of
-- them in "rnd" field 14, with the defences')
M.ROOM_ITEMS = { "Moonchild", "Wingmen", "ShipAegis", "ZfaCarrier" }   -- ((2026-11-06) the ZFA-44 carriers: sv_escort.lua)
-- ((0.73.77, plan H2) for the co-op run's squad, sv_leaderboard.lua: a slot's roster entry (name, sid, code; read
-- only) and this game's Steam ID)
function COOP.roster(slot) return M.roster[slot] end
function COOP.mySid() return M.mySid and M.mySid() or nil end
local rawSend = LB.send
LB.send = function(sh)
    if COOP.open and not cfg().leaderboard then
        log("leaderboard: a co-op run; not sent (CFG.coop.leaderboard)")
        if sh then sh.state = "local" end
        return
    end
    return rawSend(sh)
end

---------------------------------------------------------------------------------------------------- the tick
-- (Re)opens the link as role ("host" | "join"). Role auto (the default from coop.3; user, 2026-10-25: friends set
-- role = join and their games still all hosted) opens as a joiner; if no host is found in AUTO_WAIT (+ up to as much
-- again at random, so two such games don't host at once) it reopens as the host, and an automatic host that meets
-- another host while alone and before a run joins that one (onSys "samerole").
local AUTO_WAIT = 10                                  -- (s; up to twice that, at random)
-- partner: who to look for this time (host migration: the next host's Steam ID, or every player's for the new host),
-- else CFG.coop.partner
function COOP.reopen(role, why, partner)
    local c = cfg()
    local r = SV_CoopOpen(c.transport or "steam", role, partner or c.partner or "auto", c.port or 27777, c.interp_ms or 120, VERSION,
                          maxPlayers())
    COOP.open, COOP.role, COOP.slot = r == 1, role, role == "host" and 0 or nil
    M.state, M.roster = nil, {}
    if role == "host" then M.restoreMine() end          -- (you host: your own settings)
    M.autoAt = os.clock() + AUTO_WAIT + math.random() * AUTO_WAIT
    log(string.format("coop: %s as the %s over %s (partner %s, up to %d players; %s): %s", r == 1 and "open" or "NOT open",
        role == "host" and "host" or "joiner", tostring(c.transport), tostring(partner or c.partner or "auto"), maxPlayers(), why,
        r == 1 and (role == "host" and "looking for players" or "looking for the host") or
        ({ [-1] = "bad settings", [-2] = "Steam not available", [-3] = "UDP not available", [-4] = "partner isn't an IP address" })[r] or tostring(r)))
    if COOP.open and COOP.host() and M.myName ~= nil then hostRosterSelf() end
    return r
end

-- Opens co-op for this game: the role from CFG.coop.role (auto unless set), your name, and you in the roster as host
local function openCoop(why, picked)
    local c = cfg()
    if type(SV_CoopOpen) ~= "function" then log("coop: dlls/main.dll has no co-op (0.22.0 or later needed)"); return end
    local role = picked or tostring(c.role or "auto"):lower()              -- (the main menu's choice before the ini's)
    if role == "joiner" or role == "client" then role = "join" end
    if role ~= "host" and role ~= "join" then role = "auto" end
    M.auto, M.linkedOnce = role == "auto", false
    log("coop: role " .. role .. (M.auto and " (a joiner that hosts if it finds no host)" or "") ..
        (picked and " picked on the main menu" or " from CFG.coop.role"))
    COOP.reopen(M.auto and "join" or role, why)
    if not COOP.open then return end
    if type(SV_SteamName) == "function" then local okN, nm = pcall(SV_SteamName); if okN and type(nm) == "string" then M.myName = nm end end
    local own = tostring(c.name or ""):gsub("[%c|,;]", ""):match("^%s*(.-)%s*$")
    if own ~= "" then
        local n = utf8 and utf8.len(own)                                  -- (20 characters, not bytes)
        if n then M.myName = n <= 20 and own or own:sub(1, utf8.offset(own, 21) - 1) else M.myName = own:sub(1, 20) end
        log("coop: your name for the other players: " .. M.myName .. " (CFG.coop.name)")
    end
    if COOP.host() then hostRosterSelf() end
end

-- ((2026-11-07) Talos: his music "glitched out whenever he alt tabbed": the engine paused the game when its window lost
-- focus (UEngine bPauseOnLossOfFocus), COOP.tick's online-style pause undid it a tick later, and that pause / resume
-- churn on the music restarted his track twice (his log: the music player's clock back to 19 ms and 39 ms, no "next
-- track"). While another player is linked a pause can't hold anyway, so the engine isn't asked to pause on a lost focus;
-- its own value goes back when nobody's linked or co-op closes. The engine outlives every level: found once (no walk
-- while walks are held), checked live before each use.
local FOCUS = { eng = nil, orig = nil, off = false }
function COOP.focusPause(wantOff, why)
    wantOff = wantOff and true or false
    if wantOff == FOCUS.off then return end
    if not (FOCUS.eng and liveObj(FOCUS.eng)) then
        if walkHold and walkHold() then return end
        FOCUS.eng = FindFirstOf("LiveGameEngine") or FindFirstOf("GameEngine")
        if not (FOCUS.eng and liveObj(FOCUS.eng)) then FOCUS.eng = nil; once("focus engine", "coop: the game engine not found: the pause on a lost focus left as it is"); return end
    end
    local eng = FOCUS.eng
    if wantOff then
        local okR, v = pcall(function() return eng.bPauseOnLossOfFocus end)
        local okW = pcall(function() eng.bPauseOnLossOfFocus = false end)
        if not okW then once("focus write", "coop: bPauseOnLossOfFocus could not be set: the game still pauses on a lost focus"); return end
        FOCUS.orig, FOCUS.off = okR and v or nil, true
        log(string.format("coop: the game won't pause when its window loses focus while others are linked (alt-tab; "
            .. "bPauseOnLossOfFocus %s -> false; %s)", tostring(FOCUS.orig), tostring(why)))
    else
        if FOCUS.orig ~= nil then pcall(function() eng.bPauseOnLossOfFocus = FOCUS.orig end) end
        FOCUS.off = false
        log(string.format("coop: the game's own pause on a lost focus back (bPauseOnLossOfFocus %s; %s)", tostring(FOCUS.orig), tostring(why)))
    end
end

local function closeCoop(why)
    if type(SV_CoopClose) == "function" then SV_CoopClose() end
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    M.state, M.roster, M.linkedOnce, M.wasLost = nil, {}, false, nil
    M.restoreMine()
    pcall(COOP.focusPause, false, "co-op closed")
    log("coop: closed (" .. why .. ")")
end

-- Each player's name on their plane's target box (user, 2026-10-26: "we need to get player names working on the HUD
-- always"): the stand-ins SV_Unit_CoopPeer<A-X> carry the callsign key SV_CoopName_<A-X> (NAME_KEYS;
-- tools/build_survival.py COOP_NAME_KEYS), whose text is set here whenever a name changes
local function upperName(s, max)
    s = string.upper(tostring(s or ""))
    local n = utf8 and utf8.len(s)
    if n and n > max then return s:sub(1, utf8.offset(s, max + 1) - 1) end
    return n and s or s:sub(1, max)
end
local function nameTick()
    if type(SV_SetText) ~= "function" then return end
    M.nameSet = M.nameSet or {}
    for s = 0, MAX_SLOT do
        -- ((0.73.77) a stand-in unit flown for another player, plan C4: its name key says theirs)
        local n = upperName(playerName(M.unitSlot[PEER_UNITS[s]] or s), 20)
        if M.nameSet[s] ~= n then
            M.nameSet[s] = n
            pcall(SV_SetText, NAME_KEYS[s], n)
        end
    end
end

-- The HUD's co-op row (sv_hud.lua hudTick): who is playing, the host first and marked, in plain words; nil when solo.
-- Its second value is the row's news for the info key: who's in, links lost and who's shot down (not health, where they
-- are or a state gone stale). Each player's line is on the info wall (COOP.wallInfo).
local HUD_NAMES = 6
local function hudState(s)              -- a player's state and health % for their line, from COOP.players()'s sources
    local e
    if s == COOP.slot then e = COOP.me() else
        local P = M.peers[s]
        e = P and P.fresh and P
        if not e then return "NOT IN THE MISSION" end
    end
    if not e then return "" end                                 -- (your plane not up: the HUD's hidden then)
    if e.alive == false then return "DOWN" end
    return e.onAirfield and "AT THE AIRFIELD" or "FLYING", e.hpPct and math.floor(e.hpPct + 0.5)
end
local function lookingLine() return M.auto and "CO-OP: LOOKING FOR A HOST..." or "CO-OP: LOOKING FOR A FRIEND WHO PICKED HOST..." end
local WAITING_LINE = "CO-OP: YOU ARE THE HOST, WAITING FOR FRIENDS"
function COOP.hudLine()
    if not COOP.open then return nil end
    if COOP.client() and M.state ~= "linked" then
        local s = lookingLine()
        return s, s
    end
    local names, news, n = {}, {}, 0
    for s = 0, MAX_SLOT do
        if M.roster[s] or s == COOP.slot then
            n = n + 1
            local nm = upperName(playerName(s), 14) .. (s == 0 and " (HOST)" or "")
            if M.wasLost and M.wasLost[s] then nm = nm .. " (LOST)" end
            if n <= HUD_NAMES then names[#names + 1] = nm end       -- (a big room: the first few, then "+N")
            local st = hudState(s)
            -- (shot down by the last state their game sent, not by its freshness: a lagging link flips that)
            local P, down = M.peers[s], st == "DOWN"
            if s ~= COOP.slot then down = P ~= nil and (P.flags or 0) % 2 == 1 and P.alive == false end
            news[#news + 1] = s .. nm .. (down and " DOWN" or "")
        end
    end
    if COOP.host() and n <= 1 then return WAITING_LINE, WAITING_LINE end
    if n > #names then names[#names + 1] = "+" .. (n - #names) end
    return string.format("CO-OP %d/%d: %s", n, maxPlayers(), table.concat(names, "  ")), table.concat(news, "|")
end

-- The HUD's info wall (sv_hud.lua, the user's of 2026-10-31: with more than 3 players the corner's lines couldn't show
-- what everyone was doing): { header, players = { a line each } } in co-op, nil solo. A line: the name (HOST, YOU, LOST),
-- the aircraft (their plane's own name, as on their box), FLYING / AT THE AIRFIELD / DOWN / NOT IN THE MISSION and
-- health, the host first, then by slot; every player, up to the room's 24. A joiner still looking for its host: the
-- header alone.
function COOP.wallInfo()
    if not COOP.open then return nil end
    if COOP.client() and M.state ~= "linked" then return { header = lookingLine(), players = {} } end
    local list = {}
    for s = 0, MAX_SLOT do
        if M.roster[s] or s == COOP.slot then
            local tags = {}
            if s == 0 then tags[#tags + 1] = "HOST" end
            if s == COOP.slot then tags[#tags + 1] = "YOU" end
            if M.wasLost and M.wasLost[s] then tags[#tags + 1] = "LOST" end
            local parts = { upperName(playerName(s), 14) .. (#tags > 0 and " (" .. table.concat(tags, ", ") .. ")" or "") }
            local ac = (s == COOP.slot) and M.myAc or (M.roster[s] and M.roster[s].ac)
            if type(ac) == "string" and ac ~= "" then parts[#parts + 1] = ac end
            local st, hp = hudState(s)
            if st ~= "" then parts[#parts + 1] = st end
            if hp then parts[#parts + 1] = string.format("%d%%", hp) end
            list[#list + 1] = table.concat(parts, "   ")
        end
    end
    if COOP.host() and #list <= 1 then return { header = WAITING_LINE, players = list } end
    return { header = string.format("CO-OP  %d/%d PLAYERS", #list, maxPlayers()), players = list }
end

-- The menu's view of co-op (sv_menu.lua): the lobby on the COOP HOST page, settings changed there
function COOP.lobby()
    local names = {}
    for sl = 0, MAX_SLOT do if M.roster[sl] or sl == COOP.slot then names[#names + 1] = upperName(playerName(sl), 14) end end
    return { open = COOP.open, role = COOP.role, n = playerCount(), max = maxPlayers(), names = names, state = M.state }
end
function COOP.settingsChanged(name)
    if COOP.host() and playerCount() > 1 then pcall(M.sendSettings, nil) end      -- (your joiners get it at once)
    if name == "Room" and COOP.host() then
        if playerCount() <= 1 and not D then COOP.reopen("host", "room size changed")
        else log("coop: the new room size applies the next time you host") end
    end
end
-- your own settings (the menu's setups): the host's are in CFG while you play with them
function COOP.ownRoot() return M.ownRoot() end


-- The STORE freeze (0.73.72, runtime 0.32.20; tools/re/STORE_FREEZE.md): the game's DeactivateForMinigame stops every
-- AI plane when a minigame (the airfield STORE) starts. While players are linked the runtime skips it (SV_StoreKeepAI),
-- so the world keeps flying for the others; solo, or co-op closed, the stock freeze stays. Logged once per change.
function COOP.storeKeepTick(c)
    if type(SV_StoreKeepAI) ~= "function" then return end
    local want = (c.enabled and COOP.open and c.store_keep_world ~= false and (M.linkedPeers or 0) > 0) and 1 or 0
    if want == M.storeKeep then return end
    local old = SV_StoreKeepAI(want)
    M.storeKeep = want
    if type(old) == "number" and old < 0 then
        once("storekeep", "coop: the STORE's world freeze can't be skipped here (the runtime didn't hook it: " .. tostring(old) .. ")")
    else
        log("coop: a STORE opening " .. (want == 1 and "keeps the world's AI flying (players linked)" or "stops the world's AI (stock)"))
    end
end

-- (0.73.76) a joiner's VALKA: her X-02S and paint on its copy of her once it's here (up to 30 s after "vr"), then its
-- wing sweep each tick, as her round does on the host
function COOP.valkaTick()
    local v = M.vr
    if not (v and D and COOP.client()) then return end
    local cu = M.cunits[v.unit]
    local o = nil
    for _, p in pairs(cu and cu.planes or {}) do if liveAddr(p) then o = p; break end end
    if not o then
        if v.done or os.clock() - v.at > 30 then
            if not v.done then log("coop: VALKA's copy here never came: her X-02S not put on") end
            M.vr = nil
        end
        return
    end
    if not v.done then
        local ok = SPC.V.model(CFG.specials.valka, v.st, o)
        if ok then
            v.done = true
            log("coop: VALKA's X-02S on this game's copy of her (" .. nameOf(o) .. ")")
        elseif os.clock() - v.at > 30 then M.vr = nil end
        return
    end
    pcall(SPC.V.modelTick, v.st, o, (D and D.now) or os.clock())
end

function COOP.tick(tick)
    local c = cfg()
    pcall(COOP.storeKeepTick, c)
    pcall(COOP.valkaTick)
    if not c.enabled then return end
    -- Co-op opens when the player picks COOP HOST or COOP JOIN (Survival's menu page, or the flat SURVIVAL CO-OP rows),
    -- as that role, and closes when they pick any other entry (SV_MenuChoice, the runtime's: the entry, 1 SURVIVAL MODE,
    -- 2 SP OFFLINE, 3 HOST, 4 JOIN, 5 SP ONLINE, 0 another, + 16 x the picks so far: picking the same entry again
    -- retries a co-op that couldn't open, and keeps one that's open). 6, SURVIVAL MODE's page opened, leaves co-op as it
    -- is: you pick the mode next. An older main.dll without it: open at start with CFG.coop.role, as before.
    local raw = type(SV_MenuChoice) == "function" and SV_MenuChoice() or nil
    if raw == nil then
        if not COOP.open and not M.openTried then M.openTried = true; openCoop("start") end
    elseif raw ~= M.raw and math.floor(raw) % 16 == 6 then
        M.raw = raw
    elseif raw ~= M.raw then
        M.raw = raw
        local choice = math.floor(raw) % 16
        local want = (choice == 3 and "host") or (choice == 4 and "join") or nil
        if COOP.open and want ~= M.picked then
            closeCoop((want and "the other co-op entry picked") or
                      ((choice == 1 or choice == 2 or choice == 5) and "a single-player mode picked: playing alone")
                      or "another main-menu entry picked")
        end
        M.picked = want
        if want and not COOP.open then openCoop(want == "host" and "SURVIVAL CO-OP: HOST picked" or "SURVIVAL CO-OP: JOIN picked", want) end
    end
    if not COOP.open then return end
    pcall(nameTick)
    pcall(M.asideTick, os.clock())                     -- ((0.73.83) set-aside planes kept off the radar)
    if M.recycleDue and #M.recycleDue > 0 then         -- ((0.73.83) a unit the host took off, off this game's list too
        local now0 = os.clock()
        for i = #M.recycleDue, 1, -1 do
            local e = M.recycleDue[i]
            if now0 >= e.at then
                table.remove(M.recycleDue, i)
                local n = type(SV_UnitAlive) == "function" and SV_UnitAlive(e.unit) or -5
                if n >= 0 and n ~= -7 and type(SV_Recycle) == "function" then
                    crumb("coop: SV_Recycle " .. e.unit .. " (the host's " .. tostring(e.why) .. ")")
                    local okR, r = pcall(SV_Recycle, e.unit, n > 0 and 1 or 0)
                    log(string.format("coop: %s off this game's spawner list (the host's %s; %d alive here): SV_Recycle %s",
                        e.unit, tostring(e.why), n, okR and tostring(r) or ("error " .. tostring(r))))
                end
            end
        end
    end
    -- the other games' messages
    for _ = 1, 600 do
        local m = SV_CoopRecv()
        if not m or m == "" then break end
        local ok, err = pcall(onMessage, m)
        if not ok then log("coop: message error " .. tostring(err) .. " (" .. m:sub(1, 80) .. ")") end
    end
    local now = os.clock()
    if now >= M.nextInfo then
        M.nextInfo = now + 5
        local info = SV_CoopInfo()
        local st = info:match("state=(%a+)")
        M.linkNames, M.rtt = {}, {}
        M.linkedPeers = 0
        for s, st, rtt, name in (info:match("peers=(.*)$") or ""):gmatch("(%d+)/(%a+)/(%-?%d+)/%-?%d+/([^,]*)") do
            M.linkNames[tonumber(s)] = name
            local ms = tonumber(rtt)                         -- (the link's round trip: a shot's age, "fx")
            if ms and ms >= 0 and ms < 10000 then M.rtt[tonumber(s)] = ms end
            if st == "linked" then M.linkedPeers = M.linkedPeers + 1 end
        end
        if st ~= M.state then
            M.state = st
            log("coop: " .. info)
            if st == "searching" and COOP.client() then once("searching", "coop: waiting for the host (" .. tostring(c.partner) .. ")") end
        end
        if st == "linked" then M.linkedOnce = true end
        if M.auto and COOP.client() and not M.linkedOnce and st ~= "linked" and now >= (M.autoAt or 0) then
            log("coop: no host found in time (role auto): this game hosts")
            COOP.reopen("host", "no host found")
            callout("CO-OP: NO HOST FOUND", "YOU ARE THE HOST")
            return
        end
        if COOP.client() and st == "linked" and now >= M.nextHi and not M.roster[COOP.slot or -1] then
            M.nextHi = now + 10                              -- (the host hasn't listed us yet: hello again)
            sendHi()
        end
    end
    -- a new level (a run started, or started over)
    if D ~= M.lastD then
        M.lastD = D
        if type(SV_CoopReset) == "function" then SV_CoopReset() end
        if COOP.client() then killAllCopies("a new run here") end      -- (a restart in the same level keeps the actors)
        for s, P in pairs(M.peers) do                                  -- (kept: bound again by peerTick)
            M.gunOff(P)                                                -- ((review of 0.73.80) its trigger let go: gunOn isn't kept)
            -- (whose it is and whether it's their real plane kept too: a host by migration keeps every live plane)
            M.peers[s] = (P.obj and valid(P.obj)) and { obj = P.obj, addr = addrOf(P.obj), sid = P.sid, real = P.real, code = P.code,
                                                       lo = P.lo, row = P.row, unit = P.unit,
                                                       fallback = P.fallback } or {}   -- ((0.73.80) M.standInPay)
        end
        pcall(M.asidePrune)                                            -- ((0.73.77) set-aside planes gone with a level let go)
        if M.vmHere then M.valkaHere(false, D and "a new run here" or "the run here is over") end   -- ((0.73.77) D2)
        M.units, M.byId, M.copies, M.cunits, M.spawnQ, M.dead, M.hunts = {}, {}, {}, {}, {}, {}, {}
        M.joinHits, M.pendBind, M.strayFirst, M.rep, M.downAt = nil, nil, nil, nil, {}
        M.replays, groundNew, M.holdQ = {}, {}, nil
        -- ((0.73.77) a new level: no run-over kept (A9), the kills by player (C1) and the kills' players named start over,
        -- the floor's line again (A1))
        M.ro, M.tally, M.killer, M.floorSaid = nil, nil, nil, nil
        -- ((review of 0.73.80) the round hold's state from before (a player loading the new level whose link is lost
        -- isn't "lost in the mission" by their last run's states): each player held up to join_wait_s again
        M.stateAt, M.freshAt, M.lostAt, M.holding, M.outSince = {}, {}, {}, {}, {}
        -- ((0.73.73) the units' objects kept, a restart in the same level keeps the actors: those of a level gone, or whose
        -- address is another object's now, dropped)
        for unit, reg in pairs(M.objsOf) do
            for a, e in pairs(reg) do if not live(e.obj) or nameOf(e.obj) ~= e.name then reg[a] = nil end end
            if next(reg) == nil then M.objsOf[unit] = nil end
        end
        M.svcpUsable = {}                                              -- (the stand-ins' damage-0 rows in before it loaded)
        for row, sv in pairs(M.svcpReady or {}) do M.svcpUsable[row] = sv end
        if D then
            -- ((0.73.73) "rs|n": the host's new run, which a joiner starts over with; "rs|m" a host by migration's level, the
            -- same run: a joiner keeps its money and nobody DOWN comes back)
            if COOP.host() then send(true, "rs", (M.mig and M.mig.hosting) and "m" or "n")
            else M.jnAt = os.clock(); send(true, "jn") end
            log("coop: in Survival's level as " .. (COOP.host() and "the host" or ("player " .. tostring((COOP.slot or -1) + 1))))
            if COOP.client() and M.state ~= "linked" then
                callout(M.auto and "CO-OP: LOOKING FOR A HOST" or "CO-OP: WAITING FOR THE HOST",
                        M.auto and "NONE FOUND: YOU HOST" or tostring(c.partner))
            elseif COOP.host() then
                callout("CO-OP: YOU ARE THE HOST", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            end
        end
    end
    local okVw, errVw = pcall(M.valkaWatch)                          -- ((0.73.77) VALKA's mood to every joiner: D1-D2)
    if not okVw then once("valkaWatch", "coop: VALKA's mood watch error " .. tostring(errVw)) end
    if not D then
        -- ((0.73.80) no run (the main menu, the hangar): the tables the other players' planes and skins are checked
        -- against looked for here, never in a fight (M.tablesPrep)
        local okTp, errTp = pcall(M.tablesPrep)
        if not okTp then once("tablesPrep", "coop: the plane and skin tables: error " .. tostring(errTp)) end
        return
    end
    -- An online-style pause (user, 2026-10-26: "when the Host Pauses, the game doesn't pause all the enemies for the
    -- other players"): while another player is linked, the pause menu opens but the world keeps running, on the host's
    -- game (its enemies, which every game copies) and on a joiner's (its plane). Alone, the game pauses as ever.
    -- ((0.73.79) the round clock's answer this tick, when it asked the game: not paused, so nothing to undo)
    local clockSaysRunning = CLOCK_TICK == tick and CLOCK_PAUSED == false
    pcall(COOP.focusPause, (M.linkedPeers or 0) > 0, (M.linkedPeers or 0) > 0 and "others linked" or "nobody linked")
    if (M.linkedPeers or 0) > 0 and not clockSaysRunning and valid(survivalPC) and gamePaused(survivalPC) then
        local gs = cdo("/Script/Engine.Default__GameplayStatics")
        local ok = gs and pcall(function() gs:SetGamePaused(survivalPC, false) end)
        M.unpauses = (M.unpauses or 0) + 1
        if M.unpauses == 1 or M.unpauses % 40 == 0 then
            log(string.format("coop: paused with %d players: the world kept running (%s; %d times)", playerCount(),
                ok and "unpaused" or "COULD NOT unpause", M.unpauses))
        end
        if M.unpauses == 1 then callout("CO-OP: THE GAME KEEPS RUNNING", "OTHER PLAYERS ARE STILL FLYING") end
    end
    -- (hotfix6) The host's landing STORE stops the world without pausing it (VanesCreed-'s host log of 2026-11-01: in
    -- the STORE 00:07:00-00:09:54 of round 16, not paused, its frames running, yet no enemy moved or died for anyone
    -- for those 3 minutes, as in round 15's visit): most likely the world's time dilation. While another player is
    -- linked it's kept at 1, as the pause above is undone; and the world's clock is watched, so the next log says
    -- what stops it if that isn't it.
    if (M.linkedPeers or 0) > 0 and valid(survivalPC) then
        local okW, errW = pcall(function()
            local gs = cdo("/Script/Engine.Default__GameplayStatics")
            local okD, dil = pcall(function() return gs:GetGlobalTimeDilation(survivalPC) end)
            dil = (okD and type(dil) == "number") and dil or nil
            if dil and dil < 0.99 then
                local okS = pcall(function() gs:SetGlobalTimeDilation(survivalPC, 1.0) end)
                M.dilFixes = (M.dilFixes or 0) + 1
                if M.dilFixes == 1 or M.dilFixes % 40 == 0 then
                    log(string.format("coop: time dilation was %.3f with %d players%s: set back to 1 (%s; %d times)", dil,
                        playerCount(), playerOnAirfield() and " (you're down at the airfield)" or "",
                        okS and "set" or "COULD NOT set", M.dilFixes))
                end
            end
            local t, rt = gameClock(survivalPC), os.clock()
            if t then
                if M.wcT and t == M.wcT then                     -- the world's clock didn't move since last tick
                    M.wcStill = M.wcStill or rt
                    if rt - M.wcStill >= 3 and not M.wcSaid then
                        M.wcSaid = true
                        log(string.format("coop: the world's clock has stood still %.0f s with %d players (paused %s, time dilation %s%s)",
                            rt - M.wcStill, playerCount(), tostring(gamePaused(survivalPC)), dil and string.format("%.3f", dil) or "?",
                            playerOnAirfield() and ", you're down at the airfield" or ""))
                    end
                else
                    if M.wcSaid then log(string.format("coop: the world's clock runs again after %.0f s", rt - (M.wcStill or rt))) end
                    M.wcStill, M.wcSaid = nil, nil
                end
                M.wcT = t
            end
        end)
        if not okW then once("worldclock", "coop: world clock check error " .. tostring(errW)) end
    end
    -- (the host-at-the-airfield freeze, hotfixes 7-12, removed in 0.73.67: none of its switch-backs woke the planes the
    -- STORE's minigame manager (LiveMiniGameManager) switches off, and they likely caused the renderer crashes of
    -- 2026-11-01. To be reverse engineered: HOTFIX_NOTES.md open problem 1.)
    -- our own plane, streamed (flags: 1 in Survival's level, 2 alive, 4 down at the airfield, 8 DOWN: shot down and
    -- waiting for a revive, sv_down.lua, not "alive" then; the sync's 16 gear down, 32 afterburner, 64 gun firing,
    -- 128 flares)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if valid(pawn) then
        local flags = 1
        local h = health(pawn)
        local down = DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true
        if down then flags = flags + 8 elseif h and h > 0 then flags = flags + 2 end
        if playerOnAirfield() then flags = flags + 4 end
        local okB, bits = pcall(M.syncBits, pawn, now)
        if okB then flags = flags + bits else once("syncBits", "coopfire: state bits error " .. tostring(bits)) end
        SV_CoopMe(addrOf(pawn) or 0, flags)
        local row, code = myAirframe()
        local okSa, errSa = pcall(M.seenAsTick, code)        -- ((0.73.80) "OTHERS SEE YOUR <X> AS <Y>", once a level)
        if not okSa then once("seenAs", "coop: seen-as error " .. tostring(errSa)) end
        local lo = M.myLoadout()                              -- (new weapons picked at the airfield: COOP2MP T4b)
        local pt = M.myPaint()                                -- (and paint: T5)
        local acn = M.myAircraft()                            -- (and the aircraft's name)
        local okMp, mcls = pcall(M.myPlane, pawn, code)       -- ((0.73.80) and its class path: a modded plane's, sent)
        if not okMp then once("myPlane", "coop: your plane's class: error " .. tostring(mcls)); mcls = M.myCls end
        if (row and row ~= M.myRow) or (code and code ~= M.myCode) or (lo ~= "" and lo ~= M.myLo) or (pt ~= "" and pt ~= M.myPt)
            or (acn ~= "" and acn ~= M.myAc) or (mcls ~= nil and mcls ~= "" and mcls ~= M.myCls) then
            M.myRow, M.myCode = row, code
            if COOP.host() then hostRosterSelf() else sendHi() end
        end
    else
        SV_CoopMe(0, 0)
    end
    local okSf, errSf = pcall(M.slotFix)                              -- (each plane in its owner's slot: host migration)
    if not okSf then once("slotFix", "coop: slot fix error " .. tostring(errSf)) end
    for s = 0, MAX_SLOT do
        if s ~= COOP.slot then
            local okP, errP = pcall(peerTick, s)
            if not okP then once("peerTick", "coop: player plane error " .. tostring(errP)) end
        end
    end
    local okG, errG = pcall(groundTick)
    if not okG then once("groundTick", "coop: ship / vehicle error " .. tostring(errG)) end
    local okF, errF = pcall(M.syncTick, now, pawn)                   -- (weapons, gear: the sync's)
    if not okF then once("syncTick", "coopfire: sync error " .. tostring(errF)) end
    if COOP.host() then
        local okH, errH = pcall(hostTick)
        if not okH then once("hostTick", "coop: host error " .. tostring(errH)) end
    else
        local okC, errC = pcall(clientTick)
        if not okC then once("clientTick", "coop: joiner error " .. tostring(errC)) end
    end
    local okMg, errMg = pcall(M.migTick, now)                         -- (host migration: the line, the watch, a takeover)
    if not okMg then once("migTick", "coop: migration error " .. tostring(errMg)) end
end
end
