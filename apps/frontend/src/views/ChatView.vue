<template>
  <div class="flex h-full pb-14 md:pb-0">
    <!-- Chat list panel -->
    <div
      class="flex flex-col border-r border-[var(--color-border)] bg-[var(--color-surface)]"
      :class="activeChatId && isMobile ? 'hidden' : 'w-full md:w-64 lg:w-72 shrink-0'"
    >
      <div class="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)]">
        <h2 class="font-semibold text-sm">Chats</h2>
        <button
          @click="newChat"
          class="rounded-lg p-1.5 hover:bg-[var(--color-border)] text-[var(--color-muted)] hover:text-[var(--color-text)] transition-colors"
          title="New chat"
        >
          <Plus class="size-4" />
        </button>
      </div>
      <div class="flex-1 overflow-y-auto">
        <div v-if="store.chats.length === 0" class="px-4 py-8 text-center text-sm text-[var(--color-muted)]">
          No chats yet. Start one!
        </div>
        <div
          v-for="chat in store.chats"
          :key="chat.id"
          @click="openChat(chat.id)"
          @dblclick.stop="startRename(chat.id)"
          class="group w-full text-left px-4 py-3 text-sm hover:bg-[var(--color-border)] transition-colors border-b border-[var(--color-border)] last:border-0 cursor-pointer"
          :class="chat.id === activeChatId ? 'bg-[var(--color-border)] font-medium' : 'text-[var(--color-muted)]'"
        >
          <template v-if="renamingChatId === chat.id">
            <input
              ref="listRenameInputEl"
              v-model="renameInputValue"
              @keydown.enter.prevent="commitRename"
              @keydown.escape.prevent="cancelRename"
              @blur="commitRename"
              @click.stop
              class="w-full text-sm font-medium bg-transparent border-b border-[var(--color-accent)] outline-none px-0.5"
            />
          </template>
          <template v-else>
            <div class="flex items-center gap-1">
              <span class="truncate flex-1">{{ chat.title }}</span>
              <button
                @click.stop="startRename(chat.id)"
                class="opacity-0 group-hover:opacity-100 transition-opacity text-[var(--color-muted)] hover:text-[var(--color-text)] p-0.5 shrink-0"
                title="Переименовать"
              >
                <Pencil class="size-3" />
              </button>
            </div>
          </template>
          <div class="text-xs text-[var(--color-muted)] mt-0.5">
            {{ formatDate(chat.updated_at) }}
          </div>
        </div>
      </div>
    </div>

    <!-- Chat window -->
    <div
      class="flex flex-col flex-1 min-w-0"
      :class="!activeChatId && isMobile ? 'hidden' : ''"
    >
      <template v-if="activeChatId">
        <div class="flex items-center gap-2 px-4 py-3 border-b border-[var(--color-border)]">
          <button
            v-if="isMobile"
            @click="activeChatId = null"
            class="text-[var(--color-muted)] hover:text-[var(--color-text)]"
          >
            <ChevronLeft class="size-5" />
          </button>
          <template v-if="renamingChatId === activeChatId">
            <input
              ref="renameInputEl"
              v-model="renameInputValue"
              @keydown.enter.prevent="commitRename"
              @keydown.escape.prevent="cancelRename"
              @blur="commitRename"
              class="flex-1 text-sm font-semibold bg-transparent border-b border-[var(--color-accent)] outline-none px-0.5"
            />
          </template>
          <template v-else>
            <h2 class="font-semibold text-sm truncate flex-1">{{ activeChat?.title ?? "Chat" }}</h2>
            <button
              @click="startRename(activeChatId!)"
              class="text-[var(--color-muted)] hover:text-[var(--color-text)] transition-colors p-1 shrink-0"
              title="Переименовать"
            >
              <Pencil class="size-3.5" />
            </button>
          </template>
          <button
            @click="confirmDeleteChat"
            class="text-[var(--color-muted)] hover:text-red-500 transition-colors p-1 shrink-0"
          >
            <Trash2 class="size-4" />
          </button>
        </div>

        <!-- Messages -->
        <div ref="messagesEl" class="flex-1 overflow-y-auto px-4 py-4 space-y-4">
          <div v-if="!messages.length" class="text-center text-sm text-[var(--color-muted)] mt-12">
            Send a message to start the conversation
          </div>

          <div
            v-for="msg in messages"
            :key="msg.id"
            class="flex flex-col"
            :class="msg.role === 'user' ? 'items-end' : 'items-start'"
          >
            <!-- Thinking block (assistant only) -->
            <template v-if="msg.role === 'assistant'">
              <!-- Streaming indicator: no content yet -->
              <div
                v-if="isStreamingMsg(msg) && !msg.content && !msg.thinking"
                class="flex items-center gap-1.5 text-xs text-[var(--color-muted)] px-1 mb-1"
              >
                <span class="inline-flex gap-1">
                  <span class="w-1.5 h-1.5 rounded-full bg-current animate-bounce [animation-delay:0ms]"></span>
                  <span class="w-1.5 h-1.5 rounded-full bg-current animate-bounce [animation-delay:150ms]"></span>
                  <span class="w-1.5 h-1.5 rounded-full bg-current animate-bounce [animation-delay:300ms]"></span>
                </span>
              </div>

              <!-- Thinking block -->
              <details
                v-if="msg.thinking"
                :open="isStreamingMsg(msg)"
                class="mb-1.5 max-w-[80%] w-fit"
              >
                <summary
                  class="flex items-center gap-1.5 text-xs text-[var(--color-muted)] cursor-pointer select-none list-none px-2 py-1 rounded-lg hover:bg-[var(--color-border)] transition-colors w-fit"
                >
                  <Brain class="size-3 shrink-0" />
                  <span>{{ isStreamingMsg(msg) ? 'Рассуждение...' : 'Рассуждение' }}</span>
                  <ChevronDown class="size-3 shrink-0 opacity-50 details-arrow" />
                </summary>
                <div
                  ref="thinkingEl"
                  class="mt-1 px-3 py-2 text-xs text-[var(--color-muted)] font-mono whitespace-pre-wrap bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl max-h-56 overflow-y-auto"
                >{{ msg.thinking }}</div>
              </details>
            </template>

            <!-- Message bubble -->
            <div
              v-if="msg.content || msg.role === 'user'"
              class="max-w-[80%] rounded-2xl px-4 py-2.5 text-sm"
              :class="msg.role === 'user'
                ? 'bg-[var(--color-accent)] text-white rounded-br-sm'
                : 'bg-[var(--color-surface)] border border-[var(--color-border)] text-[var(--color-text)] rounded-bl-sm'"
            >
              <div
                v-if="msg.role === 'assistant'"
                class="prose prose-sm max-w-none dark:prose-invert"
                v-html="renderMd(msg.content)"
              />
              <span v-else>{{ msg.content }}</span>
            </div>
          </div>
        </div>

        <!-- Input -->
        <div class="px-4 py-3 border-t border-[var(--color-border)]">
          <form @submit.prevent="sendMessage" class="flex gap-2">
            <textarea
              v-model="input"
              @keydown.enter.exact.prevent="sendMessage"
              rows="1"
              placeholder="Type a message…"
              class="flex-1 resize-none rounded-xl border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--color-accent)] max-h-32 overflow-y-auto"
              :disabled="streaming"
            />
            <button
              type="submit"
              :disabled="!input.trim() || streaming"
              class="rounded-xl bg-[var(--color-accent)] text-white px-4 py-2 text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed hover:bg-[var(--color-accent-hover)] transition-colors"
            >
              <Send class="size-4" />
            </button>
          </form>
        </div>
      </template>

      <div v-else class="flex-1 flex items-center justify-center text-[var(--color-muted)] text-sm">
        <div class="text-center space-y-2">
          <MessageSquare class="size-10 mx-auto opacity-30" />
          <p>Select a chat or create a new one</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, nextTick, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { Plus, Send, Trash2, ChevronLeft, ChevronDown, MessageSquare, Brain, Pencil } from "lucide-vue-next";
