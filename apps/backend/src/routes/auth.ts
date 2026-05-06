import { Hono } from "hono";
import { signToken } from "../middleware/auth";

export const authRouter = new Hono();

authRouter.post("/login", async (c) => {
  const { password } = await c.req.json<{ password: string }>();
  const expected = process.env.PASSWORD ?? "changeme";

  if (password !== expected) {
    return c.json({ error: "Invalid password" }, 401);
  }

  const token = await signToken({ sub: "user" });
  return c.json({ token });
});
