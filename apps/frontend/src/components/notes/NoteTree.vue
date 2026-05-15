<template>
  <div>
    <template v-for="node in nodes" :key="node.path">
      <!-- Folder -->
      <button
        v-if="node.type === 'folder'"
        @click="emit('toggle-folder', node.path)"
        class="w-full flex items-center gap-1.5 py-2 pr-3 text-sm hover:bg-[var(--color-border)] transition-colors text-[var(--color-muted)] hover:text-[var(--color-text)]"
        :style="{ paddingLeft: `${12 + depth * 12}px` }"
      >
        <ChevronRight
          class="size-3.5 shrink-0 transition-transform duration-200"
          :class="expandedFolders.has(node.path) ? 'rotate-90' : ''"
        />
        <FolderOpen v-if="expandedFolders.has(node.path)" class="size-4 shrink-0" />
        <Folder v-else class="size-4 shrink-0" />
        <span class="truncate text-left">{{ node.name }}</span>
      </button>

      <!-- Recursive children when expanded -->
      <NoteTree
        v-if="node.type === 'folder' && expandedFolders.has(node.path)"
        :nodes="node.children"
        :depth="depth + 1"
        :expanded-folders="expandedFolders"
        :current-path="currentPath"
        @open-note="emit('open-note', $event)"
        @toggle-folder="emit('toggle-folder', $event)"
      />

      <!-- File -->
      <button
        v-if="node.type === 'file'"
        @click="emit('open-note', node.path)"
        class="w-full flex items-center gap-1.5 py-2 pr-3 text-sm hover:bg-[var(--color-border)] transition-colors"
        :style="{ paddingLeft: `${12 + depth * 12}px` }"
        :class="node.path === currentPath
          ? 'bg-[var(--color-border)] font-medium text-[var(--color-text)]'
          : 'text-[var(--color-muted)]'"
      >
        <FileText class="size-4 shrink-0" />
        <span class="truncate text-left">{{ node.name }}</span>
      </button>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ChevronRight, Folder, FolderOpen, FileText } from "lucide-vue-next";
import NoteTree from "./NoteTree.vue";
import type { TreeNode } from "@/views/NotesView.vue";

defineProps<{
  nodes: TreeNode[];
  depth: number;
  expandedFolders: Set<string>;
  currentPath: string | null;
}>();

const emit = defineEmits<{
  "open-note": [path: string];
  "toggle-folder": [path: string];
}>();
</script>
