# AC8 Survival Mode leaderboard

A Cloudflare Worker that takes finished Survival runs from the game and puts them on Discord:

- every submitted run is posted to a **#survival-runs** channel;
- a pinned message in **#survival-leaderboard** keeps the top 10 by **highest round** and by **score** for each
  difficulty (Casual / Standard / Ace), and the **fastest time for each special round**;
- slash commands: `/leaderboard [board] [difficulty]` and `/pilot <name>`.

The game asks "Submit run?" at the end of a run and sends it here over HTTPS (Survival's own runtime; it never talks to
Bandai Namco's services). The Worker works the score out itself, checks the numbers are possible, refuses duplicates
and limits each sender to 6 runs an hour.

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

Then send the Worker's address and the `SUBMIT_KEY` to whoever builds the mod (they go into the release build, not
into git).

## Testing locally
`node test/worker.test.mjs` (Node 22 or newer) runs the Worker against an in-memory database with Discord stubbed out.
