<template>
  <div class="flex h-full pb-14 md:pb-0">
    <!-- Notes list panel -->
    <div
      class="flex flex-col border-r border-[var(--color-border)] bg-[var(--color-surface)]"
      :class="store.currentPath && isMobile ? 'hidden' : 'w-full md:w-64 lg:w-72 shrink-0'"
    >
      <div class="px-4 py-3 border-b border-[var(--color-border)] space-y-2">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold text-sm">Notes</h2>
          <button
            @click="newNote"
            class="rounded-lg p-1.5 hover:bg-[var(--color-border)] text-[var(--color-muted)] hover:text-[var(--color-text)] transition-colors"
            title="New note"
          >
            <Plus class="size-4" />
          </button>
        </div>
        <div class="relative">
          <Search class="absolute left-2.5 top-1/2 -translate-y-1/2 size-3.5 text-[var(--color-muted)]" />
          <input
            v-model="searchQuery"
            @input="handleSearch"
            type="search"
            placeholder="Search…"
            class="w-full pl-8 pr-3 py-1.5 text-xs rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] focus:outline-none focus:ring-2 focus:ring-[var(--color-accent)]"
          />
        </div>
      </div>

      <div class="flex-1 overflow-y-auto">
        <!-- Search results -->
        <template v-if="searchQuery && store.searchResults.length">
          <button
            v-for="result in store.searchResults"
            :key="result.path"
            @click="openNote(result.path)"
            class="w-full text-left px-4 py-3 text-sm hover:bg-[var(--color-border)] transition-colors border-b border-[var(--color-border)] last:border-0"
            :class="result.path === store.currentPath ? 'bg-[var(--color-border)] font-medium' : 'text-[var(--color-muted)]'"
          >
            <div class="truncate font-medium text-[var(--color-text)]">{{ result.path }}</div>
            <div class="text-xs text-[var(--color-muted)] mt-0.5 truncate">{{ result.excerpt }}</div>
          </button>
        </template>
        <div
          v-else-if="searchQuery && !store.searchResults.length"
          class="px-4 py-8 text-center text-sm text-[var(--color-muted)]"
        >
          No results
        </div>

        <!-- File list -->
        <template v-else>
          <div v-if="!store.files.length" class="px-4 py-8 text-center text-sm text-[var(--color-muted)]">
            No notes found
          </div>
          <button
            v-for="file in store.files"
            :key="file"
            @click="openNote(file)"
            class="w-full text-left px-4 py-3 text-sm hover:bg-[var(--color-border)] transition-colors border-b border-[var(--color-border)] last:border-0 truncate"
            :class="file === store.currentPath ? 'bg-[var(--color-border)] font-medium text-[var(--color-text)]' : 'text-[var(--color-muted)]'"
          >
            {{ file }}
          </button>
        </template>
      </div>
    </div>

    <!-- Note editor / viewer -->
    <div class="flex-1 min-w-0 flex flex-col" :class="!store.currentPath && isMobile ? 'hidden' : ''">
      <template v-if="store.currentPath">
        <div class="flex items-center gap-2 px-4 py-3 border-b border-[var(--color-border)]">
          <button
            v-if="isMobile"
            @click="store.currentPath = null"
            class="text-[var(--color-muted)] hover:text-[var(--color-text)]"
          >
            <ChevronLeft class="size-5" />
          </button>
          <span class="text-sm font-medium truncate flex-1">{{ store.currentPath }}</span>
          <div class="flex items-center gap-1">
            <button
              @click="isEditing = !isEditing"
              class="rounded-lg p-1.5 hover:bg-[var(--color-border)] transition-colors text-[var(--color-muted)]"
              :class="isEditing ? 'text-[var(--color-accent)]' : ''"
            >
              <Pencil class="size-4" />
            </button>
            <button
              @click="confirmDelete"
              class="rounded-lg p-1.5 hover:bg-red-50 hover:text-red-500 transition-colors text-[var(--color-muted)]"
            >
              <Trash2 class="size-4" />
            </button>
          </div>
        </div>

        <!-- Viewer -->
        <div v-if="!isEditing" class="flex-1 overflow-y-auto px-6 py-4">
          <div
            class="prose prose-sm max-w-none dark:prose-invert"
            v-html="renderMd(store.currentContent)"
          />
        </div>

        <!-- Editor -->
        <div v-else class="flex-1 flex flex-col">
          <textarea
            v-model="editContent"
            class="flex-1 resize-none px-6 py-4 text-sm font-mono bg-[var(--color-bg)] focus:outline-none text-[var(--color-text)]"
            spellcheck="false"
          />
          <div class="px-4 py-3 border-t border-[var(--color-border)] flex justify-end gap-2">
            <button
              @click="cancelEdit"
              class="rounded-lg px-3 py-1.5 text-sm text-[var(--color-muted)] hover:bg-[var(--color-border)] transition-colors"
            >
              Cancel
            </button>
            <button
              @click="saveNote"
              :disabled="store.loading"
              class="rounded-lg px-3 py-1.5 text-sm bg-[var(--color-accent)] text-white hover:bg-[var(--color-accent-hover)] disabled:opacity-50 transition-colors"
            >
              {{ store.loading ? "Saving…" : "Save" }}
            </button>
          </div>
        </div>
      </template>

      <!-- New note form -->
      <template v-else-if="creatingNew">
        <div class="flex items-center gap-2 px-4 py-3 border-b border-[var(--color-border)]">
          <input
            v-model="newNotePath"
            placeholder="path/to/note.md"
            class="flex-1 text-sm border border-[var(--color-border)] rounded-lg px-3 py-1.5 bg-[var(--color-bg)] focus:outline-none focus:ring-2 focus:ring-[var(--color-accent)]"
            @keydown.enter="createNote"
            @keydown.escape="creatingNew = false"
            ref="newNoteInput"
          />
          <button @click="createNote" class="text-sm text-[var(--color-accent)] font-medium">Create</button>
          <button @click="creatingNew = false" class="text-sm text-[var(--color-muted)]">Cancel</button>
        </div>
        <textarea
          v-model="newNoteContent"
          placeholder="# Note title&#10;&#10;Start writing…"
          class="flex-1 resize-none px-6 py-4 text-sm font-mono bg-[var(--color-bg)] focus:outline-none text-[var(--color-text)]"
        />
      </template>

      <div v-else class="flex-1 flex items-center justify-center text-[var(--color-muted)] text-sm">
        <div class="text-center space-y-2">
          <FileText class="size-10 mx-auto opacity-30" />
          <p>Select a note or create a new one</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, computed, nextTick, onMounted } from "vue";
