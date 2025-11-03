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
    import Src.Prog.Com.Atoms.Core.TrackManager;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Core.Commands.CreateAtom;

    /**
     * Manages atoms in the application using the new data-driven architecture.
     * Handles creation, deletion, and tracking of atoms and their views.
     * Enhanced with atom deletion functionality and track cleanup.
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
         * Enhanced with atom deletion and track cleanup.
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
            MultiPulsator.subscribeToImpulse("ATOM_VISUAL_UPDATE", onAtomVisualUpdate);
		}

		private function onAtomVisualUpdate(impulse:Impulse):void {
			var atomId:String = impulse.data.atomId;
			var atomData:Object = _atoms[atomId];
			
			if (atomData) {
				// Принудительно обновляем визуальное представление
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
			cmd.execute(); // или через SerialCommand, если нужно в цепочку
		}

		// Добавить метод для получения поддерживаемых типов:
		public function getSupportedAtomTypes():Array {
			return AtomDefinitions.getSupportedTypes();
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
			var view:AtomView = impulse.data.view;

			trace("=== ATOM INTERACTION ===");
			trace("Atom: " + atom.type + " (" + atom.id + ")");
			trace("Interaction type: " + interactionType);

			var definition:Object = AtomDefinitions.getAtomDefinition(atom.type);
			
			if (definition && definition.behavior) {
				try {
					var newAtom:Atom = atom;
					
					// Обработка левого клика
					if (interactionType == "press" && definition.behavior.onInteraction) {
						newAtom = definition.behavior.onInteraction(atom, interactionType);
					}
					
					// Обработка правого клика  
					else if (interactionType == "rightClick" && definition.behavior.onRightClick) {
						newAtom = definition.behavior.onRightClick(atom);
					}
					
					// Обновляем атом в менеджере
					if (newAtom !== atom) {
						updateAtom(newAtom);
						
						// Эмитим изменения значений пинов
						for each (var outputPin:Pin in newAtom.outputs) {
							var oldPin:Pin = findPinByName(atom.outputs, outputPin.name);
							if (oldPin && oldPin.value !== outputPin.value) {
								MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
									atomId: newAtom.id,
									pinName: outputPin.name,
									newValue: outputPin.value,
									oldValue: oldPin.value,
									source: "interaction"
								}));
							}
						}
					}
					
				} catch (error:Error) {
					trace("ERROR in atom interaction: " + error.message);
				}
			}
			
			trace("=== END INTERACTION ===");
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
			var source:String = impulse.data.source || "unknown";

			trace("=== PIN_VALUE_CHANGED HANDLER ===");
			trace("Source: " + source);
			trace("Atom: " + atomId + ", Pin: " + pinName + ", Value: " + newValue);

			var atomData:Object = _atoms[atomId];
			if (atomData) {
				var atom:Atom = atomData.atom;
				var definition:Object = AtomDefinitions.getAtomDefinition(atom.type);

				trace("Atom type: " + atom.type + ", has onInputChange: " + 
					  (definition && definition.behavior && definition.behavior.onInputChange));

				// Для входных пинов вызываем onInputChange
				var targetPin:Pin = findPinByName(atom.inputs, pinName);
				if (targetPin && definition && definition.behavior && definition.behavior.onInputChange) {
					trace("Calling onInputChange for " + atom.type);
					var newAtom:Atom = definition.behavior.onInputChange(atom, pinName, newValue);
					updateAtom(newAtom);
				} else {
					trace("No onInputChange call needed for " + atom.type + " (not an input pin or no behavior)");
				}
			} else {
				trace("Atom data not found for: " + atomId);
			}
			
			trace("=== END PIN_VALUE_CHANGED HANDLER ===");
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
            
            // Remove all tracks connected to this atom first
            removeConnectedTracks(atom);
            
            // Then remove the atom
            removeAtom(atom.id);
        }

        /**
         * Remove all tracks connected to the specified atom
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

				// НЕМЕДЛЕННОЕ ОБНОВЛЕНИЕ ВИЗУАЛИЗАЦИИ
				view.updateVisuals();

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
         * Removes an atom by ID with enhanced cleanup.
         *
         * @param {String} atomId - The ID of the atom to remove
         */
        public function removeAtom(atomId:String):void {
            if (_atoms[atomId]) {
                var atomData:Object = _atoms[atomId];
                trace("AtomManager: Removing atom: " + atomId);

                // Remove view from display
                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view as DisplayObject);
                    trace("AtomManager: View removed from display");
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
                        trace("AtomManager: Atom removed from window tracking: " + windowType);
                        break;
                    }
                }

                MultiPulsator.emit(new Impulse("ATOM_REMOVED", {
                    atomId: atomId
                }));

                trace("AtomManager: Atom removed successfully: " + atomId);
            } else {
                trace("AtomManager: Atom not found for removal: " + atomId);
            }
        }

        /**
         * Updates an atom in the manager and refreshes its view.
         *
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

				MultiPulsator.emit(new Impulse("ATOM_UPDATED", {
					oldAtom: _atoms[newAtom.id].atom,
					newAtom: newAtom
				}));
			} else {
				trace("WARNING: Atom not found for update: " + newAtom.id);
			}
			
			trace("=== END ATOM MANAGER UPDATE ===");
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
         * Gets atom data by ID.
         *
         * @param {String} atomId - The atom ID to find
         * @return {Object} Atom data object or null if not found
         */
        public function getAtomById(atomId:String):Object {
            return _atoms[atomId];
        }

        /**
         * Gets total count of atoms in manager.
         *
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
         * Log all atoms for debugging.
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
