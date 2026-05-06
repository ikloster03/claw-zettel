import { createMiddleware } from "hono/factory";
import { HTTPException } from "hono/http-exception";
import { SignJWT, jwtVerify } from "jose";

const secret = new TextEncoder().encode(
  process.env.JWT_SECRET ?? "dev-secret-change-in-production"
);

export async function signToken(payload: Record<string, unknown>): Promise<string> {
  return new SignJWT(payload)
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(secret);
}

export async function verifyToken(token: string) {
  const { payload } = await jwtVerify(token, secret);
  return payload;
}

export const authMiddleware = createMiddleware(async (c, next) => {
  const header = c.req.header("Authorization");
  if (!header?.startsWith("Bearer ")) {
    throw new HTTPException(401, { message: "Unauthorized" });
  }
  const token = header.slice(7);
  try {
    await verifyToken(token);
  } catch {
    throw new HTTPException(401, { message: "Invalid token" });
  }
  await next();
});
