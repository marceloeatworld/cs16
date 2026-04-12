# CS 1.6 Fun Server

A fully configured Counter-Strike 1.6 dedicated server running on Docker, deployable to Coolify or a bare host in one command.

## Features

- **Full money** ($16,000) + free kevlar+helmet every round
- **125 HP** — slight boost, rifle headshots still kill
- **Smart CZ bots** blocked from AWP/Scout/AUG/SG552/Shield at the game-DLL layer
- **Bots always present** — server never looks empty to players browsing the list
- **Weakened Expert template** — HARD brain (smart pathing, grenades, teamwork) with forgiving aim
- **Weapon restrictions** — tactical shield and auto snipers (G3SG1/SG550) banned for everyone, AWP limited to 3 per team
- **No-reload pistols + shotguns** — clip auto-refills on every shot
- **Infinite reserve for rifles/SMGs** — reload still needed, backpack never empty
- **42 maps** — official + custom (fy, aim, awp, rats, deathrun, knife arena)
- **Map voting** — `/rtv` rock-the-vote + `/de /cs /fy /aim /awp /rats /ka /dr` group votes
- **Admin menu** — `/admin` + chat shortcuts for kick/ban/slap/map/restart/bot
- **Live FX** — `/night`, `/day`, `/dusk`, `/dark`, `/grav`, `/speed`, `/ff`
- **Buy anywhere** + long buytime + alltalk + no friendly fire
- **VAC secured** + Steam authentication

## Stack

| Component | Version |
|---|---|
| HLDS | Build 10211 (Oct 2024) |
| ReGameDLL_CS | 5.28.0.756 |
| Metamod | 1.21.1-am |
| AMX Mod X | 1.10.0 build 5474 |
| ReChecker | 2.7 |
| Base image | `steamcmd/steamcmd:latest` |

## Quick Start

```bash
git clone https://github.com/marceloeatworld/cs16.git
cd cs16
cp env.example .env          # edit values as needed (RCON_PASSWORD, CF_*, TZ)
docker compose build
docker compose up -d
docker compose logs -f
```

Server starts on **UDP 27015**. Connect from CS 1.6: `connect YOUR_IP:27015`.

## RCON Password

**Nothing is hardcoded.** The container picks the password in this order:

1. `RCON_PASSWORD` environment variable (recommended — set it in Coolify or `.env`)
2. Otherwise a random 24-character password is generated at first start and printed once in the logs:

```
[entrypoint] No RCON_PASSWORD set -- generated: <RANDOM_24_CHARS>
```

Grab it with `docker compose logs cs16 | grep "generated"`. The `server.cfg` in Git never contains a real password.

## Project Structure

```
.
├── Dockerfile               # SteamCMD + ReGameDLL + Metamod + AMX + plugin build
├── docker-compose.yml       # network_mode: host, env vars, volume mounts
├── entrypoint.sh            # Config sync + RCON password injection + hlds_run
├── admin-setup.sh           # Interactive admin-add helper
├── ai_commentator.py        # Optional Cloudflare Workers AI sidecar
├── configs/
│   ├── server.cfg           # Gameplay, rates, plugin cvars, bot rules
│   ├── game_init.cfg        # bot_enable 1 (read once at DLL init)
│   ├── plugins.ini          # AMX Mod X plugin load list
│   ├── users.ini            # Admin list (empty in Git — add yours)
│   ├── maps.ini              # Admin map menu
│   ├── mapcycle.txt         # Map rotation
│   ├── metamod-plugins.ini  # Metamod plugin load list
│   ├── scrollmsg.ini        # Rotating banner messages
│   ├── reunion.cfg          # Steam / non-Steam auth
│   └── BotProfile.db        # CZ bot profiles (funny names + weakened Expert)
├── scripting/               # Custom AMX Mod X plugins (.sma source)
│   ├── admin_menu.sma       # Admin + FX menus + chat shortcuts
│   ├── full_equip.sma       # Money, armor, HP, ammo refill
│   ├── weapon_limits.sma    # AWP limit, shield/auto-sniper ban, bot safety net
│   ├── fun_extras.sma       # /rtv, /help, welcome
│   ├── map_groups.sma       # Grouped map voting
│   └── ai_commentator.sma   # Game event feed for the AI sidecar
└── data/
    ├── maps/                # Drop custom .bsp + .nav + .wad here
    ├── models/              # Custom player/weapon models
    ├── gfx/                 # Custom env textures
    └── logs/                # Persistent server logs
```

## Player Commands

| Command | Description |
|---|---|
| `/help` | List all commands |
| `/rtv` | Rock the vote (60% threshold) |
| `/maps` | Show map groups |
| `/de /cs /fy /aim /awp /rats /ka /dr` | Start a 3-map vote in that group |
| `/nextmap` | Show next map |
| `/timeleft` | Show time remaining |

## Admin Commands

| Command | Description |
|---|---|
| `/admin` | Show all admin commands |
| `/kick` `/ban` `/slap` `/team` | Player management |
| `/map` `/votemap` | Change map / vote map |
| `/restrict` | Weapon restriction menu |
| `/restart` | Restart round |
| `/bot` | Bot settings menu (quota, add, kick, status) |
| `/info` | Server info |
| `/fx` | Server FX submenu |
| `/night` `/day` `/dusk` `/dark` | Instant map lighting change |
| `/grav` | Gravity preset menu |
| `/speed` | Movement speed preset menu |
| `/ff` | Toggle friendly fire |

