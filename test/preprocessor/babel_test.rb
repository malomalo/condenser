require 'test_helper'

class CondenserBabelTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::JSAnalyzer)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(@npm_dir,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    @env.unregister_minifier    'application/javascript'
  end
  
  test 'find' do
    file 'name.js', <<~JS
    var t = { 'var': () => { return 2; } };
    
    export {t as name1};
    JS

    assert_file 'name.js', 'application/javascript', <<~JS
    var t = {
      'var': function _var() {
        return 2;
      }
    };
    export { t as name1 };
    JS
  end

  test "dependency tracking for a export from" do
    file 'c.js', <<~JS
    function c() { return 'ok'; }
    
    export {c}
    JS
    
    file 'b.js', <<~JS
    export {c} from 'c';
    
    JS
    
    file 'a.js', <<~JS
    import {c} from 'b'
    
    console.log(c());
    JS

    asset = assert_file 'a.js', 'application/javascript'
    assert_equal ['/a.js', '/b.js', '/c.js'], asset.all_export_dependencies.map { |path| path.delete_prefix(@path) }
  end

  test "error" do
    file 'error.js', <<~JS
      console.log('this file has an error');
      
      var error = {;
    JS

    e = assert_raises Condenser::SyntaxError do
      assert_file 'error.js', 'application/javascript'
    end
    assert_equal <<~ERROR.rstrip, e.message.rstrip
      /assets/error.js: Unexpected token (3:13)

        1 | console.log('this file has an error');
        2 |
      > 3 | var error = {;
          |              ^
        4 |
    ERROR
    assert_equal '/assets/error.js', e.path
  end

  test 'not duplicating polyfills' do
    file 'a.js', <<-JS
      export default function () {
        console.log(Object.assign({}, {a: 1}))
      };
    JS
    file 'b.js', <<-JS
      export default function () {
        console.log(Object.assign({}, {b: 1}))
      };
    JS
    file 'c.js', <<~JS
      import a from 'a';
      import b from 'b';

      a();
      b();
    JS

    assert_exported_file 'c.js', 'application/javascript', <<~JS
      (function () {
      	'use strict';

      	var commonjsGlobal = typeof globalThis !== 'undefined' ? globalThis : typeof window !== 'undefined' ? window : typeof global !== 'undefined' ? global : typeof self !== 'undefined' ? self : {};

      	function getDefaultExportFromCjs (x) {
      		return x && x.__esModule && Object.prototype.hasOwnProperty.call(x, 'default') ? x['default'] : x;
      	}

      	var es_object_assign = {};

      	var globalThis_1;
      	var hasRequiredGlobalThis;

      	function requireGlobalThis () {
      		if (hasRequiredGlobalThis) return globalThis_1;
      		hasRequiredGlobalThis = 1;
      		var check = function (it) {
      		  return it && it.Math === Math && it;
      		};

      		// https://github.com/zloirock/core-js/issues/86#issuecomment-115759028
      		globalThis_1 =
      		  // eslint-disable-next-line es/no-global-this -- safe
      		  check(typeof globalThis == 'object' && globalThis) ||
      		  check(typeof window == 'object' && window) ||
      		  // eslint-disable-next-line no-restricted-globals -- safe
      		  check(typeof self == 'object' && self) ||
      		  check(typeof commonjsGlobal == 'object' && commonjsGlobal) ||
      		  check(typeof globalThis_1 == 'object' && globalThis_1) ||
      		  // eslint-disable-next-line no-new-func -- fallback
      		  (function () { return this; })() || Function('return this')();
      		return globalThis_1;
      	}

      	var fails;
      	var hasRequiredFails;

      	function requireFails () {
      		if (hasRequiredFails) return fails;
      		hasRequiredFails = 1;
      		fails = function (exec) {
      		  try {
      		    return !!exec();
      		  } catch (error) {
      		    return true;
      		  }
      		};
      		return fails;
      	}

      	var functionBindNative;
      	var hasRequiredFunctionBindNative;

      	function requireFunctionBindNative () {
      		if (hasRequiredFunctionBindNative) return functionBindNative;
      		hasRequiredFunctionBindNative = 1;
      		var fails = requireFails();

      		functionBindNative = !fails(function () {
      		  // eslint-disable-next-line es/no-function-prototype-bind -- safe
      		  var test = (function () { /* empty */ }).bind();
      		  // eslint-disable-next-line no-prototype-builtins -- safe
      		  return typeof test != 'function' || test.hasOwnProperty('prototype');
      		});
      		return functionBindNative;
      	}

      	var functionApply;
      	var hasRequiredFunctionApply;

      	function requireFunctionApply () {
      		if (hasRequiredFunctionApply) return functionApply;
      		hasRequiredFunctionApply = 1;
      		var NATIVE_BIND = requireFunctionBindNative();

      		var FunctionPrototype = Function.prototype;
      		var apply = FunctionPrototype.apply;
      		var call = FunctionPrototype.call;

      		// eslint-disable-next-line es/no-function-prototype-bind, es/no-reflect -- safe
      		functionApply = typeof Reflect == 'object' && Reflect.apply || (NATIVE_BIND ? call.bind(apply) : function () {
      		  return call.apply(apply, arguments);
      		});
      		return functionApply;
      	}

      	var functionUncurryThis;
      	var hasRequiredFunctionUncurryThis;

      	function requireFunctionUncurryThis () {
      		if (hasRequiredFunctionUncurryThis) return functionUncurryThis;
      		hasRequiredFunctionUncurryThis = 1;
      		var NATIVE_BIND = requireFunctionBindNative();

      		var FunctionPrototype = Function.prototype;
      		var call = FunctionPrototype.call;
      		// eslint-disable-next-line es/no-function-prototype-bind -- safe
      		var uncurryThisWithBind = NATIVE_BIND && FunctionPrototype.bind.bind(call, call);

      		functionUncurryThis = NATIVE_BIND ? uncurryThisWithBind : function (fn) {
      		  return function () {
      		    return call.apply(fn, arguments);
      		  };
      		};
      		return functionUncurryThis;
      	}

      	var classofRaw;
      	var hasRequiredClassofRaw;

      	function requireClassofRaw () {
      		if (hasRequiredClassofRaw) return classofRaw;
      		hasRequiredClassofRaw = 1;
      		var uncurryThis = requireFunctionUncurryThis();

      		var toString = uncurryThis({}.toString);
      		var stringSlice = uncurryThis(''.slice);

      		classofRaw = function (it) {
      		  return stringSlice(toString(it), 8, -1);
      		};
      		return classofRaw;
      	}

      	var functionUncurryThisClause;
      	var hasRequiredFunctionUncurryThisClause;

      	function requireFunctionUncurryThisClause () {
      		if (hasRequiredFunctionUncurryThisClause) return functionUncurryThisClause;
      		hasRequiredFunctionUncurryThisClause = 1;
      		var classofRaw = requireClassofRaw();
      		var uncurryThis = requireFunctionUncurryThis();

      		functionUncurryThisClause = function (fn) {
      		  // Nashorn bug:
      		  //   https://github.com/zloirock/core-js/issues/1128
      		  //   https://github.com/zloirock/core-js/issues/1130
      		  if (classofRaw(fn) === 'Function') return uncurryThis(fn);
      		};
      		return functionUncurryThisClause;
      	}

      	var isCallable;
      	var hasRequiredIsCallable;

      	function requireIsCallable () {
      		if (hasRequiredIsCallable) return isCallable;
      		hasRequiredIsCallable = 1;
      		// https://tc39.es/ecma262/#sec-IsHTMLDDA-internal-slot
      		var documentAll = typeof document == 'object' && document.all;

      		// `IsCallable` abstract operation
      		// https://tc39.es/ecma262/#sec-iscallable
      		// eslint-disable-next-line unicorn/no-typeof-undefined -- required for testing
      		isCallable = typeof documentAll == 'undefined' && documentAll !== undefined ? function (argument) {
      		  return typeof argument == 'function' || argument === documentAll;
      		} : function (argument) {
      		  return typeof argument == 'function';
      		};
      		return isCallable;
      	}

      	var objectGetOwnPropertyDescriptor = {};

      	var descriptors;
      	var hasRequiredDescriptors;

      	function requireDescriptors () {
      		if (hasRequiredDescriptors) return descriptors;
      		hasRequiredDescriptors = 1;
      		var fails = requireFails();

      		// Detect IE8's incomplete defineProperty implementation
      		descriptors = !fails(function () {
      		  // eslint-disable-next-line es/no-object-defineproperty -- required for testing
      		  return Object.defineProperty({}, 1, { get: function () { return 7; } })[1] !== 7;
      		});
      		return descriptors;
      	}

      	var functionCall;
      	var hasRequiredFunctionCall;

      	function requireFunctionCall () {
      		if (hasRequiredFunctionCall) return functionCall;
      		hasRequiredFunctionCall = 1;
      		var NATIVE_BIND = requireFunctionBindNative();

      		var call = Function.prototype.call;
      		// eslint-disable-next-line es/no-function-prototype-bind -- safe
      		functionCall = NATIVE_BIND ? call.bind(call) : function () {
      		  return call.apply(call, arguments);
      		};
      		return functionCall;
      	}

      	var objectPropertyIsEnumerable = {};

      	var hasRequiredObjectPropertyIsEnumerable;

      	function requireObjectPropertyIsEnumerable () {
      		if (hasRequiredObjectPropertyIsEnumerable) return objectPropertyIsEnumerable;
      		hasRequiredObjectPropertyIsEnumerable = 1;
      		var $propertyIsEnumerable = {}.propertyIsEnumerable;
      		// eslint-disable-next-line es/no-object-getownpropertydescriptor -- safe
      		var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;

      		// Nashorn ~ JDK8 bug
      		var NASHORN_BUG = getOwnPropertyDescriptor && !$propertyIsEnumerable.call({ 1: 2 }, 1);

      		// `Object.prototype.propertyIsEnumerable` method implementation
      		// https://tc39.es/ecma262/#sec-object.prototype.propertyisenumerable
      		objectPropertyIsEnumerable.f = NASHORN_BUG ? function propertyIsEnumerable(V) {
      		  var descriptor = getOwnPropertyDescriptor(this, V);
      		  return !!descriptor && descriptor.enumerable;
      		} : $propertyIsEnumerable;
      		return objectPropertyIsEnumerable;
      	}

      	var createPropertyDescriptor;
      	var hasRequiredCreatePropertyDescriptor;

      	function requireCreatePropertyDescriptor () {
      		if (hasRequiredCreatePropertyDescriptor) return createPropertyDescriptor;
      		hasRequiredCreatePropertyDescriptor = 1;
      		createPropertyDescriptor = function (bitmap, value) {
      		  return {
      		    enumerable: !(bitmap & 1),
      		    configurable: !(bitmap & 2),
      		    writable: !(bitmap & 4),
      		    value: value
      		  };
      		};
      		return createPropertyDescriptor;
      	}

      	var indexedObject;
      	var hasRequiredIndexedObject;

      	function requireIndexedObject () {
      		if (hasRequiredIndexedObject) return indexedObject;
      		hasRequiredIndexedObject = 1;
      		var uncurryThis = requireFunctionUncurryThis();
      		var fails = requireFails();
      		var classof = requireClassofRaw();

      		var $Object = Object;
      		var split = uncurryThis(''.split);

      		// fallback for non-array-like ES3 and non-enumerable old V8 strings
      		indexedObject = fails(function () {
      		  // throws an error in rhino, see https://github.com/mozilla/rhino/issues/346
      		  // eslint-disable-next-line no-prototype-builtins -- safe
      		  return !$Object('z').propertyIsEnumerable(0);
      		}) ? function (it) {
      		  return classof(it) === 'String' ? split(it, '') : $Object(it);
      		} : $Object;
      		return indexedObject;
      	}

      	var isNullOrUndefined;
      	var hasRequiredIsNullOrUndefined;

      	function requireIsNullOrUndefined () {
      		if (hasRequiredIsNullOrUndefined) return isNullOrUndefined;
      		hasRequiredIsNullOrUndefined = 1;
      		// we can't use just `it == null` since of `document.all` special case
      		// https://tc39.es/ecma262/#sec-IsHTMLDDA-internal-slot-aec
      		isNullOrUndefined = function (it) {
      		  return it === null || it === undefined;
      		};
      		return isNullOrUndefined;
      	}

      	var requireObjectCoercible;
      	var hasRequiredRequireObjectCoercible;

      	function requireRequireObjectCoercible () {
      		if (hasRequiredRequireObjectCoercible) return requireObjectCoercible;
      		hasRequiredRequireObjectCoercible = 1;
      		var isNullOrUndefined = requireIsNullOrUndefined();

      		var $TypeError = TypeError;

      		// `RequireObjectCoercible` abstract operation
      		// https://tc39.es/ecma262/#sec-requireobjectcoercible
      		requireObjectCoercible = function (it) {
      		  if (isNullOrUndefined(it)) throw new $TypeError("Can't call method on " + it);
      		  return it;
      		};
      		return requireObjectCoercible;
      	}

      	var toIndexedObject;
      	var hasRequiredToIndexedObject;

      	function requireToIndexedObject () {
      		if (hasRequiredToIndexedObject) return toIndexedObject;
      		hasRequiredToIndexedObject = 1;
      		// toObject with fallback for non-array-like ES3 strings
      		var IndexedObject = requireIndexedObject();
      		var requireObjectCoercible = requireRequireObjectCoercible();

      		toIndexedObject = function (it) {
      		  return IndexedObject(requireObjectCoercible(it));
      		};
      		return toIndexedObject;
      	}

      	var isObject;
      	var hasRequiredIsObject;

      	function requireIsObject () {
      		if (hasRequiredIsObject) return isObject;
      		hasRequiredIsObject = 1;
      		var isCallable = requireIsCallable();

      		isObject = function (it) {
      		  return typeof it == 'object' ? it !== null : isCallable(it);
      		};
      		return isObject;
      	}

      	var path;
      	var hasRequiredPath;

      	function requirePath () {
      		if (hasRequiredPath) return path;
      		hasRequiredPath = 1;
      		path = {};
      		return path;
      	}

      	var getBuiltIn;
      	var hasRequiredGetBuiltIn;

      	function requireGetBuiltIn () {
      		if (hasRequiredGetBuiltIn) return getBuiltIn;
      		hasRequiredGetBuiltIn = 1;
      		var path = requirePath();
      		var globalThis = requireGlobalThis();
      		var isCallable = requireIsCallable();

      		var aFunction = function (variable) {
      		  return isCallable(variable) ? variable : undefined;
      		};

      		getBuiltIn = function (namespace, method) {
      		  return arguments.length < 2 ? aFunction(path[namespace]) || aFunction(globalThis[namespace])
      		    : path[namespace] && path[namespace][method] || globalThis[namespace] && globalThis[namespace][method];
      		};
      		return getBuiltIn;
      	}

      	var objectIsPrototypeOf;
      	var hasRequiredObjectIsPrototypeOf;

      	function requireObjectIsPrototypeOf () {
      		if (hasRequiredObjectIsPrototypeOf) return objectIsPrototypeOf;
      		hasRequiredObjectIsPrototypeOf = 1;
      		var uncurryThis = requireFunctionUncurryThis();

      		objectIsPrototypeOf = uncurryThis({}.isPrototypeOf);
      		return objectIsPrototypeOf;
      	}

      	var environmentUserAgent;
      	var hasRequiredEnvironmentUserAgent;

      	function requireEnvironmentUserAgent () {
      		if (hasRequiredEnvironmentUserAgent) return environmentUserAgent;
      		hasRequiredEnvironmentUserAgent = 1;
      		var globalThis = requireGlobalThis();

      		var navigator = globalThis.navigator;
      		var userAgent = navigator && navigator.userAgent;

      		environmentUserAgent = userAgent ? String(userAgent) : '';
      		return environmentUserAgent;
      	}

      	var environmentV8Version;
      	var hasRequiredEnvironmentV8Version;

      	function requireEnvironmentV8Version () {
      		if (hasRequiredEnvironmentV8Version) return environmentV8Version;
      		hasRequiredEnvironmentV8Version = 1;
      		var globalThis = requireGlobalThis();
      		var userAgent = requireEnvironmentUserAgent();

      		var process = globalThis.process;
      		var Deno = globalThis.Deno;
      		var versions = process && process.versions || Deno && Deno.version;
      		var v8 = versions && versions.v8;
      		var match, version;

      		if (v8) {
      		  match = v8.split('.');
      		  // in old Chrome, versions of V8 isn't V8 = Chrome / 10
      		  // but their correct versions are not interesting for us
      		  version = match[0] > 0 && match[0] < 4 ? 1 : +(match[0] + match[1]);
      		}

      		// BrowserFS NodeJS `process` polyfill incorrectly set `.v8` to `0.0`
      		// so check `userAgent` even if `.v8` exists, but 0
      		if (!version && userAgent) {
      		  match = userAgent.match(/Edge\\/(\\d+)/);
      		  if (!match || match[1] >= 74) {
      		    match = userAgent.match(/Chrome\\/(\\d+)/);
      		    if (match) version = +match[1];
      		  }
      		}

      		environmentV8Version = version;
      		return environmentV8Version;
      	}

      	var symbolConstructorDetection;
      	var hasRequiredSymbolConstructorDetection;

      	function requireSymbolConstructorDetection () {
      		if (hasRequiredSymbolConstructorDetection) return symbolConstructorDetection;
      		hasRequiredSymbolConstructorDetection = 1;
      		/* eslint-disable es/no-symbol -- required for testing */
      		var V8_VERSION = requireEnvironmentV8Version();
      		var fails = requireFails();
      		var globalThis = requireGlobalThis();

      		var $String = globalThis.String;

      		// eslint-disable-next-line es/no-object-getownpropertysymbols -- required for testing
      		symbolConstructorDetection = !!Object.getOwnPropertySymbols && !fails(function () {
      		  var symbol = Symbol('symbol detection');
      		  // Chrome 38 Symbol has incorrect toString conversion
      		  // `get-own-property-symbols` polyfill symbols converted to object are not Symbol instances
      		  // nb: Do not call `String` directly to avoid this being optimized out to `symbol+''` which will,
      		  // of course, fail.
      		  return !$String(symbol) || !(Object(symbol) instanceof Symbol) ||
      		    // Chrome 38-40 symbols are not inherited from DOM collections prototypes to instances
      		    !Symbol.sham && V8_VERSION && V8_VERSION < 41;
      		});
      		return symbolConstructorDetection;
      	}

      	var useSymbolAsUid;
      	var hasRequiredUseSymbolAsUid;

      	function requireUseSymbolAsUid () {
      		if (hasRequiredUseSymbolAsUid) return useSymbolAsUid;
      		hasRequiredUseSymbolAsUid = 1;
      		/* eslint-disable es/no-symbol -- required for testing */
      		var NATIVE_SYMBOL = requireSymbolConstructorDetection();

      		useSymbolAsUid = NATIVE_SYMBOL &&
      		  !Symbol.sham &&
      		  typeof Symbol.iterator == 'symbol';
      		return useSymbolAsUid;
      	}

      	var isSymbol;
      	var hasRequiredIsSymbol;

      	function requireIsSymbol () {
      		if (hasRequiredIsSymbol) return isSymbol;
      		hasRequiredIsSymbol = 1;
      		var getBuiltIn = requireGetBuiltIn();
      		var isCallable = requireIsCallable();
      		var isPrototypeOf = requireObjectIsPrototypeOf();
      		var USE_SYMBOL_AS_UID = requireUseSymbolAsUid();

      		var $Object = Object;

      		isSymbol = USE_SYMBOL_AS_UID ? function (it) {
      		  return typeof it == 'symbol';
      		} : function (it) {
      		  var $Symbol = getBuiltIn('Symbol');
      		  return isCallable($Symbol) && isPrototypeOf($Symbol.prototype, $Object(it));
      		};
      		return isSymbol;
      	}

      	var tryToString;
      	var hasRequiredTryToString;

      	function requireTryToString () {
      		if (hasRequiredTryToString) return tryToString;
      		hasRequiredTryToString = 1;
      		var $String = String;

      		tryToString = function (argument) {
      		  try {
      		    return $String(argument);
      		  } catch (error) {
      		    return 'Object';
      		  }
      		};
      		return tryToString;
      	}

      	var aCallable;
      	var hasRequiredACallable;

      	function requireACallable () {
      		if (hasRequiredACallable) return aCallable;
      		hasRequiredACallable = 1;
      		var isCallable = requireIsCallable();
      		var tryToString = requireTryToString();

      		var $TypeError = TypeError;

      		// `Assert: IsCallable(argument) is true`
      		aCallable = function (argument) {
      		  if (isCallable(argument)) return argument;
      		  throw new $TypeError(tryToString(argument) + ' is not a function');
      		};
      		return aCallable;
      	}

      	var getMethod;
      	var hasRequiredGetMethod;

      	function requireGetMethod () {
      		if (hasRequiredGetMethod) return getMethod;
      		hasRequiredGetMethod = 1;
      		var aCallable = requireACallable();
      		var isNullOrUndefined = requireIsNullOrUndefined();

      		// `GetMethod` abstract operation
      		// https://tc39.es/ecma262/#sec-getmethod
      		getMethod = function (V, P) {
      		  var func = V[P];
      		  return isNullOrUndefined(func) ? undefined : aCallable(func);
      		};
      		return getMethod;
      	}

      	var ordinaryToPrimitive;
      	var hasRequiredOrdinaryToPrimitive;

      	function requireOrdinaryToPrimitive () {
      		if (hasRequiredOrdinaryToPrimitive) return ordinaryToPrimitive;
      		hasRequiredOrdinaryToPrimitive = 1;
      		var call = requireFunctionCall();
      		var isCallable = requireIsCallable();
      		var isObject = requireIsObject();

      		var $TypeError = TypeError;

      		// `OrdinaryToPrimitive` abstract operation
      		// https://tc39.es/ecma262/#sec-ordinarytoprimitive
      		ordinaryToPrimitive = function (input, pref) {
      		  var fn, val;
      		  if (pref === 'string' && isCallable(fn = input.toString) && !isObject(val = call(fn, input))) return val;
      		  if (isCallable(fn = input.valueOf) && !isObject(val = call(fn, input))) return val;
      		  if (pref !== 'string' && isCallable(fn = input.toString) && !isObject(val = call(fn, input))) return val;
      		  throw new $TypeError("Can't convert object to primitive value");
      		};
      		return ordinaryToPrimitive;
      	}

      	var sharedStore = {exports: {}};

      	var isPure;
      	var hasRequiredIsPure;

      	function requireIsPure () {
      		if (hasRequiredIsPure) return isPure;
      		hasRequiredIsPure = 1;
      		isPure = true;
      		return isPure;
      	}

      	var defineGlobalProperty;
      	var hasRequiredDefineGlobalProperty;

      	function requireDefineGlobalProperty () {
      		if (hasRequiredDefineGlobalProperty) return defineGlobalProperty;
      		hasRequiredDefineGlobalProperty = 1;
      		var globalThis = requireGlobalThis();

      		// eslint-disable-next-line es/no-object-defineproperty -- safe
      		var defineProperty = Object.defineProperty;

      		defineGlobalProperty = function (key, value) {
      		  try {
      		    defineProperty(globalThis, key, { value: value, configurable: true, writable: true });
      		  } catch (error) {
      		    globalThis[key] = value;
      		  } return value;
      		};
      		return defineGlobalProperty;
      	}

      	var hasRequiredSharedStore;

      	function requireSharedStore () {
      		if (hasRequiredSharedStore) return sharedStore.exports;
      		hasRequiredSharedStore = 1;
      		var IS_PURE = requireIsPure();
      		var globalThis = requireGlobalThis();
      		var defineGlobalProperty = requireDefineGlobalProperty();

      		var SHARED = '__core-js_shared__';
      		var store = sharedStore.exports = globalThis[SHARED] || defineGlobalProperty(SHARED, {});

      		(store.versions || (store.versions = [])).push({
      		  version: '3.42.0',
      		  mode: IS_PURE ? 'pure' : 'global',
      		  copyright: '© 2014-2025 Denis Pushkarev (zloirock.ru)',
      		  license: 'https://github.com/zloirock/core-js/blob/v3.42.0/LICENSE',
      		  source: 'https://github.com/zloirock/core-js'
      		});
      		return sharedStore.exports;
      	}

      	var shared;
      	var hasRequiredShared;

      	function requireShared () {
      		if (hasRequiredShared) return shared;
      		hasRequiredShared = 1;
      		var store = requireSharedStore();

      		shared = function (key, value) {
      		  return store[key] || (store[key] = value || {});
      		};
      		return shared;
      	}

      	var toObject;
      	var hasRequiredToObject;

      	function requireToObject () {
      		if (hasRequiredToObject) return toObject;
      		hasRequiredToObject = 1;
      		var requireObjectCoercible = requireRequireObjectCoercible();

      		var $Object = Object;

      		// `ToObject` abstract operation
      		// https://tc39.es/ecma262/#sec-toobject
      		toObject = function (argument) {
      		  return $Object(requireObjectCoercible(argument));
      		};
      		return toObject;
      	}

      	var hasOwnProperty_1;
      	var hasRequiredHasOwnProperty;

      	function requireHasOwnProperty () {
      		if (hasRequiredHasOwnProperty) return hasOwnProperty_1;
      		hasRequiredHasOwnProperty = 1;
      		var uncurryThis = requireFunctionUncurryThis();
      		var toObject = requireToObject();

      		var hasOwnProperty = uncurryThis({}.hasOwnProperty);

      		// `HasOwnProperty` abstract operation
      		// https://tc39.es/ecma262/#sec-hasownproperty
      		// eslint-disable-next-line es/no-object-hasown -- safe
      		hasOwnProperty_1 = Object.hasOwn || function hasOwn(it, key) {
      		  return hasOwnProperty(toObject(it), key);
      		};
      		return hasOwnProperty_1;
      	}

      	var uid;
      	var hasRequiredUid;

      	function requireUid () {
      		if (hasRequiredUid) return uid;
      		hasRequiredUid = 1;
      		var uncurryThis = requireFunctionUncurryThis();

      		var id = 0;
      		var postfix = Math.random();
      		var toString = uncurryThis(1.0.toString);

      		uid = function (key) {
      		  return 'Symbol(' + (key === undefined ? '' : key) + ')_' + toString(++id + postfix, 36);
      		};
      		return uid;
      	}

      	var wellKnownSymbol;
      	var hasRequiredWellKnownSymbol;

      	function requireWellKnownSymbol () {
      		if (hasRequiredWellKnownSymbol) return wellKnownSymbol;
      		hasRequiredWellKnownSymbol = 1;
      		var globalThis = requireGlobalThis();
      		var shared = requireShared();
      		var hasOwn = requireHasOwnProperty();
      		var uid = requireUid();
      		var NATIVE_SYMBOL = requireSymbolConstructorDetection();
      		var USE_SYMBOL_AS_UID = requireUseSymbolAsUid();

      		var Symbol = globalThis.Symbol;
      		var WellKnownSymbolsStore = shared('wks');
      		var createWellKnownSymbol = USE_SYMBOL_AS_UID ? Symbol['for'] || Symbol : Symbol && Symbol.withoutSetter || uid;

      		wellKnownSymbol = function (name) {
      		  if (!hasOwn(WellKnownSymbolsStore, name)) {
      		    WellKnownSymbolsStore[name] = NATIVE_SYMBOL && hasOwn(Symbol, name)
      		      ? Symbol[name]
      		      : createWellKnownSymbol('Symbol.' + name);
      		  } return WellKnownSymbolsStore[name];
      		};
      		return wellKnownSymbol;
      	}

      	var toPrimitive;
      	var hasRequiredToPrimitive;

      	function requireToPrimitive () {
      		if (hasRequiredToPrimitive) return toPrimitive;
      		hasRequiredToPrimitive = 1;
      		var call = requireFunctionCall();
      		var isObject = requireIsObject();
      		var isSymbol = requireIsSymbol();
      		var getMethod = requireGetMethod();
      		var ordinaryToPrimitive = requireOrdinaryToPrimitive();
      		var wellKnownSymbol = requireWellKnownSymbol();

      		var $TypeError = TypeError;
      		var TO_PRIMITIVE = wellKnownSymbol('toPrimitive');

      		// `ToPrimitive` abstract operation
      		// https://tc39.es/ecma262/#sec-toprimitive
      		toPrimitive = function (input, pref) {
      		  if (!isObject(input) || isSymbol(input)) return input;
      		  var exoticToPrim = getMethod(input, TO_PRIMITIVE);
      		  var result;
      		  if (exoticToPrim) {
      		    if (pref === undefined) pref = 'default';
      		    result = call(exoticToPrim, input, pref);
      		    if (!isObject(result) || isSymbol(result)) return result;
      		    throw new $TypeError("Can't convert object to primitive value");
      		  }
      		  if (pref === undefined) pref = 'number';
      		  return ordinaryToPrimitive(input, pref);
      		};
      		return toPrimitive;
      	}

      	var toPropertyKey;
      	var hasRequiredToPropertyKey;

      	function requireToPropertyKey () {
      		if (hasRequiredToPropertyKey) return toPropertyKey;
      		hasRequiredToPropertyKey = 1;
      		var toPrimitive = requireToPrimitive();
      		var isSymbol = requireIsSymbol();

      		// `ToPropertyKey` abstract operation
      		// https://tc39.es/ecma262/#sec-topropertykey
      		toPropertyKey = function (argument) {
      		  var key = toPrimitive(argument, 'string');
      		  return isSymbol(key) ? key : key + '';
      		};
      		return toPropertyKey;
      	}

      	var documentCreateElement;
      	var hasRequiredDocumentCreateElement;

      	function requireDocumentCreateElement () {
      		if (hasRequiredDocumentCreateElement) return documentCreateElement;
      		hasRequiredDocumentCreateElement = 1;
      		var globalThis = requireGlobalThis();
      		var isObject = requireIsObject();

      		var document = globalThis.document;
      		// typeof document.createElement is 'object' in old IE
      		var EXISTS = isObject(document) && isObject(document.createElement);

      		documentCreateElement = function (it) {
      		  return EXISTS ? document.createElement(it) : {};
      		};
      		return documentCreateElement;
      	}

      	var ie8DomDefine;
      	var hasRequiredIe8DomDefine;

      	function requireIe8DomDefine () {
      		if (hasRequiredIe8DomDefine) return ie8DomDefine;
      		hasRequiredIe8DomDefine = 1;
      		var DESCRIPTORS = requireDescriptors();
      		var fails = requireFails();
      		var createElement = requireDocumentCreateElement();

      		// Thanks to IE8 for its funny defineProperty
      		ie8DomDefine = !DESCRIPTORS && !fails(function () {
      		  // eslint-disable-next-line es/no-object-defineproperty -- required for testing
      		  return Object.defineProperty(createElement('div'), 'a', {
      		    get: function () { return 7; }
      		  }).a !== 7;
      		});
      		return ie8DomDefine;
      	}

      	var hasRequiredObjectGetOwnPropertyDescriptor;

      	function requireObjectGetOwnPropertyDescriptor () {
      		if (hasRequiredObjectGetOwnPropertyDescriptor) return objectGetOwnPropertyDescriptor;
      		hasRequiredObjectGetOwnPropertyDescriptor = 1;
      		var DESCRIPTORS = requireDescriptors();
      		var call = requireFunctionCall();
      		var propertyIsEnumerableModule = requireObjectPropertyIsEnumerable();
      		var createPropertyDescriptor = requireCreatePropertyDescriptor();
      		var toIndexedObject = requireToIndexedObject();
      		var toPropertyKey = requireToPropertyKey();
      		var hasOwn = requireHasOwnProperty();
      		var IE8_DOM_DEFINE = requireIe8DomDefine();

      		// eslint-disable-next-line es/no-object-getownpropertydescriptor -- safe
      		var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;

      		// `Object.getOwnPropertyDescriptor` method
      		// https://tc39.es/ecma262/#sec-object.getownpropertydescriptor
      		objectGetOwnPropertyDescriptor.f = DESCRIPTORS ? $getOwnPropertyDescriptor : function getOwnPropertyDescriptor(O, P) {
      		  O = toIndexedObject(O);
      		  P = toPropertyKey(P);
      		  if (IE8_DOM_DEFINE) try {
      		    return $getOwnPropertyDescriptor(O, P);
      		  } catch (error) { /* empty */ }
      		  if (hasOwn(O, P)) return createPropertyDescriptor(!call(propertyIsEnumerableModule.f, O, P), O[P]);
      		};
      		return objectGetOwnPropertyDescriptor;
      	}

      	var isForced_1;
      	var hasRequiredIsForced;

      	function requireIsForced () {
      		if (hasRequiredIsForced) return isForced_1;
      		hasRequiredIsForced = 1;
      		var fails = requireFails();
      		var isCallable = requireIsCallable();

      		var replacement = /#|\\.prototype\\./;

      		var isForced = function (feature, detection) {
      		  var value = data[normalize(feature)];
      		  return value === POLYFILL ? true
      		    : value === NATIVE ? false
      		    : isCallable(detection) ? fails(detection)
      		    : !!detection;
      		};

      		var normalize = isForced.normalize = function (string) {
      		  return String(string).replace(replacement, '.').toLowerCase();
      		};

      		var data = isForced.data = {};
      		var NATIVE = isForced.NATIVE = 'N';
      		var POLYFILL = isForced.POLYFILL = 'P';

      		isForced_1 = isForced;
      		return isForced_1;
      	}

      	var functionBindContext;
      	var hasRequiredFunctionBindContext;

      	function requireFunctionBindContext () {
      		if (hasRequiredFunctionBindContext) return functionBindContext;
      		hasRequiredFunctionBindContext = 1;
      		var uncurryThis = requireFunctionUncurryThisClause();
      		var aCallable = requireACallable();
      		var NATIVE_BIND = requireFunctionBindNative();

      		var bind = uncurryThis(uncurryThis.bind);

      		// optional / simple context binding
      		functionBindContext = function (fn, that) {
      		  aCallable(fn);
      		  return that === undefined ? fn : NATIVE_BIND ? bind(fn, that) : function (/* ...args */) {
      		    return fn.apply(that, arguments);
      		  };
      		};
      		return functionBindContext;
      	}

      	var objectDefineProperty = {};

      	var v8PrototypeDefineBug;
      	var hasRequiredV8PrototypeDefineBug;

      	function requireV8PrototypeDefineBug () {
      		if (hasRequiredV8PrototypeDefineBug) return v8PrototypeDefineBug;
      		hasRequiredV8PrototypeDefineBug = 1;
      		var DESCRIPTORS = requireDescriptors();
      		var fails = requireFails();

      		// V8 ~ Chrome 36-
      		// https://bugs.chromium.org/p/v8/issues/detail?id=3334
      		v8PrototypeDefineBug = DESCRIPTORS && fails(function () {
      		  // eslint-disable-next-line es/no-object-defineproperty -- required for testing
      		  return Object.defineProperty(function () { /* empty */ }, 'prototype', {
      		    value: 42,
      		    writable: false
      		  }).prototype !== 42;
      		});
      		return v8PrototypeDefineBug;
      	}

      	var anObject;
      	var hasRequiredAnObject;

      	function requireAnObject () {
      		if (hasRequiredAnObject) return anObject;
      		hasRequiredAnObject = 1;
      		var isObject = requireIsObject();

      		var $String = String;
      		var $TypeError = TypeError;

      		// `Assert: Type(argument) is Object`
      		anObject = function (argument) {
      		  if (isObject(argument)) return argument;
      		  throw new $TypeError($String(argument) + ' is not an object');
      		};
      		return anObject;
      	}

      	var hasRequiredObjectDefineProperty;

      	function requireObjectDefineProperty () {
      		if (hasRequiredObjectDefineProperty) return objectDefineProperty;
      		hasRequiredObjectDefineProperty = 1;
      		var DESCRIPTORS = requireDescriptors();
      		var IE8_DOM_DEFINE = requireIe8DomDefine();
      		var V8_PROTOTYPE_DEFINE_BUG = requireV8PrototypeDefineBug();
      		var anObject = requireAnObject();
      		var toPropertyKey = requireToPropertyKey();

      		var $TypeError = TypeError;
      		// eslint-disable-next-line es/no-object-defineproperty -- safe
      		var $defineProperty = Object.defineProperty;
      		// eslint-disable-next-line es/no-object-getownpropertydescriptor -- safe
      		var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
      		var ENUMERABLE = 'enumerable';
      		var CONFIGURABLE = 'configurable';
      		var WRITABLE = 'writable';

      		// `Object.defineProperty` method
      		// https://tc39.es/ecma262/#sec-object.defineproperty
      		objectDefineProperty.f = DESCRIPTORS ? V8_PROTOTYPE_DEFINE_BUG ? function defineProperty(O, P, Attributes) {
      		  anObject(O);
      		  P = toPropertyKey(P);
      		  anObject(Attributes);
      		  if (typeof O === 'function' && P === 'prototype' && 'value' in Attributes && WRITABLE in Attributes && !Attributes[WRITABLE]) {
      		    var current = $getOwnPropertyDescriptor(O, P);
      		    if (current && current[WRITABLE]) {
      		      O[P] = Attributes.value;
      		      Attributes = {
      		        configurable: CONFIGURABLE in Attributes ? Attributes[CONFIGURABLE] : current[CONFIGURABLE],
      		        enumerable: ENUMERABLE in Attributes ? Attributes[ENUMERABLE] : current[ENUMERABLE],
      		        writable: false
      		      };
      		    }
      		  } return $defineProperty(O, P, Attributes);
      		} : $defineProperty : function defineProperty(O, P, Attributes) {
      		  anObject(O);
      		  P = toPropertyKey(P);
      		  anObject(Attributes);
      		  if (IE8_DOM_DEFINE) try {
      		    return $defineProperty(O, P, Attributes);
      		  } catch (error) { /* empty */ }
      		  if ('get' in Attributes || 'set' in Attributes) throw new $TypeError('Accessors not supported');
      		  if ('value' in Attributes) O[P] = Attributes.value;
      		  return O;
      		};
      		return objectDefineProperty;
      	}

      	var createNonEnumerableProperty;
      	var hasRequiredCreateNonEnumerableProperty;

      	function requireCreateNonEnumerableProperty () {
      		if (hasRequiredCreateNonEnumerableProperty) return createNonEnumerableProperty;
      		hasRequiredCreateNonEnumerableProperty = 1;
      		var DESCRIPTORS = requireDescriptors();
      		var definePropertyModule = requireObjectDefineProperty();
      		var createPropertyDescriptor = requireCreatePropertyDescriptor();

      		createNonEnumerableProperty = DESCRIPTORS ? function (object, key, value) {
      		  return definePropertyModule.f(object, key, createPropertyDescriptor(1, value));
      		} : function (object, key, value) {
      		  object[key] = value;
      		  return object;
      		};
      		return createNonEnumerableProperty;
      	}

      	var _export;
      	var hasRequired_export;

      	function require_export () {
      		if (hasRequired_export) return _export;
      		hasRequired_export = 1;
      		var globalThis = requireGlobalThis();
      		var apply = requireFunctionApply();
      		var uncurryThis = requireFunctionUncurryThisClause();
      		var isCallable = requireIsCallable();
      		var getOwnPropertyDescriptor = requireObjectGetOwnPropertyDescriptor().f;
      		var isForced = requireIsForced();
      		var path = requirePath();
      		var bind = requireFunctionBindContext();
      		var createNonEnumerableProperty = requireCreateNonEnumerableProperty();
      		var hasOwn = requireHasOwnProperty();
      		// add debugging info
      		requireSharedStore();

      		var wrapConstructor = function (NativeConstructor) {
      		  var Wrapper = function (a, b, c) {
      		    if (this instanceof Wrapper) {
      		      switch (arguments.length) {
      		        case 0: return new NativeConstructor();
      		        case 1: return new NativeConstructor(a);
      		        case 2: return new NativeConstructor(a, b);
      		      } return new NativeConstructor(a, b, c);
      		    } return apply(NativeConstructor, this, arguments);
      		  };
      		  Wrapper.prototype = NativeConstructor.prototype;
      		  return Wrapper;
      		};

      		/*
      		  options.target         - name of the target object
      		  options.global         - target is the global object
      		  options.stat           - export as static methods of target
      		  options.proto          - export as prototype methods of target
      		  options.real           - real prototype method for the `pure` version
      		  options.forced         - export even if the native feature is available
      		  options.bind           - bind methods to the target, required for the `pure` version
      		  options.wrap           - wrap constructors to preventing global pollution, required for the `pure` version
      		  options.unsafe         - use the simple assignment of property instead of delete + defineProperty
      		  options.sham           - add a flag to not completely full polyfills
      		  options.enumerable     - export as enumerable property
      		  options.dontCallGetSet - prevent calling a getter on target
      		  options.name           - the .name of the function if it does not match the key
      		*/
      		_export = function (options, source) {
      		  var TARGET = options.target;
      		  var GLOBAL = options.global;
      		  var STATIC = options.stat;
      		  var PROTO = options.proto;

      		  var nativeSource = GLOBAL ? globalThis : STATIC ? globalThis[TARGET] : globalThis[TARGET] && globalThis[TARGET].prototype;

      		  var target = GLOBAL ? path : path[TARGET] || createNonEnumerableProperty(path, TARGET, {})[TARGET];
      		  var targetPrototype = target.prototype;

      		  var FORCED, USE_NATIVE, VIRTUAL_PROTOTYPE;
      		  var key, sourceProperty, targetProperty, nativeProperty, resultProperty, descriptor;

      		  for (key in source) {
      		    FORCED = isForced(GLOBAL ? key : TARGET + (STATIC ? '.' : '#') + key, options.forced);
      		    // contains in native
      		    USE_NATIVE = !FORCED && nativeSource && hasOwn(nativeSource, key);

      		    targetProperty = target[key];

      		    if (USE_NATIVE) if (options.dontCallGetSet) {
      		      descriptor = getOwnPropertyDescriptor(nativeSource, key);
      		      nativeProperty = descriptor && descriptor.value;
      		    } else nativeProperty = nativeSource[key];

      		    // export native or implementation
      		    sourceProperty = (USE_NATIVE && nativeProperty) ? nativeProperty : source[key];

      		    if (!FORCED && !PROTO && typeof targetProperty == typeof sourceProperty) continue;

      		    // bind methods to global for calling from export context
      		    if (options.bind && USE_NATIVE) resultProperty = bind(sourceProperty, globalThis);
      		    // wrap global constructors for prevent changes in this version
      		    else if (options.wrap && USE_NATIVE) resultProperty = wrapConstructor(sourceProperty);
      		    // make static versions for prototype methods
      		    else if (PROTO && isCallable(sourceProperty)) resultProperty = uncurryThis(sourceProperty);
      		    // default case
      		    else resultProperty = sourceProperty;

      		    // add a flag to not completely full polyfills
      		    if (options.sham || (sourceProperty && sourceProperty.sham) || (targetProperty && targetProperty.sham)) {
      		      createNonEnumerableProperty(resultProperty, 'sham', true);
      		    }

      		    createNonEnumerableProperty(target, key, resultProperty);

      		    if (PROTO) {
      		      VIRTUAL_PROTOTYPE = TARGET + 'Prototype';
      		      if (!hasOwn(path, VIRTUAL_PROTOTYPE)) {
      		        createNonEnumerableProperty(path, VIRTUAL_PROTOTYPE, {});
      		      }
      		      // export virtual prototype methods
      		      createNonEnumerableProperty(path[VIRTUAL_PROTOTYPE], key, sourceProperty);
      		      // export real prototype methods
      		      if (options.real && targetPrototype && (FORCED || !targetPrototype[key])) {
      		        createNonEnumerableProperty(targetPrototype, key, sourceProperty);
      		      }
      		    }
      		  }
      		};
      		return _export;
      	}

      	var mathTrunc;
      	var hasRequiredMathTrunc;

      	function requireMathTrunc () {
      		if (hasRequiredMathTrunc) return mathTrunc;
      		hasRequiredMathTrunc = 1;
      		var ceil = Math.ceil;
      		var floor = Math.floor;

      		// `Math.trunc` method
      		// https://tc39.es/ecma262/#sec-math.trunc
      		// eslint-disable-next-line es/no-math-trunc -- safe
      		mathTrunc = Math.trunc || function trunc(x) {
      		  var n = +x;
      		  return (n > 0 ? floor : ceil)(n);
      		};
      		return mathTrunc;
      	}

      	var toIntegerOrInfinity;
      	var hasRequiredToIntegerOrInfinity;

      	function requireToIntegerOrInfinity () {
      		if (hasRequiredToIntegerOrInfinity) return toIntegerOrInfinity;
      		hasRequiredToIntegerOrInfinity = 1;
      		var trunc = requireMathTrunc();

      		// `ToIntegerOrInfinity` abstract operation
      		// https://tc39.es/ecma262/#sec-tointegerorinfinity
      		toIntegerOrInfinity = function (argument) {
      		  var number = +argument;
      		  // eslint-disable-next-line no-self-compare -- NaN check
      		  return number !== number || number === 0 ? 0 : trunc(number);
      		};
      		return toIntegerOrInfinity;
      	}

      	var toAbsoluteIndex;
      	var hasRequiredToAbsoluteIndex;

      	function requireToAbsoluteIndex () {
      		if (hasRequiredToAbsoluteIndex) return toAbsoluteIndex;
      		hasRequiredToAbsoluteIndex = 1;
      		var toIntegerOrInfinity = requireToIntegerOrInfinity();

      		var max = Math.max;
      		var min = Math.min;

      		// Helper for a popular repeating case of the spec:
      		// Let integer be ? ToInteger(index).
      		// If integer < 0, let result be max((length + integer), 0); else let result be min(integer, length).
      		toAbsoluteIndex = function (index, length) {
      		  var integer = toIntegerOrInfinity(index);
      		  return integer < 0 ? max(integer + length, 0) : min(integer, length);
      		};
      		return toAbsoluteIndex;
      	}

      	var toLength;
      	var hasRequiredToLength;

      	function requireToLength () {
      		if (hasRequiredToLength) return toLength;
      		hasRequiredToLength = 1;
      		var toIntegerOrInfinity = requireToIntegerOrInfinity();

      		var min = Math.min;

      		// `ToLength` abstract operation
      		// https://tc39.es/ecma262/#sec-tolength
      		toLength = function (argument) {
      		  var len = toIntegerOrInfinity(argument);
      		  return len > 0 ? min(len, 0x1FFFFFFFFFFFFF) : 0; // 2 ** 53 - 1 == 9007199254740991
      		};
      		return toLength;
      	}

      	var lengthOfArrayLike;
      	var hasRequiredLengthOfArrayLike;

      	function requireLengthOfArrayLike () {
      		if (hasRequiredLengthOfArrayLike) return lengthOfArrayLike;
      		hasRequiredLengthOfArrayLike = 1;
      		var toLength = requireToLength();

      		// `LengthOfArrayLike` abstract operation
      		// https://tc39.es/ecma262/#sec-lengthofarraylike
      		lengthOfArrayLike = function (obj) {
      		  return toLength(obj.length);
      		};
      		return lengthOfArrayLike;
      	}

      	var arrayIncludes;
      	var hasRequiredArrayIncludes;

      	function requireArrayIncludes () {
      		if (hasRequiredArrayIncludes) return arrayIncludes;
      		hasRequiredArrayIncludes = 1;
      		var toIndexedObject = requireToIndexedObject();
      		var toAbsoluteIndex = requireToAbsoluteIndex();
      		var lengthOfArrayLike = requireLengthOfArrayLike();

      		// `Array.prototype.{ indexOf, includes }` methods implementation
      		var createMethod = function (IS_INCLUDES) {
      		  return function ($this, el, fromIndex) {
      		    var O = toIndexedObject($this);
      		    var length = lengthOfArrayLike(O);
      		    if (length === 0) return !IS_INCLUDES && -1;
      		    var index = toAbsoluteIndex(fromIndex, length);
      		    var value;
      		    // Array#includes uses SameValueZero equality algorithm
      		    // eslint-disable-next-line no-self-compare -- NaN check
      		    if (IS_INCLUDES && el !== el) while (length > index) {
      		      value = O[index++];
      		      // eslint-disable-next-line no-self-compare -- NaN check
      		      if (value !== value) return true;
      		    // Array#indexOf ignores holes, Array#includes - not
      		    } else for (;length > index; index++) {
      		      if ((IS_INCLUDES || index in O) && O[index] === el) return IS_INCLUDES || index || 0;
      		    } return !IS_INCLUDES && -1;
      		  };
      		};

      		arrayIncludes = {
      		  // `Array.prototype.includes` method
      		  // https://tc39.es/ecma262/#sec-array.prototype.includes
      		  includes: createMethod(true),
      		  // `Array.prototype.indexOf` method
      		  // https://tc39.es/ecma262/#sec-array.prototype.indexof
      		  indexOf: createMethod(false)
      		};
      		return arrayIncludes;
      	}

      	var hiddenKeys;
      	var hasRequiredHiddenKeys;

      	function requireHiddenKeys () {
      		if (hasRequiredHiddenKeys) return hiddenKeys;
      		hasRequiredHiddenKeys = 1;
      		hiddenKeys = {};
      		return hiddenKeys;
      	}

      	var objectKeysInternal;
      	var hasRequiredObjectKeysInternal;

      	function requireObjectKeysInternal () {
      		if (hasRequiredObjectKeysInternal) return objectKeysInternal;
      		hasRequiredObjectKeysInternal = 1;
      		var uncurryThis = requireFunctionUncurryThis();
      		var hasOwn = requireHasOwnProperty();
      		var toIndexedObject = requireToIndexedObject();
      		var indexOf = requireArrayIncludes().indexOf;
      		var hiddenKeys = requireHiddenKeys();

      		var push = uncurryThis([].push);

      		objectKeysInternal = function (object, names) {
      		  var O = toIndexedObject(object);
      		  var i = 0;
      		  var result = [];
      		  var key;
      		  for (key in O) !hasOwn(hiddenKeys, key) && hasOwn(O, key) && push(result, key);
      		  // Don't enum bug & hidden keys
      		  while (names.length > i) if (hasOwn(O, key = names[i++])) {
      		    ~indexOf(result, key) || push(result, key);
      		  }
      		  return result;
      		};
      		return objectKeysInternal;
      	}

      	var enumBugKeys;
      	var hasRequiredEnumBugKeys;

      	function requireEnumBugKeys () {
      		if (hasRequiredEnumBugKeys) return enumBugKeys;
      		hasRequiredEnumBugKeys = 1;
      		// IE8- don't enum bug keys
      		enumBugKeys = [
      		  'constructor',
      		  'hasOwnProperty',
      		  'isPrototypeOf',
      		  'propertyIsEnumerable',
      		  'toLocaleString',
      		  'toString',
      		  'valueOf'
      		];
      		return enumBugKeys;
      	}

      	var objectKeys;
      	var hasRequiredObjectKeys;

      	function requireObjectKeys () {
      		if (hasRequiredObjectKeys) return objectKeys;
      		hasRequiredObjectKeys = 1;
      		var internalObjectKeys = requireObjectKeysInternal();
      		var enumBugKeys = requireEnumBugKeys();

      		// `Object.keys` method
      		// https://tc39.es/ecma262/#sec-object.keys
      		// eslint-disable-next-line es/no-object-keys -- safe
      		objectKeys = Object.keys || function keys(O) {
      		  return internalObjectKeys(O, enumBugKeys);
      		};
      		return objectKeys;
      	}

      	var objectGetOwnPropertySymbols = {};

      	var hasRequiredObjectGetOwnPropertySymbols;

      	function requireObjectGetOwnPropertySymbols () {
      		if (hasRequiredObjectGetOwnPropertySymbols) return objectGetOwnPropertySymbols;
      		hasRequiredObjectGetOwnPropertySymbols = 1;
      		// eslint-disable-next-line es/no-object-getownpropertysymbols -- safe
      		objectGetOwnPropertySymbols.f = Object.getOwnPropertySymbols;
      		return objectGetOwnPropertySymbols;
      	}

      	var objectAssign;
      	var hasRequiredObjectAssign;

      	function requireObjectAssign () {
      		if (hasRequiredObjectAssign) return objectAssign;
      		hasRequiredObjectAssign = 1;
      		var DESCRIPTORS = requireDescriptors();
      		var uncurryThis = requireFunctionUncurryThis();
      		var call = requireFunctionCall();
      		var fails = requireFails();
      		var objectKeys = requireObjectKeys();
      		var getOwnPropertySymbolsModule = requireObjectGetOwnPropertySymbols();
      		var propertyIsEnumerableModule = requireObjectPropertyIsEnumerable();
      		var toObject = requireToObject();
      		var IndexedObject = requireIndexedObject();

      		// eslint-disable-next-line es/no-object-assign -- safe
      		var $assign = Object.assign;
      		// eslint-disable-next-line es/no-object-defineproperty -- required for testing
      		var defineProperty = Object.defineProperty;
      		var concat = uncurryThis([].concat);

      		// `Object.assign` method
      		// https://tc39.es/ecma262/#sec-object.assign
      		objectAssign = !$assign || fails(function () {
      		  // should have correct order of operations (Edge bug)
      		  if (DESCRIPTORS && $assign({ b: 1 }, $assign(defineProperty({}, 'a', {
      		    enumerable: true,
      		    get: function () {
      		      defineProperty(this, 'b', {
      		        value: 3,
      		        enumerable: false
      		      });
      		    }
      		  }), { b: 2 })).b !== 1) return true;
      		  // should work with symbols and should have deterministic property order (V8 bug)
      		  var A = {};
      		  var B = {};
      		  // eslint-disable-next-line es/no-symbol -- safe
      		  var symbol = Symbol('assign detection');
      		  var alphabet = 'abcdefghijklmnopqrst';
      		  A[symbol] = 7;
      		  // eslint-disable-next-line es/no-array-prototype-foreach -- safe
      		  alphabet.split('').forEach(function (chr) { B[chr] = chr; });
      		  return $assign({}, A)[symbol] !== 7 || objectKeys($assign({}, B)).join('') !== alphabet;
      		}) ? function assign(target, source) { // eslint-disable-line no-unused-vars -- required for `.length`
      		  var T = toObject(target);
      		  var argumentsLength = arguments.length;
      		  var index = 1;
      		  var getOwnPropertySymbols = getOwnPropertySymbolsModule.f;
      		  var propertyIsEnumerable = propertyIsEnumerableModule.f;
      		  while (argumentsLength > index) {
      		    var S = IndexedObject(arguments[index++]);
      		    var keys = getOwnPropertySymbols ? concat(objectKeys(S), getOwnPropertySymbols(S)) : objectKeys(S);
      		    var length = keys.length;
      		    var j = 0;
      		    var key;
      		    while (length > j) {
      		      key = keys[j++];
      		      if (!DESCRIPTORS || call(propertyIsEnumerable, S, key)) T[key] = S[key];
      		    }
      		  } return T;
      		} : $assign;
      		return objectAssign;
      	}

      	var hasRequiredEs_object_assign;

      	function requireEs_object_assign () {
      		if (hasRequiredEs_object_assign) return es_object_assign;
      		hasRequiredEs_object_assign = 1;
      		var $ = require_export();
      		var assign = requireObjectAssign();

      		// `Object.assign` method
      		// https://tc39.es/ecma262/#sec-object.assign
      		// eslint-disable-next-line es/no-object-assign -- required for testing
      		$({ target: 'Object', stat: true, arity: 2, forced: Object.assign !== assign }, {
      		  assign: assign
      		});
      		return es_object_assign;
      	}

      	var assign$2;
      	var hasRequiredAssign$2;

      	function requireAssign$2 () {
      		if (hasRequiredAssign$2) return assign$2;
      		hasRequiredAssign$2 = 1;
      		requireEs_object_assign();
      		var path = requirePath();

      		assign$2 = path.Object.assign;
      		return assign$2;
      	}

      	var assign$1;
      	var hasRequiredAssign$1;

      	function requireAssign$1 () {
      		if (hasRequiredAssign$1) return assign$1;
      		hasRequiredAssign$1 = 1;
      		var parent = requireAssign$2();

      		assign$1 = parent;
      		return assign$1;
      	}

      	var assign;
      	var hasRequiredAssign;

      	function requireAssign () {
      		if (hasRequiredAssign) return assign;
      		hasRequiredAssign = 1;
      		assign = requireAssign$1();
      		return assign;
      	}

      	var assignExports = requireAssign();
      	var _Object$assign = /*@__PURE__*/getDefaultExportFromCjs(assignExports);

      	function a () {
      	  console.log(_Object$assign({}, {
      	    a: 1
      	  }));
      	}

      	function b () {
      	  console.log(_Object$assign({}, {
      	    b: 1
      	  }));
      	}

      	a();
      	b();

      })();
    JS
  end
  
  test 'npm modules also get babelized' do
    file "#{@npm_path}/module/name.js", <<~JS
      export default function x(y) { return y?.z; }
    JS
  
    file 'name.js', <<~JS
      import x from 'module/name';
  
      var d = {};
      console.log(x(d?.z));
    JS
  
    assert_exported_file 'name.js', 'application/javascript', <<~JS
      (function () {
        'use strict';
  
        function x(y) {
          return y === null || y === void 0 ? void 0 : y.z;
        }
  
        var d = {};
        console.log(x(d === null || d === void 0 ? void 0 : d.z));
  
      })();
    JS
  
  end
end