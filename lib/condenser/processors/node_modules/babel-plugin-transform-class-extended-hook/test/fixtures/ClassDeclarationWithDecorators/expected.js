var __babelPluginTransformClassInheritedHook = function (child, parent, childName) {
  if (childName) {
    Object.defineProperty(child, "name", {
      value: childName,
      configurable: true
    });
  }

  if ("onInherited" in parent) {
    if (typeof parent.onInherited == 'function') {
      var returnedNewChild = parent.onInherited(child);

      if (returnedNewChild !== void 0) {
        if (childName && typeof returnedNewChild == 'function' && returnedNewChild.name !== childName) {
          Object.defineProperty(returnedNewChild, "name", {
            value: childName,
            configurable: true
          });
        }

        child = returnedNewChild;
      }
    } else {
      throw new TypeError("Attempted to call onInherited, but it was not a function");
    }
  }

  return child;
};

let Apple = function () {
  var _class;

  var _Apple = tasty(_class = class extends Fruit {
    tastiness() {
      return 7;
    }
  }) || _class;

  return __babelPluginTransformClassInheritedHook(_Apple, Fruit, "Apple");
}();
