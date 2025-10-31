package Src.Prog.Com.Atoms.Custom {
    import flash.display.BitmapData;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Com.Logics.Behaviors.ButtonAtomBehavior;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.Pin;


    /**
     * Visual representation of a button atom.
     * Inherits from BaseAtomView for common functionality.
     */
    public class ButtonAtom_EditorView extends BaseAtomView {
        private var _behavior:ButtonAtomBehavior = new ButtonAtomBehavior();
        private var _pressed:Boolean = false;
        private var _nameLabel:TextField;
        private static const WIDTH:Number = 80;
        private static const HEIGHT:Number = 30;

        /**
         * Constructs the ButtonAtomView.
         * Initializes visual elements and interactions.
         */
        public function ButtonAtom_EditorView() {
            super();
            createNameLabel();
            drawButton();
            setupButtonInteractions();
        }

        /**
         * @inheritDoc
         * Initializes the view with a specific atom and updates its visuals.
         */
        override public function initWithAtom(atom:BaseAtom):void {
            super.initWithAtom(atom);
            updateLabel();
            updateVisuals();
        }

        /**
         * @inheritDoc
         * Updates the visual representation of the button based on its state.
         */
        override public function updateVisuals():void {
            drawButton();
            drawContacts();
        }

        /**
         * Creates the text label for the button's name.
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
         * Sets up button-specific mouse event listeners.
         */
        private function setupButtonInteractions():void {
            // Base interactions already setup in parent
            // Add button-specific listeners
            this.addEventListener(MouseEvent.MOUSE_UP, onRelease);
            this.addEventListener(MouseEvent.ROLL_OUT, onRollOutVisual);
        }

        /**
         * @inheritDoc
         * Handles the mouse down event for the button.
         * Sets the button state to pressed and propagates a 'true' value.
         */
        override protected function onSpecificMouseDown(event:MouseEvent):void {
            if (_isDragging) return;

            _pressed = true;
            drawButton();
            drawContacts();

            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var newAtom:BaseAtom = _behavior.setPressed(_parentAtom, true);

                // Update atom in system
                var atomManager:AtomManager = AtomManager.getInstance();
                if (atomManager) {
                    atomManager.updateAtom(newAtom);
                }

                // Emit pin update
                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                    atomId: newAtom.id,
                    pinName: newAtom.outputContacts[0].name,
                    newValue: true
                }));

                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * Updates the text displayed in the name label.
         */
        private function updateLabel():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * Draws the button's background, changing color based on its pressed state.
         */
        private function drawButton():void {
            this.graphics.clear();
            var color:uint = _pressed ? 0x27AE60 : 0x2ECC71;
            this.graphics.beginFill(color);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 5, 5);
            this.graphics.endFill();
        }

        /**
         * @inheritDoc
         * Draws the contact pins for the button.
         */
        override protected function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Creates and positions the output pins based on the atom's contacts.
         * The button only has output pins.
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
         * @inheritDoc
         * Removes any existing pin objects from the display list.
         */
        override protected function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * Handles the mouse up event for the button.
         * Sets the button state to released and propagates a 'false' value.
         */
        private function onRelease(e:MouseEvent):void {
            if (_isDragging) return;
            _pressed = false;
            drawButton();
            drawContacts();

            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var newAtom:BaseAtom = _behavior.setPressed(_parentAtom, false);

                // Update atom in system
                var atomManager:AtomManager = AtomManager.getInstance();
                if (atomManager) {
                    atomManager.updateAtom(newAtom);
                }

                // Emit pin update
                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                    atomId: newAtom.id,
                    pinName: newAtom.outputContacts[0].name,
                    newValue: false
                }));

                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * Handles the mouse roll-out event.
         * Redraws the button if it's not currently pressed.
         */
        private function onRollOutVisual(e:MouseEvent):void {
            if (!_pressed) {
                drawButton();
                drawContacts();
            }
        }

        /**
         * @inheritDoc
         * Handles the completion of an asset load.
         */
        override public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "ButtonAtomView",
                message: "Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
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
         * @inheritDoc
         * Handles an error during asset loading.
         */
        override public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "ERROR",
                source: "ButtonAtomView",
                message: "ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }

        /**
         * Gets the current pressed state of the button.
         * @return True if the button is pressed, false otherwise.
         */
        public function get pressed():Boolean {
            return _pressed;
        }
    }
}
