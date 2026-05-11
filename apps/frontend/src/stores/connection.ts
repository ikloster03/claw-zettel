import { defineStore } from "pinia";
import { ref, computed } from "vue";

const LS_KEY = "cz_connection";

export const useConnectionStore = defineStore("connection", () => {
  const serverUrl = ref<string>(localStorage.getItem(LS_KEY + "_url") ?? "");
  const token = ref<string>(localStorage.getItem(LS_KEY + "_token") ?? "");
  const error = ref<string | null>(null);
  const loading = ref(false);

  const isConnected = computed(() => !!token.value && !!serverUrl.value);

  async function connect(url: string, password: string): Promise<boolean> {
    error.value = null;
    if (window.location.protocol === "https:" && url.startsWith("http:")) {
      try {
        const hostname = new URL(url).hostname;
        const isIp = /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname) || hostname === "localhost";
        if (!isIp) {
          error.value = "Mixed content blocked: this page is served over HTTPS but the server URL uses HTTP. Either use HTTPS for your server or open the frontend over HTTP.";
          return false;
        }
      } catch {
        // invalid URL — let fetch fail naturally
      }
    }
    loading.value = true;
    try {
      const res = await fetch(`${url}/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        error.value = data.error ?? "Authentication failed";
        return false;
      }
      const { token: t } = await res.json();
      serverUrl.value = url;
      token.value = t;
      localStorage.setItem(LS_KEY + "_url", url);
      localStorage.setItem(LS_KEY + "_token", t);
      return true;
    } catch (e) {
      error.value = "Cannot reach server. Check the URL.";
      return false;
    } finally {
      loading.value = false;
    }
  }

  function disconnect() {
    serverUrl.value = "";
    token.value = "";
    localStorage.removeItem(LS_KEY + "_url");
    localStorage.removeItem(LS_KEY + "_token");
  }

  function authHeaders(): Record<string, string> {
    return { Authorization: `Bearer ${token.value}` };
  }

  async function api<T = unknown>(
    path: string,
    init: RequestInit = {}
  ): Promise<T> {
    const res = await fetch(`${serverUrl.value}${path}`, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        ...authHeaders(),
        ...(init.headers ?? {}),
      },
    });
    if (res.status === 401) {
      disconnect();
      throw new Error("Session expired");
    }
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      throw new Error(data.error ?? res.statusText);
    }
    return res.json();
  }

  return { serverUrl, token, error, loading, isConnected, connect, disconnect, authHeaders, api };
});
