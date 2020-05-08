
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

### Invoking Ruby with ERB

Condenser provides an ERB engine for preprocessing assets using embedded Ruby
code. Append `.erb` to a CSS or JavaScript asset's filename to enable the ERB engine.

For example if you have an `app/application/javascripts/app_name.js.erb`
you could have this in the template

```js
var app_name = "<%= ENV['APP_NAME'] %>";
```

Generated files are cached. If you're using an `ENV` var then
when you change then ENV var the asset will be forced to
recompile. This behavior is only true for environment variables,
if you are pulling a value from somewhere else, such as a database,
must manually invalidate the cache to see the change.

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

If the `sassc` gem is available to your application, you can use Sass
to write CSS assets in Condenser.

Condenser supports both Sass syntaxes. For the original
whitespace-sensitive syntax, use the extension `.sass`. For the
new SCSS syntax, use the extension `.scss`.

In Rails if you have `app/application/stylesheets/foo.scss` it can
be referenced with `<%= asset_path("foo.css") %>`. When referencing
an asset in Rails, always specify the extension you want. Condenser will
convert `foo.scss` to `foo.css`.

## Javascript, ES#, & ES Modules

Condenser transforms Javascript for the browser by transpiling all the files
`.js` through [babel](https://babeljs.io) and bundled together via
[rollup.js](https://rollupjs.org/).

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
config.assets.js_minifier  = :uglify
config.assets.css_minifier = :scss
```

If you're not using Rails, configure this directly on the "environment".

``` ruby
environment.register_minifier 'text/css', Condenser::SassMinifier
environment.register_minifier 'application/javascript', Condenser::UglifyMinifier
```

If you are using Condenser directly with a Rack app, don't forget to add
the dependencies (the `sassc` gem in the example above) to your Gemfile.

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

Please see the [CHANGELOG](https://github.com/malomalo/condenser/tree/master/CHANGELOG.md)

## License
Condenser is released under the [MIT License](MIT-LICENSE).