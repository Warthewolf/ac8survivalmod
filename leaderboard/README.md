# AC8 Survival Mode leaderboard

A Cloudflare Worker that takes finished Survival runs from the game and puts them on Discord:

- every submitted run is posted to a **#survival-runs** channel;
- a pinned message in **#survival-leaderboard** keeps the top 10 by **highest round** and by **score** for each
  difficulty (Casual / Standard / Ace), and the **fastest time for each special round**;
- a second pinned message keeps the **records** (most kills, longest run, most zollars earned, most ace squadron kills
  and most specials beaten in one run), the **best run on each aircraft**, and **this week's** best rounds and scores
  (the week starts Monday 00:00 UTC);
- slash commands: `/leaderboard [board] [difficulty]` (boards: round, score, specials, records, aircraft, this week)
  and `/pilot <name>` (best runs, fastest specials, totals and most flown aircraft).

Players appear under their Steam name (the mod reads it from the game's Steam), or under the `pilot` name they set in
`survival.ini`'s `[leaderboard]` section. The game sends every finished run here over HTTPS (Survival's own runtime; it never talks to
Bandai Namco's services). The Worker works the score out itself, checks the numbers are possible, refuses duplicates
and limits each sender (IP) to 30 runs an hour.

Only **stock runs** count (from mod 0.72.x):
- the game doesn't send a run whose gameplay settings differ from the shipped ones (`survival.ini` or a
  `Scripts/survival_config.lua`; the HUD, sound, music, the pilot name, key bindings and texts don't count), one that
  started past round 1, or one in which a test key was pressed: its summary says `NOT RANKED: EDITED (<setting>)` and
  its log names every changed setting (`Scripts/sv_leaderboard.lua`, `LB.edited`, has the full list);
- the game's runtime hashes Survival Mode's own files (its scripts, `survival.default.ini`, `main.dll` and the
  `SurvivalMode_P` container) and sends the hash with each run, signed with it; the Worker takes a run only from a
  **build you registered** on the admin page (below). Anything else is refused as `edited or unknown build`.
- the **admin page** (`/admin`, you only) resets the boards (undoable), registers builds and switches build
  verification on and off.

**Score** = 1000 a round reached + 100 an aircraft + 50 a ground or sea target + 3000 a special round beaten,
x 0.75 Casual / 1.0 Standard / 1.5 Ace.

It's free: Cloudflare's free plan covers Workers and D1 (the database) many times over for this.

## Setup (once, about 20 minutes)

### 1. Discord: the bot
1. Go to https://discord.com/developers/applications and press **New Application**. Name it, e.g. *Survival Mode*.
2. On **General Information** copy the **Application ID** and the **Public Key** (you'll paste both in step 4).
3. On **Bot**: press **Reset Token** and copy the token (keep it secret: it's the bot's password). Leave
   "Public Bot" off if only you should be able to add it.
4. On **OAuth2 → URL Generator**: tick **bot** and **applications.commands**; under Bot Permissions tick
   **Send Messages**, **Embed Links**, **Read Message History** and **Manage Messages** (to pin the leaderboard).
   Open the URL at the bottom and add the bot to your server.

### 2. Discord: the channels
1. Make two text channels, e.g. **#survival-runs** and **#survival-leaderboard** (the bot needs to be able to post in
   both; you may want only the bot to post in #survival-leaderboard).
2. In Discord's settings → Advanced, turn on **Developer Mode**. Right-click each channel → **Copy Channel ID**.

### 3. Cloudflare: the database
1. Make a free account at https://dash.cloudflare.com.
2. **Storage & Databases → D1 → Create**, name it `ac8-survival`.
3. Open it → **Console**, paste everything in `schema.sql` and run it.

### 4. Cloudflare: the Worker
1. **Workers & Pages → Create → Create Worker**, name it `ac8-survival-leaderboard`, **Deploy**, then **Edit code**.
2. Replace the code with `src/index.js` (all of it) and **Deploy**.
3. Worker → **Settings → Bindings → Add → D1 database**: variable name `DB`, database `ac8-survival`.
4. Worker → **Settings → Variables and Secrets**, add:

   | name | type | value |
   |---|---|---|
   | `DISCORD_APP_ID` | Text | the Application ID |
   | `DISCORD_PUBLIC_KEY` | Text | the Public Key |
   | `RUNS_CHANNEL_ID` | Text | #survival-runs' ID |
   | `BOARD_CHANNEL_ID` | Text | #survival-leaderboard's ID |
   | `DISCORD_TOKEN` | Secret | the bot token |
   | `SUBMIT_KEY` | Secret | any long random text; the game signs runs with it (the mod's build must use the same) |
   | `ADMIN_KEY` | Secret | another long random text, for step 6 |

5. Copy the Worker's address, e.g. `https://ac8-survival-leaderboard.<you>.workers.dev`.

### 5. Discord: point the slash commands at the Worker
On the application's **General Information** page, set **Interactions Endpoint URL** to the Worker's address +
`/interactions`, e.g. `https://ac8-survival-leaderboard.<you>.workers.dev/interactions`, and save (Discord checks it
answers; it will once step 4 is done).

### 6. Finish
Open `https://ac8-survival-leaderboard.<you>.workers.dev/setup?key=<ADMIN_KEY>` in a browser. It registers the slash
commands and makes and pins the leaderboard message. It should answer `{"ok":true,...}`.

**After updating the Worker's code**, open the same `/setup` address again: it registers changed slash commands (e.g. the
new `/leaderboard` boards) and makes any pinned message that's new. Running it again is safe; it never makes a second
copy of a message that's already there.

Then send the Worker's address and the `SUBMIT_KEY` to whoever builds the mod (they go into the release build, not
into git).

## Updating the Worker to the admin page and build checks (2026-10-30)
1. Cloudflare → **Workers & Pages** → `ac8-survival-leaderboard` → **Edit code**. Replace everything with `src/index.js`
   (all of it) and **Deploy**.
2. Nothing to run in D1's console: the Worker adds its new tables (`builds`, `builds_seen`, `resets`, `runs_archive`,
   `specials_archive`, `admin_fails`) and the runs' new columns (`build`, `verified`) itself the first time it's used.
   (If you'd rather make them by hand, the new lines at the end of `schema_console.sql` are safe to paste: every one is
   `IF NOT EXISTS`.)
