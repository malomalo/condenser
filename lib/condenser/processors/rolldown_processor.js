const net = require('net');
const path = require('path');
const readline = require('readline');

const BUNDLER_PATH = process.argv[2];
const GLOB = '\0condenser-glob:';
const NODE_MODULES = /[\\/]node_modules[\\/]/;
const RELATIVE = /^\.\.?\//;
const ANSI = /\x1b\[[0-9;]*m/g;
const CODE_CACHE_LIMIT = 64 * 1024 * 1024;

let rid = 0;
let rolldown = null;
const pending = new Map();
const codeCache = new Map();
let codeCacheSize = 0;
let codeCacheLimit = CODE_CACHE_LIMIT;
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

function cached(id, digest) {
  const hit = codeCache.get(id);
  if (!hit || hit.digest !== digest) return null;
  codeCache.delete(id);
  codeCache.set(id, hit);
  return hit;
}

function cache(id, digest, code) {
  const old = codeCache.get(id);
  if (old) codeCacheSize -= old.code.length;
  codeCache.delete(id);
  codeCache.set(id, { digest, code });
  codeCacheSize += code.length;
  for (const [key, value] of codeCache) {
    if (codeCacheSize <= codeCacheLimit) break;
    codeCache.delete(key);
    codeCacheSize -= value.code.length;
  }
}

// Only modules whose digest Ruby gave in this build are served from the
// cache.
function condenserPlugin(build, entry, entryDigest, moduleTypes = {}) {
  const digests = new Map([[entry, entryDigest]]);
  const globs = new Map();
  // The moduleType of each module Ruby resolved: 'js' or 'json'.
  const types = new Map();
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
          digests.set(asset.id, asset.digest);
          return asset.id;
        }

        // Inside node_modules everything is npm's business.
        if (NODE_MODULES.test(importer)) return null;
        if (source.endsWith('*')) {
          if (!RELATIVE.test(source)) return GLOB + source;
          // One module per directory a "./" or "../" glob is imported from.
          const id = GLOB + path.resolve(path.dirname(importer), source);
          globs.set(id, [source, importer]);
          return id;
        }

        // null falls through to Rolldown's node_modules resolution.
        const asset = await request(build, 'resolve', [source, importer]);
        if (!asset) return null;
        digests.set(asset.id, asset.digest);
        types.set(asset.id, asset.type);
        return asset.id;
      }
    },

    load: {
      filter: { id: { exclude: NODE_MODULES } },
      async handler(id) {
        if (id.startsWith(GLOB)) {
          const glob = await request(build, 'glob', globs.get(id) || [id.slice(GLOB.length), null]);
          for (const [file, digest] of Object.entries(glob.digests)) digests.set(file, digest);
          return { code: glob.code, moduleType: 'js' };
        }
        if (id.startsWith('\0')) return null;
        // Rolldown loads a file with a module type itself.
        if (id !== entry && Object.hasOwn(moduleTypes, path.extname(id))) return null;

        const moduleType = types.get(id) || 'js';
        const digest = digests.get(id);
        const hit = digest && cached(id, digest);
        if (hit) return { code: hit.code, moduleType };

        const result = await request(build, 'load', [id]);
        if (!result) return null;
        if (result.digest) cache(id, result.digest, result.code);
        return { code: result.code, moduleType };
      }
    }
  };
}

async function run(build, config) {
  rolldown ||= require(BUNDLER_PATH).rolldown;
  codeCacheLimit = config.codeCacheLimit ?? CODE_CACHE_LIMIT;
  const bundle = await rolldown({
    input: config.entry,
    cwd: config.cwd,
    platform: config.platform,
    plugins: [condenserPlugin(build, config.entry, config.entryDigest, config.moduleTypes)],
    moduleTypes: config.moduleTypes,
    resolve: {
      mainFields: ['module', 'main'],
      modules: config.modules,
      alias: config.aliases
    },
    transform: {
      define: { 'process.env.NODE_ENV': JSON.stringify('production') }
    },
    onLog(level, log, handler) {
      // An import nothing resolved would fail at runtime.
      if (log.code === 'UNRESOLVED_IMPORT') handler('error', log);
      else if (level === 'warn') send({ method: 'warn', build, args: [log.message.replace(ANSI, '').trimEnd()] });
    }
  });

  try {
    const { output } = await bundle.generate({
      format: 'es',
      sourcemap: false,
      codeSplitting: false,
      // Rolldown's default (unset) isn't the same as `minify: false`.
      minify: config.minify ? true : undefined
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
