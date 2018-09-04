# babel-plugin-transform-class-extended-hook

Babel plugin that transforms subclass declarations to call `superclass.extended` afterwards (if present).

## Example

Before:

```javascript
class Apple extends Fruit {
  tastiness() {
    return 7;
  }
}
```

After:

```javascript
var Apple = function () {
  // Declare the Apple class as an anonymous class _Apple.
  var _Apple = class extends Fruit {
    tastiness() {
      return 7;
    }
  }

  // Set _Apple's name property to 'Apple'.
  Object.defineProperty(_Apple, "name", { value: "Apple", configurable: true });

  // If Fruit has a property called extended,
  if ("extended" in Fruit) {
    // and it's a function,
    if (typeof Fruit.extended == 'function') {
      // call it and save the returned value.
      var _Apple2 = Fruit.extended(_Apple);

      // If Fruit.extended returned a value,
      if (_Apple2 !== undefined) {
        // if it's a function, define its name property as 'Apple', if it didn't have that already.
        if (typeof _Apple2 == 'function' && _Apple2.name !== "Apple") {
          Object.defineProperty(_Apple2, "name", { value: "Apple", configurable: true });
        }

        // Use the returned value as the class instead of the declared one
        _Apple = _Apple2;
      }
    // If Fruit.extended is present but not a function,
    } else {
      // complain about it
      throw new TypeError("Attempted to call extended, but it was not a function");
    }
  }

  // Return the class so it gets set as the variable
  return _Apple;
}();
```
**NOTE:** Actual implementation uses a helper function so this logic isn't repeated every single class declaration.

## What?

Every class declaration with a superClass gets transformed into an expression that:
* Creates the child class
* calls `SuperClass.extended(ChildClass)` if present
* evaluates to the return value of `SuperClass.extended(ChildClass)` if any, otherwise the created child class

## Why?

This lets you hook class inheritance:

```javascript
function register(klass){ ... } // Add to a map, wire things up, etc

class RegisteredItem {
  static extended(child) {
    console.log(`A new registered item class was created: ${child.name}`);
    register(child);
  }
}
```

It also lets you transform classes at inheritance time:

```javascript
class Polyfill {
  // Whether we need to shim the native behavior
  static needsToBeShimmed() {
    return true;
  }

  // If we don't need to shim the native behavior, then
  // this is the native class that should be used instead
  static nativeClass() {
    return null;
  }

  static extended(child) {
    let { needsToBeShimmed, nativeClass } = child;

    if (!needsToBeShimmed()) {
      // If we return a value from extended, it will be used
      // as the value of the class declaration instead of child
      return nativeClass();
    }
  }
}

class Promise extends Polyfill {
  static needsToBeShimmed() {
    return !window.Promise;
  }

  static nativeClass() {
    return window.Promise;
  }

  constructor(func) {
    ...
  }
}

// Promise now refers to either window.Promise or the class defined by
// the Promise class declaration above, depending on if needsToBeShimmed()
// evaluated to true or false
```

## Installation

```sh
$ npm install --save babel-plugin-transform-class-extended-hook
```

## Usage

### Via `.babelrc` (Recommended)

**.babelrc**

```json
{
  "plugins": ["transform-class-extended-hook"]
}
```

### Via CLI

```sh
$ babel --plugins transform-class-extended-hook script.js
```

### Via Node API

```javascript
require('babel-core').transform('code', {
  plugins: ['transform-class-extended-hook']
});
```

## Thanks

* [suchipi/babel-plugin-transform-class-inherited-hook](https://github.com/suchipi/babel-plugin-transform-class-inherited-hook) for the original implementation
* [RReverser/babel-plugin-hello-world](https://github.com/rreverser/babel-plugin-hello-world) for the great babel plugin template
* [thejameskyle/babel-handbook](https://github.com/thejameskyle/babel-handbook) for the documentation to get me started
