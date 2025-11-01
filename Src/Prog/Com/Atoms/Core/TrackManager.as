package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Core.Managers.WindowsManager;
    import Src.Prog.Core.Managers.AtomManager;

    /**
     * TrackManager - Centralized manager for track creation and lifecycle management.
     * Updated for data-driven architecture to work with Atom and Pin classes.
     *
     * @class TrackManager
     * @public
     */
    public class TrackManager {
        /** Singleton instance */
        private static var _instance:TrackManager;

        /** Active tracks storage */
        private var _activeTracks:Object;

        /** Temporary track during drag operations */
        private var _tempTrack:Sprite;

        /** Currently dragging pin reference */
        private var _currentDragPin:Pin;

        /** Current window context */
        private var _currentWindow:Window;

        /**
         * Private constructor for singleton pattern
         */
        public function TrackManager() {
            _activeTracks = {};
            setupImpulseListeners();
        }

        /**
         * Get singleton instance
         * @return {TrackManager} TrackManager singleton instance
         */
        public static function getInstance():TrackManager {
            if (!_instance) {
                _instance = new TrackManager();
            }
            return _instance;
        }

        /**
         * Initialize track manager system
         */
        public static function initialize():void {
            getInstance(); // Ensures instance creation and setup
        }

        /**
         * Setup all impulse listeners for track management
         */
        private function setupImpulseListeners():void {
            // Track creation process
            MultiPulsator.subscribeToImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_END", onPinDragEnd);

            // System events for track updates
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
			
            MultiPulsator.subscribeToImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.subscribeToImpulse("WINDOW_CLOSING", onWindowClosing);

            // Track management commands
            MultiPulsator.subscribeToImpulse("TRACK_DISCONNECT", onTrackDisconnect);
            MultiPulsator.subscribeToImpulse("TRACK_UPDATE_ALL", onTrackUpdateAll);
        }

        // =========================================================================
        // PIN DRAG HANDLERS
        // =========================================================================

        /**
         * Handle pin drag start impulse
         * @param {Impulse} impulse - PIN_DRAG_START impulse
         */
        private function onPinDragStart(impulse:Impulse):void {
            trace("=== PIN DRAG START ===");
            _currentDragPin = impulse.data.pin;
            _currentWindow = findWindowByType(impulse.data.windowType);

            trace("Current window: " + (_currentWindow ? _currentWindow.windowType : "null"));
            trace("TracksLayer: " + (_currentWindow && _currentWindow.tracksLayer ? "exists" : "null"));
            trace("ContentLayer: " + (_currentWindow && _currentWindow.contentLayer ? "exists" : "null"));

            if (_currentWindow && _currentDragPin) {
                startTempTrack(impulse.data.startX, impulse.data.startY);
            } else {
                trace("Missing window or drag pin!");
            }
        }

        /**
         * Handle pin drag update impulse
         * @param {Impulse} impulse - PIN_DRAG_UPDATE impulse
         */
        private function onPinDragUpdate(impulse:Impulse):void {
            if (_tempTrack && _currentDragPin) {
                updateTempTrack(impulse.data.currentX, impulse.data.currentY);
            }
        }

        /**
         * Handle pin drag end impulse
         * @param {Impulse} impulse - PIN_DRAG_END impulse
         */
        private function onPinDragEnd(impulse:Impulse):void {
            if (!_currentDragPin) return;

            var fromPin:Pin = _currentDragPin;
            var toPin:Pin = impulse.data.toPin;

            trace("=== PIN DRAG END ===");
            trace("From pin: " + fromPin.name + " (type: " + fromPin.type + ")");
            trace("Initial to pin: " + (toPin ? toPin.name + " (type: " + toPin.type + ")" : "null"));

            // Если точный поиск не нашел пин, используем поиск по радиусу
            if (!toPin) {
                trace("Exact pin search failed, trying radius search...");
                toPin = findPinInRadius(impulse.data.endX, impulse.data.endY, 20);
                trace("Radius search result: " + (toPin ? toPin.name : "null"));
            }

            cleanupTempTrack();

            // Validate and create track if connection is valid
            if (toPin && isValidConnection(fromPin, toPin)) {
                trace("Creating track...");
                createTrack(fromPin, toPin);
            } else {
                trace("Invalid connection - no track created");
            }

            _currentDragPin = null;
        }

        // =========================================================================
        // PIN SEARCH METHODS
        // =========================================================================

        /**
         * Find pins within a specified radius of mouse position
         * @param {Number} stageX - Mouse X coordinate
         * @param {Number} stageY - Mouse Y coordinate  
         * @param {Number} radius - Search radius in pixels
         * @return {Pin} Closest pin within radius, or null if none found
         */
        private function findPinInRadius(stageX:Number, stageY:Number, radius:Number = 15):Pin {
            var allPins:Array = getAllPinsInWindow();
            var mousePos:Point = new Point(stageX, stageY);
            var closestPin:Pin = null;
            var minDistance:Number = Number.MAX_VALUE;
            
            trace("Searching for pins in radius " + radius + " from: " + mousePos);
            trace("Total pins in window: " + allPins.length);
            
            for each (var pin:Pin in allPins) {
                var pinPos:Point = getGlobalPinPosition(pin);
                var distance:Number = Point.distance(mousePos, pinPos);
                
                trace("Pin '" + pin.name + "' at " + pinPos + ", distance: " + distance);
                
                if (distance <= radius && distance < minDistance && pin != _currentDragPin) {
                    // Проверяем, что это валидное соединение
                    if (isValidConnection(_currentDragPin, pin)) {
                        closestPin = pin;
                        minDistance = distance;
                        trace("Found valid pin candidate: " + pin.name + " at distance " + distance);
                    }
                }
            }
            
            if (closestPin) {
                trace("Selected closest pin: " + closestPin.name + " at distance " + minDistance);
            } else {
                trace("No valid pins found in radius");
            }
            
            return closestPin;
        }

        /**
         * Get all pins in the current window
         * @return {Array} Array of all pins
         */
        private function getAllPinsInWindow():Array {
            var allPins:Array = [];
            var atomManager:AtomManager = AtomManager.getInstance();
            
            if (!_currentWindow) return allPins;
            
            var allAtoms:Array = atomManager.getAtomsForWindow(_currentWindow.windowType);
            
            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;
                
                // Добавляем входные пины
                for each (var inputPin:Pin in atom.inputs) {
                    allPins.push(inputPin);
                }
                
                // Добавляем выходные пины
                for each (var outputPin:Pin in atom.outputs) {
                    allPins.push(outputPin);
                }
            }
            
            return allPins;
        }

        // =========================================================================
        // TEMPORARY TRACK METHODS
        // =========================================================================

        /**
         * Start temporary track visualization
         * @param {Number} startX - Starting X coordinate
         * @param {Number} startY - Starting Y coordinate
         */
        private function startTempTrack(startX:Number, startY:Number):void {
            var fromPos:Point = getGlobalPinPosition(_currentDragPin);
            var localFrom:Point = _currentWindow.overlayLayer.globalToLocal(fromPos);

            _tempTrack = new TempTrack(localFrom);

            if (_currentWindow && _currentWindow.overlayLayer) {
                _currentWindow.overlayLayer.addChild(_tempTrack);
                updateTempTrack(startX, startY);
            }
        }

        /**
         * Update temporary track during drag operation
         * @param {Number} currentX - Current mouse X coordinate
         * @param {Number} currentY - Current mouse Y coordinate
         */
        private function updateTempTrack(currentX:Number, currentY:Number):void {
            if (!_tempTrack || !_currentDragPin || !_currentWindow) return;

            var localTo:Point = _currentWindow.overlayLayer.globalToLocal(new Point(currentX, currentY));
            (_tempTrack as TempTrack).update(localTo);
        }

        /**
         * Clean up temporary track
         */
        private function cleanupTempTrack():void {
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
            }
            _tempTrack = null;
        }

        // =========================================================================
        // TRACK CREATION AND VALIDATION
        // =========================================================================

        /**
         * Validate connection between pins
         * @param {Pin} fromPin - Source pin (must be output)
         * @param {Pin} toPin - Target pin (must be input)
         * @return {Boolean} True if connection is valid
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            if (!toPin || !fromPin) return false;

            // Get atoms from AtomManager since pins don't have direct parent reference
            var fromAtom:Atom = getAtomByPin(fromPin);
            var toAtom:Atom = getAtomByPin(toPin);

            return toPin.type == Pin.TYPE_INPUT &&
                   fromPin.type == Pin.TYPE_OUTPUT &&
                   fromAtom && toAtom &&
                   fromAtom.id != toAtom.id &&
                   !connectionExists(fromPin, toPin);
        }

        /**
         * Check if connection already exists
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         * @return {Boolean} True if connection already exists
         */
        private function connectionExists(fromPin:Pin, toPin:Pin):Boolean {
            var connectionId:String = generateConnectionId(fromPin, toPin);
            return _activeTracks[connectionId] != null;
        }

        /**
         * Create a new track between pins
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         */
        private function createTrack(fromPin:Pin, toPin:Pin):void {
            try {
                var track:Track = new Track(fromPin, toPin);
                var connectionId:String = generateConnectionId(fromPin, toPin);

                // Используем существующий tracksLayer
                if (_currentWindow && _currentWindow.tracksLayer) {
                    _currentWindow.tracksLayer.addChild(track);
                    trace("Track added to existing tracksLayer");
                } else if (_currentWindow && _currentWindow.contentLayer) {
                    // Fallback: используем contentLayer
                    _currentWindow.contentLayer.addChild(track);
                    trace("Track added to contentLayer (tracksLayer not available)");
                } else {
                    trace("No window or layers available for track");
                    return;
                }

                // Store track reference
                _activeTracks[connectionId] = track;

                // Create logical connection
                track.createLogicalConnection();

                MultiPulsator.emit(new Impulse("TRACK_CREATED", {
                    track: track,
                    fromPin: fromPin,
                    toPin: toPin,
                    connectionId: connectionId,
                    windowType: _currentWindow ? _currentWindow.windowType : "unknown"
                }));

            } catch (error:Error) {
                trace("Track creation error: " + error.message);
                MultiPulsator.emit(new Impulse("TRACK_CREATION_ERROR", {
                    fromPin: fromPin,
                    toPin: toPin,
                    error: error.message
                }));
            }
        }

        // =========================================================================
        // PIN POSITION CALCULATION METHODS
        // =========================================================================

        /**
         * Get global position of a pin
         * @private
         * @param {Pin} pin - Pin to get position for
         * @return {Point} Global position point
         */
        private function getGlobalPinPosition(pin:Pin):Point {
            // Find the PinView in the display hierarchy
            var pinView:PinView = findPinView(pin);
            if (pinView && pinView.stage) {
                // Получаем глобальную позицию пина
                return pinView.localToGlobal(new Point(0, 0));
            }

            // Fallback: если PinView не найден, используем позицию атома
            var atom:Atom = getAtomByPin(pin);
            var atomView:AtomView = getAtomView(atom);
            if (atomView && atomView.stage) {
                var pinIndex:int = getPinIndex(atom, pin);
                var totalPins:int = pin.type == Pin.TYPE_INPUT ? atom.inputs.length : atom.outputs.length;
                var pinY:Number = atomView.height * (pinIndex + 1) / (totalPins + 1);
                var pinX:Number = pin.type == Pin.TYPE_INPUT ? 0 : atomView.width;

                // Получаем глобальную позицию атома и добавляем смещение пина
                var atomGlobal:Point = atomView.localToGlobal(new Point(pinX, pinY));
                return atomGlobal;
            }

            return new Point(100, 100); // Fallback с видимой позицией
        }

        /**
         * Find the PinView for a given Pin
         * @private
         * @param {Pin} pin - Pin to find view for
         * @return {PinView} Found PinView or null
         */
		private function findPinView(pin:Pin):PinView {
			trace("=== FIND PIN VIEW FROM TRACKMANAGER ===");
			trace("Looking for pin: " + pin.name + " with id: " + pin.id);
			trace("Pin type: " + pin.type + ", value: " + pin.value);
			
			var atomManager:AtomManager = AtomManager.getInstance();
			var allAtoms:Array = atomManager.getAtomsForWindow("Editor");
			
			trace("Total atoms in window: " + allAtoms.length);

			for each (var atomData:Object in allAtoms) {
				var atom:Atom = atomData.atom;
				var atomView:AtomView = atomData.view;
				
				trace("Checking atom: " + atom.id + " (" + atom.type + ") at position: " + atom.position);
				trace("AtomView children count: " + atomView.numChildren);
				
				for (var i:int = 0; i < atomView.numChildren; i++) {
					var child:* = atomView.getChildAt(i);
					if (child is PinView) {
						var pinView:PinView = child as PinView;
						trace("  Found PinView: " + pinView.pin.name + 
							  " (id: " + pinView.pin.id + 
							  ", type: " + pinView.pin.type + 
							  ", same id? " + (pinView.pin.id == pin.id) + ")");
						
						if (pinView.pin.id == pin.id) {
							trace("*** MATCH FOUND! ***");
							trace("PinView position: x=" + pinView.x + ", y=" + pinView.y);
							trace("PinView global position: " + pinView.localToGlobal(new Point(0, 0)));
							return pinView;
						}
					}
				}
			}
			
			trace("*** NO MATCH FOUND for pin: " + pin.name + " with id: " + pin.id + " ***");
			return null;
		}

        /**
         * Get atom that owns the specified pin
         * @param {Pin} pin - Pin to find owner for
         * @return {Atom} Atom that owns the pin, or null if not found
         */
		private function getAtomByPin(pin:Pin):Atom {
			trace("=== GET ATOM BY PIN ===");
			trace("Looking for atom that owns pin: " + pin.name + " (id: " + pin.id + ")");
			
			var atomManager:AtomManager = AtomManager.getInstance();
			var allAtoms:Array = atomManager.getAtomsForWindow("Editor");
			
			trace("Total atoms to check: " + allAtoms.length);

			for each (var atomData:Object in allAtoms) {
				var atom:Atom = atomData.atom;
				trace("Checking atom: " + atom.id + " (" + atom.type + ")");
				
				// Check input pins
				for each (var inputPin:Pin in atom.inputs) {
					trace("  Input pin: " + inputPin.name + " (id: " + inputPin.id + 
						  ", match? " + (inputPin.id == pin.id) + ")");
					if (inputPin.id == pin.id) {
						trace("*** FOUND in inputs ***");
						return atom;
					}
				}
				
				// Check output pins
				for each (var outputPin:Pin in atom.outputs) {
					trace("  Output pin: " + outputPin.name + " (id: " + outputPin.id + 
						  ", match? " + (outputPin.id == pin.id) + ")");
					if (outputPin.id == pin.id) {
						trace("*** FOUND in outputs ***");
						return atom;
					}
				}
			}
			
			trace("*** PIN NOT FOUND IN ANY ATOM! ***");
			return null;
		}

        /**
         * Get AtomView for a given Atom
         * @private
         * @param {Atom} atom - Atom to find view for
         * @return {AtomView} Found AtomView or null
         */
        private function getAtomView(atom:Atom):AtomView {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                if (atomData.atom === atom) {
                    return atomData.view;
                }
            }
            return null;
        }

        /**
         * Get the index of a pin within its atom
         * @private
         * @param {Atom} atom - Atom containing the pin
         * @param {Pin} pin - Pin to find index for
         * @return {int} Index of the pin
         */
        private function getPinIndex(atom:Atom, pin:Pin):int {
            var pins:Vector.<Pin> = pin.type == Pin.TYPE_INPUT ? atom.inputs : atom.outputs;
            for (var i:int = 0; i < pins.length; i++) {
                if (pins[i] === pin) {
                    return i;
                }
            }
            return 0;
        }

        // =========================================================================
        // EVENT HANDLERS
        // =========================================================================

        /**
         * Handle atom movement to update connected tracks
         * @param {Impulse} impulse - ATOM_MOVED impulse
         */
		private function onAtomMoved(impulse:Impulse):void {
			trace("TrackManager: ATOM_MOVED received, updateTracks: " + impulse.data.updateTracks);
			
			// Проверяем флаг обновления треков
			if (!impulse.data.updateTracks) {
				trace("TrackManager: Skipping track update - updateTracks is false");
				return;
			}

			var movedAtom:Atom = impulse.data.newAtom;
			var atomId:String = movedAtom.id;

			trace("TrackManager: Updating tracks for atom: " + atomId);
			trace("TrackManager: Active tracks count: " + getActiveTracksCount());

			var updatedTracks:int = 0;
			
			// Update all tracks connected to this atom
			for each (var track:Track in _activeTracks) {
				if (track.isConnectedToAtom(atomId)) {
					trace("TrackManager: Updating track: " + track.connectionId);
					track.updateVisual();
					updatedTracks++;
				}
			}
			
			trace("TrackManager: Updated " + updatedTracks + " tracks");
		}
	
