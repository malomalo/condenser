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
end
