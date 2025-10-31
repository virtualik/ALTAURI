package Src.Prog.Core.Managers {
    import flash.utils.Dictionary;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.IAtomView;
    import flash.geom.Point;
    import Src.Prog.Core.Window;
    import flash.display.DisplayObject;
    import Src.Prog.Com.Atoms.Core.AtomFactory;

    /**
     * Manages atoms in the application - creation, deletion, and tracking.
     * Integrates with MultiPulsator for system communication.
     */
    public class AtomManager {
        private static var _instance:AtomManager;
        private var _atoms:Dictionary; // atomId -> {atom: BaseAtom, view: IAtomView}
        private var _windowAtoms:Dictionary; // windowType -> array of atomIds

        public static function getInstance():AtomManager {
            if (!_instance) {
                _instance = new AtomManager();
            }
            return _instance;
        }

        public function AtomManager() {
            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            setupImpulseListeners();
        }

        /**
         * Sets up impulse listeners for atom management.
         */
        private function setupImpulseListeners():void {
            MultiPulsator.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
        }

        /**
         * Handles atom creation from context menu selection.
         * @param impulse ATOM_CONTEXT_MENU_SELECTED impulse
         */
		private function onAtomContextMenuSelected(impulse:Impulse):void {
			var atomType:String = impulse.data.atomType;
			var position:Point = impulse.data.position;
			
			trace("AtomManager: Creating atom of type: " + atomType + " at position: " + position);
			
			// Проверка инициализации AtomFactory
			if (!DataManager.hasData(AtomFactory.REGISTRY_KEY)) {
				trace("ERROR: AtomFactory not initialized!");
				return;
			}
			
			var atomInfo:Object = AtomFactory.createAtom(atomType, position);
			if (atomInfo && atomInfo.atom && atomInfo.view) {
				addAtomToWindow("Editor", atomInfo.atom, atomInfo.view);
				trace("SUCCESS: Atom created and added to window");
			} else {
				trace("ERROR: Failed to create atom - atomInfo: " + atomInfo);
			}
		}

        /**
         * Handles atom movement updates.
         * @param impulse ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var newAtom:BaseAtom = impulse.data.newAtom;
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                // Update the view's reference to the new atom
                _atoms[newAtom.id].view.updateAtomReference(newAtom);
            }
        }

        /**
         * Handles atom deletion requests.
         * @param impulse ATOM_DELETE_REQUEST impulse
         */
        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:BaseAtom = impulse.data.atom;
            removeAtom(atom.id);
        }

        /**
         * Adds an atom to a specific window.
         * @param windowType The type of window ("Editor", "Device")
         * @param atom The atom instance
         * @param view The atom view
         */
		public function addAtomToWindow(windowType:String, atom:BaseAtom, view:IAtomView):void {
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
				
				// Установка позиции
				(view as DisplayObject).x = atom.position.x;
				(view as DisplayObject).y = atom.position.y;
				
				trace("SUCCESS: Atom view added to contentLayer at: " + atom.position);
				
				MultiPulsator.emit(new Impulse("ATOM_ADDED", {
					windowType: windowType,
					atom: atom,
					view: view
				}));
			} else {
				trace("ERROR: Window or contentLayer not found for: " + windowType);
				if (!window) trace("Window not found");
				if (window && !window.contentLayer) trace("contentLayer not found");
			}
		}

        /**
         * Removes an atom by ID.
         * @param atomId The ID of the atom to remove
         */
        public function removeAtom(atomId:String):void {
            if (_atoms[atomId]) {
                var atomData:Object = _atoms[atomId];
                
                // Remove view from display
                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view as flash.display.DisplayObject);
                }
                
                // Clean up
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
            }
        }

        /**
         * Gets all atoms for a specific window.
         * @param windowType The window type
         * @return Array of atom data objects
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
         * Updates an atom in the manager.
         * @param newAtom The updated atom instance
         */
        public function updateAtom(newAtom:BaseAtom):void {
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                _atoms[newAtom.id].view.updateAtomReference(newAtom);
            }
        }
    }
}
