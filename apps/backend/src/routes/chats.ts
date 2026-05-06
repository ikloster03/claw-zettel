import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import { db } from "../db";
import { authMiddleware } from "../middleware/auth";
import { nanoclawChat } from "../services/nanoclaw";

export const chatsRouter = new Hono();
chatsRouter.use("*", authMiddleware);

chatsRouter.get("/", (c) => {
  const chats = db
    .query("SELECT * FROM chats ORDER BY updated_at DESC")
    .all();
  return c.json(chats);
});

chatsRouter.post("/", async (c) => {
  const { title } = await c.req.json<{ title?: string }>();
  const id = crypto.randomUUID();
  const now = Date.now();
  db.run(
    "INSERT INTO chats (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
    [id, title ?? "New chat", now, now]
  );
  return c.json({ id, title: title ?? "New chat", created_at: now, updated_at: now }, 201);
});

chatsRouter.patch("/:id", async (c) => {
  const { id } = c.req.param();
  const { title } = await c.req.json<{ title: string }>();
  const now = Date.now();
  db.run("UPDATE chats SET title = ?, updated_at = ? WHERE id = ?", [title, now, id]);
  return c.json({ ok: true });
});

chatsRouter.delete("/:id", (c) => {
  const { id } = c.req.param();
  db.run("DELETE FROM chats WHERE id = ?", [id]);
  return c.json({ ok: true });
});

chatsRouter.get("/:id/messages", (c) => {
  const { id } = c.req.param();
  const messages = db
    .query("SELECT * FROM messages WHERE chat_id = ? ORDER BY created_at ASC")
    .all(id);
  return c.json(messages);
});

chatsRouter.post("/:id/messages", async (c) => {
  const { id } = c.req.param();
  const { content } = await c.req.json<{ content: string }>();

  const userMsgId = crypto.randomUUID();
  const now = Date.now();
  db.run(
    "INSERT INTO messages (id, chat_id, role, content, created_at) VALUES (?, ?, 'user', ?, ?)",
    [userMsgId, id, content, now]
  );
  db.run("UPDATE chats SET updated_at = ? WHERE id = ?", [now, id]);

  const history = db
    .query("SELECT role, content FROM messages WHERE chat_id = ? ORDER BY created_at ASC")
    .all(id) as { role: string; content: string }[];

  return streamSSE(c, async (stream) => {
    let fullContent = "";
    try {
      for await (const chunk of nanoclawChat(history)) {
        fullContent += chunk;
        await stream.writeSSE({ data: JSON.stringify({ chunk }) });
      }
    } catch (err) {
      await stream.writeSSE({ data: JSON.stringify({ error: String(err) }), event: "error" });
      return;
    }

    const asstMsgId = crypto.randomUUID();
    db.run(
      "INSERT INTO messages (id, chat_id, role, content, created_at) VALUES (?, ?, 'assistant', ?, ?)",
      [asstMsgId, id, fullContent, Date.now()]
    );
    db.run("UPDATE chats SET updated_at = ? WHERE id = ?", [Date.now(), id]);
    await stream.writeSSE({ data: JSON.stringify({ done: true, id: asstMsgId }), event: "done" });
  });
});
