import 'mocha';
import * as assert from 'assert';

describe("Class.extended", function() {
    describe("is called when a class is extended", function() {
        it("using named class declarations", function() {
            let child = null;

            class Parent {
                static extended(inheritor) {
                    child = inheritor;
                }
            }

            class Child extends Parent {}

            assert.strictEqual(child, Child);
        });

        it("using anonymous class expressions with variable declaration", function() {
            let child = null;

            let Parent = class {
                static extended(inheritor) {
                    child = inheritor;
                }
            };

            let Child = class extends Parent {};

            assert.strictEqual(child, Child);
        });

        it("using named class expressions saved as variables", function() {
            let child = null;

            let Parent = class NamedParent {
                static extended(inheritor) {
                    child = inheritor;
                }
            };

            let Child = class NamedChild extends Parent {};

            assert.strictEqual(child, Child);
        });

        it("using anonymous class expressions on object literal properties", function() {
            let child = null;

            let Parents = {
                Parent: class {
                    static extended(inheritor) {
                        child = inheritor;
                    }
                }
            };

            let Children = {
                Child: class extends Parents.Parent {}
            }

            assert.strictEqual(child, Children.Child);
        });

        it("using named class expressions on object literal properties", function() {
            let child = null;

            let Parents = {
                Parent: class NamedParent {
                    static extended(inheritor) {
                        child = inheritor;
                    }
                }
            };

            let Children = {
                Child: class NamedChild extends Parents.Parent {}
            }

            assert.strictEqual(child, Children.Child);
        });
    });

    describe("is called when a class is inherited from (down the chain)", function() {
        it("using named class declarations", function() {
            let child = null;

            class Grandparent {
                static extended(inheritor) {
                    child = inheritor;
                }
            }

            class Parent extends Grandparent {}

            class Child extends Parent {}

            assert.strictEqual(child, Child);
        });

        it("using anonymous class expressions with variable declaration", function() {
            let child = null;

            let Grandparent = class {
                static extended(inheritor) {
                    child = inheritor;
                }
            };

            let Parent = class extends Grandparent {};

            let Child = class extends Parent {};

            assert.strictEqual(child, Child);
        });

        it("using named class expressions saved as variables", function() {
            let child = null;

            let Grandparent = class NamedGrandparent {
                static extended(inheritor) {
                    child = inheritor;
                }
            };

            let Parent = class NamedParent extends Grandparent {};

            let Child = class NamedChild extends Parent {};

            assert.strictEqual(child, Child);
        });

        it("using anonymous class expressions on object literal properties", function() {
            let child = null;

            let Grandparents = {
                Grandparent: class {
                    static extended(inheritor) {
                        child = inheritor;
                    }
                }
            };

            let Parents = {
                Parent: class extends Grandparents.Grandparent {}
            };

            let Children = {
                Child: class extends Parents.Parent {}
            };

            assert.strictEqual(child, Children.Child);
        });

        it("using named class expressions on object literal properties", function() {
            let child = null;

            let Grandparents = {
                Grandparent: class NamedGrandparent {
                    static extended(inheritor) {
                        child = inheritor;
                    }
                }
            };

            let Parents = {
                Parent: class NamedParent extends Grandparents.Grandparent {}
            };

            let Children = {
                Child: class NamedChild extends Parents.Parent {}
            };

            assert.strictEqual(child, Children.Child);
        });
    });
    describe("can be overriden by an intermediate class in the prototype chain", function() {
        it("using named class declarations", function() {
            let calledWith = [];

            class Grandparent {
                static extended(inheritor) {
                    calledWith.push(inheritor);
                }
            }

            class Parent extends Grandparent {
                static extended(inheritor) {}
            }

            class Child extends Parent {}

            assert.deepStrictEqual(calledWith, [Parent]);
        });

        it("using anonymous class expressions with variable declaration", function() {
            let calledWith = [];

            let Grandparent = class {
                static extended(inheritor) {
                    calledWith.push(inheritor);
                }
            };

            let Parent = class extends Grandparent {
                static extended(inheritor) {}
            };

            let Child = class extends Parent {};

            assert.deepStrictEqual(calledWith, [Parent]);
        });

        it("using named class expressions saved as variables", function() {
            let calledWith = [];

            let Grandparent = class NamedGrandparent {
                static extended(inheritor) {
                    calledWith.push(inheritor);
                }
            };

            let Parent = class NamedParent extends Grandparent {
                static extended(inheritor) {}
            };

            let Child = class NamedChild extends Parent {};

            assert.deepStrictEqual(calledWith, [Parent]);
        });

        it("using anonymous class expressions on object literal properties", function() {
            let calledWith = [];

            let Grandparents = {
                Grandparent: class {
                    static extended(inheritor) {
                        calledWith.push(inheritor);
                    }
                }
            };

            let Parents = {
                Parent: class extends Grandparents.Grandparent {
                    static extended(inheritor) {}
                }
            };

            let Children = {
                Child: class extends Parents.Parent {}
            }

            assert.deepStrictEqual(calledWith, [Parents.Parent]);
        });

        it("using named class expressions on object literal properties", function() {
            let calledWith = [];

            let Grandparents = {
                Grandparent: class NamedGrandparent {
                    static extended(inheritor) {
                        calledWith.push(inheritor);
                    }
                }
            };

            let Parents = {
                Parent: class NamedParent extends Grandparents.Grandparent {
                    static extended(inheritor) {}
                }
            };

            let Children = {
                Child: class NamedChild extends Parents.Parent {}
            }

            assert.deepStrictEqual(calledWith, [Parents.Parent]);
        });
    });

    describe("can redefine the value of the declared class", function() {
        it("using named class declarations", function() {
            let replacement = {};

            class Parent {
                static extended(inheritor) {
                    return replacement;
                }
            }

            class Child extends Parent {}

            assert.strictEqual(Child, replacement);
        });

        it("using anonymous class expressions with variable declaration", function() {
            let replacement = {};

            let Parent = class {
                static extended(inheritor) {
                    return replacement;
                }
            };

            let Child = class extends Parent {};

            assert.strictEqual(Child, replacement);
        });

        it("using named class expressions saved as variables", function() {
            let replacement = {};

            let Parent = class NamedParent {
                static extended(inheritor) {
                    return replacement;
                }
            };

            let Child = class NamedChild extends Parent {};

            assert.strictEqual(Child, replacement);
        });

        it("using anonymous class expressions on object literal properties", function() {
            let replacement = {};

            let Parents = {
                Parent: class {
                    static extended(inheritor) {
                        return replacement;
                    }
                }
            };

            let Children = {
                Child: class extends Parents.Parent {}
            }

            assert.strictEqual(Children.Child, replacement);
        });

        it("using named class expressions on object literal properties", function() {
            let replacement = {};

            let Parents = {
                Parent: class NamedParent {
                    static extended(inheritor) {
                        return replacement;
                    }
                }
            };

            let Children = {
                Child: class NamedChild extends Parents.Parent {}
            }

            assert.strictEqual(Children.Child, replacement);
        });
    });

    describe("can redefine the value of the declared class to a falsy value other than undefined", function() {
        describe("null", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {
                        return null;
                    }
                }

                class Child extends Parent {}

                assert.strictEqual(Child, null);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {
                        return null;
                    }
                };

                let Child = class extends Parent {};

                assert.strictEqual(Child, null);
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {
                        return null;
                    }
                };

                let Child = class NamedChild extends Parent {};

                assert.strictEqual(Child, null);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {
                            return null;
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                }

                assert.strictEqual(Children.Child, null);
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {
                            return null;
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                }

                assert.strictEqual(Children.Child, null);
            });
        });

        describe("0", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {
                        return 0;
                    }
                }

                class Child extends Parent {}

                assert.strictEqual(Child, 0);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {
                        return 0;
                    }
                };

                let Child = class extends Parent {};

                assert.strictEqual(Child, 0);
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {
                        return 0;
                    }
                };

                let Child = class NamedChild extends Parent {};

                assert.strictEqual(Child, 0);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {
                            return 0;
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                }

                assert.strictEqual(Children.Child, 0);
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {
                            return 0;
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                }

                assert.strictEqual(Children.Child, 0);
            });
        });

        describe("\"\" (empty string)", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {
                        return "";
                    }
                }

                class Child extends Parent {}

                assert.equal(Child, "");
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {
                        return "";
                    }
                };

                let Child = class extends Parent {};

                assert.equal(Child, "");
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {
                        return "";
                    }
                };

                let Child = class NamedChild extends Parent {};

                assert.equal(Child, "");
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {
                            return "";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                }

                assert.equal(Children.Child, "");
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {
                            return "";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                }

                assert.equal(Children.Child, "");
            });
        });

        describe("false", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {
                        return false;
                    }
                }

                class Child extends Parent {}

                assert.equal(Child, false);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {
                        return false;
                    }
                };

                let Child = class extends Parent {};

                assert.equal(Child, false);
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {
                        return false;
                    }
                };

                let Child = class NamedChild extends Parent {};

                assert.equal(Child, false);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {
                            return false;
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                }

                assert.equal(Children.Child, false);
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {
                            return false;
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                }

                assert.equal(Children.Child, false);
            });
        });

        describe("NaN", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {
                        return NaN;
                    }
                }

                class Child extends Parent {}

                assert.ok(isNaN(Child));
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {
                        return NaN;
                    }
                };

                let Child = class extends Parent {};

                assert.ok(isNaN(Child));
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {
                        return NaN;
                    }
                };

                let Child = class NamedChild extends Parent {};

                assert.ok(isNaN(Child));
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {
                            return NaN;
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                }

                assert.ok(isNaN(Children.Child));
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {
                            return NaN;
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                }

                assert.ok(isNaN(Children.Child));
            });
        });
    });

    describe("can not redefine the value of the declared class by returning undefined", function() {
        it("using named class declarations", function() {
            class Parent {
                static extended(inheritor) {
                    return undefined;
                }
            }

            class Child extends Parent {}

            assert.notEqual(Child, undefined)
        });

        it("using anonymous class expressions with variable declaration", function() {
            let Parent = class {
                static extended(inheritor) {
                    return undefined;
                }
            };

            let Child = class extends Parent {};

            assert.notEqual(Child, undefined)
        });

        it("using named class expressions saved as variables", function() {
            let Parent = class NamedParent {
                static extended(inheritor) {
                    return undefined;
                }
            };

            let Child = class NamedChild extends Parent {};

            assert.notEqual(Child, undefined)
        });

        it("using anonymous class expressions on object literal properties", function() {
            let Parents = {
                Parent: class {
                    static extended(inheritor) {
                        return undefined;
                    }
                }
            };

            let Children = {
                Child: class extends Parents.Parent {}
            }

            assert.notEqual(Children.Child, undefined)
        });

        it("using named class expressions on object literal properties", function() {
            let Parents = {
                Parent: class NamedParent {
                    static extended(inheritor) {
                        return undefined;
                    }
                }
            };

            let Children = {
                Child: class NamedChild extends Parents.Parent {}
            }

            assert.notEqual(Children.Child, undefined)
        });
    });
});



