-- survival_config.lua for the valka suite (tools/autotest/kit.py): co-op off, round 1 an hour away (the suite forces
-- VALKA's round), her disguise off so she comes at once and alone; never ranked (LB.edited).
return { coop = { enabled = false }, first_round_delay_s = 3600, specials = { valka = { disguise = false } } }
