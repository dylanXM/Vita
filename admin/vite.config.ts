import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "node:path";

// The admin dashboard talks to the Vita API. In dev it proxies /v1 to the
// backend so the browser never makes a cross-origin call — no CORS config
// needed. Point VITE_DEV_PROXY_TARGET at the running API (the default matches
// `make be-run`, which listens on :8260).
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const target = env.VITE_DEV_PROXY_TARGET || "http://127.0.0.1:8260";
  const port = Number(env.VITE_DEV_PORT || 5174);

  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: { "@": resolve(__dirname, "src") },
    },
    build: {
      rollupOptions: {
        output: {
          manualChunks: {
            "vendor-react": ["react", "react-dom", "react-router-dom"],
            "vendor-query": ["@tanstack/react-query", "@tanstack/react-table"],
            "vendor-ui": ["radix-ui", "lucide-react", "sonner"],
            "vendor-form": ["react-hook-form", "@hookform/resolvers", "zod"],
            "vendor-i18n": ["i18next", "react-i18next", "i18next-browser-languagedetector"],
          },
        },
      },
    },
    server: {
      host: "127.0.0.1",
      port,
      proxy: {
        "/v1": { target, changeOrigin: true },
      },
    },
  };
});
