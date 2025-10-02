package Application.Managers {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Application.AtomLinker.Core.Pin;
    import Application.AtomLinker.Core.Track;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import flash.utils.Dictionary;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.Managers.AtomManager;
    import Application.AtomICScript.AtomICScriptManager;

    /**
     * Connection Manager - manages creation and display of tracks between atoms
     * Handles pin connections, track drawing, and value propagation
     */
    public class ConnectionManager {
        private static var _instance: ConnectionManager;
        private var _currentFromPin: Pin;
        private var _tempTrack: Sprite;
        private var _allTracks: Array;
        private var _tracksById:Dictionary;
        private var _tracksByPin:Dictionary;

        /**
         * Constructor - initializes track storage and subscribes to events
         */
        public function ConnectionManager() {
            _allTracks = [];
            _tracksById = new Dictionary();
            _tracksByPin = new Dictionary();
            subscribeToEvents();
        }

        /**
         * Get singleton instance
         */
        public static function getInstance(): ConnectionManager {
            if(!_instance) _instance = new ConnectionManager();
            return _instance;
        }

        /**
         * Subscribe to relevant impulses
         */
        private function subscribeToEvents(): void {
            MultiPulsator.subscribeToImpulse("PIN_MOUSE_DOWN", onPinMouseDown);
            MultiPulsator.subscribeToImpulse("EDITOR_MOUSE_MOVE", onEditorMouseMove);
            MultiPulsator.subscribeToImpulse("EDITOR_MOUSE_UP", onEditorMouseUp);
            MultiPulsator.subscribeToImpulse("PIN_UPDATED", onPinUpdated);
            MultiPulsator.subscribeToImpulse("TRACK_RIGHT_CLICK", onTrackRightClick);
            MultiPulsator.subscribeToImpulse("DELETE_TRACK_REQUEST", onDeleteTrackRequest);
        }

        // --- Impulse handlers ---

        /**
         * Handle track right-click for deletion
         */
        private function onTrackRightClick(impulse:Impulse):void {
            var track:Track = impulse.data.track as Track;
            if (track) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "INFO",
                    source: "ConnectionManager",
                    message: "Right click on track " + track.id
                }));
                removeTrack(track);
            }
        }

        /**
         * Handle pin value updates and propagate through tracks
         */
        private function onPinUpdated(impulse: Impulse): void {
            var atomId: String = impulse.data.atomId as String;
            var pinName: String = impulse.data.pinName as String;
            var newValue: * = impulse.data.newValue;

            if (!atomId || !pinName) return;

            var atomManager: AtomManager = AtomManager.getInstance();
            if (!atomManager) return;

            var sourceAtom: BaseAtom = atomManager.getAtom(atomId);
            if (!sourceAtom) return;

            var sourcePin: Pin = null;
            for each (var outPin: Pin in sourceAtom.outputContacts) {
                if (outPin.name == pinName) {
                    sourcePin = outPin;
                    break;
                }
            }
            if (!sourcePin) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "ConnectionManager",
                    message: "Pin not found " + pinName + " in atom " + atomId
                }));
                return;
            }

            var trackFound: Boolean = false;
            for each (var track: Track in _allTracks) {
                if (track.fromPin.parentAtom.id == atomId && track.fromPin.name == pinName) {
                    trackFound = true;
                    var targetPin: Pin = track.toPin;
                    var oldTargetAtom: BaseAtom = atomManager.getAtom(targetPin.parentAtom.id);
                    if (!oldTargetAtom) continue;

                    var newTargetAtom: BaseAtom = oldTargetAtom.setInputPinValue(targetPin.name, newValue);
                    if (!newTargetAtom) continue;

                    // Check value change
                    var valueChanged: Boolean = true;
                    var oldInputPin: Pin = getPinByName(oldTargetAtom.inputContacts, targetPin.name);
                    var newInputPin: Pin = getPinByName(newTargetAtom.inputContacts, targetPin.name);

                    if (oldInputPin && newInputPin) {
                        valueChanged = (oldInputPin.value !== newInputPin.value);
                    }

                    if (valueChanged) {
                        var atomICScriptManager:AtomICScriptManager = AtomICScriptManager.getInstance();
                        newTargetAtom = atomICScriptManager.handlePinChange(newTargetAtom, newInputPin);

                        // Check output changes
                        for (var i:int = 0; i < oldTargetAtom.outputContacts.length; i++) {
                            var oldOutPin: Pin = oldTargetAtom.outputContacts[i];
                            var newOutPin: Pin = newTargetAtom.outputContacts[i];
                            if (oldOutPin.value !== newOutPin.value) {
                                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                                    atomId: newTargetAtom.id,
                                    pinName: newOutPin.name,
                                    newValue: newOutPin.value
                                }));
                            }
                        }
                    }

                    atomManager.updateAtom(newTargetAtom);
                    MultiPulsator.emit(new Impulse("ATOM_UPDATED", {
                        oldAtom: oldTargetAtom,
                        newAtom: newTargetAtom
                    }));
                }
            }

            if (!trackFound) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "WARN",
                    source: "ConnectionManager",
                    message: "No connections for pin " + sourcePin.toStringRepresentation()
                }));
            }
        }

        /**
         * Handle pin mouse down to start connection
         */
        private function onPinMouseDown(impulse: Impulse): void {
            var pin: Pin = impulse.data.pin as Pin;
            if(pin && pin.type == Pin.TYPE_OUTPUT) {
                MultiPulsator.emit(new Impulse("OUTPUT_PIN_SELECTED", {
                    pin: pin,
                    source: "ConnectionManager"
                }));
                startConnection(pin);
            }
        }

        /**
         * Handle editor mouse move for temporary track drawing
         */
        private function onEditorMouseMove(impulse:Impulse):void {
            if(!_currentFromPin) return;
            var mousePos:Point = impulse.data.mousePos as Point;
            drawTempTrack(mousePos);
        }

        /**
         * Handle editor mouse up to complete or cancel connection
         */
        private function onEditorMouseUp(impulse:Impulse):void {
            if(!_currentFromPin) return;

            var mousePos:Point = impulse.data.mousePos as Point;
            var targetPin:Pin = findPinUnderMouse(mousePos);

            if(targetPin && isValidConnection(_currentFromPin, targetPin)) {
                completeConnection(targetPin);
            } else {
                cancelConnection();
            }
        }

        // --- Main methods ---

        /**
         * Start new connection from output pin
         */
        public function startConnection(fromPin:Pin):void {
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
                _tempTrack = null;
            }

            _currentFromPin = fromPin;
            _tempTrack = new Sprite();
            _tempTrack.graphics.lineStyle(4, 0xFF0000, 1.0);

            MultiPulsator.emit(new Impulse("ADD_TO_EDITOR", {
                object: _tempTrack,
                type: "temporary_track"
            }));

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "ConnectionManager",
                message: "Starting connection from pin: " + fromPin.name
            }));
        }

        /**
         * Draw temporary track during connection creation
         */
        private function drawTempTrack(mousePos: Point): void {
            if(!_currentFromPin || !_tempTrack) return;
            _tempTrack.graphics.clear();
            _tempTrack.graphics.lineStyle(3, 0xFF0000, 1.0);
            var startPos: Point = getLocalPinPosition(_currentFromPin);
            _tempTrack.graphics.moveTo(startPos.x, startPos.y);
            _tempTrack.graphics.lineTo(mousePos.x, mousePos.y);
        }

        /**
         * Get pin position in global coordinates
         */
        private function getLocalPinPosition(pin: Pin): Point {
            if(!pin || !pin.parentAtom || !pin.parentAtom.displayObject)
                return new Point(0, 0);
            var pinLocalX: Number = pin.x;
            var pinLocalY: Number = pin.y;
            var atomX: Number = pin.parentAtom.displayObject.x;
            var atomY: Number = pin.parentAtom.displayObject.y;
            return new Point(atomX + pinLocalX, atomY + pinLocalY);
        }

        /**
         * Remove all tracks between two pins
         */
        public function removeAllTracksBetween(fromPin:Pin, toPin:Pin):void {
            if (!fromPin || !toPin) return;

            var fromPinKey:String = getPinKey(fromPin);
            var tracks:Array = _tracksByPin[fromPinKey];

            if (tracks) {
                var tracksToRemove:Array = [];
                for each (var track:Track in tracks) {
                    if (track.fromPin === fromPin && track.toPin === toPin) {
                        tracksToRemove.push(track);
                    }
                }
                for each (var trackToRemove:Track in tracksToRemove) {
                    removeTrack(trackToRemove);
                }
            }
        }

        /**
         * Complete connection to target pin
         */
        public function completeConnection(toPin:Pin):void {
            if (!_currentFromPin || !toPin) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "ConnectionManager",
                    message: "Invalid pins for connection"
                }));
                return;
            }

            // Remove existing tracks between these pins
            removeAllTracksBetween(_currentFromPin, toPin);

            if (!isValidConnection(_currentFromPin, toPin)) {
                cancelConnection();
                return;
            }

            // Remove temporary track
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
                _tempTrack = null;
            }

            // Create new track
            var track:Track = new Track(_currentFromPin, toPin);
            _allTracks.push(track);
            _tracksById[track.id] = track;
            indexTrackByPins(track, _currentFromPin, toPin);

            // Pass initial value
            if (_currentFromPin.value !== null && _currentFromPin.value !== undefined) {
                var atomManager:AtomManager = AtomManager.getInstance();
                var targetAtom:BaseAtom = toPin.parentAtom;
                if (atomManager && targetAtom) {
                    var newTargetAtom:BaseAtom = targetAtom.setInputPinValue(toPin.name, _currentFromPin.value);
                    atomManager.updateAtom(newTargetAtom);
                    MultiPulsator.emit(new Impulse("ATOM_UPDATED", {
                        oldAtom: targetAtom,
                        newAtom: newTargetAtom
                    }));
                }
            }

            MultiPulsator.emit(new Impulse("ADD_TRACK_TO_EDITOR", {
                track: track,
                fromPin: _currentFromPin,
                toPin: toPin
            }));

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "ConnectionManager",
                message: "Connection created: " + _currentFromPin.name + " → " + toPin.name
            }));

            cleanUp();
        }

        /**
         * Cancel current connection
         */
        public function cancelConnection():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "ConnectionManager",
                message: "Connection cancelled"
            }));
            cleanUp();
        }

        /**
         * Clean up temporary connection state
         */
        private function cleanUp():void {
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
            }
            _currentFromPin = null;
            _tempTrack = null;
        }

        // --- Helper methods ---

        /**
         * Find pin under mouse position
         */
        private function findPinUnderMouse(mousePos:Point):Pin {
            var atomManager:AtomManager = AtomManager.getInstance();
            if(!atomManager) return null;

            var allAtoms:Dictionary = atomManager.getAllAtoms();
            var closestPin:Pin = null;
            var closestDistance:Number = Number.MAX_VALUE;

            for each(var atom:BaseAtom in allAtoms) {
                if(!atom.displayObject) continue;

                var localMousePos:Point = atom.displayObject.globalToLocal(mousePos);
                for each(var pin:Pin in atom.getAllContacts()) {
                    if (!pin.parent) continue;
                    if (!pin.parentAtom || pin.parentAtom != atom) continue;

                    var pinPos:Point = new Point(pin.x, pin.y);
                    var distance:Number = Point.distance(pinPos, localMousePos);

                    if(distance < 15 && distance < closestDistance) {
                        closestDistance = distance;
                        closestPin = pin;
                    }
                }
            }

            return closestPin;
        }

        /**
         * Get pin by name from pin vector
         */
        private function getPinByName(pins:Vector.<Pin>, name:String):Pin {
            for each (var pin:Pin in pins) {
                if (pin.name == name) return pin;
            }
            return null;
        }

        /**
         * Get all tracks associated with atom
         */
        public function getTracksByAtom(atom:BaseAtom):Array {
            var result:Array = [];

            // Check all atom pins
            var allPins:Vector.<Pin> = atom.getAllContacts();

            for each (var pin:Pin in allPins) {
                var pinTracks:Array = getTracksByPin(pin);
                for each (var track:Track in pinTracks) {
                    // Add only unique tracks
                    if (result.indexOf(track) == -1) {
                        result.push(track);
                    }
                }
            }

            return result;
        }

        /**
         * Index track by its pins for quick lookup
         */
        private function indexTrackByPins(track:Track, fromPin:Pin, toPin:Pin):void {
            if (!track || !fromPin || !toPin) return;

            var fromPinKey:String = getPinKey(fromPin);
            var toPinKey:String = getPinKey(toPin);

            if (!_tracksByPin[fromPinKey]) _tracksByPin[fromPinKey] = [];
            if (!_tracksByPin[toPinKey]) _tracksByPin[toPinKey] = [];

            if (_tracksByPin[fromPinKey].indexOf(track) == -1) {
                _tracksByPin[fromPinKey].push(track);
            }
            if (_tracksByPin[toPinKey].indexOf(track) == -1) {
                _tracksByPin[toPinKey].push(track);
            }
        }

        /**
         * Remove track from pin indexing
         */
        private function unindexTrackByPins(track:Track):void {
            if (!track || !track.fromPin || !track.toPin) return;

            var fromPinKey:String = getPinKey(track.fromPin);
            var toPinKey:String = getPinKey(track.toPin);

            removeTrackFromArray(_tracksByPin[fromPinKey], track);
            removeTrackFromArray(_tracksByPin[toPinKey], track);

            if (_tracksByPin[fromPinKey] && _tracksByPin[fromPinKey].length == 0) {
                delete _tracksByPin[fromPinKey];
            }
            if (_tracksByPin[toPinKey] && _tracksByPin[toPinKey].length == 0) {
                delete _tracksByPin[toPinKey];
            }
        }

        /**
         * Remove track from array
         */
        private function removeTrackFromArray(array:Array, track:Track):void {
            if (!array) return;
            var index:int = array.indexOf(track);
            if (index != -1) {
                array.splice(index, 1);
            }
        }

        /**
         * Get unique key for pin
         */
        private function getPinKey(pin:Pin):String {
            if (!pin || !pin.parentAtom) return "unknown";
            return pin.parentAtom.id + "." + pin.name;
        }

        /**
         * Check if connection already exists
         */
        public function connectionExists(fromPin:Pin, toPin:Pin):Boolean {
            if (!fromPin || !toPin) return false;

            var fromPinKey:String = getPinKey(fromPin);
            var tracks:Array = _tracksByPin[fromPinKey];

            if (tracks) {
                for each (var track:Track in tracks) {
                    if (track.fromPin === fromPin && track.toPin === toPin) {
                        return true;
                    }
                }
            }
            return false;
        }

        /**
         * Validate if connection between pins is valid
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            if (!fromPin || !toPin) return false;
            if (fromPin.type == toPin.type) return false;
            if (fromPin.parentAtom == toPin.parentAtom) return false;
            if (fromPin.type != Pin.TYPE_OUTPUT || toPin.type != Pin.TYPE_INPUT) return false;

            return !connectionExists(fromPin, toPin);
        }

        /**
         * Remove track from system
         */
        public function removeTrack(track:Track):void {
            if (!track) return;

            // Remove from main array
            var index:int = _allTracks.indexOf(track);
            if (index != -1) {
                _allTracks.splice(index, 1);
            }

            // Remove from dictionaries
            if (_tracksById[track.id]) {
                delete _tracksById[track.id];
            }
            unindexTrackByPins(track);

            // Remove visual representation
            if (track.parent) {
                track.parent.removeChild(track);
            }

            // Send impulses
            MultiPulsator.emit(new Impulse("TRACK_REMOVED", {
                track: track,
                fromPin: track.fromPin,
                toPin: track.toPin
            }));

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "ConnectionManager",
                message: "Track removed: " + track.id
            }));
        }

        /**
         * Handle track deletion request
         */
        private function onDeleteTrackRequest(impulse:Impulse):void {
            var track:Track = impulse.data.track as Track;
            if (track) {
                removeTrack(track);
            }
        }

        /**
         * Get all tracks connected to pin
         */
        public function getTracksByPin(pin:Pin):Array {
            var key:String = getPinKey(pin);
            return _tracksByPin[key] ? _tracksByPin[key].concat() : [];
        }
    }
}
