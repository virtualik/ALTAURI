package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Core.Managers.WindowsManager;
    import Src.Prog.Core.Managers.AtomManager;

    /**
     * TrackManager - Centralized manager for track creation, lifecycle management and pin calculations
     * Handles all track-related operations including pin positioning and atom discovery
     * 
     * @class TrackManager
     * @public
     */
    public class TrackManager {
        /** Singleton instance */
        private static var _instance:TrackManager;

        /** Active tracks storage by connection ID */
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
         * 
         * @static
         * @public
         * @return {TrackManager} Singleton instance
         */
        public static function getInstance():TrackManager {
            if (!_instance) {
                _instance = new TrackManager();
            }
            return _instance;
        }

        /**
         * Initialize track manager system
         * 
         * @static
         * @public
         */
        public static function initialize():void {
            getInstance();
        }

        // =========================================================================
        // PIN POSITION CALCULATION METHODS (UNIFIED)
        // =========================================================================

        /**
         * Get global position of a pin
         * 
         * @public
         * @param {Pin} pin - Pin to get position for
         * @return {Point} Global position point
         */
        public function getGlobalPinPosition(pin:Pin):Point {
            // Find the PinView in the display hierarchy
            var pinView:PinView = findPinView(pin);
            if (pinView && pinView.stage) {
                return pinView.localToGlobal(new Point(0, 0));
            }

            // Fallback: use atom position if PinView not found
            var atom:Atom = getAtomByPin(pin);
            var atomView:AtomView = getAtomView(atom);
            if (atomView && atomView.stage) {
                var pinIndex:int = getPinIndex(atom, pin);
                var totalPins:int = pin.type == Pin.TYPE_INPUT ? atom.inputs.length : atom.outputs.length;
                var pinY:Number = atomView.height * (pinIndex + 1) / (totalPins + 1);
                var pinX:Number = pin.type == Pin.TYPE_INPUT ? 0 : atomView.width;

                var atomGlobal:Point = atomView.localToGlobal(new Point(pinX, pinY));
                return atomGlobal;
            }

            return new Point(100, 100); // Fallback position
        }

        /**
         * Find the PinView for a given Pin
         * 
         * @public
         * @param {Pin} pin - Pin to find view for
         * @return {PinView} Found PinView or null
         */
        public function findPinView(pin:Pin):PinView {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;
                var atomView:AtomView = atomData.view;

                for (var i:int = 0; i < atomView.numChildren; i++) {
                    var child:* = atomView.getChildAt(i);
                    if (child is PinView) {
                        var pinView:PinView = child as PinView;
                        if (pinView.pin.id == pin.id) {
                            return pinView;
                        }
                    }
                }
            }

            return null;
        }

        /**
         * Get atom that owns the specified pin
         * 
         * @public
         * @param {Pin} pin - Pin to find owner for
         * @return {Atom} Atom that owns the pin, or null if not found
         */
        public function getAtomByPin(pin:Pin):Atom {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;

                // Check input pins
                for each (var inputPin:Pin in atom.inputs) {
                    if (inputPin.id == pin.id) {
                        return atom;
                    }
                }

                // Check output pins
                for each (var outputPin:Pin in atom.outputs) {
                    if (outputPin.id == pin.id) {
                        return atom;
                    }
                }
            }

            return null;
        }

        /**
         * Get AtomView for a given Atom
         * 
         * @public
         * @param {Atom} atom - Atom to find view for
         * @return {AtomView} Found AtomView or null
         */
        public function getAtomView(atom:Atom):AtomView {
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
         * 
         * @public
         * @param {Atom} atom - Atom containing the pin
         * @param {Pin} pin - Pin to find index for
         * @return {int} Index of the pin
         */
        public function getPinIndex(atom:Atom, pin:Pin):int {
            var pins:Vector.<Pin> = pin.type == Pin.TYPE_INPUT ? atom.inputs : atom.outputs;
            for (var i:int = 0; i < pins.length; i++) {
                if (pins[i] === pin) {
                    return i;
                }
            }
            return 0;
        }

        // =========================================================================
        // PIN SEARCH METHODS
        // =========================================================================

        /**
         * Find pins within a specified radius of mouse position
         * 
         * @private
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

            for each (var pin:Pin in allPins) {
                var pinPos:Point = getGlobalPinPosition(pin);
                var distance:Number = Point.distance(mousePos, pinPos);

                if (distance <= radius && distance < minDistance && pin != _currentDragPin) {
                    if (isValidConnection(_currentDragPin, pin)) {
                        closestPin = pin;
                        minDistance = distance;
                    }
                }
            }

            return closestPin;
        }

        /**
         * Get all pins in the current window
         * 
         * @private
         * @return {Array} Array of all pins
         */
        private function getAllPinsInWindow():Array {
            var allPins:Array = [];
            var atomManager:AtomManager = AtomManager.getInstance();

            if (!_currentWindow) return allPins;

            var allAtoms:Array = atomManager.getAtomsForWindow(_currentWindow.windowType);

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;

                // Add input pins
                for each (var inputPin:Pin in atom.inputs) {
                    allPins.push(inputPin);
                }

                // Add output pins
                for each (var outputPin:Pin in atom.outputs) {
                    allPins.push(outputPin);
                }
            }

            return allPins;
        }

        // =========================================================================
        // TRACK CREATION AND VALIDATION
        // =========================================================================

        /**
         * Validate connection between pins
         * 
         * @private
         * @param {Pin} fromPin - Source pin (must be output)
         * @param {Pin} toPin - Target pin (must be input)
         * @return {Boolean} True if connection is valid
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            if (!toPin || !fromPin) return false;

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
         * 
         * @private
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         * @return {Boolean} True if connection already exists
         */
        private function connectionExists(fromPin:Pin, toPin:Pin):Boolean {
            var connectionId:String = generateConnectionId(fromPin, toPin);
            return _activeTracks[connectionId] != null;
        }

        /**
         * Generate unique connection ID
         * 
         * @private
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

        // =========================================================================
        // IMPULSE LISTENERS SETUP
        // =========================================================================

        /**
         * Setup impulse listeners for track management
         * 
         * @private
         */
        private function setupImpulseListeners():void {
            // Track creation process
            MultiPulsator.subscribeToImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_END", onPinDragEnd);

            // Atom movement events
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);

            // Window events
            MultiPulsator.subscribeToImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.subscribeToImpulse("WINDOW_CLOSING", onWindowClosing);

            // Track management commands
            MultiPulsator.subscribeToImpulse("TRACK_DELETE_REQUEST", onTrackDeleteRequest);
        }

        // =========================================================================
        // EVENT HANDLERS
        // =========================================================================

        /**
         * Handle pin drag start impulse
         */
        private function onPinDragStart(impulse:Impulse):void {
            _currentDragPin = impulse.data.pin;
            _currentWindow = findWindowByType(impulse.data.windowType);

            if (_currentWindow && _currentDragPin) {
                startTempTrack(impulse.data.startX, impulse.data.startY);
            }
        }

        /**
         * Handle pin drag update impulse
         */
        private function onPinDragUpdate(impulse:Impulse):void {
            if (_tempTrack && _currentDragPin) {
                updateTempTrack(impulse.data.currentX, impulse.data.currentY);
            }
        }

        /**
         * Handle pin drag end impulse
         */
        private function onPinDragEnd(impulse:Impulse):void {
            if (!_currentDragPin) return;

            var fromPin:Pin = _currentDragPin;
            var toPin:Pin = impulse.data.toPin;

            if (!toPin) {
                toPin = findPinInRadius(impulse.data.endX, impulse.data.endY, 20);
            }

            cleanupTempTrack();

            if (toPin && isValidConnection(fromPin, toPin)) {
                createTrack(fromPin, toPin);
            }

            _currentDragPin = null;
        }

        /**
         * Handle atom movement to update connected tracks
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:Atom = impulse.data.newAtom;
            var atomId:String = movedAtom.id;
            var updateTracks:Boolean = impulse.data.updateTracks;

            if (updateTracks) {
                updateTracksForAtom(atomId);
            }
        }

        /**
         * Handle window activation to update track context
         */
        private function onWindowActivated(impulse:Impulse):void {
            _currentWindow = impulse.data.window;
        }

        /**
         * Handle window closing to cleanup tracks
         */
        private function onWindowClosing(impulse:Impulse):void {
            var closingWindow:Window = impulse.data.window;
            var windowType:String = closingWindow.windowType;
            cleanupTracksByWindow(windowType);
        }

        /**
         * Handle track deletion request from context menu
         */
        private function onTrackDeleteRequest(impulse:Impulse):void {
            var track:Track = impulse.data.track;

            if (track) {
                removeTrack(track);
                MultiPulsator.emit(new Impulse("TRACK_DELETED", {
                    track: track,
                    connectionId: track.connectionId
                }));
            }
        }

        // =========================================================================
        // TRACK OPERATIONS
        // =========================================================================

        /**
         * Create a new track between pins
         */
        private function createTrack(fromPin:Pin, toPin:Pin):void {
            try {
                var track:Track = new Track(fromPin, toPin, this);
                var connectionId:String = generateConnectionId(fromPin, toPin);

                if (_currentWindow && _currentWindow.tracksLayer) {
                    _currentWindow.tracksLayer.addChild(track);
                } else if (_currentWindow && _currentWindow.contentLayer) {
                    _currentWindow.contentLayer.addChild(track);
                } else {
                    return;
                }

                _activeTracks[connectionId] = track;
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

        /**
         * Update all tracks connected to a specific atom
         */
        private function updateTracksForAtom(atomId:String):void {
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) {
                    track.updateVisual();
                }
            }
        }

        // =========================================================================
        // TEMPORARY TRACK METHODS
        // =========================================================================

        private function startTempTrack(startX:Number, startY:Number):void {
            var fromPos:Point = getGlobalPinPosition(_currentDragPin);
            var localFrom:Point = _currentWindow.overlayLayer.globalToLocal(fromPos);

            _tempTrack = new TempTrack(localFrom);

            if (_currentWindow && _currentWindow.overlayLayer) {
                _currentWindow.overlayLayer.addChild(_tempTrack);
                updateTempTrack(startX, startY);
            }
        }

        private function updateTempTrack(currentX:Number, currentY:Number):void {
            if (!_tempTrack || !_currentDragPin || !_currentWindow) return;

            var localTo:Point = _currentWindow.overlayLayer.globalToLocal(new Point(currentX, currentY));
            (_tempTrack as TempTrack).update(localTo);
        }

        private function cleanupTempTrack():void {
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
            }
            _tempTrack = null;
        }

        // =========================================================================
        // UTILITY METHODS
        // =========================================================================

        private function findWindowByType(windowType:String):Window {
            var windowsManager:WindowsManager = WindowsManager.getInstance();
            return windowsManager ? windowsManager.findWindow(windowType) : null;
        }

        private function cleanupTracksByWindow(windowType:String):void {
            for (var connectionId:String in _activeTracks) {
                var track:Track = _activeTracks[connectionId];
                if (_currentWindow && _currentWindow.windowType == windowType) {
                    removeTrack(track);
                }
            }
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

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

        public function removeTrackById(connectionId:String):Track {
            var track:Track = _activeTracks[connectionId];
            if (track) removeTrack(track);
            return track;
        }

        public function getActiveTracks():Object { return _activeTracks; }
        public function getTrackById(connectionId:String):Track { return _activeTracks[connectionId]; }

        public function getTracksByAtom(atomId:String):Array {
            var connectedTracks:Array = [];
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) connectedTracks.push(track);
            }
            return connectedTracks;
        }

        public function getTracksByPin(pin:Pin):Array {
            var connectedTracks:Array = [];
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToPin(pin)) connectedTracks.push(track);
            }
            return connectedTracks;
        }

        public function getActiveTracksCount():int {
            var count:int = 0;
            for (var key:String in _activeTracks) count++;
            return count;
        }

        public function dispose():void {
            MultiPulsator.removeImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.removeImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.removeImpulse("PIN_DRAG_END", onPinDragEnd);
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.removeImpulse("WINDOW_CLOSING", onWindowClosing);
            MultiPulsator.removeImpulse("TRACK_DELETE_REQUEST", onTrackDeleteRequest);

            for each (var track:Track in _activeTracks) track.dispose();
            _activeTracks = {};
            cleanupTempTrack();
            _currentDragPin = null;
            _currentWindow = null;
        }
    }
}
