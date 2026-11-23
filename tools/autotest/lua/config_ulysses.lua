-- survival_config.lua for the ulysses suite (tools/autotest/kit.py): co-op off, round 1 an hour away (the suite forces
-- ULYSSES), its fragments sooner and the core at 25 s; never ranked (LB.edited).
return { coop = { enabled = false }, first_round_delay_s = 3600,
         specials = { ulysses = { big = { at_s = 25 }, fragments = { first_s = 3, every_s = { 2, 4 } } } } }
