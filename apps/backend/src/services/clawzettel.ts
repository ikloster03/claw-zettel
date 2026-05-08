export interface Message {
  role: string;
  content: string;
}

const CLAWZETTEL_URL = () =>
  process.env.CLAWZETTEL_BASE_URL ?? "http://host.docker.internal:42617";

const CLAWZETTEL_TOKEN = () => process.env.CLAWZETTEL_TOKEN ?? "";

async function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function* mockChat(messages: Message[]): AsyncGenerator<string> {
  const last = messages.findLast((m) => m.role === "user")?.content ?? "";
  const lower = last.toLowerCase();

  let reply: string;

  if (lower.includes("привет") || lower.includes("hello") || lower.includes("hi")) {
    reply =
      "Привет! Я mock-версия clawzettel для локального тестирования. " +
      "Я могу помочь вам с вашим Zettelkasten — создавать, искать и редактировать заметки. " +
      "Попробуйте спросить: «покажи мои заметки» или «создай заметку о Vue 3».";
  } else if (lower.includes("заметк") || lower.includes("note")) {
    reply =
      "В вашем Zettelkasten есть несколько заметок для демонстрации. " +
      "Вы можете перейти во вкладку **Notes** чтобы просмотреть и отредактировать их, " +
      "или попросите меня найти что-то конкретное. " +
      "Например: «найди заметки про Zettelkasten».";
  } else if (lower.includes("найди") || lower.includes("search") || lower.includes("поиск")) {
    reply =
      "Поиск по Zettelkasten работает через вкладку Notes (строка поиска слева). " +
      "В реальном режиме clawzettel выполняет семантический поиск по вашей базе знаний. " +
      "В local-режиме — простой полнотекстовый поиск через API `/notes/search?q=`.";
  } else if (lower.includes("создай") || lower.includes("create") || lower.includes("напиши")) {
    reply =
      "Хорошо! В реальном режиме я бы создал заметку прямо сейчас. " +
      "В local-режиме используйте кнопку **+** во вкладке Notes, " +
      "или скажите мне точный путь и содержимое, и я вызову API создания.";
  } else if (lower.includes("помощ") || lower.includes("help") || lower.includes("умеешь")) {
    reply =
      "**Что я умею:**\n\n" +
      "- Искать информацию в вашем Zettelkasten\n" +
      "- Создавать новые заметки\n" +
      "- Редактировать и рефакторить существующие\n" +
      "- Искать в интернете (в реальном режиме)\n" +
      "- Связывать идеи между заметками\n\n" +
      "> **Сейчас работает local-режим** (mock clawzettel). " +
      "Подключите реальный clawzettel-сервер для полного функционала.";
  } else {
    reply =
      `Вы написали: _«${last}»_\n\n` +
      "Я получил ваше сообщение. В **local-режиме** я не подключён к реальному clawzettel, " +
      "поэтому не могу обработать произвольные запросы к вашей базе знаний.\n\n" +
      "Для полноценной работы запустите clawzettel-сервер и укажите `CLAWZETTEL_BASE_URL` в `.env`.\n\n" +
      "А пока — попробуйте вкладку **Notes** для работы с заметками без AI.";
  }

  const words = reply.split(/(\s+)/);
  for (const word of words) {
    yield word;
    await sleep(25 + Math.random() * 30);
  }
}

function buildPrompt(messages: Message[]): string {
  return messages
    .map((m) => `${m.role === "user" ? "User" : "Assistant"}: ${m.content}`)
    .join("\n") + "\nAssistant:";
}

export async function* clawzettelChat(
  messages: Message[]
): AsyncGenerator<string> {
  if (process.env.CLAWZETTEL_MODE === "mock") {
    yield* mockChat(messages);
    return;
  }

  const token = CLAWZETTEL_TOKEN();
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const message = buildPrompt(messages);

  const res = await fetch(`${CLAWZETTEL_URL()}/webhook`, {
    method: "POST",
    headers,
    body: JSON.stringify({ message }),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText);
    throw new Error(`clawzettel error ${res.status}: ${text}`);
  }

  const data = await res.json() as Record<string, unknown>;
  const reply =
    (data.response as string) ??
    (data.reply as string) ??
    (data.message as string) ??
    (data.content as string) ??
    (data.text as string) ??
    JSON.stringify(data);

  yield reply;
}
