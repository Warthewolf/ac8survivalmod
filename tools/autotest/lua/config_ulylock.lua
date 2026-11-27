-- survival_config.lua for the ulylock suite (tools/autotest/kit.py): co-op off, round 1 an hour away (the suite forces
-- ULYSSES' two rounds back to back), 10 fragments a round, close and fast (each lands within ~25 s), the core 8 s into
-- round 2 from 14 km; never ranked (LB.edited). Saint Alessia's co-op run of 0.75.117 (2026-11-24): round 20 had no
-- target to lock, the air-to-air specials locked none, the sepia wash stopped short on her 21:9 screen.
return { coop = { enabled = false }, first_round_delay_s = 3600,
         specials = { ulysses = { big = { at_s = 8, from_km = 14, alt_m = 6000, speed_kmh = 2600 },
                                  fragments = { round1 = 10, round2 = 10, first_s = 2, every_s = { 2, 3 }, from_km = { 6, 9 },
                                                alt_m = { 3000, 5000 }, speed_kmh = { 1400, 1600 } } } } }
