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

    public class AtomManager {
        private static var _instance:AtomManager;
        private var _allAtoms:Array;
        private var _atomsById:Dictionary;
        private var _windowsManager:WindowsManager;

        public function AtomManager() {
            if (_instance) {
                throw new Error("AtomManager is singleton. Use getInstance() instead.");
            }

            _allAtoms = new Array();
            _atomsById = new Dictionary();
            _windowsManager = WindowsManager.getInstance();
            setupImpulseListeners();
        }

        public static function getInstance():AtomManager {
            if (!_instance) {
                _instance = new AtomManager();
            }
            return _instance;
        }

        public static function initialize():void {
            getInstance();
        }

        private function setupImpulseListeners():void {
            Impulsys.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.subscribeToImpulse("ATOM_DRAG_END", onAtomDragEnd);
            Impulsys.subscribeToImpulse("WINDOW_CREATED", onWindowCreated);
            Impulsys.subscribeToImpulse("WINDOW_CLOSED", onWindowClosed);
        }

        public function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            var creationResult:Object = AtomFactory.createAtom(type, position, windowType, name);
            if (!creationResult) {
                return null;
            }

            var atom:Atom = creationResult.atom;
            var view:AtomView = creationResult.view;

            _allAtoms.push({ atom: atom, view: view, windowType: windowType });
            _atomsById[atom.id] = { atom: atom, view: view, windowType: windowType };

            var window:Window = _windowsManager.findWindow(windowType);
            if (window && window.contentLayer) {
                window.contentLayer.addChild(view);
            }

            Impulsys.emit(new Impulse("ATOM_CREATED", {
                atom: atom,
                view: view,
                window: window,
                windowType: windowType
            }));

            return creationResult;
        }

        public function deleteAtom(atomId:String):Boolean {
            var atomData:Object = getAtomById(atomId);
            if (!atomData) {
                return false;
            }

            var atom:Atom = atomData.atom;
            var view:AtomView = atomData.view;

            atom.disposeContacts();

            var index:int = findAtomIndex(atomId);
            if (index !== -1) {
                _allAtoms.splice(index, 1);
            }
            delete _atomsById[atomId];

            if (view && view.parent) {
                view.parent.removeChild(view);
                view.dispose();
            }

            Impulsys.emit(new Impulse("ATOM_DELETED", {
                atom: atom,
                atomId: atomId
            }));

            return true;
        }

        public function updateAtom(updatedAtom:Atom):void {
            if (!updatedAtom) {
                return;
            }

            var atomData:Object = getAtomById(updatedAtom.id);
            if (!atomData) {
                return;
            }

            var oldAtom:Atom = atomData.atom;
            var view:AtomView = atomData.view;

            _atomsById[updatedAtom.id] = { atom: updatedAtom, view: view, windowType: atomData.windowType };

            if (view) {
                view.updateAtom(updatedAtom);
            }

            Impulsys.emit(new Impulse("ATOM_UPDATED", {
                oldAtom: oldAtom,
                newAtom: updatedAtom,
                view: view,
                updateLinks: true
            }));
        }

        public function updateAtomPosition(atomId:String, newPosition:Point):void {
            var atomData:Object = getAtomById(atomId);
            if (!atomData || !atomData.atom) return;

            var oldAtom:Atom = atomData.atom;
            var newAtom:Atom = oldAtom.setPosition(newPosition);

            atomData.atom = newAtom;
            _atomsById[atomId] = atomData;

            if (atomData.view) {
                atomData.view.updateAtom(newAtom);
            }

            updateLinksForAtom(atomId);
        }

		private function updateLinksForAtom(atomId:String):void {
			var linkRegistry:LinkRegistry = LinkRegistry.getInstance();
			if (!linkRegistry) return;

			var links:Array = linkRegistry.getLinksByAtom(atomId);
			for each (var link:Link in links) {
				if (link && link.updateVisual is Function) {
					link.updateVisual();
				}
			}
        }

        public function getAtomsForWindow(windowType:String):Array {
            var result:Array = new Array();

            for each (var atomData:Object in _allAtoms) {
                if (atomData.windowType == windowType) {
                    result.push(atomData);
                }
            }

            return result;
        }

        public function getAtomById(atomId:String):Object {
            return _atomsById[atomId] as Object;
        }

        public function getAtomView(atom:Atom):AtomView {
            var data:Object = getAtomById(atom.id);
            return data ? data.view : null;
        }

        private function findAtomIndex(atomId:String):int {
            for (var i:int = 0; i < _allAtoms.length; i++) {
                if (_allAtoms[i].atom.id == atomId) {
                    return i;
                }
            }
            return -1;
        }

        private function onAtomContextMenuSelected(impulse:Impulse):void {
            var atomType:String = impulse.data.atomType;
            var position:Point = impulse.data.position;

            if (atomType && position) {
                createAtom(atomType, position, "Editor");
            }
        }

        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            if (atom) {
                deleteAtom(atom.id);
            }
        }

        private function onAtomMoved(impulse:Impulse):void {
            var newAtom:Atom = impulse.data.newAtom;
            var updateLinks:Boolean = impulse.data.updateLinks !== false;

            if (newAtom && updateLinks) {
                updateAtomPosition(newAtom.id, newAtom.position);
            }
        }

        private function onAtomDragEnd(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            if (atom) {
                updateAtomPosition(atom.id, atom.position);
            }
        }

        private function onWindowCreated(impulse:Impulse):void {
        }

        private function onWindowClosed(impulse:Impulse):void {
        }

        public function getActiveContactCount(windowType:String):Object {
            var window:Window = _windowsManager.findWindow(windowType);
            if (!window) return { active: 0, total: 0 };

            var atoms:Array = getAtomsForWindow(windowType);
            var activeContacts:int = 0;
            var totalContacts:int = 0;

            for each (var atomData:Object in atoms) {
                var atom:Atom = atomData.atom;
                if (atom) {
                    totalContacts += atom.contactInputs.length + atom.contactOutputs.length;

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

        public function getDebugInfo():Object {
            var contactStats:Object = getContactStats();

            return {
                totalAtoms: _allAtoms.length,
                contactStats: contactStats,
                atomsByWindow: getAtomsByWindowStats(),
                registrySize: Object(_atomsById).length
            };
        }

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

        public function clearAll():void {
            for each (var atomData:Object in _allAtoms) {
                if (atomData.atom) {
                    atomData.atom.disposeContacts();
                }
                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view);
                    atomData.view.dispose();
                }
            }

            _allAtoms = new Array();
            _atomsById = new Dictionary();
        }

        public function dispose():void {
            clearAll();

            Impulsys.removeImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            Impulsys.removeImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.removeImpulse("ATOM_DRAG_END", onAtomDragEnd);
            Impulsys.removeImpulse("WINDOW_CREATED", onWindowCreated);
            Impulsys.removeImpulse("WINDOW_CLOSED", onWindowClosed);

            _instance = null;
        }
    }
}
