import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const [mode, ...args] = process.argv.slice(2);
const env = { ...process.env, ELM_HOME: resolve('.cache/elm') };
mkdirSync('public', { recursive: true });
const command = mode === 'test' ? 'elm-test' : 'elm';
const options = mode === 'test' ? args : ['make', 'src/Main.elm', '--optimize', '--output=public/elm.js', ...args];
const result = spawnSync(command, options, { env, stdio: 'inherit', shell: process.platform === 'win32' });
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
