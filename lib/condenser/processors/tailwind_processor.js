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

  return { css: output, dependencies, files: scanner.files, globs: scanner.globs };
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
