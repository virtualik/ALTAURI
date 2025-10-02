package Application.AtomLinker.Services {
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;
    import Application.AtomLinker.View.IAtomView;
    import Application.AtomLinker.View.SimpleAtomView;
    import Application.AtomLinker.View.CounterAtomView;
    import Application.AtomLinker.View.ButtonAtomView;
    import Application.AtomLinker.View.NumberDisplayAtomView;
    import flash.geom.Point;
    import flash.display.MovieClip;
    import flash.utils.Dictionary;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.AtomICScript.AtomICScriptManager;
    import Application.AtomICScript.behaviors.ButtonAtomBehavior;
    import Application.AtomICScript.behaviors.CounterAtomBehavior;
    import Application.AtomICScript.behaviors.NumberDisplayAtomBehavior;

    /**
     * Universal Atom Factory - centralized atom creation and registration management
     */
    public class AtomFactory {
        private static var _atomRegistry:Dictionary = new Dictionary();

        /**
         * Initialize atom factory
         */
        public static function initialize():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "AtomFactory",
                message: "Initializing atom factory"
            }));

            var atomICScriptManager:AtomICScriptManager = AtomICScriptManager.getInstance();
            atomICScriptManager.registerBehavior("Button", new ButtonAtomBehavior());
            atomICScriptManager.registerBehavior("Counter", new CounterAtomBehavior());
            atomICScriptManager.registerBehavior("NumberDisplay", new NumberDisplayAtomBehavior());

            registerAtomType("TestType", SimpleAtomView, "Test atom", "General");
            registerAtomType("Counter", CounterAtomView, "Counter", "Logic");
            registerAtomType("Button", ButtonAtomView, "Button", "Sources");
            registerAtomType("NumberDisplay", NumberDisplayAtomView, "Number display", "Outputs");

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "AtomFactory",
                message: "Registered atom types: " + getRegisteredTypeNames().length
            }));
        }

        /**
         * Register new atom type
         * @param atomType - atom type identifier
         * @param viewClass - view class for atom
         * @param displayName - display name for atom
         * @param category - atom category
         */
        public static function registerAtomType(atomType:String, viewClass:Class, displayName:String = null, category:String = "General"):void {
            if (!atomType || !viewClass) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "AtomFactory",
                    message: "Attempt to register invalid atom type"
                }));
                return;
            }

            _atomRegistry[atomType] = {
                viewClass: viewClass,
                displayName: displayName || atomType,
                category: category
            };
        }

        /**
         * Create atom instance
         * @param atomType - atom type to create
         * @param position - atom position
         * @param name - atom name
         * @return BaseAtom - created atom instance
         */
        public static function createAtom(atomType:String, position:Point, name:String = null):BaseAtom {
            if(!atomType || !position) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "AtomFactory",
                    message: "Invalid atom creation parameters: type=" + atomType + ", pos=" + position
                }));
                return null;
            }

            var atomInfo:Object = _atomRegistry[atomType];
            if(!atomInfo) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "AtomFactory",
                    message: "Atom type not found in registry: " + atomType
                }));
                return null;
            }

            var atomName:String = name || atomInfo.displayName;
            var atomId:String = generateId();

            try {
                var view:MovieClip = new atomInfo.viewClass();
                var inputContacts:Vector.<Pin> = new Vector.<Pin>();
                var outputContacts:Vector.<Pin> = new Vector.<Pin>();
                createPinsForAtomType(inputContacts, outputContacts, atomType);

                var atom:BaseAtom = new BaseAtom(atomId, position, atomName, atomType, inputContacts, outputContacts);
                atom.displayObject = view;
                updatePinsParentAtom(atom, inputContacts, outputContacts);

                if(view is IAtomView) {
                    IAtomView(view).initWithAtom(atom);
                } else if("setParentAtom" in view) {
                    view["setParentAtom"](atom);
                }

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "INFO",
                    source: "AtomFactory",
                    message: "Atom created: " + atom.id + " (" + atomType + ")"
                }));

                return atom;
            } catch(e:Error) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "AtomFactory",
                    message: "Error creating atom type " + atomType + ": " + e.message
                }));
                return null;
            }
            return atom;
        }

        /**
         * Update pins parent atom reference
         * @param atom - parent atom
         * @param inputPins - input pins vector
         * @param outputPins - output pins vector
         */
        private static function updatePinsParentAtom(atom:BaseAtom, inputPins:Vector.<Pin>, outputPins:Vector.<Pin>):void {
            for each (var inputPin:Pin in inputPins) {
                if (inputPin.hasOwnProperty("_parentAtom")) {
                    inputPin["_parentAtom"] = atom;
                }
            }

            for each (var outputPin:Pin in outputPins) {
                if (outputPin.hasOwnProperty("_parentAtom")) {
                    outputPin["_parentAtom"] = atom;
                }
            }
        }

        /**
         * Create and configure pins for specific atom type
         * @param inputContacts - input pins vector
         * @param outputContacts - output pins vector
         * @param type - atom type
         */
        private static function createPinsForAtomType(inputContacts:Vector.<Pin>, outputContacts:Vector.<Pin>, type:String):void {
            switch(type) {
                case "Button":
                    outputContacts.push(new Pin("out", Pin.TYPE_OUTPUT, null));
                    break;
                case "Counter":
                    inputContacts.push(new Pin("in", Pin.TYPE_INPUT, null));
                    outputContacts.push(new Pin("out", Pin.TYPE_OUTPUT, null));
                    break;
                case "NumberDisplay":
                    inputContacts.push(new Pin("in", Pin.TYPE_INPUT, null));
                    break;
                default:
                    inputContacts.push(new Pin("in", Pin.TYPE_INPUT, null));
                    outputContacts.push(new Pin("out", Pin.TYPE_OUTPUT, null));
            }
        }

        /**
         * Generate unique identifier
         * @return String - unique ID
         */
        private static function generateId():String {
            return "atom_" + new Date().getTime() + "_" + Math.round(Math.random() * 1000);
        }

        /**
         * Get view class for atom type
         * @param atomType - atom type
         * @return Class - view class
         */
        public static function getViewClassForType(atomType:String):Class {
            return _atomRegistry[atomType] ? _atomRegistry[atomType].viewClass : null;
        }

        /**
         * Get registered type names
         * @return Array - array of registered type names
         */
        public static function getRegisteredTypeNames():Array {
            var names:Array = [];
            for (var key:Object in _atomRegistry) {
                names.push(key);
            }
            return names;
        }

        /**
         * Get atom info
         * @param atomType - atom type
         * @return Object - atom information
         */
        public static function getAtomInfo(atomType:String):Object {
            return _atomRegistry[atomType];
        }

        /**
         * Get types by category
         * @param category - category name
         * @return Array - array of atom types in category
         */
        public static function getTypesByCategory(category:String):Array {
            var result:Array = [];
            for each (var atomInfo:Object in _atomRegistry) {
                if (atomInfo.category == category) {
                    result.push(atomInfo);
                }
            }
            return result;
        }
    }
}
