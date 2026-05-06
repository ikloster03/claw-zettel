#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/ikloster03/claw-zettel"
NANOCLAW_REPO="https://github.com/qwibitai/nanoclaw"
BACKEND_DIR="/opt/claw-zettel-backend"
NANOCLAW_DIR="/opt/nanoclaw"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${GREEN}[claw-zettel]${NC} $*"; }
warn()    { echo -e "${YELLOW}[claw-zettel]${NC} $*"; }
error()   { echo -e "${RED}[claw-zettel]${NC} $*" >&2; exit 1; }
step()    { echo ""; echo "  $*"; echo ""; }

# All reads use /dev/tty so the script works when piped: curl ... | bash
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

ask_secret() {
  local _var="$1" _msg="$2"
  printf "${BLUE}>>${NC} %s: " "$_msg" >/dev/tty
  local _val
  IFS= read -rs _val </dev/tty
  echo >/dev/tty
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

gen_password() {
  openssl rand -base64 16 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 20 ||
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 20
}

gen_secret() {
  openssl rand -hex 32 2>/dev/null ||
    tr -dc 'a-f0-9' </dev/urandom | head -c 64
}

# ─────────────────────────────────────────────
#  Dependency check
# ─────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || error "Docker not installed: https://docs.docker.com/engine/install/"
command -v git    >/dev/null 2>&1 || error "Git is not installed."

echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │     claw-zettel  backend installer    │"
echo "  └──────────────────────────────────────┘"
echo ""

# ─────────────────────────────────────────────
#  Step 1: Notes repository
# ─────────────────────────────────────────────
step "[1/6] Notes repository"

GIT_REMOTE="" GIT_USER="" GIT_TOKEN=""

if ask_yn "Do you have a remote git repo for your notes?" "n"; then
  ask GIT_REMOTE "Remote URL (e.g. https://github.com/you/notes.git)"
  [[ -z "$GIT_REMOTE" ]] && error "Remote URL cannot be empty."
  ask GIT_USER "Git username"
  ask_secret GIT_TOKEN "Git token / password (leave blank to skip push auth)"
else
  info "A local-only repo will be created."
fi

ask NOTES_PATH "Local notes path" "/opt/zettelkasten"

# ─────────────────────────────────────────────
#  Step 2: Server password
# ─────────────────────────────────────────────
step "[2/6] Server password"

ask_secret PASSWORD "Password (press Enter to auto-generate)"

GENERATED_PASSWORD=false
if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(gen_password)"
  GENERATED_PASSWORD=true
  info "Password auto-generated — will be shown at the end."
fi

# ─────────────────────────────────────────────
#  Step 3: Ports
# ─────────────────────────────────────────────
step "[3/6] Ports"
ask BACKEND_PORT "Backend port" "3001"

# ─────────────────────────────────────────────
#  Step 4: Frontend (optional)
# ─────────────────────────────────────────────
step "[4/6] Frontend (clawzettel UI)"

INSTALL_FRONTEND=false
FRONTEND_PORT="3000"

if ask_yn "Install the frontend UI?" "y"; then
  INSTALL_FRONTEND=true
  ask FRONTEND_PORT "Frontend port" "3000"
fi

# ─────────────────────────────────────────────
#  Step 5: Domain + SSL
# ─────────────────────────────────────────────
step "[5/6] Domain & SSL"

DOMAIN="" USE_SSL=false SSL_TYPE="letsencrypt"
LE_EMAIL="" CERT_FILE="" KEY_FILE=""

if ask_yn "Do you have a domain pointing to this server?" "n"; then
  ask DOMAIN "Domain name (e.g. notes.example.com)"
  [[ -z "$DOMAIN" ]] && error "Domain cannot be empty."
  USE_SSL=true

  echo ""
  echo "    SSL options:"
  echo "    1) Let's Encrypt — free, auto-renewing (recommended)"
  echo "    2) Custom certificate — you provide .crt and .key files"
  echo ""
  ask SSL_CHOICE "Choice" "1"

  if [[ "$SSL_CHOICE" == "2" ]]; then
    SSL_TYPE="custom"
    ask CERT_FILE "Path to certificate file (.crt / .pem)"
    [[ ! -f "$CERT_FILE" ]] && error "Certificate file not found: $CERT_FILE"
    ask KEY_FILE "Path to private key (.key)"
    [[ ! -f "$KEY_FILE" ]] && error "Key file not found: $KEY_FILE"
  else
    SSL_TYPE="letsencrypt"
    ask LE_EMAIL "Email for Let's Encrypt expiry notices"
    [[ -z "$LE_EMAIL" ]] && error "Email is required for Let's Encrypt."
    warn "Ensure ports 80 and 443 are open and $DOMAIN points to this server's IP."
  fi
fi

# ─────────────────────────────────────────────
#  Step 6: nanoclaw AI agent (optional)
# ─────────────────────────────────────────────
step "[6/6] nanoclaw AI agent"

INSTALL_NANOCLAW=false
NANOCLAW_API_KEY=""
NANOCLAW_TRIGGER="@Andy"

echo "    nanoclaw is an AI assistant that runs Claude Code agents in isolated"
echo "    containers. It will be restricted to your zettelkasten notes and its"
echo "    own config files — nothing else on the server."
echo ""

if ask_yn "Install nanoclaw AI agent?" "n"; then
  INSTALL_NANOCLAW=true
  ask_secret NANOCLAW_API_KEY "Anthropic API key (console.anthropic.com)"
  [[ -z "$NANOCLAW_API_KEY" ]] && error "Anthropic API key is required for nanoclaw."
  ask NANOCLAW_TRIGGER "Agent trigger word" "@Andy"
fi

# ─────────────────────────────────────────────
#  Derived values
# ─────────────────────────────────────────────
JWT_SECRET="$(gen_secret)"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)"

