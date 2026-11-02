// Expériences ciblées : aucune modification de src/ ni des tests d'origine.
// Ce n'est ni une preuve formelle ni une campagne exhaustive de mutations.
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, 'output/evidence');
mkdirSync(output, { recursive: true });
mkdirSync(join(root, '.cache'), { recursive: true });
const scratch = mkdtempSync(join(root, '.cache/evidence-'));
const compiler = join(root, 'node_modules/.bin/elm');
const runner = join(root, 'node_modules/elm-test/bin/elm-test');
const env = { ...process.env, ELM_HOME: join(root, '.cache/elm') };

function inputs(folder) {
  return readdirSync(folder, { withFileTypes: true }).flatMap(entry => {
    const path = join(folder, entry.name);
    return entry.isDirectory() ? inputs(path) : [path];
  });
}
const files = [...inputs(join(root, 'src')), ...inputs(join(root, 'tests')), ...inputs(join(root, 'api')),
  ...['elm.json', 'package.json', 'package-lock.json', 'index.html', 'vite.config.js', 'scripts/probe-evidence.mjs'].map(name => join(root, name))].sort();
const hashes = () => Object.fromEntries(files.map(path => [relative(root, path), createHash('sha256').update(readFileSync(path)).digest('hex')]));
const originalHashes = hashes();
const sourceHash = createHash('sha256').update(JSON.stringify(originalHashes)).digest('hex');

const experiments = [
  { id: 'baseline', label: 'Version actuelle' },
  { id: 'discount', label: 'Remise de 5 % au lieu de 10 %', file: 'src/Cart.elm', from: 'subtotal // 10', to: 'subtotal // 20' },
  { id: 'negative-price', label: 'Prix négatifs acceptés', file: 'src/Api.elm', from: '(Decode.field "price" nonNegativeMoney)', to: '(Decode.field "price" Decode.int)' },
  {
    id: 'missing-http', label: 'Envoi HTTP de commande supprimé', file: 'src/Main.elm',
    transform(source) {
      const start = source.indexOf('        SubmitOrder scenario email cart ->');
      const end = source.lastIndexOf('    )');
      if (start < 0 || end < start) throw new Error('Branche SubmitOrder introuvable');
      return source.slice(0, start) + '        SubmitOrder _ _ _ ->\n            Cmd.none\n' + source.slice(end);
    },
  },
];
const report = {
  schemaVersion: 1, startedAt: new Date().toISOString(), sourceHash, inputHashes: originalHashes,
  scope: '27 tests Elm + compilation de Main pour chaque variante. Aucun test navigateur exécuté par cette commande.',
  seed: 42, fuzzRuns: 1000, experiments: [],
};

function command(experiment, executable, args, cwd, label) {
  const result = spawnSync(executable, args, { cwd, env, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024 });
  writeFileSync(join(output, `${experiment.id}-${label}.log`), (result.stdout ?? '') + (result.stderr ?? ''));
  if (result.error || result.signal) throw new Error(`${label}: ${result.error?.message ?? result.signal}`);
  return result;
}

try {
  for (const experiment of experiments) {
    const cwd = join(scratch, experiment.id);
    mkdirSync(cwd);
    for (const path of ['src', 'tests', 'elm.json']) cpSync(join(root, path), join(cwd, path), { recursive: true });
    if (experiment.file) {
      const path = join(cwd, experiment.file);
      const source = readFileSync(path, 'utf8');
      if (experiment.from && source.split(experiment.from).length !== 2) throw new Error(`Mutation ambiguë : ${experiment.id}`);
      writeFileSync(path, experiment.transform ? experiment.transform(source) : source.replace(experiment.from, experiment.to));
    }
    const build = command(experiment, compiler, ['make', 'src/Main.elm', '--optimize', '--output', join(cwd, 'main.js')], cwd, 'build');
    if (build.status !== 0) throw new Error(`${experiment.id} ne compile pas : ce résultat ne prouve pas la sensibilité des tests.`);
    const run = command(experiment, process.execPath, [runner, '--compiler', compiler, '--report', 'json', '--seed', '42', '--fuzz', '1000'], cwd, 'tests');
    const events = run.stdout.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
    const summary = events.find(event => event.event === 'runComplete');
    const tests = events.filter(event => event.event === 'testCompleted');
    if (!summary || summary.autoFail || tests.length !== 27 || ![0, 2].includes(run.status)) throw new Error(`Exécution incomplète : ${experiment.id}`);
    const passed = Number(summary.passed);
    const failed = Number(summary.failed);
    if (passed + failed !== tests.length || (failed === 0 && run.status !== 0) || (failed > 0 && run.status !== 2)) throw new Error(`Résultat incohérent : ${experiment.id}`);
    if (experiment.id === 'baseline' && failed > 0) throw new Error('La référence échoue : comparaison de mutations interrompue.');
    const outcome = experiment.id === 'baseline' ? 'baseline-pass' : failed ? 'detected' : 'survived';
    report.experiments.push({ id: experiment.id, label: experiment.label, file: experiment.file ?? null, compiled: true, passed, failed, outcome, tests });
    console.log(`${experiment.label}: ${passed} réussis, ${failed} échoués — ${outcome}`);
  }
  report.completedAt = new Date().toISOString();
  report.originalSourcesUnchanged = JSON.stringify(originalHashes) === JSON.stringify(hashes());
  if (!report.originalSourcesUnchanged) throw new Error('Les fichiers ont changé pendant les expériences : rapport à régénérer.');
  report.status = report.experiments.some(result => result.outcome === 'survived') ? 'gap-found' : 'targeted-mutations-detected';
  writeFileSync(join(output, 'latest.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`Rapport : ${join(output, 'latest.json')}`);
  console.log(`Statut : ${report.status}. Trois mutations ciblées ne constituent pas une certification.`);
  process.exitCode = report.status === 'gap-found' ? 1 : 0;
} catch (error) {
  report.status = 'execution-error';
  report.error = error.message;
  writeFileSync(join(output, 'latest.json'), JSON.stringify(report, null, 2) + '\n');
  console.error(error.message);
  process.exitCode = 2;
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
