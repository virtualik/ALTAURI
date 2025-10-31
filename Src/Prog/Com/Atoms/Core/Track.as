package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.utils.setTimeout;

    /**
     * Track - Visual and logical connection between two pins.
     * Handles data flow between output and input pins with automatic updates.
     */
    public class Track extends Sprite {
        /** Connected pins */
        private var _fromPin:Pin;
        private var _toPin:Pin;
        
        /** Track properties */
        private var _connectionId:String;
        private var _isActive:Boolean = false;

        /**
         * Track constructor
         * @param fromPin Source pin (output)
         * @param toPin Target pin (input)
         */
        public function Track(fromPin:Pin, toPin:Pin) {
            if (fromPin.pinType != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("From pin must be OUTPUT type");
            }
            if (toPin.pinType != Pin.TYPE_INPUT) {
                throw new ArgumentError("To pin must be INPUT type");
            }
            
            _fromPin = fromPin;
            _toPin = toPin;
            _connectionId = generateConnectionId();
            
            drawTrack();
            setupImpulseListeners();
        }

        /**
         * Generate unique connection identifier
         * @return Unique connection ID string
         */
        private function generateConnectionId():String {
            return "track_" + _fromPin.parentAtom.id + "_" + _fromPin.pinName + 
                   "_to_" + _toPin.parentAtom.id + "_" + _toPin.pinName;
        }

        /**
         * Setup impulse listeners for track functionality
         */
        private function setupImpulseListeners():void {
            // Listen for atom movements to update visual
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            
            // Listen for source pin value changes
            var sourceImpulseKey:String = "PIN_VALUE_CHANGED_" + _fromPin.parentAtom.id + "_" + _fromPin.pinName;
            MultiPulsator.subscribeToImpulse(sourceImpulseKey, onSourceValueChanged);
            
            // Listen for track-specific impulses
            MultiPulsator.subscribeToImpulse("TRACK_UPDATE_REQUEST", onTrackUpdateRequest);
        }

        /**
         * Create logical connection between pins
         */
        public function createLogicalConnection():void {
            _isActive = true;
            
            // Initial value transfer
            if (_fromPin.value !== null) {
                transferValue(_fromPin.value);
            }
            
            MultiPulsator.emit(new Impulse("TRACK_CONNECTED", {
                track: this,
                fromPin: _fromPin,
                toPin: _toPin,
                connectionId: _connectionId
            }));
        }

        /**
         * Handle atom movement to update track visual
         * @param impulse ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:BaseAtom = impulse.data.newAtom;
            if (movedAtom.id == _fromPin.parentAtom.id || movedAtom.id == _toPin.parentAtom.id) {
                drawTrack();
                
                MultiPulsator.emit(new Impulse("TRACK_UPDATED", {
                    track: this,
                    reason: "atom_moved"
                }));
            }
        }

        /**
         * Handle source pin value changes
         * @param impulse PIN_VALUE_CHANGED impulse
         */
        private function onSourceValueChanged(impulse:Impulse):void {
            var newValue:* = impulse.data.value;
            transferValue(newValue);
            
            // Visual feedback for active data transfer
            showDataFlowFeedback();
        }

        /**
         * Handle track update requests
         * @param impulse TRACK_UPDATE_REQUEST impulse
         */
        private function onTrackUpdateRequest(impulse:Impulse):void {
            if (impulse.data.track == this || impulse.data.connectionId == _connectionId) {
                drawTrack();
            }
        }

        /**
         * Transfer value from source to target pin
         * @param value Value to transfer
         */
        private function transferValue(value:*):void {
            // Emit input change to target pin
            MultiPulsator.emit(new Impulse("PIN_INPUT_CHANGE_" + _toPin.parentAtom.id + "_" + _toPin.pinName, {
                value: value,
                sourceTrack: this,
                sourcePin: _fromPin
            }));
            
            // Also update the pin directly for immediate feedback
            _toPin.handleInputChange(value);
        }

        /**
         * Show visual feedback for data flow
         */
        private function showDataFlowFeedback():void {
            // Temporary visual effect for data flow
            this.alpha = 1.0;
            
            // You could add more sophisticated animations here
            // For now, just reset alpha after short delay
            setTimeout(function():void {
                if (parent) { // Check if still in display list
                    alpha = 0.7;
                }
            }, 200);
        }

        /**
         * Draw or update track visual representation
         */
        public function drawTrack():void {
            this.graphics.clear();
            
            var fromPos:Point = getGlobalPinPosition(_fromPin);
            var toPos:Point = getGlobalPinPosition(_toPin);
            
            // Convert to local coordinates of this track sprite
            var localFrom:Point = this.globalToLocal(fromPos);
            var localTo:Point = this.globalToLocal(toPos);
            
            // Draw track line
            var lineColor:uint = _isActive ? 0x00FF00 : 0x666666;
            var lineAlpha:Number = _isActive ? 0.7 : 0.4;
            var lineThickness:Number = _isActive ? 2 : 1;
            
            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);
            
            // Add arrowhead for direction indication
            drawArrowhead(localFrom, localTo);
        }

        /**
         * Draw direction arrowhead on track
         * @param from Start point
         * @param to End point
         */
        private function drawArrowhead(from:Point, to:Point):void {
            var length:Number = Point.distance(from, to);
            if (length < 20) return; // Don't draw arrowhead for very short tracks
            
            var angle:Number = Math.atan2(to.y - from.y, to.x - from.x);
            var arrowSize:Number = 6;
            
            // Calculate arrowhead points
            var arrow1:Point = new Point(
                to.x - arrowSize * Math.cos(angle - Math.PI/6),
                to.y - arrowSize * Math.sin(angle - Math.PI/6)
            );
            var arrow2:Point = new Point(
                to.x - arrowSize * Math.cos(angle + Math.PI/6),
                to.y - arrowSize * Math.sin(angle + Math.PI/6)
            );
            
            // Draw arrowhead
            this.graphics.lineStyle(1, 0x00FF00, 0.7);
            this.graphics.moveTo(to.x, to.y);
            this.graphics.lineTo(arrow1.x, arrow1.y);
            this.graphics.moveTo(to.x, to.y);
            this.graphics.lineTo(arrow2.x, arrow2.y);
        }

        /**
         * Get global position of a pin
         * @param pin Pin to get position for
         * @return Global position point
         */
        private function getGlobalPinPosition(pin:Pin):Point {
            return pin.localToGlobal(new Point(0, 0));
        }

        /**
         * Update track visual (alias for drawTrack)
         */
        public function updateVisual():void {
            drawTrack();
        }

        /**
         * Check if track is connected to specific atom
         * @param atomId Atom ID to check
         * @return True if connected to atom
         */
        public function isConnectedToAtom(atomId:String):Boolean {
            return _fromPin.parentAtom.id == atomId || _toPin.parentAtom.id == atomId;
        }

        /**
         * Check if track is connected to specific pin
         * @param pin Pin to check
         * @return True if connected to pin
         */
        public function isConnectedToPin(pin:Pin):Boolean {
            return _fromPin == pin || _toPin == pin;
        }

        /**
         * Get connection information
         * @return Connection info object
         */
        public function getConnectionInfo():Object {
            return {
                fromAtom: _fromPin.parentAtom.id,
                fromPin: _fromPin.pinName,
                toAtom: _toPin.parentAtom.id,
                toPin: _toPin.pinName,
                connectionId: _connectionId,
                isActive: _isActive
            };
        }

        /**
         * Clean up track resources
         */
        public function dispose():void {
            _isActive = false;
            
            // Remove all impulse listeners
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            
            var sourceImpulseKey:String = "PIN_VALUE_CHANGED_" + _fromPin.parentAtom.id + "_" + _fromPin.pinName;
            MultiPulsator.removeImpulse(sourceImpulseKey, onSourceValueChanged);
            
            MultiPulsator.removeImpulse("TRACK_UPDATE_REQUEST", onTrackUpdateRequest);
            
            // Emit disconnect impulse
            MultiPulsator.emit(new Impulse("TRACK_DISCONNECTED", {
                track: this,
                connectionId: _connectionId
            }));
            
            // Clear graphics
            this.graphics.clear();
            
            _fromPin = null;
            _toPin = null;
            
            if (parent) {
                parent.removeChild(this);
            }
        }

        // =========================================================================
        // PUBLIC GETTERS
        // =========================================================================

        /**
         * Get source pin
         * @return From pin (output)
         */
        public function get fromPin():Pin {
            return _fromPin;
        }

        /**
         * Get target pin
         * @return To pin (input)
         */
        public function get toPin():Pin {
            return _toPin;
        }

        /**
         * Get connection ID
         * @return Unique connection identifier
         */
        public function get connectionId():String {
            return _connectionId;
        }

        /**
         * Get track active state
         * @return True if track is active
         */
        public function get isActive():Boolean {
            return _isActive;
        }
    }
}
