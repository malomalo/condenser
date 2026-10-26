
# Condenser

Condenser is a Ruby library for compiling and serving static web assets
inspired by [Sprockets](https://github.com/rails/sprockets). It features
a powerful pipeline that allows you to write assets in languages like Sass
and SCSS.

## Installation

In your project's `Gemfile` with Bundler:

``` ruby
gem 'condenser'
```

Or via Ruby Gems

``` sh
$ gem install condenser
```

If you are using Condenser with Rails, instead of the `condenser` gem use the
`condenser-rails` gem.

## Guides

For most people interested in Condenser, you will want to see the README below.

If you are a framework developer see [Building an Asset Processing Framework](guides/building_an_asset_processing_framework.md).

If you are a library developer who is extending Condenser, see [Extending Condenser](guides/extending_condenser.md).

If you want to work on Condenser or better understand how it works read [How Condenser Works](guides/how_condenser_works.md).

## Overview

Since you are likely using Condenser through another framework, there will be
configuration options you can toggle that will change behavior such as what
directories or files get compiled. For that documentation you should see your
framework's documentation.

#### Accessing Assets

Assets in Condenser are always referenced by their *logical path*.

The logical path is the path of the asset source file relative to its
containing directory in the load path. For example, if your load path
contains the directory `app/assets/javascripts`:

<table>
  <tr>
    <th>Logical path</th>
    <th>Source file on disk</th>
  </tr>
  <tr>
    <td>application.js</td>
    <td>app/assets/javascripts/application.js</td>
  </tr>
  <tr>
    <td>models/project.js</td>
    <td>app/assets/javascripts/models/project.js</td>
  </tr>
  <tr>
    <td>hello.js</td>
    <td>app/assets/javascripts/hello.coffee</td>
  </tr>
</table>

> Note: For assets that are compiled or transpiled, you may want to specify the
  extension that you want, not the extension on disk. For example we specified
  `hello.js` even if the file on disk is a coffeescript file, since the asset
  it will generate is javascript.

## File Order Processing

By default files are processed in alphabetical order. This behavior can impact
your asset compilation when one asset needs to be loaded before another.

For example if you have an `application.js` and it loads another directory

```js
import initializers from 'config/initializers/*';

initializers.forEach((i) => i());
```

The files in that directory will be loaded in alphabetical order. If the directory
looks like this:

```sh
$ ls -1 config/initializers/

alpha.js
beta.js
gamma.js
```

Then `alpha.js` will be loaded before either of the other two. This can be a
problem if `gamma.js` needs to be called before `alpha.js`. For files that are
order dependent you can either rename the files or require individual files
manually:

```js
import alpha from 'config/initializers/alpha';
import beta from 'config/initializers/beta';
import gamma from 'config/initializers/gamma';

gamma();
alpha();
beta();
```

## Directives

Sometimes you need to tell Condenser that a file depends on other files. For
example a `js.erb` file maybe dynamically update depending on the contents of a
folder as follows:

```js
console.log([<%= Dir.children("#{asset_path}/models").sort.map(&:inspect).join(', ') %>]);
```

To tell Condenser that this file depends on `models/*` simply add the depends_on
directive:

```js
// depends_on models/*.js

console.log([<%= Dir.children("#{asset_path}/models").sort.map(&:inspect).join(', ') %>]);
```

The directives must be the first portion of the file.

A `depends_on` path is looked up as follows:

1. A path starting with `!` is a file relative to the environment's `base`
   (`Rails.root` with condenser-rails), never an asset.
2. Any other path is an asset, looked up the same way as an import: in the
   load paths, relative to the file if it starts with `./` or `../`, or as an
   absolute path. A matching asset is a dependency like it always was.
3. If no asset matches and the path isn't a glob, a `./`, `../` or absolute
   path is used as a file.
4. If nothing is found, processing raises `Condenser::FileNotFound`. A bare
   path is never looked up in `base`; the error suggests the `!` form.

A file is a rebuild trigger only: when its contents change the asset is
rebuilt, but it's never included in the output. A running server notices the
change if the file is under a load path or a path passed to `watch`.

A glob never raises, even if it matches nothing.

For example, to rebuild a `js.erb` file when `config/credentials.yml` at the
app root changes:

```js
// depends_on !config/credentials.yml

const key = <%= YAML.load_file(Rails.root.join('config/credentials.yml'))['mapbox_key'].to_json %>;
```

Only a `!` path in the `depends_on` directive looks in `base`. Imports, Sass `@import` and
`@use`, `find`, `resolve`, `link_asset`, `depend_on` and `depend_on_file` never
do.

## Cache

Compiling assets is slow. It requires a lot of disk use to pull assets off of
hard drives, a lot of RAM to manipulate those files in memory, and a lot of CPU
for compilation operations. Because of this Condenser has a cache to speed up
asset compilation times. That's the good news. The bad news, is that Condenser
has a cache and if you've found a bug it's likely going to involve the cache.

By default Condenser uses the file system to cache assets. It makes sense that
Condenser does not want to generate assets that already exist on disk in
`public/assets`, what might not be as intuitive is that Condenser needs to cache
"partial" assets.

For example if you have an `application.js` and it is made up of `a.js`, `b.js`,
all the way to `z.js`

```js
import 'a';
import 'b';
// ...
import 'z';
```

The first time this file is compiled the `application.js` output will be written
to disk, but also intermediary compiled files for `a.js` etc. will be written to
the cache directory (usually `tmp/cache/assets`).

So, if `b.js` changes it will get recompiled. However instead of having to
recompile the other files from `a.js` to `z.js` since they did not change,
we can use the prior intermediary files stored in the cached values . If these
files were expensive to generate, then this "partial" asset cache strategy can
save a lot of time.

Directives such as `import` in Javascript and `@import` in SCSS tell Condenser
what assets need to be re-compiled when a file changes. Files are considered
"fresh" based on their inode number, mtime, size and a combination of cache keys.

In Rails you can force a "clean" install by clearing the `public/assets` and
`tmp/cache/assets` directories.

### Listening for changes

By default an environment starts a file listener
([Listen](https://github.com/guard/listen)) on its load paths and watched paths,
so a long running process, like a development server, notices changed, added
and removed files and rebuilds only what they affect. Listen is only used when it
has a native adapter for the platform (FSEvents, inotify, ...); it isn't used
when it would fall back to polling.

For one-off builds, like precompiling assets, or in production, pass
`listen: false`:

```ruby
env = Condenser.new('app/assets', listen: false)
```

No listener is started, for the load paths or for the paths passed to
`env.watch`, which are still recorded. Builds work the same and each new
environment checks the cache against the files' digests, so it picks up changes
made since the last build. A running environment doesn't notice files that
change after it has found an asset; create a new environment to see them.

`Rake::CondenserTask`'s default environment doesn't listen. When you set your
own `environment` on the task, pass `listen: false` to it.

### Depending on files that aren't assets

A processor whose output depends on files that aren't assets, like the
templates a utility CSS framework scans for class names, records them as file
and directory dependencies. They're digested rather than processed, so they
don't have to be on the load path or have an extension Condenser knows.

```ruby
def call(environment, input)
  input[:file_dependencies] << '/app/views/layouts/application.html.erb'
  # The names of the matching files in a directory, and its subdirectories
  input[:directory_dependencies] << { path: '/app/views', glob: '*.erb', recursive: true }
end
```

In ERB templates (and through `condenser_context` in Sass functions)
`depend_on_file(path)` and `depend_on_directory(path, glob:, recursive:)` do
the same.

Paths starting with `./` or `../` are relative to the directory of the asset's
source file. Other relative paths, like `'config/tailwind.css'`, are looked up
in the load paths, in order, like imports; they aren't relative to `base` or
`Dir.pwd`. Like an import they're looked up again when the cache is checked, so
a file added to an earlier load path takes over. A path that doesn't exist
raises `Condenser::FileNotFound`, so the build fails until the file is added.
In a processor, `environment.expand_dependency_path(path, source_file:
input[:source_file], directory: false)` gives the path to read, or raises
`Condenser::FileNotFound`.

A file dependency invalidates the asset when its contents change and a
directory dependency when a matching file or a subdirectory is added, removed
or renamed. Both are checked against the cache when a new process starts. A
running process notices them through the file listener, so they need to be on
the load path or a watched path. A watched path is listened to but assets
aren't resolved from it:

```ruby
env.watch(Rails.root, ignore: ['public/assets', 'storage', /\.log\z/])
```

`ignore` takes directories relative to the watched path, or Regexps matched
against the relative paths. `node_modules`, `.git`, `tmp` and `log` are always
ignored.

Watching a path that's already listened to (the same path, including through a
symlink, or a path under a load path or under a watched path that doesn't
ignore it) does nothing, so the first `ignore` for it applies. A watched path
that contains another one ignores it, since that one has its own listener.

### Invoking Ruby with ERB

Condenser provides an ERB engine for preprocessing assets using embedded Ruby
code. Append `.erb` to a CSS or JavaScript asset's filename to enable the ERB engine.

For example if you have an `app/application/javascripts/app_name.js.erb`
you could have this in the template

```js
var app_name = "<%= env_proxy['APP_NAME'] %>";
```

Generated files are cached. If you read an `ENV` var through `env_proxy` (or
declare it with `depend_on_env('APP_NAME')`) then when you change the ENV var
the asset will be forced to recompile in the next process. This behavior is
only true for environment variables, if you are pulling a value from somewhere
else, such as a database, must manually invalidate the cache to see the change.

`depend_on(path)` declares a dependency on another asset and returns it, and
`link_asset(path)` also adds it to the precompiled manifest. Paths starting
with `./` are relative to the template, and without an extension they match the
template's type. A missing asset raises `Condenser::FileNotFound`, unless it's
`depend_on(path, required: false)`, which returns nil. A glob like
`depend_on('icons/*.png')` returns the matching assets and never raises. Both
of those also invalidate the template when a matching file is added later.

If you're using Rails, there are helpers you can use such as `asset_url`
that will cause a recompile if the value changes.

For example if you have this in your `application.css.erb`

``` css.erb
.logo {
  background: url(<%= asset_url("logo.png") %>)
}
```

When you modify the `logo.png` on disk, it will force `application.css` to be
recompiled so that the fingerprint will be correct in the generated asset.

### Styling with Sass and SCSS

[Sass](http://sass-lang.com/) is a language that compiles to CSS and
adds features like nested rules, variables, mixins and selector
inheritance.

If the `sass-embedded` gem (Dart Sass) is available to your application, you can use Sass
to write CSS assets in Condenser.

Condenser supports both Sass syntaxes. For the original
whitespace-sensitive syntax, use the extension `.sass`. For the
new SCSS syntax, use the extension `.scss`.

In Rails if you have `app/application/stylesheets/foo.scss` it can
be referenced with `<%= asset_path("foo.css") %>`. When referencing
an asset in Rails, always specify the extension you want. Condenser will
convert `foo.scss` to `foo.css`.

### Browser Targets with Lightning CSS

If the `lightningcss` gem (native Rust bindings for
[Lightning CSS](https://lightningcss.dev)) is available to your application,
Condenser can transform CSS for the browsers you support, lowering modern
syntax such as nesting and `lab()` colors and adding vendor prefixes. Register
it as a `text/css` exporter so it runs once on the exported CSS (including CSS
compiled from Sass), before the minifier. `targets` is a Hash of browser to the
oldest version you support, either a major version or one with the minor
version such as `15.4` or `"15.4"`:

``` ruby
environment.register_exporter 'text/css', Condenser::LightningCSSExporter.new(targets: { safari: 15.4, chrome: 100, firefox: 100 })
```

Other options (`error_recovery`, `scope`) are passed to `LightningCSS.transform`.
It needs version 1.33.0.2 or later of the `lightningcss` gem. The default
`text/css` minifier, `Condenser::LightningCSSMinifier`, also takes `targets`,
so to lower syntax and minify in one pass register it with the targets instead
of adding an exporter (see [Minifying Assets](#minifying-assets)).

### Utility CSS with Tailwind

`Condenser::TailwindProcessor` compiles stylesheets that `@import
"tailwindcss"` or use `@reference` with [Tailwind CSS](https://tailwindcss.com)
v4, which needs [Node.js](https://nodejs.org/). Other stylesheets are left as
they are. Register it as a `text/css` preprocessor:

```ruby
env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(env.npm_path, base: Rails.root)
```

```css
/* app/assets/stylesheets/application.css */
@import "tailwindcss";
@source "../../../vendor/components";
```

When the processor is created, `tailwindcss`, `@tailwindcss/node`,
`@tailwindcss/oxide` and `ignore` are installed with `npm` into the npm path if
they aren't there, and their versions are read for the cache keys. Tailwind
runs in a node process that's kept running between builds, and each build
scans and compiles from scratch, so the output is the same as the
`tailwindcss` CLI's, with `base:` as its `--cwd`, and a class removed from the
templates is removed from the CSS.

`base:` is the directory Tailwind's automatic source detection scans, like the
CLI's `--cwd`. Without it a stylesheet has to say what to scan with
`@import "tailwindcss" source("../views")` or `source(none)` and `@source`.
`@source` paths are relative to the stylesheet, as in Tailwind.

A stylesheet that's built separately, and only needs `@apply`, `theme()` or
custom variants, can `@reference` the main one instead of importing Tailwind
again. It gets the main stylesheet's theme, utilities and variants but none of
its CSS, and since it has no utilities to generate nothing is scanned and it
doesn't need `base:`:

```css
/* app/assets/stylesheets/admin.css */
@reference "./application.css";
.btn { @apply px-4 font-bold text-brand; }
```

The path is resolved by Tailwind, relative to the stylesheet or as an npm
package, not through the load paths. The referenced file and what it imports
are file dependencies, so changing its `@theme` rebuilds the stylesheet.

Every file Tailwind scans is recorded as a file dependency, and every
directory it scans as a directory dependency (see [Depending on files that
aren't assets](#depending-on-files-that-arent-assets)), so editing a template's
classes, or adding a template, rebuilds the CSS. A running process only
notices that if the files are on the load path or a watched path, so watch the
directories Tailwind scans that aren't, usually the app's root:

```ruby
env.watch(Rails.root, ignore: ['public/assets', 'storage'])
```

The processor doesn't call `env.watch` itself: what to ignore under the root
is up to the app, and a process that gets the CSS from a persistent cache
doesn't run the processor at all. It logs a warning for each directory it
scans that isn't watched.

Automatic source detection skips gitignored files, and the gitignored
directories it finds, like `log/`, `tmp/` and `storage/`, aren't tracked
either, so files added there don't rebuild the CSS. Explicit `@source` paths
are always tracked, even in a gitignored directory like `node_modules/`.

`minify: true` minifies the CSS like `tailwindcss --minify`, with Tailwind's
own Lightning CSS pass. Condenser's default CSS minifier,
`LightningCSSMinifier`, also minifies with Lightning CSS, so with the default
pipeline `minify:` isn't needed. To minify only in the processor, unregister
the CSS minifier. Don't use `SassMinifier` with Tailwind: it rewrites
Tailwind's output differently and makes minified output bigger.

```ruby
env.unregister_minifier 'text/css'
env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(env.npm_path, base: Rails.root, minify: true)
```

## Javascript, ES#, & ES Modules

Condenser transforms Javascript for the browser by transpiling all the files
`.js` through [babel](https://babeljs.io) and bundled together via
[Rolldown](https://rolldown.rs/).

```js
// app/assets/javascript/application.js

var square = (n) => n * n

console.log(square);
```

Start a Rails server in development mode and visit
`localhost:3000/assets/application.js`, and this asset will be transpiled to
JavaScript:

```js
var square = function square(n) {
  return n * n;
};

console.log(square);
```

### Bundling with Rolldown

`Condenser.new`'s default pipeline bundles JavaScript with a
`Condenser::RolldownProcessor`, which needs [Node.js](https://nodejs.org/).
Rolldown runs in a node process that's kept running between builds. When the
processor is created, Rolldown is installed with `npm` into its npm path if
it isn't there, and its version is read for the cache keys. Without an npm
path, `rolldown` is loaded with Node's own module lookup (for example from
`NODE_PATH`).

The default `RolldownProcessor` minifies the bundle with Rolldown's built-in
(Oxc) minifier, `minify: true`, in the same native build. `RolldownProcessor.new`
defaults to `minify: false`, for readable bundles. The default pipeline
registers no `application/javascript` minifier; if you register one, e.g.
`TerserMinifier`, use a `RolldownProcessor` without `minify: true`, or the
bundle is minified twice.

`RolldownProcessor` is registered as an instance, and uses the npm path it's
created with. Pass `npm_path:` to `Condenser.new` so the default one gets it,
or, if the npm path is set afterwards, register your own once it's set:

```ruby
condenser.unregister_exporter('application/javascript')
condenser.register_exporter('application/javascript', Condenser::RolldownProcessor.new(condenser.npm_path, minify: true))
```

Since the version is read once, upgrading Rolldown takes effect when the
process restarts or a new processor is created.

An import that can't be resolved, as an asset or an npm package, fails the
build with an error naming the importing file and the import.

### Importing JSON

With Rolldown, a `.json` file can be imported like any other asset, from the
load paths or relative to the importing file. The extension is required, as in
Node; `import users from 'users'` doesn't find `users.json`.

```js
import users from 'users.json';
import { name } from 'config/app.json' with { type: 'json' };
```

The JSON is the default export, and its top-level keys that are valid
identifiers are also named exports. It's inlined into the bundle, and editing
it rebuilds the bundles that import it. JSON rendered from a template, such as
`users.json.erb`, is imported as `users.json`. `RollupProcessor` doesn't
support importing JSON.

### Importing images, fonts and other files

`module_types:` maps file extensions to the
[module types](https://rolldown.rs/in-depth/module-types) Rolldown loads them
as, like esbuild's `loader`:

```ruby
Condenser::RolldownProcessor.new(npm_path, module_types: { png: :dataurl, ttf: :base64 })
```

```js
import logo from 'images/logo.png';    // "data:image/png;base64,…"
import font from 'fonts/Regular.ttf';  // a base64 String
```

The types are `:base64`, `:binary` (a `Uint8Array`), `:dataurl`, `:empty`,
`:text` and the JavaScript and JSON types. `:asset`, `:copy` and `:css` aren't
supported, since they emit files and only the bundle is kept.

The file is found by its absolute path, `./` or `../` relative to the
importing file, in the load paths, or else through `aliases:`.
Rolldown reads it itself, so a module type is used instead of any processing
condenser does for that extension (with `svg: :text` an `.svg` import is its
markup, not the `SVGTransformer`'s module). A file that isn't found fails the
build. A dynamic `import()` of one is bundled, even with
`dynamic_imports: :keep`.

Replacing a file rebuilds the bundles that import it from the load paths or
relative to themselves. A file found only through an alias, outside the load
paths, isn't tracked, as with aliased JavaScript modules. `RollupProcessor`
doesn't support `module_types:`.

`Condenser::RollupProcessor` is deprecated and will be removed in condenser
3.0. Until then it can still be used by registering it in place of Rolldown:

```ruby
condenser.unregister_exporter('application/javascript')
condenser.register_exporter('application/javascript', Condenser::RollupProcessor)
```


### JavaScript Templating with EJS

Condenser supports *JavaScript templates* for client-side rendering of
strings or markup. JavaScript templates have the special format
extension `.jst` and are compiled to JavaScript functions.

The templates can then be imported. When invoked they will render the template
as a string that can be inserted into the DOM.

```javascript
<!-- templates/hello.jst.ejs -->
<div>Hello, <span><%= name %></span>!</div>

import hello from 'templates/hello';

$("#hello").html(hello({ name: "Sam" }));
```

If the `ejs` gem is available to your application, you can use EJS
templates in Condenser. EJS templates have the extension `.jst.ejs`.

### Minifying Assets

Several JavaScript and CSS minifiers are available through shorthand.

In Rails you will specify them with:

```ruby
config.assets.js_minifier  = :rolldown
config.assets.css_minifier = :lightning_css
```

If you're not using Rails, configure this directly on the "environment".

``` ruby
environment.register_minifier 'text/css', Condenser::LightningCSSMinifier
```

`Condenser.new`'s default pipeline minifies JavaScript with Rolldown (see
[Bundling with Rolldown](#bundling-with-rolldown)) and registers no separate
JavaScript minifier. To minify with [Terser](https://terser.org) instead,
register a `RolldownProcessor` that doesn't minify and `Condenser::TerserMinifier`,
which runs in Node and installs `terser` into the npm path:

``` ruby
environment.unregister_exporter 'application/javascript'
environment.register_exporter 'application/javascript', Condenser::RolldownProcessor.new(environment.npm_path)
environment.register_minifier 'application/javascript', Condenser::TerserMinifier.new(environment.npm_path)
```

`Condenser.new`'s default pipeline minifies CSS with
`Condenser::LightningCSSMinifier`, which needs the `lightningcss` gem (version
1.33.0.2 or later). The gem is only loaded when CSS is first minified, which
raises a `LoadError` if it's missing. To also lower modern syntax and add
vendor prefixes for your browsers, register it with `targets`, as for
`LightningCSSExporter`:

``` ruby
environment.register_minifier 'text/css', Condenser::LightningCSSMinifier.new(targets: { safari: 15.4, chrome: 100 })
```

`Condenser::SassMinifier` minifies CSS with Dart Sass instead, for apps that
already use the `sass-embedded` gem and don't want another native gem:

``` ruby
environment.register_minifier 'text/css', Condenser::SassMinifier
```

If you are using Condenser directly with a Rack app, don't forget to add
the dependencies (the `lightningcss` gem in the example above) to your Gemfile.

### Gzip

By default when Condenser generates a compiled asset file it will also produce a
gzipped copy of that file. Condenser only gzips non-binary files such as CSS,
javascript, and SVG files.

For example if Condenser is generating

```
application-12345.css
```

Then it will also generate a compressed copy in

```
application-12345.css.gz
```

This behavior can be disabled, refer to your framework specific documentation.

### Serving Assets

In production you should generate your assets to a directory on disk and serve
them either via Nginx or a feature like Rail's `config.public_file_server.enabled = true`.

On Rails you can generate assets by running:

```term
$ RAILS_ENV=production rails assets:precompile
```

In development Rails will serve assets from `Condenser::Server`.

### Version History

Please see the [CHANGELOG](https://github.com/malomalo/condenser/blob/master/CHANGELOG.md)

## License
Condenser is released under the [MIT License](LICENSE).