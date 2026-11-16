-- target_practice.lua: a minimal add-on sortie for AC8 Survival Mode (add-on API 2.0, docs/ADDONS.md).
-- TARGET PRACTICE: three stock trucks parked on the spaceport pad, paid when destroyed; the round ends when all three
-- are down or after time_s. Stock assets only, so it needs no container of its own.
-- Install: this folder (target_practice, this file in it) into Mods/AC8SurvivalAddons/. Its settings: [specials.practice]
-- in survival.ini. It runs in an environment of its own: Survival's globals aren't there, only the API (SVP).

local TRUCK = "/Game/Blueprints/Vehicle/AI/GroundVehicle/GR026_trka/CP/BP_GR026_trka_CP.BP_GR026_trka_CP_C"
local R = { s = nil }                    -- the round in progress: { started, actors = {}, ids = {} }

local function cfg() return SVP.cfg("practice") end   -- (its settings, read-only: def.cfg with survival.ini over it)

-- the trucks' spots: around the pad, `spread_m` apart, facing it
local function spots()
    local pad, out = SVP.pad(), {}
    local d = (cfg().spread_m or 300) * 100
    for i = 1, cfg().trucks do
        local a = (i - 1) * 2 * math.pi / cfg().trucks
        out[i] = { at = { X = pad.X + d * math.cos(a), Y = pad.Y + d * math.sin(a), Z = pad.Z }, yaw = math.deg(a) + 180 }
    end
    return out
end

local function cleanUp(touch)
    local s = R.s
    R.s = nil
    if not s then return end
    for _, id in ipairs(s.ids) do SVP.untarget(id) end
    -- (an actor kept between ticks is used only while it's still the engine's live object)
    if touch then for _, a in ipairs(s.actors) do if SVP.liveObj(a) then SVP.despawn(a) end end end
end

local ok, why = SVP.register("practice", {
    name = "Target practice", ver = "1.0", api = "2.0",
    rotation = false,                           -- (only when the player puts "practice" in survival.ini's rotation)
    cfg = { from_round = 2, trucks = 3, pay = 500, spread_m = 300, time_s = 120 },
    -- its own readiness: the stock truck must load (any add-on would check its own container here)
    check = function()
        if SVP.load(TRUCK) then return true end
        return false, "the truck class isn't in this game"
    end,
    kind = {
        sub = function() return "TARGET PRACTICE" end,
        alone = true, aircraft = 0,             -- (no Survival fighters with it)
        -- (no ready: Survival keeps it out before its from_round itself, and nothing else rules it out)
        spawn = function(now)
            local s = { started = now, actors = {}, ids = {} }
            for _, sp in ipairs(spots()) do
                local a = SVP.spawn(TRUCK, sp.at, sp.yaw)
                if a then
                    s.actors[#s.actors + 1] = a
                    s.ids[#s.ids + 1] = SVP.target(a, { pay = cfg().pay, label = "truck" })
                end
            end
            if #s.actors == 0 then return false end            -- (nothing came: Survival plays a normal round)
            R.s = s
            SVP.callout("TARGET PRACTICE", "DESTROY THE TRUCKS ON THE PAD")
            SVP.log(string.format("%d trucks on the pad", #s.actors))
            return true
        end,
        tick = function(now)
            local s = R.s
            if not s then return end
            local up = 0
            for _, id in ipairs(s.ids) do if SVP.alive(id) then up = up + 1 end end
            if up == 0 and not s.result then s.result = "won"; SVP.callout("TARGET PRACTICE", "ALL TARGETS DOWN") end
            if up > 0 and now - s.started >= cfg().time_s and not s.result then
                s.result = "timeout"
                SVP.callout("TARGET PRACTICE", "TIME UP")
            end
        end,
        busy = function() return R.s ~= nil and R.s.result == nil end,   -- (holds the round until it's decided)
        over = function() cleanUp(true) end,
        abort = function(why) cleanUp(why ~= "the level is going") end,   -- (touch nothing while the level goes)
    },
})
if not ok then SVP.log("not registered: " .. tostring(why)) end
