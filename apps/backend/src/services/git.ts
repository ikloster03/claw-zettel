import { join } from "path";

function notesRoot(): string {
  return process.env.NOTES_REPO_PATH ?? join(process.cwd(), "notes");
}

async function git(args: string[]): Promise<string> {
  const cwd = notesRoot();
  const name = process.env.GIT_USER_NAME ?? "nanoclaw";
  const email = process.env.GIT_USER_EMAIL ?? "nanoclaw@claw-zettel";
  const proc = Bun.spawn(
    ["git", "-c", `user.name=${name}`, "-c", `user.email=${email}`, ...args],
    { cwd, stdout: "pipe", stderr: "pipe" }
  );
  await proc.exited;
  return new Response(proc.stdout).text();
}

export async function gitCommitAndPush(message: string): Promise<void> {
  try {
    await git(["add", "-A"]);
    await git(["commit", "-m", message]);
    const remote = process.env.GIT_REMOTE_URL;
    if (remote) {
      await git(["push"]);
    }
  } catch {
    // Git errors are non-fatal — note was already saved to disk
  }
}
