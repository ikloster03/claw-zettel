#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/ikloster03/claw-zettel"
BACKEND_DIR="/opt/claw-zettel-backend"

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
step "[1/5] Notes repository"

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
step "[2/5] Server password"

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
step "[3/5] Ports"
ask BACKEND_PORT "Backend port" "3001"

# ─────────────────────────────────────────────
#  Step 4: Domain + SSL  [required]
# ─────────────────────────────────────────────
step "[4/5] Domain & SSL (required)"

echo "    A domain name pointing to this server is required to generate"
echo "    an HTTPS certificate.  Make sure the DNS A-record already resolves"
echo "    to this server's IP and that ports 80 and 443 are open."
echo ""

SSL_TYPE="letsencrypt"
LE_EMAIL="" CERT_FILE="" KEY_FILE=""

ask DOMAIN "Domain name (e.g. notes.example.com)"
[[ -z "$DOMAIN" ]] && error "Domain is required.  Point a DNS A-record to this server first."
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
  info "Certbot will temporarily bind to port 80 — make sure nothing else uses it."
fi

# ─────────────────────────────────────────────
#  Step 5: GLM AI chat
# ─────────────────────────────────────────────
step "[5/5] GLM AI chat"

GLM_API_KEY=""
GLM_BASE_URL="https://api.z.ai/api/coding/paas/v4"
GLM_MODEL="glm-z1-flash"

echo "    The AI chat feature uses the GLM API (z.ai). Get your key at z.ai."
echo "    Leave blank to start in mock mode (no real AI responses)."
echo ""

ask_secret GLM_API_KEY "GLM API key (leave blank for mock mode)"
if [[ -n "$GLM_API_KEY" ]]; then
  ask GLM_BASE_URL "GLM base URL" "$GLM_BASE_URL"
  ask GLM_MODEL "GLM model" "$GLM_MODEL"
fi

# ─────────────────────────────────────────────
#  Derived values
# ─────────────────────────────────────────────
JWT_SECRET="$(gen_secret)"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)"

BACKEND_PUBLIC_URL="https://${DOMAIN}"

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
if [[ -n "$GLM_API_KEY" ]]; then
  CLAWZETTEL_MODE_LINE=""
  GLM_LINES="GLM_API_KEY=${GLM_API_KEY}
GLM_BASE_URL=${GLM_BASE_URL}
GLM_MODEL=${GLM_MODEL}"
else
  CLAWZETTEL_MODE_LINE="CLAWZETTEL_MODE=mock"
  GLM_LINES="# GLM_API_KEY= (not set — running in mock mode)"
fi

cat > "$BACKEND_DIR/apps/backend/.env" <<ENVEOF
PORT=${BACKEND_PORT}
PASSWORD=${PASSWORD}
JWT_SECRET=${JWT_SECRET}
NOTES_REPO_PATH=${NOTES_PATH}
GIT_REMOTE_URL=${GIT_REMOTE}
GIT_USER_NAME=${GIT_USER:-clawzettel}
GIT_USER_EMAIL=clawzettel@claw-zettel
${GLM_LINES}
${CLAWZETTEL_MODE_LINE}
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

    cat <<NGINXEOF
    location / {
        proxy_pass http://host.docker.internal:${BACKEND_PORT}/;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
NGINXEOF

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

  # ── Auto-renewal (Let's Encrypt only) ────────
  if [[ "$SSL_TYPE" == "letsencrypt" ]]; then
    RENEW_SCRIPT="/usr/local/bin/certbot-renew-claw.sh"
    RENEW_LOG="/var/log/certbot-renew-claw.log"

    cat > "$RENEW_SCRIPT" <<RENEWEOF
#!/usr/bin/env bash
# Auto-generated by claw-zettel installer — do not edit manually.
set -euo pipefail
NGINX_DIR="${NGINX_DIR}"
LOG="${RENEW_LOG}"
exec >> "\$LOG" 2>&1
echo "--- \$(date -u +%Y-%m-%dT%H:%M:%SZ) certbot renew ---"
docker compose -f "\$NGINX_DIR/docker-compose.yml" stop nginx
docker run --rm \
  -p 80:80 \
  -v "\$NGINX_DIR/certs:/etc/letsencrypt" \
  certbot/certbot renew --standalone --quiet
docker compose -f "\$NGINX_DIR/docker-compose.yml" start nginx
echo "--- done ---"
RENEWEOF
    chmod +x "$RENEW_SCRIPT"

    # Use systemd timer if available, otherwise fall back to cron
    if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
      cat > /etc/systemd/system/certbot-renew-claw.service <<SVCEOF
[Unit]
Description=claw-zettel Let's Encrypt certificate renewal
After=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=${RENEW_SCRIPT}
StandardOutput=append:${RENEW_LOG}
StandardError=append:${RENEW_LOG}
SVCEOF

      cat > /etc/systemd/system/certbot-renew-claw.timer <<TIMEREOF
[Unit]
Description=claw-zettel Let's Encrypt certificate renewal (twice daily)

[Timer]
OnCalendar=*-*-* 03,15:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

      systemctl daemon-reload
      systemctl enable --now certbot-renew-claw.timer
      info "Certificate auto-renewal systemd timer registered (3am & 3pm, ±30 min jitter)."
    else
      # Fallback: cron
      (crontab -l 2>/dev/null | grep -v certbot-renew-claw; \
       echo "0 3,15 * * * ${RENEW_SCRIPT} >> ${RENEW_LOG} 2>&1") | crontab -
      info "Certificate auto-renewal cron registered (3am & 3pm daily)."
    fi

    info "Renewal log: ${RENEW_LOG}"
  fi
fi

# ─────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────
echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │          Installation complete!       │"
echo "  └──────────────────────────────────────┘"
echo ""

info "Backend:   https://${DOMAIN}"

echo ""
if [[ "$GENERATED_PASSWORD" == "true" ]]; then
  warn "Server password: ${PASSWORD}"
  warn "Save this — you need it to connect the frontend to the backend."
  echo ""
fi

warn ".env:      $BACKEND_DIR/apps/backend/.env"
if [[ -z "$GLM_API_KEY" ]]; then
  warn "AI chat:   mock mode (set GLM_API_KEY in .env to enable real AI)"
else
  warn "AI chat:   GLM ${GLM_MODEL} via ${GLM_BASE_URL}"
fi
echo ""
