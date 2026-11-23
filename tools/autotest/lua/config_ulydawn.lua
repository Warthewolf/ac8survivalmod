-- survival_config.lua for the ulydawn suite (the ulysses2 suite at its real dawn light; tools/autotest/kit.py)
-- ULYSSES), its fragments close and fast (each lands within ~25 s), the core 8 s in from 14 km; never ranked (LB.edited).
return { coop = { enabled = false }, first_round_delay_s = 3600,
         specials = { ulysses = { big = { at_s = 8, from_km = 14, alt_m = 6000, speed_kmh = 2600 },
                                  fragments = { first_s = 2, every_s = { 2, 3 }, from_km = { 6, 9 }, alt_m = { 3000, 5000 },
                                                speed_kmh = { 1400, 1600 } } } } }
