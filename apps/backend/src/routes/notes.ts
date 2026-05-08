import { Hono } from "hono";
import { join, resolve } from "path";
import { readdir, readFile, writeFile, unlink, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { authMiddleware } from "../middleware/auth";
import { gitCommitAndPush } from "../services/git";

export const notesRouter = new Hono();
notesRouter.use("*", authMiddleware);

function notesRoot(): string {
  return resolve(process.env.NOTES_REPO_PATH ?? join(process.cwd(), "notes"));
}

function safeFullPath(root: string, userPath: string): string | null {
  const full = resolve(join(root, userPath));
  if (full !== root && !full.startsWith(root + "/")) return null;
  return full;
}

async function listMdFiles(dir: string, base = ""): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const results: string[] = [];
  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    const rel = base ? `${base}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      results.push(...(await listMdFiles(join(dir, entry.name), rel)));
    } else if (entry.name.endsWith(".md")) {
      results.push(rel);
    }
  }
  return results;
}

notesRouter.get("/", async (c) => {
  const root = notesRoot();
  if (!existsSync(root)) return c.json([]);
  const files = await listMdFiles(root);
  return c.json(files);
});

notesRouter.get("/search", async (c) => {
  const q = (c.req.query("q") ?? "").toLowerCase();
  if (!q) return c.json([]);
  const root = notesRoot();
  if (!existsSync(root)) return c.json([]);
  const files = await listMdFiles(root);
  const results: { path: string; excerpt: string }[] = [];
  for (const file of files) {
    const text = await readFile(join(root, file), "utf-8");
    if (text.toLowerCase().includes(q)) {
      const idx = text.toLowerCase().indexOf(q);
      const excerpt = text.slice(Math.max(0, idx - 60), idx + 120).replace(/\n/g, " ").trim();
      results.push({ path: file, excerpt });
    }
  }
  return c.json(results);
});

notesRouter.get("/*", async (c) => {
  const path = c.req.path.replace(/^\/notes\//, "");
  const root = notesRoot();
  const fullPath = safeFullPath(root, path);
  if (!fullPath) return c.json({ error: "Invalid path" }, 400);
  if (!existsSync(fullPath)) return c.json({ error: "Not found" }, 404);
  const content = await readFile(fullPath, "utf-8");
  return c.json({ path, content });
});

notesRouter.post("/", async (c) => {
  const { path, content } = await c.req.json<{ path: string; content: string }>();
  const root = notesRoot();
  const fullPath = safeFullPath(root, path);
  if (!fullPath) return c.json({ error: "Invalid path" }, 400);
  await mkdir(join(fullPath, ".."), { recursive: true });
  await writeFile(fullPath, content, "utf-8");
  await gitCommitAndPush(`create: ${path}`);
  return c.json({ ok: true, path }, 201);
});

notesRouter.put("/*", async (c) => {
  const path = c.req.path.replace(/^\/notes\//, "");
  const { content } = await c.req.json<{ content: string }>();
  const root = notesRoot();
  const fullPath = safeFullPath(root, path);
  if (!fullPath) return c.json({ error: "Invalid path" }, 400);
  if (!existsSync(fullPath)) return c.json({ error: "Not found" }, 404);
  await writeFile(fullPath, content, "utf-8");
  await gitCommitAndPush(`update: ${path}`);
  return c.json({ ok: true });
});

notesRouter.delete("/*", async (c) => {
  const path = c.req.path.replace(/^\/notes\//, "");
  const root = notesRoot();
  const fullPath = safeFullPath(root, path);
  if (!fullPath) return c.json({ error: "Invalid path" }, 400);
  if (!existsSync(fullPath)) return c.json({ error: "Not found" }, 404);
  await unlink(fullPath);
  await gitCommitAndPush(`delete: ${path}`);
  return c.json({ ok: true });
});
