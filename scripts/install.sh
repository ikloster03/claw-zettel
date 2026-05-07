#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/ikloster03/claw-zettel"
BACKEND_DIR="/opt/claw-zettel-backend"
ZEROCLAW_CONFIG_DIR="${HOME}/.zeroclaw"

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
step "[1/7] Notes repository"

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
step "[2/7] Server password"

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
step "[3/7] Ports"
ask BACKEND_PORT "Backend port" "3001"

# ─────────────────────────────────────────────
#  Step 4: Frontend (optional)
# ─────────────────────────────────────────────
step "[4/7] Frontend (clawzettel UI)"

INSTALL_FRONTEND=false
FRONTEND_PORT="3000"

if ask_yn "Install the frontend UI?" "y"; then
  INSTALL_FRONTEND=true
  ask FRONTEND_PORT "Frontend port" "3000"
fi

# ─────────────────────────────────────────────
#  Step 5: Domain + SSL
# ─────────────────────────────────────────────
step "[5/7] Domain & SSL"

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
#  Step 6: zeroclaw AI agent (optional)
# ─────────────────────────────────────────────
step "[6/7] zeroclaw AI agent"

INSTALL_ZEROCLAW=false
ZEROCLAW_API_KEY=""

echo "    zeroclaw is a self-hosted AI agent runtime (Rust binary). It connects"
echo "    to LLM providers, channels (Discord, Telegram, CLI, …) and tools."
echo "    Config lives at ~/.zeroclaw/config.toml"
echo ""

if ask_yn "Install zeroclaw AI agent?" "n"; then
  INSTALL_ZEROCLAW=true
  ask_secret ZEROCLAW_API_KEY "z.ia API key (ZAI_API_KEY)"
  [[ -z "$ZEROCLAW_API_KEY" ]] && error "z.ia API key is required for zeroclaw."
fi

# ─────────────────────────────────────────────
#  Step 7: opencode AI coding assistant (optional)
# ─────────────────────────────────────────────
step "[7/7] opencode AI coding assistant"

INSTALL_OPENCODE=false
OPENCODE_PROVIDER=""
OPENCODE_API_KEY=""
OPENCODE_MODEL=""

echo "    opencode is a terminal-based AI coding assistant."
echo ""

if ask_yn "Install opencode?" "n"; then
  INSTALL_OPENCODE=true

  echo ""
  echo "    Provider options:"
  echo "    1) Anthropic (Claude) — console.anthropic.com"
  echo "    2) z.ia               — z.ia / glm models"
  echo "    3) OpenAI             — platform.openai.com"
  echo "    4) Other (custom OpenAI-compatible endpoint)"
  echo ""
  ask OPENCODE_PROVIDER_CHOICE "Choice" "2"

  case "$OPENCODE_PROVIDER_CHOICE" in
    1)
      OPENCODE_PROVIDER="anthropic"
      ask_secret OPENCODE_API_KEY "Anthropic API key"
      ask OPENCODE_MODEL "Model" "claude-sonnet-4-5"
      ;;
    2)
      OPENCODE_PROVIDER="z.ai"
      ask_secret OPENCODE_API_KEY "z.ia API key"
      ask OPENCODE_MODEL "Model" "glm-5.1"
      ;;
    3)
      OPENCODE_PROVIDER="openai"
      ask_secret OPENCODE_API_KEY "OpenAI API key"
      ask OPENCODE_MODEL "Model" "gpt-4o"
      ;;
    4)
      OPENCODE_PROVIDER="custom"
      ask OPENCODE_CUSTOM_BASE_URL "Base URL (e.g. https://api.example.com/v1)"
      [[ -z "$OPENCODE_CUSTOM_BASE_URL" ]] && error "Base URL cannot be empty."
      ask_secret OPENCODE_API_KEY "API key"
      ask OPENCODE_MODEL "Model name"
      [[ -z "$OPENCODE_MODEL" ]] && error "Model name cannot be empty."
      ;;
    *)
      warn "Unknown choice, skipping opencode provider configuration."
      ;;
  esac
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
#  zeroclaw
# ─────────────────────────────────────────────
if [[ "$INSTALL_ZEROCLAW" == "true" ]]; then
  info "Installing zeroclaw…"

  # Install the zeroclaw binary (prebuilt, skip onboard wizard — configure below)
  SKIP_ONBOARD=true curl -fsSL \
    https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/install.sh \
    | bash -s -- --prebuilt --skip-onboard || error "zeroclaw installation failed."

  ZEROCLAW_BIN="${HOME}/.cargo/bin/zeroclaw"
  if [[ ! -f "$ZEROCLAW_BIN" ]]; then
    warn "zeroclaw binary not found at $ZEROCLAW_BIN — onboard skipped."
    warn "After adding ~/.cargo/bin to PATH, run: zeroclaw onboard --provider zai"
  else
    info "Configuring zeroclaw with z.ia provider (glm-5.1)…"
    ZAI_API_KEY="$ZEROCLAW_API_KEY" ZEROCLAW_MODEL="glm-5.1" \
      "$ZEROCLAW_BIN" onboard --provider zai --api-key "$ZEROCLAW_API_KEY" || \
      warn "zeroclaw onboard failed — run manually: zeroclaw onboard --provider zai"
    info "Run 'zeroclaw agent' to start chatting, or 'zeroclaw service install' for always-on."
  fi
fi

# ─────────────────────────────────────────────
#  opencode
# ─────────────────────────────────────────────
if [[ "$INSTALL_OPENCODE" == "true" ]]; then
  info "Installing opencode…"
  curl -fsSL https://opencode.ai/install | bash || error "opencode installation failed."

  OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
  mkdir -p "$OPENCODE_CONFIG_DIR"

  case "$OPENCODE_PROVIDER" in
    anthropic)
      cat > "$OPENCODE_CONFIG_DIR/config.json" <<OCEOF
{
  "model": "${OPENCODE_MODEL}",
  "provider": {
    "anthropic": {
      "apiKey": "${OPENCODE_API_KEY}"
    }
  }
}
OCEOF
      ;;
    z.ai)
      cat > "$OPENCODE_CONFIG_DIR/config.json" <<OCEOF
{
  "model": "${OPENCODE_MODEL}",
  "provider": {
    "openai": {
      "name": "z.ai",
      "baseUrl": "https://api.z.ai/v1",
      "apiKey": "${OPENCODE_API_KEY}"
    }
  }
}
OCEOF
      ;;
    openai)
      cat > "$OPENCODE_CONFIG_DIR/config.json" <<OCEOF
{
  "model": "${OPENCODE_MODEL}",
  "provider": {
    "openai": {
      "apiKey": "${OPENCODE_API_KEY}"
    }
  }
}
OCEOF
      ;;
    custom)
      cat > "$OPENCODE_CONFIG_DIR/config.json" <<OCEOF
{
  "model": "${OPENCODE_MODEL}",
  "provider": {
    "openai": {
      "baseUrl": "${OPENCODE_CUSTOM_BASE_URL}",
      "apiKey": "${OPENCODE_API_KEY}"
    }
  }
}
OCEOF
      ;;
  esac

  info "opencode configured at $OPENCODE_CONFIG_DIR/config.json"
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
if [[ "$INSTALL_ZEROCLAW" == "true" ]]; then
  warn "zeroclaw:  ${HOME}/.cargo/bin/zeroclaw"
  warn "config:    ${ZEROCLAW_CONFIG_DIR}/config.toml"
fi
if [[ "$INSTALL_OPENCODE" == "true" ]]; then
  warn "opencode:  ${HOME}/.config/opencode/config.json"
fi
echo ""
