package Application.AtomLinker.View {
    import flash.display.MovieClip;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.display.BitmapData;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.AtomManager;
    import Application.Managers.ConnectionManager;
    import Application.AtomLinker.Core.Track;

    /**
     * Counter Atom View - visual representation of counter atom
     */
    public class CounterAtomView extends MovieClip implements IAtomView {
        private var _valueLabel:TextField;
        private var _nameLabel:TextField;
        private var _parentAtom:BaseAtom;
        private var _isDragging:Boolean = false;
        private var _dragOffset:Point = new Point();
        private static const GRID_SIZE:int = 10;
        private static const SNAP_TO_GRID:Boolean = true;
        public static const WIDTH:Number = 120;
        public static const HEIGHT:Number = 60;

        /**
         * Counter Atom View constructor
         */
        public function CounterAtomView() {
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
            MultiPulsator.subscribeToImpulse("ATOM_UPDATED", onAtomUpdated);
            updateLabels();
            updateVisuals();
        }

        /**
         * Handle atom update
         * @param impulse - update impulse
         */
        private function onAtomUpdated(impulse:Impulse):void {
            var newAtom:BaseAtom = impulse.data.newAtom as BaseAtom;
            if (newAtom && newAtom.id == _parentAtom.id) {
                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * Update visual representation
         */
        public function updateVisuals():void {
            drawBackground();
            drawContacts();
            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var outputPin:Pin = _parentAtom.outputContacts[0];
                _valueLabel.text = (outputPin.value !== null && outputPin.value !== undefined) ? outputPin.value.toString() : "0";
            } else {
                _valueLabel.text = "0";
            }
        }

        /**
         * Create visual elements
         */
        private function createVisuals():void {
            createValueLabel();
            createNameLabel();
        }

        /**
         * Set up mouse interactions
         */
        private function setupInteractions():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        /**
         * Draw background
         */
        private function drawBackground():void {
            this.graphics.clear();
            this.graphics.beginFill(0x3498DB);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 10, 10);
            this.graphics.endFill();
        }

        /**
         * Create value label
         */
        private function createValueLabel():void {
            _valueLabel = new TextField();
            _valueLabel.width = WIDTH;
            _valueLabel.height = HEIGHT;
            _valueLabel.selectable = false;
            _valueLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 18;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xFFFFFF;
            format.bold = true;
            _valueLabel.defaultTextFormat = format;
            this.addChild(_valueLabel);
        }

        /**
         * Create name label
         */
        private function createNameLabel():void {
            _nameLabel = new TextField();
            _nameLabel.width = WIDTH;
            _nameLabel.y = 40;
            _nameLabel.selectable = false;
            _nameLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xEEEEEE;
            _nameLabel.defaultTextFormat = format;
            this.addChild(_nameLabel);
        }

        /**
         * Update labels text
         */
        private function updateLabels():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
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
                message: "[CounterAtomView] Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
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
                message: "[CounterAtomView] ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }
    }
}
