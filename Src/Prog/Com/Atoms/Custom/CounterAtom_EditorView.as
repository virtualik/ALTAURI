package Src.Prog.Com.Atoms.Custom {
    import flash.display.BitmapData;
    import flash.events.MouseEvent;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Visual representation of a counter atom.
     * Inherits from BaseAtomView for common functionality.
     */
    public class CounterAtom_EditorView extends BaseAtomView {
        private var _valueLabel:TextField;
        private var _nameLabel:TextField;
        public static const WIDTH:Number = 120;
        public static const HEIGHT:Number = 60;

        /**
         * Constructs the CounterAtomView.
         * Initializes visual elements and interactions.
         */
        public function CounterAtom_EditorView() {
            super();
            createVisuals();
            setupCounterInteractions();
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
            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var outputPin:Pin = _parentAtom.outputContacts[0];
                _valueLabel.text = (outputPin.value !== null && outputPin.value !== undefined) ? outputPin.value.toString() : "0";
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
         * Sets up counter-specific interactions.
         * Currently, the counter does not require additional mouse listeners.
         */
        private function setupCounterInteractions():void {
            // Base interactions already setup in parent
            // Counter doesn't need additional mouse listeners
        }

        /**
         * @inheritDoc
         * Handles the mouse down event for the counter.
         * The counter only supports dragging, handled by the parent class.
         */
        override protected function onSpecificMouseDown(event:MouseEvent):void {
            // Counter doesn't have click behavior, only drag
            // BaseAtomView already handles bringToFront and drag
        }

        /**
         * Draws the background of the counter.
         */
        private function drawBackground():void {
            this.graphics.clear();
            this.graphics.beginFill(0x3498DB);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 10, 10);
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
            format.size = 18;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xFFFFFF;
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
			_nameLabel.height = 20;
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
         * Updates the text displayed in the name label.
         */
        private function updateLabels():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * @inheritDoc
         * Draws the contact pins for the counter.
         */
        override protected function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Creates and positions the input and output pins based on the atom's contacts.
         */
        private function createAndPositionPins():void {
            if(!_parentAtom) return;

            // Use parent class method to remove existing pins
            removeExistingPins();

            // Input pins
            for(var i:int = 0; i < _parentAtom.inputContacts.length; i++) {
                var inputPin:Pin = _parentAtom.inputContacts[i];
                var inputY:Number = HEIGHT * (i + 1) / (_parentAtom.inputContacts.length + 1);
                inputPin.x = 0;
                inputPin.y = inputY;
                this.addChild(inputPin);
            }

            // Output pins
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
         * Handles the completion of an asset load.
         */
        override public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "CounterAtomView",
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
                source: "CounterAtomView",
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