import { Plus, Search, Pencil, Trash2, ChevronLeft, FileText } from "lucide-vue-next";
import { marked } from "marked";
import { useNotesStore } from "@/stores/notes";

const store = useNotesStore();
const isMobile = computed(() => window.innerWidth < 768);
const isEditing = ref(false);
const editContent = ref("");
const searchQuery = ref("");
const creatingNew = ref(false);
const newNotePath = ref("");
const newNoteContent = ref("");
const newNoteInput = ref<HTMLInputElement | null>(null);
let searchTimer: ReturnType<typeof setTimeout>;

onMounted(() => store.fetchFiles());

watch(() => store.currentPath, (path) => {
  if (path) {
    isEditing.value = false;
    editContent.value = store.currentContent;
  }
});

watch(() => store.currentContent, (c) => {
  if (!isEditing.value) editContent.value = c;
});

function renderMd(content: string): string {
  return marked.parse(content) as string;
}

async function openNote(path: string) {
  await store.openNote(path);
  creatingNew.value = false;
}

function handleSearch() {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    if (searchQuery.value.trim()) store.search(searchQuery.value.trim());
  }, 300);
}

function cancelEdit() {
  isEditing.value = false;
  editContent.value = store.currentContent;
}

async function saveNote() {
  if (!store.currentPath) return;
  await store.saveNote(store.currentPath, editContent.value);
  isEditing.value = false;
}

async function confirmDelete() {
  if (!store.currentPath || !confirm("Delete this note?")) return;
  await store.deleteNote(store.currentPath);
}

async function newNote() {
  creatingNew.value = true;
  store.currentPath = null;
  newNotePath.value = "";
  newNoteContent.value = "";
  await nextTick();
  newNoteInput.value?.focus();
}

async function createNote() {
  if (!newNotePath.value.trim()) return;
  const path = newNotePath.value.trim().endsWith(".md")
    ? newNotePath.value.trim()
    : `${newNotePath.value.trim()}.md`;
  await store.saveNote(path, newNoteContent.value);
  creatingNew.value = false;
  await store.openNote(path);
}
</script>
