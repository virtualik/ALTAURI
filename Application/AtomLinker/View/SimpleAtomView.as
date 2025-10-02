package Application.AtomLinker.View {
    import flash.display.MovieClip;
    import flash.display.BitmapData;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.MouseEvent;
    import flash.events.Event;
    import flash.geom.Point;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;
    import Application.Managers.AtomManager;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.ConnectionManager;
    import Application.AtomLinker.Core.Track;

    /**
     * Simple Atom View - basic visual representation of atom
     */
    public class SimpleAtomView extends MovieClip implements IAtomView {
        private var _background:MovieClip;
        private var _label:TextField;
        private var _parentAtom:BaseAtom;
        private var _isHighlighted:Boolean = false;
        private var _isDragging:Boolean = false;
        private var _dragOffset:Point = new Point();
        private static const GRID_SIZE:int = 10;
        private static const SNAP_TO_GRID:Boolean = true;
        public static const WIDTH:Number = 100;
        public static const HEIGHT:Number = 60;

        /**
         * Simple Atom View constructor
         */
        public function SimpleAtomView() {
            super();
            createVisuals();
            setupInteractions();
        }

        /**
         * Initialize with atom
         * @param atom - parent atom
         */
        public function initWithAtom(atom:BaseAtom):void {
            _parentAtom = atom;
            updateDataFromAtom();
            updateVisuals();
        }

        /**
         * Update visual representation
         */
        public function updateVisuals():void {
            drawBackground();
            drawContacts();
        }

        /**
         * Create visual elements
         */
        private function createVisuals():void {
            _background = new MovieClip();
            addChild(_background);

            _label = new TextField();
            _label.width = WIDTH;
            _label.height = HEIGHT;
            _label.multiline = true;
            _label.wordWrap = true;
            _label.selectable = false;
            _label.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.align = "center";
            format.size = 10;
            format.color = 0xFFFFFF;
            _label.defaultTextFormat = format;
            addChild(_label);
        }

        /**
         * Set up mouse interactions
         */
        private function setupInteractions():void {
            buttonMode = true;
            useHandCursor = true;
            addEventListener(MouseEvent.CLICK, onClick);
            addEventListener(MouseEvent.ROLL_OVER, onRollOver);
            addEventListener(MouseEvent.ROLL_OUT, onRollOut);
            addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        /**
         * Update data from atom
         */
        private function updateDataFromAtom():void {
            if(_parentAtom) {
                _label.text = _parentAtom.name + "\n" + _parentAtom.type + "\n" + _parentAtom.id;
            }
        }

        /**
         * Draw background
         */
        private function drawBackground():void {
            _background.graphics.clear();
            _background.graphics.beginFill(_isHighlighted ? 0xFFAA00 : 0x00AA00, 0.7);
            _background.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            _background.graphics.endFill();
        }

        /**
         * Draw contact pins
         */
        private function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Create and position pins
         */
        private function createAndPositionPins():void {
            if(!_parentAtom) return;
            removeExistingPins();

            for(var i:int = 0; i < _parentAtom.inputContacts.length; i++) {
                var inputPin:Pin = _parentAtom.inputContacts[i];
                var inputY:Number = HEIGHT * (i + 1) / (_parentAtom.inputContacts.length + 1);
                inputPin.x = 0;
                inputPin.y = inputY;
                this.addChild(inputPin);
            }

            for(var j:int = 0; j < _parentAtom.outputContacts.length; j++) {
                var outputPin:Pin = _parentAtom.outputContacts[j];
                var outputY:Number = HEIGHT * (j + 1) / (_parentAtom.outputContacts.length + 1);
                outputPin.x = this.width;
                outputPin.y = outputY;
                this.addChild(outputPin);
            }
        }

        /**
         * Remove existing pins
         */
        private function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * Handle mouse down for dragging
         */
        private function onMouseDown(event:MouseEvent):void {
            _isDragging = true;
            _dragOffset.x = event.localX;
            _dragOffset.y = event.localY;

            stage.addEventListener(MouseEvent.MOUSE_MOVE, reactor_onMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, reactor_onMouseUp);

            onDragStart(new Point(event.localX, event.localY));
            event.stopPropagation();
        }

        /**
         * Handle mouse move during drag
         */
        private function reactor_onMouseMove(event:MouseEvent):void {
            if (_isDragging) {
                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);

                var newX:Number = localPos.x - _dragOffset.x;
                var newY:Number = localPos.y - _dragOffset.y;

                if (SNAP_TO_GRID) {
                    newX = Math.round(newX / GRID_SIZE) * GRID_SIZE;
                    newY = Math.round(newY / GRID_SIZE) * GRID_SIZE;
                }

                onDrag(new Point(newX, newY));
            }
        }

        /**
         * Handle mouse up after drag
         */
        private function reactor_onMouseUp(event:MouseEvent):void {
            if (_isDragging) {
                _isDragging = false;
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, reactor_onMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, reactor_onMouseUp);

                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);
                var newX:Number = localPos.x - _dragOffset.x;
                var newY:Number = localPos.y - _dragOffset.y;

                if (SNAP_TO_GRID) {
                    newX = Math.round(newX / GRID_SIZE) * GRID_SIZE;
                    newY = Math.round(newY / GRID_SIZE) * GRID_SIZE;
                }

                onDragEnd(new Point(newX, newY));
            }
        }

        /**
         * Handle drag start
         * @param mousePos - mouse position
         */
        public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7;
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "SimpleAtomView: Started moving atom " + _parentAtom.name
            }));
        }

        /**
         * Handle drag movement
         * @param mousePos - mouse position
         */
        public function onDrag(mousePos:Point):void {
            this.x = mousePos.x;
            this.y = mousePos.y;
            updateTracksDuringDrag();
        }

        /**
         * Update tracks during drag
         */
        private function updateTracksDuringDrag():void {
            var connectionManager:ConnectionManager = ConnectionManager.getInstance();
            if (!connectionManager) return;

            var tracks:Array = connectionManager.getTracksByAtom(_parentAtom);

            for each (var track:Track in tracks) {
                track.update();
            }

            if (stage) {
                stage.invalidate();
            }
        }

        /**
         * Handle drag end
         * @param mousePos - mouse position
         */
        public function onDragEnd(mousePos:Point):void {
            this.alpha = 1.0;

            if (_parentAtom) {
                var newPosition:Point = new Point(mousePos.x, mousePos.y);
                var newAtom:BaseAtom = _parentAtom.setPosition(newPosition);

                var atomManager:AtomManager = AtomManager.getInstance();
                if (atomManager) {
                    atomManager.updateAtom(newAtom);
                }

                MultiPulsator.emit(new Impulse("ATOM_UPDATED", {
                    oldAtom: _parentAtom,
                    newAtom: newAtom
                }));

                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    atom: newAtom,
                    oldPosition: _parentAtom.position,
                    newPosition: newPosition
                }));

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "SimpleAtomView: Atom " + _parentAtom.name + " moved to " + newPosition
                }));
            }
        }

        /**
         * Handle click
         */
        private function onClick(event:MouseEvent):void {
            toggleHighlight();
        }

        /**
         * Handle roll over
         */
        private function onRollOver(event:MouseEvent):void {
            if(!_isHighlighted) {
                _background.graphics.clear();
                _background.graphics.beginFill(0x00FF00, 0.7);
                _background.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
                _background.graphics.endFill();
            }
        }

        /**
         * Handle roll out
         */
        private function onRollOut(event:MouseEvent):void {
            if(!_isHighlighted) {
                drawBackground();
                drawContacts();
            }
        }

        /**
         * Toggle highlight state
         */
        private function toggleHighlight():void {
            _isHighlighted = !_isHighlighted;
            drawBackground();
            drawContacts();
        }

        /**
         * Get parent atom
         * @return BaseAtom - parent atom
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }

        /**
         * Handle asset load complete
         * @param assetUrl - asset URL
         * @param assetData - asset data
         */
        public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "[SimpleAtomView] Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
            }));
            if (assetData is BitmapData) {
                this.graphics.clear();
                var bitmap:flash.display.Bitmap = new flash.display.Bitmap(assetData as BitmapData);
                bitmap.x = (WIDTH - bitmap.width) / 2;
                bitmap.y = (HEIGHT - bitmap.height) / 2;
                this.addChild(bitmap);
                drawContacts();
            }
        }

        /**
         * Handle asset load error
         * @param assetUrl - asset URL
         * @param errorMessage - error message
         */
        public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "[SimpleAtomView] ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }
    }
}
