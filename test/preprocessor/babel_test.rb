require 'test_helper'

class CondenserBabelTest < ActiveSupport::TestCase
  
  def setup
    super
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
  
  test 'not duplicating babel-helpers' do
    file 'a.js', <<-JS
      export default class {
        constructor(height, width) {
          console.log('A');
        }
      };
    JS
    file 'b.js', <<-JS
    export default class {
      constructor(height, width) {
        console.log('B');
      }
    };
    JS
    file 'c.js', <<~JS
      import a from 'a';
      import b from 'b';

      new a();
      new b();
    JS

    assert_exported_file 'c.js', 'application/javascript', <<~JS
      (function () {
        'use strict';

        function _classCallCheck(instance, Constructor) {
          if (!(instance instanceof Constructor)) {
            throw new TypeError("Cannot call a class as a function");
          }
        }

        var _default$1 = function _default(height, width) {
          _classCallCheck(this, _default);

          console.log('A');
        };

        var _default = function _default(height, width) {
          _classCallCheck(this, _default);

          console.log('B');
        };

        new _default$1();
        new _default();

      })();
    JS
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
      	var global_1 =
      	  // eslint-disable-next-line no-undef
      	  check(typeof globalThis == 'object' && globalThis) ||
      	  check(typeof window == 'object' && window) ||
      	  check(typeof self == 'object' && self) ||
      	  check(typeof commonjsGlobal == 'object' && commonjsGlobal) ||
      	  // eslint-disable-next-line no-new-func
      	  (function () { return this; })() || Function('return this')();

      	var fails = function (exec) {
      	  try {
      	    return !!exec();
      	  } catch (error) {
      	    return true;
      	  }
      	};

      	// Thank's IE8 for his funny defineProperty
      	var descriptors = !fails(function () {
      	  return Object.defineProperty({}, 1, { get: function () { return 7; } })[1] != 7;
      	});

      	var nativePropertyIsEnumerable = {}.propertyIsEnumerable;
      	var getOwnPropertyDescriptor$1 = Object.getOwnPropertyDescriptor;

      	// Nashorn ~ JDK8 bug
      	var NASHORN_BUG = getOwnPropertyDescriptor$1 && !nativePropertyIsEnumerable.call({ 1: 2 }, 1);

      	// `Object.prototype.propertyIsEnumerable` method implementation
      	// https://tc39.github.io/ecma262/#sec-object.prototype.propertyisenumerable
      	var f$3 = NASHORN_BUG ? function propertyIsEnumerable(V) {
      	  var descriptor = getOwnPropertyDescriptor$1(this, V);
      	  return !!descriptor && descriptor.enumerable;
      	} : nativePropertyIsEnumerable;

      	var objectPropertyIsEnumerable = {
      		f: f$3
      	};

      	var createPropertyDescriptor = function (bitmap, value) {
      	  return {
      	    enumerable: !(bitmap & 1),
      	    configurable: !(bitmap & 2),
      	    writable: !(bitmap & 4),
      	    value: value
      	  };
      	};

      	var toString = {}.toString;

      	var classofRaw = function (it) {
      	  return toString.call(it).slice(8, -1);
      	};

      	var split = ''.split;

      	// fallback for non-array-like ES3 and non-enumerable old V8 strings
      	var indexedObject = fails(function () {
      	  // throws an error in rhino, see https://github.com/mozilla/rhino/issues/346
      	  // eslint-disable-next-line no-prototype-builtins
      	  return !Object('z').propertyIsEnumerable(0);
      	}) ? function (it) {
      	  return classofRaw(it) == 'String' ? split.call(it, '') : Object(it);
      	} : Object;

      	// `RequireObjectCoercible` abstract operation
      	// https://tc39.github.io/ecma262/#sec-requireobjectcoercible
      	var requireObjectCoercible = function (it) {
      	  if (it == undefined) throw TypeError("Can't call method on " + it);
      	  return it;
      	};

      	// toObject with fallback for non-array-like ES3 strings



      	var toIndexedObject = function (it) {
      	  return indexedObject(requireObjectCoercible(it));
      	};

      	var isObject = function (it) {
      	  return typeof it === 'object' ? it !== null : typeof it === 'function';
      	};

      	// `ToPrimitive` abstract operation
      	// https://tc39.github.io/ecma262/#sec-toprimitive
      	// instead of the ES6 spec version, we didn't implement @@toPrimitive case
      	// and the second argument - flag - preferred type is a string
      	var toPrimitive = function (input, PREFERRED_STRING) {
      	  if (!isObject(input)) return input;
      	  var fn, val;
      	  if (PREFERRED_STRING && typeof (fn = input.toString) == 'function' && !isObject(val = fn.call(input))) return val;
      	  if (typeof (fn = input.valueOf) == 'function' && !isObject(val = fn.call(input))) return val;
      	  if (!PREFERRED_STRING && typeof (fn = input.toString) == 'function' && !isObject(val = fn.call(input))) return val;
      	  throw TypeError("Can't convert object to primitive value");
      	};

      	var hasOwnProperty = {}.hasOwnProperty;

      	var has = function (it, key) {
      	  return hasOwnProperty.call(it, key);
      	};

      	var document = global_1.document;
      	// typeof document.createElement is 'object' in old IE
      	var EXISTS = isObject(document) && isObject(document.createElement);

      	var documentCreateElement = function (it) {
      	  return EXISTS ? document.createElement(it) : {};
      	};

      	// Thank's IE8 for his funny defineProperty
      	var ie8DomDefine = !descriptors && !fails(function () {
      	  return Object.defineProperty(documentCreateElement('div'), 'a', {
      	    get: function () { return 7; }
      	  }).a != 7;
      	});

      	var nativeGetOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;

      	// `Object.getOwnPropertyDescriptor` method
      	// https://tc39.github.io/ecma262/#sec-object.getownpropertydescriptor
      	var f$2 = descriptors ? nativeGetOwnPropertyDescriptor : function getOwnPropertyDescriptor(O, P) {
      	  O = toIndexedObject(O);
      	  P = toPrimitive(P, true);
      	  if (ie8DomDefine) try {
      	    return nativeGetOwnPropertyDescriptor(O, P);
      	  } catch (error) { /* empty */ }
      	  if (has(O, P)) return createPropertyDescriptor(!objectPropertyIsEnumerable.f.call(O, P), O[P]);
      	};

      	var objectGetOwnPropertyDescriptor = {
      		f: f$2
      	};

      	var replacement = /#|\\.prototype\\./;

      	var isForced = function (feature, detection) {
      	  var value = data[normalize(feature)];
      	  return value == POLYFILL ? true
      	    : value == NATIVE ? false
      	    : typeof detection == 'function' ? fails(detection)
      	    : !!detection;
      	};

      	var normalize = isForced.normalize = function (string) {
      	  return String(string).replace(replacement, '.').toLowerCase();
      	};

      	var data = isForced.data = {};
      	var NATIVE = isForced.NATIVE = 'N';
      	var POLYFILL = isForced.POLYFILL = 'P';

      	var isForced_1 = isForced;

      	var path = {};

      	var aFunction = function (it) {
      	  if (typeof it != 'function') {
      	    throw TypeError(String(it) + ' is not a function');
      	  } return it;
      	};

      	// optional / simple context binding
      	var functionBindContext = function (fn, that, length) {
      	  aFunction(fn);
      	  if (that === undefined) return fn;
      	  switch (length) {
      	    case 0: return function () {
      	      return fn.call(that);
      	    };
      	    case 1: return function (a) {
      	      return fn.call(that, a);
      	    };
      	    case 2: return function (a, b) {
      	      return fn.call(that, a, b);
      	    };
      	    case 3: return function (a, b, c) {
      	      return fn.call(that, a, b, c);
      	    };
      	  }
      	  return function (/* ...args */) {
      	    return fn.apply(that, arguments);
      	  };
      	};

      	var anObject = function (it) {
      	  if (!isObject(it)) {
      	    throw TypeError(String(it) + ' is not an object');
      	  } return it;
      	};

      	var nativeDefineProperty = Object.defineProperty;

      	// `Object.defineProperty` method
      	// https://tc39.github.io/ecma262/#sec-object.defineproperty
      	var f$1 = descriptors ? nativeDefineProperty : function defineProperty(O, P, Attributes) {
      	  anObject(O);
      	  P = toPrimitive(P, true);
      	  anObject(Attributes);
      	  if (ie8DomDefine) try {
      	    return nativeDefineProperty(O, P, Attributes);
      	  } catch (error) { /* empty */ }
      	  if ('get' in Attributes || 'set' in Attributes) throw TypeError('Accessors not supported');
      	  if ('value' in Attributes) O[P] = Attributes.value;
      	  return O;
      	};

      	var objectDefineProperty = {
      		f: f$1
      	};

      	var createNonEnumerableProperty = descriptors ? function (object, key, value) {
      	  return objectDefineProperty.f(object, key, createPropertyDescriptor(1, value));
      	} : function (object, key, value) {
      	  object[key] = value;
      	  return object;
      	};

      	var getOwnPropertyDescriptor = objectGetOwnPropertyDescriptor.f;






      	var wrapConstructor = function (NativeConstructor) {
      	  var Wrapper = function (a, b, c) {
      	    if (this instanceof NativeConstructor) {
      	      switch (arguments.length) {
      	        case 0: return new NativeConstructor();
      	        case 1: return new NativeConstructor(a);
      	        case 2: return new NativeConstructor(a, b);
      	      } return new NativeConstructor(a, b, c);
      	    } return NativeConstructor.apply(this, arguments);
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
      	*/
      	var _export = function (options, source) {
      	  var TARGET = options.target;
      	  var GLOBAL = options.global;
      	  var STATIC = options.stat;
      	  var PROTO = options.proto;

      	  var nativeSource = GLOBAL ? global_1 : STATIC ? global_1[TARGET] : (global_1[TARGET] || {}).prototype;

      	  var target = GLOBAL ? path : path[TARGET] || (path[TARGET] = {});
      	  var targetPrototype = target.prototype;

      	  var FORCED, USE_NATIVE, VIRTUAL_PROTOTYPE;
      	  var key, sourceProperty, targetProperty, nativeProperty, resultProperty, descriptor;

      	  for (key in source) {
      	    FORCED = isForced_1(GLOBAL ? key : TARGET + (STATIC ? '.' : '#') + key, options.forced);
      	    // contains in native
      	    USE_NATIVE = !FORCED && nativeSource && has(nativeSource, key);

      	    targetProperty = target[key];

      	    if (USE_NATIVE) if (options.noTargetGet) {
      	      descriptor = getOwnPropertyDescriptor(nativeSource, key);
      	      nativeProperty = descriptor && descriptor.value;
      	    } else nativeProperty = nativeSource[key];

      	    // export native or implementation
      	    sourceProperty = (USE_NATIVE && nativeProperty) ? nativeProperty : source[key];

      	    if (USE_NATIVE && typeof targetProperty === typeof sourceProperty) continue;

      	    // bind timers to global for call from export context
      	    if (options.bind && USE_NATIVE) resultProperty = functionBindContext(sourceProperty, global_1);
      	    // wrap global constructors for prevent changs in this version
      	    else if (options.wrap && USE_NATIVE) resultProperty = wrapConstructor(sourceProperty);
      	    // make static versions for prototype methods
      	    else if (PROTO && typeof sourceProperty == 'function') resultProperty = functionBindContext(Function.call, sourceProperty);
      	    // default case
      	    else resultProperty = sourceProperty;

      	    // add a flag to not completely full polyfills
      	    if (options.sham || (sourceProperty && sourceProperty.sham) || (targetProperty && targetProperty.sham)) {
      	      createNonEnumerableProperty(resultProperty, 'sham', true);
      	    }

      	    target[key] = resultProperty;

      	    if (PROTO) {
      	      VIRTUAL_PROTOTYPE = TARGET + 'Prototype';
      	      if (!has(path, VIRTUAL_PROTOTYPE)) {
      	        createNonEnumerableProperty(path, VIRTUAL_PROTOTYPE, {});
      	      }
      	      // export virtual prototype methods
      	      path[VIRTUAL_PROTOTYPE][key] = sourceProperty;
      	      // export real prototype methods
      	      if (options.real && targetPrototype && !targetPrototype[key]) {
      	        createNonEnumerableProperty(targetPrototype, key, sourceProperty);
      	      }
      	    }
      	  }
      	};

      	var ceil = Math.ceil;
      	var floor = Math.floor;

      	// `ToInteger` abstract operation
      	// https://tc39.github.io/ecma262/#sec-tointeger
      	var toInteger = function (argument) {
      	  return isNaN(argument = +argument) ? 0 : (argument > 0 ? floor : ceil)(argument);
      	};

      	var min$1 = Math.min;

      	// `ToLength` abstract operation
      	// https://tc39.github.io/ecma262/#sec-tolength
      	var toLength = function (argument) {
      	  return argument > 0 ? min$1(toInteger(argument), 0x1FFFFFFFFFFFFF) : 0; // 2 ** 53 - 1 == 9007199254740991
      	};

      	var max = Math.max;
      	var min = Math.min;

      	// Helper for a popular repeating case of the spec:
      	// Let integer be ? ToInteger(index).
      	// If integer < 0, let result be max((length + integer), 0); else let result be min(integer, length).
      	var toAbsoluteIndex = function (index, length) {
      	  var integer = toInteger(index);
      	  return integer < 0 ? max(integer + length, 0) : min(integer, length);
      	};

      	// `Array.prototype.{ indexOf, includes }` methods implementation
      	var createMethod = function (IS_INCLUDES) {
      	  return function ($this, el, fromIndex) {
      	    var O = toIndexedObject($this);
      	    var length = toLength(O.length);
      	    var index = toAbsoluteIndex(fromIndex, length);
      	    var value;
      	    // Array#includes uses SameValueZero equality algorithm
      	    // eslint-disable-next-line no-self-compare
      	    if (IS_INCLUDES && el != el) while (length > index) {
      	      value = O[index++];
      	      // eslint-disable-next-line no-self-compare
      	      if (value != value) return true;
      	    // Array#indexOf ignores holes, Array#includes - not
      	    } else for (;length > index; index++) {
      	      if ((IS_INCLUDES || index in O) && O[index] === el) return IS_INCLUDES || index || 0;
      	    } return !IS_INCLUDES && -1;
      	  };
      	};

      	var arrayIncludes = {
      	  // `Array.prototype.includes` method
      	  // https://tc39.github.io/ecma262/#sec-array.prototype.includes
      	  includes: createMethod(true),
      	  // `Array.prototype.indexOf` method
      	  // https://tc39.github.io/ecma262/#sec-array.prototype.indexof
      	  indexOf: createMethod(false)
      	};

      	var hiddenKeys = {};

      	var indexOf = arrayIncludes.indexOf;


      	var objectKeysInternal = function (object, names) {
      	  var O = toIndexedObject(object);
      	  var i = 0;
      	  var result = [];
      	  var key;
      	  for (key in O) !has(hiddenKeys, key) && has(O, key) && result.push(key);
      	  // Don't enum bug & hidden keys
      	  while (names.length > i) if (has(O, key = names[i++])) {
      	    ~indexOf(result, key) || result.push(key);
      	  }
      	  return result;
      	};

      	// IE8- don't enum bug keys
      	var enumBugKeys = [
      	  'constructor',
      	  'hasOwnProperty',
      	  'isPrototypeOf',
      	  'propertyIsEnumerable',
      	  'toLocaleString',
      	  'toString',
      	  'valueOf'
      	];

      	// `Object.keys` method
      	// https://tc39.github.io/ecma262/#sec-object.keys
      	var objectKeys = Object.keys || function keys(O) {
      	  return objectKeysInternal(O, enumBugKeys);
      	};

      	var f = Object.getOwnPropertySymbols;

      	var objectGetOwnPropertySymbols = {
      		f: f
      	};

      	// `ToObject` abstract operation
      	// https://tc39.github.io/ecma262/#sec-toobject
      	var toObject = function (argument) {
      	  return Object(requireObjectCoercible(argument));
      	};

      	var nativeAssign = Object.assign;
      	var defineProperty = Object.defineProperty;

      	// `Object.assign` method
      	// https://tc39.github.io/ecma262/#sec-object.assign
      	var objectAssign = !nativeAssign || fails(function () {
      	  // should have correct order of operations (Edge bug)
      	  if (descriptors && nativeAssign({ b: 1 }, nativeAssign(defineProperty({}, 'a', {
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
      	  // eslint-disable-next-line no-undef
      	  var symbol = Symbol();
      	  var alphabet = 'abcdefghijklmnopqrst';
      	  A[symbol] = 7;
      	  alphabet.split('').forEach(function (chr) { B[chr] = chr; });
      	  return nativeAssign({}, A)[symbol] != 7 || objectKeys(nativeAssign({}, B)).join('') != alphabet;
      	}) ? function assign(target, source) { // eslint-disable-line no-unused-vars
      	  var T = toObject(target);
      	  var argumentsLength = arguments.length;
      	  var index = 1;
      	  var getOwnPropertySymbols = objectGetOwnPropertySymbols.f;
      	  var propertyIsEnumerable = objectPropertyIsEnumerable.f;
      	  while (argumentsLength > index) {
      	    var S = indexedObject(arguments[index++]);
      	    var keys = getOwnPropertySymbols ? objectKeys(S).concat(getOwnPropertySymbols(S)) : objectKeys(S);
      	    var length = keys.length;
      	    var j = 0;
      	    var key;
      	    while (length > j) {
      	      key = keys[j++];
      	      if (!descriptors || propertyIsEnumerable.call(S, key)) T[key] = S[key];
      	    }
      	  } return T;
      	} : nativeAssign;

      	// `Object.assign` method
      	// https://tc39.github.io/ecma262/#sec-object.assign
      	_export({ target: 'Object', stat: true, forced: Object.assign !== objectAssign }, {
      	  assign: objectAssign
      	});

      	var assign$2 = path.Object.assign;

      	var assign$1 = assign$2;

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
      export default class { };
    JS

    file 'name.js', <<~JS
      import C from 'module/name';
      
      class D extends C { }
    JS

    assert_file 'name.js', 'application/javascript', <<~JS
      import _Reflect$construct from "@babel/runtime-corejs3/core-js-stable/reflect/construct";
      import _classCallCheck from "@babel/runtime-corejs3/helpers/esm/classCallCheck";
      import _inherits from "@babel/runtime-corejs3/helpers/esm/inherits";
      import _possibleConstructorReturn from "@babel/runtime-corejs3/helpers/esm/possibleConstructorReturn";
      import _getPrototypeOf from "@babel/runtime-corejs3/helpers/esm/getPrototypeOf";
      
      function _createSuper(Derived) { var hasNativeReflectConstruct = _isNativeReflectConstruct(); return function _createSuperInternal() { var Super = _getPrototypeOf(Derived), result; if (hasNativeReflectConstruct) { var NewTarget = _getPrototypeOf(this).constructor; result = _Reflect$construct(Super, arguments, NewTarget); } else { result = Super.apply(this, arguments); } return _possibleConstructorReturn(this, result); }; }
      
      function _isNativeReflectConstruct() { if (typeof Reflect === "undefined" || !_Reflect$construct) return false; if (_Reflect$construct.sham) return false; if (typeof Proxy === "function") return true; try { Date.prototype.toString.call(_Reflect$construct(Date, [], function () {})); return true; } catch (e) { return false; } }
      
      import C from 'module/name';
      
      var D = /*#__PURE__*/function (_C) {
        _inherits(D, _C);
      
        var _super = _createSuper(D);
      
        function D() {
          _classCallCheck(this, D);
      
          return _super.apply(this, arguments);
        }
      
        return D;
      }(C);
    JS

  end
end