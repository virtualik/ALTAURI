package Src.Prog.Com.Atoms.Data {
    import flash.display.Graphics;
    import Src.Prog.Com.Atoms.Core.Atom;

    /**
     * Central data repository defining all atom types and their behaviors.
     * This is the heart of the data-driven architecture - all atom types are defined here.
     * 
     * @class AtomDefinitions
     * @public
     */
    public class AtomDefinitions {
        
        /**
         * Master definitions object containing all atom type configurations.
         * Each atom type has:
         * - behavior: Functions for initialization, input handling, and interactions
         * - pins: Input and output pin definitions
         * - visuals: Rendering configurations for different window types
         */
        public static var definitions:Object = {
            "Button": {
                // Behavior configuration
                behavior: {
                    /**
                     * Initializes the atom when created.
                     * @param {Atom} atom - The atom to initialize
                     * @return {Atom} Initialized atom
                     */
                    initialize: function(atom:Atom):Atom {
                        return atom.setPinValue("out", false, false);
                    },
                    
                    /**
                     * Handles input pin value changes.
                     * @param {Atom} atom - Current atom state
                     * @param {String} pinName - Name of changed pin
                     * @param {*} newValue - New pin value
                     * @return {Atom} Updated atom
                     */
                    onInputChange: function(atom:Atom, pinName:String, newValue:*):Atom {
                        // Button has no inputs, so this is unused
                        return atom;
                    },
                    
                    /**
                     * Handles user interactions (clicks, presses).
                     * @param {Atom} atom - Current atom state
                     * @param {String} interactionType - Type of interaction
                     * @return {Atom} Updated atom
                     */
                    onInteraction: function(atom:Atom, interactionType:String):Atom {
                        if (interactionType == "press") {
                            return atom.setPinValue("out", true, false);
                        } else if (interactionType == "release") {
                            return atom.setPinValue("out", false, false);
                        }
                        return atom;
                    }
                },
                
                // Pin configuration
                pins: {
                    inputs: [],
                    outputs: [
                        { name: "out", type: "output" }
                    ]
                },
                
                // Visual configuration for different window contexts
                visuals: {
                    "Editor": {
                        width: 80,
                        height: 30,
                        color: 0x2ECC71,
                        cornerRadius: 5,
                        textColor: 0xFFFFFF,
                        /**
                         * Custom drawing function for Editor window
                         * @param {Graphics} graphics - Graphics object to draw on
                         * @param {Atom} atom - Atom to draw
                         * @param {Object} config - Visual configuration
                         */
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            var isPressed:Boolean = atom.getValue("isPressed") || false;
                            var color:uint = isPressed ? 0x27AE60 : config.color;
                            
                            graphics.beginFill(color);
                            graphics.drawRoundRect(0, 0, config.width, config.height, config.cornerRadius, config.cornerRadius);
                            graphics.endFill();
                        }
                    },
                    "Device": {
                        width: 60,
                        height: 25,
                        color: 0x27AE60,
                        cornerRadius: 3,
                        textColor: 0xFFFFFF,
                        /**
                         * Custom drawing function for Device window
                         * @param {Graphics} graphics - Graphics object to draw on
                         * @param {Atom} atom - Atom to draw
                         * @param {Object} config - Visual configuration
                         */
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            graphics.beginFill(config.color);
                            graphics.drawRoundRect(0, 0, config.width, config.height, config.cornerRadius, config.cornerRadius);
                            graphics.endFill();
                        }
                    },
                    "default": {
                        width: 70,
                        height: 28,
                        color: 0xCCCCCC,
                        cornerRadius: 4,
                        textColor: 0x000000
                    }
                }
            },
            
            "Counter": {
                behavior: {
                    initialize: function(atom:Atom):Atom {
                        return atom.setData("count", 0)
                                  .setPinValue("out", 0, false);
                    },
                    onInputChange: function(atom:Atom, pinName:String, newValue:*):Atom {
                        if (pinName == "in" && newValue === true) {
                            var currentCount:int = atom.getValue("count") || 0;
                            var newCount:int = currentCount + 1;
                            return atom.setData("count", newCount)
                                      .setPinValue("out", newCount, false);
                        }
                        return atom;
                    },
                    onInteraction: function(atom:Atom, interactionType:String):Atom {
                        return atom; // Counter doesn't respond to direct interactions
                    }
                },
                pins: {
                    inputs: [
                        { name: "in", type: "input" }
                    ],
                    outputs: [
                        { name: "out", type: "output" }
                    ]
                },
                visuals: {
                    "Editor": {
                        width: 100,
                        height: 50,
                        color: 0x3498DB,
                        cornerRadius: 8,
                        textColor: 0xFFFFFF,
                        draw: function(graphics:Graphics, atom:Atom, config:Object):void {
                            graphics.beginFill(config.color);
                            graphics.drawRoundRect(0, 0, config.width, config.height, config.cornerRadius, config.cornerRadius);
                            graphics.endFill();
                            
                            // Display current count
                            var count:int = atom.getValue("count") || 0;
                            graphics.beginFill(0xFFFFFF, 0.2);
                            graphics.drawRect(5, 5, config.width - 10, 20);
                            graphics.endFill();
                        }
                    }
                }
            }
            // Additional atom types can be added here...
        };

        /**
         * Retrieves the definition for a specific atom type.
         * 
         * @param {String} type - Atom type to look up
         * @return {Object} Atom definition, or default if not found
         */
        public static function getAtomDefinition(type:String):Object {
            return definitions[type] || createDefaultDefinition(type);
        }

        /**
         * Gets an array of all supported atom type names.
         * 
         * @return {Array} Array of atom type names
         */
        public static function getSupportedTypes():Array {
            var types:Array = [];
            for (var type:String in definitions) {
                types.push(type);
            }
            return types;
        }

        /**
         * Creates a default definition for unknown atom types.
         * 
         * @private
         * @param {String} type - Atom type name
         * @return {Object} Default atom definition
         */
        private static function createDefaultDefinition(type:String):Object {
            return {
                behavior: {
                    initialize: function(atom:Atom):Atom { return atom; },
                    onInputChange: function(atom:Atom, pinName:String, newValue:*):Atom { return atom; },
                    onInteraction: function(atom:Atom, interactionType:String):Atom { return atom; }
                },
                pins: {
                    inputs: [{ name: "in", type: "input" }],
                    outputs: [{ name: "out", type: "output" }]
                },
                visuals: {
                    "default": {
                        width: 60,
                        height: 40,
                        color: 0xCCCCCC,
                        textColor: 0x000000
                    }
                }
            };
        }
    }
}
