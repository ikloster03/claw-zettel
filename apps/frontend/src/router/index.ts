import { createRouter, createWebHistory } from "vue-router";
import { useConnectionStore } from "@/stores/connection";

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: "/connect",
      name: "connect",
      component: () => import("@/views/ConnectView.vue"),
    },
    {
      path: "/",
      component: () => import("@/views/AppLayout.vue"),
      meta: { requiresAuth: true },
      children: [
        { path: "", redirect: "/chat" },
        {
          path: "chat",
          name: "chat",
          component: () => import("@/views/ChatView.vue"),
        },
        {
          path: "chat/:id",
          name: "chat-detail",
          component: () => import("@/views/ChatView.vue"),
        },
        {
          path: "notes",
          name: "notes",
          component: () => import("@/views/NotesView.vue"),
        },
        {
          path: "notes/*",
          name: "note-detail",
          component: () => import("@/views/NotesView.vue"),
        },
        {
          path: "settings",
          name: "settings",
          component: () => import("@/views/SettingsView.vue"),
        },
      ],
    },
    { path: "/:pathMatch(.*)*", redirect: "/" },
  ],
});

router.beforeEach((to) => {
  const conn = useConnectionStore();
  if (to.meta.requiresAuth && !conn.isConnected) {
    return "/connect";
  }
  if (to.path === "/connect" && conn.isConnected) {
    return "/chat";
  }
});
