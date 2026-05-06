<template>
  <div class="flex h-full bg-[var(--color-bg)] text-[var(--color-text)]">
    <!-- Desktop sidebar -->
    <aside class="hidden md:flex flex-col w-16 lg:w-56 shrink-0 border-r border-[var(--color-border)] bg-[var(--color-surface)]">
      <div class="px-3 py-4 border-b border-[var(--color-border)]">
        <span class="hidden lg:block font-bold text-base text-[var(--color-text)]">claw-zettel</span>
        <span class="lg:hidden font-bold text-lg text-center block text-[var(--color-accent)]">C</span>
      </div>
      <nav class="flex-1 py-3 space-y-1 px-2">
        <RouterLink
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="flex items-center gap-3 rounded-lg px-2 py-2 text-sm font-medium transition-colors hover:bg-[var(--color-border)] text-[var(--color-muted)] [&.router-link-active]:text-[var(--color-text)] [&.router-link-active]:bg-[var(--color-border)]"
        >
          <component :is="item.icon" class="size-5 shrink-0" />
          <span class="hidden lg:block">{{ item.label }}</span>
        </RouterLink>
      </nav>
      <div class="p-2 border-t border-[var(--color-border)]">
        <button
          @click="handleDisconnect"
          class="flex items-center gap-3 w-full rounded-lg px-2 py-2 text-sm text-[var(--color-muted)] hover:text-red-500 hover:bg-red-50 transition-colors"
        >
          <LogOut class="size-5 shrink-0" />
          <span class="hidden lg:block">Disconnect</span>
        </button>
      </div>
    </aside>

    <!-- Main content -->
    <main class="flex-1 min-w-0 flex flex-col">
      <RouterView />
    </main>

    <!-- Mobile bottom nav -->
    <nav class="md:hidden fixed bottom-0 inset-x-0 flex border-t border-[var(--color-border)] bg-[var(--color-surface)] z-10">
      <RouterLink
        v-for="item in navItems"
        :key="item.to"
        :to="item.to"
        class="flex-1 flex flex-col items-center gap-1 py-3 text-xs text-[var(--color-muted)] [&.router-link-active]:text-[var(--color-accent)]"
      >
        <component :is="item.icon" class="size-5" />
        <span>{{ item.label }}</span>
      </RouterLink>
    </nav>
  </div>
</template>

<script setup lang="ts">
import { RouterLink, RouterView, useRouter } from "vue-router";
import { MessageSquare, FileText, Settings, LogOut } from "lucide-vue-next";
import { useConnectionStore } from "@/stores/connection";

const conn = useConnectionStore();
const router = useRouter();

const navItems = [
  { to: "/chat", label: "Chat", icon: MessageSquare },
  { to: "/notes", label: "Notes", icon: FileText },
  { to: "/settings", label: "Settings", icon: Settings },
];

function handleDisconnect() {
  conn.disconnect();
  router.push("/connect");
}
</script>
