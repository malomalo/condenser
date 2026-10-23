require 'test_helper'

class RolldownJSONTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
  end

  def teardown
    super
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
  end

  def new_env
    @cache_dir ||= File.realpath(Dir.mktmpdir)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: Condenser::Cache::FileStore.new(@cache_dir))
    env.unregister_minifier('application/javascript')
    env.unregister_exporter('application/javascript')
    env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@npm_dir))
    env
  end

  test 'a JSON file is imported through the load paths' do
    file 'users.json', '{ "id": 999, "name": "Ben" }'
    file 'app/main.js', <<~JS
      import users from 'users.json';

      console.log( users );
    JS

    assert_exported_file 'app/main.js', 'application/javascript', <<~FILE
      // app/main.js
      console.log({
      	id: 999,
      	name: "Ben"
      });
    FILE
  end

  test 'a top-level key of a JSON file is a named import' do
    file 'users.json', '{ "id": 999, "name": "Ben", "not-an-identifier": true }'
    file 'main.js', <<~JS
      import { name } from 'users.json';

      console.log( name );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log("Ben");
    FILE
  end

  test 'a JSON array is the default export' do
    file 'ids.json', '[1, 2, 3]'
    file 'main.js', <<~JS
      import ids from 'ids.json';

      console.log( ids );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log([
      	1,
      	2,
      	3
      ]);
    FILE
  end

  test 'a JSON file is imported with a type: json import attribute' do
    file 'users.json', '{ "name": "Ben" }'
    file 'main.js', <<~JS
      import users from 'users.json' with { type: 'json' };

      console.log( users );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log({ name: "Ben" });
    FILE
  end

  test 'a JSON file is imported relative to the importing file' do
    file 'users.json', '{ "name": "Root" }'
    file 'app/users.json', '{ "name": "Ben" }'
    file 'app/main.js', <<~JS
      import users from './users.json';

      console.log( users );
    JS

    assert_exported_file 'app/main.js', 'application/javascript', <<~FILE
      // app/main.js
      console.log({ name: "Ben" });
    FILE
  end

  test 'a JSON file rendered from a template is imported' do
    file 'users.json.erb', '{ "id": <%= 3 * 333 %> }'
    file 'main.js', <<~JS
      import users from 'users.json';

      console.log( users );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log({ id: 999 });
    FILE
  end

  test 'a JSON file is not imported without its extension' do
    file 'users.json', '{ "name": "Ben" }'
    file 'main.js', <<~JS
      import users from 'users';

      console.log( users );
    JS

    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert error.message.start_with?("Error: #{@path}/main.js:1:19: [UNRESOLVED_IMPORT] Could not resolve 'users' in main.js"), error.message
  end

  test 'an edited JSON file rebuilds the bundle' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'users.json', '{ "name": "Ben" }'
    file 'main.js', <<~JS
      import users from 'users.json';

      console.log( users );
    JS

    assert_includes @env.find('main.js').export.source, '"Ben"'
    file 'users.json', '{ "name": "Jon" }'
    assert wait_until { @env.find('main.js').export.source.include?('"Jon"') }
  end

  test 'an edited JSON file rebuilds the bundle in a new process' do
    file 'users.json', '{ "name": "Ben" }'
    file 'main.js', <<~JS
      import users from 'users.json';

      console.log( users );
    JS

    asset = new_env.find('main.js').export
    assert_includes asset.source, '"Ben"'
    assert_equal asset.source, new_env.find('main.js').export.source

    file 'users.json', '{ "name": "Jon" }'
    rebuilt = new_env.find('main.js').export
    assert_includes rebuilt.source, '"Jon"'
    assert_not_equal asset.digest, rebuilt.digest
  end

  test 'an imported JSON file is an export dependency' do
    file 'users.json', '{ "name": "Ben" }'
    file 'main.js', <<~JS
      import users from 'users.json';

      console.log( users );
    JS

    assert_equal ['users.json'], @env.find('main.js').export_dependencies.map(&:filename)
  end

end
