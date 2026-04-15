#!/usr/bin/env node
// Post-build install: copy dist/index.html to ../priv/reporter/template.html
// so the Elixir reporter can find it.
//
// Run via `npm run build:install`. The output path can be overridden via the
// LIVELOAD_TEMPLATE_PATH environment variable for non-standard layouts.

import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "..");
const source = resolve(projectRoot, "dist", "index.html");
const dest =
  process.env.LIVELOAD_TEMPLATE_PATH ||
  resolve(projectRoot, "..", "priv", "react-reporter", "template.html");

if (!existsSync(source)) {
  console.error(`Source not found: ${source}`);
  console.error("Did you run `npm run build` first?");
  process.exit(1);
}

mkdirSync(dirname(dest), { recursive: true });
copyFileSync(source, dest);
console.log(`Installed template → ${dest}`);
