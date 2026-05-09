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
              <span v-else class="whitespace-pre-wrap">{{ msg.content }}</span>
            </div>
          </div>
        </div>

        <!-- Input -->
        <div class="relative px-4 py-3 border-t border-[var(--color-border)]">
          <!-- Slash command menu -->
          <Transition name="menu">
            <div
              v-if="slashMenuOpen && filteredCommands.length"
              class="absolute bottom-full left-4 right-4 mb-1.5 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl overflow-hidden shadow-lg z-20"
            >
              <div class="px-3 pt-2 pb-1 text-[10px] font-medium text-[var(--color-muted)] uppercase tracking-wide">
                Команды
              </div>
              <div
                v-for="(cmd, i) in filteredCommands"
                :key="cmd.name"
                @mousedown.prevent="selectCommand(cmd)"
                class="flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors"
                :class="i === slashMenuIndex
                  ? 'bg-[var(--color-accent)] text-white'
                  : 'hover:bg-[var(--color-border)]'"
              >
                <span class="font-mono font-semibold text-sm w-12 shrink-0"
                  :class="i === slashMenuIndex ? 'text-white' : 'text-[var(--color-accent)]'"
                >{{ cmd.label }}</span>
                <span class="text-sm" :class="i === slashMenuIndex ? 'text-white/90' : 'text-[var(--color-text)]'">{{ cmd.desc }}</span>
                <span class="ml-auto text-xs opacity-50 truncate hidden sm:block">{{ cmd.example }}</span>
              </div>
            </div>
          </Transition>

          <!-- @ autocomplete menu -->
          <Transition name="menu">
            <div
              v-if="atMenuOpen && filteredNotes.length"
              class="absolute bottom-full left-4 right-4 mb-1.5 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl overflow-hidden shadow-lg z-20 max-h-52 overflow-y-auto"
            >
              <div class="px-3 pt-2 pb-1 text-[10px] font-medium text-[var(--color-muted)] uppercase tracking-wide">
                Заметки
              </div>
              <div
                v-for="(note, i) in filteredNotes"
                :key="note"
                @mousedown.prevent="selectNote(note)"
                class="flex items-center gap-2.5 px-3 py-2 cursor-pointer transition-colors"
                :class="i === atMenuIndex
                  ? 'bg-[var(--color-accent)] text-white'
                  : 'hover:bg-[var(--color-border)]'"
              >
                <FileText class="size-3.5 shrink-0 opacity-60" />
                <span class="font-mono text-xs truncate">{{ note }}</span>
              </div>
            </div>
          </Transition>

          <!-- Delete note confirmation bar -->
          <Transition name="menu">
            <div
              v-if="pendingDeleteNote"
              class="absolute bottom-full left-4 right-4 mb-1.5 bg-red-50 dark:bg-red-950 border border-red-200 dark:border-red-800 rounded-xl px-4 py-3 z-20 flex items-center gap-3"
            >
              <Trash2 class="size-4 text-red-500 shrink-0" />
              <span class="text-sm flex-1 text-red-700 dark:text-red-300">
                Удалить заметку <span class="font-mono font-medium">{{ pendingDeleteNote }}</span>?
              </span>
              <button
                @click="cancelDelete"
                class="text-sm text-[var(--color-muted)] hover:text-[var(--color-text)] px-2 py-1 rounded-lg hover:bg-[var(--color-border)] transition-colors"
              >Отмена</button>
              <button
                @click="confirmDeleteNote"
                class="text-sm bg-red-500 hover:bg-red-600 text-white px-3 py-1 rounded-lg transition-colors font-medium"
              >Удалить</button>
            </div>
          </Transition>

          <form @submit.prevent="sendMessage" class="flex gap-2">
            <textarea
              ref="textareaEl"
              v-model="input"
              @keydown="handleKeydown"
              rows="1"
              placeholder="Сообщение… или /new /find /upd /del /web"
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
import { Plus, Send, Trash2, ChevronLeft, ChevronDown, MessageSquare, Brain, Pencil, FileText } from "lucide-vue-next";
import { marked } from "marked";
import { useChatsStore } from "@/stores/chats";
import { useNotesStore } from "@/stores/notes";
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
const notesStore = useNotesStore();
const route = useRoute();
const router = useRouter();

const activeChatId = ref<string | null>((route.params.id as string) ?? null);
const input = ref("");
const streaming = ref(false);
const streamingMsgId = ref<string | null>(null);
const messagesEl = ref<HTMLElement | null>(null);
const thinkingEl = ref<HTMLElement | null>(null);
const textareaEl = ref<HTMLTextAreaElement | null>(null);
const renamingChatId = ref<string | null>(null);
const renameInputValue = ref("");
const renameInputEl = ref<HTMLInputElement | null>(null);
const listRenameInputEl = ref<HTMLInputElement | null>(null);

// Slash command state
const slashMenuOpen = ref(false);
const slashMenuIndex = ref(0);
const atMenuOpen = ref(false);
const atMenuIndex = ref(0);
const pendingDeleteNote = ref<string | null>(null);

