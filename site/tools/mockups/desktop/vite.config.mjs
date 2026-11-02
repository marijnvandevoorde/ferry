// Builds apps/desktop with the Tauri APIs swapped for tauri-mock.ts, so its UI can be screenshotted in a browser.
// No imports: this file lives outside apps/desktop, where `vite` can't be resolved.
import { fileURLToPath } from "node:url";
const here = (p) => fileURLToPath(new URL(p, import.meta.url));
export default {
  root: here("../../../../apps/desktop"),
  publicDir: here(".."),
  resolve: { alias: [{ find: /^@tauri-apps\/.*/, replacement: here("tauri-mock.ts") }] },
  build: { target: "es2022", outDir: process.env.OUT_DIR, emptyOutDir: true },
};
