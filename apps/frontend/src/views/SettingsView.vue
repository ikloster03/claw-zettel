<template>
  <div class="flex-1 overflow-y-auto px-4 py-6 pb-20 md:pb-6 max-w-lg mx-auto w-full">
    <h1 class="text-lg font-semibold mb-6">Settings</h1>

    <section class="bg-[var(--color-surface)] rounded-xl border border-[var(--color-border)] divide-y divide-[var(--color-border)]">
      <div class="px-4 py-4">
        <div class="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)] mb-3">Connection</div>
        <div class="space-y-2 text-sm">
          <div class="flex justify-between items-center">
            <span class="text-[var(--color-muted)]">Server</span>
            <span class="font-mono text-xs truncate max-w-[200px]">{{ conn.serverUrl || "—" }}</span>
          </div>
          <div class="flex justify-between items-center">
            <span class="text-[var(--color-muted)]">Status</span>
            <span
              class="inline-flex items-center gap-1.5 text-xs font-medium"
              :class="conn.isConnected ? 'text-green-600' : 'text-red-500'"
            >
              <span class="size-2 rounded-full" :class="conn.isConnected ? 'bg-green-500' : 'bg-red-400'" />
              {{ conn.isConnected ? "Connected" : "Disconnected" }}
            </span>
          </div>
        </div>
        <button
          @click="handleDisconnect"
          class="mt-4 w-full text-sm rounded-lg border border-red-200 text-red-500 hover:bg-red-50 py-2 transition-colors"
        >
          Disconnect
        </button>
      </div>

      <div class="px-4 py-4">
        <div class="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)] mb-3">Appearance</div>
        <div class="flex items-center justify-between">
          <span class="text-sm">Dark mode</span>
          <button
            @click="toggleDark"
            class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors"
            :class="isDark ? 'bg-[var(--color-accent)]' : 'bg-[var(--color-border)]'"
          >
            <span
              class="inline-block h-4 w-4 rounded-full bg-white shadow transition-transform"
              :class="isDark ? 'translate-x-6' : 'translate-x-1'"
            />
          </button>
        </div>
      </div>

      <div class="px-4 py-4">
        <div class="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)] mb-2">About</div>
        <div class="text-sm text-[var(--color-muted)]">
          claw-zettel v0.1.0 — AI-powered personal Zettelkasten
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRouter } from "vue-router";
import { useConnectionStore } from "@/stores/connection";

const conn = useConnectionStore();
const router = useRouter();
const isDark = ref(document.documentElement.classList.contains("dark"));

function toggleDark() {
  isDark.value = !isDark.value;
  document.documentElement.classList.toggle("dark", isDark.value);
  localStorage.setItem("cz_dark", isDark.value ? "1" : "0");
}

onMounted(() => {
  isDark.value = localStorage.getItem("cz_dark") === "1";
  document.documentElement.classList.toggle("dark", isDark.value);
});

function handleDisconnect() {
  conn.disconnect();
  router.push("/connect");
}
</script>
