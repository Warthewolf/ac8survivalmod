-- sv_selftest_keys.lua: the autotest's key recorder (tools/autotest/kit.py puts it FIRST in the installed main.lua's
-- MODULES, for a gated test run only; it's in no build). Every RegisterKeyBind call after it is recorded in
-- SELFTEST_BINDS (key, Ctrl or not, callback) and passed on to UE4SS unchanged, so sv_selftest.lua can "press" a test
-- key (SELFTEST.press("L") runs Ctrl+L's callback) with nobody at the keyboard: AC8 ignores posted key messages, and the
-- self-test never takes the user's focus (tools/autotest/README.md).
SELFTEST_BINDS = {}
do
    local orig = RegisterKeyBind
    if type(orig) == "function" then
        RegisterKeyBind = function(key, a, b, ...)
            local mods, fn = a, b
            if type(a) == "function" then mods, fn = nil, a end      -- (the two-argument form: RegisterKeyBind(key, fn))
            local ctrl = false
            if type(mods) == "table" and ModifierKey then
                for _, m in ipairs(mods) do if m == ModifierKey.CONTROL then ctrl = true end end
            end
            SELFTEST_BINDS[#SELFTEST_BINDS + 1] = { key = key, ctrl = ctrl, fn = fn }
            return orig(key, a, b, ...)
        end
    end
end
