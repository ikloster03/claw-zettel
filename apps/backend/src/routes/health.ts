import { Hono } from "hono";
import { existsSync } from "fs";
import { join } from "path";

export const healthRouter = new Hono();

healthRouter.get("/", (c) => {
  const notesPath = process.env.NOTES_REPO_PATH ?? join(process.cwd(), "notes");
  const gitReady = existsSync(join(notesPath, ".git"));
  return c.json({
    ok: true,
    version: "0.1.0",
    notes_repo: notesPath,
    git_ready: gitReady,
  });
});