## Bot Configuration

Bots are native CZ bots shipped with ReGameDLL. No custom bot plugin.

| Cvar | Value | Notes |
|---|---|---|
| `bot_enable` | `1` | **Must live in `game_init.cfg`** — read once at DLL init |
| `bot_quota` | `10` | Total slots filled by humans + bots |
| `bot_quota_mode` | `fill` | Bots get kicked as humans connect |
| `bot_difficulty` | `2` | 0 easy / 1 normal / 2 hard / 3 expert |
| `bot_join_after_player` | `0` | Bots join even at 0 humans |
| `bot_allow_snipers` | `0` | Blocks AWP, Scout, G3SG1, SG550 for bots at the buy AI |
| `bot_allow_shield` | `0` | Blocks tactical shield for bots (both T and CT) |

The `Expert` template in `BotProfile.db` is tuned down:
`Skill = 25`, `Aggression = 40`, `ReactionTime = 0.95`, `AttackDelay = 0.55`, `Difficulty = HARD`.
Bots still play smart but you can actually win duels.

Bots require a `.nav` file on every map they play. The Dockerfile pulls 20+ official `.nav` files from `phamvanhiepvn/cs` at build time.

## Weapons & Ammo

Handled by `full_equip.sma` on every `CurWeapon` event:

| Weapon class | Clip | Reserve |
|---|---|---|
| Pistols (Glock, USP, Deagle, P228, FiveSeven, Elite) | Infinite, no reload | — |
| Shotguns (M3, XM1014) | Infinite, no reload | — |
| Rifles (AK, M4A1, AUG, SG552, Famas, Galil) | Reload normally | 90, always full |
| SMGs (MP5, P90, UMP45, TMP, MAC10) | Reload normally | 120, always full |
| Snipers (Scout, AWP, G3SG1, SG550) | Reload normally | 30, always full |
| M249 | Reload normally | 200, always full |

**Banned:** tactical shield (everyone), G3SG1 + SG550 auto snipers (everyone), AWP / Scout / AUG / SG552 for bots only. Humans are limited to 3 AWPs per team.

## Adding Admins

Use the interactive script:
```bash
./admin-setup.sh
```

Or append to `configs/users.ini` by hand:
```
"STEAM_0:1:XXXXXXX" "" "abcdefghijklmnopqrstu" "ce"
```

## Adding Maps

Drop `.bsp` files into `data/maps/`. The entrypoint copies them into `cstrike/maps/` on every container start. Drop `.nav` (bot nav), `.wad` (textures), `.res` (resources) alongside if they exist.

For bots to play a custom map, the matching `.nav` file must be present — otherwise the bot buy/move system silently ignores that map.

## AI Commentator (optional)

Live game commentary through Cloudflare Workers AI (Gemma 4). Set `CF_ACCOUNT_ID` and `CF_API_TOKEN` (see `env.example`) and the Python sidecar starts automatically. Leave them blank to skip.

## Environment Variables

All runtime-configurable values live in `env.example`. Copy it to `.env` for local compose, or paste the values into Coolify's Environment Variables tab.

| Variable | Default | Purpose |
|---|---|---|
| `RCON_PASSWORD` | auto-generated 24-char | Remote admin console password |
| `CF_ACCOUNT_ID` | (unset) | Cloudflare account id for the AI commentator |
| `CF_API_TOKEN` | (unset) | Cloudflare Workers AI token |
| `TZ` | `Europe/Lisbon` | Container timezone (any tzdata name) |

## Coolify Deployment

1. Push this repo to Git.
2. Coolify -> New Resource -> Docker Compose.
3. Advanced -> enable **Preserve Repository During Deployment** (required so the bind mounts resolve — see `coollabsio/coolify#1996`).
4. Environment Variables tab -> paste values from `env.example`:
   - `RCON_PASSWORD` — strongly recommended
   - `CF_ACCOUNT_ID`, `CF_API_TOKEN` — optional, for the AI commentator
   - `TZ` — optional, defaults to Europe/Lisbon
5. Do **not** assign a domain. This is raw UDP, not HTTP.
6. Hetzner firewall -> allow inbound UDP 27015 + TCP 27015.
7. Deploy.

Configs are baked into the image as a fallback, so the server still starts if the mount is empty.

## Known Issues

- `GameConfig CRC mismatch` warnings on startup — harmless, AMX 1.10 falls back to its bundled signatures for HLDS 10211.
- `pluginmenu.amxx: Menus Front-End not loaded` — expected, the stock front-end is replaced by `admin_menu.amxx`.
- AZERTY keyboards: menu number keys may not reach the game reliably. Use the chat shortcuts (`/kick`, `/ban`, ...) which work on any layout.
- `mp_infinite_ammo 1` in ReGameDLL actually gives **infinite clip** on rifles (undocumented engine behavior). The server keeps it at `0` and `full_equip.sma` handles reserve refill instead.
- Bot weapon restrictions live in `server.cfg` via `bot_allow_*` cvars — Ham and fakemeta hooks run too late in the bot buy pipeline.

## License

Server configuration and custom plugins are released under the MIT License — see the file headers.
CS 1.6, HLDS, and related assets are property of Valve Corporation.
AMX Mod X is licensed under GPL v2. ReGameDLL_CS is licensed under GPL v3.
