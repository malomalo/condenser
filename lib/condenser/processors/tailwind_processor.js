const net = require('net');
const path = require('path');
const readline = require('readline');

// Stylesheets and plugins that aren't found from the stylesheet are looked
// up in the npm path, as @tailwindcss/node reads NODE_PATH when it loads.
const MODULES = process.argv[2];
process.env.NODE_PATH = [MODULES, process.env.NODE_PATH].filter(Boolean).join(path.delimiter);
const load = (name) => require(require.resolve(name, { paths: [MODULES] }));
const { compile, optimize } = load('@tailwindcss/node');
const { Scanner } = load('@tailwindcss/oxide');

const channel = new net.Socket({ fd: 3 });
channel.on('error', () => process.exit(1));

function send(message) {
  channel.write(JSON.stringify(message) + "\n");
}

// The same sources and steps as `tailwindcss --input file [--minify]`, with
// +base+ as its working directory.
async function run({ file, css, base, minify }) {
  const dependencies = [];
  const compiler = await compile(css, {
    from: file,
    base: path.dirname(file),
    onDependency: (dependency) => dependencies.push(dependency)
  });

  if (compiler.root === null && base === null) {
    throw new Error(`${file} uses automatic source detection, which needs the TailwindProcessor's base:, or set the sources with source(...) or source(none)`);
  }
  const sources = (compiler.root === 'none' ? []
    : compiler.root === null ? [{ base, pattern: '**/*', negated: false }]
    : [{ ...compiler.root, negated: false }]).concat(compiler.sources);
  sources.push({ base: path.dirname(file), pattern: path.basename(file), negated: false });

  const scanner = new Scanner({ sources });
  let output = compiler.build(scanner.scan());
  if (minify) output = optimize(output, { file, minify: true }).code;

  return { css: output, dependencies, files: scanner.files, globs: scanner.globs };
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
