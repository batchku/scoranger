import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The score workspace is served as static files at the dev server root:
// /manifest.json, /<slug>/vNNN.musicxml
// Mutations (New... upload) go to the local engine API: `scor serve`
export default defineConfig({
  plugins: [react()],
  publicDir: '../workspace',
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:8765',
    },
  },
})
