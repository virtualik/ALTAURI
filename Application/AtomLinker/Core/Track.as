package Application.AtomLinker.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Application.AtomLinker.Core.Pin;
    import Application.Managers.AtomManager;
    import Application.Managers.ConnectionManager;
    import flash.events.MouseEvent;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Track class - visual and logical connection between pins
     * Handles visual display and value transfer between pins
     */
    public class Track extends Sprite {
        private var _fromPin:Pin;
        private var _toPin:Pin;
        private var _id:String;

        /**
         * Track constructor
         * @param fromPin - source pin
         * @param toPin - target pin
         */
        public function Track(fromPin:Pin, toPin:Pin) {
            _fromPin = fromPin;
            _toPin = toPin;
            _id = generateTrackId();

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "[Track] Created track " + _id + " from " +
                        (fromPin ? fromPin.name : "null") + " to " +
                        (toPin ? toPin.name : "null")
            }));

            setupInteractions();
            draw();
        }

        /**
         * Set up mouse interactions
         */
        private function setupInteractions():void {
            this.buttonMode = true;
            this.doubleClickEnabled = true;
            this.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            this.addEventListener(MouseEvent.CLICK, onClick);
            this.addEventListener(MouseEvent.ROLL_OVER, onRollOver);
            this.addEventListener(MouseEvent.ROLL_OUT, onRollOut);
        }

        /**
         * Handle right click event
         */
        private function onRightClick(event:MouseEvent):void {
            event.stopPropagation();

            MultiPulsator.emit(new Impulse("TRACK_RIGHT_CLICK", {
                track: this,
                fromPin: _fromPin,
                toPin: _toPin,
                mouseEvent: event
            }));

            highlight(true);
        }

        /**
         * Handle click event
         */
        private function onClick(event:MouseEvent):void {
            highlight(false);
        }

        /**
         * Handle roll over event
         */
        private function onRollOver(event:MouseEvent):void {
            this.alpha = 0.8;
        }

        /**
         * Handle roll out event
         */
        private function onRollOut(event:MouseEvent):void {
            this.alpha = 1.0;
            highlight(false);
        }

        /**
         * Highlight track
         * @param isHighlighted - highlight state
         */
        private function highlight(isHighlighted:Boolean):void {
            if(isHighlighted) {
                this.graphics.lineStyle(5, 0xFF6600, 1.0);
            }
            else {
                this.graphics.lineStyle(5, 0x111111, 1.0);
            }
            redraw();
        }

        /**
         * Redraw track
         */
        private function redraw():void {
            draw();
        }

        /**
         * Generate unique track ID
         * @return String - unique track identifier
         */
        private function generateTrackId():String {
            return "track_" + new Date().getTime() + "_" + Math.random().toString().substr(2, 6);
        }

        /**
         * Transfer value from source to target pin
         * Initiates creation of new object versions through ConnectionManager
         */
        public function transferValue():void {
            if(_fromPin && _toPin) {
                var newValue:* = _fromPin.value;
                var connectionManager:ConnectionManager = ConnectionManager.getInstance();
            }
        }

        /**
         * Draw visual representation of track
         */
        public function draw():void {
            this.graphics.clear();
            this.graphics.lineStyle(7, 0x111111, 1.0);
            var startPos:Point = getLocalPinPosition(_fromPin);
            var endPos:Point = getLocalPinPosition(_toPin);
            this.graphics.moveTo(startPos.x, startPos.y);
            this.graphics.lineTo(endPos.x, endPos.y);

            this.graphics.lineStyle(3, 0x111111, 1.0);
            this.graphics.beginFill(0xFFFFFC);
            this.graphics.drawCircle(startPos.x, startPos.y, 5);
            this.graphics.drawCircle(endPos.x, endPos.y, 5);
            this.graphics.endFill();
        }

        /**
         * Get local pin position relative to drawing surface
         * @param pin - pin to get position for
         * @return Point - local position
         */
        private function getLocalPinPosition(pin:Pin):Point {
            if(!pin || !pin.parentAtom || !pin.parentAtom.displayObject) {
                return new Point(0, 0);
            }
            var pinLocalX:Number = pin.x;
            var pinLocalY:Number = pin.y;
            var atomX:Number = pin.parentAtom.displayObject.x;
            var atomY:Number = pin.parentAtom.displayObject.y;
            return new Point(atomX + pinLocalX, atomY + pinLocalY);
        }

        /**
         * Update track position (e.g. when atoms move)
         */
        public function update():void {
            draw();
        }

        /**
         * Get track ID
         */
        public function get id():String {
            return _id;
        }

        /**
         * Get source pin
         */
        public function get fromPin():Pin {
            return _fromPin;
        }

        /**
         * Get target pin
         */
        public function get toPin():Pin {
            return _toPin;
        }
    }
}
