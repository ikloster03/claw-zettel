import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { HTTPException } from "hono/http-exception";
import "./db";
import { authRouter } from "./routes/auth";
import { chatsRouter } from "./routes/chats";
import { notesRouter } from "./routes/notes";
import { healthRouter } from "./routes/health";
import { seedLocalNotes } from "./services/localSeed";

const app = new Hono();

app.use("*", logger());
app.use(
  "*",
  cors({
    origin: "*",
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
    exposeHeaders: ["Content-Type"],
  })
);

app.route("/auth", authRouter);
app.route("/chats", chatsRouter);
app.route("/notes", notesRouter);
app.route("/health", healthRouter);

app.notFound((c) => c.json({ error: "Not found" }, 404));
app.onError((err, c) => {
  console.error(err);
  // Ensure CORS headers survive error responses (HTTPException creates a new Response
  // that doesn't inherit headers set by the cors() middleware on the context).
  c.header("Access-Control-Allow-Origin", "*");
  if (err instanceof HTTPException) {
    return c.json({ error: err.message }, err.status);
  }
  return c.json({ error: err.message }, 500);
});

await seedLocalNotes();

const port = Number(process.env.PORT ?? 3001);
const mode = process.env.CLAWZETTEL_MODE === "mock" ? " [local/mock]" : "";
console.log(`Backend running on http://0.0.0.0:${port}${mode}`);

export default {
  port,
  fetch: app.fetch,
};
