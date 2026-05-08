#!/usr/bin/env bash
# Updates claw-zettel backend on the server:
# pulls the latest code and rebuilds/restarts the Docker container.
# .env is preserved — no settings are changed.
set -euo pipefail

BACKEND_DIR="/opt/claw-zettel-backend"
COMPOSE_FILE="$BACKEND_DIR/apps/backend/docker-compose.yml"
ENV_FILE="$BACKEND_DIR/apps/backend/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[claw-zettel]${NC} $*"; }
warn()  { echo -e "${YELLOW}[claw-zettel]${NC} $*"; }
error() { echo -e "${RED}[claw-zettel]${NC} $*" >&2; exit 1; }

# ─────────────────────────────────────────────
#  Checks
# ─────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || error "Docker not found."
command -v git    >/dev/null 2>&1 || error "Git not found."

[[ -d "$BACKEND_DIR/.git" ]] || error "Backend not installed at $BACKEND_DIR. Run install.sh first."
[[ -f "$COMPOSE_FILE" ]]     || error "docker-compose.yml not found at $COMPOSE_FILE"

echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │    claw-zettel  backend updater       │"
echo "  └──────────────────────────────────────┘"
echo ""

# ─────────────────────────────────────────────
#  Show current version
# ─────────────────────────────────────────────
CURRENT_COMMIT="$(git -C "$BACKEND_DIR" rev-parse --short HEAD)"
info "Current commit: $CURRENT_COMMIT"

# ─────────────────────────────────────────────
#  Pull latest code
# ─────────────────────────────────────────────
info "Pulling latest code…"
git -C "$BACKEND_DIR" fetch origin

LOCAL="$(git -C "$BACKEND_DIR" rev-parse HEAD)"
REMOTE="$(git -C "$BACKEND_DIR" rev-parse @{u} 2>/dev/null || echo '')"

if [[ -n "$REMOTE" && "$LOCAL" == "$REMOTE" ]]; then
  warn "Already up to date ($(git -C "$BACKEND_DIR" rev-parse --short HEAD))."
  warn "Pass --force to rebuild the image anyway."
  if [[ "${1:-}" != "--force" ]]; then
    echo ""
    exit 0
  fi
fi

git -C "$BACKEND_DIR" pull --ff-only
NEW_COMMIT="$(git -C "$BACKEND_DIR" rev-parse --short HEAD)"
info "Updated to: $NEW_COMMIT"

# ─────────────────────────────────────────────
#  Rebuild and restart container
# ─────────────────────────────────────────────
info "Rebuilding Docker image…"

ENV_ARGS=""
[[ -f "$ENV_FILE" ]] && ENV_ARGS="--env-file $ENV_FILE"

# shellcheck disable=SC2086
docker compose -f "$COMPOSE_FILE" $ENV_ARGS \
  up -d --build --remove-orphans

# ─────────────────────────────────────────────
#  Remove dangling images left by the rebuild
# ─────────────────────────────────────────────
docker image prune -f --filter "dangling=true" >/dev/null 2>&1 || true

# ─────────────────────────────────────────────
#  Health check
# ─────────────────────────────────────────────
PORT="${PORT:-}"
if [[ -z "$PORT" && -f "$ENV_FILE" ]]; then
  PORT="$(grep -E '^PORT=' "$ENV_FILE" | cut -d= -f2 | tr -d '[:space:]' || echo '')"
fi
PORT="${PORT:-3001}"

info "Waiting for backend to respond on port $PORT…"
for i in $(seq 1 15); do
  if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    info "Backend is up."
    break
  fi
  if [[ "$i" -eq 15 ]]; then
    warn "Health check did not pass after 15 s — check logs:"
    warn "  docker compose -f $COMPOSE_FILE logs --tail=50"
  fi
  sleep 1
done

# ─────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────
echo ""
info "Update complete. $CURRENT_COMMIT → $NEW_COMMIT"
echo ""
