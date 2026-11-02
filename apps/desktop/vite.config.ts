import { defineConfig } from "vite";

// Tauri serves the dev build on a fixed port and loads dist/ in release builds.
export default defineConfig({
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: { target: "es2022", outDir: "dist" },
});
