package Application.AtomICLinker.View {
    import flash.display.MovieClip;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Application.AtomICLinker.View.Pin;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.AtomManager;
    import Application.Managers.ConnectionManager;
    import Application.AtomICLinker.View.Track;
    import Application.AtomICCore.Atom.BaseAtom;

    /**
     * Base class for all atom views.
     * Provides common functionality such as drag/drop, bringToFront, and common interactions.
     */
    public class BaseEditAtomView extends MovieClip implements IAtomView {
        protected var _parentAtom:BaseAtom;
        protected var _isDragging:Boolean = false;
        protected var _dragOffset:Point = new Point();
        protected static const GRID_SIZE:int = 10;
        protected static const SNAP_TO_GRID:Boolean = true;

        /**
         * Constructs the BaseAtomView.
         * Sets up base mouse interactions.
         */
        public function BaseEditAtomView() {
            super();
            setupBaseInteractions();
        }

        /**
         * Updates the reference to the atom this view represents and refreshes the view.
         * @param newAtom The new atom instance to represent.
         */
        public function updateAtomReference(newAtom:BaseAtom):void {
            if (_parentAtom !== newAtom) {
                _parentAtom = newAtom;
                updateVisuals(); // Update visual representation
            }
        }

        /**
         * Sets up base mouse event listeners for dragging and bringing the view to the front.
         */
        private function setupBaseInteractions():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onBaseMouseDown);
        }

        /**
         * Handles the base mouse down event.
         * Brings the view to the front and starts dragging if the Ctrl key is pressed.
         */
        private function onBaseMouseDown(event:MouseEvent):void {
            // Always bring to front on click
            if (!_isDragging) {
                bringToFront();
            }

            // Start dragging if Ctrl key is pressed
            if (event.ctrlKey) {
                _isDragging = true;
                _dragOffset.x = event.localX;
                _dragOffset.y = event.localY;
                stage.addEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                onDragStart(new Point(event.localX, event.localY));
                event.stopPropagation();
            }

            // Call specific mouse down handler in child class
            onSpecificMouseDown(event);
        }

        /**
         * Handles the base mouse move event during dragging.
         */
        private function onBaseMouseMove(event:MouseEvent):void {
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
         * Handles the base mouse up event after dragging.
         */
        private function onBaseMouseUp(event:MouseEvent):void {
            if (_isDragging) {
                _isDragging = false;
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
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
         * Updates the tracks connected to this atom during dragging.
         */
        protected function updateTracksDuringDrag():void {
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
         * Brings this atom view to the front of its parent's display list.
         */
        public function bringToFront():void {
            if (this.parent) {
                this.parent.setChildIndex(this, this.parent.numChildren - 1);

                // Also bring pins to front within this view
                for (var i:int = 0; i < this.numChildren; i++) {
                    var child:* = this.getChildAt(i);
                    if (child is Pin) {
                        this.setChildIndex(child, this.numChildren - 1);
                    }
                }

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "BaseAtomView",
                    message: "Atom brought to front: " + (_parentAtom ? _parentAtom.name : "Unknown")
                }));
            }
        }

        /**
         * Removes any existing pin objects from the display list.
         */
        protected function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * Draws the contact pins. This method should be overridden by child classes.
         */
        protected function drawContacts():void {
            // Override in child classes to implement pin drawing
        }

        /**
         * Ensures pins are visible and properly positioned by removing and re-adding them.
         */
        public function refreshPins():void {
            if (_parentAtom) {
                // Remove and re-add pins to ensure they're visible
                removeExistingPins();
                drawContacts();

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "BaseAtomView",
                    message: "Pins refreshed for: " + (_parentAtom ? _parentAtom.name : "Unknown")
                }));
            }
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Can be overridden in child classes for specific cleanup.
         */
        public function dispose():void {
            // Basic event cleanup
            removeEventListener(MouseEvent.MOUSE_DOWN, onBaseMouseDown);

            // Stop drag if active
            if (_isDragging && stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                _isDragging = false;
            }

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "DEBUG",
                source: "BaseAtomView",
                message: "BaseAtomView disposed: " + (_parentAtom ? _parentAtom.name : "Unknown")
            }));
        }

        // --- Abstract methods to be implemented by child classes ---

        /**
         * Handles the disconnection of a pin.
         * @param pinName The name of the pin that was disconnected.
         */
        protected function handlePinDisconnection(pinName:String):void {
            if (_parentAtom) {
                // Find pin and reset its value
                for each(var inputPin:Pin in _parentAtom.inputContacts) {
                    if (inputPin.name == pinName) {
                        var newAtom:BaseAtom = _parentAtom.setInputPinValue(pinName, null);
                        updateAtomReference(newAtom);
                        break;
                    }
                }
            }
        }

        /**
         * Handles the specific mouse down event for child classes.
         * Override in child classes for specific click behavior.
         */
        protected function onSpecificMouseDown(event:MouseEvent):void {
            // Override in child classes for specific click behavior
        }

        /**
         * Initializes the view with a specific atom.
         * @param atom The atom to initialize the view with.
         */
        public function initWithAtom(atom:BaseAtom):void {
            _parentAtom = atom;
            refreshPins(); // Ensure pins are visible
        }

        /**
         * Updates the visual representation of the atom.
         * Override in child classes to implement specific visual updates.
         */
        public function updateVisuals():void { }

        /**
         * Handles the start of a drag operation.
         * @param mousePos The mouse position when dragging started.
         */
        public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7;
        }

        /**
         * Handles the movement during a drag operation.
         * @param mousePos The current mouse position during dragging.
         */
        public function onDrag(mousePos:Point):void {
            this.x = mousePos.x;
            this.y = mousePos.y;
            updateTracksDuringDrag();
        }

        /**
         * Handles the end of a drag operation.
         * @param mousePos The mouse position when dragging ended.
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
         * Handles the completion of an asset load.
         * @param assetUrl The URL of the loaded asset.
         * @param assetData The loaded asset data.
         */
        public function onAssetLoadComplete(assetUrl:String, assetData:*):void { }

        /**
         * Handles an error during asset loading.
         * @param assetUrl The URL of the asset that failed to load.
         * @param errorMessage The error message describing the failure.
         */
        public function onAssetLoadError(assetUrl:String, errorMessage:String):void { }

        /**
         * Gets the atom this view represents.
         * @return The parent atom.
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }
    }
}
