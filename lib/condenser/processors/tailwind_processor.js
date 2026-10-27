const fs = require('fs');
const net = require('net');
const path = require('path');
const readline = require('readline');

// Stylesheets and plugins that aren't found from the stylesheet are looked
// up in the npm path, as @tailwindcss/node reads NODE_PATH when it loads.
const MODULES = process.argv[2];
process.env.NODE_PATH = [MODULES, process.env.NODE_PATH].filter(Boolean).join(path.delimiter);
const load = (name) => require(require.resolve(name, { paths: [MODULES] }));
const { compile, optimize, Features } = load('@tailwindcss/node');
const { Scanner } = load('@tailwindcss/oxide');
const ignore = load('ignore');

const channel = new net.Socket({ fd: 3 });
channel.on('error', () => process.exit(1));

function send(message) {
  channel.write(JSON.stringify(message) + "\n");
}

// The same sources and steps as `tailwindcss --input file [--minify]`, with
// +base+ as its working directory, or with `source(none)` and an `@source`
// for each of the +extra+ directories if there are any.
async function run({ file, css, base, sources: extra, minify }) {
  const dependencies = [];
  const compiler = await compile(css, {
    from: file,
    base: path.dirname(file),
    onDependency: (dependency) => dependencies.push(dependency)
  });

  // Without `@tailwind utilities`, as in a stylesheet that only has
  // `@reference`, the candidates aren't used, so nothing is scanned, like
  // @tailwindcss/postcss and @tailwindcss/vite.
  if (!(compiler.features & Features.Utilities)) {
    return { css: finish(compiler.build([]), file, minify), dependencies, files: [], globs: [] };
  }

  if (compiler.root === null && base === null && extra.length === 0) {
    throw new Error(`${file} uses automatic source detection, which needs the environment's base or the TailwindProcessor's sources:, or set the sources with source(...) or source(none)`);
  }
  // The directories scanned by automatic detection: source(...) on the
  // import, or else the base unless there are +extra+ ones, and the +extra+
  // ones, which are scanned like @source paths. Then the @source paths
  // written in the stylesheet, and the stylesheet itself.
  const auto = (compiler.root === 'none' ? []
    : compiler.root !== null ? [{ ...compiler.root, negated: false }]
    : extra.length === 0 ? [{ base, pattern: '**/*', negated: false }]
    : []).concat(extra.map((dir) => ({ base: dir, pattern: '**/*', negated: false })));
  const explicit = compiler.sources.concat([{ base: path.dirname(file), pattern: path.basename(file), negated: false }]);
  const sources = auto.concat(explicit);

  const scanner = new Scanner({ sources });
  const output = finish(compiler.build(scanner.scan()), file, minify);

  if (auto.length === 0) {
    return { css: output, dependencies, files: scanner.files, globs: scanner.globs };
  }
  return { css: output, dependencies, ...withoutIgnored(scanner, auto, explicit) };
}

// Automatic source detection skips gitignored files, but Tailwind still
// reports globs for gitignored directories, such as an app's log/, tmp/ and
// storage/. These globs are dropped, with the files under them, which only
// a negation like `!/log/.keep` brings back. A directory automatic detection
// starts from, such as one of the sources:, is always kept, as are the
// directories in or around an explicit @source path.
function withoutIgnored(scanner, auto, explicit) {
  const directory = (s) => realpath(staticPrefix(path.resolve(s.base, s.pattern)));
  const roots = auto.map(directory);
  const kept = explicit.filter((s) => !s.negated).map(directory);
  const gitignores = new Map();
  const dropped = [];
  const globs = scanner.globs.filter((glob) => {
    const root = roots.filter((r) => inside(r, glob.base)).sort((a, b) => b.length - a.length)[0];
    const drop = root !== undefined && !roots.some((r) => inside(glob.base, r)) &&
      !kept.some((p) => inside(p, glob.base) || inside(glob.base, p)) &&
      gitignored(root, glob.base, probes(glob.pattern), gitignores);
    if (drop) dropped.push(glob.base);
    return !drop;
  });
  const files = scanner.files.filter((f) => !dropped.some((d) => inside(d, f)));
  return { files, globs };
}

// Whether +dir+, below +root+, is ignored by the .gitignore files from +root+
// down to it: it or a directory above it is ignored (`node_modules`,
// `/vendor`), or every file named in +names+ would be, for a pattern like
// `/log/*` that ignores the contents but not the directory, even with
// `!/log/.keep`. A deeper .gitignore takes precedence, as in git, and
// nothing below an ignored directory can be re-included.
function gitignored(root, dir, names, gitignores) {
  const levels = [];
  const test = (target, directory) => ignoredBy(levels, target, directory);

  let current = root;
  for (const part of ['', ...path.relative(root, dir).split(path.sep)]) {
    current = path.join(current, part);
    if (current !== root && test(current, true)) return true;

    const rules = gitignore(current, gitignores);
    if (rules) levels.push({ dir: current, rules });
  }
  return levels.length > 0 && names.every((name) => test(path.join(dir, name), false));
}

// Whether +target+ is ignored by the deepest of the +levels+ that has a rule
// for it.
function ignoredBy(levels, target, directory) {
  for (let i = levels.length - 1; i >= 0; i--) {
    const result = levels[i].rules.test(path.relative(levels[i].dir, target) + (directory ? '/' : ''));
    if (result.ignored || result.unignored) return result.ignored;
  }
  return false;
}

// The rules in +dir+'s .gitignore, or null.
function gitignore(dir, gitignores) {
  if (!gitignores.has(dir)) {
    const file = path.join(dir, '.gitignore');
    gitignores.set(dir, fs.existsSync(file) ? ignore().add(fs.readFileSync(file, 'utf8')) : null);
  }
  return gitignores.get(dir);
}

// A file name with each extension a glob like `**/*.{,erb,html}` scans.
function probes(pattern) {
  const extensions = pattern.match(/\.\{([^{}]*)\}/);
  return (extensions ? extensions[1].split(',') : ['']).map((ext) => ext ? `condenser-probe.${ext}` : 'condenser-probe');
}

// The part of a path before its first glob character.
function staticPrefix(pattern) {
  const parts = pattern.split(path.sep);
  const glob = parts.findIndex((part) => /[*?[\]{}]/.test(part));
  return glob === -1 ? pattern : parts.slice(0, glob).join(path.sep);
}

function inside(dir, file) {
  return file === dir || file.startsWith(dir.endsWith(path.sep) ? dir : dir + path.sep);
}

function realpath(file) {
  try { return fs.realpathSync(file); } catch { return file; }
}

function finish(css, file, minify) {
  return minify ? optimize(css, { file, minify: true }).code : css;
}

// Builds run one at a time, in the order they arrive.
let queue = Promise.resolve();
readline.createInterface({ input: channel, crlfDelay: Infinity }).on('line', (line) => {
  const message = JSON.parse(line);
  queue = queue.then(() => run(message.config).then(
    (result) => send({ method: 'done', build: message.build, args: [result], rss: process.memoryUsage.rss() }),
    (e) => send({ method: 'error', build: message.build, args: [e.name || 'Error', e.message || String(e), e.stack || ''], rss: process.memoryUsage.rss() })
  ));
}).on('close', () => process.exit(0));
