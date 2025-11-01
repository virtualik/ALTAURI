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
			trace("onPinDragStart event handler here!")
            _currentDragPin = impulse.data.pin;
            _currentWindow = findWindowByType(impulse.data.windowType);
            
            if (_currentWindow && _currentDragPin) {
                startTempTrack(impulse.data.startX, impulse.data.startY);
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
            
            cleanupTempTrack();

            // Validate and create track if connection is valid
            if (toPin && isValidConnection(fromPin, toPin)) {
                createTrack(fromPin, toPin);
            }
            
            _currentDragPin = null;
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

                // Add to tracksLayer instead of contentLayer
                if (_currentWindow && _currentWindow.tracksLayer) {
                    _currentWindow.tracksLayer.addChild(track);
                } else if (_currentWindow && _currentWindow.contentLayer) {
                    // Fallback to contentLayer if tracksLayer is not available
                    _currentWindow.contentLayer.addChild(track);
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
			if (pinView) {
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
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                var atomView:AtomView = atomData.view;
                for (var i:int = 0; i < atomView.numChildren; i++) {
                    var child:* = atomView.getChildAt(i);
                    if (child is PinView && (child as PinView).pin === pin) {
                        return child as PinView;
                    }
                }
            }
            return null;
        }

        /**
         * Get atom that owns the specified pin
         * @param {Pin} pin - Pin to find owner for
         * @return {Atom} Atom that owns the pin, or null if not found
         */
        private function getAtomByPin(pin:Pin):Atom {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;
                // Check input pins
                for each (var inputPin:Pin in atom.inputs) {
                    if (inputPin === pin) return atom;
                }
                // Check output pins
                for each (var outputPin:Pin in atom.outputs) {
                    if (outputPin === pin) return atom;
                }
            }
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
            var movedAtom:Atom = impulse.data.newAtom;
            var atomId:String = movedAtom.id;
            
            // Update all tracks connected to this atom
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) {
                    track.updateVisual();
                }
            }
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
