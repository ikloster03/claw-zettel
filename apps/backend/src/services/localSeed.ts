import { join } from "path";
import { existsSync } from "fs";
import { mkdir, writeFile } from "fs/promises";

const SAMPLE_NOTES: Record<string, string> = {
  "zettelkasten/about.md": `# Что такое Zettelkasten

Zettelkasten («ящик карточек» с нем.) — метод управления знаниями, разработанный социологом Никласом Луманом.

## Принципы

- **Атомарность** — одна заметка = одна идея
- **Связность** — заметки ссылаются друг на друга
- **Собственными словами** — не копипаст, а переформулировка

## Теги

#метод #pkm #знания
`,
  "zettelkasten/links.md": `# Как создавать связи между заметками

Ссылки — главная сила Zettelkasten. Связывайте заметки через \`[[название]]\`.

## Типы связей

- **Прямая ссылка** — явная связь идей
- **Тематическая** — через общие теги
- **Структурная** — через индексные заметки

## Пример

Идея из [[zettelkasten/about]] применима в [[projects/claw-zettel]].

#zettelkasten #связи
`,
  "projects/claw-zettel.md": `# claw-zettel

AI-ассистент для работы с Zettelkasten.

## Стек

- Frontend: Vue 3 + Pinia + Tailwind
- Backend: Hono + Bun + SQLite
- AI: clawzettel

## Возможности

- Чат с AI о заметках
- Создание и редактирование через чат
- Поиск по базе знаний
- Автоматические git-коммиты

#проект #vue #bun
`,
  "ideas/learning.md": `# Заметки об обучении

## Техника интервального повторения

Повторяй материал через возрастающие промежутки времени:
1 день → 3 дня → 1 неделя → 2 недели → 1 месяц

## Метод Фейнмана

1. Изучи концепцию
2. Объясни её простыми словами
3. Найди пробелы
4. Вернись к источнику
5. Упрости объяснение

Связано с: [[zettelkasten/about]]

#обучение #методы
`,
  "inbox/unsorted.md": `# Входящие (unsorted)

Заметки для последующей обработки и переноса в нужные разделы.

- Прочитать о методе PARA
- Посмотреть Obsidian vs Logseq
- Попробовать weekly review

#inbox #todo
`,
};

export async function seedLocalNotes(): Promise<void> {
  if (process.env.CLAWZETTEL_MODE !== "mock") return;

  const root = process.env.NOTES_REPO_PATH ?? "./local-notes";
  if (existsSync(root)) return; // already seeded

  console.log("[local] Seeding example notes in", root);

  for (const [relPath, content] of Object.entries(SAMPLE_NOTES)) {
    const fullPath = join(root, relPath);
    const dir = join(fullPath, "..");
    await mkdir(dir, { recursive: true });
    await writeFile(fullPath, content, "utf-8");
  }

  // Init a local git repo so git operations don't fail
  const proc = Bun.spawn(
    ["git", "init", "-b", "main"],
    { cwd: root, stdout: "pipe", stderr: "pipe" }
  );
  await proc.exited;

  const commit = Bun.spawn(
    [
      "git",
      "-c", "user.name=clawzettel-local",
      "-c", "user.email=clawzettel@localhost",
      "commit",
      "--allow-empty",
      "-m", "initial: seed example notes",
    ],
    { cwd: root, stdout: "pipe", stderr: "pipe" }
  );
  // stage first
  const add = Bun.spawn(["git", "add", "-A"], { cwd: root, stdout: "pipe", stderr: "pipe" });
  await add.exited;
  await commit.exited;

  console.log("[local] Example notes ready:", Object.keys(SAMPLE_NOTES).length, "files");
}