describe("A class", function() {
    describe("with no parent", function() {
        describe("has a reliable name property", function() {
            it("using named class declarations", function() {
                class Thing {}
                assert.equal(Thing.name, "Thing");
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Thing = class {};
                assert.equal(Thing.name, "Thing")
            });

            it("using named class expressions saved as variables", function() {
                let Thing = class NamedThing {};
                assert.equal(Thing.name, "NamedThing")
            });

            it("using named class expressions on object literal properties", function() {
                let Things = {
                    Thing: class NamedThing {}
                }
                assert.equal(Things.Thing.name, "NamedThing")
            });
        });
        describe("can have static methods", function() {
            it("using named class declarations", function() {
                class Thing {
                    static coolnessFactor() {
                        return 5;
                    }
                }
                assert.equal(Thing.coolnessFactor(), 5);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Thing = class {
                    static coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(Thing.coolnessFactor(), 5);
            });

            it("using named class expressions saved as variables", function() {
                let Thing = class NamedThing {
                    static coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(Thing.coolnessFactor(), 5);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Things = {
                    Thing: class {
                        static coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(Things.Thing.coolnessFactor(), 5);
            });

            it("using named class expressions on object literal properties", function() {
                let Things = {
                    Thing: class NamedThing {
                        static coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(Things.Thing.coolnessFactor(), 5);
            });
        });
        describe("can have instance methods", function() {
            it("using named class declarations", function() {
                class Thing {
                    coolnessFactor() {
                        return 5;
                    }
                }
                assert.equal(new Thing().coolnessFactor(), 5);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Thing = class {
                    coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(new Thing().coolnessFactor(), 5);
            });

            it("using named class expressions saved as variables", function() {
                let Thing = class NamedThing {
                    coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(new Thing().coolnessFactor(), 5);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Things = {
                    Thing: class {
                        coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(new Things.Thing().coolnessFactor(), 5);
            });

            it("using named class expressions on object literal properties", function() {
                let Things = {
                    Thing: class NamedThing {
                        coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(new Things.Thing().coolnessFactor(), 5);
            });
        });
    });
    describe("with no parent that defines a static extended method", function() {
        describe("has a reliable name property", function() {
            it("using named class declarations", function() {
                class Thing {
                    static extended(inheritor) {}
                }
                assert.equal(Thing.name, "Thing")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Thing = class {
                    static extended(inheritor) {}
                };
                assert.equal(Thing.name, "Thing")
            });

            it("using named class expressions saved as variables", function() {
                let Thing = class NamedThing {
                    static extended(inheritor) {}
                };
                assert.equal(Thing.name, "NamedThing")
            });

            it("using named class expressions on object literal properties", function() {
                let Things = {
                    Thing: class NamedThing {
                        static extended(inheritor) {}
                    }
                }
                assert.equal(Things.Thing.name, "NamedThing")
            });
        });
        describe("can have static methods", function() {
            it("using named class declarations", function() {
                class Thing {
                    static extended(inheritor) {}
                    static coolnessFactor() {
                        return 5;
                    }
                }
                assert.equal(Thing.coolnessFactor(), 5);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Thing = class {
                    static extended(inheritor) {}
                    static coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(Thing.coolnessFactor(), 5);
            });

            it("using named class expressions saved as variables", function() {
                let Thing = class NamedThing {
                    static extended(inheritor) {}
                    static coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(Thing.coolnessFactor(), 5);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Things = {
                    Thing: class {
                        static extended(inheritor) {}
                        static coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(Things.Thing.coolnessFactor(), 5);
            });

            it("using named class expressions on object literal properties", function() {
                let Things = {
                    Thing: class NamedThing {
                        static extended(inheritor) {}
                        static coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(Things.Thing.coolnessFactor(), 5);
            });
        });
        describe("can have instance methods", function() {
            it("using named class declarations", function() {
                class Thing {
                    static extended(inheritor) {}
                    coolnessFactor() {
                        return 5;
                    }
                }
                assert.equal(new Thing().coolnessFactor(), 5);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Thing = class {
                    static extended(inheritor) {}
                    coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(new Thing().coolnessFactor(), 5);
            });

            it("using named class expressions saved as variables", function() {
                let Thing = class NamedThing {
                    static extended(inheritor) {}
                    coolnessFactor() {
                        return 5;
                    }
                };
                assert.equal(new Thing().coolnessFactor(), 5);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Things = {
                    Thing: class {
                        static extended(inheritor) {}
                        coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(new Things.Thing().coolnessFactor(), 5);
            });

            it("using named class expressions on object literal properties", function() {
                let Things = {
                    Thing: class NamedThing {
                        static extended(inheritor) {}
                        coolnessFactor() {
                            return 5;
                        }
                    }
                }
                assert.equal(new Things.Thing().coolnessFactor(), 5);
            });
        });
    });
    describe("with a parent", function() {
        describe("has a reliable name property", function() {
            it("using named class declarations", function() {
                class Parent {}
                class Child extends Parent {}
                assert.equal(Child.name, "Child")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {};
                let Child = class extends Parent {};
                assert.equal(Child.name, "Child")
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {};
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.name, "NamedChild")
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.name, "NamedChild")
            });
        });
        describe("can have static methods", function() {
            it("using named class declarations", function() {
                class Parent {}
                class Child extends Parent {
                    static childishness() {
                        return 6;
                    }
                }
                assert.equal(Child.childishness(), 6);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {};
                let Child = class extends Parent {
                    static childishness() {
                        return 6;
                    }
                };
                assert.equal(Child.childishness(), 6);
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {};
                let Child = class NamedChild extends Parent {
                    static childishness() {
                        return 6;
                    }
                };
                assert.equal(Child.childishness(), 6);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {}
                };

                let Children = {
                    Child: class extends Parents.Parent {
                        static childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(Children.Child.childishness(), 6);
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {
                        static childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(Children.Child.childishness(), 6);
            });
        });
        describe("can inherit static methods from its parent", function() {
            it("using named class declarations", function() {
                class Parent {
                    static eyeColor() {
                        return "brown";
                    }
                }
                class Child extends Parent {}
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static eyeColor() {
                        return "brown";
                    }
                };
                let Child = class extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static eyeColor() {
                        return "brown";
                    }
                };
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });
        });
        describe("can have instance methods", function() {
            it("using named class declarations", function() {
                class Parent {}
                class Child extends Parent {
                    childishness() {
                        return 6;
                    }
                }
                assert.equal(new Child().childishness(), 6);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {};
                let Child = class extends Parent {
                    childishness() {
                        return 6;
                    }
                };
                assert.equal(new Child().childishness(), 6);
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {};
                let Child = class NamedChild extends Parent {
                    childishness() {
                        return 6;
                    }
                };
                assert.equal(new Child().childishness(), 6);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {}
                };

                let Children = {
                    Child: class extends Parents.Parent {
                        childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(new Children.Child().childishness(), 6);
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {
                        childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(new Children.Child().childishness(), 6);
            });
        });
        describe("can inherit instance methods from its parent", function() {
            it("using named class declarations", function() {
                class Parent {
                    eyeColor() {
                        return "brown";
                    }
                }
                class Child extends Parent {}
                assert.equal(new Child().eyeColor(), "brown");
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    eyeColor() {
                        return "brown";
                    }
                };
                let Child = class extends Parent {};
                assert.equal(new Child().eyeColor(), "brown");
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    eyeColor() {
                        return "brown";
                    }
                };
                let Child = class NamedChild extends Parent {};
                assert.equal(new Child().eyeColor(), "brown");
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(new Children.Child().eyeColor(), "brown");
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(new Children.Child().eyeColor(), "brown");
            });
        });
    });
    describe("with a parent that declares a static extended method", function() {
        describe("has a reliable name property", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {}
                }
                class Child extends Parent {}
                assert.equal(Child.name, "Child")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {}
                };
                let Child = class extends Parent {};
                assert.equal(Child.name, "Child")
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {}
                };
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.name, "NamedChild")
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {}
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.name, "NamedChild")
            });
        });
        describe("can have static methods", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {}
                }
                class Child extends Parent {
                    static childishness() {
                        return 6;
                    }
                }
                assert.equal(Child.childishness(), 6)
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {}
                };
                let Child = class extends Parent {
                    static childishness() {
                        return 6;
                    }
                };
                assert.equal(Child.childishness(), 6)
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {}
                };
                let Child = class NamedChild extends Parent {
                    static childishness() {
                        return 6;
                    }
                };
                assert.equal(Child.childishness(), 6)
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {}
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {
                        static childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(Children.Child.childishness(), 6)
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {}
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {
                        static childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(Children.Child.childishness(), 6)
            });
        });
        describe("can inherit static methods from its parent", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {}
                    static eyeColor() {
                        return "brown";
                    }
                }
                class Child extends Parent {}
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {}
                    static eyeColor() {
                        return "brown";
                    }
                };
                let Child = class extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {}
                    static eyeColor() {
                        return "brown";
                    }
                };
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {}
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {}
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });
        });
        describe("can have instance methods", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {}
                }
                class Child extends Parent {
                    childishness() {
                        return 6;
                    }
                }
                assert.equal(new Child().childishness(), 6);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {}
                };
                let Child = class extends Parent {
                    childishness() {
                        return 6;
                    }
                };
                assert.equal(new Child().childishness(), 6);
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {}
                };
                let Child = class NamedChild extends Parent {
                    childishness() {
                        return 6;
                    }
                };
                assert.equal(new Child().childishness(), 6);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {}
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {
                        childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(new Children.Child().childishness(), 6);
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {}
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {
                        childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(new Children.Child().childishness(), 6);
            });
        });
        describe("can inherit instance methods from its parent", function() {
            it("using named class declarations", function() {
                class Parent {
                    static extended(inheritor) {}
                    eyeColor() {
                        return "brown";
                    }
                }
                class Child extends Parent {}
                assert.equal(new Child().eyeColor(), "brown");
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Parent = class {
                    static extended(inheritor) {}
                    eyeColor() {
                        return "brown";
                    }
                };
                let Child = class extends Parent {};
                assert.equal(new Child().eyeColor(), "brown");
            });

            it("using named class expressions saved as variables", function() {
                let Parent = class NamedParent {
                    static extended(inheritor) {}
                    eyeColor() {
                        return "brown";
                    }
                };
                let Child = class NamedChild extends Parent {};
                assert.equal(new Child().eyeColor(), "brown");
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class {
                        static extended(inheritor) {}
                        eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(new Children.Child().eyeColor(), "brown");
            });

            it("using named class expressions on object literal properties", function() {
                let Parents = {
                    Parent: class NamedParent {
                        static extended(inheritor) {}
                        eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(new Children.Child().eyeColor(), "brown");
            });
        });
    });
    describe("with a grandparent that declares a static extended method", function() {
        describe("has a reliable name property", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                }
                class Parent extends Grandparent {}
                class Child extends Parent {}
                assert.equal(Child.name, "Child")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                };
                let Parent = class extends Grandparent {};
                let Child = class extends Parent {};
                assert.equal(Child.name, "Child")
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                };
                let Parent = class NamedParent extends Grandparent {};
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.name, "NamedChild")
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.name, "NamedChild")
            });
        });
        describe("can have static methods", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                }
                class Parent extends Grandparent {}
                class Child extends Parent {
                    static childishness() {
                        return 6;
                    }
                }
                assert.equal(Child.childishness(), 6)
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                };
                let Parent = class extends Grandparent {};
                let Child = class extends Parent {
                    static childishness() {
                        return 6;
                    }
                };
                assert.equal(Child.childishness(), 6)
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                };
                let Parent = class NamedParent extends Grandparent {};
                let Child = class NamedChild extends Parent {
                    static childishness() {
                        return 6;
                    }
                };
                assert.equal(Child.childishness(), 6)
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class extends Parents.Parent {
                        static childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(Children.Child.childishness(), 6)
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {
                        static childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(Children.Child.childishness(), 6)
            });
        });
        describe("can inherit static methods from its parent", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                }

                class Parent extends Grandparent {
                    static eyeColor() {
                        return "brown";
                    }
                }
                class Child extends Parent {}
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                };

                let Parent = class extends Grandparent {
                    static eyeColor() {
                        return "brown";
                    }
                };
                let Child = class extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                };

                let Parent = class NamedParent extends Grandparent {
                    static eyeColor() {
                        return "brown";
                    }
                };
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class extends Grandparents.Grandparent {
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });
        });
        describe("can inherit static methods from its grandparent", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                    static eyeColor() {
                        return "brown";
                    }
                }

                class Parent extends Grandparent {}
                class Child extends Parent {}
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                    static eyeColor() {
                        return "brown";
                    }
                };

                let Parent = class extends Grandparent {};
                let Child = class extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                    static eyeColor() {
                        return "brown";
                    }
                };

                let Parent = class NamedParent extends Grandparent {};
                let Child = class NamedChild extends Parent {};
                assert.equal(Child.eyeColor(), "brown")
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class {
                        static extended(inheritor) {}
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Parents = {
                    Parent: class extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                        static eyeColor() {
                            return "brown";
                        }
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(Children.Child.eyeColor(), "brown")
            });
        });
        describe("can have instance methods", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                }

                class Parent extends Grandparent {}
                class Child extends Parent {
                    childishness() {
                        return 6;
                    }
                }
                assert.equal(new Child().childishness(), 6);
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                };

                let Parent = class extends Grandparent {};
                let Child = class extends Parent {
                    childishness() {
                        return 6;
                    }
                }
                assert.equal(new Child().childishness(), 6);
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                };

                let Parent = class NamedParent extends Grandparent {};
                let Child = class NamedChild extends Parent {
                    childishness() {
                        return 6;
                    }
                }
                assert.equal(new Child().childishness(), 6);
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class extends Parents.Parent {
                        childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(new Children.Child().childishness(), 6);
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {
                        childishness() {
                            return 6;
                        }
                    }
                };
                assert.equal(new Children.Child().childishness(), 6);
            });
        });
        describe("can inherit instance methods from its parent", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                }

                class Parent extends Grandparent {
                    hairColor() {
                        return "red";
                    }
                }
                class Child extends Parent {}
                assert.equal(new Child().hairColor(), "red");
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                };

                let Parent = class extends Grandparent {
                    hairColor() {
                        return "red";
                    }
                };
                let Child = class extends Parent {}
                assert.equal(new Child().hairColor(), "red");
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                };

                let Parent = class NamedParent extends Grandparent {
                    hairColor() {
                        return "red";
                    }
                };
                let Child = class NamedChild extends Parent {}
                assert.equal(new Child().hairColor(), "red");
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class extends Grandparents.Grandparent {
                        hairColor() {
                            return "red";
                        }
                    }
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(new Children.Child().hairColor(), "red");
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {
                        hairColor() {
                            return "red";
                        }
                    }
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(new Children.Child().hairColor(), "red");
            });
        });
        describe("can inherit instance methods from its grandparent", function() {
            it("using named class declarations", function() {
                class Grandparent {
                    static extended(inheritor) {}
                    hairColor() {
                        return "red";
                    }
                }

                class Parent extends Grandparent {}
                class Child extends Parent {}
                assert.equal(new Child().hairColor(), "red");
            });

            it("using anonymous class expressions with variable declaration", function() {
                let Grandparent = class {
                    static extended(inheritor) {}
                    hairColor() {
                        return "red";
                    }
                };

                let Parent = class extends Grandparent {};
                let Child = class extends Parent {}
                assert.equal(new Child().hairColor(), "red");
            });

            it("using named class expressions saved as variables", function() {
                let Grandparent = class NamedGrandparent {
                    static extended(inheritor) {}
                    hairColor() {
                        return "red";
                    }
                };

                let Parent = class NamedParent extends Grandparent {};
                let Child = class NamedChild extends Parent {}
                assert.equal(new Child().hairColor(), "red");
            });

            it("using anonymous class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class {
                        static extended(inheritor) {}
                        hairColor() {
                            return "red";
                        }
                    }
                };

                let Parents = {
                    Parent: class extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class extends Parents.Parent {}
                };
                assert.equal(new Children.Child().hairColor(), "red");
            });

            it("using named class expressions on object literal properties", function() {
                let Grandparents = {
                    Grandparent: class NamedGrandparent {
                        static extended(inheritor) {}
                        hairColor() {
                            return "red";
                        }
                    }
                };

                let Parents = {
                    Parent: class NamedParent extends Grandparents.Grandparent {}
                };

                let Children = {
                    Child: class NamedChild extends Parents.Parent {}
                };
                assert.equal(new Children.Child().hairColor(), "red");
            });
        });
    });
});
