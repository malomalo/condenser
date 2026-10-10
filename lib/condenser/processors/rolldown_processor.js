// Runs one Rolldown build for Condenser::RolldownProcessor.
//
// Usage: node rolldown_processor.js '<config json>'
//
// Ruby only answers for what only condenser knows: the entry, load-path
// imports, files whose processed source lives in Ruby (.erb, .ejx, .jst,
// .svg, ...), glob imports and dynamic imports. Rolldown resolves and reads
// node_modules itself, so npm files never round-trip to Ruby.
//
// Protocol (one JSON document per line):
//   node -> ruby: TOKEN {"rid": n, "method": "...", "args": [...]}
//   ruby -> node: {"rid": n, "return": ...}
// Any other line node writes to stdout is passed through by Ruby.
const fs = require('fs');
const readline = require('readline');

const config = JSON.parse(process.argv[2]);
const TOKEN = config.token;
const ENTRY = config.entry;
const GLOB = '\0condenser-glob:';
const NODE_MODULES = /[\\/]node_modules[\\/]/;
const ANSI = /\x1b\[[0-9;]*m/g;

let rid = 0;
const pending = new Map();

function send(message, callback) {
  process.stdout.write(TOKEN + JSON.stringify(message) + "\n", callback);
}

function request(method, args) {
  const id = rid++;
  return new Promise((resolve) => {
    pending.set(id, resolve);
    send({ rid: id, method, args });
  });
}

readline.createInterface({ input: process.stdin, crlfDelay: Infinity }).on('line', (line) => {
  if (line.length === 0) return;
  const message = JSON.parse(line);
  const resolve = pending.get(message.rid);
  pending.delete(message.rid);
  resolve(message['return']);
}).on('close', () => process.exit(1));

const condenser = {
  name: 'condenser',

  resolveId: {
    filter: { id: { exclude: /^\0/ } },
    async handler(source, importer, options) {
      if (importer === undefined) return source === ENTRY ? ENTRY : null;
      // Modules generated for globs import absolute paths; Rolldown can
      // resolve those itself.
      if (importer.startsWith('\0')) return null;

      if (options.kind === 'dynamic-import') {
        const asset = await request('resolveDynamicImport', [source, importer]);
        if (!asset) return null;
        // :keep / :local / false: leave the import in place, pointing at
        // the URL of the separately exported asset.
        if (asset.external) return { id: asset.path, external: 'absolute' };
        return asset.id;
      }

      // Inside node_modules everything is npm's business.
      if (NODE_MODULES.test(importer)) return null;
      if (source.endsWith('*')) return GLOB + source;

      // Load paths first, like condenser; `null` falls through to Rolldown's
      // node_modules resolution.
      return await request('resolve', [source, importer]);
    }
  },

  load: {
    filter: { id: { exclude: NODE_MODULES } },
    async handler(id) {
      if (id.startsWith(GLOB)) {
        const code = await request('glob', [id.slice(GLOB.length)]);
        return { code, moduleType: 'js' };
      }
      if (id.startsWith('\0')) return null;

      const result = await request('load', [id]);
      if (!result) return null;
      return { code: result.code, map: result.map || null, moduleType: 'js' };
    }
  },

  buildEnd() {
    if (config.modulesFile) {
      fs.writeFileSync(config.modulesFile, JSON.stringify([...this.getModuleIds()]));
    }
  }
};

const timing = config.timing ? (label) => process.stderr.write(`[rolldown] ${label} ${(performance.now() / 1000).toFixed(3)}s after node start\n`) : () => {};

async function build() {
  timing('script running');
  const { rolldown } = require(config.bundlerPath);
  timing('rolldown loaded');
  const bundle = await rolldown({
    input: ENTRY,
    cwd: config.cwd,
    platform: 'neutral',
    plugins: [condenser],
    resolve: {
      mainFields: ['module', 'main'],
      modules: config.modules,
      alias: { '@arcgis/lumina/controllers': '@arcgis/components-controllers' }
    },
    transform: {
      define: { 'process.env.NODE_ENV': JSON.stringify('production') }
    },
    onLog(level, log) {
      if (config.verbose) process.stderr.write(`[rolldown ${level}] ${log.message}\n`);
      if (level === 'warn') send({ method: 'warn', args: [log.message.replace(ANSI, '').trimEnd()] });
    }
  });

  timing('build done');
  try {
    const { output } = await bundle.generate({
      format: 'es',
      sourcemap: false,
      codeSplitting: false
    });
    timing('generate done');
    return output[0].code;
  } finally {
    await bundle.close();
  }
}

build().then(
  (code) => send({ method: 'done', args: [code] }, () => process.exit(0)),
  (e) => send({ method: 'error', args: [e.name || 'Error', e.message || String(e), e.stack || ''] }, () => process.exit(1))
);