import { marked } from "marked";
import { useChatsStore } from "@/stores/chats";
import type { Message } from "@/stores/chats";

marked.use({
  renderer: {
    link({ href, title, text }) {
      const titleAttr = title ? ` title="${title}"` : "";
      return `<a href="${href}"${titleAttr} target="_blank" rel="noopener noreferrer">${text}</a>`;
    },
  },
});

const store = useChatsStore();
const route = useRoute();
const router = useRouter();

const activeChatId = ref<string | null>((route.params.id as string) ?? null);
const input = ref("");
const streaming = ref(false);
const streamingMsgId = ref<string | null>(null);
const messagesEl = ref<HTMLElement | null>(null);
const thinkingEl = ref<HTMLElement | null>(null);
const renamingChatId = ref<string | null>(null);
const renameInputValue = ref("");
const renameInputEl = ref<HTMLInputElement | null>(null);
const listRenameInputEl = ref<HTMLInputElement | null>(null);

const isMobile = computed(() => window.innerWidth < 768);
const activeChat = computed(() => store.chats.find((c) => c.id === activeChatId.value));
const messages = computed(() => (activeChatId.value ? store.messages[activeChatId.value] ?? [] : []));

function isStreamingMsg(msg: Message) {
  return streaming.value && msg.id === streamingMsgId.value;
}

