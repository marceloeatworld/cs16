#!/bin/bash
# CS 1.6 container entrypoint.
# Picks configs from mount (compose) or baked-in (Coolify fallback), injects
# the RCON password, then execs hlds_run.
set -e

cd /hlds

if [ -d /hlds/custom_configs ] && [ -n "$(ls -A /hlds/custom_configs 2>/dev/null)" ]; then
    CONFIG_SRC=/hlds/custom_configs
    echo "[entrypoint] Using mounted configs from $CONFIG_SRC"
elif [ -d /hlds/custom_configs_baked ]; then
    CONFIG_SRC=/hlds/custom_configs_baked
    echo "[entrypoint] Using baked-in configs (mount empty)"
else
    CONFIG_SRC=""
    echo "[entrypoint] WARNING: no config source found, using image defaults"
fi

if [ -n "$CONFIG_SRC" ]; then
    copy_if_exists() { [ -f "$1" ] && cp -f "$1" "$2"; }

    copy_if_exists "$CONFIG_SRC/server.cfg"          /hlds/cstrike/server.cfg
    copy_if_exists "$CONFIG_SRC/game_init.cfg"       /hlds/cstrike/game_init.cfg
    copy_if_exists "$CONFIG_SRC/mapcycle.txt"        /hlds/cstrike/mapcycle.txt
    copy_if_exists "$CONFIG_SRC/users.ini"           /hlds/cstrike/addons/amxmodx/configs/users.ini
    copy_if_exists "$CONFIG_SRC/plugins.ini"         /hlds/cstrike/addons/amxmodx/configs/plugins.ini
    copy_if_exists "$CONFIG_SRC/maps.ini"            /hlds/cstrike/addons/amxmodx/configs/maps.ini
    copy_if_exists "$CONFIG_SRC/scrollmsg.ini"       /hlds/cstrike/addons/amxmodx/configs/scrollmsg.ini
    copy_if_exists "$CONFIG_SRC/metamod-plugins.ini" /hlds/cstrike/addons/metamod/plugins.ini
    copy_if_exists "$CONFIG_SRC/reunion.cfg"         /hlds/cstrike/reunion.cfg

    echo "[entrypoint] Configs synced"
fi

# --- Env-based admin injection ---
# ADMINS="STEAM_0:1:123,STEAM_0:0:456" → append full-owner lines to users.ini.
if [ -n "${ADMINS:-}" ]; then
    USERS_INI=/hlds/cstrike/addons/amxmodx/configs/users.ini
    mkdir -p "$(dirname "$USERS_INI")"
    touch "$USERS_INI"
    if [ -s "$USERS_INI" ] && [ "$(tail -c1 "$USERS_INI" | wc -l)" -eq 0 ]; then
        printf '\n' >> "$USERS_INI"
    fi
    added=0
    IFS=','
    for sid in $ADMINS; do
        sid=$(printf '%s' "$sid" | tr -d '[:space:]')
        [ -z "$sid" ] && continue
        if ! printf '%s' "$sid" | grep -qE '^STEAM_[0-9]:[01]:[0-9]+$'; then
            echo "[entrypoint]   skip invalid SteamID: $sid"
            continue
        fi
        if grep -qF "\"$sid\"" "$USERS_INI"; then
            echo "[entrypoint]   already present: $sid"
            continue
        fi
        printf '"%s" "" "abcdefghijklmnopqrstu" "ce"\n' "$sid" >> "$USERS_INI"
        echo "[entrypoint]   + $sid"
        added=$((added+1))
    done
    unset IFS
    echo "[entrypoint] admins injected from \$ADMINS: $added"
fi

# Inject RCON password: env var wins, otherwise generate a random one.
if [ -z "${RCON_PASSWORD:-}" ]; then
    RCON_PASSWORD=$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
    echo "[entrypoint] No RCON_PASSWORD set — generated: $RCON_PASSWORD"
else
    echo "[entrypoint] Using RCON_PASSWORD from environment"
fi
# Escape forward slashes for sed just in case the random/env value contains one.
ESCAPED=$(printf '%s' "$RCON_PASSWORD" | sed -e 's/[\/&]/\\&/g')
sed -i "s/__SET_AT_RUNTIME__/$ESCAPED/" /hlds/cstrike/server.cfg

# --- Custom maps drop zone ---
MAPS_DROP=/hlds/custom_maps_drop
if [ -d "$MAPS_DROP" ]; then
    bsp_count=$(find "$MAPS_DROP" -maxdepth 1 -type f -name "*.bsp" 2>/dev/null | wc -l)
    if [ "$bsp_count" -gt 0 ]; then
        echo "[entrypoint] Copying $bsp_count custom map file(s)..."
        cp -f "$MAPS_DROP"/*.bsp /hlds/cstrike/maps/ 2>/dev/null || true
        cp -f "$MAPS_DROP"/*.nav /hlds/cstrike/maps/ 2>/dev/null || true
        cp -f "$MAPS_DROP"/*.res /hlds/cstrike/maps/ 2>/dev/null || true
        cp -f "$MAPS_DROP"/*.txt /hlds/cstrike/maps/ 2>/dev/null || true
        cp -f "$MAPS_DROP"/*.wad /hlds/cstrike/        2>/dev/null || true
    fi
fi

# --- Custom models + gfx ---
MODELS_DROP=/hlds/custom_models_drop
if [ -d "$MODELS_DROP" ] && [ -n "$(ls -A "$MODELS_DROP" 2>/dev/null)" ]; then
    echo "[entrypoint] Copying custom models..."
    cp -rf "$MODELS_DROP"/* /hlds/cstrike/models/ 2>/dev/null || true
fi

GFX_DROP=/hlds/custom_gfx_drop
if [ -d "$GFX_DROP" ] && [ -n "$(ls -A "$GFX_DROP" 2>/dev/null)" ]; then
    echo "[entrypoint] Copying custom gfx..."
    cp -rf "$GFX_DROP"/* /hlds/cstrike/gfx/ 2>/dev/null || true
fi

# --- AI Commentator sidecar (runs in background) ---
if [ -f /hlds/ai_commentator.py ] && [ -n "$CF_ACCOUNT_ID" ] && [ -n "$CF_API_TOKEN" ]; then
    echo "[entrypoint] Starting AI Commentator sidecar..."
    python3 /hlds/ai_commentator.py &
elif [ -f /hlds/ai_commentator.py ]; then
    echo "[entrypoint] AI Commentator: CF_ACCOUNT_ID / CF_API_TOKEN not set, skipping."
fi

exec "$@"
