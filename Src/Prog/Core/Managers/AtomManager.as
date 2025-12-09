package Src.Prog.Core.Managers {
    import flash.geom.Point;
    import flash.utils.Dictionary;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Com.Atoms.Core.AtomFactory;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Core.Managers.WindowsManager;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
	import Src.Prog.Com.Atoms.Contact.View.Link;
    import Src.Prog.Com.Atoms.Contact.Core.LinkRegistry;

    /**
     * Centralized manager for all atoms in the application.
     * Manages atom lifecycle, state updates, and cross-window coordination.
     * Updated for Contact-only system (Pin system removed).
     */
    public class AtomManager {
        
        /** Singleton instance reference */
        private static var _instance:AtomManager;
        
        /** Collection of all atoms in the system */
        private var _allAtoms:Array;
        /** Fast lookup dictionary for atoms by ID */
        private var _atomsById:Dictionary;
        /** Windows manager for window operations */
        private var _windowsManager:WindowsManager;

        /**
         * Private constructor for singleton pattern.
         */
        public function AtomManager() {
            if (_instance) {
                throw new Error("AtomManager is singleton. Use getInstance() instead.");
            }
            
            _allAtoms = new Array();
            _atomsById = new Dictionary();
            _windowsManager = WindowsManager.getInstance();
            
            setupImpulseListeners();
            
            trace("✅ AtomManager: Initialized for Contact-only system");
        }

        /**
         * Gets the singleton instance of AtomManager.
         */
        public static function getInstance():AtomManager {
            if (!_instance) {
                _instance = new AtomManager();
            }
            return _instance;
        }

        /**
         * Initializes the AtomManager system.
         */
        public static function initialize():void {
            getInstance();
        }

        /**
         * Sets up impulse listeners for atom lifecycle management.
         */
        private function setupImpulseListeners():void {
            // Atom creation and deletion
            Impulsys.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            
            // Atom movement and updates
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.subscribeToImpulse("ATOM_DRAG_END", onAtomDragEnd);
            
            // Window management
            Impulsys.subscribeToImpulse("WINDOW_CREATED", onWindowCreated);
            Impulsys.subscribeToImpulse("WINDOW_CLOSED", onWindowClosed);
        }

        // =========================================================================
        // ATOM LIFECYCLE MANAGEMENT
        // =========================================================================

        /**
         * Creates a new atom at the specified position.
         */
        public function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            trace("AtomManager: Creating atom - " + type + " at " + position);
            
            var creationResult:Object = AtomFactory.createAtom(type, position, windowType, name);
            if (!creationResult) {
                trace("AtomManager: ERROR - Atom creation failed for type: " + type);
                return null;
            }
            
            var atom:Atom = creationResult.atom;
            var view:AtomView = creationResult.view;
            
            // Register atom
            _allAtoms.push({ atom: atom, view: view, windowType: windowType });
            _atomsById[atom.id] = { atom: atom, view: view, windowType: windowType };
            
            // Add to appropriate window
            var window:Window = _windowsManager.findWindow(windowType);
            if (window && window.contentLayer) {
                window.contentLayer.addChild(view);
                trace("AtomManager: Atom view added to window: " + windowType);
            }
            
            // Emit creation event
            Impulsys.emit(new Impulse("ATOM_CREATED", {
                atom: atom,
                view: view,
                window: window,
                windowType: windowType
            }));
            
            trace("AtomManager: Atom created successfully - " + atom.name + " (" + atom.id + ")");
            return creationResult;
        }

        /**
         * Deletes an atom and all its associated resources.
         */
        public function deleteAtom(atomId:String):Boolean {
            trace("AtomManager: Deleting atom - " + atomId);
            
            var atomData:Object = getAtomById(atomId);
            if (!atomData) {
                trace("AtomManager: Atom not found for deletion: " + atomId);
                return false;
            }
            
            var atom:Atom = atomData.atom;
            var view:AtomView = atomData.view;
            
            // Dispose atom contacts (this will also disconnect all Links)
            atom.disposeContacts();
            
            // Remove from registry
            var index:int = findAtomIndex(atomId);
            if (index !== -1) {
                _allAtoms.splice(index, 1);
            }
            delete _atomsById[atomId];
            
            // Remove view from display
            if (view && view.parent) {
                view.parent.removeChild(view);
                view.dispose();
            }
            
            // Emit deletion event
            Impulsys.emit(new Impulse("ATOM_DELETED", {
                atom: atom,
                atomId: atomId
            }));
            
            trace("AtomManager: Atom deleted successfully - " + atom.name + " (" + atomId + ")");
            return true;
        }

        // =========================================================================
        // ATOM STATE MANAGEMENT
        // =========================================================================

        /**
         * Updates an atom in the system.
         * For Contact system - Links update automatically through Contact.notifySubscribers()
         */
        public function updateAtom(updatedAtom:Atom):void {
            if (!updatedAtom) {
                trace("AtomManager: Cannot update null atom");
                return;
            }

            var atomData:Object = getAtomById(updatedAtom.id);
            if (!atomData) {
                trace("AtomManager: Atom not found for update: " + updatedAtom.id);
                return;
            }

            var oldAtom:Atom = atomData.atom;
            var view:AtomView = atomData.view;

            // Update registry
            _atomsById[updatedAtom.id] = { atom: updatedAtom, view: view, windowType: atomData.windowType };

            // Update view
            if (view) {
                view.updateAtom(updatedAtom);
            }

            // 🔥 ВАЖНО: Для Contact системы Links обновляются автоматически
            // через Contact.notifySubscribers() при изменении значения

            // Emit update event
            Impulsys.emit(new Impulse("ATOM_UPDATED", {
                oldAtom: oldAtom,
                newAtom: updatedAtom,
                view: view,
                updateLinks: true // Contact система сама обновит Links
            }));

            trace("AtomManager: Atom updated - " + updatedAtom.name + " (" + updatedAtom.id + ")");
        }

        /**
         * Updates atom position and handles visual updates.
         */
        public function updateAtomPosition(atomId:String, newPosition:Point):void {
            var atomData:Object = getAtomById(atomId);
            if (!atomData || !atomData.atom) return;
            
            var oldAtom:Atom = atomData.atom;
            var newAtom:Atom = oldAtom.setPosition(newPosition);
            
            // Update in registry
            atomData.atom = newAtom;
            _atomsById[atomId] = atomData;
            
            // Update view position
            if (atomData.view) {
                atomData.view.updateAtom(newAtom);
            }
            
            // Update all Links connected to this atom
            updateLinksForAtom(atomId);
            
            trace("AtomManager: Atom position updated - " + newAtom.name + " to " + newPosition);
        }

		/**
		 * Updates all Links connected to an atom.
		 */
		private function updateLinksForAtom(atomId:String):void {
			var linkRegistry:LinkRegistry = LinkRegistry.getInstance();
			if (!linkRegistry) return;
			
			// 🔥 ИСПРАВЛЕНО: Теперь getLinksByAtom возвращает Array
			var links:Array = linkRegistry.getLinksByAtom(atomId);
			for each (var link:Link in links) {
				if (link && link.updateVisual is Function) {
					link.updateVisual();
				}
			}
}

        // =========================================================================
        // ATOM QUERY AND RETRIEVAL
        // =========================================================================

        /**
         * Gets all atoms for a specific window type.
         */
        public function getAtomsForWindow(windowType:String):Array {
            var result:Array = new Array();
            
            for each (var atomData:Object in _allAtoms) {
                if (atomData.windowType == windowType) {
                    result.push(atomData);
                }
            }
            
            return result;
        }

        /**
         * Gets an atom by its ID.
         */
        public function getAtomById(atomId:String):Object {
            return _atomsById[atomId] as Object;
        }

        /**
         * Gets the atom view for a specific atom.
         */
        public function getAtomView(atom:Atom):AtomView {
            var data:Object = getAtomById(atom.id);
            return data ? data.view : null;
        }

        /**
         * Finds the index of an atom in the _allAtoms array.
         */
        private function findAtomIndex(atomId:String):int {
            for (var i:int = 0; i < _allAtoms.length; i++) {
                if (_allAtoms[i].atom.id == atomId) {
                    return i;
                }
            }
            return -1;
        }

        // =========================================================================
        // IMPULSE HANDLERS
        // =========================================================================

        /**
         * Handles atom creation from context menu.
         */
        private function onAtomContextMenuSelected(impulse:Impulse):void {
            var atomType:String = impulse.data.atomType;
            var position:Point = impulse.data.position;
            
            if (atomType && position) {
                createAtom(atomType, position, "Editor");
            }
        }

        /**
         * Handles atom deletion requests.
         */
        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            if (atom) {
                deleteAtom(atom.id);
            }
        }

        /**
         * Handles atom movement events.
         */
        private function onAtomMoved(impulse:Impulse):void {
            var newAtom:Atom = impulse.data.newAtom;
            var updateLinks:Boolean = impulse.data.updateLinks !== false;
            
            if (newAtom && updateLinks) {
                updateAtomPosition(newAtom.id, newAtom.position);
            }
        }

        /**
         * Handles atom drag end events.
         */
        private function onAtomDragEnd(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            if (atom) {
                updateAtomPosition(atom.id, atom.position);
            }
        }

        /**
         * Handles window creation events.
         */
        private function onWindowCreated(impulse:Impulse):void {
            var window:Window = impulse.data.window;
            trace("AtomManager: Window created - " + (window ? window.windowType : "unknown"));
        }

        /**
         * Handles window closure events.
         */
        private function onWindowClosed(impulse:Impulse):void {
            var window:Window = impulse.data.window;
            if (window) {
                trace("AtomManager: Window closed - " + window.windowType);
                // Note: Atoms are automatically disposed when window closes
                // because views are removed from display list
            }
        }

        // =========================================================================
        // STATISTICS AND DEBUG INFORMATION
        // =========================================================================

        /**
         * Gets the active contact count for a window.
         * Replaces old getActivePinCount() method.
         */
        public function getActiveContactCount(windowType:String):Object {
            var window:Window = _windowsManager.findWindow(windowType);
            if (!window) return { active: 0, total: 0 };
            
            var atoms:Array = getAtomsForWindow(windowType);
            var activeContacts:int = 0;
            var totalContacts:int = 0;
            
            for each (var atomData:Object in atoms) {
                var atom:Atom = atomData.atom;
                if (atom) {
                    // 🔥 ИСПРАВЛЕНО: Используем contactInputs/contactOutputs вместо inputs/outputs
                    totalContacts += atom.contactInputs.length + atom.contactOutputs.length;
                    
                    // Считаем активные контакты (подключенные)
                    for each (var input:Contact in atom.contactInputs) {
                        if (input.isConnected) activeContacts++;
                    }
                    for each (var output:Contact in atom.contactOutputs) {
                        if (output.isConnected) activeContacts++;
                    }
                }
            }
            
            return { active: activeContacts, total: totalContacts };
        }

        /**
         * Gets contact statistics for the entire system.
         */
        public function getContactStats():Object {
            var totalContacts:int = 0;
            var connectedContacts:int = 0;
            var totalConnections:int = 0;
            
            for each (var atomData:Object in _allAtoms) {
                var atom:Atom = atomData.atom;
                if (atom) {
                    for each (var input:Contact in atom.contactInputs) {
                        totalContacts++;
                        if (input.isConnected) connectedContacts++;
                    }
                    for each (var output:Contact in atom.contactOutputs) {
                        totalContacts++;
                        if (output.isConnected) {
                            connectedContacts++;
                            totalConnections += output.subscribers.length;
                        }
                    }
                }
            }
            
            return {
                totalContacts: totalContacts,
                connectedContacts: connectedContacts,
                totalConnections: totalConnections,
                connectionDensity: totalContacts > 0 ? (connectedContacts / totalContacts).toFixed(2) : "0.00"
            };
        }

        /**
         * Gets debug info for all atoms.
         */
        public function getDebugInfo():Object {
            var contactStats:Object = getContactStats();
            
            return {
                totalAtoms: _allAtoms.length,
                contactStats: contactStats,
                atomsByWindow: getAtomsByWindowStats(),
                registrySize: Object(_atomsById).length
            };
        }

        /**
         * Gets atom statistics by window.
         */
        private function getAtomsByWindowStats():Object {
            var stats:Object = {};
            
            for each (var atomData:Object in _allAtoms) {
                var windowType:String = atomData.windowType;
                if (!stats[windowType]) {
                    stats[windowType] = { count: 0, contacts: 0 };
                }
                stats[windowType].count++;
                
                var atom:Atom = atomData.atom;
                if (atom) {
                    stats[windowType].contacts += atom.contactInputs.length + atom.contactOutputs.length;
                }
            }
            
            return stats;
        }

        /**
         * Validates atom integrity in the system.
         */
        public function validateAtoms():Object {
            var errors:Array = new Array();
            var warnings:Array = new Array();
            
            for each (var atomData:Object in _allAtoms) {
                var atom:Atom = atomData.atom;
                var view:AtomView = atomData.view;
                
                if (!atom) {
                    errors.push("Null atom in registry");
                    continue;
                }
                
                if (!view) {
                    warnings.push("Atom '" + atom.name + "' has no view");
                }
                
                if (atom.position.x < 0 || atom.position.y < 0) {
                    warnings.push("Atom '" + atom.name + "' has negative position: " + atom.position);
                }
                
                // Проверяем контакты
                for each (var contact:Contact in atom.getAllContacts()) {
                    if (!contact.atom || contact.atom.id !== atom.id) {
                        errors.push("Contact '" + contact.name + "' has wrong owner atom");
                    }
                }
            }
            
            return {
                valid: errors.length === 0,
                errors: errors,
                warnings: warnings,
                atomCount: _allAtoms.length
            };
        }

        // =========================================================================
        // SYSTEM MAINTENANCE AND CLEANUP
        // =========================================================================

        /**
         * Clears all atoms from the system (for testing).
         */
        public function clearAll():void {
            trace("AtomManager: Clearing all atoms...");
            
            // Dispose all atoms
            for each (var atomData:Object in _allAtoms) {
                if (atomData.atom) {
                    atomData.atom.disposeContacts();
                }
                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view);
                    atomData.view.dispose();
                }
            }
            
            // Clear registries
            _allAtoms = new Array();
            _atomsById = new Dictionary();
            
            trace("AtomManager: All atoms cleared");
        }

        /**
         * Disposes the AtomManager and all its resources.
         */
        public function dispose():void {
            trace("AtomManager: Disposing...");
            
            clearAll();
            
            // Unsubscribe from impulses
            Impulsys.removeImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.removeImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.removeImpulse("ATOM_DRAG_END", onAtomDragEnd);
            Impulsys.removeImpulse("WINDOW_CREATED", onWindowCreated);
            Impulsys.removeImpulse("WINDOW_CLOSED", onWindowClosed);
            
            _instance = null;
            trace("AtomManager: Disposed");
        }
    }
}