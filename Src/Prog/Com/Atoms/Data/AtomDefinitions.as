package Src.Prog.Com.Atoms.Data {
    import Src.Prog.Com.Atoms.Core.Atom;

    /**
     * Central registry for all atom definitions in the system
     * ALL atoms must be registered here to be available in the application
     */
    public class AtomDefinitions {
        private static var _definitions:Object = {};
        private static var _initialized:Boolean = false;

        /**
         * Register all atom definitions - call this once at app startup
         */
        public static function initialize():void {
            if (_initialized) {
                trace("AtomDefinitions: Already initialized");
                return;
            }

            trace("AtomDefinitions: Initializing atom registry...");

            // Input Atoms
            registerAtomType("Button", {
                displayName: "Button",
                category: "Input",
                description: "A simple push button that sends impulses when pressed",
                pins: [
                    {name: "output", type: "output", dataType: "impulse", description: "Sends impulse when pressed"}
                ],
                behavior: {
                    onInteraction: function(atom:Atom, interactionType:String):Atom {
                        trace("Button pressed - sending impulse");
                        // Button logic here
                        return atom;
                    }
                },
                viewConfig: {
                    width: 60,
                    height: 30,
                    backgroundColor: 0x3366CC
                },
                visuals: {
                    base: {
                        width: 60,
                        height: 30,
                        color: 0x3366CC,
                        textColor: 0x000000,
						cornerRadius: 8
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
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
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("Slider", {
                displayName: "Slider",
                category: "Input",
                description: "A slider for selecting numeric values",
                pins: [
                    {name: "value", type: "output", dataType: "number", description: "Current slider value"}
                ],
                viewConfig: {
                    width: 100,
                    height: 30,
                    backgroundColor: 0xCC6633
                },
                visuals: {
                    base: {
                        width: 100,
                        height: 30,
                        color: 0xCC6633,
                        textColor: 0x000000
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            // Logic Atoms
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
                        // Counter logic here
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
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("Timer", {
                displayName: "Timer",
                category: "Logic",
                description: "Generates impulses at regular intervals", 
                pins: [
                    {name: "start", type: "input", dataType: "impulse", description: "Start timer"},
                    {name: "stop", type: "input", dataType: "impulse", description: "Stop timer"},
                    {name: "interval", type: "input", dataType: "number", description: "Timer interval in ms"},
                    {name: "output", type: "output", dataType: "impulse", description: "Timer impulse output"}
                ],
                viewConfig: {
                    width: 70,
                    height: 35,
                    backgroundColor: 0xCC9966
                },
                visuals: {
                    base: {
                        width: 70,
                        height: 35,
                        color: 0xCC9966,
                        textColor: 0x000000
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            // Output Atoms
            registerAtomType("NumberDisplay", {
                displayName: "Number Display",
                category: "Output",
                description: "Displays numeric values on screen",
                pins: [
                    {name: "value", type: "input", dataType: "number", description: "Numeric value to display"},
                    {name: "trigger", type: "input", dataType: "impulse", description: "Update display"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        trace("NumberDisplay: Value changed to " + value);
                        return atom;
                    }
                },
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
                    Editor: {
                        // специфичные настройки для Editor
                    }
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
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("LED", {
                displayName: "LED Indicator",
                category: "Output", 
                description: "Visual indicator that lights up when active",
                pins: [
                    {name: "input", type: "input", dataType: "boolean", description: "LED state (on/off)"}
                ],
                viewConfig: {
                    width: 30,
                    height: 30,
                    backgroundColor: 0x333333
                },
                visuals: {
                    base: {
                        width: 30,
                        height: 30,
                        color: 0x333333,
                        textColor: 0xFFFFFF
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            // System Atoms
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
                    Editor: {
                        // специфичные настройки для Editor
                    }
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
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            _initialized = true;
            trace("AtomDefinitions: Initialization complete - " + getSupportedTypes().length + " atom types registered");
        }

        /**
         * Register a single atom type
         */
        public static function registerAtomType(type:String, definition:Object):void {
            if (_definitions[type]) {
                trace("WARNING: Overwriting existing atom definition: " + type);
            }
            
            _definitions[type] = definition;
            trace("AtomDefinitions: Registered - " + type);
        }

        /**
         * Get atom definition by type
         */
        public static function getAtomDefinition(type:String):Object {
            if (!_initialized) {
                trace("ERROR: AtomDefinitions not initialized!");
                return null;
            }
            
            var definition:Object = _definitions[type];
            if (!definition) {
                trace("WARNING: Atom definition not found: " + type);
            }
            
            return definition;
        }

        /**
         * Get all supported atom types
         */
        public static function getSupportedTypes():Array {
            if (!_initialized) {
                trace("ERROR: AtomDefinitions not initialized!");
                return [];
            }
            
            var types:Array = [];
            for (var key:String in _definitions) {
                types.push(key);
            }
            types.sort(); // Alphabetical order
            return types;
        }

        /**
         * Get atom types by category
         */
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

        /**
         * Get all available categories
         */
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

        /**
         * Check if atom type is registered
         */
        public static function isAtomTypeRegistered(type:String):Boolean {
            return _definitions[type] != null;
        }

        /**
         * Validate all atom definitions
         */
        public static function validateDefinitions():void {
            trace("=== ATOM DEFINITIONS VALIDATION ===");
            
            var supportedTypes:Array = getSupportedTypes();
            trace("Total registered atoms: " + supportedTypes.length);
            
            var errors:int = 0;
            var warnings:int = 0;
            
            for each (var type:String in supportedTypes) {
                var definition:Object = getAtomDefinition(type);
                
                if (!definition) {
                    trace("ERROR: " + type + " - definition missing");
                    errors++;
                    continue;
                }
                
                // Check required fields
                if (!definition.displayName) {
                    trace("WARNING: " + type + " - missing displayName");
                    warnings++;
                }
                
                if (!definition.category) {
                    trace("WARNING: " + type + " - missing category");
                    warnings++;
                }
                
                if (!definition.pins || definition.pins.length == 0) {
                    trace("WARNING: " + type + " - no pins defined");
                    warnings++;
                } else {
                    // Validate pins
                    for each (var pin:Object in definition.pins) {
                        if (!pin.name) {
                            trace("WARNING: " + type + " - pin missing name");
                            warnings++;
                        }
                        if (!pin.type || (pin.type != "input" && pin.type != "output")) {
                            trace("WARNING: " + type + " - pin '" + pin.name + "' has invalid type: " + pin.type);
                            warnings++;
                        }
                    }
                }
                
                trace("VALID: " + type + " (" + definition.displayName + ") - " + 
                      (definition.pins ? definition.pins.length : 0) + " pins");
            }
            
            trace("Validation complete - Errors: " + errors + ", Warnings: " + warnings);
            trace("=== END VALIDATION ===");
        }

        /**
         * Clear all definitions (for testing)
         */
        public static function clear():void {
            _definitions = new Object();
            _initialized = false;
            trace("AtomDefinitions: Cleared all definitions");
        }
    }
}
