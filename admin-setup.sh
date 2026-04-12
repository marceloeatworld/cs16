#!/usr/bin/env bash
# ==========================================================
# CS 1.6 - Interactive AMX Mod X admin add script
# ==========================================================
# Usage: ./admin-setup.sh
# - Prompts for auth method (nick+pw / SteamID / IP)
# - Prompts for access level
# - Appends a line to configs/users.ini
# - Offers to restart the container to apply

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERS_INI="${SCRIPT_DIR}/configs/users.ini"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

err()  { printf '%sERROR:%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
ok()   { printf '%sOK%s %s\n' "$GREEN" "$NC" "$*"; }
info() { printf '%s>%s %s\n' "$BLUE" "$NC" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$NC" "$*"; }

[[ -f "$USERS_INI" ]] || err "users.ini not found: $USERS_INI"

echo
printf '%s==================================================%s\n' "${BOLD}${BLUE}" "$NC"
printf '%s  CS 1.6 - Add AMX Mod X admin%s\n' "${BOLD}${BLUE}" "$NC"
printf '%s==================================================%s\n' "${BOLD}${BLUE}" "$NC"
echo

# --- Currently configured admins ---
info "Admins currently configured in users.ini:"
current=$(grep -vE '^\s*(;|$)' "$USERS_INI" 2>/dev/null || true)
if [[ -z "$current" ]]; then
  echo "  (none)"
else
  printf '%s\n' "$current" | sed 's/^/  /'
fi
echo

# --- Authentication method ---
printf '%sAuthentication method:%s\n' "$BOLD" "$NC"
echo "  1) Nickname + password  (non-steam, easiest for testing)"
echo "  2) SteamID              (Steam player)"
echo "  3) Fixed IP address"
read -rp "Choice [1-3]: " auth_method

case "$auth_method" in
  1)
    read -rp "In-game nickname: " nick
    [[ -n "${nick// }" ]] || err "Empty nickname"
    read -rsp "Password (min 4 chars): " pass
    echo
    [[ ${#pass} -ge 4 ]] || err "Password too short"
    ident="$nick"
    auth_flags="c"
    ;;
  2)
    read -rp "SteamID (e.g. STEAM_0:1:12345678): " steamid
    [[ "$steamid" =~ ^STEAM_[0-9]:[01]:[0-9]+$ ]] || err "Invalid SteamID format"
    ident="$steamid"
    pass=""
    auth_flags="e"
    ;;
  3)
    read -rp "IP address: " ipaddr
    [[ "$ipaddr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || err "Invalid IP format"
    ident="$ipaddr"
    pass=""
    auth_flags="d"
    ;;
  *)
    err "Invalid choice"
    ;;
esac

# --- Duplicate check ---
if grep -qF "\"$ident\"" "$USERS_INI"; then
  warn "An admin with identifier '$ident' already exists."
  read -rp "Add a new line anyway? [y/N] " dup
  [[ "${dup,,}" == "y" ]] || { info "Cancelled"; exit 0; }
fi

# --- Access level ---
echo
printf '%sAccess level:%s\n' "$BOLD" "$NC"
echo "  1) Owner       full admin + rcon        [abcdefghijklmnopqrstu]"
echo "  2) Admin       ban/kick/map/vote/menu   [abcdefijmnu]"
echo "  3) Moderator   kick/slay/chat/menu      [aceiju]"
echo "  4) Custom      (you pick the flags)"
read -rp "Choice [1-4]: " level

case "$level" in
  1) access_flags="abcdefghijklmnopqrstu" ;;
  2) access_flags="abcdefijmnu" ;;
  3) access_flags="aceiju" ;;
  4)
    read -rp "Access flags (combination of a-u): " access_flags
    [[ -n "$access_flags" ]] || err "Empty flags"
    ;;
  *)
    err "Invalid choice"
    ;;
esac

# --- Build line ---
ident_clean="${ident//\"/}"
pass_clean="${pass//\"/}"
line="\"${ident_clean}\" \"${pass_clean}\" \"${access_flags}\" \"${auth_flags}\""

if [[ -n "$pass_clean" ]]; then
  display_line="\"${ident_clean}\" \"***\" \"${access_flags}\" \"${auth_flags}\""
else
  display_line="$line"
fi

echo
info "Line to be added:"
echo "  $display_line"
echo
read -rp "Confirm add? [y/N] " confirm
[[ "${confirm,,}" == "y" ]] || { warn "Cancelled"; exit 0; }

# --- Write ---
# Ensure trailing newline before appending
if [[ -s "$USERS_INI" ]] && [[ "$(tail -c1 "$USERS_INI" | xxd -p)" != "0a" ]]; then
  printf '\n' >> "$USERS_INI"
fi
printf '%s\n' "$line" >> "$USERS_INI"
ok "Admin added to $USERS_INI"

# --- Post-setup instructions for nick+password ---
if [[ "$auth_method" == "1" ]]; then
  echo
  printf '%sIMPORTANT%s - In the CS console (~ key), type ONCE:\n' "$YELLOW" "$NC"
  printf '  %ssetinfo _pw %s%s\n' "$BOLD" "$pass" "$NC"
  printf 'Then connect using nickname: %s%s%s\n' "$BOLD" "$nick" "$NC"
fi

# --- Restart ---
echo
if [[ -f "$COMPOSE_FILE" ]] && command -v docker >/dev/null 2>&1; then
  read -rp "Restart CS 1.6 container to apply? [y/N] " restart
  if [[ "${restart,,}" == "y" ]]; then
    if (cd "$SCRIPT_DIR" && docker compose restart cs16 2>/dev/null); then
      ok "Container restarted. Join the server and type 'amx_menu' in console."
    else
      warn "Restart failed (container not created yet?). Run first: docker compose up -d"
    fi
  else
    info "To apply later: cd $SCRIPT_DIR && docker compose restart cs16"
  fi
else
  info "Docker not detected. Apply manually with: docker compose restart cs16"
fi

echo
ok "Done."
