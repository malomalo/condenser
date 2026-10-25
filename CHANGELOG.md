# Changelog

## Unreleased

### Fixed / improved

- Concurrent builds on a listening environment no longer deadlock. A build takes the build cache's lock before counting itself, so a second thread waiting on the lock can't stop the first from releasing it. The build cache is created under a lock, so concurrent first requests share one cache and lock.
- `SVGTransformer` decodes SVGs as UTF-8, so non-ASCII text no longer reaches `JSON.generate` as BINARY (a warning in json 2, an error in json 3), and raises `Condenser::EncodingError` for an SVG that isn't valid UTF-8. Templates still get the source as read; a template that needs an encoding sets it itself (EJX does from malomalo/ejx#14).
- A byte order mark is now removed from text sources: the charset detection's result was being discarded.
- `Condenser::Server`, `Condenser`, `Condenser::BuildCache` and `Condenser::Export` have a short `#inspect`. The default one dumped the whole environment, so the Rails routing error page, which prints mounted apps, could fail with Nokogiri's "Document tree depth limit exceeded".
- `RolldownProcessor` resolves npm packages like Node, from the importing file up, so a package gets the dependency in its own nested `node_modules` instead of the top-level version of it.
- An import with an explicit extension only resolves to a file with that extension, or one converted to it: `import logo from 'images/logo.png'` no longer bundles `images/logo.svg`'s JavaScript module when both exist. Rolldown is only given the file it asked to load.

## 2.0.0.rc1

Changes since 1.5.1.

### Breaking changes / upgrade notes

- Ruby 3.3 or later is required (#29).
- `Condenser::RolldownProcessor` is the default JavaScript exporter, so bundling needs Node; `rolldown` is npm-installed into the npm path when the processor is created. Bundle output, digests and etags change (#38, #62, #63).
- `RolldownProcessor` is instance-only: register `Condenser::RolldownProcessor.new(npm_path)`, not the class. If the npm path is set after `Condenser.new`, register your own instance once it's set (#63).
- `Condenser::RollupProcessor` is deprecated, logs a warning on first use, and will be removed in 3.0 (#62).
- `RollupProcessor`'s `dynamic_imports:` only accepts `:inline` and `:keep`; `false` and `:local` raise (#50).
- sassc is replaced by Dart Sass through `sass-embedded`. Add `gem 'sass-embedded'` in place of `sassc`. Dart Sass is stricter, compiled CSS changes, errors are `Sass::CompileError`, custom functions use the `sass-embedded` API, and `SassTransformer`/`SassMinifier` take keyword options. `DartSassTransformer`/`DartScssTransformer` are removed (#39).
- `UglifyMinifier` is removed. The default pipeline minifies with Rolldown's built-in minifier (`RolldownProcessor.new(npm_path, minify: true)`) and registers no separate JS minifier. To use `TerserMinifier`, register a `RolldownProcessor` without `minify: true` (#76).
- `Condenser::LightningCSSMinifier` is the default CSS minifier, in place of `SassMinifier`. It needs `gem 'lightningcss', '>= 1.33.0.2'`; without it, minifying CSS raises a `LoadError` (#75).
- An import that resolves nowhere fails the Rolldown build instead of being left in the bundle with a warning (#78).
- A bare `// depends_on` path that matches no asset raises `Condenser::FileNotFound`. Use `!path` for a file relative to `base` (e.g. `// depends_on !config/credentials.yml`). Globs never raise (#81).
- ERB `depend_on` on a missing, non-glob path raises; pass `required: false` for the old behaviour (#60).
- Relative file and directory dependencies resolve against the source file (`./`, `../`) or the load paths (bare), not `Dir.pwd`, and missing ones raise `FileNotFound` (#66).
- New processors are instance-only where noted: `RolldownProcessor` (#63), `TailwindProcessor` (#68) and `LightningCSSExporter` (#49).
- ActiveSupport is no longer loaded at runtime. Code that relied on condenser loading it must require it itself (#83).
- `listen` is pinned to `~> 3.10` (#65), and `logger` is a runtime dependency.
- Cache keys and etags change: they are scoped to the processors each file uses and include Condenser's version, the Rolldown version and file dependencies (#36, #53, #63). Clear asset caches when upgrading.

### Added

- `Condenser::TailwindProcessor`, a Tailwind CSS v4 preprocessor running in a persistent Node worker (#68).
- `Condenser::LightningCSSExporter`, which lowers modern CSS and adds prefixes for browser `targets:` through the `lightningcss` gem (#49).
- `Condenser::LightningCSSMinifier`, with optional `targets:` (#75).
- `Condenser::RolldownProcessor`, with `prefix:`, `dynamic_imports:`, `aliases:`, `platform:`, `minify:` and `max_memory:` options (#38, #76).
- JSON imports with the Rolldown exporter, from the load paths or relative to the importer, including `.json.erb` (#78).
- `Condenser.new(listen: false)` to start no file listener; the Rake task's default environment no longer listens (#83).
- File and directory dependencies that aren't processed as assets (`input[:file_dependencies]`, `input[:directory_dependencies]`, `depend_on_file`, `depend_on_directory`), and `env.watch` to listen to paths outside the load paths (#53, #59).
- `// depends_on !path` for a file relative to `base` (#81).
- Sass imports of npm packages read the `exports` conditions and the `sass` and `style` fields, and resolve the package's relative imports (#79).
- `./` and `../` glob imports resolve against the importing file (#69).
- Optional chaining (`?.`) in JST templates.

### Fixed / improved

- Cold builds are about twice as fast: a direct-edge dependency index and a persistent JST Node worker (#29).
- Lookups that find nothing are cached while listening, and the build cache is cleared after npm installs (#30).
- The npm packages a bundle imports are part of its cache key and etag (#34).
- Cache keys are per file, from the part of the pipeline it uses, so the first warm build after a cold one no longer rebuilds everything (#36).
- The Rolldown version and `Condenser::VERSION` are in the cache keys and etags (#63).
- Linux: a file written to a new directory before inotify watches it is noticed (#58).
- A path that's already watched doesn't get a second listener (#59).
- Changed files are matched to load paths on a directory boundary, including nested load paths (#61).
- ERB assets keep the dependencies and links recorded by helpers such as `asset_path`, `depend_on` and `link_asset`; `asset_data_uri` works (#60).
- `JSAnalyzer` only matches `import`/`export` as whole tokens, and handles `import.meta` (#52).
- `Cache::NullStore` implements `fetch_if` and the rest of the cache interface (#77).
- Each cache store has its own `delete`; `FileStore#delete` removes the file (#80).
- Resolving with `npm: true` and no npm path no longer raises a `TypeError` (#64).
- `FileStore`, `Manifest` and `FileWriter` work without Rails (`zlib` and `condenser/utils` are required where used) (#31).
- `TerserMinifier` has an `options` reader, so registering an instance works (#76).
