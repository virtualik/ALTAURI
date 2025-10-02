package Application.AtomLinker.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.utils.getQualifiedClassName;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Pin class - connection point for data/impulse transfer between atoms
     * Immutable class - any state change returns new Pin instance
     */
    public class Pin extends Sprite {
        public static const TYPE_INPUT:String = "In";
        public static const TYPE_OUTPUT:String = "Out";

        private var _name:String;
        private var _type:String;
        public var _parentAtom:BaseAtom;
        private var _value:* = null;
        private var _isActive:Boolean = false;
        private var _isOver:Boolean = false;
        private var _normalAlpha:Number = 1.0;
        private var _highlightAlpha:Number = 0.3;

        /**
         * Pin constructor
         * @param name - unique pin name within atom
         * @param type - pin type (TYPE_INPUT or TYPE_OUTPUT)
         * @param parentAtom - reference to parent atom
         * @param value - initial pin value (optional)
         */
        public function Pin(name:String, type:String, parentAtom:BaseAtom, value:* = null) {
            if(type != Pin.TYPE_INPUT && type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("Invalid pin type: " + type + ". Use Pin.TYPE_INPUT or Pin.TYPE_OUTPUT.");
            }
            this._name = name;
            this._type = type;
            this._parentAtom = parentAtom;
            this._value = value;
            this._isActive = (this._value !== null && this._value !== undefined);

            this.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "_name: " + _name
            }));
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "this: " + getQualifiedClassName(this).split("::").pop()
            }));
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "parentAtom: " + getQualifiedClassName(this._parentAtom).split("::").pop()
            }));

            setupInteractions();
            drawVisualState();

            MultiPulsator.subscribeToImpulse("OUTPUT_PIN_SELECTED", onOutputPinSelected);
            MultiPulsator.subscribeToImpulse("EDITOR_MOUSE_UP", onEditorMouseUp);
        }

        /**
         * Create new Pin instance with updated value
         * @param newValue - new value for pin
         * @return Pin - new Pin instance with updated value
         */
        public function setValue(newValue:*):Pin {
            var newPin:Pin = new Pin(this._name, this._type, this._parentAtom, newValue);
            newPin._isOver = this._isOver;
            newPin.alpha = this.alpha;
            newPin.x = this.x;
            newPin.y = this.y;
            while (this.numChildren > 0) {
                newPin.addChild(this.getChildAt(0));
            }
            return newPin;
        }

        /**
         * Handle output pin selection impulse
         */
        private function onOutputPinSelected(impulse:Impulse):void {
            var selectedPin:Pin = impulse.data.pin as Pin;
            if(this.type == Pin.TYPE_INPUT && selectedPin != this) {
                this.alpha = _highlightAlpha;
            }
        }

        /**
         * Handle editor mouse up impulse
         */
        private function onEditorMouseUp(impulse:Impulse):void {
            this.alpha = _normalAlpha;
        }

        /**
         * Set up mouse interactions
         */
        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.addEventListener(MouseEvent.ROLL_OVER, onRollOver);
            this.addEventListener(MouseEvent.ROLL_OUT, onRollOut);
        }

        /**
         * Handle mouse down event
         */
        private function onMouseDown(e:MouseEvent):void {
            e.stopPropagation();
            MultiPulsator.emit(new Impulse("PIN_MOUSE_DOWN", {
                pin: this,
                mouseEvent: e
            }));
        }

        /**
         * Handle roll over event
         */
        private function onRollOver(e:MouseEvent):void {
            _isOver = true;
            drawVisualState();
            if(this.type == Pin.TYPE_OUTPUT) {
                this.alpha = _highlightAlpha;
            }
        }

        /**
         * Handle roll out event
         */
        private function onRollOut(e:MouseEvent):void {
            _isOver = false;
            drawVisualState();
            if(this.type == Pin.TYPE_OUTPUT) {
                this.alpha = _normalAlpha;
            }
        }

        /**
         * Draw pin visual state
         */
        private function drawVisualState():void {
            this.graphics.clear();
            var color:uint = _isOver ? 0xFFFF00 : (_type == TYPE_INPUT ? 0xFF0000 : 0x00FF00);
            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 5);
            this.graphics.endFill();
        }

        /**
         * Handle right click event
         */
        public function onRightClick(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "RightClick on Pin Event"
            }));
        }

        /**
         * Get pin name
         */
        public override function get name():String {
            return this._name;
        }

        /**
         * Get pin type
         */
        public function get type():String {
            return this._type;
        }

        /**
         * Get parent atom
         */
        public function get parentAtom():BaseAtom {
            return this._parentAtom;
        }

        /**
         * Get pin value
         */
        public function get value():* {
            return this._value;
        }

        /**
         * Check if pin is active
         */
        public function get isActive():Boolean {
            return this._isActive;
        }

        /**
         * Get connected tracks
         * @return Array - array of connected tracks
         */
        public function getConnectedTracks():Array {
            return [];
        }

        /**
         * Check if pin is connected
         * @return Boolean - true if connected
         */
        public function isConnected():Boolean {
            return this.getConnectedTracks().length > 0;
        }

        /**
         * Get string representation
         * @return String - pin representation string
         */
        public function toStringRepresentation():String {
            return "Pin(" + this._name + ":" + this._type + ")";
        }

        /**
         * Get full pin name including parent atom
         * @return String - full pin name
         */
        public function getFullName():String {
            var parentName:String = "UnknownAtom";
            if(this._parentAtom && this._parentAtom.name) {
                parentName = this._parentAtom.name;
            } else if(this._parentAtom) {
                parentName = getQualifiedClassName(this._parentAtom).split("::").pop();
            }
            return parentName + "." + this._name;
        }
    }
}
