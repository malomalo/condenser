require 'test_helper'

class CondenserBabelTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::JSAnalyzer)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(@path,
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

      	var check = function (it) {
      	  return it && it.Math == Math && it;
      	};

      	// https://github.com/zloirock/core-js/issues/86#issuecomment-115759028
      	var global$i =
      	  // eslint-disable-next-line es/no-global-this -- safe
      	  check(typeof globalThis == 'object' && globalThis) ||
      	  check(typeof window == 'object' && window) ||
      	  // eslint-disable-next-line no-restricted-globals -- safe
      	  check(typeof self == 'object' && self) ||
      	  check(typeof commonjsGlobal == 'object' && commonjsGlobal) ||
      	  // eslint-disable-next-line no-new-func -- fallback
      	  (function () { return this; })() || Function('return this')();

      	var FunctionPrototype$1 = Function.prototype;
      	var apply$1 = FunctionPrototype$1.apply;
      	var bind$3 = FunctionPrototype$1.bind;
      	var call$6 = FunctionPrototype$1.call;

      	// eslint-disable-next-line es/no-reflect -- safe
      	var functionApply = typeof Reflect == 'object' && Reflect.apply || (bind$3 ? call$6.bind(apply$1) : function () {
      	  return call$6.apply(apply$1, arguments);
      	});

      	var FunctionPrototype = Function.prototype;
      	var bind$2 = FunctionPrototype.bind;
      	var call$5 = FunctionPrototype.call;
      	var uncurryThis$9 = bind$2 && bind$2.bind(call$5, call$5);

      	var functionUncurryThis = bind$2 ? function (fn) {
      	  return fn && uncurryThis$9(fn);
      	} : function (fn) {
      	  return fn && function () {
      	    return call$5.apply(fn, arguments);
      	  };
      	};

      	// `IsCallable` abstract operation
      	// https://tc39.es/ecma262/#sec-iscallable
      	var isCallable$7 = function (argument) {
      	  return typeof argument == 'function';
      	};

      	var objectGetOwnPropertyDescriptor = {};

      	var fails$7 = function (exec) {
      	  try {
      	    return !!exec();
      	  } catch (error) {
      	    return true;
      	  }
      	};

      	var fails$6 = fails$7;

      	// Detect IE8's incomplete defineProperty implementation
      	var descriptors = !fails$6(function () {
      	  // eslint-disable-next-line es/no-object-defineproperty -- required for testing
      	  return Object.defineProperty({}, 1, { get: function () { return 7; } })[1] != 7;
      	});

      	var call$4 = Function.prototype.call;

      	var functionCall = call$4.bind ? call$4.bind(call$4) : function () {
      	  return call$4.apply(call$4, arguments);
      	};

      	var objectPropertyIsEnumerable = {};

      	var $propertyIsEnumerable = {}.propertyIsEnumerable;
      	// eslint-disable-next-line es/no-object-getownpropertydescriptor -- safe
      	var getOwnPropertyDescriptor$1 = Object.getOwnPropertyDescriptor;

      	// Nashorn ~ JDK8 bug
      	var NASHORN_BUG = getOwnPropertyDescriptor$1 && !$propertyIsEnumerable.call({ 1: 2 }, 1);

      	// `Object.prototype.propertyIsEnumerable` method implementation
      	// https://tc39.es/ecma262/#sec-object.prototype.propertyisenumerable
      	objectPropertyIsEnumerable.f = NASHORN_BUG ? function propertyIsEnumerable(V) {
      	  var descriptor = getOwnPropertyDescriptor$1(this, V);
      	  return !!descriptor && descriptor.enumerable;
      	} : $propertyIsEnumerable;

      	var createPropertyDescriptor$2 = function (bitmap, value) {
      	  return {
      	    enumerable: !(bitmap & 1),
      	    configurable: !(bitmap & 2),
      	    writable: !(bitmap & 4),
      	    value: value
      	  };
      	};

      	var uncurryThis$8 = functionUncurryThis;

      	var toString$1 = uncurryThis$8({}.toString);
      	var stringSlice = uncurryThis$8(''.slice);

      	var classofRaw = function (it) {
      	  return stringSlice(toString$1(it), 8, -1);
      	};

      	var global$h = global$i;
      	var uncurryThis$7 = functionUncurryThis;
      	var fails$5 = fails$7;
      	var classof = classofRaw;

      	var Object$3 = global$h.Object;
      	var split = uncurryThis$7(''.split);

      	// fallback for non-array-like ES3 and non-enumerable old V8 strings
      	var indexedObject = fails$5(function () {
      	  // throws an error in rhino, see https://github.com/mozilla/rhino/issues/346
      	  // eslint-disable-next-line no-prototype-builtins -- safe
      	  return !Object$3('z').propertyIsEnumerable(0);
      	}) ? function (it) {
      	  return classof(it) == 'String' ? split(it, '') : Object$3(it);
      	} : Object$3;

      	var global$g = global$i;

      	var TypeError$5 = global$g.TypeError;

      	// `RequireObjectCoercible` abstract operation
      	// https://tc39.es/ecma262/#sec-requireobjectcoercible
      	var requireObjectCoercible$2 = function (it) {
      	  if (it == undefined) throw TypeError$5("Can't call method on " + it);
      	  return it;
      	};

      	// toObject with fallback for non-array-like ES3 strings
      	var IndexedObject$1 = indexedObject;
      	var requireObjectCoercible$1 = requireObjectCoercible$2;

      	var toIndexedObject$3 = function (it) {
      	  return IndexedObject$1(requireObjectCoercible$1(it));
      	};

      	var isCallable$6 = isCallable$7;

      	var isObject$4 = function (it) {
      	  return typeof it == 'object' ? it !== null : isCallable$6(it);
      	};

      	var path$3 = {};

      	var path$2 = path$3;
      	var global$f = global$i;
      	var isCallable$5 = isCallable$7;

      	var aFunction = function (variable) {
      	  return isCallable$5(variable) ? variable : undefined;
      	};

      	var getBuiltIn$2 = function (namespace, method) {
      	  return arguments.length < 2 ? aFunction(path$2[namespace]) || aFunction(global$f[namespace])
      	    : path$2[namespace] && path$2[namespace][method] || global$f[namespace] && global$f[namespace][method];
      	};

      	var uncurryThis$6 = functionUncurryThis;

      	var objectIsPrototypeOf = uncurryThis$6({}.isPrototypeOf);

      	var getBuiltIn$1 = getBuiltIn$2;

      	var engineUserAgent = getBuiltIn$1('navigator', 'userAgent') || '';

      	var global$e = global$i;
      	var userAgent = engineUserAgent;

      	var process = global$e.process;
      	var Deno = global$e.Deno;
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

      	var engineV8Version = version;

      	/* eslint-disable es/no-symbol -- required for testing */

      	var V8_VERSION = engineV8Version;
      	var fails$4 = fails$7;

      	// eslint-disable-next-line es/no-object-getownpropertysymbols -- required for testing
      	var nativeSymbol = !!Object.getOwnPropertySymbols && !fails$4(function () {
      	  var symbol = Symbol();
      	  // Chrome 38 Symbol has incorrect toString conversion
      	  // `get-own-property-symbols` polyfill symbols converted to object are not Symbol instances
      	  return !String(symbol) || !(Object(symbol) instanceof Symbol) ||
      	    // Chrome 38-40 symbols are not inherited from DOM collections prototypes to instances
      	    !Symbol.sham && V8_VERSION && V8_VERSION < 41;
      	});

      	/* eslint-disable es/no-symbol -- required for testing */

      	var NATIVE_SYMBOL$1 = nativeSymbol;

      	var useSymbolAsUid = NATIVE_SYMBOL$1
      	  && !Symbol.sham
      	  && typeof Symbol.iterator == 'symbol';

      	var global$d = global$i;
      	var getBuiltIn = getBuiltIn$2;
      	var isCallable$4 = isCallable$7;
      	var isPrototypeOf = objectIsPrototypeOf;
      	var USE_SYMBOL_AS_UID$1 = useSymbolAsUid;

      	var Object$2 = global$d.Object;

      	var isSymbol$2 = USE_SYMBOL_AS_UID$1 ? function (it) {
      	  return typeof it == 'symbol';
      	} : function (it) {
      	  var $Symbol = getBuiltIn('Symbol');
      	  return isCallable$4($Symbol) && isPrototypeOf($Symbol.prototype, Object$2(it));
      	};

      	var global$c = global$i;

      	var String$2 = global$c.String;

      	var tryToString$1 = function (argument) {
      	  try {
      	    return String$2(argument);
      	  } catch (error) {
      	    return 'Object';
      	  }
      	};

      	var global$b = global$i;
      	var isCallable$3 = isCallable$7;
      	var tryToString = tryToString$1;

      	var TypeError$4 = global$b.TypeError;

      	// `Assert: IsCallable(argument) is true`
      	var aCallable$2 = function (argument) {
      	  if (isCallable$3(argument)) return argument;
      	  throw TypeError$4(tryToString(argument) + ' is not a function');
      	};

      	var aCallable$1 = aCallable$2;

      	// `GetMethod` abstract operation
      	// https://tc39.es/ecma262/#sec-getmethod
      	var getMethod$1 = function (V, P) {
      	  var func = V[P];
      	  return func == null ? undefined : aCallable$1(func);
      	};

      	var global$a = global$i;
      	var call$3 = functionCall;
      	var isCallable$2 = isCallable$7;
      	var isObject$3 = isObject$4;

      	var TypeError$3 = global$a.TypeError;

      	// `OrdinaryToPrimitive` abstract operation
      	// https://tc39.es/ecma262/#sec-ordinarytoprimitive
      	var ordinaryToPrimitive$1 = function (input, pref) {
      	  var fn, val;
      	  if (pref === 'string' && isCallable$2(fn = input.toString) && !isObject$3(val = call$3(fn, input))) return val;
      	  if (isCallable$2(fn = input.valueOf) && !isObject$3(val = call$3(fn, input))) return val;
      	  if (pref !== 'string' && isCallable$2(fn = input.toString) && !isObject$3(val = call$3(fn, input))) return val;
      	  throw TypeError$3("Can't convert object to primitive value");
      	};

      	var shared$1 = {exports: {}};

      	var global$9 = global$i;

      	// eslint-disable-next-line es/no-object-defineproperty -- safe
      	var defineProperty$1 = Object.defineProperty;

      	var setGlobal$1 = function (key, value) {
      	  try {
      	    defineProperty$1(global$9, key, { value: value, configurable: true, writable: true });
      	  } catch (error) {
      	    global$9[key] = value;
      	  } return value;
      	};

      	var global$8 = global$i;
      	var setGlobal = setGlobal$1;

      	var SHARED = '__core-js_shared__';
      	var store$1 = global$8[SHARED] || setGlobal(SHARED, {});

      	var sharedStore = store$1;

      	var store = sharedStore;

      	(shared$1.exports = function (key, value) {
      	  return store[key] || (store[key] = value !== undefined ? value : {});
      	})('versions', []).push({
      	  version: '3.20.2',
      	  mode: 'pure' ,
      	  copyright: '© 2022 Denis Pushkarev (zloirock.ru)'
      	});

      	var global$7 = global$i;
      	var requireObjectCoercible = requireObjectCoercible$2;

      	var Object$1 = global$7.Object;

      	// `ToObject` abstract operation
      	// https://tc39.es/ecma262/#sec-toobject
      	var toObject$2 = function (argument) {
      	  return Object$1(requireObjectCoercible(argument));
      	};

      	var uncurryThis$5 = functionUncurryThis;
      	var toObject$1 = toObject$2;

      	var hasOwnProperty = uncurryThis$5({}.hasOwnProperty);

      	// `HasOwnProperty` abstract operation
      	// https://tc39.es/ecma262/#sec-hasownproperty
      	var hasOwnProperty_1 = Object.hasOwn || function hasOwn(it, key) {
      	  return hasOwnProperty(toObject$1(it), key);
      	};

      	var uncurryThis$4 = functionUncurryThis;

      	var id = 0;
      	var postfix = Math.random();
      	var toString = uncurryThis$4(1.0.toString);

      	var uid$1 = function (key) {
      	  return 'Symbol(' + (key === undefined ? '' : key) + ')_' + toString(++id + postfix, 36);
      	};

      	var global$6 = global$i;
      	var shared = shared$1.exports;
      	var hasOwn$3 = hasOwnProperty_1;
      	var uid = uid$1;
      	var NATIVE_SYMBOL = nativeSymbol;
      	var USE_SYMBOL_AS_UID = useSymbolAsUid;

      	var WellKnownSymbolsStore = shared('wks');
      	var Symbol$1 = global$6.Symbol;
      	var symbolFor = Symbol$1 && Symbol$1['for'];
      	var createWellKnownSymbol = USE_SYMBOL_AS_UID ? Symbol$1 : Symbol$1 && Symbol$1.withoutSetter || uid;

      	var wellKnownSymbol$1 = function (name) {
      	  if (!hasOwn$3(WellKnownSymbolsStore, name) || !(NATIVE_SYMBOL || typeof WellKnownSymbolsStore[name] == 'string')) {
      	    var description = 'Symbol.' + name;
      	    if (NATIVE_SYMBOL && hasOwn$3(Symbol$1, name)) {
      	      WellKnownSymbolsStore[name] = Symbol$1[name];
      	    } else if (USE_SYMBOL_AS_UID && symbolFor) {
      	      WellKnownSymbolsStore[name] = symbolFor(description);
      	    } else {
      	      WellKnownSymbolsStore[name] = createWellKnownSymbol(description);
      	    }
      	  } return WellKnownSymbolsStore[name];
      	};

      	var global$5 = global$i;
      	var call$2 = functionCall;
      	var isObject$2 = isObject$4;
      	var isSymbol$1 = isSymbol$2;
      	var getMethod = getMethod$1;
      	var ordinaryToPrimitive = ordinaryToPrimitive$1;
      	var wellKnownSymbol = wellKnownSymbol$1;

      	var TypeError$2 = global$5.TypeError;
      	var TO_PRIMITIVE = wellKnownSymbol('toPrimitive');

      	// `ToPrimitive` abstract operation
      	// https://tc39.es/ecma262/#sec-toprimitive
      	var toPrimitive$1 = function (input, pref) {
      	  if (!isObject$2(input) || isSymbol$1(input)) return input;
      	  var exoticToPrim = getMethod(input, TO_PRIMITIVE);
      	  var result;
      	  if (exoticToPrim) {
      	    if (pref === undefined) pref = 'default';
      	    result = call$2(exoticToPrim, input, pref);
      	    if (!isObject$2(result) || isSymbol$1(result)) return result;
      	    throw TypeError$2("Can't convert object to primitive value");
      	  }
      	  if (pref === undefined) pref = 'number';
      	  return ordinaryToPrimitive(input, pref);
      	};

      	var toPrimitive = toPrimitive$1;
      	var isSymbol = isSymbol$2;

      	// `ToPropertyKey` abstract operation
      	// https://tc39.es/ecma262/#sec-topropertykey
      	var toPropertyKey$2 = function (argument) {
      	  var key = toPrimitive(argument, 'string');
      	  return isSymbol(key) ? key : key + '';
      	};

      	var global$4 = global$i;
      	var isObject$1 = isObject$4;

      	var document = global$4.document;
      	// typeof document.createElement is 'object' in old IE
      	var EXISTS = isObject$1(document) && isObject$1(document.createElement);

      	var documentCreateElement = function (it) {
      	  return EXISTS ? document.createElement(it) : {};
      	};

      	var DESCRIPTORS$5 = descriptors;
      	var fails$3 = fails$7;
      	var createElement = documentCreateElement;

      	// Thank's IE8 for his funny defineProperty
      	var ie8DomDefine = !DESCRIPTORS$5 && !fails$3(function () {
      	  // eslint-disable-next-line es/no-object-defineproperty -- required for testing
      	  return Object.defineProperty(createElement('div'), 'a', {
      	    get: function () { return 7; }
      	  }).a != 7;
      	});

      	var DESCRIPTORS$4 = descriptors;
      	var call$1 = functionCall;
      	var propertyIsEnumerableModule$1 = objectPropertyIsEnumerable;
      	var createPropertyDescriptor$1 = createPropertyDescriptor$2;
      	var toIndexedObject$2 = toIndexedObject$3;
      	var toPropertyKey$1 = toPropertyKey$2;
      	var hasOwn$2 = hasOwnProperty_1;
      	var IE8_DOM_DEFINE$1 = ie8DomDefine;

      	// eslint-disable-next-line es/no-object-getownpropertydescriptor -- safe
      	var $getOwnPropertyDescriptor$1 = Object.getOwnPropertyDescriptor;

      	// `Object.getOwnPropertyDescriptor` method
      	// https://tc39.es/ecma262/#sec-object.getownpropertydescriptor
      	objectGetOwnPropertyDescriptor.f = DESCRIPTORS$4 ? $getOwnPropertyDescriptor$1 : function getOwnPropertyDescriptor(O, P) {
      	  O = toIndexedObject$2(O);
      	  P = toPropertyKey$1(P);
      	  if (IE8_DOM_DEFINE$1) try {
      	    return $getOwnPropertyDescriptor$1(O, P);
      	  } catch (error) { /* empty */ }
      	  if (hasOwn$2(O, P)) return createPropertyDescriptor$1(!call$1(propertyIsEnumerableModule$1.f, O, P), O[P]);
      	};

      	var fails$2 = fails$7;
      	var isCallable$1 = isCallable$7;

      	var replacement = /#|\\.prototype\\./;

      	var isForced$1 = function (feature, detection) {
      	  var value = data[normalize(feature)];
      	  return value == POLYFILL ? true
      	    : value == NATIVE ? false
      	    : isCallable$1(detection) ? fails$2(detection)
      	    : !!detection;
      	};

      	var normalize = isForced$1.normalize = function (string) {
      	  return String(string).replace(replacement, '.').toLowerCase();
      	};

      	var data = isForced$1.data = {};
      	var NATIVE = isForced$1.NATIVE = 'N';
      	var POLYFILL = isForced$1.POLYFILL = 'P';

      	var isForced_1 = isForced$1;

      	var uncurryThis$3 = functionUncurryThis;
      	var aCallable = aCallable$2;

      	var bind$1 = uncurryThis$3(uncurryThis$3.bind);

      	// optional / simple context binding
      	var functionBindContext = function (fn, that) {
      	  aCallable(fn);
      	  return that === undefined ? fn : bind$1 ? bind$1(fn, that) : function (/* ...args */) {
      	    return fn.apply(that, arguments);
      	  };
      	};

      	var objectDefineProperty = {};

      	var DESCRIPTORS$3 = descriptors;
      	var fails$1 = fails$7;

      	// V8 ~ Chrome 36-
      	// https://bugs.chromium.org/p/v8/issues/detail?id=3334
      	var v8PrototypeDefineBug = DESCRIPTORS$3 && fails$1(function () {
      	  // eslint-disable-next-line es/no-object-defineproperty -- required for testing
      	  return Object.defineProperty(function () { /* empty */ }, 'prototype', {
      	    value: 42,
      	    writable: false
      	  }).prototype != 42;
      	});

      	var global$3 = global$i;
      	var isObject = isObject$4;

      	var String$1 = global$3.String;
      	var TypeError$1 = global$3.TypeError;

      	// `Assert: Type(argument) is Object`
      	var anObject$1 = function (argument) {
      	  if (isObject(argument)) return argument;
      	  throw TypeError$1(String$1(argument) + ' is not an object');
      	};

      	var global$2 = global$i;
      	var DESCRIPTORS$2 = descriptors;
      	var IE8_DOM_DEFINE = ie8DomDefine;
      	var V8_PROTOTYPE_DEFINE_BUG = v8PrototypeDefineBug;
      	var anObject = anObject$1;
      	var toPropertyKey = toPropertyKey$2;

      	var TypeError = global$2.TypeError;
      	// eslint-disable-next-line es/no-object-defineproperty -- safe
      	var $defineProperty = Object.defineProperty;
      	// eslint-disable-next-line es/no-object-getownpropertydescriptor -- safe
      	var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
      	var ENUMERABLE = 'enumerable';
      	var CONFIGURABLE = 'configurable';
      	var WRITABLE = 'writable';

      	// `Object.defineProperty` method
      	// https://tc39.es/ecma262/#sec-object.defineproperty
      	objectDefineProperty.f = DESCRIPTORS$2 ? V8_PROTOTYPE_DEFINE_BUG ? function defineProperty(O, P, Attributes) {
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
      	  if ('get' in Attributes || 'set' in Attributes) throw TypeError('Accessors not supported');
      	  if ('value' in Attributes) O[P] = Attributes.value;
      	  return O;
      	};

      	var DESCRIPTORS$1 = descriptors;
      	var definePropertyModule = objectDefineProperty;
      	var createPropertyDescriptor = createPropertyDescriptor$2;

      	var createNonEnumerableProperty$1 = DESCRIPTORS$1 ? function (object, key, value) {
      	  return definePropertyModule.f(object, key, createPropertyDescriptor(1, value));
      	} : function (object, key, value) {
      	  object[key] = value;
      	  return object;
      	};

      	var global$1 = global$i;
      	var apply = functionApply;
      	var uncurryThis$2 = functionUncurryThis;
      	var isCallable = isCallable$7;
      	var getOwnPropertyDescriptor = objectGetOwnPropertyDescriptor.f;
      	var isForced = isForced_1;
      	var path$1 = path$3;
      	var bind = functionBindContext;
      	var createNonEnumerableProperty = createNonEnumerableProperty$1;
      	var hasOwn$1 = hasOwnProperty_1;

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
      	  options.target      - name of the target object
      	  options.global      - target is the global object
      	  options.stat        - export as static methods of target
      	  options.proto       - export as prototype methods of target
      	  options.real        - real prototype method for the `pure` version
      	  options.forced      - export even if the native feature is available
      	  options.bind        - bind methods to the target, required for the `pure` version
      	  options.wrap        - wrap constructors to preventing global pollution, required for the `pure` version
      	  options.unsafe      - use the simple assignment of property instead of delete + defineProperty
      	  options.sham        - add a flag to not completely full polyfills
      	  options.enumerable  - export as enumerable property
      	  options.noTargetGet - prevent calling a getter on target
      	  options.name        - the .name of the function if it does not match the key
      	*/
      	var _export = function (options, source) {
      	  var TARGET = options.target;
      	  var GLOBAL = options.global;
      	  var STATIC = options.stat;
      	  var PROTO = options.proto;

      	  var nativeSource = GLOBAL ? global$1 : STATIC ? global$1[TARGET] : (global$1[TARGET] || {}).prototype;

      	  var target = GLOBAL ? path$1 : path$1[TARGET] || createNonEnumerableProperty(path$1, TARGET, {})[TARGET];
      	  var targetPrototype = target.prototype;

      	  var FORCED, USE_NATIVE, VIRTUAL_PROTOTYPE;
      	  var key, sourceProperty, targetProperty, nativeProperty, resultProperty, descriptor;

      	  for (key in source) {
      	    FORCED = isForced(GLOBAL ? key : TARGET + (STATIC ? '.' : '#') + key, options.forced);
      	    // contains in native
      	    USE_NATIVE = !FORCED && nativeSource && hasOwn$1(nativeSource, key);

      	    targetProperty = target[key];

      	    if (USE_NATIVE) if (options.noTargetGet) {
      	      descriptor = getOwnPropertyDescriptor(nativeSource, key);
      	      nativeProperty = descriptor && descriptor.value;
      	    } else nativeProperty = nativeSource[key];

      	    // export native or implementation
      	    sourceProperty = (USE_NATIVE && nativeProperty) ? nativeProperty : source[key];

      	    if (USE_NATIVE && typeof targetProperty == typeof sourceProperty) continue;

      	    // bind timers to global for call from export context
      	    if (options.bind && USE_NATIVE) resultProperty = bind(sourceProperty, global$1);
      	    // wrap global constructors for prevent changs in this version
      	    else if (options.wrap && USE_NATIVE) resultProperty = wrapConstructor(sourceProperty);
      	    // make static versions for prototype methods
      	    else if (PROTO && isCallable(sourceProperty)) resultProperty = uncurryThis$2(sourceProperty);
      	    // default case
      	    else resultProperty = sourceProperty;

      	    // add a flag to not completely full polyfills
      	    if (options.sham || (sourceProperty && sourceProperty.sham) || (targetProperty && targetProperty.sham)) {
      	      createNonEnumerableProperty(resultProperty, 'sham', true);
      	    }

      	    createNonEnumerableProperty(target, key, resultProperty);

      	    if (PROTO) {
      	      VIRTUAL_PROTOTYPE = TARGET + 'Prototype';
      	      if (!hasOwn$1(path$1, VIRTUAL_PROTOTYPE)) {
      	        createNonEnumerableProperty(path$1, VIRTUAL_PROTOTYPE, {});
      	      }
      	      // export virtual prototype methods
      	      createNonEnumerableProperty(path$1[VIRTUAL_PROTOTYPE], key, sourceProperty);
      	      // export real prototype methods
      	      if (options.real && targetPrototype && !targetPrototype[key]) {
      	        createNonEnumerableProperty(targetPrototype, key, sourceProperty);
      	      }
      	    }
      	  }
      	};

      	var ceil = Math.ceil;
      	var floor = Math.floor;

      	// `ToIntegerOrInfinity` abstract operation
      	// https://tc39.es/ecma262/#sec-tointegerorinfinity
      	var toIntegerOrInfinity$2 = function (argument) {
      	  var number = +argument;
      	  // eslint-disable-next-line no-self-compare -- safe
      	  return number !== number || number === 0 ? 0 : (number > 0 ? floor : ceil)(number);
      	};

      	var toIntegerOrInfinity$1 = toIntegerOrInfinity$2;

      	var max = Math.max;
      	var min$1 = Math.min;

      	// Helper for a popular repeating case of the spec:
      	// Let integer be ? ToInteger(index).
      	// If integer < 0, let result be max((length + integer), 0); else let result be min(integer, length).
      	var toAbsoluteIndex$1 = function (index, length) {
      	  var integer = toIntegerOrInfinity$1(index);
      	  return integer < 0 ? max(integer + length, 0) : min$1(integer, length);
      	};

      	var toIntegerOrInfinity = toIntegerOrInfinity$2;

      	var min = Math.min;

      	// `ToLength` abstract operation
      	// https://tc39.es/ecma262/#sec-tolength
      	var toLength$1 = function (argument) {
      	  return argument > 0 ? min(toIntegerOrInfinity(argument), 0x1FFFFFFFFFFFFF) : 0; // 2 ** 53 - 1 == 9007199254740991
      	};

      	var toLength = toLength$1;

      	// `LengthOfArrayLike` abstract operation
      	// https://tc39.es/ecma262/#sec-lengthofarraylike
      	var lengthOfArrayLike$1 = function (obj) {
      	  return toLength(obj.length);
      	};

      	var toIndexedObject$1 = toIndexedObject$3;
      	var toAbsoluteIndex = toAbsoluteIndex$1;
      	var lengthOfArrayLike = lengthOfArrayLike$1;

      	// `Array.prototype.{ indexOf, includes }` methods implementation
      	var createMethod = function (IS_INCLUDES) {
      	  return function ($this, el, fromIndex) {
      	    var O = toIndexedObject$1($this);
      	    var length = lengthOfArrayLike(O);
      	    var index = toAbsoluteIndex(fromIndex, length);
      	    var value;
      	    // Array#includes uses SameValueZero equality algorithm
      	    // eslint-disable-next-line no-self-compare -- NaN check
      	    if (IS_INCLUDES && el != el) while (length > index) {
      	      value = O[index++];
      	      // eslint-disable-next-line no-self-compare -- NaN check
      	      if (value != value) return true;
      	    // Array#indexOf ignores holes, Array#includes - not
      	    } else for (;length > index; index++) {
      	      if ((IS_INCLUDES || index in O) && O[index] === el) return IS_INCLUDES || index || 0;
      	    } return !IS_INCLUDES && -1;
      	  };
      	};

      	var arrayIncludes = {
      	  // `Array.prototype.includes` method
      	  // https://tc39.es/ecma262/#sec-array.prototype.includes
      	  includes: createMethod(true),
      	  // `Array.prototype.indexOf` method
      	  // https://tc39.es/ecma262/#sec-array.prototype.indexof
      	  indexOf: createMethod(false)
      	};

      	var hiddenKeys$1 = {};

      	var uncurryThis$1 = functionUncurryThis;
      	var hasOwn = hasOwnProperty_1;
      	var toIndexedObject = toIndexedObject$3;
      	var indexOf = arrayIncludes.indexOf;
      	var hiddenKeys = hiddenKeys$1;

      	var push = uncurryThis$1([].push);

      	var objectKeysInternal = function (object, names) {
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

      	// IE8- don't enum bug keys
      	var enumBugKeys$1 = [
      	  'constructor',
      	  'hasOwnProperty',
      	  'isPrototypeOf',
      	  'propertyIsEnumerable',
      	  'toLocaleString',
      	  'toString',
      	  'valueOf'
      	];

      	var internalObjectKeys = objectKeysInternal;
      	var enumBugKeys = enumBugKeys$1;

      	// `Object.keys` method
      	// https://tc39.es/ecma262/#sec-object.keys
      	// eslint-disable-next-line es/no-object-keys -- safe
      	var objectKeys$1 = Object.keys || function keys(O) {
      	  return internalObjectKeys(O, enumBugKeys);
      	};

      	var objectGetOwnPropertySymbols = {};

      	// eslint-disable-next-line es/no-object-getownpropertysymbols -- safe
      	objectGetOwnPropertySymbols.f = Object.getOwnPropertySymbols;

      	var DESCRIPTORS = descriptors;
      	var uncurryThis = functionUncurryThis;
      	var call = functionCall;
      	var fails = fails$7;
      	var objectKeys = objectKeys$1;
      	var getOwnPropertySymbolsModule = objectGetOwnPropertySymbols;
      	var propertyIsEnumerableModule = objectPropertyIsEnumerable;
      	var toObject = toObject$2;
      	var IndexedObject = indexedObject;

      	// eslint-disable-next-line es/no-object-assign -- safe
      	var $assign = Object.assign;
      	// eslint-disable-next-line es/no-object-defineproperty -- required for testing
      	var defineProperty = Object.defineProperty;
      	var concat = uncurryThis([].concat);

      	// `Object.assign` method
      	// https://tc39.es/ecma262/#sec-object.assign
      	var objectAssign = !$assign || fails(function () {
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
      	  var symbol = Symbol();
      	  var alphabet = 'abcdefghijklmnopqrst';
      	  A[symbol] = 7;
      	  alphabet.split('').forEach(function (chr) { B[chr] = chr; });
      	  return $assign({}, A)[symbol] != 7 || objectKeys($assign({}, B)).join('') != alphabet;
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

      	var $ = _export;
      	var assign$3 = objectAssign;

      	// `Object.assign` method
      	// https://tc39.es/ecma262/#sec-object.assign
      	// eslint-disable-next-line es/no-object-assign -- required for testing
      	$({ target: 'Object', stat: true, forced: Object.assign !== assign$3 }, {
      	  assign: assign$3
      	});

      	var path = path$3;

      	var assign$2 = path.Object.assign;

      	var parent = assign$2;

      	var assign$1 = parent;

      	var assign = assign$1;

      	function a () {
      	  console.log(assign({}, {
      	    a: 1
      	  }));
      	}

      	function b () {
      	  console.log(assign({}, {
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