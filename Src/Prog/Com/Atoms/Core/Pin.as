package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.display.DisplayObject;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Pin - Connection point for atoms with impulse-based interaction system.
     * Represents input/output contacts and handles connection creation through impulses.
     */
    public class Pin extends Sprite {
        /** Pin type constants */
        public static const TYPE_INPUT:String = "In";
        public static const TYPE_OUTPUT:String = "Out";

        /** Pin properties */
        private var _pinName:String;
        private var _pinType:String;
        private var _parentAtom:BaseAtom;
        private var _value:* = null;
        private var _isDragging:Boolean = false;

        /**
         * Pin constructor
         * @param name Unique name of the pin within its parent atom
         * @param type Type of the pin (TYPE_INPUT or TYPE_OUTPUT)
         * @param parentAtom Reference to the atom this pin belongs to
         * @param value Optional initial value for the pin
         */
        public function Pin(name:String, type:String, parentAtom:BaseAtom, value:* = null) {
            if (type != Pin.TYPE_INPUT && type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("Invalid pin type: " + type + ". Use Pin.TYPE_INPUT or Pin.TYPE_OUTPUT.");
            }

            this._pinName = name;
            this._pinType = type;
            this._parentAtom = parentAtom;
            this._value = value;

            setupPinVisual();
            setupImpulseListeners();
        }

        /**
         * Setup pin visual representation
         */
        private function setupPinVisual():void {
            this.graphics.clear();

            // Different colors for input/output pins
            var color:uint = (_pinType == TYPE_INPUT) ? 0xFF4444 : 0x44FF44;

            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 6);
            this.graphics.endFill();

            // Add subtle border
            this.graphics.lineStyle(1, 0x000000, 0.3);
            this.graphics.drawCircle(0, 0, 6);

            this.buttonMode = true;
            this.mouseChildren = false;
        }

        /**
         * Setup impulse listeners for pin interactions
         */
        private function setupImpulseListeners():void {
            MultiPulsator.subscribeToImpulse("PIN_MOUSE_DOWN", onPinMouseDown);
        }

        /**
         * Handle pin mouse down impulse
         * @param impulse PIN_MOUSE_DOWN impulse
         */
        private function onPinMouseDown(impulse:Impulse):void {
            var targetPin:Pin = impulse.data.pin;

            // Only handle if this pin is the target and it's an output pin
            if (targetPin == this && _pinType == TYPE_OUTPUT) {
                _isDragging = true;

                // Start track creation process
                MultiPulsator.emit(new Impulse("PIN_DRAG_START", {
                    pin: this,
                    startX: impulse.data.stageX,
                    startY: impulse.data.stageY,
                    windowType: impulse.data.windowType
                }));

                // Subscribe to mouse movement and release
                MultiPulsator.subscribeToImpulse("WINDOW_MOUSE_MOVE", on_MouseMove);
                MultiPulsator.subscribeToImpulse("PIN_MOUSE_UP", onPinMouseUp);
                MultiPulsator.subscribeToImpulse("WINDOW_MOUSE_UP", onWindowMouseUp);
            }
        }

        /**
         * Handle mouse movement during drag
         * @param impulse WINDOW_MOUSE_MOVE impulse
         */
        private function on_MouseMove(impulse:Impulse):void {
            if (_isDragging) {
                MultiPulsator.emit(new Impulse("PIN_DRAG_UPDATE", {
                    pin: this,
                    currentX: impulse.data.stageX,
                    currentY: impulse.data.stageY,
                    windowType: impulse.data.windowType
                }));
            }
        }

        /**
         * Handle pin mouse up impulse
         * @param impulse PIN_MOUSE_UP impulse
         */
        private function onPinMouseUp(impulse:Impulse):void {
            if (_isDragging) {
                completeDragOperation(impulse.data.pin);
            }
        }

        /**
         * Handle window mouse up impulse (fallback)
         * @param impulse WINDOW_MOUSE_UP impulse
         */
        private function onWindowMouseUp(impulse:Impulse):void {
            if (_isDragging) {
                // If we get window mouse up but no pin target, cancel the operation
                completeDragOperation(null);
            }
        }

        /**
         * Complete drag operation and create track if valid
         * @param targetPin Potential target pin for connection
         */
        private function completeDragOperation(targetPin:Pin):void {
            _isDragging = false;

            // Unsubscribe from temporary listeners
            MultiPulsator.removeImpulse("WINDOW_MOUSE_MOVE", on_MouseMove);
            MultiPulsator.removeImpulse("PIN_MOUSE_UP", onPinMouseUp);
            MultiPulsator.removeImpulse("WINDOW_MOUSE_UP", onWindowMouseUp);

            // Emit drag end impulse
            MultiPulsator.emit(new Impulse("PIN_DRAG_END", {
                fromPin: this,
                toPin: targetPin,
                windowType: getCurrentWindowType()
            }));
        }

        /**
         * Get current window type through parent hierarchy
         * @return Current window type or "unknown"
         */
        private function getCurrentWindowType():String {
            var parent:DisplayObject = this.parent;
            while (parent) {
                if (parent.hasOwnProperty("windowType")) {
                    return parent["windowType"];
                }
                parent = parent.parent;
            }
            return "unknown";
        }

        /**
         * Create new pin instance with updated value (immutable pattern)
         * @param newValue New value for the pin
         * @return New Pin instance with updated value
         */
        public function setValue(newValue:*):Pin {
            var newPin:Pin = new Pin(_pinName, _pinType, _parentAtom, newValue);

            // Copy visual properties
            newPin.x = this.x;
            newPin.y = this.y;
            newPin.alpha = this.alpha;
            newPin.scaleX = this.scaleX;
            newPin.scaleY = this.scaleY;

            return newPin;
        }

        /**
         * Sets the parent atom for this pin.
         * @param parentAtom The parent atom to set
         */
        public function setParentAtom(parentAtom:BaseAtom):void {
            _parentAtom = parentAtom;
        }

        /**
         * Emit value change impulse to notify connected tracks
         * @param newValue New value to emit
         */
        public function emitValueChange(newValue:*):void {
            _value = newValue;

            MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED_" + _parentAtom.id + "_" + _pinName, {
                pin: this,
                value: newValue,
                atomId: _parentAtom.id,
                pinName: _pinName
            }));

            // Also emit general pin value change for global listeners
            MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
                pin: this,
                value: newValue,
                atomId: _parentAtom.id,
                pinName: _pinName
            }));
        }

        /**
         * Handle input value change from connected track
         * @param newValue New input value
         */
        public function handleInputChange(newValue:*):void {
            _value = newValue;

            // Notify parent atom about input change
            if (_parentAtom) {
                MultiPulsator.emit(new Impulse("ATOM_INPUT_CHANGED", {
                    atom: _parentAtom,
                    pin: this,
                    value: newValue
                }));
            }
        }

        /**
         * Clean up pin resources
         */
        public function dispose():void {
            MultiPulsator.removeImpulse("PIN_MOUSE_DOWN", onPinMouseDown);
            MultiPulsator.removeImpulse("WINDOW_MOUSE_MOVE", on_MouseMove);
            MultiPulsator.removeImpulse("PIN_MOUSE_UP", onPinMouseUp);
            MultiPulsator.removeImpulse("WINDOW_MOUSE_UP", onWindowMouseUp);

            this.graphics.clear();
            _parentAtom = null;
        }

        // =========================================================================
        // PUBLIC GETTERS
        // =========================================================================

        /**
         * Get pin name
         * @return Pin name
         */
        public function get pinName():String {
            return _pinName;
        }

        /**
         * Get pin type
         * @return Pin type (TYPE_INPUT or TYPE_OUTPUT)
         */
        public function get pinType():String {
            return _pinType;
        }

        /**
         * Get parent atom
         * @return Parent BaseAtom instance
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }

        /**
         * Get current pin value
         * @return Current pin value
         */
        public function get value():* {
            return _value;
        }

        /**
         * Check if pin has active value
         * @return True if pin has non-null value
         */
        public function get isActive():Boolean {
            return _value !== null && _value !== undefined;
        }

        /**
         * Get string representation for debugging
         * @return String representation of pin
         */
        public function toStringRepresentation():String {
            var atomName:String = _parentAtom ? _parentAtom.name : "UnknownAtom";
            return "Pin(" + atomName + "." + _pinName + ":" + _pinType + ")";
        }

        /**
         * Get full pin identifier
         * @return Full pin identifier string
         */
        public function getFullName():String {
            var parentName:String = _parentAtom ? _parentAtom.name : "UnknownAtom";
            return parentName + "." + _pinName;
        }
    }
}
