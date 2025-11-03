package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Window;

    /**
     * Track - Visual and logical connection between two pins
     * Handles data flow between output and input pins with automatic updates
     * 
     * @class Track
     * @public
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
         * 
         * @public
         * @param {Pin} fromPin - Source pin (output)
         * @param {Pin} toPin - Target pin (input)
         */
        public function Track(fromPin:Pin, toPin:Pin) {
            if (fromPin.type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("From pin must be OUTPUT type");
            }
            if (toPin.type != Pin.TYPE_INPUT) {
                throw new ArgumentError("To pin must be INPUT type");
            }

            _fromPin = fromPin;
            _toPin = toPin;
            _connectionId = generateConnectionId();

            // Make track interactive for right-click
            this.mouseEnabled = true;
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);

            setupImpulseListeners();

            // Draw when added to stage
            this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        /**
         * Handle right mouse down event - emit impulse for context menu
         * 
         * @private
         * @param {MouseEvent} event - Right mouse down event
         */
        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();

            // Emit impulse for menu system
            MultiPulsator.emit(new Impulse("TRACK_RIGHT_CLICK", {
                track: this,
                globalPosition: new Point(event.stageX, event.stageY),
                window: this.stage ? this.stage.nativeWindow as Window : null,
                connectionId: _connectionId
            }));
        }

        // =========================================================================
        // INITIALIZATION METHODS
        // =========================================================================

        /**
         * Generate unique connection identifier
         * 
         * @private
         * @return {String} Unique connection ID string
         */
        private function generateConnectionId():String {
            var fromAtom:Atom = getAtomByPin(_fromPin);
            var toAtom:Atom = getAtomByPin(_toPin);

            if (!fromAtom || !toAtom) {
                return "track_invalid_" + Math.random();
            }

            return "track_" + fromAtom.id + "_" + _fromPin.name +
                   "_to_" + toAtom.id + "_" + _toPin.name;
        }

        /**
         * Setup impulse listeners for track functionality
         * 
         * @private
         */
        private function setupImpulseListeners():void {
            // Listen for atom movements to update visual
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);

            // Listen for source pin value changes
            MultiPulsator.subscribeToImpulse("PIN_VALUE_CHANGED", onPinValueChanged);
        }

        /**
         * Handler when track is added to stage
         * 
         * @private
         * @param {Event} event - ADDED_TO_STAGE event
         */
        private function onAddedToStage(event:Event):void {
            this.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            drawTrack();
        }

        /**
         * Create logical connection between pins
         * 
         * @public
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

        // =========================================================================
        // EVENT HANDLERS
        // =========================================================================

        /**
         * Handle atom movement to update track visual
         * 
         * @private
         * @param {Impulse} impulse - ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:Atom = impulse.data.newAtom;
            var atomId:String = movedAtom.id;

            var fromAtom:Atom = getAtomByPin(_fromPin);
            var toAtom:Atom = getAtomByPin(_toPin);

            if ((fromAtom && fromAtom.id == atomId) || (toAtom && toAtom.id == atomId)) {
                drawTrack();

                MultiPulsator.emit(new Impulse("TRACK_UPDATED", {
                    track: this,
                    reason: "atom_moved"
                }));
            }
        }

        /**
         * Handle pin value changes from connected atoms
         * 
         * @private
         * @param {Impulse} impulse - PIN_VALUE_CHANGED impulse
         */
        private function onPinValueChanged(impulse:Impulse):void {
            var atomId:String = impulse.data.atomId;
            var pinName:String = impulse.data.pinName;
            var newValue:* = impulse.data.newValue;

            var fromAtom:Atom = getAtomByPin(_fromPin);

            // Check if this value change is from our source pin
            if (fromAtom && fromAtom.id == atomId && _fromPin.name == pinName) {
                transferValue(newValue);
            }
        }

        // =========================================================================
        // DATA FLOW METHODS
        // =========================================================================

        /**
         * Transfer value from source to target pin
         * 
         * @private
         * @param {*} value - Value to transfer
         */
        private function transferValue(value:*):void {
            // Update the target pin value directly
            _toPin.value = value;

            // Notify the target atom about input change
            var toAtom:Atom = getAtomByPin(_toPin);
            if (toAtom) {
                MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
                    atomId: toAtom.id,
                    pinName: _toPin.name,
                    newValue: value,
                    sourceTrack: this,
                    sourcePin: _fromPin
                }));
            }
        }

        // =========================================================================
        // VISUALIZATION METHODS
        // =========================================================================

        /**
         * Draw or update track visual representation
         * 
         * @public
         */
        public function drawTrack():void {
            this.graphics.clear();

            var fromPos:Point = getGlobalPinPosition(_fromPin);
            var toPos:Point = getGlobalPinPosition(_toPin);

            // Defer drawing if not yet added to stage
            if (!this.parent) {
                this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
                return;
            }

            var tracksLayer:Sprite = this.parent as Sprite;
            var localFrom:Point = tracksLayer.globalToLocal(fromPos);
            var localTo:Point = tracksLayer.globalToLocal(toPos);

            // Validate coordinates
            if (isNaN(localFrom.x) || isNaN(localFrom.y) || isNaN(localTo.x) || isNaN(localTo.y)) {
                return;
            }

            // Draw track line
            var lineColor:uint = 0x777777;
            var lineAlpha:Number = 0.5;
            var lineThickness:Number = _isActive ? 2 : 1;

            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);

            // Add arrowhead for direction indication
            drawArrowhead(localFrom, localTo);
        }

        /**
         * Draw direction arrowhead on track
         * 
         * @private
         * @param {Point} from - Start point
         * @param {Point} to - End point
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
         * Update track visual (alias for drawTrack)
         * 
         * @public
         */
        public function updateVisual():void {
            drawTrack();
        }

        // =========================================================================
        // PIN POSITION CALCULATION METHODS
        // =========================================================================

        /**
         * Get global position of a pin
         * 
         * @private
         * @param {Pin} pin - Pin to get position for
         * @return {Point} Global position point
         */
        private function getGlobalPinPosition(pin:Pin):Point {
            // Find PinView
            var pinView:PinView = findPinView(pin);
            if (pinView && pinView.stage) {
                return pinView.localToGlobal(new Point(0, 0));
            }

            // Fallback: use atom position
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

            return new Point(100, 100); // Fallback
        }

        /**
         * Find the PinView for a given Pin
         * 
         * @private
         * @param {Pin} pin - Pin to find view for
         * @return {PinView} Found PinView or null
         */
        private function findPinView(pin:Pin):PinView {
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
         * @private
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
         * 
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
        // PUBLIC API
        // =========================================================================

        /**
         * Check if track is connected to specific atom
         * 
         * @public
         * @param {String} atomId - Atom ID to check
         * @return {Boolean} True if connected to atom
         */
        public function isConnectedToAtom(atomId:String):Boolean {
            return _connectionId.indexOf(atomId) !== -1;
        }

        /**
         * Check if track is connected to specific pin
         * 
         * @public
         * @param {Pin} pin - Pin to check
         * @return {Boolean} True if connected to pin
         */
        public function isConnectedToPin(pin:Pin):Boolean {
            return _fromPin == pin || _toPin == pin;
        }

        /**
         * Get connection information
         * 
         * @public
         * @return {Object} Connection info object
         */
        public function getConnectionInfo():Object {
            var fromAtom:Atom = getAtomByPin(_fromPin);
            var toAtom:Atom = getAtomByPin(_toPin);

            return {
                fromAtom: fromAtom ? fromAtom.id : "unknown",
                fromPin: _fromPin.name,
                toAtom: toAtom ? toAtom.id : "unknown",
                toPin: _toPin.name,
                connectionId: _connectionId,
                isActive: _isActive
            };
        }

        /**
         * Clean up track resources
         * 
         * @public
         */
        public function dispose():void {
            _isActive = false;

            // Remove all impulse listeners
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("PIN_VALUE_CHANGED", onPinValueChanged);

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
         * 
         * @public
         * @return {Pin} From pin (output)
         */
        public function get fromPin():Pin {
            return _fromPin;
        }

        /**
         * Get target pin
         * 
         * @public
         * @return {Pin} To pin (input)
         */
        public function get toPin():Pin {
            return _toPin;
        }

        /**
         * Get connection ID
         * 
         * @public
         * @return {String} Unique connection identifier
         */
        public function get connectionId():String {
            return _connectionId;
        }

        /**
         * Get track active state
         * 
         * @public
         * @return {Boolean} True if track is active
         */
        public function get isActive():Boolean {
            return _isActive;
        }
    }
}
