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

function ZLAS.zfaRow(npc, mine, addRow, row)
    ZLAS.armed = false
    local z = zc()
    if z.laser == false then return addRow(row), " (laser off: the plain host)" end
    local function plain(why) return addRow(row), " (no laser: " .. why .. ")" end
    local fr, lr = tostring(z.laser_fcs_row), tostring(z.laser_row)
    local _, have = dtCall(npc, "FindRow", row)
    if have ~= nil then                                    -- (in already: which one, by its slot 3)
        local cur = nil
        pcall(function() cur = have.NpcFCSId3:ToString() end)
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
    return true, string.format(" (with the anti-missile laser: %s's struct, its slot 3 %s, that row in DT_NPC_FCS)", lr, fr)
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
