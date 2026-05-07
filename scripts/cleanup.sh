#!/usr/bin/env bash
# Removes a claw-zettel installation from the server.
# Safe to pipe through bash: all reads use /dev/tty.
set -euo pipefail

BACKEND_DIR="/opt/claw-zettel-backend"
ZEROCLAW_BIN="${HOME}/.cargo/bin/zeroclaw"
ZEROCLAW_CONFIG_DIR="${HOME}/.zeroclaw"
DEFAULT_NOTES_PATH="/opt/zettelkasten"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[claw-zettel]${NC} $*"; }
warn()  { echo -e "${YELLOW}[claw-zettel]${NC} $*"; }
error() { echo -e "${RED}[claw-zettel]${NC} $*" >&2; exit 1; }

ask() {
  local _var="$1" _msg="$2" _default="${3:-}"
  if [[ -n "$_default" ]]; then
    printf "${BLUE}>>${NC} %s [%s]: " "$_msg" "$_default" >/dev/tty
  else
    printf "${BLUE}>>${NC} %s: " "$_msg" >/dev/tty
  fi
  local _val
  IFS= read -r _val </dev/tty
  [[ -z "$_val" ]] && _val="$_default"
  printf -v "$_var" '%s' "$_val"
}

ask_yn() {
  local _msg="$1" _default="${2:-y}"
  if [[ "$_default" == "y" ]]; then
    printf "${BLUE}>>${NC} %s (Y/n): " "$_msg" >/dev/tty
  else
    printf "${BLUE}>>${NC} %s (y/N): " "$_msg" >/dev/tty
  fi
  local _val
  IFS= read -r _val </dev/tty
  _val="${_val:-$_default}"
  [[ "$_val" =~ ^[Yy] ]]
}

echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │      claw-zettel  cleanup tool        │"
echo "  └──────────────────────────────────────┘"
echo ""
warn "This removes claw-zettel from this server. Notes are kept by default."
echo ""

ANYTHING_DONE=false

# ─────────────────────────────────────────────
#  nginx reverse proxy
# ─────────────────────────────────────────────
NGINX_DIR="$BACKEND_DIR/nginx"
if [[ -f "$NGINX_DIR/docker-compose.yml" ]]; then
  if ask_yn "Stop and remove nginx reverse proxy?"; then
    docker compose -f "$NGINX_DIR/docker-compose.yml" down --remove-orphans 2>/dev/null || true
    info "nginx removed."
    ANYTHING_DONE=true
  fi
  # Remove certbot renewal cron if present
  if crontab -l 2>/dev/null | grep -q certbot-renew; then
    crontab -l 2>/dev/null | grep -v certbot-renew | crontab - || true
    info "Certbot renewal cron removed."
  fi
fi

# ─────────────────────────────────────────────
#  Frontend containers
# ─────────────────────────────────────────────
if [[ -f "$BACKEND_DIR/apps/frontend/docker-compose.yml" ]]; then
  if ask_yn "Stop and remove frontend containers?"; then
    docker compose -f "$BACKEND_DIR/apps/frontend/docker-compose.yml" down --remove-orphans 2>/dev/null || true
    info "Frontend containers removed."
    ANYTHING_DONE=true
  fi
fi

# ─────────────────────────────────────────────
#  Backend containers
# ─────────────────────────────────────────────
if [[ -f "$BACKEND_DIR/apps/backend/docker-compose.yml" ]]; then
  if ask_yn "Stop and remove backend containers?"; then
    docker compose -f "$BACKEND_DIR/apps/backend/docker-compose.yml" down --remove-orphans 2>/dev/null || true
    info "Backend containers removed."
    ANYTHING_DONE=true
  fi
fi

# ─────────────────────────────────────────────
#  Docker images (optional — frees disk space)
# ─────────────────────────────────────────────
if ask_yn "Remove claw-zettel Docker images (frees disk space)?" "n"; then
  docker images --filter=reference='*claw-zettel*' -q | xargs -r docker rmi -f 2>/dev/null || true
  info "Docker images removed."
  ANYTHING_DONE=true
fi

# ─────────────────────────────────────────────
#  zeroclaw
# ─────────────────────────────────────────────
if [[ -f "$ZEROCLAW_BIN" ]]; then
  if ask_yn "Remove zeroclaw binary at $ZEROCLAW_BIN?"; then
    # Stop any running zeroclaw service first
    if command -v zeroclaw >/dev/null 2>&1; then
      zeroclaw service uninstall 2>/dev/null || true
    fi
    rm -f "$ZEROCLAW_BIN"
    info "zeroclaw binary removed."
    ANYTHING_DONE=true
  fi
fi

# Remove zeroclaw config
if [[ -d "$ZEROCLAW_CONFIG_DIR" ]]; then
  if ask_yn "Remove zeroclaw config at $ZEROCLAW_CONFIG_DIR?" "n"; then
    rm -rf "$ZEROCLAW_CONFIG_DIR"
    info "zeroclaw config removed."
    ANYTHING_DONE=true
  fi
fi

# ─────────────────────────────────────────────
#  Backend installation directory
# ─────────────────────────────────────────────
if [[ -d "$BACKEND_DIR" ]]; then
  if ask_yn "Remove backend installation at $BACKEND_DIR?"; then
    rm -rf "$BACKEND_DIR"
    info "Backend directory removed."
    ANYTHING_DONE=true
  fi
else
  info "Backend directory not found — skipping."
fi

# ─────────────────────────────────────────────
#  Notes directory (destructive — explicit confirmation required)
# ─────────────────────────────────────────────
ask NOTES_PATH "Notes directory path" "$DEFAULT_NOTES_PATH"

if [[ -d "$NOTES_PATH" ]]; then
  echo ""
  warn "WARNING: deleting $NOTES_PATH will permanently erase your notes."
  if ask_yn "Delete the notes directory?" "n"; then
    printf "${RED}>>${NC} Type DELETE to confirm: " >/dev/tty
    local_confirm=""
    IFS= read -r local_confirm </dev/tty
    if [[ "$local_confirm" == "DELETE" ]]; then
      rm -rf "$NOTES_PATH"
      info "Notes directory removed."
      ANYTHING_DONE=true
    else
      info "Confirmation not matched — notes kept."
    fi
  fi
else
  info "Notes directory not found — skipping."
fi

# ─────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────
echo ""
if [[ "$ANYTHING_DONE" == "true" ]]; then
  info "Cleanup complete. Run install.sh to start fresh."
else
  info "Nothing was removed."
fi
echo ""
