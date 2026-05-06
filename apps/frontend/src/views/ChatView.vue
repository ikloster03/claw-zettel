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
        <button
          v-for="chat in store.chats"
          :key="chat.id"
          @click="openChat(chat.id)"
          class="w-full text-left px-4 py-3 text-sm hover:bg-[var(--color-border)] transition-colors border-b border-[var(--color-border)] last:border-0"
          :class="chat.id === activeChatId ? 'bg-[var(--color-border)] font-medium' : 'text-[var(--color-muted)]'"
        >
          <div class="truncate">{{ chat.title }}</div>
          <div class="text-xs text-[var(--color-muted)] mt-0.5">
            {{ formatDate(chat.updated_at) }}
          </div>
        </button>
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
          <h2 class="font-semibold text-sm truncate flex-1">
            {{ activeChat?.title ?? "Chat" }}
          </h2>
          <button
            @click="confirmDeleteChat"
            class="text-[var(--color-muted)] hover:text-red-500 transition-colors p-1"
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
            class="flex"
            :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
          >
            <div
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
import { Plus, Send, Trash2, ChevronLeft, MessageSquare } from "lucide-vue-next";
import { marked } from "marked";
import { useChatsStore } from "@/stores/chats";

const store = useChatsStore();
const route = useRoute();
const router = useRouter();

const activeChatId = ref<string | null>((route.params.id as string) ?? null);
const input = ref("");
const streaming = ref(false);
const messagesEl = ref<HTMLElement | null>(null);

const isMobile = computed(() => window.innerWidth < 768);
const activeChat = computed(() => store.chats.find((c) => c.id === activeChatId.value));
const messages = computed(() => (activeChatId.value ? store.messages[activeChatId.value] ?? [] : []));

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
      scrollToBottom();
    }
  } finally {
    streaming.value = false;
    scrollToBottom();
  }
}
</script>
