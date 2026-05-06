#!/usr/bin/env bash
# Starts frontend + backend in local/mock mode for testing without a real clawzettel server.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/apps/backend"
FRONTEND="$ROOT/apps/frontend"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[local]${NC} $*"; }

info "Starting claw-zettel in local mode"
info "  Backend  → http://localhost:3001  (password: local)"
info "  Frontend → http://localhost:5173"
echo ""

# Trap Ctrl-C and kill all child processes
cleanup() {
  echo ""
  info "Shutting down…"
  kill 0
}
trap cleanup INT TERM

# Start backend with .env.local
cd "$BACKEND"
bun --env-file .env.local --watch src/index.ts &
BACKEND_PID=$!

# Give backend a moment to start
sleep 1

# Start frontend
cd "$FRONTEND"
bun run dev &
FRONTEND_PID=$!

info "Both services started. Press Ctrl-C to stop."
wait
