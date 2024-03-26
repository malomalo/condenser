require 'test_helper'

class CacheTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.cache = Condenser::Cache::MemoryStore.new
  end
  
  test 'resolving and asset twice only compiles once' do
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"

    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS

    Condenser::Erubi.stubs(:call).never

    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS
  end
  
  test 'with a base set and the same cache, the second attempt from another location should use the cache' do
    @env.base = @path
    
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"
    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS
    
    @new_path = File.realpath(Dir.mktmpdir)
    @new_env = Condenser.new(@new_path, logger: Logger.new('/dev/null', level: :debug), base: @new_path)
    @new_env.unregister_writer(Condenser::ZlibWriter)
    @new_env.unregister_writer(Condenser::BrotliWriter)
    @new_env.cache = @env.cache
    FileUtils.cp(File.join(@path, 'test.txt.erb'), File.join(@new_path, 'test.txt.erb'))
    FileUtils.touch File.join(@new_path, 'test.txt.erb'), mtime: File.stat(File.join(@path, 'test.txt.erb')).mtime
    
    Condenser::Erubi.stubs(:call).never

    asset = @new_env.find('test.txt')
    asset.process
    assert_equal 'test.txt',     asset.filename
    assert_equal ['text/plain'], asset.content_types
    assert_equal('123'.rstrip, asset.source.rstrip)
  end

  test 'changing a source file reflects in the next call' do
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"

    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS

    file 'test.txt.erb', "1<%= 1 + 2 %>5\n"

    assert_file 'test.txt', 'text/plain', <<~CSS
    135
    CSS
  end

  test 'changing a source file on calls needs_reprocessing! and needs_reexporting! once' do
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"
    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS

    asset = @env.find('test.txt')

    asset.expects(:needs_reprocessing!).once
    asset.expects(:needs_reexporting!).once
    file 'test.txt.erb', "1<%= 1 + 2 %>5\n"
  end

  test 'changing a js dependency reflects in the next call' do
    file 'main.js', <<-JS
      import { cube } from 'math';

      console.log( cube( 5 ) ); // 125
    JS

    file 'math.js', <<-JS
      export function cube ( x ) {
        return x * x;
      }
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~CSS
      !function(){"use strict";var o;console.log((o=5)*o)}();
    CSS

    assert_exported_file 'main.js', 'application/javascript', <<~CSS
      !function(){"use strict";var o;console.log((o=5)*o)}();
    CSS

    file 'math.js', <<-JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~CSS
      !function(){"use strict";var o;console.log((o=5)*o*o)}();
    CSS
  end

  test 'changing a scss dependency reflects in the next call' do
    file "dir/a.scss", "body { color: blue; }"
    file "dir/b.scss", "body { color: green; }"

    file 'test.scss', '@import "dir/*"'

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{color:blue}body{color:green}
    CSS

    file "dir/b.scss", "body { color: red; }"

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{color:blue}body{color:red}
    CSS
  end

  test 'importing the same file from two spots' do
    file 'dep.js', <<-JS
      console.log( 5 );
    JS

    file 'a.js', <<-JS
      import 'dep';
    JS

    file 'b.js', <<-JS
      import 'dep';
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(5)}();
    JS
    assert_exported_file 'b.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(5)}();
    JS

    file 'dep.js', <<-JS
      console.log( 10 );
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(10)}();
    JS
    assert_exported_file 'b.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(10)}();
    JS

  end

  test 'a dependency is superceeded by a new file' do
    Dir.mkdir(File.join(@path, 'a'))
    Dir.mkdir(File.join(@path, 'b'))
    @env.clear_path
    @env.append_path File.join(@path, 'a')
    @env.append_path File.join(@path, 'b')
    
    file 'b/dep.js', <<-JS
      console.log( 5 );
    JS

    file 'a/a.js', <<-JS
      import 'dep';
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(5)}();
    JS

    file 'a/dep.js', <<-JS
      console.log( 10 );
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(10)}();
    JS
  end

  test 'a globed dependency is supurceeded by a new file' do
    Dir.mkdir(File.join(@path, 'a'))
    Dir.mkdir(File.join(@path, 'b'))
    @env.clear_path
    @env.append_path File.join(@path, 'a')
    @env.append_path File.join(@path, 'b')
    
    file 'b/deps/dep.js', <<-JS
      console.log( 5 );
    JS

    file 'a/a.js', <<-JS
      import 'deps/*';
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(5)}();
    JS

    file 'a/deps/dep.js', <<-JS
      console.log( 10 );
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(10)}();
    JS

    file 'a/deps/dep.js', <<-JS
      console.log( 20 );
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log(20)}();
    JS
  end
  
  test 'a new dependency for a glob call is reflected in the next call' do
    file "dir/a.scss", "body { color: blue; }"
    file 'test.scss', '@import "dir/*"'

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{color:blue}
    CSS

    file "dir/b.scss", "body { color: green; }"

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{color:blue}body{color:green}
    CSS
  end

  test '2a new dependency for a glob call is reflected in the next call' do
    file "dir/a.svg", "<svg>test</svg>"
    file 'test.scss', 'body { background: image-url("dir/a.svg") }'

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{background:url(/assets/dir/a-01a4bd3cb9faa518c5df2d2fcc8e6cd0ba24cfc3e9438dd01455ab1e59a39068.svg)}
    CSS

    file "dir/a.svg", "<svg>tests</svg>"

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{background:url(/assets/dir/a-1d7d038c7ace080963e116cbb962075a38d5e5dc68c6ff688e42d213dd432256.svg)}
    CSS
  end
  
  test 'a dependency is removed for a glob call when one of it dependencies is delted' do
    file "css/a.scss", "body { color: blue; }"
    file "css/b.scss", "body { color: green; }"
    file 'test.scss', '@import "css/*"'

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{color:blue}body{color:green}
    CSS

    rm "css/b.scss"

    assert_exported_file 'test.css', 'text/css', <<~CSS
      body{color:blue}
    CSS
  end

  test 'a dependency is added then changed should flush the parent (JS)' do
    file 'a.js', "console.log('a');\n"
    file 'b.js', <<~JS
      export default function b () { console.log('b'); }
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log("a")}();
    JS

    file 'a.js', <<~JS
      import b from 'b';
      console.log('a');
      b();
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log("a"),console.log("b")}();
    JS

    file 'b.js', <<~JS
      export default function b () { console.log('c'); }
    JS

    assert_exported_file 'a.js', 'application/javascript', <<~JS
      !function(){"use strict";console.log("a"),console.log("c")}();
    JS
  end

  test 'a dependency is added then changed should flush the parent (CSS)' do
    file 'a.scss', "body { background: aqua; }"
    file 'b.scss', <<~JS
      body { background: blue; }
    JS

    assert_exported_file 'a.css', 'text/css', <<~JS
      body{background:aqua}
    JS

    file 'a.scss', <<~JS
      @import "b";
      body { background: aqua; }
    JS

    assert_exported_file 'a.css', 'text/css', <<~JS
      body{background:blue}body{background:aqua}
    JS

    file 'b.scss', <<~JS
      body { background: green; }
    JS

    assert_exported_file 'a.css', 'text/css', <<~JS
      body{background:green}body{background:aqua}
    JS
  end

end
