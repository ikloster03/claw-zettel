# claw-zettel

AI-powered personal Zettelkasten web app. Connect your own VPS running [clawzettel](https://github.com/ikloster03/clawzettel) and get a unified interface for chatting with AI and managing your notes.

## Architecture

```
Frontend (static SPA)  ←──── HTTP/HTTPS ────→  Backend (your VPS)
  Vue3 + Pinia                                    Hono + Bun
  reka-ui + Tailwind                              SQLite (chat history)
  Docker / Vercel                                 clawzettel AI agent
                                                  Git (notes repo)
```

## Quick start

### 1. Install backend on your VPS

```bash
curl -fsSL https://raw.githubusercontent.com/ikloster03/claw-zettel/main/scripts/install.sh | bash
```

The script will:
- Ask for a password, port, path to your Zettelkasten Git repo, and clawzettel URL
- Clone the backend, create `.env`, and start it via Docker Compose

### 2. Run frontend locally

```bash
bun install
bun run dev:frontend
```

Or with Docker:

```bash
cd apps/frontend
docker compose up -d
```

Or deploy to Vercel / Netlify — the repo includes `vercel.json` and `.netlify.toml`.

### 3. Connect

Open the frontend, enter your server URL (e.g. `http://your-vps:3001`) and password.

---

## Development

```bash
bun install          # install all workspace dependencies
bun run dev          # start both frontend and backend in watch mode
bun run dev:frontend # frontend only (port 5173)
bun run dev:backend  # backend only (port 3001)
```

Copy `.env.example` to `.env` in `apps/backend/` before running the backend.

## Tech stack

| Layer    | Tech |
|----------|------|
| Frontend | Vue 3, Pinia, reka-ui, Tailwind CSS v4, Vite, TypeScript |
| Backend  | Hono, Bun, SQLite (`bun:sqlite`), jose (JWT) |
| AI       | clawzettel (streaming SSE) |
| VCS      | Git (auto-commit + push after note operations) |
| Infra    | Docker, Docker Compose, nginx |

## Features

- **Chat** — multiple isolated chat sessions, streaming AI responses (SSE)
- **Zettelkasten search** — ask AI to search your notes
- **Note operations via chat** — create, edit, refactor notes through conversation
- **Notes editor** — standalone Markdown editor and viewer (no AI required)
- **Full-text search** — search across all notes
- **Auto Git commits** — every note change is committed and pushed automatically
- **Responsive** — mobile, tablet, desktop layouts
- **Dark mode**
