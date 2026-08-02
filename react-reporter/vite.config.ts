import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";

// Vite build config for the LiveLoad HTML reporter.
//
// Output: a single self-contained HTML file at dist/index.html with all JS,
// CSS, and assets inlined. The file contains a placeholder for compressed
// scenario data which the Elixir reporter replaces at render time.
//
// Run `npm run build` to produce dist/index.html.
// Run `npm run build:install` to also copy it to ../priv/reporter/template.html.
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: {
    target: "es2020",
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    // Don't copy public/ contents into dist/ — that's where dev fixtures live.
    // Dev mode (`npm run dev`) still serves public/ correctly via a separate
    // Vite code path.
    copyPublicDir: false,
    rollupOptions: {
      output: {
        codeSplitting: false,
      },
    },
  },
});
