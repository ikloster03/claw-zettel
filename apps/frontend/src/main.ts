import { createApp } from "vue";
import { createPinia } from "pinia";
import App from "./App.vue";
import { router } from "./router";
import "./assets/main.css";

if (localStorage.getItem("cz_dark") === "1") {
  document.documentElement.classList.add("dark");
}

const app = createApp(App);
app.use(createPinia());
app.use(router);
app.mount("#app");
