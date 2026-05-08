import { defineStore } from "pinia";
import { ref } from "vue";
import { useConnectionStore } from "./connection";

export interface Chat {
  id: string;
  title: string;
  created_at: number;
  updated_at: number;
}

export interface Message {
  id: string;
  chat_id: string;
  role: "user" | "assistant";
  content: string;
  thinking?: string | null;
  created_at: number;
}

export const useChatsStore = defineStore("chats", () => {
  const conn = useConnectionStore();
  const chats = ref<Chat[]>([]);
  const messages = ref<Record<string, Message[]>>({});
  const loading = ref(false);

  async function fetchChats() {
    chats.value = await conn.api<Chat[]>("/chats");
  }

  async function createChat(title?: string): Promise<Chat> {
    const chat = await conn.api<Chat>("/chats", {
      method: "POST",
      body: JSON.stringify({ title }),
    });
    chats.value.unshift(chat);
    return chat;
  }

  async function renameChat(id: string, title: string) {
    await conn.api(`/chats/${id}`, { method: "PATCH", body: JSON.stringify({ title }) });
    const c = chats.value.find((x) => x.id === id);
    if (c) c.title = title;
  }

  async function deleteChat(id: string) {
    await conn.api(`/chats/${id}`, { method: "DELETE" });
    chats.value = chats.value.filter((c) => c.id !== id);
    delete messages.value[id];
  }

  async function fetchMessages(chatId: string) {
    messages.value[chatId] = await conn.api<Message[]>(`/chats/${chatId}/messages`);
  }

  async function* sendMessage(chatId: string, content: string): AsyncGenerator<void> {
    const userMsg: Message = {
      id: crypto.randomUUID(),
      chat_id: chatId,
      role: "user",
      content,
      created_at: Date.now(),
    };
    if (!messages.value[chatId]) messages.value[chatId] = [];
    messages.value[chatId].push(userMsg);

    const placeholder: Message = {
      id: crypto.randomUUID(),
      chat_id: chatId,
      role: "assistant",
      content: "",
      thinking: "",
      created_at: Date.now(),
    };
    messages.value[chatId].push(placeholder);

    const res = await fetch(`${conn.serverUrl}/chats/${chatId}/messages`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...conn.authHeaders(),
      },
      body: JSON.stringify({ content }),
    });

    if (!res.ok || !res.body) throw new Error("Stream failed");

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
        try {
          const parsed = JSON.parse(raw);
          if (parsed.chunk) {
            placeholder.content += parsed.chunk;
            yield;
          }
          if (parsed.thinking) {
            placeholder.thinking = (placeholder.thinking ?? "") + parsed.thinking;
            yield;
          }
          if (parsed.done && parsed.id) {
            placeholder.id = parsed.id;
          }
        } catch {
          // skip malformed
        }
      }
    }

    const chat = chats.value.find((c) => c.id === chatId);
    if (chat) chat.updated_at = Date.now();
  }

  return { chats, messages, loading, fetchChats, createChat, renameChat, deleteChat, fetchMessages, sendMessage };
});
