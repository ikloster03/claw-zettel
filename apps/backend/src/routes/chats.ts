import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import { db } from "../db";
import { authMiddleware } from "../middleware/auth";
import { clawzettelChat, generateChatTitle } from "../services/clawzettel";

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

chatsRouter.delete("/:id/messages/last", (c) => {
  const { id } = c.req.param();
  const lastTwo = db
    .query("SELECT * FROM messages WHERE chat_id = ? ORDER BY created_at DESC LIMIT 2")
    .all(id) as { id: string; role: string; content: string }[];

  if (lastTwo.length === 0) return c.json({ ok: true, userContent: null });

  const [last, prev] = lastTwo;

  if (last.role === "assistant" && prev?.role === "user") {
    db.run("DELETE FROM messages WHERE id IN (?, ?)", [last.id, prev.id]);
    return c.json({ ok: true, userContent: prev.content });
  }

  if (last.role === "user") {
    db.run("DELETE FROM messages WHERE id = ?", [last.id]);
    return c.json({ ok: true, userContent: last.content });
  }

  return c.json({ ok: true, userContent: null });
});

chatsRouter.post("/:id/messages", async (c) => {
  const { id } = c.req.param();
  const { content } = await c.req.json<{ content: string }>();
  const reqSignal = c.req.raw.signal;

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

  const isFirstMessage = history.length === 1;

  return streamSSE(c, async (stream) => {
    let fullContent = "";
    let fullThinking = "";
    let streamError = false;

    const abortAndCleanup = () => {
      db.run("DELETE FROM messages WHERE id = ?", [userMsgId]);
    };

    try {
      for await (const chunk of clawzettelChat(history)) {
        if (reqSignal.aborted) {
          abortAndCleanup();
          return;
        }
        if (chunk.type === "text") {
          fullContent += chunk.text;
          try {
            await stream.writeSSE({ data: JSON.stringify({ chunk: chunk.text }) });
          } catch {
            abortAndCleanup();
            return;
          }
        } else if (chunk.type === "thinking") {
          fullThinking += chunk.text;
          try {
            await stream.writeSSE({ data: JSON.stringify({ thinking: chunk.text }) });
          } catch {
            abortAndCleanup();
            return;
          }
        }
      }
    } catch (err) {
      streamError = true;
      try {
        await stream.writeSSE({ data: JSON.stringify({ error: String(err) }), event: "error" });
      } catch {
        // ignore write error if client already disconnected
      }
      return;
    }

    if (reqSignal.aborted) {
      abortAndCleanup();
      return;
    }

    const asstMsgId = crypto.randomUUID();
    db.run(
      "INSERT INTO messages (id, chat_id, role, content, thinking, created_at) VALUES (?, ?, 'assistant', ?, ?, ?)",
      [asstMsgId, id, fullContent, fullThinking, Date.now()]
    );
    db.run("UPDATE chats SET updated_at = ? WHERE id = ?", [Date.now(), id]);

    if (isFirstMessage && !streamError) {
      try {
        const title = await generateChatTitle(content);
        db.run("UPDATE chats SET title = ? WHERE id = ?", [title, id]);
        await stream.writeSSE({ data: JSON.stringify({ titleUpdate: title }) });
      } catch {
        // title generation is best-effort
      }
    }

    await stream.writeSSE({ data: JSON.stringify({ done: true, id: asstMsgId }), event: "done" });
  });
});
