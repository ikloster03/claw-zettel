#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/ikloster03/claw-zettel"
BACKEND_DIR="/opt/claw-zettel-backend"
SERVICE_NAME="claw-zettel"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[claw-zettel]${NC} $*"; }
warn()  { echo -e "${YELLOW}[claw-zettel]${NC} $*"; }
error() { echo -e "${RED}[claw-zettel]${NC} $*" >&2; exit 1; }

# --- Check dependencies ---
command -v docker >/dev/null 2>&1 || error "Docker is not installed. Install it first: https://docs.docker.com/engine/install/"
command -v git    >/dev/null 2>&1 || error "Git is not installed."

# --- Collect configuration ---
echo ""
echo "  claw-zettel backend installer"
echo "  =============================="
echo ""

read -rp "  Server password (used to connect from frontend): " PASSWORD
[[ -z "$PASSWORD" ]] && error "Password cannot be empty"

read -rp "  Port [3001]: " PORT
PORT="${PORT:-3001}"

read -rp "  Path to your Zettelkasten git repo [/opt/zettelkasten]: " NOTES_PATH
NOTES_PATH="${NOTES_PATH:-/opt/zettelkasten}"

read -rp "  Git remote URL for auto-push (leave blank to skip push): " GIT_REMOTE

read -rp "  nanoclaw URL [http://localhost:4000]: " NANOCLAW_URL
NANOCLAW_URL="${NANOCLAW_URL:-http://localhost:4000}"

JWT_SECRET="$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64)"

# --- Set up notes repo ---
if [[ ! -d "$NOTES_PATH/.git" ]]; then
  info "Initializing new git repo at $NOTES_PATH"
  mkdir -p "$NOTES_PATH"
  git -C "$NOTES_PATH" init
  if [[ -n "$GIT_REMOTE" ]]; then
    git -C "$NOTES_PATH" remote add origin "$GIT_REMOTE"
  fi
fi

# --- Clone / update backend ---
if [[ -d "$BACKEND_DIR/.git" ]]; then
  info "Updating existing installation at $BACKEND_DIR"
  git -C "$BACKEND_DIR" pull --ff-only
else
  info "Cloning backend to $BACKEND_DIR"
  git clone --depth 1 "$REPO" "$BACKEND_DIR"
fi

# --- Write .env ---
cat > "$BACKEND_DIR/apps/backend/.env" <<EOF
PORT=${PORT}
PASSWORD=${PASSWORD}
JWT_SECRET=${JWT_SECRET}
NOTES_REPO_PATH=${NOTES_PATH}
GIT_REMOTE_URL=${GIT_REMOTE}
GIT_USER_NAME=nanoclaw
GIT_USER_EMAIL=nanoclaw@claw-zettel
NANOCLAW_BASE_URL=${NANOCLAW_URL}
DB_PATH=/app/data/data.sqlite
EOF

# --- Update docker-compose with env file ---
mkdir -p "$BACKEND_DIR/data"

# --- Start with Docker Compose ---
info "Starting backend with Docker Compose…"
docker compose -f "$BACKEND_DIR/apps/backend/docker-compose.yml" \
  --env-file "$BACKEND_DIR/apps/backend/.env" \
  up -d --build

echo ""
info "Installation complete!"
echo ""
echo "  Backend is running at: http://$(hostname -I | awk '{print $1}'):${PORT}"
echo "  Connect your frontend to this URL and use the password you set."
echo ""
warn "Keep your .env file safe — it contains your JWT secret."
