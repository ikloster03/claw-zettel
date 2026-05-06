import { defineStore } from "pinia";
import { ref } from "vue";
import { useConnectionStore } from "./connection";

export interface SearchResult {
  path: string;
  excerpt: string;
}

export const useNotesStore = defineStore("notes", () => {
  const conn = useConnectionStore();
  const files = ref<string[]>([]);
  const searchResults = ref<SearchResult[]>([]);
  const currentPath = ref<string | null>(null);
  const currentContent = ref<string>("");
  const loading = ref(false);

  async function fetchFiles() {
    files.value = await conn.api<string[]>("/notes");
  }

  async function search(q: string) {
    searchResults.value = await conn.api<SearchResult[]>(`/notes/search?q=${encodeURIComponent(q)}`);
  }

  async function openNote(path: string) {
    const { content } = await conn.api<{ path: string; content: string }>(`/notes/${path}`);
    currentPath.value = path;
    currentContent.value = content;
  }

  async function saveNote(path: string, content: string) {
    loading.value = true;
    try {
      if (files.value.includes(path)) {
        await conn.api(`/notes/${path}`, { method: "PUT", body: JSON.stringify({ content }) });
      } else {
        await conn.api("/notes", { method: "POST", body: JSON.stringify({ path, content }) });
        files.value.push(path);
        files.value.sort();
      }
      if (currentPath.value === path) currentContent.value = content;
    } finally {
      loading.value = false;
    }
  }

  async function deleteNote(path: string) {
    await conn.api(`/notes/${path}`, { method: "DELETE" });
    files.value = files.value.filter((f) => f !== path);
    if (currentPath.value === path) {
      currentPath.value = null;
      currentContent.value = "";
    }
  }

  return { files, searchResults, currentPath, currentContent, loading, fetchFiles, search, openNote, saveNote, deleteNote };
});
