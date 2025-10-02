package Application.AtomLinker.View {
    import flash.display.MovieClip;
    import flash.display.BitmapData;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.AtomICScript.behaviors.ButtonAtomBehavior;
    import Application.Managers.AtomManager;
    import Application.Managers.ConnectionManager;
    import Application.AtomLinker.Core.Track;

    /**
     * Button Atom View - visual representation of button atom
     */
    public class ButtonAtomView extends MovieClip implements IAtomView {
        private var _behavior:ButtonAtomBehavior = new ButtonAtomBehavior();
        private var _pressed:Boolean = false;
        private var _nameLabel:TextField;
        private var _parentAtom:BaseAtom;
        private var _isDragging:Boolean = false;
        private var _dragOffset:Point = new Point();
        private static const GRID_SIZE:int = 10;
        private static const SNAP_TO_GRID:Boolean = true;
        private static const WIDTH:Number = 80;
        private static const HEIGHT:Number = 30;

        /**
         * Button Atom View constructor
         */
        public function ButtonAtomView() {
            super();
            createNameLabel();
            drawButton();
            setupInteractions();
        }

        /**
         * Initialize with atom
         * @param atom - parent atom
         */
        public function initWithAtom(atom:BaseAtom):void {
            _parentAtom = atom;
            updateLabel();
            updateVisuals();
        }

        /**
         * Update visual representation
         */
        public function updateVisuals():void {
            drawButton();
            drawContacts();
        }

        /**
         * Create name label
         */
        private function createNameLabel():void {
            _nameLabel = new TextField();
            _nameLabel.width = WIDTH;
            _nameLabel.height = HEIGHT;
            _nameLabel.y = 10;
            _nameLabel.selectable = false;
            _nameLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0x333333;
            _nameLabel.defaultTextFormat = format;
            this.addChild(_nameLabel);
        }

        /**
         * Set up mouse interactions
         */
        private function setupInteractions():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onPress);
            this.addEventListener(MouseEvent.MOUSE_UP, onRelease);
            this.addEventListener(MouseEvent.ROLL_OUT, onRollOutVisual);
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        /**
         * Update label text
         */
        private function updateLabel():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * Draw button background
         */
        private function drawButton():void {
            this.graphics.clear();
            var color:uint = _pressed ? 0x27AE60 : 0x2ECC71;
            this.graphics.beginFill(color);
            this.graphics.drawRoundRect(0, 0, 80, 40, 5, 5);
            this.graphics.endFill();
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
            if (event.ctrlKey) {
                _isDragging = true;
                _dragOffset.x = event.localX;
                _dragOffset.y = event.localY;

                stage.addEventListener(MouseEvent.MOUSE_MOVE, reactor_onMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, reactor_onMouseUp);

                onDragStart(new Point(event.localX, event.localY));
                event.stopPropagation();
            }
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
            }
        }

        /**
         * Handle button press
         */
        private function onPress(e:MouseEvent):void {
            if (_isDragging) return;

            _pressed = true;
            drawButton();
            drawContacts();
            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var newAtom:BaseAtom = _behavior.setPressed(_parentAtom, true);
                _parentAtom = newAtom;
                updateVisuals();
                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                    atomId: newAtom.id,
                    pinName: newAtom.outputContacts[0].name,
                    newValue: true
                }));
            }
        }

        /**
         * Handle button release
         */
        private function onRelease(e:MouseEvent):void {
            if (_isDragging) return;

            _pressed = false;
            drawButton();
            drawContacts();
            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var newAtom:BaseAtom = _behavior.setPressed(_parentAtom, false);
                _parentAtom = newAtom;
                updateVisuals();
                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                    atomId: newAtom.id,
                    pinName: newAtom.outputContacts[0].name,
                    newValue: false
                }));
            }
        }

        /**
         * Handle roll out visual
         */
        private function onRollOutVisual(e:MouseEvent):void {
            if (!_pressed) {
                drawButton();
                drawContacts();
            }
        }

        /**
         * Get pressed state
         * @return Boolean - pressed state
         */
        public function get pressed():Boolean {
            return _pressed;
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
                message: "[ButtonAtomView] Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
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
                message: "[ButtonAtomView] ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }
    }
}
