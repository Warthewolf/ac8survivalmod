-- survival_config.lua for the shuttleradio suite (tools/autotest/kit.py): co-op off, round 1 an hour away (the suite
-- forces two shuttle rounds back to back and runs each countdown on to its last 45 s); never ranked (LB.edited). The
-- user, 2026-11-28: "nagases countdown seemed off", "fix the timing and the second round copies too".
return { coop = { enabled = false }, first_round_delay_s = 3600 }
