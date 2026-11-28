-- survival_config.lua for the radioprobe suite (tools/autotest/kit.py): co-op off, round 1 an hour away (the suite asks
-- the radio subsystem for Nagase's countdown groups itself, no round); never ranked (LB.edited). The user, 2026-11-28:
-- "nagases countdown seemed off", "fix the timing and the second round copies too".
return { coop = { enabled = false }, first_round_delay_s = 3600 }