if [[ "$USE_SSL" == "true" ]]; then
  if [[ "$INSTALL_FRONTEND" == "true" ]]; then
    BACKEND_PUBLIC_URL="https://${DOMAIN}/api"
    FRONTEND_PUBLIC_URL="https://${DOMAIN}"
  else
    BACKEND_PUBLIC_URL="https://${DOMAIN}"
    FRONTEND_PUBLIC_URL=""
  fi
else
  BACKEND_PUBLIC_URL="http://${SERVER_IP}:${BACKEND_PORT}"
  FRONTEND_PUBLIC_URL="http://${SERVER_IP}:${FRONTEND_PORT}"
fi

# ─────────────────────────────────────────────
#  Set up notes repo
# ─────────────────────────────────────────────
if [[ ! -d "$NOTES_PATH/.git" ]]; then
  info "Initialising notes repo at $NOTES_PATH"
  mkdir -p "$NOTES_PATH"
  git -C "$NOTES_PATH" init -b main

  if [[ -n "$GIT_REMOTE" ]]; then
    if [[ -n "$GIT_TOKEN" && -n "$GIT_USER" ]]; then
      PROTO="${GIT_REMOTE%%://*}://"
      REST="${GIT_REMOTE#*://}"
      AUTH_REMOTE="${PROTO}${GIT_USER}:${GIT_TOKEN}@${REST}"
      git -C "$NOTES_PATH" remote add origin "$AUTH_REMOTE"
    else
      git -C "$NOTES_PATH" remote add origin "$GIT_REMOTE"
    fi
    info "Fetching notes from remote…"
    git -C "$NOTES_PATH" fetch origin 2>/dev/null &&
      git -C "$NOTES_PATH" checkout -b main --track origin/main 2>/dev/null ||
      warn "Could not checkout remote branch — starting with an empty repo."
  fi
fi

# ─────────────────────────────────────────────
#  Clone / update backend
# ─────────────────────────────────────────────
if [[ -d "$BACKEND_DIR/.git" ]]; then
  info "Updating existing installation at $BACKEND_DIR"
  git -C "$BACKEND_DIR" pull --ff-only
else
  info "Cloning backend to $BACKEND_DIR"
  git clone --depth 1 "$REPO" "$BACKEND_DIR"
fi

mkdir -p "$BACKEND_DIR/apps/backend/data"

