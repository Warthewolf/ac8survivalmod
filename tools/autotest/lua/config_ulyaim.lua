-- survival_config.lua for the ulyaim suite (ulymany with fragments.aim_share 0.4) (tools/autotest/kit.py): co-op off, round 1 an hour away (the suite forces
-- ULYSSES), its fragments at their real heights and speeds, only the waves closer (every 3-4 s: at_once's 30 reached);
-- never ranked (LB.edited).
return { coop = { enabled = false }, first_round_delay_s = 3600,
         specials = { ulysses = { fragments = { first_s = 3, every_s = { 3, 4 }, aim_share = 0.4 } } } }
