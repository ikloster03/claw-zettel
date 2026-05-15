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
  const fileMtimes = ref<Record<string, number>>({});
  const searchResults = ref<SearchResult[]>([]);
  const currentPath = ref<string | null>(null);
  const currentContent = ref<string>("");
  const loading = ref(false);

  async function fetchFiles() {
    const data = await conn.api<{ path: string; mtime: number }[]>("/notes");
    files.value = data.map(f => f.path);
    fileMtimes.value = Object.fromEntries(data.map(f => [f.path, f.mtime]));
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
      fileMtimes.value = { ...fileMtimes.value, [path]: Date.now() };
      if (currentPath.value === path) currentContent.value = content;
    } finally {
      loading.value = false;
    }
  }

  async function deleteNote(path: string) {
    await conn.api(`/notes/${path}`, { method: "DELETE" });
    files.value = files.value.filter((f) => f !== path);
    const { [path]: _, ...rest } = fileMtimes.value;
    fileMtimes.value = rest;
    if (currentPath.value === path) {
      currentPath.value = null;
      currentContent.value = "";
    }
  }

  return { files, fileMtimes, searchResults, currentPath, currentContent, loading, fetchFiles, search, openNote, saveNote, deleteNote };
});
