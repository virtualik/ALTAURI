package Src.Prog.Core.Managers {
    import flash.utils.Dictionary;
    import flash.display.DisplayObject;
    import flash.geom.Point;
    
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Com.Atoms.Core.AtomFactory;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Manages atoms in the application using the new data-driven architecture.
     * Handles creation, deletion, and tracking of atoms and their views.
     * 
     * @class AtomManager
     * @public
     */
    public class AtomManager {
        private static var _instance:AtomManager;
        
        /** Storage for atom data: atomId -> {atom: Atom, view: AtomView} */
        private var _atoms:Dictionary;
        
        /** Window-specific atom tracking: windowType -> array of atomIds */
        private var _windowAtoms:Dictionary;

        /**
         * Gets the singleton instance of AtomManager.
         * 
         * @return {AtomManager} Singleton instance
         */
        public static function getInstance():AtomManager {
            if (!_instance) {
                _instance = new AtomManager();
            }
            return _instance;
        }

        /**
         * Creates a new AtomManager instance.
         * 
         * @constructor
         */
        public function AtomManager() {
            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            setupImpulseListeners();
        }

        /**
         * Sets up impulse listeners for atom management.
         * 
         * @private
         */
        private function setupImpulseListeners():void {
            // Atom creation and management
            MultiPulsator.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            MultiPulsator.subscribeToImpulse("ATOM_INTERACTION", onAtomInteraction);
            MultiPulsator.subscribeToImpulse("PIN_VALUE_CHANGED", onPinValueChanged);
        }

        /**
         * Handles atom creation from context menu selection.
         * 
         * @private
         * @param {Impulse} impulse - ATOM_CONTEXT_MENU_SELECTED impulse
         */
        private function onAtomContextMenuSelected(impulse:Impulse):void {
            var atomType:String = impulse.data.atomType;
            var position:Point = impulse.data.position;

            trace("AtomManager: Creating atom of type: " + atomType + " at position: " + position);

            var atomInfo:Object = AtomFactory.createAtom(atomType, position, "Editor");
            if (atomInfo && atomInfo.atom && atomInfo.view) {
                addAtomToWindow("Editor", atomInfo.atom, atomInfo.view);
                trace("SUCCESS: Atom created and added to window");
            } else {
                trace("ERROR: Failed to create atom");
                MultiPulsator.emit(new Impulse("ERROR", {
                    source: "AtomManager",
                    message: "Failed to create atom: " + atomType
                }));
            }
        }

        /**
         * Handles atom movement updates.
         * 
         * @private
         * @param {Impulse} impulse - ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var newAtom:Atom = impulse.data.newAtom;
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                // Update the view's reference to the new atom
                var view:AtomView = _atoms[newAtom.id].view;
                view.updateAtom(newAtom);
                
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "AtomManager",
                    message: "Atom moved: " + newAtom.name + " to " + newAtom.position
                }));
            }
        }

        /**
         * Handles atom interaction events (clicks, presses, etc.).
         * 
         * @private
         * @param {Impulse} impulse - ATOM_INTERACTION impulse
         */
        private function onAtomInteraction(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            var interactionType:String = impulse.data.interactionType;
            
            var definition:Object = AtomDefinitions.getAtomDefinition(atom.type);
            if (definition && definition.behavior && definition.behavior.onInteraction) {
                var newAtom:Atom = definition.behavior.onInteraction(atom, interactionType);
                updateAtom(newAtom);
                
                // Emit pin value changes if outputs were updated
                for each (var outputPin:Pin in newAtom.outputs) {
                    var oldPin:Pin = findPinByName(atom.outputs, outputPin.name);
                    if (oldPin && oldPin.value !== outputPin.value) {
                        MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
                            atomId: newAtom.id,
                            pinName: outputPin.name,
                            newValue: outputPin.value,
                            oldValue: oldPin.value
                        }));
                    }
                }
            }
        }

        /**
         * Handles pin value changes from connections.
         * 
         * @private
         * @param {Impulse} impulse - PIN_VALUE_CHANGED impulse
         */
        private function onPinValueChanged(impulse:Impulse):void {
            var atomId:String = impulse.data.atomId;
            var pinName:String = impulse.data.pinName;
            var newValue:* = impulse.data.newValue;
            
            var atomData:Object = _atoms[atomId];
            if (atomData) {
                var atom:Atom = atomData.atom;
                var definition:Object = AtomDefinitions.getAtomDefinition(atom.type);
                
                if (definition && definition.behavior && definition.behavior.onInputChange) {
                    var newAtom:Atom = definition.behavior.onInputChange(atom, pinName, newValue);
                    updateAtom(newAtom);
                    
                    // Emit output pin changes if any
                    for each (var outputPin:Pin in newAtom.outputs) {
                        var oldPin:Pin = findPinByName(atom.outputs, outputPin.name);
                        if (oldPin && oldPin.value !== outputPin.value) {
                            MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
                                atomId: newAtom.id,
                                pinName: outputPin.name,
                                newValue: outputPin.value,
                                oldValue: oldPin.value
                            }));
                        }
                    }
                }
            }
        }

        /**
         * Handles atom deletion requests.
         * 
         * @private
         * @param {Impulse} impulse - ATOM_DELETE_REQUEST impulse
         */
        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            removeAtom(atom.id);
        }

        /**
         * Adds an atom to a specific window.
         * 
         * @param {String} windowType - The type of window ("Editor", "Device")
         * @param {Atom} atom - The atom instance
         * @param {AtomView} view - The atom view
         */
        public function addAtomToWindow(windowType:String, atom:Atom, view:AtomView):void {
            trace("Adding atom to window: " + windowType + ", atom: " + atom.id);

            if (!_windowAtoms[windowType]) {
                _windowAtoms[windowType] = [];
            }

            _atoms[atom.id] = { atom: atom, view: view };
            _windowAtoms[windowType].push(atom.id);

            var windowsManager:WindowsManager = WindowsManager.getInstance();
            var window:Window = windowsManager.findWindow(windowType);

            if (window && window.contentLayer) {
                window.contentLayer.addChild(view as DisplayObject);

                // Set position from atom data
                view.x = atom.position.x;
                view.y = atom.position.y;

                trace("SUCCESS: Atom view added to contentLayer at: " + atom.position);

                MultiPulsator.emit(new Impulse("ATOM_ADDED", {
                    windowType: windowType,
                    atom: atom,
                    view: view
                }));
            } else {
                trace("ERROR: Window or contentLayer not found for: " + windowType);
            }
        }

        /**
         * Removes an atom by ID.
         * 
         * @param {String} atomId - The ID of the atom to remove
         */
        public function removeAtom(atomId:String):void {
            if (_atoms[atomId]) {
                var atomData:Object = _atoms[atomId];

                // Remove view from display
                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view as DisplayObject);
                }

                // Clean up view resources
                atomData.view.dispose();
                delete _atoms[atomId];

                // Remove from window tracking
                for (var windowType:String in _windowAtoms) {
                    var atomIds:Array = _windowAtoms[windowType];
                    var index:int = atomIds.indexOf(atomId);
                    if (index !== -1) {
                        atomIds.splice(index, 1);
                        break;
                    }
                }

                MultiPulsator.emit(new Impulse("ATOM_REMOVED", {
                    atomId: atomId
                }));

                trace("Atom removed: " + atomId);
            }
        }

        /**
         * Updates an atom in the manager and refreshes its view.
         * 
         * @param {Atom} newAtom - The updated atom instance
         */
        public function updateAtom(newAtom:Atom):void {
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                _atoms[newAtom.id].view.updateAtom(newAtom);
                
                MultiPulsator.emit(new Impulse("ATOM_UPDATED", {
                    oldAtom: _atoms[newAtom.id].atom,
                    newAtom: newAtom
                }));
            }
        }

        /**
         * Gets all atoms for a specific window.
         * 
         * @param {String} windowType - The window type
         * @return {Array} Array of atom data objects
         */
        public function getAtomsForWindow(windowType:String):Array {
            var result:Array = [];
            if (_windowAtoms[windowType]) {
                for each (var atomId:String in _windowAtoms[windowType]) {
                    if (_atoms[atomId]) {
                        result.push(_atoms[atomId]);
                    }
                }
            }
            return result;
        }

        /**
         * Finds a pin by name in a pin vector.
         * 
         * @private
         * @param {Vector.<Pin>} pins - Vector of pins to search
         * @param {String} pinName - Name of pin to find
         * @return {Pin} Found pin or null
         */
        private function findPinByName(pins:Vector.<Pin>, pinName:String):Pin {
            for each (var pin:Pin in pins) {
                if (pin.name == pinName) {
                    return pin;
                }
            }
            return null;
        }

        /**
         * Gets all registered atom types.
         * 
         * @return {Array} Array of supported atom type names
         */
        public function getSupportedAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Cleans up all resources.
         */
        public function dispose():void {
            // Remove all impulse listeners
            MultiPulsator.removeImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            MultiPulsator.removeImpulse("ATOM_INTERACTION", onAtomInteraction);
            MultiPulsator.removeImpulse("PIN_VALUE_CHANGED", onPinValueChanged);

            // Remove all atoms
            for (var atomId:String in _atoms) {
                removeAtom(atomId);
            }

            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
        }
    }
}
