package Src.Prog.Com.Atoms.Custom {
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.Pin;

	// НАДО ДОБАВИТЬ НЕДОСТАЮЩИЕ import
	
    /**
     * Visual representation of a number display atom.
     * Inherits from BaseAtomView for common functionality.
     */
    public class NumberDisplayAtom_EditorView extends BaseAtomView {
        private var _valueLabel:TextField;
        private var _nameLabel:TextField;
        public static const WIDTH:Number = 100;
        public static const HEIGHT:Number = 50;

        /**
         * Constructs the NumberDisplayAtomView.
         * Initializes visual elements and interactions.
         */
        public function NumberDisplayAtom_EditorView() {
            super();
            createVisuals();
            setupDisplayInteractions();
        }

        /**
         * @inheritDoc
         * Initializes the view with a specific atom, subscribes to updates, and updates visuals.
         */
        override public function initWithAtom(atom:BaseAtom):void {
            super.initWithAtom(atom);
            MultiPulsator.subscribeToImpulse("ATOM_UPDATED", onAtomUpdated);
            updateLabels();
            updateVisuals();
        }

        /**
         * Handles the ATOM_UPDATED impulse to refresh the display if the atom changes.
         */
        private function onAtomUpdated(impulse:Impulse):void {
            var newAtom:BaseAtom = impulse.data.newAtom as BaseAtom;
            if (newAtom && newAtom.id == _parentAtom.id) {
                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * @inheritDoc
         * Updates the visual representation, including the background, contacts, and value display.
         */
        override public function updateVisuals():void {
            drawBackground();
            drawContacts();
            if (_parentAtom && _parentAtom.inputContacts.length > 0) {
                var inputPin:Pin = _parentAtom.inputContacts[0];
                _valueLabel.text = inputPin.value !== undefined && inputPin.value !== null ? inputPin.value.toString() : "0";
            } else {
                _valueLabel.text = "0";
            }
        }

        /**
         * Creates the necessary visual elements like labels.
         */
        private function createVisuals():void {
            createValueLabel();
            createNameLabel();
        }

        /**
         * Sets up display-specific interactions.
         * Currently, the display does not require additional mouse listeners.
         */
        private function setupDisplayInteractions():void {
            // Base interactions already setup in parent
            // Display doesn't need additional mouse listeners
        }

        /**
         * @inheritDoc
         * Handles the mouse down event for the display.
         * The display only supports dragging, handled by the parent class.
         */
        override protected function onSpecificMouseDown(event:MouseEvent):void {
            // Display doesn't have click behavior, only drag
            // BaseAtomView already handles bringToFront and drag
        }

        /**
         * Draws the background of the display.
         */
        private function drawBackground():void {
            this.graphics.clear();
            this.graphics.beginFill(0x34495E);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 5, 5);
            this.graphics.endFill();
        }

        /**
         * Creates the text label for displaying the numeric value.
         */
        private function createValueLabel():void {
            _valueLabel = new TextField();
            _valueLabel.width = WIDTH;
            _valueLabel.height = HEIGHT;
            _valueLabel.selectable = false;
            _valueLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 16;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xECF0F1;
            format.bold = true;
            _valueLabel.defaultTextFormat = format;
            this.addChild(_valueLabel);
        }

        /**
         * Creates the text label for displaying the atom's name.
         */
        private function createNameLabel():void {
            _nameLabel = new TextField();
            _nameLabel.width = WIDTH;
            _nameLabel.y = 30;
            _nameLabel.selectable = false;
            _nameLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xBDC3C7;
            _nameLabel.defaultTextFormat = format;
            this.addChild(_nameLabel);
        }

        /**
         * Updates the text displayed in the name label.
         */
        private function updateLabels():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * @inheritDoc
         * Draws the contact pins for the display.
         */
        override protected function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Creates and positions the input pins based on the atom's contacts.
         * The display only has input pins.
         */
        private function createAndPositionPins():void {
            if(!_parentAtom) return;
            removeExistingPins();

            // Input pins only (display has no outputs)
            for(var i:int = 0; i < _parentAtom.inputContacts.length; i++) {
                var inputPin:Pin = _parentAtom.inputContacts[i];
                var inputY:Number = HEIGHT * (i + 1) / (_parentAtom.inputContacts.length + 1);
                inputPin.x = 0;
                inputPin.y = inputY;
                this.addChild(inputPin);
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
         * @inheritDoc
         * Handles the completion of an asset load.
         */
        override public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "NumberDisplayAtomView",
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
                source: "NumberDisplayAtomView",
                message: "ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }
    }
}
