"""music_tracks.py : the tracks Survival adds to the pause menu's music player (2026-11-08).

The user: "add all the named music into the music player". AC8's music player lists DT_SoundMusicPlayerBGM, whose rows
are named after the Wwise event the player posts (AKE_Bgm_MUSICPLAYER_BGM_<id>_Play). These are the game's own events
for named tracks the stock list leaves out: the campaign's three endings, Online Mode's named tracks, the online lobby's
jukebox (77, from AC8's DT_JukeBoxMusic) and the online match tracks of the older games that the jukebox doesn't have.
((2026-11-08) the user, after 0.74.29: "Delete the briefing debriefing cutscene tracks": the cutscenes' pieces and
Debriefing IV are out; AC8's music player shows 120 tracks at most (its scroll list's limit; more crashed the game), so
Scripts/sv_music.lua adds a random share of these each run: CFG.music.player_max.) tools/build_survival_rows.py (build_music_rows) turns them into rows of
Survival's own table DT_SV_MusicRows; Scripts/sv_music.lua adds them to the game's table while Survival's level is on
and takes them out after. Their four banks are resident from the game's start in every mode (DA_SoundSettings'
RegidentSoundBanks: tools/re/MUSIC_BANKS.md 2); the game's list build skips a row whose event no loaded bank has.

A title that has a key in the game's text (CP: MusicPlayer_SongTitle_*) uses it. Every other title is a text of
Survival's own (SV_Mus<n>T, no numeric tail: hard rule 17), set at run time from the row's TitleString (SV_SetText).
The DLC tracks (PurpleMagic A-C, NoID010-070) have keys but no event in any bank here, so they aren't in.
"""

CAMPAIGN, ONLINE, LOBBY = 'AKB_BGM_Campaign', 'AKB_BGM_Online', 'AKB_BGM_Online_Lobby'
# ELiveSoundMusicFilterTag: the music player's tabs and colour sets (DT_LiveMusicPlayerColorVariationSettings has
# colours for 1, 2, 3 and 6 only, so a row uses one of them)
ORCHESTRA, BAND, SYNTH, ENVIRONMENT = 1, 2, 3, 6

# the games the older tracks are from (AC8's own names, ON: Online_JukeBox_SouceTitleNN_Name; 12-14 not in AC8's text)
ORIGINS = {
    1: 'ACE COMBAT', 2: 'ACE COMBAT 2', 3: 'ACE COMBAT 3: Electrosphere', 4: 'ACE COMBAT 04: Shattered Skies',
    5: 'ACE COMBAT 5: THE UNSUNG WAR', 6: 'ACE COMBAT 6: Fires of Liberation', 7: 'ACE COMBAT 7: SKIES UNKNOWN',
    8: 'ACE COMBAT 8: WINGS OF THEVE', 9: 'ACE COMBAT ASSAULT HORIZON', 10: 'ACE COMBAT INFINITY',
    11: 'ACE COMBAT ZERO: THE BELKAN WAR', 12: 'ACE COMBAT X: Skies of Deception', 13: 'ACE COMBAT X2: Joint Assault',
    14: 'ACE COMBAT 3D: Cross Rumble',
}
JUKEBOX_ORIGIN_KEY = 'Online_JukeBox_SouceTitle'   # (sic) DT_JukeBoxMusic's OriginTextID: <key>NN_Name


# (event, the game's title key or None, title, origin number or None, bank, filter)
CAMPAIGN_TRACKS = [
    ('AKE_Bgm_Ending01_Play', None, 'Ending Ⅰ', None, CAMPAIGN, ORCHESTRA),
    ('AKE_Bgm_Ending02_Play', None, 'Ending Ⅱ', None, CAMPAIGN, ORCHESTRA),
    ('AKE_Bgm_Ending03_Play', None, 'Ending Ⅲ', None, CAMPAIGN, ORCHESTRA),
]

