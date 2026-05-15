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
          <div class="flex items-center gap-0.5">
            <button
              v-if="allFolderPaths.length"
              @click="toggleAllFolders"
              class="rounded-lg p-1.5 hover:bg-[var(--color-border)] text-[var(--color-muted)] hover:text-[var(--color-text)] transition-colors"
              :title="allExpanded ? 'Collapse all' : 'Expand all'"
            >
              <ChevronsDownUp v-if="allExpanded" class="size-4" />
              <ChevronsUpDown v-else class="size-4" />
            </button>
            <button
              @click="newNote"
              class="rounded-lg p-1.5 hover:bg-[var(--color-border)] text-[var(--color-muted)] hover:text-[var(--color-text)] transition-colors"
              title="New note"
            >
              <Plus class="size-4" />
            </button>
          </div>
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

        <!-- File tree -->
        <template v-else>
          <div v-if="!store.files.length" class="px-4 py-8 text-center text-sm text-[var(--color-muted)]">
            No notes found
          </div>
          <NoteTree
            v-else
            :nodes="fileTree"
            :depth="0"
            :expanded-folders="expandedFolders"
            :current-path="store.currentPath"
            @open-note="openNote"
            @toggle-folder="toggleFolder"
          />
        </template>
      </div>
    </div>

    <!-- Note editor / viewer -->
    <div class="flex-1 min-w-0 flex flex-col" :class="!store.currentPath && isMobile ? 'hidden' : ''">
      <template v-if="store.currentPath">
        <div class="flex items-center gap-2 px-4 py-3 border-b border-[var(--color-border)]">
          <button
            v-if="isMobile"
            @click="goBack"
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
            @click="handleContentClick"
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
import { useRoute, useRouter } from "vue-router";
import { Plus, Search, Pencil, Trash2, ChevronLeft, FileText, ChevronsUpDown, ChevronsDownUp } from "lucide-vue-next";
import { marked, type Tokens } from "marked";
import { useNotesStore } from "@/stores/notes";
import NoteTree from "@/components/notes/NoteTree.vue";

marked.use({
  extensions: [
    {
      name: "wikilink",
      level: "inline" as const,
      start(src: string) { return src.indexOf("[["); },
      tokenizer(src: string) {
        const match = src.match(/^\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/);
        if (match) return { type: "wikilink", raw: match[0], path: match[1].trim(), label: (match[2] ?? match[1]).trim() };
      },
      renderer(token: Tokens.Generic) {
        const { path, label } = token as Tokens.Generic & { path: string; label: string };
        return `<a href="${path}" data-internal="true">${label}</a>`;
      },
    },
  ],
  renderer: {
    html({ text }: { text: string }) {
      return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    },
    link({ href, title, text }: { href: string; title?: string | null; text: string }) {
      const isExternal = /^https?:\/\//.test(href) || href.startsWith("//");
      if (isExternal) {
        const t = title ? ` title="${title}"` : "";
        return `<a href="${href}"${t} target="_blank" rel="noopener noreferrer">${text}</a>`;
      }
      return `<a href="${href}" data-internal="true">${text}</a>`;
    },
  },
});

export interface TreeNode {
  type: "folder" | "file";
  name: string;
  path: string;
  children: TreeNode[];
}

function buildTree(files: string[], fileMtimes: Record<string, number>): TreeNode[] {
  const root: TreeNode[] = [];
  for (const filePath of files) {
    const segments = filePath.split("/");
    let currentLevel = root;
    for (let i = 0; i < segments.length - 1; i++) {
      const folderPath = segments.slice(0, i + 1).join("/");
      let folder = currentLevel.find(n => n.type === "folder" && n.path === folderPath);
      if (!folder) {
        folder = { type: "folder", name: segments[i], path: folderPath, children: [] };
        currentLevel.push(folder);
      }
      currentLevel = folder.children;
    }
    const fileName = segments[segments.length - 1];
    currentLevel.push({ type: "file", name: fileName, path: filePath, children: [] });
  }
  function sortLevel(nodes: TreeNode[]): void {
    nodes.sort((a, b) => {
      if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
      if (a.type === "file") return (fileMtimes[b.path] ?? 0) - (fileMtimes[a.path] ?? 0);
      return a.name.localeCompare(b.name);
    });
    for (const node of nodes) {
      if (node.type === "folder") sortLevel(node.children);
    }
  }
  sortLevel(root);
  return root;
}

const store = useNotesStore();
const route = useRoute();
const router = useRouter();
const isMobile = computed(() => window.innerWidth < 768);
const isEditing = ref(false);
const editContent = ref("");
const searchQuery = ref("");
const creatingNew = ref(false);
const newNotePath = ref("");
const newNoteContent = ref("");
const newNoteInput = ref<HTMLInputElement | null>(null);
let searchTimer: ReturnType<typeof setTimeout>;

const LS_EXPANDED_KEY = "cz_notes_expanded_folders";

function loadExpandedFromStorage(): Set<string> {
  try {
    const stored = localStorage.getItem(LS_EXPANDED_KEY);
    if (stored) return new Set(JSON.parse(stored) as string[]);
  } catch {}
  return new Set();
}

const expandedFolders = ref<Set<string>>(loadExpandedFromStorage());
const fileTree = computed<TreeNode[]>(() => buildTree(store.files, store.fileMtimes));

watch(expandedFolders, (set) => {
  localStorage.setItem(LS_EXPANDED_KEY, JSON.stringify([...set]));
});

function toggleFolder(path: string) {
  const next = new Set(expandedFolders.value);
  if (next.has(path)) next.delete(path); else next.add(path);
  expandedFolders.value = next;
}

function collectFolderPaths(nodes: TreeNode[]): string[] {
  const paths: string[] = [];
  for (const node of nodes) {
    if (node.type === "folder") {
      paths.push(node.path);
      paths.push(...collectFolderPaths(node.children));
    }
  }
  return paths;
}

const allFolderPaths = computed(() => collectFolderPaths(fileTree.value));
const allExpanded = computed(() =>
  allFolderPaths.value.length > 0 &&
  allFolderPaths.value.every(p => expandedFolders.value.has(p))
);

function toggleAllFolders() {
  expandedFolders.value = allExpanded.value ? new Set() : new Set(allFolderPaths.value);
}

onMounted(async () => {
  await store.fetchFiles();
  const pathMatch = route.params.pathMatch;
  const notePath = Array.isArray(pathMatch) ? pathMatch.join("/") : (pathMatch as string) ?? "";
  if (notePath) await store.openNote(notePath);
});

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

function handleContentClick(e: MouseEvent) {
  const anchor = (e.target as HTMLElement).closest("a");
  if (!anchor) return;
  if (anchor.dataset.internal !== "true") return;
  e.preventDefault();
  const href = anchor.getAttribute("href");
  if (href) openNote(href.endsWith(".md") ? href : `${href}.md`);
}

async function openNote(path: string) {
  await store.openNote(path);
  creatingNew.value = false;
  router.replace(`/notes/${path}`);
}

function goBack() {
  store.currentPath = null;
  router.replace("/notes");
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
