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
// +base+ as its working directory, and the +extra+ directories scanned like
// `@source` paths.
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

  if (compiler.root === null && base === null) {
    throw new Error(`${file} uses automatic source detection, which needs the TailwindProcessor's base: or an app directory in the environment's base, or set the sources with source(...) or source(none)`);
  }
  const sources = (compiler.root === 'none' ? []
    : compiler.root === null ? [{ base, pattern: '**/*', negated: false }]
    : [{ ...compiler.root, negated: false }]).concat(compiler.sources);
  for (const dir of extra) sources.push({ base: dir, pattern: '**/*', negated: false });
  sources.push({ base: path.dirname(file), pattern: path.basename(file), negated: false });

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