const COMMANDS = [
  { name: "new", label: "/new", desc: "Создать новую заметку", example: "/new основные черты цетелькастена" },
  { name: "find", label: "/find", desc: "Найти в заметках", example: "/find атомарность" },
  { name: "upd", label: "/upd", desc: "Обновить заметку", example: "/upd @zettel.md добавь ссылки" },
  { name: "del", label: "/del", desc: "Удалить заметку", example: "/del @zettel.md" },
  { name: "web", label: "/web", desc: "Найти в интернете", example: "/web второй мозг и цеттелькастен" },
] as const;

const isMobile = computed(() => window.innerWidth < 768);
const activeChat = computed(() => store.chats.find((c) => c.id === activeChatId.value));
const messages = computed(() => (activeChatId.value ? store.messages[activeChatId.value] ?? [] : []));

const filteredCommands = computed(() => {
  const m = input.value.match(/^\/(\w*)$/);
  if (!m) return [];
  const f = m[1].toLowerCase();
  return COMMANDS.filter((c) => c.name.startsWith(f));
});

const filteredNotes = computed(() => {
  const m = input.value.match(/@([\w\-./ ]*)$/);
  if (!m) return [];
  const f = m[1].toLowerCase().trim();
  return notesStore.files.filter((p) => p.toLowerCase().includes(f)).slice(0, 8);
});

watch(input, () => {
  const isSlashTyping = /^\/\w*$/.test(input.value);
  slashMenuOpen.value = isSlashTyping && filteredCommands.value.length > 0;
  if (!slashMenuOpen.value) slashMenuIndex.value = 0;

  const hasCommand = /^\/(upd|del|new|find|web)\s/.test(input.value);
  const hasAt = /@[\w\-./ ]*$/.test(input.value) && input.value.includes("@");
  atMenuOpen.value = hasCommand && hasAt && filteredNotes.value.length > 0;
  if (!atMenuOpen.value) atMenuIndex.value = 0;
});

function selectCommand(cmd: (typeof COMMANDS)[number]) {
  input.value = `/${cmd.name} `;
  slashMenuOpen.value = false;
  nextTick(() => textareaEl.value?.focus());
}

function selectNote(path: string) {
  input.value = input.value.replace(/@[\w\-./ ]*$/, `@${path} `);
  atMenuOpen.value = false;
  nextTick(() => textareaEl.value?.focus());
}

function handleKeydown(e: KeyboardEvent) {
  if (slashMenuOpen.value && filteredCommands.value.length > 0) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      slashMenuIndex.value = (slashMenuIndex.value + 1) % filteredCommands.value.length;
      return;
    }
    if (e.key === "ArrowUp") {
      e.preventDefault();
      slashMenuIndex.value = (slashMenuIndex.value - 1 + filteredCommands.value.length) % filteredCommands.value.length;
      return;
    }
    if (e.key === "Tab" || (e.key === "Enter" && !e.shiftKey)) {
      e.preventDefault();
      selectCommand(filteredCommands.value[slashMenuIndex.value]);
      return;
    }
    if (e.key === "Escape") {
      slashMenuOpen.value = false;
      return;
    }
  }

  if (atMenuOpen.value && filteredNotes.value.length > 0) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      atMenuIndex.value = (atMenuIndex.value + 1) % filteredNotes.value.length;
      return;
    }
    if (e.key === "ArrowUp") {
      e.preventDefault();
      atMenuIndex.value = (atMenuIndex.value - 1 + filteredNotes.value.length) % filteredNotes.value.length;
      return;
    }
    if (e.key === "Tab" || (e.key === "Enter" && !e.shiftKey)) {
      e.preventDefault();
      selectNote(filteredNotes.value[atMenuIndex.value]);
      return;
    }
    if (e.key === "Escape") {
      atMenuOpen.value = false;
      return;
    }
  }

  if (e.key === "Escape" && pendingDeleteNote.value) {
    cancelDelete();
    return;
  }

  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
}

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
  // Prefetch notes list for @ autocomplete
  notesStore.fetchFiles().catch(() => {});
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

function cancelDelete() {
  pendingDeleteNote.value = null;
  input.value = "";
  nextTick(() => textareaEl.value?.focus());
}

async function confirmDeleteNote() {
  const path = pendingDeleteNote.value;
  if (!path) return;
  pendingDeleteNote.value = null;
  input.value = "";
  try {
    await notesStore.deleteNote(path);
  } catch {
    // silent — notes store handles errors
  }
}

async function sendMessage() {
  const text = input.value.trim();
  if (!text || !activeChatId.value || streaming.value) return;

  slashMenuOpen.value = false;
  atMenuOpen.value = false;

  // Handle /del separately: show confirmation bar, don't send to AI
  const delMatch = text.match(/^\/del\s+@([\w\-./]+\.md)\s*$/i);
  if (delMatch) {
    pendingDeleteNote.value = delMatch[1];
    return;
  }

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

.menu-enter-active,
.menu-leave-active {
  transition: opacity 0.1s ease, transform 0.1s ease;
}
.menu-enter-from,
.menu-leave-to {
  opacity: 0;
  transform: translateY(4px);
}
</style>
