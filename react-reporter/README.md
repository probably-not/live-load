# LiveLoad React Reporter

The frontend source for LiveLoad's self-contained HTML reports. This is a Vite + React + TypeScript project that builds to a single `index.html` file with all JS, CSS, and assets inlined. The Elixir reporter (`LiveLoad.Reporter.HTML.render!/1`) reads that file as a template, replaces a data placeholder with a base64+gzip-encoded `LiveLoad.Result`, and returns the final HTML as a binary.

The dev server reads from a local JSON file at `public/dev-data.json` (or any path set via `VITE_DEV_DATA_PATH`).

The data loader detects dev mode by checking whether the placeholder string in `window.__LIVELOAD_DATA__` is still present (it is, because Vite serves `index.html` literally). In production, the Elixir reporter replaces it with real data and the loader takes the decompression path.
