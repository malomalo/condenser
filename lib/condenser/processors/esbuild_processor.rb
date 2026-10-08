# frozen_string_literal: true

require 'json'
require 'securerandom'

# A drop-in alternative to Condenser::RollupProcessor that bundles with
# esbuild.
#
# Only what condenser alone can resolve goes through Ruby: imports from files
# condenser loaded (load-path imports like `models/listing`, relative imports,
# `.erb`/`.ejx`/`.jst`/`.svg` files and glob imports). Those modules live in
# the `condenser` esbuild namespace and their source comes from the
# condenser pipeline. Anything Ruby can't find (bare npm imports) and every
# import made from a file in node_modules is resolved and read by esbuild
# itself.
class Condenser::EsbuildProcessor

  @@setup = []

  def self.setup(environment)
    install_npm_packages(environment.npm_path) if !default_bundler_path
  end

  def self.default_bundler_path
    ENV['CONDENSER_ESBUILD_PATH']
  end

  def self.install_npm_packages(npm_path)
    return if @@setup.include?(npm_path)

    ::Condenser::NodeProcessor.new(npm_path).npm_install('esbuild')
    @@setup << npm_path
  end

  def self.call(environment, input)
    @instances ||= {}
    (@instances[environment] ||= new(environment.npm_path)).call(environment, input)
  end

  def name
    self.class.name
  end

  def options
    {prefix: @prefix, dynamic_imports: @dynamic_imports}
  end

  # @param prefix [string] string to prefix to the url of dynamic imports
  # @param dynamic_imports [symbol] Default is :inline
  #    :inline - Inline dynamic imports into the output file.
  #    anything else (:keep, :local, false) - Keep the dynamic import but
  #    rewrite it to the URL of the imported asset.
  # @param bundler_path [string] path to the esbuild package to use. Defaults
  #    to $CONDENSER_ESBUILD_PATH, then esbuild in the npm path.
  # @param const_shim [boolean] rewrite `const` declarations that are later
  #    assigned to as `let`, since esbuild refuses to bundle them.
  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, const_shim: true)
    @bundler_path = bundler_path || self.class.default_bundler_path
    self.class.install_npm_packages(dir) if !@bundler_path
    @npm_dir = dir
    @prefix = prefix
    @dynamic_imports = dynamic_imports
    @const_shim = const_shim
    @const_patches = {}
  end

  def call(environment, input)
    Runner.new(@npm_dir, prefix: @prefix, dynamic_imports: @dynamic_imports, bundler_path: @bundler_path,
               const_shim: @const_shim, const_patches: @const_patches).call(environment, input)
  end

  class Runner < Condenser::NodeProcessor

    def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, const_shim: true, const_patches: {})
      super(dir)
      @const_shim = const_shim
      @const_patches = const_patches
      @prefix = prefix
      @dynamic_imports = dynamic_imports
      @bundler_path = bundler_path || npm_module_path('esbuild')
    end

    def call(environment, input)
      @environment = environment
      @input = input
      @accept = input[:content_types].last
      @assets = {}

      options = {
        entry: { id: input[:filename], path: input[:source_file] },
        esbuild: @bundler_path,
        npmRoot: environment.npm_path ? File.join(npm_module_path, '') : nil,
        nodePaths: environment.npm_path ? [npm_module_path] : [],
        workingDir: environment.npm_path || Dir.pwd,
        keepDynamicImports: @dynamic_imports != :inline,
        metafile: ENV['CONDENSER_ESBUILD_METAFILE'],
        constShim: @const_shim,
        constPatches: @const_patches
      }

      result = exec_runtime(SCRIPT, options)
      @const_patches.merge!(result['constPatches'] || {})
      input[:source] = result['code']
      input[:type] = 'module'
      input
    end

    def exec_runtime(script, options)
      token = "#{SecureRandom.hex(8)}:"
      env = { 'CONDENSER_TOKEN' => token, 'CONDENSER_OPTIONS' => JSON.generate(options) }
      io = IO.popen(env, [binary, '-e', script], 'r+')
      buffer = String.new
      result = nil
      error = nil

      begin
        while IO.select([io]) && (chunk = io.read_nonblock(65_536))
          buffer << chunk
          while (i = buffer.index("\n"))
            line = buffer.slice!(0, i + 1)
            if !line.start_with?(token)
              $stdout.write(line) if !line.strip.empty?
              next
            end

            message = JSON.parse(line.delete_prefix(token))
            case message['method']
            when 'done'
              result = message['args'][0]
            when 'error'
              error = message['args'][0]
            else
              ret = begin
                send("handle_#{message['method']}", *message['args'])
              rescue => e
                error = "#{e.class}: #{e.message}"
                nil
              end
              io.write(JSON.generate({ rid: message['rid'], return: ret }), "\n")
            end
          end
        end
      rescue Errno::EPIPE, EOFError
      end

      io.close
      raise exec_runtime_error(error) if error
      raise exec_runtime_error(buffer) if !$?.success? || result.nil?
      result
    end

    def importer_path(importer)
      importer.nil? || importer.empty? ? @input[:source_file] : importer
    end

    # Returns the source file condenser resolves +importee+ to, a glob marker,
    # or nil to let esbuild resolve it (npm packages).
    def handle_resolve(importee, importer)
      if importee.end_with?('*')
        path = importee.start_with?('.') ? File.expand_path(importee, File.dirname(importer_path(importer))) : importee
        { id: path, path: path, glob: true }
      else
        asset = @environment.find(importee, importer_path(importer), accept: @accept)
        return nil if !asset
        @assets[asset.source_file] = asset
        { id: asset.filename, path: asset.source_file }
      end
    end

    def handle_resolveDynamicImport(importee, importer)
      base = importer_path(importer)
      asset = @environment.find(importee, base, accept: @accept, npm: true)
      asset ||= @environment.find(importee.delete_suffix('.js') + "/index.js", base, accept: @accept, npm: true)
      asset ||= @environment.find(importee.gsub(/\/[^\/]+$/, '') + "/dist/index.js", base, accept: @accept, npm: true)
      return nil if !asset

      if asset.source_file == @input[:source_file]
        { id: @input[:filename], path: asset.source_file }
      else
        { external: File.join("/", *[@prefix, asset.path].compact) }
      end
    end

    def handle_load(path)
      if path == @input[:source_file]
        { code: @input[:source] }
      elsif path.end_with?('*')
        assets = @environment.resolve(path, nil, accept: @accept, npm: true)
        code = String.new
        names = []
        assets.each_with_index do |f, i|
          if f.has_default_export?
            code << "import _#{i} from #{JSON.generate(f.source_file)};\n"
            names << "_#{i}"
          elsif f.has_exports?
            code << "import * as _#{i} from #{JSON.generate(f.source_file)};\n"
            names << "_#{i}"
          else
            code << "import #{JSON.generate(f.source_file)};\n"
          end
        end
        code << "export default [#{names.join(', ')}];"
        { code: code }
      else
        asset = @assets[path] || @environment.find(path, accept: @accept)
        asset ? { code: asset.source } : nil
      end
    end

    SCRIPT = <<~'JS'
      const path = require('path');
      const fs = require('fs');
      const token = process.env.CONDENSER_TOKEN;
      const options = JSON.parse(process.env.CONDENSER_OPTIONS);
      const esbuild = require(options.esbuild);

      let rid = 0;
      const pending = new Map();
      function send(message, callback) { process.stdout.write(token + JSON.stringify(message) + "\n", callback); }
      // Exit only once the (possibly large) last message is flushed.
      const finish = (message, status) => send(message, () => process.exit(status));
      function request(method, ...args) {
        const id = rid++;
        return new Promise((resolve) => { pending.set(id, resolve); send({ rid: id, method, args }); });
      }
      // Memoized so a retried build (see constPatches) doesn't ask Ruby again.
      const memo = new Map();
      function cachedRequest(method, ...args) {
        const key = JSON.stringify([method, args]);
        if (!memo.has(key)) memo.set(key, request(method, ...args));
        return memo.get(key);
      }

      // esbuild refuses to bundle an assignment to a `const` (Rollup allows
      // it; it throws at runtime). Such declarations are rewritten to `let`:
      // {path: [[line, column, name]]}, learned from the error and kept by
      // Ruby across builds.
      const constPatches = options.constPatches || {};
      function applyConstPatches(file, code) {
        const patches = constPatches[file];
        if (!patches) return code;
        const lines = code.split("\n");
        for (const [line, column, name] of patches) {
          const text = lines[line - 1];
          if (text === undefined || text.substr(column, name.length) !== name) continue;
          const m = text.slice(0, column).match(/\bconst(\s+)$/);
          if (m) lines[line - 1] = text.slice(0, m.index) + 'let  ' + text.slice(m.index + 5);
        }
        return lines.join("\n");
      }
      function learnConstPatches(errors) {
        let learned = false;
        for (const e of errors) {
          const m = e.text.match(/^Cannot assign to "(.+)" because it is a constant$/);
          const decl = e.notes && e.notes[0] && e.notes[0].location;
          if (!m || !decl || !options.constShim) continue;
          const file = decl.file.replace(/^condenser:/, '');
          (constPatches[file] ||= []).push([decl.line, decl.column, m[1]]);
          learned = true;
        }
        return learned;
      }
      require('readline').createInterface({ input: process.stdin, crlfDelay: Infinity }).on('line', (line) => {
        const message = JSON.parse(line);
        const resolve = pending.get(message.rid);
        pending.delete(message.rid);
        resolve(message.return);
      });

      const inNpm = (p) => options.npmRoot && p.startsWith(options.npmRoot);

      const condenser = {
        name: 'condenser',
        setup(build) {
          // Modules in the condenser namespace are named by their asset
          // filename (so no local paths end up in the output); `files` maps
          // those names to source files.
          const files = new Map();
          const module = (r) => {
            files.set(r.id, r.path);
            return { path: r.id, namespace: 'condenser' };
          };
          const importer = (args) => files.get(args.importer);

          build.onResolve({ filter: /^condenser:entry$/ }, () => module(options.entry));

          if (options.keepDynamicImports) {
            build.onResolve({ filter: /.*/, namespace: 'condenser' }, async (args) => {
              if (args.kind !== 'dynamic-import') return undefined;
              const r = await cachedRequest('resolveDynamicImport', args.path, importer(args));
              if (!r) return undefined;
              if (r.external) return { path: r.external, external: true };
              return module(r);
            });
          }

          // Only imports made from modules condenser loaded reach Ruby; files
          // esbuild read itself (node_modules) are resolved by esbuild.
          build.onResolve({ filter: /.*/, namespace: 'condenser' }, async (args) => {
            // Condenser's files are ES modules; like Rollup's commonjs
            // plugin, leave any require() calls in them alone.
            if (args.kind === 'require-call') return { path: args.path, external: true };
            if (args.path === '@arcgis/lumina/controllers') {
              return build.resolve('@arcgis/components-controllers', { kind: args.kind, resolveDir: args.resolveDir });
            }
            const r = await cachedRequest('resolve', args.path, importer(args));
            if (!r) return undefined;
            if (!r.glob && inNpm(r.path)) return { path: r.path };
            return module(r);
          });

          build.onLoad({ filter: /.*/, namespace: 'condenser' }, async (args) => {
            const file = files.get(args.path);
            const r = await cachedRequest('load', file);
            if (!r) return { errors: [{ text: `Could not load "${file}"` }] };
            return {
              contents: applyConstPatches(args.path, r.code),
              loader: 'js',
              resolveDir: path.isAbsolute(file) ? path.dirname(file) : options.workingDir
            };
          });
        }
      };

      (async () => {
        try {
          const build = () => esbuild.build({
            entryPoints: ['condenser:entry'],
            bundle: true,
            write: false,
            format: 'esm',
            platform: 'neutral',
            target: 'esnext',
            mainFields: ['module', 'main'],
            conditions: ['module'],
            nodePaths: options.nodePaths,
            absWorkingDir: options.workingDir,
            define: { 'process.env.NODE_ENV': '"production"' },
            charset: 'utf8',
            // esbuild renames colliding top-level bindings (`var Modal2 =
            // class extends ...`), which changes `.name`; Rollup keeps it
            // (`let Modal$1 = class Modal`). Viking derives model names from
            // `.name`, so it has to be kept.
            keepNames: true,
            legalComments: 'inline',
            logLevel: 'silent',
            metafile: !!options.metafile,
            outfile: 'entry.js',
            plugins: [condenser]
          });
          let result;
          for (let attempt = 0; ; attempt++) {
            try {
              result = await build();
              break;
            } catch (e) {
              if (attempt > 4 || !e.errors || !learnConstPatches(e.errors)) throw e;
            }
          }
          if (options.metafile) fs.writeFileSync(options.metafile, JSON.stringify(result.metafile));
          // esbuild starts each module with a `// path` comment; drop the
          // ones for condenser's files so local paths don't end up in the
          // output (npm ones are relative to the npm path).
          const code = result.outputFiles[0].text.replace(/^\/\/ condenser:.*\n/gm, '');
          finish({ method: 'done', args: [{ code, constPatches }] }, 0);
        } catch (e) {
          let text = e.message;
          if (e.errors && e.errors.length) {
            text = (await esbuild.formatMessages(e.errors, { kind: 'error' })).join("\n");
          }
          finish({ method: 'error', args: [text] }, 1);
        }
      })();
    JS
  end
end
