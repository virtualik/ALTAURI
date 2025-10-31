// File: Src.Prog.Com.Atoms.Core.BaseAtomView.as

package Src.Prog.Com.Atoms.Core {
    import flash.display.MovieClip;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    // import Src.Prog.Core.Managers.AtomManager; // Предполагаем, что AtomManager будет использоваться
    // import Src.Prog.Com.Atoms.Linker.Track; // Предполагаем, что Track будет реализован и использован
    // import Src.Prog.Com.AssetsDomain.AssetManager; // Предполагаем, что AssetManager будет использоваться

    /**
     * Base class for all atom views.
     * Provides common functionality such as drag/drop, bringToFront, and common interactions.
     * Integrates with MultiPulsator for system communication and expects integration
     * with AtomManager and AssetDomain for updates and visuals.
     */
    public class BaseAtomView extends MovieClip implements IAtomView {
        protected var _parentAtom:BaseAtom;
        protected var _isDragging:Boolean = false;
        protected var _dragOffset:Point = new Point();
        protected static const GRID_SIZE:int = 10;
        protected static const SNAP_TO_GRID:Boolean = true;

        /**
         * Constructs the BaseAtomView.
         * Sets up base mouse interactions.
         */
        public function BaseAtomView() {
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
                updateVisuals(); // Update visual representation based on new atom state
                refreshPins(); // Refresh pins based on new atom's contacts
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
         * Placeholder: Requires ConnectionManager or similar service to be implemented.
         * Example integration with MultiPulsator or direct call to Linker domain.
         */
        protected function updateTracksDuringDrag():void {
            // Example: Emit an impulse for the Linker domain to handle
            if (_parentAtom) {
                 MultiPulsator.emit(new Impulse("ATOM_DRAGGING", {
                    atom: _parentAtom,
                    position: new Point(this.x, this.y) // Current visual position during drag
                }));
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
                // Optional: Emit an impulse if other parts of the system need to know
                // MultiPulsator.emit(new Impulse("ATOM_BROUGHT_TO_FRONT", { atomId: _parentAtom?.id }));
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
         * It should create visual Pin instances and add them to this view's display list.
         */
        protected function drawContacts():void {
            // Override in child classes to implement pin drawing
            // Example: Create Pin sprites based on _parentAtom.inputContacts and outputContacts
            // and add them as children to this MovieClip.
        }

        /**
         * Ensures pins are visible and properly positioned by removing and re-adding them.
         */
        public function refreshPins():void {
            if (_parentAtom) {
                // Remove and re-add pins to ensure they're visible and reflect atom state
                removeExistingPins();
                drawContacts();
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

            // Remove pins
            removeExistingPins();

            // Clear atom reference
            _parentAtom = null;
        }

        // --- Methods to be implemented by child classes ---

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
            refreshPins(); // Ensure pins are visible and reflect initial atom state
            updateVisuals(); // Initial visual update
        }

        /**
         * Updates the visual representation of the atom.
         * Override in child classes to implement specific visual updates.
         */
        public function updateVisuals():void {
             // Override in child classes to update visuals based on _parentAtom state
             // e.g., update display based on pin values, name, type, etc.
        }

        /**
         * Handles the start of a drag operation.
         * @param mousePos The mouse position when dragging started.
         */
        public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7; // Visual feedback for dragging
        }

        /**
         * Handles the movement during a drag operation.
         * @param mousePos The current mouse position during dragging.
         */
        public function onDrag(mousePos:Point):void {
            this.x = mousePos.x;
            this.y = mousePos.y;
            updateTracksDuringDrag(); // Notify system about ongoing drag
        }

        /**
         * Handles the end of a drag operation.
         * Updates the atom's position and notifies the system via MultiPulsator.
         * Expects AtomManager or similar service to handle the ATOM_MOVED impulse.
         */
        public function onDragEnd(mousePos:Point):void {
            this.alpha = 1.0; // Reset visual feedback
            if (_parentAtom) {
                var newPosition:Point = new Point(mousePos.x, mousePos.y);
                // Create new atom with updated position using immutable pattern
                var newAtom:BaseAtom = _parentAtom.setPosition(newPosition);

                // Notify the system about the change
                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    oldAtom: _parentAtom,
                    newAtom: newAtom,
                    oldPosition: _parentAtom.position,
                    newPosition: newPosition
                }));

                // The AtomManager (or whoever listens to ATOM_MOVED) should now
                // update its registry and potentially call updateAtomReference(newAtom) on this view.
            }
        }

        /**
         * Handles the completion of an asset load.
         * Override in child classes if specific asset loading logic is needed.
         * @param assetUrl The URL of the loaded asset.
         * @param assetData The loaded asset data.
         */
        public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
             // Override in child classes if needed
             // e.g., apply loaded asset to a display object
        }

        /**
         * Handles an error during asset loading.
         * Override in child classes if specific asset loading error logic is needed.
         * @param assetUrl The URL of the asset that failed to load.
         * @param errorMessage The error message describing the failure.
         */
        public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
             // Override in child classes if needed
             // e.g., show error state visually
        }

        /**
         * Gets the atom this view represents.
         * @return The parent atom.
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }
    }
}
