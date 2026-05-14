<template>
  <Transition name="slide-up">
    <div v-if="needRefresh" class="fixed bottom-4 right-4 z-50 flex items-center gap-3 rounded-lg border border-border bg-background px-4 py-3 shadow-lg">
      <span class="text-sm text-foreground">Доступно обновление</span>
      <button
        class="rounded-md bg-primary px-3 py-1 text-sm font-medium text-primary-foreground hover:opacity-90"
        @click="updateServiceWorker()"
      >
        Обновить
      </button>
      <button
        class="rounded-md px-2 py-1 text-sm text-muted-foreground hover:text-foreground"
        @click="close()"
      >
        ✕
      </button>
    </div>
  </Transition>
</template>

<script setup lang="ts">
import { useRegisterSW } from "virtual:pwa-register/vue";

const { needRefresh, updateServiceWorker } = useRegisterSW();

function close() {
  needRefresh.value = false;
}
</script>

<style scoped>
.slide-up-enter-active,
.slide-up-leave-active {
  transition: transform 0.25s ease, opacity 0.25s ease;
}
.slide-up-enter-from,
.slide-up-leave-to {
  transform: translateY(1rem);
  opacity: 0;
}
</style>
