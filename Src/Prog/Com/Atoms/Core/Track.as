package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Window;

    /**
     * Track - Visual and logical connection between two pins
     * Uses TrackManager for all pin and atom related operations
     * 
     * @class Track
     * @public
     */
    public class Track extends Sprite {
        private var _fromPin:Pin;
        private var _toPin:Pin;
        private var _connectionId:String;
        private var _isActive:Boolean = false;
        private var _trackManager:TrackManager;

        /**
         * Track constructor
         * 
         * @public
         * @param {Pin} fromPin - Source pin (output)
         * @param {Pin} toPin - Target pin (input)
         * @param {TrackManager} trackManager - Reference to track manager for shared operations
         */
        public function Track(fromPin:Pin, toPin:Pin, trackManager:TrackManager) {
            if (fromPin.type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("From pin must be OUTPUT type");
            }
            if (toPin.type != Pin.TYPE_INPUT) {
                throw new ArgumentError("To pin must be INPUT type");
            }

            _fromPin = fromPin;
            _toPin = toPin;
            _trackManager = trackManager;
            _connectionId = generateConnectionId();

            this.mouseEnabled = true;
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            setupImpulseListeners();
            this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        // =========================================================================
        // INITIALIZATION METHODS
        // =========================================================================

        private function generateConnectionId():String {
            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);

            if (!fromAtom || !toAtom) {
                return "track_invalid_" + Math.random();
            }

            return "track_" + fromAtom.id + "_" + _fromPin.name +
                   "_to_" + toAtom.id + "_" + _toPin.name;
        }

        private function setupImpulseListeners():void {
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.subscribeToImpulse("PIN_VALUE_CHANGED", onPinValueChanged);
        }

        private function onAddedToStage(event:Event):void {
            this.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            drawTrack();
        }

        // =========================================================================
        // EVENT HANDLERS
        // =========================================================================

        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            MultiPulsator.emit(new Impulse("TRACK_RIGHT_CLICK", {
                track: this,
                globalPosition: new Point(event.stageX, event.stageY),
                window: this.stage ? this.stage.nativeWindow as Window : null,
                connectionId: _connectionId
            }));
        }

        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:Atom = impulse.data.newAtom;
            var atomId:String = movedAtom.id;

            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);

            if ((fromAtom && fromAtom.id == atomId) || (toAtom && toAtom.id == atomId)) {
                drawTrack();
                MultiPulsator.emit(new Impulse("TRACK_UPDATED", {
                    track: this,
                    reason: "atom_moved"
                }));
            }
        }

        private function onPinValueChanged(impulse:Impulse):void {
            var atomId:String = impulse.data.atomId;
            var pinName:String = impulse.data.pinName;
            var newValue:* = impulse.data.newValue;

            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            if (fromAtom && fromAtom.id == atomId && _fromPin.name == pinName) {
                transferValue(newValue);
            }
        }

        // =========================================================================
        // DATA FLOW AND VISUALIZATION
        // =========================================================================

        public function createLogicalConnection():void {
            _isActive = true;
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

        private function transferValue(value:*):void {
            _toPin.value = value;
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);
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

        public function drawTrack():void {
            this.graphics.clear();

            var fromPos:Point = _trackManager.getGlobalPinPosition(_fromPin);
            var toPos:Point = _trackManager.getGlobalPinPosition(_toPin);

            if (!this.parent) {
                this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
                return;
            }

            var tracksLayer:Sprite = this.parent as Sprite;
            var localFrom:Point = tracksLayer.globalToLocal(fromPos);
            var localTo:Point = tracksLayer.globalToLocal(toPos);

            if (isNaN(localFrom.x) || isNaN(localFrom.y) || isNaN(localTo.x) || isNaN(localTo.y)) {
                return;
            }

            var lineColor:uint = 0x777777;
            var lineAlpha:Number = 0.5;
            var lineThickness:Number = _isActive ? 5 : 3;

            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);

            drawArrowhead(localFrom, localTo);
        }

        private function drawArrowhead(from:Point, to:Point):void {
            var length:Number = Point.distance(from, to);
            if (length < 20) return;

            var angle:Number = Math.atan2(to.y - from.y, to.x - from.x);
            var arrowSize:Number = 6;

            var arrow1:Point = new Point(
                to.x - arrowSize * Math.cos(angle - Math.PI/6),
                to.y - arrowSize * Math.sin(angle - Math.PI/6)
            );
            var arrow2:Point = new Point(
                to.x - arrowSize * Math.cos(angle + Math.PI/6),
                to.y - arrowSize * Math.sin(angle + Math.PI/6)
            );

            this.graphics.lineStyle(1, 0x00FF00, 0.7);
            this.graphics.moveTo(to.x, to.y);
            this.graphics.lineTo(arrow1.x, arrow1.y);
            this.graphics.moveTo(to.x, to.y);
            this.graphics.lineTo(arrow2.x, arrow2.y);
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        public function updateVisual():void { drawTrack(); }

        public function isConnectedToAtom(atomId:String):Boolean {
            return _connectionId.indexOf(atomId) !== -1;
        }

        public function isConnectedToPin(pin:Pin):Boolean {
            return _fromPin == pin || _toPin == pin;
        }

        public function getConnectionInfo():Object {
            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);

            return {
                fromAtom: fromAtom ? fromAtom.id : "unknown",
                fromPin: _fromPin.name,
                toAtom: toAtom ? toAtom.id : "unknown",
                toPin: _toPin.name,
                connectionId: _connectionId,
                isActive: _isActive
            };
        }

        public function dispose():void {
            _isActive = false;
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("PIN_VALUE_CHANGED", onPinValueChanged);
            MultiPulsator.emit(new Impulse("TRACK_DISCONNECTED", {
                track: this,
                connectionId: _connectionId
            }));
            this.graphics.clear();
            _fromPin = null;
            _toPin = null;
            if (parent) parent.removeChild(this);
        }

        // =========================================================================
        // PUBLIC GETTERS
        // =========================================================================

        public function get fromPin():Pin { return _fromPin; }
        public function get toPin():Pin { return _toPin; }
        public function get connectionId():String { return _connectionId; }
        public function get isActive():Boolean { return _isActive; }
    }
}
