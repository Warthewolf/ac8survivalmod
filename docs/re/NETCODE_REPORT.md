# Co-op netcode report: how it works today

Baseline for the traffic counters and the optimisations that come after them.
No code was changed to write this. Everything is read from the sources named in each line; a claim that is reasoned
rather than read is marked "(inferred)". Line numbers are those of the tree this was written on (runtime 0.32.x, protocol 4,
Lua 0.74.x). `coop.c` below is runtime/coop.c.

Where things live: native transport and per-frame work in runtime/coop.c (+ coop_lua.c for the Lua functions),
the flight block in runtime/flight_coop2mp.c, the Lua half in Scripts/sv_coop.lua, sv_coop_joiner.lua, sv_coop_planes.lua,
sv_coop_sync.lua, sv_coop_migration.lua. Older design notes: docs/re/COOP.md, docs/re/COOP2MP.md.

## 1. Topology

- A star around the host. Slot 0 is the host, slots 1..23 the joiners (coop.c:6-9, `CO_MAX_PLAYERS 24` at :42). The host
  has one `CoLink` per joiner (index = the joiner's slot); a joiner has exactly one link, index 0, to the host
  (coop.c:353-354 comment, `CoLink` :355-369, `CO.links[CO_MAX_PLAYERS]` :400). Joiners never talk to each other: the host relays
  everything (planes in Q batches, shots as `fx` Lua messages, sv_coop_sync.lua:586-592).
- Roles: `CO_ROLE_HOST 1`, `CO_ROLE_JOIN 2` (coop.c:55-56). Two hosts, or two joiners, ignore each other's hellos; a host
  that hears another host logs "is also the host" at most every 10 s (coop.c:905-914).
- Transport, chosen at `SV_CoopOpen` (coop_lua.c:43-87): Steam P2P (ISteamNetworking through steam_api64's flat API,
  channel 1480, `SendP2PPacket` with type 0 = unreliable, coop.c:46, :577-586) or plain UDP (ws2_32 loaded at run time,
  non-blocking; host binds `port` (27777 default), a joiner binds `port + 1`; coop_lua.c:72). Every datagram is
  at most 1,200 bytes (`CO_MAX_PACKET`, coop.c:47; larger sends are silently refused, :579). Both transports are
  datagrams: all ordering, loss recovery and retransmission is done by this code (section 3).
- Discovery (`CoDiscover`, coop.c:1125-1175), every 2 s while "searching" (a host while a slot is free, a joiner
  while it has no host link; CoStep, :1337). Steam: the candidates are the partner names / SteamID64s from the ini
  and, for `auto`, every Steam friend currently playing this app (friend flag 4, `friendGame` app id match; up to 64
  candidates, `CO_MAX_CAND`). For each candidate without a link it calls `AcceptP2PSessionWithUser` and sends a hello. UDP:
  only a joiner, to the host's address from the ini.
- Joining: the host answers a hello from an unknown sender by giving it the lowest free slot below `maxPlayers`
  (coop.c:921-929) and opens the link; no free slot -> hello with `yourSlot = 0xFE` (full, :925-927). The slot goes back to
  the joiner in the host's hello (`yourSlot`) and the joiner adopts it (:967-976).
- Session nonce: each game picks `nonce = QPC*1000003 ^ (pid << 16) ^ 0x5C0F` at open (coop_lua.c:64). The hello
  carries it. A changed nonce on a known link means the peer restarted: the link's reliable state and the peer's streams
  are reset and Lua is told `sys|restart` (coop.c:929-937, :958-966). L and K packets carry the sender's nonce and are
  ignored when it does not match the link's (:1033, :1038). P, Q, E and U carry no nonce: they are accepted from any
  known link (Steam ID, or UDP address+port, `CoLinkOf` :826-835) (inferred consequence: a stale packet from a previous
  session of the same peer is accepted until its first hello changes the nonce).
- Version check: `CoSameVer` is an exact compare of the 32-byte build string Lua passes to `SV_CoopOpen`
  (VERSION + co-op tag) (coop.c:858-865). A host answers a different build with `yourSlot = 0xFD` and does not open a
  link (:917-922); a joiner checks too, so an older host that does not refuse is still caught (:942-954). The protocol
  byte `CO_PROTO` (4) is checked first on every packet; a different one is dropped, logged at most every 10 s
  (:1016-1023). Protocol history: 4 added the flight block (coop.c:40-41).
- Link liveness: any packet from the peer refreshes `lastRecv` (:1029). `connected` = silent for less than 6 s
  (`CO_LOST_S`, :54, :1346-1351); a link silent for 90 s is freed and its slot reopened (`CO_DROP_S` :1327, :1352-1358);
  a joiner whose host link is freed forgets its slot and all streams (:1357).
- Who gets the state streams: the host sends Q and E only to a joiner that is `connected`, whose own P arrived in
  the last 3 s and carries `CO_FLAG_LEVEL` (Survival's level) (`CoWantsState`, :1205-1209). A joiner in the menus, loading,
  or on another build gets only hellos and reliable messages.
- Per-frame work runs on the game thread from the music player's tick (`CoopFrame`, :1422-1433, `CoStep` per frame, at
  most once per millisecond). The Lua calls (`SV_CoopSend`, `SV_CoopRecv`, `SV_CoopInfo`) also run `CoStep(now, 0)`
  when no frame ticked for 0.1 s (menus, loading) (coop_lua.c:96, :150).

## 2. Packet types

Every packet starts with a 4-byte header: `'S'` (0x53), `CO_PROTO` (4), type letter, flags byte (always 0 and never read;
`CoHeader`, coop.c:594). Integers are little-endian (memcpy of native values). Sizes below include the header.
`CO_FL` = 13 (flight block), `CO_Q_REC` = 49 + 13 = 62, `CO_P_SIZE` = 4 + 60 + 13 = 77.

| Type | Direction | Rate | Reliable | Size (bytes) | Code |
|---|---|---|---|---|---|
| H hello | both, per link | 1 Hz per link; plus 0.5 Hz per Steam candidate while searching | no | 119 | send :606-621 (call :1341-1345), parse :891-983 |
| L reliable Lua | both | on demand (section 4) | yes (own scheme) | 14 + len (len <= 1100) | send :701-715, parse :737-761 |
| K ack | both | one per CoStep in which an L (new or repeat) arrived | no (cumulative; loss repaired by the next one or by L's resend) | 12 | send :716-721, parse :724-735 |
| U unreliable Lua | both | on demand | no | 6 + len | send :668-677, parse :1041-1044 |
| P joiner's own plane | joiner -> host | 30 Hz, always | no | 77 | send :1178-1203, parse :1044-1052 |
| Q batch of planes | host -> each joiner in level | 30 Hz up to 6 players, 20 Hz at 7+ | no | 5 + 62 x records, <= 19 records per packet | send :1213-1230, parse :1053-1064 |
| E tracked enemies | host -> each joiner in level | 15 Hz | no | 10 + 22 x enemies, <= 54 per packet | send :1232-1261, parse :1065-1088 |

Layouts (offsets from the start of the packet; header at 0-3):

- H (119 B): [4] role; [5..8] nonce; [9..12] sender time in ms (`CoMs(QPC)`); [13..16] echo of the last hello's time heard on
  this link; [17..20] age of that echo in ms; [21] `yourSlot` (host: the slot it gives, 0xFF none yet, 0xFE full, 0xFD wrong
  build); [22] max players; [23..54] version string (32 B); [55..118] name (64 B) (coop.c:606-621; parse :893-904).
  A joiner's version and name are therefore re-sent 1 Hz per link for the whole session (see section 9).
- L (14 + len): [4..7] sender nonce; [8..11] seq (per link, starts at 1); [12..13] len; payload (coop.c:709-712).
- K (12): [4..7] sender nonce; [8..11] `recvNext` = every seq below this arrived (coop.c:717-718).
- U (6 + len): [4..5] len; payload. No nonce, no seq.
- P (77): [4] sender slot (the host ignores it and uses the link), [5..7] spare; [8..11] sender time ms; [12..35] position
  (3 doubles, cm); [36..51] rotation as 4 float32 quaternion; [52..55] health int32; [56..59] max health float32;
  [60..63] Lua's state flags (32 bits: level, alive, airfield, down, gear, afterburner, gun, flares); [64..76] flight block
  (coop.c:1013-1015, :1186-1203; parse offsets +4 from `p = b + 4` at :1030, P parse :1046-1050).
- Q (5 + 62n): [4] record count; then n records of 62 B (`CoQRec`, coop.c:985-996): slot (1), time ms (4), position 3 doubles (24),
  quaternion as 4 int16 x 32767 (8), health (4), max health (4), flags (4), flight block (13). n <= 19 (1,200 B limit:
  the flush test at :1221 splits after 5 + 19 x 62 = 1,183 B). Contains every player's latest record that arrived since the
  last batch (`fresh`), the receiver's own left out, slot 0 = the host's own plane (:1213-1230).
- E (10 + 22n): [4..7] host time ms; [8..9] count; then n records of 22 B: id (2, 1..65535), position 3 float32 (12),
  quaternion 4 int16 (8) (coop.c:1232-1261). n <= 54 per packet (the flush test at :1249 after 10 + 54 x 22 = 1,198 B).
  Every tracked enemy with a live local object goes out each time, whether it moved or not. The same buffer is sent once per
  eligible joiner (:1251, :1257).
- Flight block, 13 B (`FlFlightBlock`, flight_coop2mp.c:119-139): 6 stick axes as int8 x127 (pitch, yaw, roll, throttle, brake,
  high-G), afterburner amount x255, speed m/s x10 as uint16, the flight State as uint32. It rides on every P and every Q record
  (COOP2MP's real player planes are fed from it).

Rate rules and timers (CoStep, coop.c:1329-1374):

- `hz = 20` when this game is the host and `linked + 1 > CO_FAST_UPTO (6)`, i.e. 7 or more players, else 30 (:1365). One
  timer drives both the host's own record, the Q batches (host) and the P (joiner): a joiner always sends P at 30 Hz
  (the 20 Hz rule is host-only).
- E has its own 15 Hz timer (:1371). H has a per-link 1 s timer (:1341-1345).
- The timers test `now - last >= 1/hz` once per frame and then set `last = now` (not `last += period`): the achieved rate is
  quantised by the frame rate. At 60 fps 20 Hz needs 3 frames (50.0 ms against 3 x 16.67 ms: borderline, so some intervals
  are 4 frames = 15 Hz) (inferred; to measure). Evidence of a shortfall: the 2026-10-30 run measured 85-105 KB a minute from
  joiners at protocol 3 (docs/re/COOP.md:377-378), i.e. about 1.45 KB/s against 30 x 64 B + hellos = 2.0 KB/s, about 22-25
  effective packets/s (inferred arithmetic).
- Q only carries `fresh` records: if a joiner's P did not arrive since the last batch its record is skipped for that
  batch, so the packet is shorter, never padded (:1220). With P at 30 Hz and Q at 20 Hz one in three of a joiner's P is never relayed.

## 3. Reliability (L and K)

Only Lua messages are reliable; P, Q, E, U and H are fire-and-forget.

- Send side (`CoSendLua`, coop.c:668-684): a reliable message is copied to the link's queue `out[]` with the next seq,
  `sentAt = -1`. Queue size `CO_RELIABLE` 256; a full queue drops the new message and logs
  "reliable queue to player N full; a message was dropped" for every dropped message (:679, no rate limit). The queue is
  filled for any `used` link, connected or not (the check is `L->used`, :670).
- Flush (`CoFlushReliable`, :701-722), once per link per CoStep (per frame): walks the queue in order, sends up to 16 messages
  per call (1 when the link is not `connected`). A message goes out when it was never sent, or when `now - sentAt >= CoRto`.
  Resends are counted in `L->resent` (:708). `tries` saturates at 255.
- Timeout (`CoRto`, :690-699): `rto = rtt x 1.5 + 0.1 s` (0.5 s until a round trip is known), at least 0.25 s, doubled for each try
  after the first, at most 4 s. The round trip is the hello echo, smoothed 0.8 / 0.2, accepted when within 0..5 s (coop.c:979-982,
  CoOnHello's tail: `L->rtt*0.8 + rtt*0.2`, one sample a second).
- Acks (`CoOnAck`, :724-735): cumulative only ("every seq below N arrived"); messages with seq < N are freed. When N advances,
  the remaining messages' `tries` are put back to 1 so they wait one round trip again, not a backed-off time. No selective
  ack: a lost L blocks the delivery of every later message on that link (head-of-line blocking) until it is
  resent (>= 250 ms after its send, more on slow links).
- Receive side (`CoOnReliable`, :737-761): sets `ackDue` for every L, even a duplicate. seq below `recvNext` -> duplicate,
  dropped silently. seq ahead: held in a 64-slot out-of-order ring (`CO_OOO`) indexed by seq mod 64; more than 64 ahead
  is dropped ("it comes again"); an occupied slot is not overwritten. In-order messages are pushed to the Lua inbox, then
  any consecutive held ones.
- K is built at the end of CoFlushReliable when `ackDue` (:716-721): one K per CoStep per link however many L arrived.
- Lost link: while not `connected` a link is sent only its oldest reliable message as a probe (:704) plus hellos. After 90 s
  the link, with its queue, is freed without a log of how many messages were discarded (:1352-1358, `CoLinkFree` :645-649).
  A new session of the peer (nonce change) clears both directions' reliable state (`CoLinkResetReliable` :638-644).
- Inbox: `CO_INBOX` 512 messages; `CoInboxPush` (:624-636) drops when full and logs "Lua inbox full; a message was dropped"
  (no rate limit). It also stamps each message with "<sender slot>|" . The U path and system lines (`sys|...`) share it.
  Lua drains up to 600 messages per `COOP.tick` (sv_coop_migration.lua:1293-1298), and `COOP.tick` runs once per 250 ms
  (sv_main.lua:1028; the tick is 250 ms in two halves, sv_main.lua:958-960), so the inbox is read at 4 Hz.
- Bad input counter `CO.badPk` (:405): truncated/unknown/oversized packets, packets from unknown Steam senders, unsane
  states (`CoSaneState` :763-769: non-finite or > 1e10 position, quaternion not near unit length). It is the only
  counter of dropped input and is printed in the 60 s line.
- Accounting caveat: `txPk`/`txB` count only sends the transport reported as successful, and payload bytes only (no
  IP/UDP/Steam overhead) (sends :584-585, counted :586); `rxPk`/`rxB` count every packet of a known link except H (the hello branch returns before
  the counters, :1024 against :1028), while `txPk` does include hellos. So tx and rx in the 60 s line are not symmetric (section 7).

## 4. Lua traffic

Lua sends through `sendTo(to, reliable, kind, fields...)` / `send(reliable, ...)` (sv_coop.lua:53-59): fields are joined with
`|`, `|` inside a field replaced by `/`, then `SV_CoopSend(text, reliable, to)` (coop_lua.c:129-142). `to = -1` queues the
message once per linked game (a copy and a seq per link, including links that are lost). A joiner's links are only the host, so
its messages all go to the host. Maximum length 1,100 bytes. Received text is "<slot>|<kind>|...". Lua code runs in
`COOP.tick`, every 250 ms, so a message produced between ticks leaves at the next CoStep after it is queued, and a received one
waits for the next tick (average extra latency of about 125 ms each way, bounded by 250 ms) (inferred from the tick period).

Kinds, grouped by who sends them. "Reliable" is `send(true, ...)`. Frequencies are what the code allows; sizes are rough
(inferred from field lists), per message before the 14-byte L header.

Host -> joiners (every linked game unless noted):
- `rnd` unreliable, once a second (`hostTick`, sv_coop.lua:854-895): round, state, seconds, wave, waves, alive, level, glitch
  phase, allies' room code, special, special state, purchase counters, fishing arc. About 100-300 B (inferred).
- `hp` reliable, once a second, only enemies whose health changed since the last send, batches of up to 60 entries `id:hp`
  (sv_coop.lua:787-819). Up to about 600 B a message; zero in a quiet second.
- `dn` reliable, one per enemy death, at once (sv_coop.lua:799-800, :128, :730). About 15-25 B.
- `bd` reliable, one per mirrored aircraft at spawn (sv_coop.lua:612) and `gd` one per ground object (:630): unit, generation,
  ordinal, stream id; `sp` one per flight (sv_coop.lua:511, pose and ops text). Bursts at each wave start: 60 aircraft are
  60 `bd` plus the `sp` lines; the flush limit of 16 messages per link per frame spreads a burst over a few frames.
- `af` reliable when the airfield state changes (at most every 2 s, resent every 10 s, sv_coop.lua:911-918); `spx` the
  Spaceport state, at most 1 Hz, repeated every 10 s (sv_coop.lua:900-909); `fsx` unreliable, 1 Hz for the festival (sv_festival.lua:681-683; the fishing caller was not checked)
  rounds (sv_coop.lua:85); `hl` (sv_coop_migration.lua:102) and `al` (:98, every 30 s) small status messages.
- Events and UI: `ev` (mirrored event names, sv_coop.lua:486, :848, :1052), `co` (callouts, sv_coop_migration.lua:871), `sb`
  (subtitles, :879), `cr` / `db` (pay, sv_coop_migration.lua:908, sv_coop.lua:66), `fh` / `fw` / `fwe` (fishing), `vm` / `vr`
  (VALKA), `wd`, `tl` / `dv` (tells and decoys, sv_coop.lua:287, :318), `pi` roster lines (sv_coop.lua:635-645, on a change),
  `cf` settings chunks (sv_coop_sync.lua:1077, at link time and on change), `rs`, `po`, `rj`, `rz`, `hq`, `ro`, `rc`, `ab` / `ar` /
  `ak` / `ax` / `ao` / `ag` (shop and orders, sv_coop_sync.lua:1177-1242). Event-driven, a few a minute in normal play.

Joiner -> host:
- `in` unreliable, about once a second (`COOP.sendIntensity`, sv_coop.lua:329-333): intensity, comfort, health, missiles.
- `ht` reliable, sent on each loss or floor event on a mirrored enemy (sv_coop_joiner.lua:983-1008); no throttle found in that code
  (the 4-a-second cap in COOP.md:546 is for dw/rv, not ht). Small (about 20 B); its rate is not bounded by the code read.
- `fx` reliable, shots and gun-target changes, built in `M.syncTick` every Lua tick from the new launches
  (sv_coop_sync.lua:667-707): up to `FX_MAX` entries per message, only when something was fired. The host fires them locally and
  relays the passed entries to every other joiner as another `fx|<slot>|...` reliable message
  (sv_coop_sync.lua:586-592). One shot is therefore one reliable message up and N-2 down.
- `hi` (roster line, sv_coop_sync.lua:907; re-sent every 10 s until the host lists the joiner, sv_coop_migration.lua:1325, and on a change of airframe or loadout), `jn` (join request, sv_coop_joiner.lua:851,
  sv_coop_migration.lua:741), `dw` / `rv` (down / revive, at most 4 a second), `sq`, `rj`, small and rare.

The host also sends `sys|...` lines to its own Lua through the same inbox (joined, up, lost, left, restart, slot, refused...,
coop.c:850-851, :1346-1358). These are not network traffic.

Not on the wire: every other state (gear, afterburner, gun, flares, down) is in the P/Q flags word; the plane pose, health and
flight block are in P/Q; enemy pose in E. Enemy health is `hp` (1 Hz).

## 5. Interpolation and puppets

- A "puppet" is a local plane bound to a stream: another player's plane (`CoPlayer.plane`, SV_CoopPeer) or, on a joiner, a copy
  of a host enemy (`CO.ents[]`, SV_CoopBind). Each stream is a ring of the last `CO_SNAPS` = 12 snapshots
  `{sender time, position, quaternion}` (coop.c:50, :771-780). A snapshot older or equal to the newest is ignored; insert
  after `CoSaneState`. Twelve snapshots are 0.6 s at 20 Hz, 0.8 s at 15 Hz.
- Every frame (`CoDrive`, :1305-1327) each puppet is moved to where its stream was at `render time = now - offset - delay`, on the
  sender's clock, by the plane's own teleport (vtable slot 315 for an AI plane; for a player plane `AActor::TeleportTo` plus
  the flight reset without OnReposition, coop.c:507-541). A plane that is a real player plane fed by the remote update
  (`FlFeeds`) is not teleported: it is fed the sampled pose and the flight block (:1311).
- `CoTrackOffset` (:787-795), per received state: `est = local now - sender ms`. `offset` is the smallest `est` seen, letting go
  by 0.1 % of the difference per packet (clock drift, slower route). `late = est - offset`; `jit` follows `late` by 30 % per packet
  when it rises, 0.5 % per packet when it falls (about 7 s at 30 Hz, about 13 s at 15 Hz) (inferred time constants). Frames longer
  than 0.1 s on this game (`CO.frameGap`) and `late` outside 0..2 s are not counted.
  Enemy states feed player 0's tracker (the host's clock): both E packets and the host's Q records (:1072).
- `CoAdaptDelay` (:797-807), once per frame per player: `want = jit + 30 ms`, clamped from `CO.delay` (Lua `interp_ms`, 120 ms
  default; sv_coop_migration.lua:1020) up to `CO_DELAY_MAX` 300 ms; the delay moves toward `want` by at most 0.1 s per second.
  `CoRenderDelay` returns that value (or `CO.delay` before the first adaptation).
- `CoSample` (:1263-1289) returns how it placed the puppet: 1 inside the snapshots or before the first (linear position, nlerp
  rotation), 2 past the newest snapshot by up to 0.5 s ("ahead": position extrapolated along the velocity of the last two
  snapshots, with no cap on that velocity), 3 more than 0.5 s past the newest ("held": stays at the last position, no
  extrapolation, rotation frozen). `CoDriveOne` counts `drives`, `ahead` (2 and 3 together) and `held` (3 only) (:1291-1303);
  a failed teleport counts `fails`. A plane with health <= 0 is left to fall (:1295).
- The 60 s line reports these per minute (section 7). Rule of thumb: `ahead/moves` near 0 means the delay is large enough;
  a high `held` means the stream stopped (loss, a stalled sender, a stream the host no longer sends).
- Streams are reused when a stream id's entry has no bound actor and has been silent for 3 s (`CoEntById`, :809-825); the table
  holds 256 enemies (`CO_MAX_ENTS`), ids up to 65,535.

## 6. Expected bandwidth

Method: payload bytes from section 2, rates from the timers. N = number of players (host included); J = N - 1 joiners;
n = enemies tracked (an `SV_CoopTrack` call per mirrored aircraft; the cap on aircraft up at once is `coop.max_up` 30 and a
round's total `coop.max_aircraft` 60, COOP.md:390-392, so 20 is a mid-fight figure and 60 a ceiling).

Formulas (per joiner, bytes/s, the host's upload to it = that joiner's download):
- Q: `hz x (ceil((N-1)/19) x 5 + (N-1) x 62)` with `hz = 30` for N <= 6 and 20 for N >= 7. All records assumed fresh (upper bound).
- E: `15 x (ceil(n/54) x 10 + 22 n)`: 6,750 B/s at n = 20 (1 packet), 20,100 B/s at n = 60 (2 packets).
- H: 119 B/s. L/K and U: not in the table (estimate below).
- Host total upload = J x per-joiner stream. Joiner upload = P (30 x 77 = 2,310 B/s) + H 119 + K + its Lua messages.

Payload only (no IP/UDP/Steam headers); packets/s counts Q, E and the hello.

| N | Q hz | Q B/s per joiner | per joiner Q+E+H, 20 enemies | per joiner Q+E+H, 60 enemies | host upload, 20 enemies | host upload, 60 enemies | host pkt/s, 20 / 60 enemies | joiner upload |
|---|---|---|---|---|---|---|---|---|
| 2 | 30 | 2,010 | 8,879 | 22,229 | 8.9 KB/s | 22.2 KB/s | 46 / 61 | about 2.4 KB/s |
| 4 | 30 | 5,730 | 12,599 | 25,949 | 37.8 KB/s | 77.8 KB/s | 138 / 183 | about 2.4 KB/s |
| 8 | 20 | 8,780 | 15,649 | 28,999 | 109.5 KB/s | 203.0 KB/s | 252 / 357 | about 2.4 KB/s |
| 12 | 20 | 13,740 | 20,609 | 33,959 | 226.7 KB/s | 373.5 KB/s | 396 / 561 | about 2.4 KB/s |
| 24 | 20 | 28,720 (2 packets) | 35,589 | 48,939 | 818.5 KB/s | 1,125.6 KB/s | 1,288 / 1,633 | about 2.4 KB/s |

(KB = 1,000 B here.) The host's upload at 24 players is about 6.5 Mbit/s with 20 enemies and about 9 Mbit/s with 60, payload
only. A joiner's download is the per-joiner column: 8.9 to 49 KB/s, dominated by Q at 12+ players and by E at 8 or fewer.

What is estimated, what is exact:
- Exact given the code (with all records fresh and the timers at their nominal rate): packet sizes and the Q / E / H / P
  figures. They are upper bounds: Q skips records not refreshed (:1220), a frame-quantised timer lowers the rate, and
  players not in the level get no Q or E (:1205).
- Estimated (inferred): enemy count n; Lua L/K traffic, which I put at roughly 0.3 to 1 KB/s per link in steady state from the
  kinds in section 4 (`rnd` about 150 B/s + `hp` up to 600 B/s + `dn` and `fx` events + 12 B acks), with bursts of 5 to 10 KB
  at a wave start (60 `bd` x about 75 B incl. header, plus `sp`). It is small next to Q/E at 8+ players, and should be
  measured, not trusted.
- Cross-check with the only measurement in the docs (COOP.md:376-378, 13 players, protocol 3, 49-byte Q records, some
  joiners in menus or loading): the host sent 450-850 KB/min per joiner = 7.5-14 KB/s and received 85-105 KB/min. The model for
  13 players gives Q 20 x (5 + 12 x 49) = 11.9 KB/s plus E, i.e. at or above the top of the measured range; the measured values are
  below the model, consistent with fewer fresh records, a lower achieved rate and enemies not tracked all the time (inferred).

Per-packet overhead, assumption stated separately: UDP over IPv4 adds 28 B per packet (20 IP + 8 UDP). Steam P2P adds its own
framing and, through a relay, more; the repo has no figure for it, so I assume 28 to 60 B per packet in total for Steam
(assumption, not read anywhere). At 24 players and 20 enemies the host sends 1,288 packets/s, which adds 36 KB/s at 28 B
(+4.4 %) or 77 KB/s at 60 B (+9 %). At 2-4 players, where packets are small (about 190-1,200 B), the overhead share is
larger (4 players: 138 pkt/s x 28 B = 3.9 KB/s on 37.8 KB/s, 10 %).

## 7. What is measured today

The only periodic native statistics are in `CoStep` once per 60 s (coop.c:1374-1418), starting 60 s after `SV_CoopOpen`.

Line 1, "coop: you are player N; B enemy streams bound (D moves, F failed); K bad packets; enemies drawn X ms behind the host
(lateness Y ms); the last minute's M enemy moves: A past their newest state, H held" (:1385-1388):
- B: enemy streams with a bound local actor (on the host, the tracked enemies; on a joiner, the bound copies).
- D, F: cumulative moves and failed teleports of those streams since they were bound.
- K: `CO.badPk`, cumulative since open (all packet kinds, sender unknown, unsane state).
- X: the host stream's render delay `CoRenderDelay(&players[0])`; Y: its `jit` (lateness).
- M, A, H: enemy moves in the last minute, how many were past the newest snapshot (ahead, includes held), how many held. These
  last three reset each minute (:1380-1383); D and F do not.

Line 2, one per used link: "coop:   player N <name>: linked|link lost, rtt R ms; sent P packets (S KB), got Q (T KB), U
resent; their plane D moves" (:1389-1394): packets and KB are cumulative since the link opened (not per minute: a rate needs two
lines and a subtraction), KB is integer-truncated payload, tx includes hellos, rx excludes them (section 3). `U` is the cumulative
resend count. `D` = that player's plane moves here, cumulative.

Line 3, "coop: planes here (player drawn-behind/lateness ms past/moves, the last minute): ..." (:1397-1417): per bound player puppet,
render delay / lateness in ms, and `ahead/moves` over the last minute.

Other native coop log lines (all `Log(L"coop: ...")` in coop.c unless noted): offsets resolved once (:443, in
`CoResolve`); "open: ..." and a missing teleport warning (coop_lua.c:81, :84); "looking for players: N Steam friend(s)" when the
candidate count changes (:1175); "joined / paired with <name> (host|joiner, mod V) as player N" (:850); refusals (:882,
once a minute per player); "also the host / joiner" (:911); "you are player N" (:969); "host's game is full" (:939), "runs
Survival X, this game Y" (:950); "another game's co-op protocol is P, ours 4" (:1021); new-session lines (:931, :960); "player N:
link up" / "link lost (nothing for 6 s)" (:1347-1348); "player N gone (nothing for 90 s); the slot is free" (:1353); "reliable
queue to player N full" (:679); "Lua inbox full" (:626); "a puppet's actor is gone (stream N); unbound" (:1294); the afterburner
and second-plane lines (coop.c:1319, coop_lua.c, flight_coop2mp.c "coop2mp: fed plane ..."); "closed" (:1441).

Lua side: `SV_CoopInfo()` returns state, slot, players and per-link "slot/state/rtt ms/ms since last/name", polled every 5 s and logged
when the state changes (sv_coop_migration.lua:1302-1317); Lua keeps per-link rtt for shot ages. The general "perf: tick avg ...
parts (ms a tick / worst, share)" line (sv_main.lua:925-950) includes a "coop" row: the Lua cost of `COOP.tick` per 250 ms tick, so the
Lua half is timed; the native `CoStep` is not.

## 8. Gaps, and the planned measurements

Planned measurements (not built yet): two CSV logs. One row per interval, per link and direction and packet type: packets, bytes, largest packet, busiest 1 s (Lua messages split by kind as `L:<kind>`). One row per interval per link: round trip, lateness, drawn-behind delay, estimated loss of P/Q/E, reliable queue depth, resends, drops, moves and held moves, CoStep CPU time.

| Cannot be diagnosed today | Because | Planned measurement |
|---|---|---|
| Bytes per packet type, per player, per direction | only cumulative packets and payload KB per link, all types together | packets, bytes, largest packet by type and direction |
| Bursts and peaks (a wave start, a hitch flush) | only cumulative totals, a 60 s cadence | busiest 1 s, largest packet |
| Loss on P, Q, E | none of them carry a sequence number; nothing counts expected vs received | loss P/Q/E (estimated from the send time stamps) |
| Reliable queue depth, resends over time, drops | `nout` is not logged; `resent` is cumulative; a drop logs a line per message | queue depth, resends, drops |
| Per-kind Lua volume (which feature costs bytes) | kinds are not counted anywhere | `L:<kind>` rows |
| CPU time of CoStep (and of CoPump / CoDrive inside it) | only Lua's COOP.tick is timed | CoStep time, average and max |
| Interpolation health per player | only the minute's `ahead/held`, as text | lateness, drawn-behind delay, moves, held |
| Link quality over time | rtt only in the 60 s line and a 5 s Lua poll | round trip per interval |

Gaps the planned measurements do not cover (found while reading):
1. Send failures. `CoRawTo` ignores a failed `SendP2PPacket` / `sendto`, counts nothing and logs nothing (:583-585). A
   saturated or broken link would look like silence on the sender's side. Count `tx_fail` per link and type.
2. Packets silently refused for size (`n > CO_MAX_PACKET`, :579) and the break-down of `CO.badPk` (truncated, unknown Steam
   sender, unsane state, unknown type, protocol mismatch). Today it is one number.
3. Steam's own view: `ISteamNetworking::GetP2PSessionState` (relay or direct connection, bytes queued, last error) is never read
   (inferred from the Steamworks API; not used anywhere in the repo). Steam relay round trips of 220-470 ms are the
   documented difference between links (COOP.md:377-378), so "relayed or direct" is the first thing to record per link.
4. Reliable-channel health: ack latency (send to ack time), head-of-line wait, out-of-order ring occupancy and rejections
   ("more than 64 ahead", :743), duplicates received, queue messages thrown away when a link is freed after 90 s (:1352-1358).
5. Inbox depth and age: the Lua inbox is read at 4 Hz (section 3); depth and the wait before Lua reads a message are not
   measured. Dropped "inbox full" and "queue full" are lines, not counts.
6. Achieved send rate against the target (the frame-quantisation of section 2). Packets per interval gives it, but nothing
   records the frame gap distribution; `CO.frameGap` hitches over 0.1 s (which bias lateness and skip jitter updates, :793)
   are not counted. A per-interval count of hitches and the worst gap would explain "held" bursts.
7. Streams' size, not just packets: how many enemies E carried (n per packet, tracked ids), and how many Q records per batch
   (how many players were fresh). These two numbers make bytes explainable.
8. Teleport failures (`fails`) per player, `fedSkip` / `fed` for real planes (they exist in `CoPlayer`, :386, but only the
   enemy `failed` total is printed).
9. Accounting symmetry: the 60 s line's tx counts hellos and rx does not; KB is truncated; counts are cumulative. The CSV counters
   should count at the same two points for both directions (every `CoRawTo` success, and every packet entering `CoOnPacket`).
10. Loss estimation needs something to compare. P, Q and E have no sequence number, so "expected" can only come from time stamps and
    nominal rates, which the frame quantisation makes uncertain. The header's flags byte (byte 3) is always 0 and never read
    (coop.c:594, :1016-1018), so an 8-bit per-link sequence could go there without changing any packet size (protocol
    bump or not to be decided; an old receiver ignores the byte).
11. Bytes on the wire vs payload: no overhead term (section 6); the counters should add the assumed per-packet overhead as a
    constant, labelled, or log the packet size distribution.

## 9. Suspected hot spots for later optimisation (observations only; each "to measure")

1. E has no interest management or delta coding: every tracked enemy, moved or not, 22 B each at 15 Hz to every joiner in the
   level, the same bytes built once and sent J times (coop.c:1232-1261). With 60 enemies and 24 players this is
   20 KB/s x 23 = 462 KB/s from the host, about 41 % of the table's top figure. Candidates: skip unchanged enemies, rates by
   distance to each joiner, quantised positions (the 12-byte float position and 8-byte quaternion are generous).
   To measure: n per E packet, bytes per interval for E.
2. Q is all-to-all through the host, O(N squared) in bytes: each of J joiners gets N-1 records of 62 B at 20 Hz
   (coop.c:1213-1230); 28.7 KB/s per joiner and 660 KB/s total at 24 players, 81 % of the stream at 24 players with 20 enemies.
   Each record repeats unchanged fields every time (max health, flags, the 13 B flight block, 4 B time stamp, doubles for the
   position). A parked or airfield plane is sent at full rate. Candidates: delta against the last record, lower rate
   for far or idle players, int32 or quantised positions. To measure: bytes of Q by interval, records per batch.
3. Rate quantisation (section 2): `lastPlayerSend = now` per frame test means 20 Hz at 60 fps may run closer to 15 Hz and 30 Hz
   to 20-30 Hz at lower frame rates, and the Q rate also depends on the host's frame rate. Possible smoothness loss
   rather than bandwidth. To measure: packets per interval against 20 / 30.
4. Reliable channel: cumulative-ack only, so one lost L delays everything behind it (coop.c:724-735); a message more than 64 ahead
   is dropped and waits a full RTO (:743); the minimum RTO is 250 ms and the RTO uses a smoothed 1 Hz hello sample (rtt x 1.5 + 0.1).
   On the 220-470 ms Steam relay links (COOP.md:377-378) reliable latency for kills, hp, spawns and shots can reach
   hundreds of ms on every loss. Shots (`fx`) and kills (`dn`) are reliable and ordered with everything else. To measure: ack
   latency, resends per kind, queue depth.
5. Lua cadence: messages are produced, and read, every 250 ms (sv_main.lua:958-960, sv_coop_migration.lua:1293). Reliable latency has
   a floor of about 125 ms per direction (inferred) on top of the network. `hp` is one batch per second. To measure: inbox age.
6. Reliable fan-out and queue on lost links: `to = -1` copies each message into every link's queue (coop_lua.c:129-142), including
   links that are `used` but lost (:670), which accumulate up to 256 messages for up to 90 s and then log
   a line per dropped message (:679). Relay of `fx` is another copy per other joiner (sv_coop_sync.lua:586-592). To measure: rel_queue
   on lost links, log lines per minute.
7. Hello: 119 B per second per link in both directions, and it repeats the 32 B version and 64 B name forever (coop.c:606-621);
   2.7 KB/s at the host at 24 players. Discovery adds a hello every 2 s to every Steam friend playing the game while the host has
   a free slot (:1125-1175), i.e. until the room is full. Small; the 1 Hz echo is also the only RTT sample (see 4).
8. Receiving cost: the host handles 23 x 30 = 690 P/s, K, H and `fx`, via `CoPump` up to 512 packets per frame (:1096-1121), each with
   a `CoSaneState`, a snapshot push and, for the host, a Q record copy (:998-1012). On joiners, `CoDrive` teleports every bound
   puppet every frame (:1305-1327): 60 enemies plus 23 plane puppets are 83 slot-315 teleports a frame, a call that also runs the
   AI plane's OnReposition (coop.c:495-506 comment, :1300). CPU, not bandwidth; nothing times it today.
9. Packets are one per `CoSendTo` with no coalescing: a joiner's P (77 B), the host's Q and E, K and L are separate datagrams,
   each paying the per-packet overhead (section 6). Coalescing the small ones (P with K, hello, U) could cut packet counts.
   To measure: packets per second by type.
10. A time-base note (inferred): states carry `CoMs(QPC)` as a uint32 of milliseconds, and QPC counts from boot, so the field
    wraps after about 49.7 days of machine uptime (coop.c:599, `CoMs`). A wrap mid-session would make `CoPushSnap` drop states as
    "old" (:773-775) and break the offset. Unlikely, but a free fix when the packet format is next changed (relative time since
    `SV_CoopOpen`).
