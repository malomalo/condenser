require 'test_helper'
require 'rack/builder'
require 'rack/test'

class ServerTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  
  def setup
    super
    server = Condenser::Server.new(@env)
    @app = nil
    @condenser_server = Rack::Builder.new do
      map "/assets" do
        run server
      end
    end

    file 'foo.js', <<~JS
      console.log(1);
    JS
  end
  
  def app
    @app ||= Rack::Lint.new(@condenser_server)
  end
  
  test "serve single source file" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status
    assert_equal "15", last_response.headers['Content-Length']
    assert_equal "Accept-Encoding", last_response.headers['Vary']
    assert_equal <<~JS.strip, last_response.body
      console.log(1);
    JS
  end

  # TODO:
  # test "serve single source file from cached environment" do
  #   get "/cached/javascripts/foo.js"
  #   assert_equal "var foo;\n", last_response.body
  # end

  test "serve source with dependencies" do
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) ); // 125
    JS
    file 'math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    get "/assets/main.js"
    assert_equal <<~JS.strip, last_response.body
      (()=>{var o;console.log((o=5)*o*o)})();
    JS
  end

  test "serve source with content type headers" do
    file 'main.css', <<~CSS
      body { background: green ; }
    CSS

    get "/assets/foo.js"
    assert_equal "application/javascript", last_response.headers['Content-Type']

    get "/assets/main.css"
    assert_equal "text/css; charset=utf-8", last_response.headers['Content-Type']
  end

  test "serve source with etag headers" do
    get "/assets/foo.js"

    digest = '35c146f76e129477c64061bc84511e1090f3d4d8059713e6663dd4b35b1f7642'
    assert_equal "\"#{digest}\"", last_response.headers['ETag']
  end

  test "not modified partial response when if-none-match etags match" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status
    etag, cache_control, expires, vary = last_response.headers.values_at(
      'ETag', 'Cache-Control', 'Expires', 'Vary'
    )

    assert_nil expires
    get "/assets/foo.js", {},
      'HTTP_IF_NONE_MATCH' => etag

    assert_equal 304, last_response.status

    # Allow 304 headers
    assert_equal cache_control, last_response.headers['Cache-Control']
    assert_equal etag, last_response.headers['ETag']
    assert_nil last_response.headers['Expires']
    assert_equal vary, last_response.headers['Vary']

    # Disallowed 304 headers
    refute last_response.headers['Content-Type']
    refute last_response.headers['Content-Length']
    refute last_response.headers['Content-Encoding']
  end

  test "response when if-none-match etags don't match" do
    get "/assets/foo.js", {},
      'HTTP_IF_NONE_MATCH' => "nope"

    assert_equal 200, last_response.status
    assert_equal '"35c146f76e129477c64061bc84511e1090f3d4d8059713e6663dd4b35b1f7642"', last_response.headers['ETag']
    assert_equal '15', last_response.headers['Content-Length']
  end

  test "not modified partial response with fingerprint and if-none-match etags match" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status

    etag   = last_response.headers['ETag']
    digest = etag[/"(.+)"/, 1]

    get "/assets/foo-#{digest}.js", {},
      'HTTP_IF_NONE_MATCH' => etag
    assert_equal 304, last_response.status
  end

  test "ok response with fingerprint and if-nonematch etags don't match" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status

    etag   = last_response.headers['ETag']
    digest = etag[/"(.+)"/, 1]

    get "/assets/foo-#{digest}.js", {},
      'HTTP_IF_NONE_MATCH' => "nope"
    assert_equal 200, last_response.status
  end

  test "not found with if-none-match" do
    get "/assets/missing.js", {},
      'HTTP_IF_NONE_MATCH' => '"000"'
    assert_equal 404, last_response.status
  end

  test "not found fingerprint with if-none-match" do
    get "/assets/missing-b452c9ae1d5c8d9246653e0d93bc83abce0ee09ef725c0f0a29a41269c217b83.js", {},
      'HTTP_IF_NONE_MATCH' => '"b452c9ae1d5c8d9246653e0d93bc83abce0ee09ef725c0f0a29a41269c217b83"'
    assert_equal 404, last_response.status
  end

  test "not found with response with incorrect fingerprint and matching if-none-match etags" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status

    etag = last_response.headers['ETag']

    get "/assets/foo-0000000000000000000000000000000000000000.js", {},
      'HTTP_IF_NONE_MATCH' => etag
    assert_equal 404, last_response.status
  end

  test "ok partial response when if-match etags match" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status
    etag = last_response.headers['ETag']

    get "/assets/foo.js", {},
      'HTTP_IF_MATCH' => etag

    assert_equal 200, last_response.status
    assert_equal '"35c146f76e129477c64061bc84511e1090f3d4d8059713e6663dd4b35b1f7642"', last_response.headers['ETag']
    assert_equal '15', last_response.headers['Content-Length']
  end

  test "precondition failed with if-match is a mismatch" do
    get "/assets/foo.js", {},
      'HTTP_IF_MATCH' => '"000"'
    assert_equal 412, last_response.status

    refute last_response.headers['ETag']
  end

  test "not found with if-match" do
    get "/assets/missing.js", {},
      'HTTP_IF_MATCH' => '"000"'
    assert_equal 404, last_response.status
  end

  # TODO:
  # test "if sources didnt change the server shouldnt rebundle" do
  #   get "/assets/application.js"
  #   asset_before = @env["application.js"]
  #   assert asset_before
  #
  #   get "/assets/application.js"
  #   asset_after = @env["application.js"]
  #   assert asset_after
  #
  #   assert asset_before.eql?(asset_after)
  # end
  #
  test "fingerprint digest sets expiration to the future" do
    get "/assets/foo.js"
    digest = last_response.headers['ETag'][/"(.+)"/, 1]

    get "/assets/foo-#{digest}.js"
    assert_equal 200, last_response.status
    assert_match %r{max-age}, last_response.headers['Cache-Control']
    assert_match %r{immutable}, last_response.headers['Cache-Control']
  end

  test "bad fingerprint digest returns a 404" do
    get "/assets/foo-0000000000000000000000000000000000000000.js"
    assert_equal 404, last_response.status

    head "/assets/foo-0000000000000000000000000000000000000000.js"
    assert_equal 404, last_response.status
    assert_equal "0", last_response.headers['Content-Length']
    assert_equal "", last_response.body
  end

  test "missing source" do
    get "/assets/none.js"
    assert_equal 404, last_response.status
    assert_equal "pass", last_response.headers['X-Cascade']
  end

  test "re-throw JS exceptions in the browser when using babel" do
    @env.unregister_preprocessor('application/javascript', Condenser::JSAnalyzer)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(@path,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    
    file 'error.js', "var error = {;"

    get "/assets/error.js"
    assert_equal 200, last_response.status
    assert_match(/SyntaxError: \/assets\/error\.js: Unexpected token/, last_response.body)
  end

  test "display CSS exceptions in the browser" do
    file 'error.scss', "* { color: $test; }"

    get "/assets/error.css"
    assert_equal 200, last_response.status
    assert_match %r{content: ".*?SassC::SyntaxError}, last_response.body
  end

  test "serve encoded utf-8 filename" do
    file '日本語.js', <<~JS
      var japanese = "日本語";

      console.log(japanese);
    JS
    get "/assets/%E6%97%A5%E6%9C%AC%E8%AA%9E.js"
    assert_equal <<~JS.strip, last_response.body
      console.log("日本語");
    JS
  end

  test "illegal require outside load path" do
    get "/assets//etc/passwd"
    assert_equal 403, last_response.status

    get "/assets/%2fetc/passwd"
    assert_equal 403, last_response.status

    get "/assets//%2fetc/passwd"
    assert_equal 403, last_response.status

    get "/assets/%2f/etc/passwd"
    assert_equal 403, last_response.status

    get "/assets/../etc/passwd"
    assert_equal 403, last_response.status

    get "/assets/%2e%2e/etc/passwd"
    assert_equal 403, last_response.status

    get "/assets/.-0000000./etc/passwd"
    assert_equal 403, last_response.status

    head "/assets/.-0000000./etc/passwd"
    assert_equal 403, last_response.status
    assert_equal "0", last_response.headers['Content-Length']
    assert_equal "", last_response.body
  end

  # TODO:
  # test "add new source to tree" do
  #   filename = fixture_path("server/app/javascripts/baz.js")
  #
  #   sandbox filename do
  #     get "/assets/tree.js"
  #     assert_equal "var foo;\n\n(function () {\n  application.boot();\n})();\nvar bar;\nvar japanese = \"日本語\";\n", last_response.body
  #
  #     File.open(filename, "w") do |f|
  #       f.write "var baz;\n"
  #     end
  #
  #     path = fixture_path "server/app/javascripts"
  #     mtime = Time.now + 60
  #     File.utime(mtime, mtime, path)
  #
  #     get "/assets/tree.js"
  #     assert_equal "var foo;\n\n(function () {\n  application.boot();\n})();\nvar bar;\nvar baz;\nvar japanese = \"日本語\";\n", last_response.body
  #   end
  # end

  test "serving static assets" do
    bytes = Random.new.bytes(128)
    file 'logo.png', bytes

    get "/assets/logo.png"
    assert_equal 200, last_response.status
    assert_equal "image/png", last_response.headers['Content-Type']
    refute last_response.headers['Content-Encoding']
    assert_equal bytes, last_response.body
  end

  test "disallow non-get methods" do
    get "/assets/foo.js"
    assert_equal 200, last_response.status

    head "/assets/foo.js"
    assert_equal 200, last_response.status
    assert_equal "application/javascript", last_response.headers['Content-Type']
    assert_equal "0", last_response.headers['Content-Length']
    assert_equal "", last_response.body

    post "/assets/foo.js"
    assert_equal 405, last_response.status

    put "/assets/foo.js"
    assert_equal 405, last_response.status

    delete "/assets/foo.js"
    assert_equal 405, last_response.status
  end

  test "invalid URLs" do
    get "/assets/%E2%EF%BF%BD%A6.js"
    assert_equal 400, last_response.status
  end

end