function renderMd(content: string): string {
  return marked.parse(content) as string;
}

function formatDate(ts: number): string {
  return new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

async function scrollToBottom() {
  await nextTick();
  if (messagesEl.value) {
    messagesEl.value.scrollTop = messagesEl.value.scrollHeight;
  }
}

async function scrollThinkingToBottom() {
  await nextTick();
  const el = Array.isArray(thinkingEl.value) ? thinkingEl.value[thinkingEl.value.length - 1] : thinkingEl.value;
  if (el) el.scrollTop = el.scrollHeight;
}

onMounted(async () => {
  await store.fetchChats();
  if (activeChatId.value) {
    await store.fetchMessages(activeChatId.value);
    scrollToBottom();
  }
});

watch(activeChatId, async (id) => {
  if (id) {
    router.replace(`/chat/${id}`);
    if (!store.messages[id]) await store.fetchMessages(id);
    scrollToBottom();
  }
});

async function newChat() {
  const chat = await store.createChat("New chat");
  activeChatId.value = chat.id;
}

async function openChat(id: string) {
  activeChatId.value = id;
}

async function startRename(chatId: string) {
  const chat = store.chats.find((c) => c.id === chatId);
  if (!chat) return;
  renamingChatId.value = chatId;
  renameInputValue.value = chat.title;
  await nextTick();
  const el = renameInputEl.value ?? (Array.isArray(listRenameInputEl.value) ? listRenameInputEl.value[0] : listRenameInputEl.value);
  el?.focus();
  el?.select();
}

async function commitRename() {
  const id = renamingChatId.value;
  if (!id) return;
  const title = renameInputValue.value.trim();
  renamingChatId.value = null;
  if (title && title !== store.chats.find((c) => c.id === id)?.title) {
    await store.renameChat(id, title);
  }
}

function cancelRename() {
  renamingChatId.value = null;
}

async function confirmDeleteChat() {
  if (!activeChatId.value) return;
  if (!confirm("Delete this chat?")) return;
  await store.deleteChat(activeChatId.value);
  activeChatId.value = store.chats[0]?.id ?? null;
}

async function sendMessage() {
  const text = input.value.trim();
  if (!text || !activeChatId.value || streaming.value) return;
  input.value = "";
  streaming.value = true;
  try {
    for await (const _ of store.sendMessage(activeChatId.value, text)) {
      const msgs = store.messages[activeChatId.value];
      if (msgs?.length) {
        const last = msgs[msgs.length - 1];
        streamingMsgId.value = last.id;
        if (last.thinking) scrollThinkingToBottom();
      }
      scrollToBottom();
    }
  } finally {
    streaming.value = false;
    streamingMsgId.value = null;
    scrollToBottom();
  }
}
</script>

<style scoped>
details[open] .details-arrow {
  transform: rotate(180deg);
}
.details-arrow {
  transition: transform 0.15s;
}
</style>
