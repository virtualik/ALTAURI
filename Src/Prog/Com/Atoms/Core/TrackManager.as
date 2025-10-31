package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Core.Managers.WindowsManager;

    /**
     * TrackManager - Centralized manager for track creation and lifecycle management.
     * Handles the complete track creation process from pin interactions to visual representation.
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
         * @return TrackManager singleton instance
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

        /**
         * Handle pin drag start impulse
         * @param impulse PIN_DRAG_START impulse
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
         * @param impulse PIN_DRAG_UPDATE impulse
         */
        private function onPinDragUpdate(impulse:Impulse):void {
            if (_tempTrack && _currentDragPin) {
                updateTempTrack(impulse.data.currentX, impulse.data.currentY);
            }
        }

        /**
         * Handle pin drag end impulse
         * @param impulse PIN_DRAG_END impulse
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

        /**
         * Start temporary track visualization
         * @param startX Starting X coordinate
         * @param startY Starting Y coordinate
         */
        private function startTempTrack(startX:Number, startY:Number):void {
            _tempTrack = new Sprite();
            
            if (_currentWindow && _currentWindow.overlayLayer) {
                _currentWindow.overlayLayer.addChild(_tempTrack);
                updateTempTrack(startX, startY);
            }
        }

        /**
         * Update temporary track during drag operation
         * @param currentX Current mouse X coordinate
         * @param currentY Current mouse Y coordinate
         */
        private function updateTempTrack(currentX:Number, currentY:Number):void {
            if (!_tempTrack || !_currentDragPin || !_currentWindow) return;
            
            var fromPos:Point = _currentDragPin.localToGlobal(new Point(0, 0));
            
            _tempTrack.graphics.clear();
            _tempTrack.graphics.lineStyle(2, 0x00FF00, 0.8);
            _tempTrack.graphics.moveTo(fromPos.x, fromPos.y);
            _tempTrack.graphics.lineTo(currentX, currentY);
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

        /**
         * Validate connection between pins
         * @param fromPin Source pin (must be output)
         * @param toPin Target pin (must be input)
         * @return True if connection is valid
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            return toPin && 
                   toPin.pinType == Pin.TYPE_INPUT && 
                   toPin.parentAtom != fromPin.parentAtom &&
                   !connectionExists(fromPin, toPin);
        }

        /**
         * Check if connection already exists
         * @param fromPin Source pin
         * @param toPin Target pin
         * @return True if connection already exists
         */
        private function connectionExists(fromPin:Pin, toPin:Pin):Boolean {
            var connectionId:String = generateConnectionId(fromPin, toPin);
            return _activeTracks[connectionId] != null;
        }

        /**
         * Create a new track between pins
         * @param fromPin Source pin
         * @param toPin Target pin
         */
        private function createTrack(fromPin:Pin, toPin:Pin):void {
            try {
                var track:Track = new Track(fromPin, toPin);
                var connectionId:String = generateConnectionId(fromPin, toPin);
                
                // Add to content layer of current window
                if (_currentWindow && _currentWindow.contentLayer) {
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

        /**
         * Handle atom movement to update connected tracks
         * @param impulse ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:BaseAtom = impulse.data.newAtom;
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
         * @param impulse WINDOW_ACTIVATED impulse
         */
        private function onWindowActivated(impulse:Impulse):void {
            _currentWindow = impulse.data.window;
        }

        /**
         * Handle window closing to cleanup tracks
         * @param impulse WINDOW_CLOSING impulse
         */
        private function onWindowClosing(impulse:Impulse):void {
            var closingWindow:Window = impulse.data.window;
            var windowType:String = closingWindow.windowType;
            
            // Remove tracks associated with this window
            cleanupTracksByWindow(windowType);
        }

        /**
         * Handle track disconnect command
         * @param impulse TRACK_DISCONNECT impulse
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
         * @param impulse TRACK_UPDATE_ALL impulse
         */
        private function onTrackUpdateAll(impulse:Impulse):void {
            for each (var track:Track in _activeTracks) {
                track.updateVisual();
            }
        }

        /**
         * Generate unique connection ID
         * @param fromPin Source pin
         * @param toPin Target pin
         * @return Unique connection identifier
         */
        private function generateConnectionId(fromPin:Pin, toPin:Pin):String {
            return "track_" + fromPin.parentAtom.id + "_" + fromPin.pinName + 
                   "_to_" + toPin.parentAtom.id + "_" + toPin.pinName;
        }

        /**
         * Find window by type
         * @param windowType Window type to find
         * @return Found window or null
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
         * @param windowType Window type to cleanup
         */
        private function cleanupTracksByWindow(windowType:String):void {
            // Implementation depends on track-window association strategy
            // For now, we'll keep it simple and not remove tracks based on window
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Remove track by track instance
         * @param track Track to remove
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
         * @param connectionId Connection ID to remove
         */
        public function removeTrackById(connectionId:String):void {
            var track:Track = _activeTracks[connectionId];
            if (track) {
                removeTrack(track);
            }
        }

        /**
         * Get all active tracks
         * @return Object of active tracks
         */
        public function getActiveTracks():Object {
            return _activeTracks;
        }

        /**
         * Get track by connection ID
         * @param connectionId Connection ID to find
         * @return Found track or null
         */
        public function getTrackById(connectionId:String):Track {
            return _activeTracks[connectionId];
        }

        /**
         * Get tracks connected to specific atom
         * @param atomId Atom ID to find connections for
         * @return Array of connected tracks
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
         * @param pin Pin to find connections for
         * @return Array of connected tracks
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
