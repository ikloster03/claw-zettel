import { Database } from "bun:sqlite";
import { join } from "path";

const DB_PATH = process.env.DB_PATH ?? join(process.cwd(), "data.sqlite");

export const db = new Database(DB_PATH, { create: true });

db.run("PRAGMA journal_mode=WAL");
db.run("PRAGMA foreign_keys=ON");

db.run(`
  CREATE TABLE IF NOT EXISTS chats (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
`);

db.run(`
  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
`);

db.run(`
  CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)
`);

try {
  db.run("ALTER TABLE messages ADD COLUMN thinking TEXT DEFAULT ''");
} catch {
  // Column already exists
};
