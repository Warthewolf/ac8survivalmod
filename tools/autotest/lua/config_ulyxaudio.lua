-- survival_config.lua for the ulyxaudio suite (tools/autotest/kit.py): co-op off, round 1 an hour away; ULYSSES' Wwise
-- sounds off (its XAudio2 fallback), its waves close (every 3-4 s); never ranked.
return { coop = { enabled = false }, first_round_delay_s = 3600,
         specials = { ulysses = { sounds = { wwise = { enabled = false } }, fragments = { first_s = 3, every_s = { 3, 4 } } } } }
