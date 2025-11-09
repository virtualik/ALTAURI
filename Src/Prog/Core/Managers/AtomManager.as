package Src.Prog.Core.Managers {

    import flash.utils.Dictionary;
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Com.Atoms.Core.AtomFactory;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Atoms.Core.TrackManager;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Core.Commands.CreateAtom;

    /**
     * Manages atoms in the application using the new data-driven architecture.
     * Enhanced with support for button release interactions.
     * FIXED: PIN_VALUE_CHANGED handler now properly processes target atoms.
     * Uses singleton pattern with full lifecycle management.
     *
     * @class AtomManager
     * @singleton
     * @public
     */
    public class AtomManager {

        /** Singleton instance */
        private static var _instance:AtomManager;

        /** Storage for atom data: atomId -> {atom: Atom, view: AtomView} */
        private var _atoms:Dictionary;

        /** Window-specific atom tracking: windowType -> array of atomIds */
        private var _windowAtoms:Dictionary;

        /**
         * Gets the singleton instance of AtomManager.
         *
         * @static
         * @public
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
         * Private constructor to enforce singleton pattern.
         *
         * @constructor
         * @private
         */
        public function AtomManager() {
            if (_instance) {
                throw new Error("AtomManager is a singleton. Use getInstance() instead.");
            }
            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            setupImpulseListeners();
        }

        /**
         * Sets up impulse listeners for atom management.
         * Enhanced with support for release interactions.
         *
         * @private
         */
        private function setupImpulseListeners():void {
            // Atom creation and management
            Impulsys.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.subscribeToImpulse("ATOM_INTERACTION", onAtomInteraction);
            Impulsys.subscribeToImpulse("ATOM_VISUAL_UPDATE", onAtomVisualUpdate);
        }

        /**
         * Handles visual update request for a specific atom.
         *
         * @private
         * @param {Impulse} impulse - ATOM_VISUAL_UPDATE impulse
         */
        private function onAtomVisualUpdate(impulse:Impulse):void {
            var atomId:String = impulse.data.atomId;
            var atomData:Object = _atoms[atomId];
            if (atomData) {
                atomData.view.updateVisuals();
                trace("Visual update for atom: " + atomId);
            }
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
            var cmd:CreateAtom = new CreateAtom(atomType, position, "Editor");
            cmd.execute();
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
                var view:AtomView = _atoms[newAtom.id].view;
                view.updateAtom(newAtom);
                Impulsys.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "AtomManager",
                    message: "Atom moved: " + newAtom.name + " to " + newAtom.position
                }));
            }
        }

        /**
         * Handles atom interaction events (press and release).
         * Enhanced to support release interactions.
         *
         * @private
         * @param {Impulse} impulse - ATOM_INTERACTION impulse
         */
        private function onAtomInteraction(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            var interactionType:String = impulse.data.interactionType;
            var view:AtomView = impulse.data.view;
            trace("=== ATOM INTERACTION ===");
            trace("Atom: " + atom.type + " (" + atom.id + ")");
            trace("Interaction type: " + interactionType);

            var definition:Object = AtomDefinitions.getAtomDefinition(atom.type);
            if (definition && definition.behavior) {
                try {
                    var newAtom:Atom = atom;

                    if (interactionType == "press" && definition.behavior.onInteraction) {
                        newAtom = definition.behavior.onInteraction(atom, interactionType);
                    }
                    else if (interactionType == "release" && definition.behavior.onRelease) {
                        newAtom = definition.behavior.onRelease(atom);
                    }

                    if (newAtom !== atom) {
                        updateAtom(newAtom);
					}
                } catch (error:Error) {
                    trace("ERROR in atom interaction: " + error.message);
                }
            }
            trace("=== END INTERACTION ===");
        }

        /**
         * Handles atom deletion requests with connected track cleanup.
         *
         * @private
         * @param {Impulse} impulse - ATOM_DELETE_REQUEST impulse
         */
        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            trace("AtomManager: Received atom delete request for: " + atom.id);
            removeConnectedTracks(atom);
            removeAtom(atom.id);
        }

        /**
         * Remove all tracks connected to the specified atom.
         *
         * @private
         * @param {Atom} atom - Atom to remove tracks for
         */
        private function removeConnectedTracks(atom:Atom):void {
            var trackManager:TrackManager = TrackManager.getInstance();
            var connectedTracks:Array = trackManager.getTracksByAtom(atom.id);
            trace("AtomManager: Removing " + connectedTracks.length + " tracks connected to atom: " + atom.id);
            for each (var track:Track in connectedTracks) {
                trackManager.removeTrack(track);
            }
        }

        /**
         * Adds an atom to a specific window.
         *
         * @public
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
                view.x = atom.position.x;
                view.y = atom.position.y;
                view.updateVisuals();
                trace("SUCCESS: Atom view added to contentLayer at: " + atom.position);

                Impulsys.emit(new Impulse("ATOM_ADDED", {
                    windowType: windowType,
                    atom: atom,
                    view: view
                }));
            } else {
                trace("ERROR: Window or contentLayer not found for: " + windowType);
            }
        }

        /**
         * Removes an atom by ID with enhanced cleanup.
         *
         * @public
         * @param {String} atomId - The ID of the atom to remove
         */
        public function removeAtom(atomId:String):void {
            if (_atoms[atomId]) {
                var atomData:Object = _atoms[atomId];
                trace("AtomManager: Removing atom: " + atomId);

                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view as DisplayObject);
                    trace("AtomManager: View removed from display");
                }

                atomData.view.dispose();
                delete _atoms[atomId];

                for (var windowType:String in _windowAtoms) {
                    var atomIds:Array = _windowAtoms[windowType];
                    var index:int = atomIds.indexOf(atomId);
                    if (index !== -1) {
                        atomIds.splice(index, 1);
                        trace("AtomManager: Atom removed from window tracking: " + windowType);
                        break;
                    }
                }

                Impulsys.emit(new Impulse("ATOM_REMOVED", { atomId: atomId }));
                trace("AtomManager: Atom removed successfully: " + atomId);
            } else {
                trace("AtomManager: Atom not found for removal: " + atomId);
            }
        }

        /**
         * Updates an atom in the manager and refreshes its view.
         *
         * @public
         * @param {Atom} newAtom - The updated atom instance
         */
        public function updateAtom(newAtom:Atom):void {
            trace("=== ATOM MANAGER UPDATE ATOM ===");
            trace("Updating atom: " + newAtom.id + " (" + newAtom.type + ")");


            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                trace("Calling view.updateAtom()");
                _atoms[newAtom.id].view.updateAtom(newAtom);
                trace("View update completed");
            } else {
                trace("WARNING: Atom not found for update: " + newAtom.id);
            }
            trace("=== END ATOM MANAGER UPDATE ===");
        }

        /**
         * Gets all atoms for a specific window.
         *
         * @public
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
         * Gets atom data by ID.
         *
         * @public
         * @param {String} atomId - The atom ID to find
         * @return {Object} Atom data object or null if not found
         */
        public function getAtomById(atomId:String):Object {
            return _atoms[atomId];
        }

        /**
         * Gets total count of atoms in manager.
         *
         * @public
         * @return {int} Number of atoms
         */
        public function getAtomCount():int {
            var count:int = 0;
            for (var key:String in _atoms) {
                count++;
            }
            return count;
        }

        /**
         * Gets the AtomView for a given Atom instance.
         *
         * @public
         * @param {Atom} atom - Atom to find view for
         * @return {AtomView} Found AtomView or null if not found
         */
        public function getAtomView(atom:Atom):AtomView {
            var atomData:Object = _atoms[atom.id];
            return atomData ? atomData.view : null;
        }

        /**
         * Gets all available atom definitions for menu creation.
         *
         * @public
         * @return {Array} Array of atom definition objects with type, name, and category
         */
        public function getAtomDefinitionsForMenu():Array {
            var result:Array = [];
            var supportedTypes:Array = getSupportedAtomTypes();
            for each (var atomType:String in supportedTypes) {
                var definition:Object = AtomDefinitions.getAtomDefinition(atomType);
                if (definition) {
                    result.push({
                        type: atomType,
                        name: definition.displayName || atomType,
                        category: definition.category || "General"
                    });
                }
            }
            return result;
        }

        /**
         * Gets supported atom types from definitions.
         *
         * @public
         * @return {Array} Array of supported atom type strings
         */
        public function getSupportedAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Log all atoms for debugging.
         *
         * @public
         */
        public function logAllAtoms():void {
            trace("=== ALL ATOMS ===");
            for (var atomId:String in _atoms) {
                var atomData:Object = _atoms[atomId];
                trace("Atom: " + atomId + ", Type: " + atomData.atom.type + ", Position: " + atomData.atom.position);
            }
            trace("=== END ATOMS LOG ===");
        }

        /**
         * Cleans up all resources and listeners.
         *
         * @public
         */
        public function dispose():void {
            Impulsys.removeImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.removeImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.removeImpulse("ATOM_INTERACTION", onAtomInteraction);
            Impulsys.removeImpulse("ATOM_VISUAL_UPDATE", onAtomVisualUpdate);

            for (var atomId:String in _atoms) {
                removeAtom(atomId);
            }

            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            _instance = null;
        }
    }
}
