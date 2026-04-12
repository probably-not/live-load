# LiveLoad React Reporter

The frontend source for LiveLoad's self-contained HTML reports. This is a Vite +
React + TypeScript project that builds to a single `index.html` file with all
JS, CSS, and assets inlined. The Elixir reporter
(`LiveLoad.Reporter.HTML.render/1`) reads that file as a template, replaces a
data placeholder with a base64+gzip-encoded `LiveLoad.Result`, and returns the
final HTML as iodata.

## Layout

```
react-reporter/
├── index.html               # Vite entry; contains the data placeholder
├── package.json
├── tsconfig.json
├── vite.config.ts           # single-file build config
├── public/
│   └── dev-data.json        # (gitignored) dev fixture you provide locally
├── scripts/
│   └── install-template.mjs # copies dist/index.html → ../priv/reporter/template.html
└── src/
    ├── main.tsx             # React entry, mounts <App />
    ├── App.tsx              # Top-level routing (compare ↔ scenario)
    ├── data.ts              # Decompression / dev mode loading
    ├── parse.ts             # Raw JSON → display-ready shapes
    ├── format.ts            # Value formatters (incl. unit-aware fmtTsValue)
    ├── meta.ts              # Histogram & counter metadata, palette
    ├── types.ts             # All TypeScript types (mirrors LiveLoad.Result)
    ├── styles.css
    └── components/
        ├── Tooltip.tsx       # Shared chart tooltip
        ├── CDFModal.tsx      # Distribution curve modal
        ├── ScenarioView.tsx  # Single-scenario report
        └── CompareView.tsx   # Multi-scenario comparison view
```

## Setup

```bash
cd react-reporter
npm install
```

## Dev workflow

The dev server reads from a local JSON file at `public/dev-data.json` (or any
path set via `VITE_DEV_DATA_PATH`). This file is gitignored — drop your own
result there to iterate on the report design with hot reload.

```bash
# Save a real result first (see RUNBOOK.md):
#   results |> Enum.map(...) |> JSON.encode_to_iodata!() |> File.write!(...)
cp ~/some_result.json public/dev-data.json

npm run dev
# → http://localhost:5173 with HMR
```

The data loader detects dev mode by checking whether the placeholder string in
`window.__LIVELOAD_DATA__` is still present (it is, because Vite serves
`index.html` literally). In production, the Elixir reporter replaces it with
real data and the loader takes the decompression path.

To point at a different file, set `VITE_DEV_DATA_PATH`:

```bash
echo "VITE_DEV_DATA_PATH=/my-data.json" > .env.local
cp ~/other_result.json public/my-data.json
npm run dev
```

## Building

```bash
npm run build
# → produces dist/index.html (everything inlined)
```

To install the template into the Elixir project's `priv/reporter/` directory:

```bash
npm run build:install
# → ../priv/reporter/template.html
```

The install path can be overridden:

```bash
LIVELOAD_TEMPLATE_PATH=/custom/path/template.html npm run build:install
```

## How the data flow works

1. **Build time:** Vite produces `dist/index.html` containing the React app and
   a `<script>window.__LIVELOAD_DATA__ = "__LIVELOAD_DATA_INJECTION_POINT_DO_NOT_REMOVE__";</script>`
   placeholder in the `<head>`.
2. **Render time:** The Elixir reporter reads the template, JSON-encodes the
   `LiveLoad.Result` map, gzips it, base64-encodes it, and replaces the
   placeholder with the encoded payload.
3. **Run time:** The browser loads the HTML, the React app starts, and
   `loadData()` decompresses `window.__LIVELOAD_DATA__` via the
   `DecompressionStream` API and parses the resulting JSON.

The single placeholder string is unique enough that a single
`String.replace/3` is safe — it never collides with anything else in the
bundle. The placeholder is also a valid JS string literal so the page is
parseable even before injection.

## TypeScript types

`src/types.ts` mirrors `LiveLoad.Result` exactly. **When the Elixir struct
evolves, update both sides together.** The `Raw*` types describe the JSON
shape; the `Parsed*` types describe the post-parse display shapes the
components consume.

## Adding a metric

If LiveLoad starts emitting a new histogram or counter:

1. Add it to `HIST_META` or `COUNTER_META` in `src/meta.ts` with a `label`,
   `unit`, and (for histograms) `tsLabel` indicating whether it should appear
   in the time-series chart selector.
2. Add the key to `LV_KEYS` or `HTTP_KEYS` to control its position in the
   metrics tables.
3. Rebuild and verify against a real result.

No changes to the parser or components needed — they iterate the metadata.