# ─────────────────────────────────────────────
#  Write backend .env
# ─────────────────────────────────────────────
cat > "$BACKEND_DIR/apps/backend/.env" <<ENVEOF
PORT=${BACKEND_PORT}
PASSWORD=${PASSWORD}
JWT_SECRET=${JWT_SECRET}
NOTES_REPO_PATH=${NOTES_PATH}
GIT_REMOTE_URL=${GIT_REMOTE}
GIT_USER_NAME=${GIT_USER:-clawzettel}
GIT_USER_EMAIL=clawzettel@claw-zettel
CLAWZETTEL_BASE_URL=${FRONTEND_PUBLIC_URL:-http://localhost:${FRONTEND_PORT}}
DB_PATH=/app/data/data.sqlite
ENVEOF

# ─────────────────────────────────────────────
#  Start backend
# ─────────────────────────────────────────────
info "Starting backend…"
docker compose -f "$BACKEND_DIR/apps/backend/docker-compose.yml" \
  --env-file "$BACKEND_DIR/apps/backend/.env" \
  up -d --build

# ─────────────────────────────────────────────
#  Start frontend (optional)
# ─────────────────────────────────────────────
if [[ "$INSTALL_FRONTEND" == "true" ]]; then
  info "Starting frontend…"
  printf 'PORT=%s\n' "$FRONTEND_PORT" > "$BACKEND_DIR/apps/frontend/.env"
  docker compose -f "$BACKEND_DIR/apps/frontend/docker-compose.yml" \
    --env-file "$BACKEND_DIR/apps/frontend/.env" \
    up -d --build
fi

# ─────────────────────────────────────────────
#  SSL + nginx reverse proxy
# ─────────────────────────────────────────────
if [[ "$USE_SSL" == "true" ]]; then
  NGINX_DIR="$BACKEND_DIR/nginx"
  mkdir -p "$NGINX_DIR/certs"

  # ── Obtain / copy certificate ──────────────
  if [[ "$SSL_TYPE" == "letsencrypt" ]]; then
    info "Obtaining Let's Encrypt certificate for $DOMAIN…"
    docker run --rm \
      -p 80:80 \
      -v "$NGINX_DIR/certs:/etc/letsencrypt" \
      certbot/certbot certonly \
        --standalone --non-interactive --agree-tos \
        --email "$LE_EMAIL" -d "$DOMAIN" \
      || error "Let's Encrypt failed. Check that $DOMAIN resolves here and port 80 is open."

    NGINX_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    NGINX_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    NGINX_CERTS_VOLUME="./certs:/etc/letsencrypt:ro"
  else
    cp "$CERT_FILE" "$NGINX_DIR/certs/cert.pem"
    cp "$KEY_FILE"  "$NGINX_DIR/certs/key.pem"
    NGINX_CERT="/etc/nginx/certs/cert.pem"
    NGINX_KEY="/etc/nginx/certs/key.pem"
    NGINX_CERTS_VOLUME="./certs:/etc/nginx/certs:ro"
  fi

  # ── Write nginx.conf ───────────────────────
  {
    cat <<NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${NGINX_CERT};
    ssl_certificate_key ${NGINX_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_session_cache shared:SSL:10m;

NGINXEOF

    if [[ "$INSTALL_FRONTEND" == "true" ]]; then
      cat <<NGINXEOF
    # Backend API (strips /api prefix before proxying)
    location /api/ {
        proxy_pass http://host.docker.internal:${BACKEND_PORT}/;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Frontend
    location / {
        proxy_pass http://host.docker.internal:${FRONTEND_PORT}/;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
NGINXEOF
    else
      cat <<NGINXEOF
    location / {
        proxy_pass http://host.docker.internal:${BACKEND_PORT}/;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
NGINXEOF
    fi

    echo "}"
  } > "$NGINX_DIR/nginx.conf"

  # ── Write nginx docker-compose ─────────────
  cat > "$NGINX_DIR/docker-compose.yml" <<DCEOF
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ${NGINX_CERTS_VOLUME}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
DCEOF

  info "Starting nginx reverse proxy…"
  docker compose -f "$NGINX_DIR/docker-compose.yml" up -d

  # ── Auto-renewal cron (Let's Encrypt only) ─
  if [[ "$SSL_TYPE" == "letsencrypt" ]]; then
    RENEW_CMD="docker compose -f '${NGINX_DIR}/docker-compose.yml' stop nginx \
&& docker run --rm -p 80:80 -v '${NGINX_DIR}/certs:/etc/letsencrypt' \
   certbot/certbot renew --standalone --quiet \
&& docker compose -f '${NGINX_DIR}/docker-compose.yml' start nginx"
    (crontab -l 2>/dev/null | grep -v certbot-renew; \
     echo "0 3,15 * * * $RENEW_CMD >> /var/log/certbot-renew.log 2>&1") | crontab -
    info "Certificate auto-renewal cron registered (3am & 3pm daily)."
  fi
fi

# ─────────────────────────────────────────────
#  nanoclaw
# ─────────────────────────────────────────────
if [[ "$INSTALL_NANOCLAW" == "true" ]]; then
  info "Setting up nanoclaw…"

  # Clone or update
  if [[ -d "$NANOCLAW_DIR/.git" ]]; then
    info "Updating existing nanoclaw at $NANOCLAW_DIR"
    git -C "$NANOCLAW_DIR" pull --ff-only
  else
    info "Cloning nanoclaw to $NANOCLAW_DIR"
    git clone --depth 1 "$NANOCLAW_REPO" "$NANOCLAW_DIR"
  fi

  # Mount allowlist — restrict agent to its own configs + notes only
  mkdir -p "${HOME}/.config/nanoclaw"
  cat > "${HOME}/.config/nanoclaw/mount-allowlist.json" <<MEOF
{
  "allowedRoots": [
    {
      "path": "${NANOCLAW_DIR}/groups",
      "allowReadWrite": true,
      "description": "nanoclaw agent group configs (own directory)"
    },
    {
      "path": "${NOTES_PATH}",
      "allowReadWrite": true,
      "description": "Zettelkasten notes"
    }
  ],
  "blockedPatterns": [
    ".env",
    "id_rsa",
    "id_ed25519",
    "*.key",
    "*.pem",
    "*.sqlite"
  ],
  "nonMainReadOnly": true
}
MEOF
  info "Mount allowlist written — nanoclaw restricted to its configs and notes."

  # Pre-create the zettelkasten agent group
  ZETTEL_GROUP_DIR="$NANOCLAW_DIR/groups/zettelkasten"
  mkdir -p "$ZETTEL_GROUP_DIR"
  cat > "$ZETTEL_GROUP_DIR/CLAUDE.md" <<GEOF
@./.claude-global.md
# Zettelkasten Assistant

You are a personal knowledge management assistant.
Your notes are mounted at \`/workspace/extra/notes/\`.

## Capabilities

- Read, create, and edit Markdown notes in \`/workspace/extra/notes/\`
- Link ideas between notes and suggest connections
- Search and summarise notes on request
- Help maintain note structure and metadata

## Hard Restrictions

You have access to exactly two locations:
- \`/workspace/group/\` — your own config and memory (this directory)
- \`/workspace/extra/notes/\` — the Zettelkasten notes

Do **not** attempt to read or write any other path.
Do **not** run system-level commands unrelated to managing notes.
Do **not** access the network unless asked to look something up.

## Note Format

Notes are plain Markdown. Follow the conventions already present in the
notes directory (filenames, front matter, linking style, etc.).
GEOF
  info "Zettelkasten agent group created."

  echo ""
  warn "─────────────────────────────────────────────"
  warn " nanoclaw setup will start now."
  warn ""
  warn " When asked to name your agent, use: ${NANOCLAW_TRIGGER}"
  warn ""
  warn " After completing the setup wizard, connect the agent"
  warn " to your notes by telling your main agent:"
  warn ""
  warn "   Register the zettelkasten group with folder 'zettelkasten'"
  warn "   and mount ${NOTES_PATH} at /workspace/extra/notes/ (read-write)"
  warn "─────────────────────────────────────────────"
  echo ""
  printf "  Press Enter to continue into nanoclaw setup…" >/dev/tty
  IFS= read -r _ </dev/tty

  cd "$NANOCLAW_DIR"
  ANTHROPIC_API_KEY="$NANOCLAW_API_KEY" bash nanoclaw.sh || \
    warn "nanoclaw setup exited — you can re-run it with: bash $NANOCLAW_DIR/nanoclaw.sh"
  cd - >/dev/null
fi

# ─────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────
echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │          Installation complete!       │"
echo "  └──────────────────────────────────────┘"
echo ""

if [[ "$USE_SSL" == "true" && "$INSTALL_FRONTEND" == "true" ]]; then
  info "Frontend:  https://${DOMAIN}"
  info "Backend:   https://${DOMAIN}/api"
elif [[ "$USE_SSL" == "true" ]]; then
  info "Backend:   https://${DOMAIN}"
elif [[ "$INSTALL_FRONTEND" == "true" ]]; then
  info "Frontend:  http://${SERVER_IP}:${FRONTEND_PORT}"
  info "Backend:   http://${SERVER_IP}:${BACKEND_PORT}"
else
  info "Backend:   http://${SERVER_IP}:${BACKEND_PORT}"
fi

echo ""
if [[ "$GENERATED_PASSWORD" == "true" ]]; then
  warn "Server password: ${PASSWORD}"
  warn "Save this — you need it to connect the frontend to the backend."
  echo ""
fi

warn ".env:      $BACKEND_DIR/apps/backend/.env"
if [[ "$INSTALL_NANOCLAW" == "true" ]]; then
  warn "nanoclaw:  $NANOCLAW_DIR"
  warn "allowlist: ${HOME}/.config/nanoclaw/mount-allowlist.json"
fi
echo ""
