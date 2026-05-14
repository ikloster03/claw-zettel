<template>
  <RouterView />
  <PwaUpdatePrompt />
</template>

<script setup lang="ts">
import { RouterView } from "vue-router";
import PwaUpdatePrompt from "@/components/shared/PwaUpdatePrompt.vue";
</script>
