# syntax=docker/dockerfile:1
# Self-contained build: every third-party binary lives in vendor/ inside
# this repo, so the Docker build only hits the network for SteamCMD
# (the Valve HLDS base game files, app 90).
FROM steamcmd/steamcmd:latest

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unzip ca-certificates tar gzip \
    && rm -rf /var/lib/apt/lists/*

# HLDS base (CS 1.6, appid 90). SteamCMD + app 90 is flaky, so we retry.
RUN set -eux; \
    for i in 1 2 3; do \
        steamcmd \
            +api_logging 1 1 \
            +force_install_dir /hlds \
            +login anonymous \
            +app_set_config 90 mod cstrike \
            +app_update 90 validate \
            +quit || true; \
    done; \
    test -f /hlds/hlds_run; \
    test -d /hlds/cstrike/dlls

WORKDIR /hlds

# Copy the entire vendor tree into /tmp, unpack in order, then drop /tmp.
COPY vendor/ /tmp/vendor/

# ReGameDLL_CS 5.28.0.756 — modernized CS game DLL.
# ReHLDS is NOT installed: 3.14 needs a newer libsteam_api.so than Valve HLDS
# ships, which crashes at startup with undefined symbol SteamGameServer_Init.
RUN set -eux; \
    unzip -oq /tmp/vendor/archives/regamedll-5.28.0.756.zip -d /tmp/regamedll; \
    cp -rf /tmp/regamedll/bin/linux32/cstrike/. /hlds/cstrike/; \
    test -f /hlds/cstrike/dlls/cs.so; \
    rm -rf /tmp/regamedll

# Metamod 1.21.1-am (officially paired with AMX Mod X 1.10).
RUN set -eux; \
    unzip -oq /tmp/vendor/archives/metamod-1.21.1-am.zip -d /hlds/cstrike/; \
    test -f /hlds/cstrike/addons/metamod/dlls/metamod.so; \
    sed -i -e 's|^gamedll_linux .*|gamedll_linux "addons/metamod/dlls/metamod.so"|' \
        /hlds/cstrike/liblist.gam

# AMX Mod X 1.10.0 build 5474 (HL25-compatible).
# Fixes alliedmodders/amxmodx#1086: segfault on HLDS build 10211+.
RUN set -eux; \
    tar -xzf /tmp/vendor/archives/amxmodx-1.10.0-git5474-base-linux.tar.gz -C /hlds/cstrike/; \
    tar -xzf /tmp/vendor/archives/amxmodx-1.10.0-git5474-cstrike-linux.tar.gz -C /hlds/cstrike/; \
    test -f /hlds/cstrike/addons/amxmodx/dlls/amxmodx_mm_i386.so; \
    test -f /hlds/cstrike/addons/amxmodx/scripting/amxxpc

# ReAPI module for AMX plugins using the ReGameDLL hook chain API.
COPY configs/addons_reapi/reapi_amxx_i386.so /hlds/cstrike/addons/amxmodx/modules/reapi_amxx_i386.so

# Compile our custom .sma plugins with amxxpc.
COPY scripting/ /hlds/cstrike/addons/amxmodx/scripting/custom/
RUN set -eux; \
    cd /hlds/cstrike/addons/amxmodx/scripting; \
    chmod +x amxxpc compile.sh 2>/dev/null || true; \
    for sma in custom/*.sma; do \
        name=$(basename "$sma" .sma); \
        echo "Compiling $sma..."; \
        ./amxxpc "$sma" -o"../plugins/${name}.amxx" || ./amxxpc "$sma"; \
        [ -f "${name}.amxx" ] && mv "${name}.amxx" "../plugins/${name}.amxx" || true; \
        test -f "../plugins/${name}.amxx" || (echo "FAILED to compile $sma" && exit 1); \
    done

# Reunion 0.2.0.25: mixed Steam + non-Steam authentication.
RUN set -eux; \
    unzip -oq /tmp/vendor/archives/reunion-0.2.0.25.zip -d /tmp/reunion; \
    mkdir -p /hlds/cstrike/addons/reunion; \
    find /tmp/reunion -name "reunion_mm_i386.so" -exec cp {} /hlds/cstrike/addons/reunion/reunion_mm_i386.so \; ; \
    find /tmp/reunion -name "reunion.cfg"         -exec cp {} /hlds/cstrike/reunion.cfg \; ; \
    rm -rf /tmp/reunion

# ReChecker 2.7: basic client file integrity check (anti-cheat).
RUN set -eux; \
    unzip -oq /tmp/vendor/archives/rechecker-2.7.zip -d /tmp/rechecker; \
    mkdir -p /hlds/cstrike/addons/rechecker; \
    find /tmp/rechecker -name "rechecker_mm_i386.so" -exec cp {} /hlds/cstrike/addons/rechecker/rechecker_mm_i386.so \; ; \
    find /tmp/rechecker -name "resources.ini"        -exec cp {} /hlds/cstrike/addons/rechecker/resources.ini \; 2>/dev/null || true; \
    rm -rf /tmp/rechecker

# Persistent directories + drop zones for bind mounts.
RUN mkdir -p /hlds/cstrike/logs /hlds/cstrike/maps /hlds/custom_maps_drop /hlds/custom_configs

# WADs used by custom maps. de_vegas.wad is real (needed by fy_iceworld for
# texture lv_marble); the rest are dummy 12-byte stubs (maps embed their
# textures, the engine just needs the file to exist so it doesn't refuse
# to load the map).
RUN set -eux; \
    cp /tmp/vendor/wads/de_vegas.wad /hlds/cstrike/de_vegas.wad; \
    for wad in dsds india awp_india awp_fpsproject cs_office_btm \
        sveney_christmas_btm nocredit de_celtic ratsnew swat3tex1a-g \
        doombank2 de_highschool cs_bbicotka cs_bikini cs_estate \
        de_rats_caravan pldecal rats2k4; do \
        printf '\x57\x41\x44\x33\x00\x00\x00\x00\x0c\x00\x00\x00' > "/hlds/cstrike/${wad}.wad"; \
    done; \
    printf '\x57\x41\x44\x33\x00\x00\x00\x00\x0c\x00\x00\x00' > "/hlds/cstrike/MaxPayne - Texes.wad"

# BotProfile.db: required for CZ bots to spawn (bot_add / bot_quota).
COPY configs/BotProfile.db /hlds/cstrike/BotProfile.db

# game_init.cfg fallback. ReGameDLL reads bot_enable ONCE at DLL init from
# this file; setting it in server.cfg is too late.
RUN printf '// Read once at game DLL init -- do not move to server.cfg\nbot_enable 1\n' \
    > /hlds/cstrike/game_init.cfg

# Bot navigation meshes + custom map .bsp files from vendor/.
# HLDS (app 90) ships zero .nav files; without them LoadNavigationMap()
# fails and bot_add / bot_quota silently do nothing.
RUN set -eux; \
    cp -f /tmp/vendor/nav/*.nav   /hlds/cstrike/maps/; \
    cp -f /tmp/vendor/maps/*.bsp  /hlds/cstrike/maps/; \
    echo "[vendor] .nav files:  $(ls -1 /hlds/cstrike/maps/*.nav 2>/dev/null | wc -l)"; \
    echo "[vendor] .bsp custom: $(ls -1 /hlds/cstrike/maps/fy_*.bsp /hlds/cstrike/maps/aim_*.bsp \
                                    /hlds/cstrike/maps/awp_*.bsp /hlds/cstrike/maps/de_rats*.bsp \
                                    /hlds/cstrike/maps/35hp*.bsp 2>/dev/null | wc -l)"

# Bake configs as fallback defaults for when the bind mount is empty
# (Coolify with "Preserve Repository During Deployment" disabled).
COPY configs/ /hlds/custom_configs_baked/

# Clean up the vendor staging area.
RUN rm -rf /tmp/vendor

# AI Commentator sidecar (runs as a Python sidecar process in entrypoint).
COPY ai_commentator.py /hlds/ai_commentator.py

# Entrypoint: copies configs and maps from drop zones, injects RCON password,
# then execs hlds_run.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 27015/udp 27015/tcp

WORKDIR /hlds
ENTRYPOINT ["/entrypoint.sh"]
CMD ["./hlds_run", \
     "-game", "cstrike", \
     "+ip", "0.0.0.0", \
     "+port", "27015", \
     "+maxplayers", "32", \
     "+map", "de_dust2", \
     "-pingboost", "3", \
     "+sys_ticrate", "1000"]
