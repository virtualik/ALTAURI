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
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Com.Atoms.Core.TrackRegistry;
    import Src.Prog.Core.Commands.CreateAtom;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Interaction.LinkCreator;
    import Src.Prog.Com.Atoms.Contact.View.Link;

    /**
     * Manages atoms in the application with support for both Pin and Contact systems.
     */
    public class AtomManager {

        /** Singleton instance */
        private static var _instance:AtomManager;
        /** Storage for atom data: atomId -> {atom: Atom, view: AtomView} */
        private var _atoms:Dictionary;
        /** Window-specific atom tracking: windowType -> array of atomIds */
        private var _windowAtoms:Dictionary;
        /** LinkCreator for Contact system */
        private var _linkCreator:LinkCreator;

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
         * Creates a new AtomManager instance.
         */
        public function AtomManager() {
            if (_instance) {
                throw new Error("AtomManager is a singleton. Use getInstance() instead.");
            }
            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            _linkCreator = LinkCreator.getInstance();
            setupImpulseListeners();
            
            trace("✅ AtomManager initialized with DUAL contact systems");
        }

        /**
         * Sets up impulse listeners for atom management.
         */
        private function setupImpulseListeners():void {
            // Atom creation and management
            Impulsys.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.subscribeToImpulse("ATOM_INTERACTION", onAtomInteraction);
            Impulsys.subscribeToImpulse("ATOM_VISUAL_UPDATE", onAtomVisualUpdate);
            Impulsys.subscribeToImpulse("CONTACT_CONNECTION_REQUEST", onContactConnectionRequest);
            
            trace("📡 AtomManager: Impulse listeners setup complete");
        }

        /**
         * Handles Contact connection requests.
         */
        private function onContactConnectionRequest(impulse:Impulse):void {
            var fromContact:Contact = impulse.data.fromContact;
            var toContact:Contact = impulse.data.toContact;
            
            if (fromContact && toContact) {
                trace("🔗 Contact connection request received");
                var link:Link = _linkCreator.createConnection(fromContact, toContact);
                if (link) {
                    trace("✅ Contact connection created successfully");
                } else {
                    trace("❌ Failed to create contact connection");
                }
            }
        }

        /**
         * Handles visual update request for a specific atom.
         */
        private function onAtomVisualUpdate(impulse:Impulse):void {
            var atomId:String = impulse.data.atomId;
            var atomData:Object = _atoms[atomId];
            if (atomData) {
                atomData.view.updateVisuals();
                trace("🔄 Visual update for atom: " + atomId);
            }
        }

        /**
         * Handles atom creation from context menu selection.
         */
        private function onAtomContextMenuSelected(impulse:Impulse):void {
            var atomType:String = impulse.data.atomType;
            var position:Point = impulse.data.position;
            var cmd:CreateAtom = new CreateAtom(atomType, position, "Editor");
            cmd.execute();
        }

        /**
         * Handles atom movement updates.
         */
        private function onAtomMoved(impulse:Impulse):void {
            var newAtom:Atom = impulse.data.newAtom;
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                var view:AtomView = _atoms[newAtom.id].view;
                view.updateAtom(newAtom);
                
                trace("📍 Atom moved: " + newAtom.name + " to " + newAtom.position);
                
                // Уведомляем систему об обновлении связей
                updateConnectionsForAtom(newAtom);
            }
        }

        /**
         * Обновляет связи для атома после перемещения.
         */
        private function updateConnectionsForAtom(atom:Atom):void {
            // Обновляем связи в Track системе
            var trackRegistry:TrackRegistry = TrackRegistry.getInstance();
            var connectedTracks:Vector.<Track> = trackRegistry.getTracksByAtom(atom);
            for each (var track:Track in connectedTracks) {
                track.updateVisual();
            }
            
            // TODO: Обновлять связи в Contact системе (Link)
            // Нужно будет реализовать LinkRegistry аналогично TrackRegistry
        }

        /**
         * Handles atom interaction events (press and release).
         */
        private function onAtomInteraction(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            var interactionType:String = impulse.data.interactionType;
            
            trace("🖱️ Atom interaction: " + atom.type + " - " + interactionType);

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
                    trace("❌ ERROR in atom interaction: " + error.message);
                }
            }
        }

        /**
         * Handles atom deletion requests with connected track cleanup.
         */
        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            trace("🗑️ Atom delete request for: " + atom.id);
            removeConnectedTracks(atom);
            removeConnectedLinks(atom); // Новая система
            removeAtom(atom.id);
        }

        /**
         * Remove all tracks connected to the specified atom (Pin система).
         */
        private function removeConnectedTracks(atom:Atom):void {
            var trackRegistry:TrackRegistry = TrackRegistry.getInstance();
            var connectedTracks:Vector.<Track> = trackRegistry.getTracksByAtom(atom);
            trace("🔌 Removing " + connectedTracks.length + " Pin tracks from atom: " + atom.id);
            
            for each (var track:Track in connectedTracks) {
                track.dispose();
            }
        }

        /**
         * Remove all links connected to the specified atom (Contact система).
         */
        private function removeConnectedLinks(atom:Atom):void {
            // TODO: Реализовать LinkRegistry для управления связями Contact системы
            // Пока просто освобождаем все контакты атома
            atom.disposeContacts();
            trace("🔌 Contact connections removed for atom: " + atom.id);
        }

        /**
         * Adds an atom to a specific window.
         */
        public function addAtomToWindow(windowType:String, atom:Atom, view:AtomView):void {
            trace("➕ Adding atom to window: " + windowType + ", atom: " + atom.id);

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
                
                trace("✅ Atom view added to contentLayer at: " + atom.position);

                Impulsys.emit(new Impulse("ATOM_ADDED", {
                    windowType: windowType,
                    atom: atom,
                    view: view,
                    systems: {
                        pins: atom.inputs.length + atom.outputs.length,
                        contacts: atom.contactInputs.length + atom.contactOutputs.length
                    }
                }));
            } else {
                trace("❌ ERROR: Window or contentLayer not found for: " + windowType);
            }
        }

        /**
         * Removes an atom by ID with enhanced cleanup.
         */
        public function removeAtom(atomId:String):void {
            if (_atoms[atomId]) {
                var atomData:Object = _atoms[atomId];
                trace("🗑️ Removing atom: " + atomId);

                // Remove connected tracks first (Pin система)
                removeConnectedTracks(atomData.atom);
                
                // Remove connected links (Contact система)
                removeConnectedLinks(atomData.atom);

                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view as DisplayObject);
                    trace("👁️ View removed from display");
                }

                atomData.view.dispose();
                delete _atoms[atomId];

                for (var windowType:String in _windowAtoms) {
                    var atomIds:Array = _windowAtoms[windowType];
                    var index:int = atomIds.indexOf(atomId);
                    if (index !== -1) {
                        atomIds.splice(index, 1);
                        trace("🗂️ Atom removed from window tracking: " + windowType);
                        break;
                    }
                }

                Impulsys.emit(new Impulse("ATOM_REMOVED", { 
                    atomId: atomId,
                    timestamp: new Date().getTime()
                }));
                
                trace("✅ Atom removed successfully: " + atomId);
            } else {
                trace("⚠ WARNING: Atom not found for removal: " + atomId);
            }
        }

        /**
         * Updates an atom in the manager and refreshes its view.
         */
        public function updateAtom(newAtom:Atom):void {
            trace("🔄 Updating atom: " + newAtom.id + " (" + newAtom.type + ")");

            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                _atoms[newAtom.id].view.updateAtom(newAtom);
                
                // Триггерим обновление атома
                newAtom.triggerUpdate();
                
                trace("✅ Atom updated successfully");
            } else {
                trace("⚠ WARNING: Atom not found for update: " + newAtom.id);
            }
        }

        /**
         * Creates a connection between two atoms using Contact system.
         */
        public function connectAtoms(sourceAtomId:String, targetAtomId:String, 
                                    sourceContactName:String, targetContactName:String):Boolean {
            var sourceData:Object = _atoms[sourceAtomId];
            var targetData:Object = _atoms[targetAtomId];
            
            if (!sourceData || !targetData) {
                trace("❌ Connection failed: atoms not found");
                return false;
            }
            
            var result:Boolean = sourceData.atom.connectTo(targetData.atom, sourceContactName, targetContactName);
            
            if (result) {
                trace("✅ Atoms connected: " + sourceAtomId + " → " + targetAtomId);
                Impulsys.emit(new Impulse("ATOMS_CONNECTED", {
                    sourceAtom: sourceData.atom,
                    targetAtom: targetData.atom,
                    sourceContact: sourceContactName,
                    targetContact: targetContactName,
                    timestamp: new Date().getTime()
                }));
            } else {
                trace("❌ Atoms connection failed");
            }
            
            return result;
        }

        /**
         * Gets all atoms for a specific window.
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
         * Gets atom data by ID.
         */
        public function getAtomById(atomId:String):Object {
            return _atoms[atomId];
        }

        /**
         * Gets total count of atoms in manager.
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
         */
        public function getAtomView(atom:Atom):AtomView {
            var atomData:Object = _atoms[atom.id];
            return atomData ? atomData.view : null;
        }

        /**
         * Gets all available atom definitions for menu creation.
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
                        category: definition.category || "General",
                        description: definition.description || "",
                        pins: definition.pins || []
                    });
                }
            }
            return result;
        }

        /**
         * Gets supported atom types from definitions.
         */
        public function getSupportedAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Log all atoms for debugging.
         */
        public function logAllAtoms():void {
            trace("=== ALL ATOMS (" + getAtomCount() + ") ===");
            for (var atomId:String in _atoms) {
                var atomData:Object = _atoms[atomId];
                var atom:Atom = atomData.atom;
                trace("Atom: " + atom.id);
                trace("  Type: " + atom.type + ", Name: " + atom.name);
                trace("  Position: " + atom.position);
                trace("  Pins: " + atom.inputs.length + " in, " + atom.outputs.length + " out");
                trace("  Contacts: " + atom.contactInputs.length + " in, " + atom.contactOutputs.length + " out");
                
                // Логируем информацию о контактах
                if (atom.contactOutputs.length > 0) {
                    trace("  Contact outputs:");
                    for each (var contact:Contact in atom.contactOutputs) {
                        trace("    - " + contact.name + ": value=" + contact.value + 
                              ", connected=" + contact.isConnected + 
                              ", subscribers=" + contact.subscribers.length);
                    }
                }
            }
            trace("=== END ATOMS LOG ===");
        }

        /**
         * Gets statistics about all managed atoms.
         */
        public function getStatistics():Object {
            var totalPins:int = 0;
            var totalContacts:int = 0;
            var connectedPins:int = 0;
            var connectedContacts:int = 0;
            
            for (var atomId:String in _atoms) {
                var atom:Atom = _atoms[atomId].atom;
                totalPins += atom.inputs.length + atom.outputs.length;
                totalContacts += atom.contactInputs.length + atom.contactOutputs.length;
                
                // Подсчитываем подключенные контакты
                for each (var output:Contact in atom.contactOutputs) {
                    if (output.isConnected) connectedContacts += output.subscribers.length;
                }
            }
            
            return {
                totalAtoms: getAtomCount(),
                totalPins: totalPins,
                totalContacts: totalContacts,
                connectedContacts: connectedContacts,
                windows: getWindowStats()
            };
        }

        /**
         * Gets window statistics.
         */
        private function getWindowStats():Object {
            var stats:Object = {};
            for (var windowType:String in _windowAtoms) {
                stats[windowType] = _windowAtoms[windowType].length;
            }
            return stats;
        }

        /**
         * Cleans up all resources and listeners.
         */
        public function dispose():void {
            trace("🧹 Disposing AtomManager...");
            
            // Удаляем слушатели импульсов
            Impulsys.removeImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.removeImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.removeImpulse("ATOM_INTERACTION", onAtomInteraction);
            Impulsys.removeImpulse("ATOM_VISUAL_UPDATE", onAtomVisualUpdate);
            Impulsys.removeImpulse("CONTACT_CONNECTION_REQUEST", onContactConnectionRequest);

            // Удаляем все атомы
            for (var atomId:String in _atoms) {
                removeAtom(atomId);
            }

            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            _linkCreator = null;
            _instance = null;
            
            trace("✅ AtomManager disposed");
        }
    }
}