ONLINE_TRACKS = [
    ('AKE_Bgm_Online_Op_Play', 'MusicPlayer_SongTitle_Online_OP', 'Sky mercenaries', None, ONLINE, BAND),
    ('AKE_Bgm_Online_Tutorial_Play', 'MusicPlayer_SongTitle_Online_Tutorial', 'Combat-ready fighter pilot-', None, ONLINE, BAND),
    ('AKE_Bgm_Online_Matching_Play', 'MusicPlayer_SongTitle_Online_Matching', 'Flight Junkies in the sky', None, ONLINE, BAND),
    ('AKE_Bgm_Online_FreeFlight_Play', 'MusicPlayer_SongTitle_Online_FreeFlight', 'Wonderful Fanciful Flight', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EmergencyPhase_01_Play', 'MusicPlayer_SongTitle_Online_EmergencyPhase01', 'Abruptly Attack', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EmergencyPhase_02_Play', 'MusicPlayer_SongTitle_Online_EmergencyPhase02', 'Tightrope', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EmergencyPhase_03_Play', 'MusicPlayer_SongTitle_Online_EmergencyPhase03', 'Blazing Battlefield', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EmergencyPhase_04_Play', 'MusicPlayer_SongTitle_Online_EmergencyPhase04', 'Interception', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EmergencyPhase_05_Play', 'MusicPlayer_SongTitle_Online_EmergencyPhase05', 'The Abominable Visitor', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EmergencyPhase_06_Play', 'MusicPlayer_SongTitle_Online_EmergencyPhase06', 'Critical Situation', None, ONLINE, BAND),
    ('AKE_Bgm_Online_EB003_Play', 'MusicPlayer_SongTitle_Online_EB003', 'Revolt the Fate', None, ONLINE, BAND),
    ('AKE_Bgm_Online_Result_Victory_Play', 'MusicPlayer_SongTitle_Online_Result_Victory', 'Skies of Victory', None, ONLINE, BAND),
    ('AKE_Bgm_Online_Result_Lose_Play', 'MusicPlayer_SongTitle_Online_Result_Lose', 'Get back your sky', None, ONLINE, BAND),
    ('AKE_Bgm_Online_Result_Draw_Play', 'MusicPlayer_SongTitle_Online_Result_Draw', 'Fair air combat', None, ONLINE, BAND),
    ('AKE_Bgm_Online_GeneralMVP_Play', 'MusicPlayer_SongTitle_Online_Result_MVP', 'Got the MVP', None, ONLINE, BAND),
]

