-- survival_config.lua for the valkasolg suite (tools/autotest/kit.py): VALKA at once and alone, no cutscene, her SOLG
-- called in 4 s after her lines start and falling for 45 s from 12 km off; never ranked (LB.edited).
return { coop = { enabled = false }, first_round_delay_s = 3600,
         specials = { valka = { disguise = false, cine = { enabled = false },
                                solg = { call_s = 4, travel_s = 45, corner_km = 12, alt_km = 6 } } } }
