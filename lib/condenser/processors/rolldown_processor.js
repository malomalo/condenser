const net = require('net');
const readline = require('readline');

const BUNDLER_PATH = process.argv[2];
const GLOB = '\0condenser-glob:';
const NODE_MODULES = /[\\/]node_modules[\\/]/;
const ANSI = /\x1b\[[0-9;]*m/g;

let rid = 0;
let rolldown = null;
const pending = new Map();
const channel = new net.Socket({ fd: 3 });
channel.on('error', () => process.exit(1));

function send(message, callback) {
  channel.write(JSON.stringify(message) + "\n", callback);
}

function request(build, method, args) {
  const id = rid++;
  return new Promise((resolve, reject) => {
    pending.set(id, (message) => {
      if (message.error === undefined) resolve(message['return']);
      else reject(new Error(message.error));
    });
    send({ rid: id, build, method, args });
  });
}

function condenserPlugin(build, entry) {
  return {
    name: 'condenser',

    resolveId: {
      filter: { id: { exclude: /^\0/ } },
      async handler(source, importer, options) {
        if (importer === undefined) return source === entry ? entry : null;
        // Glob modules import absolute paths.
        if (importer.startsWith('\0')) return null;

        if (options.kind === 'dynamic-import') {
          const asset = await request(build, 'resolveDynamicImport', [source, importer]);
          if (!asset) return null;
          if (asset.external) return { id: asset.path, external: 'absolute' };
          return asset.id;
        }

        // Inside node_modules everything is npm's business.
        if (NODE_MODULES.test(importer)) return null;
        if (source.endsWith('*')) return GLOB + source;

        // null falls through to Rolldown's node_modules resolution.
        return await request(build, 'resolve', [source, importer]);
      }
    },

    load: {
      filter: { id: { exclude: NODE_MODULES } },
      async handler(id) {
        if (id.startsWith(GLOB)) {
          const code = await request(build, 'glob', [id.slice(GLOB.length)]);
          return { code, moduleType: 'js' };
        }
        if (id.startsWith('\0')) return null;

        const result = await request(build, 'load', [id]);
        if (!result) return null;
        return { code: result.code, map: result.map || null, moduleType: 'js' };
      }
    }
  };
}

async function run(build, config) {
  rolldown ||= require(BUNDLER_PATH).rolldown;
  const bundle = await rolldown({
    input: config.entry,
    cwd: config.cwd,
    platform: config.platform,
    plugins: [condenserPlugin(build, config.entry)],
    resolve: {
      mainFields: ['module', 'main'],
      modules: config.modules,
      alias: config.aliases
    },
    transform: {
      define: { 'process.env.NODE_ENV': JSON.stringify('production') }
    },
    onLog(level, log) {
      if (level === 'warn') send({ method: 'warn', build, args: [log.message.replace(ANSI, '').trimEnd()] });
    }
  });

  try {
    const { output } = await bundle.generate({
      format: 'es',
      sourcemap: false,
      codeSplitting: false
    });
    return output[0].code;
  } finally {
    await bundle.close();
  }
}

function errorMessage(e) {
  if (!Array.isArray(e.errors)) return (e.message || String(e)).replace(ANSI, '');
  return e.errors.map((error) => {
    const file = error.loc?.file || error.id;
    const where = file ? (error.loc ? `${file}:${error.loc.line}:${error.loc.column + 1}: ` : `${file}: `) : '';
    return where + error.message.replace(ANSI, '').trimEnd();
  }).join('\n\n');
}

// Builds run one at a time, in the order they arrive.
let queue = Promise.resolve();
readline.createInterface({ input: channel, crlfDelay: Infinity }).on('line', (line) => {
  const message = JSON.parse(line);
  if (message.rid !== undefined) {
    const settle = pending.get(message.rid);
    pending.delete(message.rid);
    settle?.(message);
  } else if (message.build !== undefined) {
    queue = queue.then(() => run(message.build, message.config).then(
      (code) => send({ method: 'done', build: message.build, args: [code], rss: process.memoryUsage.rss() }),
      (e) => send({ method: 'error', build: message.build, args: [e.name || 'Error', errorMessage(e), e.stack || ''], rss: process.memoryUsage.rss() })
    ));
  }
}).on('close', () => process.exit(0));
