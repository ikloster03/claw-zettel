<template>
  <div class="min-h-screen flex items-center justify-center bg-[var(--color-bg)] p-4">
    <div class="w-full max-w-md">
      <div class="text-center mb-8">
        <h1 class="text-3xl font-bold text-[var(--color-text)]">claw-zettel</h1>
        <p class="mt-2 text-[var(--color-muted)] text-sm">Connect to your clawzettel server</p>
      </div>

      <div class="bg-[var(--color-surface)] rounded-2xl shadow-lg border border-[var(--color-border)] p-6">
        <form @submit.prevent="handleConnect" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-[var(--color-text)] mb-1">
              Server URL
            </label>
            <input
              v-model="url"
              type="text"
              placeholder="http://your-vps:3001"
              class="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm text-[var(--color-text)] placeholder:text-[var(--color-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--color-accent)]"
              required
              autocomplete="url"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-[var(--color-text)] mb-1">
              Password
            </label>
            <input
              v-model="password"
              type="password"
              placeholder="••••••••"
              class="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm text-[var(--color-text)] placeholder:text-[var(--color-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--color-accent)]"
              required
              autocomplete="current-password"
            />
          </div>

          <div
            v-if="conn.error"
            class="rounded-lg bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-600"
          >
            {{ conn.error }}
          </div>

          <button
            type="submit"
            :disabled="conn.loading"
            class="w-full rounded-lg bg-[var(--color-accent)] hover:bg-[var(--color-accent-hover)] text-white font-medium py-2 px-4 text-sm transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
          >
            <span v-if="conn.loading">Connecting…</span>
            <span v-else>Connect</span>
          </button>
        </form>

        <p class="mt-4 text-xs text-center text-[var(--color-muted)]">
          Both HTTP and HTTPS are supported.
        </p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useConnectionStore } from "@/stores/connection";

const conn = useConnectionStore();
const router = useRouter();
const url = ref("");
const password = ref("");

async function handleConnect() {
  const ok = await conn.connect(url.value.replace(/\/$/, ""), password.value);
  if (ok) router.push("/chat");
}
</script>