# The online match tracks the jukebox doesn't have (most loop until skipped: Wwise "infinite" events)
_MATCH = [
    (1, 'ACE', [('Get_off_him', 'Get Off Him'), ('Head_first', 'Head First'), ('Like_a_sea_gull', 'Like a Sea Gull'),
                ('Night_and_Day', 'Night and Day')]),
    (2, 'ACE2', [('Aim_Hight', 'Aim High'), ('Dynapolis', 'Dynapolis'), ('El_Dorado', 'El Dorado'),
                 ('Elemental_Particle', 'Elemental Particle'), ('Fire_Away', 'Fire Away'), ('Fire_Youngman', 'Fire Youngman'),
                 ('Night_And_Day', 'Night and Day'), ('Rising_High', 'Rising High'), ('Sunset_Glow', 'Sunset Glow')]),
    (3, 'ACE3', [('Code_of_Honor', 'Code of Honor'), ('Frozen_Soul', 'Frozen Soul'), ('Gordian_Knot', 'Gordian Knot'),
                 ('Mind_Flow', 'Mind Flow'), ('Physical_Layer', 'Physical Layer'), ('Revelation', 'Revelation'),
                 ('Shattered_Stones', 'Shattered Stones'), ('The_Execution', 'The Execution'),
                 ('Transparent_Blue', 'Transparent Blue')]),
    (3, 'Ms_ac3', [('Linkage', 'Linkage')]),
    (4, 'ACE04', [('Aquila', 'Aquila'), ('Safe_Return', 'Safe Return'), ('Whiskey_Corridor', 'Whiskey Corridor')]),
    (5, 'ACE5', [('8492', '8492'), ('Fortress', 'Fortress')]),
    (6, 'ACE6', [('Through_the_Heart_of_a_Nation', 'Through the Heart of a Nation')]),
    (7, 'ACE7', [('Pipeline_Destruction', 'Pipeline Destruction')]),
    (9, 'ACEAH', [('Beyond_The_Canal', 'Beyond The Canal'), ('Dogfight', 'Dogfight'), ('Fighter', 'Fighter'),
                  ('Keep_Alive', 'Keep Alive'), ('Naval_Warfare', 'Naval Warfare'), ('Rush', 'Rush'),
                  ('Shall_Defend', 'Shall Defend'), ('White_Devil', 'White Devil')]),
    (10, 'ACEINF', [('Blue_Skies_INFINITY_Remix', 'Blue Skies (INFINITY Remix)'),
                    ('Invincible_Fleet_INFINITY_Remix', 'Invincible Fleet (INFINITY Remix)')]),
    (12, 'ACEX', [('Blitz', 'Blitz'), ('End_of_Deception', 'End of Deception'), ('Gaiuss_Tower', 'Gaiuss Tower'),
                  ('Operation_X', 'Operation X'), ('Prelude', 'Prelude')]),
    (13, 'ACEX2', [('Metropolitan', 'Metropolitan'), ('War_Torn_Radiance', 'War Torn Radiance')]),
    (14, 'ACE3D', [('Fighter_s_Honor_Flying_Remix', "Fighter's Honor (Flying Remix)"), ('Gravity', 'Gravity'),
                   ('Heartbeat', 'Heartbeat'), ('If_The_Sky_Is_Burnin_Out_2011', "If The Sky Is Burnin' Out 2011"),
                   ('On_The_Verge', 'On The Verge')]),
]
MATCH_TRACKS = [(f'AKE_Bgm_Online_{game}_{ev}_Play', None, title, origin, ONLINE, BAND)
                for origin, game, songs in _MATCH for ev, title in songs]


MENU_WORDS = ('BRIEFING', 'HANGAR')     # (the user: "Delete the briefing debriefing cutscene tracks", "hangars too")


def menu_track(event):
    """A briefing, debriefing or hangar piece (AC5's jukebox has "Briefing 1" and "Hangar 1"), or a cutscene's."""
    return '_Cin_' in event or any(w in event.upper() for w in MENU_WORDS)


def jukebox_tracks(rows):
    """The lobby jukebox's from AC8's DT_JukeBoxMusic (77, its briefing and hangar pieces left out): rows =
    [(ResourceName, TitleText, OriginTextID)]."""
    out = []
    for ev, title, okey in rows:
        assert okey.startswith(JUKEBOX_ORIGIN_KEY) and okey.endswith('_Name'), okey
        origin = int(okey[len(JUKEBOX_ORIGIN_KEY):-len('_Name')])
        assert origin in ORIGINS, okey
        if not menu_track(ev):
            out.append((ev, None, title, origin, LOBBY, BAND))
    return out


def all_tracks(jukebox_rows):
    """Every added track in the order they're listed: the campaign's endings, Online Mode's, the jukebox's, the other
    online match tracks. Checked: no event twice, no row of the stock table, no cutscene or menu track."""
    tracks = CAMPAIGN_TRACKS + ONLINE_TRACKS + jukebox_tracks(jukebox_rows) + MATCH_TRACKS
    evs = [t[0] for t in tracks]
    assert len(evs) == len(set(evs)), [e for e in evs if evs.count(e) > 1]
    for t in tracks:
        assert t[0].endswith('_Play') and t[4] in (CAMPAIGN, ONLINE, LOBBY) and t[5] in (1, 2, 3, 6), t
        assert not menu_track(t[0]), t
    return tracks


def title_key(i, track):
    """The row's TitleTextID: the game's key, else Survival's SV_Mus<i>T."""
    return track[1] or f'SV_Mus{i}T'


def origin_key(origin):
    return f'SV_MusO{origin}T'
