import OpenAI from "openai";
import { readdir, readFile, writeFile, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { join } from "path";
import { gitCommitAndPush } from "./git";

export interface Message {
  role: string;
  content: string;
}

export interface ChatChunk {
  type: "thinking" | "text";
  text: string;
}

function notesRoot(): string {
  return process.env.NOTES_REPO_PATH ?? join(process.cwd(), "notes");
}

function buildSystemPrompt(): string {
  const date = new Date().toISOString().split("T")[0];
  return `Ты — AI-ассистент, встроенный в персональную систему управления знаниями (Zettelkasten).

Стратегия работы с запросами:
1. На ЛЮБОЙ информационный вопрос — сначала выполни search_notes, чтобы найти релевантные заметки, и только потом отвечай
2. Если в заметках ничего нет — ответь на основе своих знаний, но предложи создать заметку
3. Если пользователь явно просит поискать в интернете или использует /web — вызови web_search

Если в сообщении есть @<файл> — немедленно прочитай эту заметку через read_note и используй её содержимое как контекст для ответа.

Slash-команды пользователя (выполняй немедленно):
- /new <тема> → придумай имя файла (английский kebab-case, .md) и создай заметку через create_note
- /find <запрос> → найди через search_notes, покажи результаты
- /upd @<файл> <инструкция> → прочитай заметку через read_note, примень правки, сохрани через update_note
- /web <запрос> → найди через web_search, процитируй источники

Правила работы с заметками:
- Имя файла: на английском через дефис, например "zettelkasten-method.md" или "programming/rust-types.md"
- Формат: Markdown, первая строка — заголовок # Название
- После создания/изменения заметки подтверди действие

Текущая дата: ${date}`;
}

const TOOLS: OpenAI.Chat.ChatCompletionTool[] = [
  {
    type: "function",
    function: {
      name: "list_notes",
      description: "Показать список всех заметок в Zettelkasten",
      parameters: { type: "object" as const, properties: {}, required: [] },
    },
  },
  {
    type: "function",
    function: {
      name: "read_note",
      description: "Прочитать содержимое заметки",
      parameters: {
        type: "object" as const,
        properties: {
          path: { type: "string", description: "Путь к файлу заметки (например, 'zettelkasten.md')" },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_note",
      description: "Создать новую заметку в Zettelkasten",
      parameters: {
        type: "object" as const,
        properties: {
          path: { type: "string", description: "Путь для новой заметки (например, 'topic/note-name.md')" },
          content: { type: "string", description: "Содержимое заметки в формате Markdown" },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_note",
      description: "Обновить содержимое существующей заметки",
      parameters: {
        type: "object" as const,
        properties: {
          path: { type: "string", description: "Путь к заметке" },
          content: { type: "string", description: "Новое содержимое в Markdown" },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_notes",
      description: "Найти заметки по тексту запроса",
      parameters: {
        type: "object" as const,
        properties: {
          query: { type: "string", description: "Поисковый запрос" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "web_search",
      description: "Найти информацию в интернете. Используй когда пользователь явно просит поискать в вебе или использует /web команду",
      parameters: {
        type: "object" as const,
        properties: {
          query: { type: "string", description: "Поисковый запрос" },
        },
        required: ["query"],
      },
    },
  },
];

async function listAllNotes(): Promise<string[]> {
  const root = notesRoot();
  if (!existsSync(root)) return [];
  async function walk(dir: string, base = ""): Promise<string[]> {
    const entries = await readdir(dir, { withFileTypes: true });
    const results: string[] = [];
    for (const entry of entries) {
      if (entry.name.startsWith(".")) continue;
      const rel = base ? `${base}/${entry.name}` : entry.name;
      if (entry.isDirectory()) results.push(...(await walk(join(dir, entry.name), rel)));
      else if (entry.name.endsWith(".md")) results.push(rel);
    }
    return results;
  }
  return walk(root);
}

async function executeTool(name: string, input: Record<string, string>): Promise<string> {
  const root = notesRoot();
  switch (name) {
    case "list_notes": {
      const notes = await listAllNotes();
      return notes.length ? notes.join("\n") : "Заметок нет";
    }
    case "read_note": {
      const fullPath = join(root, input.path);
      if (!existsSync(fullPath)) return `Заметка не найдена: ${input.path}`;
      return readFile(fullPath, "utf-8");
    }
    case "create_note": {
      const fullPath = join(root, input.path);
      await mkdir(join(fullPath, ".."), { recursive: true });
      await writeFile(fullPath, input.content, "utf-8");
      await gitCommitAndPush(`create: ${input.path}`);
      return `Создана заметка: ${input.path}`;
    }
    case "update_note": {
      const fullPath = join(root, input.path);
      if (!existsSync(fullPath)) return `Заметка не найдена: ${input.path}`;
      await writeFile(fullPath, input.content, "utf-8");
      await gitCommitAndPush(`update: ${input.path}`);
      return `Обновлена заметка: ${input.path}`;
    }
    case "search_notes": {
      const q = input.query.toLowerCase();
      const notes = await listAllNotes();
      const results: string[] = [];
      for (const file of notes) {
        const text = await readFile(join(root, file), "utf-8");
        if (text.toLowerCase().includes(q)) {
          const idx = text.toLowerCase().indexOf(q);
          const excerpt = text.slice(Math.max(0, idx - 60), idx + 120).replace(/\n/g, " ").trim();
          results.push(`${file}: ...${excerpt}...`);
        }
      }
      return results.length ? results.join("\n\n") : "Ничего не найдено";
    }
    case "web_search": {
      const mcpKey = process.env.ZAI_MCP_KEY ?? process.env.GLM_API_KEY;
      if (!mcpKey) return "Ошибка: ZAI_MCP_KEY не задан";
      try {
        const res = await fetch("https://api.z.ai/api/mcp/web_search_prime/mcp", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json, text/event-stream",
            Authorization: `Bearer ${mcpKey}`,
          },
          body: JSON.stringify({
            jsonrpc: "2.0",
            method: "tools/call",
            id: 1,
            params: {
              name: "web_search_prime",
              arguments: {
                search_query: input.query,
                location: "ru",
                content_size: "medium",
              },
            },
          }),
        });
        if (!res.ok) return `Ошибка веб-поиска: ${res.status}`;
        const text = await res.text();
        // Parse SSE: find last data: line
        const dataLine = text.split("\n").filter((l) => l.startsWith("data:")).pop();
        if (!dataLine) return "Ошибка веб-поиска: пустой ответ";
        const envelope = JSON.parse(dataLine.slice(5)) as {
          result?: { content?: Array<{ type: string; text: string }>; isError?: boolean };
          error?: { message: string };
        };
        if (envelope.error) return `Ошибка веб-поиска: ${envelope.error.message}`;
        const content = envelope.result?.content ?? [];
        if (envelope.result?.isError) return `Ошибка веб-поиска: ${content[0]?.text ?? "неизвестная ошибка"}`;
        const resultText = content.map((c) => c.text).join("\n");
        return resultText || "Ничего не найдено в интернете";
      } catch (e) {
        return `Ошибка веб-поиска: ${e}`;
      }
    }
    default:
      return `Неизвестный инструмент: ${name}`;
  }
}

async function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function* mockChat(messages: Message[]): AsyncGenerator<ChatChunk> {
  const last = messages.findLast((m) => m.role === "user")?.content ?? "";
  const lower = last.toLowerCase();

  const thinkText = `Анализирую запрос пользователя: "${last}"\nОпределяю намерение и подбираю ответ...`;
  for (const ch of thinkText) {
    yield { type: "thinking", text: ch };
    await sleep(8);
  }

  let reply: string;
  if (lower.includes("привет") || lower.includes("hello") || lower.includes("hi")) {
    reply = "Привет! Я mock-версия для локального тестирования. Настройте GLM_API_KEY для полного функционала.";
  } else if (lower.includes("создай") || lower.includes("create")) {
    reply = "В реальном режиме я бы создал заметку прямо сейчас через инструменты. Настройте GLM_API_KEY.";
  } else {
    reply = `Получил: _«${last}»_\n\nЭто local/mock режим. Настройте **GLM_API_KEY** для полноценной работы с Zettelkasten.`;
  }

  for (const word of reply.split(/(\s+)/)) {
    yield { type: "text", text: word };
    await sleep(25 + Math.random() * 30);
  }
}

export async function generateChatTitle(userMessage: string): Promise<string> {
  if (process.env.CLAWZETTEL_MODE === "mock") {
    return userMessage.slice(0, 40);
  }
  const apiKey = process.env.GLM_API_KEY;
  if (!apiKey) return userMessage.slice(0, 40);

  const client = new OpenAI({
    apiKey,
    baseURL: process.env.GLM_BASE_URL ?? "https://api.z.ai/api/coding/paas/v4",
  });
  const model = process.env.GLM_TITLE_MODEL ?? process.env.GLM_MODEL ?? "GLM-5-Turbo";

  try {
    const res = await client.chat.completions.create({
      model,
      messages: [
        {
          role: "user",
          content: `Придумай короткое название (3-5 слов) для чата, где первое сообщение пользователя: "${userMessage.slice(0, 300)}". Ответь ТОЛЬКО названием — без кавычек, пояснений и рассуждений.`,
        },
      ],
      stream: false,
    });
    let title = (res.choices[0]?.message?.content ?? "").trim();
    // Strip any <think>...</think> reasoning blocks
    title = title.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
    return title || userMessage.slice(0, 40);
  } catch {
    return userMessage.slice(0, 40);
  }
}

export async function* clawzettelChat(messages: Message[]): AsyncGenerator<ChatChunk> {
  if (process.env.CLAWZETTEL_MODE === "mock") {
    yield* mockChat(messages);
    return;
  }

  const apiKey = process.env.GLM_API_KEY;
  if (!apiKey) throw new Error("GLM_API_KEY not set");

  const client = new OpenAI({
    apiKey,
    baseURL: process.env.GLM_BASE_URL ?? "https://api.z.ai/api/coding/paas/v4",
  });

  const model = process.env.GLM_MODEL ?? "GLM-5-Turbo";

  let glmMessages: OpenAI.Chat.ChatCompletionMessageParam[] = [
    { role: "system", content: buildSystemPrompt() },
    ...messages.map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    })),
  ];

  while (true) {
    const stream = await client.chat.completions.create({
      model,
      messages: glmMessages,
      tools: TOOLS,
      tool_choice: "auto",
      stream: true,
    });

    let stopReason: string | null = null;
    const toolCallsMap: Record<number, { id: string; name: string; argsJson: string }> = {};
    let hasReasoningField = false;
    let parseBuffer = "";
    let inThink = false;
    let turnContent = "";

    for await (const chunk of stream) {
      const delta = chunk.choices[0]?.delta as any;
      stopReason = chunk.choices[0]?.finish_reason ?? stopReason;

      // GLM-Z1 / DeepSeek-R1 style: reasoning_content as separate field
      if (delta?.reasoning_content) {
        hasReasoningField = true;
        yield { type: "thinking", text: delta.reasoning_content };
      }

      // Tool calls accumulation
      if (delta?.tool_calls) {
        for (const tc of delta.tool_calls) {
          const idx: number = tc.index ?? 0;
          if (!toolCallsMap[idx]) toolCallsMap[idx] = { id: "", name: "", argsJson: "" };
          if (tc.id) toolCallsMap[idx].id = tc.id;
          if (tc.function?.name) toolCallsMap[idx].name = tc.function.name;
          if (tc.function?.arguments) toolCallsMap[idx].argsJson += tc.function.arguments;
        }
      }

      // Content
      if (delta?.content) {
        const text: string = delta.content;
        turnContent += text;

        if (hasReasoningField) {
          // Reasoning is in separate field — content is clean text
          yield { type: "text", text };
        } else {
          // Parse <think>...</think> tags inline
          parseBuffer += text;

          while (parseBuffer.length > 0) {
            if (inThink) {
              const endIdx = parseBuffer.indexOf("</think>");
              if (endIdx !== -1) {
                if (endIdx > 0) yield { type: "thinking", text: parseBuffer.slice(0, endIdx) };
                parseBuffer = parseBuffer.slice(endIdx + 8);
                inThink = false;
              } else {
                const safe = Math.max(0, parseBuffer.length - 8);
                if (safe > 0) {
                  yield { type: "thinking", text: parseBuffer.slice(0, safe) };
                  parseBuffer = parseBuffer.slice(safe);
                }
                break;
              }
            } else {
              const startIdx = parseBuffer.indexOf("<think>");
              if (startIdx !== -1) {
                if (startIdx > 0) yield { type: "text", text: parseBuffer.slice(0, startIdx) };
                parseBuffer = parseBuffer.slice(startIdx + 7);
                inThink = true;
              } else {
                const safe = Math.max(0, parseBuffer.length - 7);
                if (safe > 0) {
                  yield { type: "text", text: parseBuffer.slice(0, safe) };
                  parseBuffer = parseBuffer.slice(safe);
                }
                break;
              }
            }
          }
        }
      }
    }

    // Flush remaining parse buffer
    if (parseBuffer.length > 0) {
      yield { type: inThink ? "thinking" : "text", text: parseBuffer };
    }

    const toolCalls = Object.values(toolCallsMap).filter((tc) => tc.name);
    if (stopReason !== "tool_calls" || toolCalls.length === 0) break;

    // Add assistant message with tool calls
    glmMessages.push({
      role: "assistant",
      content: turnContent || null,
      tool_calls: toolCalls.map((tc) => ({
        id: tc.id,
        type: "function" as const,
        function: { name: tc.name, arguments: tc.argsJson },
      })),
    } as OpenAI.Chat.ChatCompletionMessageParam);

    // Execute tools and add results
    for (const tc of toolCalls) {
      let input: Record<string, string> = {};
      try {
        input = JSON.parse(tc.argsJson);
      } catch {
        // ignore parse error
      }
      const result = await executeTool(tc.name, input);
      glmMessages.push({
        role: "tool",
        tool_call_id: tc.id,
        content: result,
      } as OpenAI.Chat.ChatCompletionMessageParam);
    }
  }
}
