import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    // Vite 8 defaults to Safari/iOS 16.4. Keep the generated store bundle
    // compatible with this release candidate's iOS 15 deployment target.
    target: ['chrome87', 'edge88', 'firefox78', 'safari15'],
    rolldownOptions: {
      onwarn(warning, warn) {
        if (warning.code === 'MODULE_LEVEL_DIRECTIVE') return
        warn(warning)
      }
    }
  }
})
