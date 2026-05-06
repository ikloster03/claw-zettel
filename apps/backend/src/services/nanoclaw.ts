export interface Message {
  role: string;
  content: string;
}

const NANOCLAW_URL = () =>
  process.env.NANOCLAW_BASE_URL ?? "http://localhost:4000";

async function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function* mockChat(messages: Message[]): AsyncGenerator<string> {
  const last = messages.findLast((m) => m.role === "user")?.content ?? "";
  const lower = last.toLowerCase();

  let reply: string;

  if (lower.includes("привет") || lower.includes("hello") || lower.includes("hi")) {
    reply =
      "Привет! Я mock-версия nanoclaw для локального тестирования. " +
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
      "В реальном режиме я использую nanoclaw для семантического поиска по вашей базе знаний. " +
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
      "> **Сейчас работает local-режим** (mock nanoclaw). " +
      "Подключите реальный nanoclaw-сервер для полного функционала.";
  } else {
    reply =
      `Вы написали: _«${last}»_\n\n` +
      "Я получил ваше сообщение. В **local-режиме** я не подключён к реальному nanoclaw, " +
      "поэтому не могу обработать произвольные запросы к вашей базе знаний.\n\n" +
      "Для полноценной работы запустите nanoclaw-сервер и укажите `NANOCLAW_BASE_URL` в `.env`.\n\n" +
      "А пока — попробуйте вкладку **Notes** для работы с заметками без AI.";
  }

  const words = reply.split(/(\s+)/);
  for (const word of words) {
    yield word;
    await sleep(25 + Math.random() * 30);
  }
}

export async function* nanoclawChat(
  messages: Message[]
): AsyncGenerator<string> {
  if (process.env.NANOCLAW_MODE === "mock") {
    yield* mockChat(messages);
    return;
  }

  const res = await fetch(`${NANOCLAW_URL()}/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ messages }),
  });

  if (!res.ok || !res.body) {
    const text = await res.text().catch(() => res.statusText);
    throw new Error(`nanoclaw error: ${text}`);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      if (!line.startsWith("data:")) continue;
      const raw = line.slice(5).trim();
      if (raw === "[DONE]") return;
      try {
        const parsed = JSON.parse(raw);
        const chunk: string =
          parsed?.choices?.[0]?.delta?.content ??
          parsed?.content ??
          parsed?.chunk ??
          "";
        if (chunk) yield chunk;
      } catch {
        // non-JSON SSE line, skip
      }
    }
  }
}
