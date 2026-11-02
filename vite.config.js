import { defineConfig } from 'vite';
import { execFile } from 'node:child_process';
import { demoApi } from './api/server.mjs';

export default defineConfig({
  plugins: [{
    name: 'elm-pilot',
    configureServer(server) { server.middlewares.use(demoApi); },
    configurePreviewServer(server) { server.middlewares.use(demoApi); },
    async handleHotUpdate({ file, server }) {
      if (!file.endsWith('.elm')) return;
      await new Promise(resolve => {
        execFile(process.execPath, ['scripts/elm-tool.mjs', 'build'], (error, stdout, stderr) => {
          if (error) server.ws.send({ type: 'error', err: { message: stderr || stdout, stack: '', plugin: 'elm' } });
          else server.ws.send({ type: 'full-reload' });
          resolve();
        });
      });
      return [];
    },
  }],
});