3. No new variables: the admin page uses the `ADMIN_KEY` secret you already have.
4. Runs from co-op builds (`0.72.2-coop.20`, Stable 1's `0.71.5-coop.17`) are taken now: they were all refused as
   `bad mod version` before.

## The admin page
Open `https://ac8-survival-leaderboard.<you>.workers.dev/admin` (a phone's browser works), type your `ADMIN_KEY` and
press **Unlock**. Your browser's password manager can keep it. The key goes in each request's body, never in the
address, so it's in no history or log. Five wrong keys from one address lock that address out for 15 minutes (the
`/setup` address's key counts too).

- **Status**: how many runs are on the boards, and whether build verification is on.
- **Builds runs are taken from**: the builds registered, each with how many runs it has. **Remove** stops taking its
  runs (those already on the boards stay).
- **Builds seen but not registered**: builds runs came from that were refused. Normally it's empty; if your own
  release shows up here you forgot to register it. Register a build from here only if you packaged it: an edited copy
  shows up here too.
- **Reset the leaderboard**: type `RESET` and press the red button. Every run and special result goes into the archive
  (`runs_archive` / `specials_archive`) under a reset id, so the reset can be undone; the boards (round, score,
  specials, records, best per aircraft, this week) start from zero, the pinned messages are updated and a note goes to
  #survival-runs. A run from before the reset that the game sends again isn't put back on the fresh boards.
- **Restore the last reset**: puts the latest reset's runs back (runs sent since stay). Pressed again, it undoes the
  reset before that one.

## Registering a build
`tools/package_release.sh online ...` prints `build hash: <64 hex characters>` and writes it next to the zip as
`<zip>.buildhash.txt` (its `mod` and `build` lines). On the admin page, paste that file's text into **Register a build**
(a note such as the zip's name is optional) and press **Register build**. Do it for every zip you give out, before
players send runs from it: a run counts only from a registered build, and a refused run isn't kept (the game drops it).
A build is its exact files: rebuilding or re-packaging gives a new hash to register.

## Build verification
- **Off** (the start): runs from mods older than 0.72.x (they send no build hash) are still taken, marked unverified
  (their post in #survival-runs says "older mod, build not checked"). Runs from 0.72.x or newer count only from a
  registered build either way.
- **On**: runs without a build hash are refused too (`no build check: update or reinstall survival mode`).

The order: register the build your players use, let them update to it, then turn verification on.

What it can't stop: everything runs on the player's PC. The submit key is inside `main.dll`, and the release's files
(so its hash) are public, so someone who digs the key out of the DLL can sign runs with any registered build's hash.
The checks stop edited settings, `survival_config.lua`, edited scripts or containers and older clients; they aren't
proof against a determined cheater. A reset or removing that pilot's runs is the answer then.

## Testing locally
`node test/worker.test.mjs` (Node 22 or newer) runs the Worker against an in-memory database with Discord stubbed out:
the checks, the boards, co-op versions, the admin page and its actions, builds, verification, reset and restore.
`sh tools/checks/build_hash_test.sh` checks that the game's runtime and `tools/build_hash.py` work out the same build
hash and signature; `sh tools/checks/leaderboard_test.sh` the game's edited-run check.
