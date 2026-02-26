package Src.Atom.Data {
    import Src.Atom.Core.Atom;
    import Src.Impulsator.Impulsys;
    import Src.Impulsator.Impulse;
    import Src.Managers.AtomManager;
    import flash.display.Graphics;
    import Src.Atom.Core.AtomView;
    import Src.Atom.Data.Behaviors.ButtonBehavior;
    import Src.Atom.Data.Behaviors.LEDBehavior;
    import Src.Atom.Data.Behaviors.NumberDisplayBehavior;

    public class AtomDefinitions {
        private static var _definitions:Object = {};
        private static var _initialized:Boolean = false;

        public static function drawLED(graphics:Graphics, atom:Atom, config:Object):void {
            var width:Number = config.width || 30;
            var height:Number = config.height || 30;
            var centerX:Number = width / 2;
            var centerY:Number = height / 2;

            var isOn:Boolean = atom.data.isOn === true;
            var color:uint = isOn ? 0x00FF00 : 0x333333;
            var glowColor:uint = isOn ? 0x80FF80 : 0x666666;

            graphics.clear();
            try {
                if (isOn) {
                    graphics.beginFill(glowColor, 0.3);
                    var glowRadius:Number = Math.max(1, width / 1.5);
                    graphics.drawCircle(centerX, centerY, glowRadius);
                    graphics.endFill();
                }

                graphics.beginFill(color);
                var ledRadius:Number = Math.max(1, width / 2 - 2);
                graphics.drawCircle(centerX, centerY, ledRadius);
                graphics.endFill();

                graphics.lineStyle(1, 0x666666);
                graphics.drawCircle(centerX, centerY, ledRadius);
            } catch (error:Error) {
                graphics.beginFill(0xFF0000);
                graphics.drawRect(0, 0, width, height);
                graphics.endFill();
            }
        }

        public static function initialize():void {
            if (_initialized) {
                return;
            }

            registerAtomType("Button", {
                displayName: "Button",
                category: "Input",
                description: "Button with DUAL output systems (Pin and Contact) - sends TRUE when pressed, FALSE when released",
				pins: [
					{name: "output", type: "output", dataType: "boolean"}
				],

				behavior: new ButtonBehavior(),
                viewConfig: {
                    width: 70,
                    height: 30,
                    backgroundColor: 0x3366CC,
                    dualSystemHint: true,
                    pinPortColor: 0x888888,
                    contactPortColor: 0x00AAFF
                },
                visuals: {
                    base: {
                        width: 70,
                        height: 30,
                        color: 0x3366CC,
                        textColor: 0xFFFFFF,
                        cornerRadius: 8,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            var width:Number = config.width || 70;
                            var height:Number = config.height || 30;

                            graphics.clear();
                            graphics.beginFill(config.color || 0x3366CC);
                            graphics.drawRoundRect(0, 0, width, height, 8, 8);
                            graphics.endFill();
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.drawRoundRect(1, 1, width-2, height-2, 6, 6);
                            graphics.lineStyle(1, 0xFFFFFF);
                            graphics.drawRect(width/2 - 15, height/2 - 8, 30, 16);
                            graphics.lineStyle(1, 0x888888);
                            graphics.beginFill(0x666666);
                            graphics.drawRect(width - 8, height/4 - 4, 8, 8);
                            graphics.endFill();
                            graphics.lineStyle(1, 0x00AAFF);
                            graphics.beginFill(0x0088CC);
                            graphics.drawCircle(width - 4, 3*height/4, 4);
                            graphics.endFill();
                        }
                    },
                    Editor: {},
                    Device: {}
                }
            });

            registerAtomType("Toggle", {
                displayName: "Toggle Switch",
                category: "Input",
                description: "A switch that toggles between on/off states",
                pins: [
                    {name: "state", type: "output", dataType: "boolean", description: "Current toggle state"}
                ],
                viewConfig: {
                    width: 50,
                    height: 25,
                    backgroundColor: 0x66AA66
                },
                visuals: {
                    base: {
                        width: 50,
                        height: 25,
                        color: 0x66AA66,
                        textColor: 0x000000
                    },
                    Editor: {}
                }
            });

			registerAtomType("LED", {
				displayName: "LED Indicator",
				category: "Output",
				description: "LED with DUAL input systems (Pin and Contact) - lights up when active",
				pins: [
					{name: "input", type: "input", dataType: "boolean"},
				],
                behavior: new LEDBehavior(),
				visuals: {
					base: {
						width: 40,
						height: 30,
						color: 0x333333,
						textColor: 0xFFFFFF,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            AtomDefinitions.drawLED(graphics, atom, config);
                            var width:Number = config.width || 40;
                            var height:Number = config.height || 30;
                            graphics.lineStyle(1, 0x888888);
                            graphics.beginFill(0x666666);
                            graphics.drawRect(0, height/4 - 4, 8, 8);
                            graphics.endFill();
                            graphics.lineStyle(1, 0x00AAFF);
                            graphics.beginFill(0x0088CC);
                            graphics.drawCircle(4, 3*height/4, 4);
                            graphics.endFill();
                        }
					},
					Editor: {
						width: 40,
						height: 30,
						color: 0x333333,
						textColor: 0xFFFFFF,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            AtomDefinitions.drawLED(graphics, atom, config);
                            var width:Number = config.width || 40;
                            var height:Number = config.height || 30;
                            graphics.lineStyle(1, 0x888888);
                            graphics.beginFill(0x666666);
                            graphics.drawRect(0, height/4 - 4, 8, 8);
                            graphics.endFill();
                            graphics.lineStyle(1, 0x00AAFF);
                            graphics.beginFill(0x0088CC);
                            graphics.drawCircle(4, 3*height/4, 4);
                            graphics.endFill();
                        }
					},
					Device: {
						width: 40,
						height: 30,
						color: 0x333333,
						textColor: 0xFFFFFF,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            AtomDefinitions.drawLED(graphics, atom, config);
                        }
					}
				}
			});

			registerAtomType("AND", {
                displayName: "AND Gate",
                category: "Logic",
                description: "Logical AND gate - output is TRUE only when both inputs are TRUE",
                pins: [
                    {name: "input1", type: "input", dataType: "boolean", description: "First input signal"},
                    {name: "input2", type: "input", dataType: "boolean", description: "Second input signal"},
                    {name: "output", type: "output", dataType: "boolean", description: "Output signal (input1 AND input2)"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        var newAtom:Atom = atom.setData(pinName, Boolean(value));
                        var input1:Boolean = newAtom.data.input1 === true;
                        var input2:Boolean = newAtom.data.input2 === true;
                        var result:Boolean = input1 && input2;
                        var finalAtom:Atom = newAtom.setPinValue("output", result, false);
                        return finalAtom;
                    },
                    initialize: function(atom:Atom):Atom {
                        var newAtom:Atom = atom;
                        if (!atom.hasValue("input1")) newAtom = newAtom.setData("input1", false);
                        if (!atom.hasValue("input2")) newAtom = newAtom.setData("input2", false);
                        newAtom = newAtom.setPinValue("output", false, false);
                        return newAtom;
                    }
                },
                viewConfig: {
                    width: 70,
                    height: 50,
                    backgroundColor: 0x6666CC
                },
                visuals: {
                    base: {
                        width: 70,
                        height: 50,
                        color: 0x6666CC,
                        textColor: 0xFFFFFF,
                        cornerRadius: 5,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            var width:Number = config.width || 70;
                            var height:Number = config.height || 50;
                            graphics.clear();
                            graphics.beginFill(config.color || 0x6666CC);
                            graphics.drawRoundRect(0, 0, width, height, 10, 10);
                            graphics.endFill();
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
                            graphics.lineStyle(1, 0xFFFFFF);
                            graphics.moveTo(width * 0.3, height * 0.4);
                            graphics.lineTo(width * 0.7, height * 0.4);
                        }
                    },
                    Editor: {},
                    Device: {}
                }
            });

            registerAtomType("OR", {
                displayName: "OR Gate",
                category: "Logic",
                description: "Logical OR gate - output is TRUE when at least one input is TRUE",
                pins: [
                    {name: "input1", type: "input", dataType: "boolean", description: "First input signal"},
                    {name: "input2", type: "input", dataType: "boolean", description: "Second input signal"},
                    {name: "output", type: "output", dataType: "boolean", description: "Output signal (input1 OR input2)"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        var newAtom:Atom = atom.setData(pinName, Boolean(value));
                        var input1:Boolean = newAtom.data.input1 === true;
                        var input2:Boolean = newAtom.data.input2 === true;
                        var result:Boolean = input1 || input2;
                        var finalAtom:Atom = newAtom.setPinValue("output", result, false);
                        return finalAtom;
                    },
                    initialize: function(atom:Atom):Atom {
                        var newAtom:Atom = atom;
                        if (!atom.hasValue("input1")) newAtom = newAtom.setData("input1", false);
                        if (!atom.hasValue("input2")) newAtom = newAtom.setData("input2", false);
                        newAtom = newAtom.setPinValue("output", false, false);
                        return newAtom;
                    }
                },
                viewConfig: {
                    width: 70,
                    height: 50,
                    backgroundColor: 0xCC6666
                },
                visuals: {
                    base: {
                        width: 70,
                        height: 50,
                        color: 0xCC6666,
                        textColor: 0xFFFFFF,
                        cornerRadius: 5,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            var width:Number = config.width || 70;
                            var height:Number = config.height || 50;
                            graphics.clear();
                            graphics.beginFill(config.color || 0xCC6666);
                            graphics.drawRoundRect(0, 0, width, height, 10, 10);
                            graphics.endFill();
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.moveTo(0, height * 0.3);
                            graphics.lineTo(width * 0.3, height * 0.3);
                            graphics.moveTo(0, height * 0.7);
                            graphics.lineTo(width * 0.3, height * 0.7);
                            graphics.moveTo(width * 0.3, height * 0.3);
                            graphics.curveTo(width * 0.5, height * 0.5, width * 0.3, height * 0.7);
                            graphics.moveTo(width * 0.7, height * 0.5);
                            graphics.lineTo(width, height * 0.5);
                        }
                    },
                    Editor: {},
                    Device: {}
                }
            });

            registerAtomType("NOT", {
                displayName: "NOT Gate",
                category: "Logic",
                description: "Logical NOT gate (inverter) - output is the opposite of input",
                pins: [
                    {name: "input", type: "input", dataType: "boolean", description: "Input signal"},
                    {name: "output", type: "output", dataType: "boolean", description: "Output signal (inverse of input)"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        var inputValue:Boolean = Boolean(value);
                        var result:Boolean = !inputValue;
                        var newAtom:Atom = atom.setContactValue("output", result, false);
                        return newAtom;
                    },
                    initialize: function(atom:Atom):Atom {
                        return atom.setContactValue("output", true, false);
                    }
                },
                viewConfig: {
                    width: 60,
                    height: 40,
                    backgroundColor: 0x66CC66
                },
                visuals: {
                    base: {
                        width: 60,
                        height: 40,
                        color: 0x66CC66,
                        textColor: 0xFFFFFF,
                        cornerRadius: 5,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            var width:Number = config.width || 60;
                            var height:Number = config.height || 40;
                            graphics.clear();
                            graphics.beginFill(config.color || 0x66CC66);
                            graphics.drawRoundRect(0, 0, width, height, 10, 10);
                            graphics.endFill();
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.moveTo(0, height * 0.5);
                            graphics.lineTo(width * 0.3, height * 0.5);
                            graphics.moveTo(width * 0.3, height * 0.2);
                            graphics.lineTo(width * 0.7, height * 0.5);
                            graphics.lineTo(width * 0.3, height * 0.8);
                            graphics.lineTo(width * 0.3, height * 0.2);
                            graphics.drawCircle(width * 0.8, height * 0.5, 3);
                            graphics.moveTo(width * 0.83, height * 0.5);
                            graphics.lineTo(width, height * 0.5);
                        }
                    },
                    Editor: {},
                    Device: {}
                }
            });

            registerAtomType("NAND", {
                displayName: "NAND Gate",
                category: "Logic",
                description: "Logical NAND gate - output is FALSE only when both inputs are TRUE",
                pins: [
                    {name: "input1", type: "input", dataType: "boolean", description: "First input signal"},
                    {name: "input2", type: "input", dataType: "boolean", description: "Second input signal"},
                    {name: "output", type: "output", dataType: "boolean", description: "Output signal (NOT (input1 AND input2))"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        var newAtom:Atom = atom.setData(pinName, Boolean(value));
                        var input1:Boolean = newAtom.data.input1 === true;
                        var input2:Boolean = newAtom.data.input2 === true;
                        var result:Boolean = !(input1 && input2);
                        var finalAtom:Atom = newAtom.setContactValue("output", result, false);
                        return finalAtom;
                    },
                    initialize: function(atom:Atom):Atom {
                        var newAtom:Atom = atom;
                        if (!atom.hasValue("input1")) newAtom = newAtom.setData("input1", false);
                        if (!atom.hasValue("input2")) newAtom = newAtom.setData("input2", false);
                        newAtom = newAtom.setContactValue("output", true, false);
                        return newAtom;
                    }
                },
                viewConfig: {
                    width: 70,
                    height: 50,
                    backgroundColor: 0xCC66CC
                },
                visuals: {
                    base: {
                        width: 70,
                        height: 50,
                        color: 0xCC66CC,
                        textColor: 0xFFFFFF,
                        cornerRadius: 5,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            var width:Number = config.width || 70;
                            var height:Number = config.height || 50;
                            graphics.clear();
                            graphics.beginFill(config.color || 0xCC66CC);
                            graphics.drawRoundRect(0, 0, width, height, 10, 10);
                            graphics.endFill();
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
                            graphics.lineStyle(2, 0xFFFFFF);
                            graphics.moveTo(0, height * 0.3);
                            graphics.lineTo(width * 0.2, height * 0.3);
                            graphics.moveTo(0, height * 0.7);
                            graphics.lineTo(width * 0.2, height * 0.7);
                            graphics.moveTo(width * 0.2, height * 0.2);
                            graphics.lineTo(width * 0.6, height * 0.2);
                            graphics.lineTo(width * 0.6, height * 0.8);
                            graphics.lineTo(width * 0.2, height * 0.8);
                            graphics.lineTo(width * 0.2, height * 0.2);
                            graphics.drawCircle(width * 0.7, height * 0.5, 3);
                            graphics.moveTo(width * 0.73, height * 0.5);
                            graphics.lineTo(width, height * 0.5);
                        }
                    },
                    Editor: {},
                    Device: {}
                }
            });

            registerAtomType("Counter", {
                displayName: "Counter",
                category: "Logic",
                description: "Counts impulses and outputs the current count",
                pins: [
                    {name: "input", type: "input", dataType: "impulse", description: "Increment counter"},
                    {name: "reset", type: "input", dataType: "impulse", description: "Reset counter to zero"},
                    {name: "count", type: "output", dataType: "number", description: "Current count value"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        return atom;
                    }
                },
                viewConfig: {
                    width: 80,
                    height: 40,
                    backgroundColor: 0x9966CC
                },
                visuals: {
                    base: {
                        width: 80,
                        height: 40,
                        color: 0x9966CC,
                        textColor: 0x000000
                    },
                    Editor: {}
                }
            });

            registerAtomType("NumberDisplay", {
                displayName: "Number Display",
                category: "Output",
                description: "Displays numeric values on screen",
                pins: [
                    {name: "value", type: "input", dataType: "number", description: "Numeric value to display"},
                    {name: "trigger", type: "input", dataType: "impulse", description: "Update display"}
                ],
				behavior: new NumberDisplayBehavior(),
                viewConfig: {
                    width: 80,
                    height: 40,
                    backgroundColor: 0x222266
                },
                visuals: {
                    base: {
                        width: 80,
                        height: 40,
                        color: 0x222266,
                        textColor: 0xFFFFFF
                    },
                    Editor: {}
                }
            });

            registerAtomType("TextDisplay", {
                displayName: "Text Display",
                category: "Output",
                description: "Displays text messages on screen",
                pins: [
                    {name: "text", type: "input", dataType: "string", description: "Text to display"},
                    {name: "trigger", type: "input", dataType: "impulse", description: "Update display"}
                ],
                viewConfig: {
                    width: 120,
                    height: 50,
                    backgroundColor: 0x226622
                },
                visuals: {
                    base: {
                        width: 120,
                        height: 50,
                        color: 0x226622,
                        textColor: 0xFFFFFF
                    },
                    Editor: {}
                }
            });

            registerAtomType("Clock", {
                displayName: "System Clock",
                category: "System",
                description: "Provides system time information",
                pins: [
                    {name: "time", type: "output", dataType: "number", description: "Current time in ms"},
                    {name: "tick", type: "output", dataType: "impulse", description: "Clock tick impulse"}
                ],
                viewConfig: {
                    width: 90,
                    height: 45,
                    backgroundColor: 0x666633
                },
                visuals: {
                    base: {
                        width: 90,
                        height: 45,
                        color: 0x666633,
                        textColor: 0xFFFFFF
                    },
                    Editor: {}
                }
            });

            registerAtomType("Random", {
                displayName: "Random Generator",
                category: "System",
                description: "Generates random values",
                pins: [
                    {name: "generate", type: "input", dataType: "impulse", description: "Generate new random value"},
                    {name: "min", type: "input", dataType: "number", description: "Minimum value"},
                    {name: "max", type: "input", dataType: "number", description: "Maximum value"},
                    {name: "value", type: "output", dataType: "number", description: "Random value output"}
                ],
                viewConfig: {
                    width: 85,
                    height: 42,
                    backgroundColor: 0x663366
                },
                visuals: {
                    base: {
                        width: 85,
                        height: 42,
                        color: 0x663366,
                        textColor: 0xFFFFFF
                    },
                    Editor: {}
                }
            });

            _initialized = true;
        }

        public static function registerAtomType(type:String, definition:Object):void {
            if (_definitions[type]) {
            }
            _definitions[type] = definition;
        }

        public static function getAtomDefinition(type:String):Object {
            if (!_initialized) {
                return null;
            }
            var definition:Object = _definitions[type];
            return definition;
        }

        public static function getSupportedTypes():Array {
            if (!_initialized) {
                return [];
            }
            var types:Array = [];
            for (var key:String in _definitions) {
                types.push(key);
            }
            types.sort();
            return types;
        }

        public static function getTypesByCategory(category:String):Array {
            var result:Array = [];
            var allTypes:Array = getSupportedTypes();
            for each (var type:String in allTypes) {
                var definition:Object = getAtomDefinition(type);
                if (definition && definition.category == category) {
                    result.push(type);
                }
            }
            return result;
        }

        public static function getCategories():Array {
            var categories:Object = {};
            var allTypes:Array = getSupportedTypes();
            for each (var type:String in allTypes) {
                var definition:Object = getAtomDefinition(type);
                if (definition && definition.category) {
                    categories[definition.category] = true;
                }
            }
            var result:Array = [];
            for (var category:String in categories) {
                result.push(category);
            }
            result.sort();
            return result;
        }

        public static function isAtomTypeRegistered(type:String):Boolean {
            return _definitions[type] != null;
        }

        public static function validateDefinitions():void {
            var supportedTypes:Array = getSupportedTypes();
            var errors:int = 0;
            var warnings:int = 0;

            for each (var type:String in supportedTypes) {
                var definition:Object = getAtomDefinition(type);
                if (!definition) {
                    errors++;
                    continue;
                }

                if (!definition.displayName) {
                    warnings++;
                }

                if (!definition.category) {
                    warnings++;
                }

                if (!definition.pins || definition.pins.length == 0) {
                    warnings++;
                } else {
                    for each (var pin:Object in definition.pins) {
                        if (!pin.name) {
                            warnings++;
                        }
                        if (!pin.type || (pin.type != "input" && pin.type != "output")) {
                            warnings++;
                        }
                    }
                }
            }
        }

        public static function clear():void {
            _definitions = new Object();
            _initialized = false;
        }
    }
}
