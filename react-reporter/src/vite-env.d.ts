/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_DEV_DATA_PATH?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