public function getActiveTracksCount():int {
    var count:int = 0;
    for (var key:String in _activeTracks) {
        count++;
    }
    return count;
}

// Добавьте метод для логирования всех треков
public function logAllTracks():void {
    trace("=== ALL ACTIVE TRACKS ===");
    for (var connectionId:String in _activeTracks) {
        var track:Track = _activeTracks[connectionId];
        var info:Object = track.getConnectionInfo();
        trace("Track: " + connectionId + ", From: " + info.fromAtom + "." + info.fromPin + 
              " -> To: " + info.toAtom + "." + info.toPin);
    }
    trace("=== END TRACKS LOG ===");
}
        /**
         * Handle window activation to update track context
         * @param {Impulse} impulse - WINDOW_ACTIVATED impulse
         */
        private function onWindowActivated(impulse:Impulse):void {
            _currentWindow = impulse.data.window;
        }

        /**
         * Handle window closing to cleanup tracks
         * @param {Impulse} impulse - WINDOW_CLOSING impulse
         */
        private function onWindowClosing(impulse:Impulse):void {
            var closingWindow:Window = impulse.data.window;
            var windowType:String = closingWindow.windowType;

            // Remove tracks associated with this window
            cleanupTracksByWindow(windowType);
        }

        /**
         * Handle track disconnect command
         * @param {Impulse} impulse - TRACK_DISCONNECT impulse
         */
        private function onTrackDisconnect(impulse:Impulse):void {
            var track:Track = impulse.data.track;
            var connectionId:String = impulse.data.connectionId;

            if (track) {
                removeTrack(track);
            } else if (connectionId) {
                removeTrackById(connectionId);
            }
        }

        /**
         * Handle update all tracks command
         * @param {Impulse} impulse - TRACK_UPDATE_ALL impulse
         */
        private function onTrackUpdateAll(impulse:Impulse):void {
            for each (var track:Track in _activeTracks) {
                track.updateVisual();
            }
        }

        // =========================================================================
        // UTILITY METHODS
        // =========================================================================

        /**
         * Generate unique connection ID
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         * @return {String} Unique connection identifier
         */
        private function generateConnectionId(fromPin:Pin, toPin:Pin):String {
            var fromAtom:Atom = getAtomByPin(fromPin);
            var toAtom:Atom = getAtomByPin(toPin);

            if (!fromAtom || !toAtom) {
                return "invalid_connection";
            }

            return "track_" + fromAtom.id + "_" + fromPin.name +
                   "_to_" + toAtom.id + "_" + toPin.name;
        }

        /**
         * Find window by type
         * @param {String} windowType - Window type to find
         * @return {Window} Found window or null
         */
        private function findWindowByType(windowType:String):Window {
            var windowsManager:WindowsManager = WindowsManager.getInstance();
            if (windowsManager) {
                return windowsManager.findWindow(windowType);
            }
            return null;
        }

        /**
         * Cleanup tracks by window type
         * @param {String} windowType - Window type to cleanup
         */
        private function cleanupTracksByWindow(windowType:String):void {
            // Remove tracks that are in the specified window
            for (var connectionId:String in _activeTracks) {
                var track:Track = _activeTracks[connectionId];
                // We need to check which window the track belongs to
                // For now, we'll assume all tracks are in the current window context
                if (_currentWindow && _currentWindow.windowType == windowType) {
                    removeTrack(track);
                }
            }
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Remove track by track instance
         * @param {Track} track - Track to remove
         */
        public function removeTrack(track:Track):void {
            var connectionId:String = track.connectionId;

            if (_activeTracks[connectionId]) {
                track.dispose();
                delete _activeTracks[connectionId];

                MultiPulsator.emit(new Impulse("TRACK_REMOVED", {
                    track: track,
                    connectionId: connectionId
                }));
            }
        }

        /**
         * Remove track by connection ID
         * @param {String} connectionId - Connection ID to remove
         */
        public function removeTrackById(connectionId:String):Track {
            var track:Track = _activeTracks[connectionId];
            if (track) {
                removeTrack(track);
            }
            return track;
        }

        /**
         * Get all active tracks
         * @return {Object} Object of active tracks
         */
        public function getActiveTracks():Object {
            return _activeTracks;
        }

        /**
         * Get track by connection ID
         * @param {String} connectionId - Connection ID to find
         * @return {Track} Found track or null
         */
        public function getTrackById(connectionId:String):Track {
            return _activeTracks[connectionId];
        }

        /**
         * Get tracks connected to specific atom
         * @param {String} atomId - Atom ID to find connections for
         * @return {Array} Array of connected tracks
         */
        public function getTracksByAtom(atomId:String):Array {
            var connectedTracks:Array = [];

            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) {
                    connectedTracks.push(track);
                }
            }

            return connectedTracks;
        }

        /**
         * Get tracks connected to specific pin
         * @param {Pin} pin - Pin to find connections for
         * @return {Array} Array of connected tracks
         */
        public function getTracksByPin(pin:Pin):Array {
            var connectedTracks:Array = [];

            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToPin(pin)) {
                    connectedTracks.push(track);
                }
            }

            return connectedTracks;
        }

        /**
         * Cleanup all resources
         */
        public function dispose():void {
            // Remove all impulse listeners
            MultiPulsator.removeImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.removeImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.removeImpulse("PIN_DRAG_END", onPinDragEnd);
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.removeImpulse("WINDOW_CLOSING", onWindowClosing);
            MultiPulsator.removeImpulse("TRACK_DISCONNECT", onTrackDisconnect);
            MultiPulsator.removeImpulse("TRACK_UPDATE_ALL", onTrackUpdateAll);

            // Dispose all active tracks
            for each (var track:Track in _activeTracks) {
                track.dispose();
            }
            _activeTracks = {};

            // Cleanup temporary track
            cleanupTempTrack();

            _currentDragPin = null;
            _currentWindow = null;
        }
    }
}
