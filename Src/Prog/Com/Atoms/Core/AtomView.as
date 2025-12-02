package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import flash.display.Graphics;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.display.DisplayObject;
    import flash.filters.GlowFilter;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.View.ContactView;
    import Src.Prog.Com.Atoms.Core.PinView;

    /**
     * Universal view class - расширен для отрисовки Contact системы.
     */
    public class AtomView extends Sprite {

        /** Reference to the logical atom model */
        private var _atom:Atom;
        /** Window type for context-specific rendering */
        private var _windowType:String;
        /** Atom definition from registry */
        private var _definition:Object;
        /** Display label for atom name */
        private var _label:TextField;
        /** Drag state flag */
        private var _isDragging:Boolean = false;
        /** Drag offset for smooth dragging */
        private var _dragOffset:Point = new Point();
        /** Visual configuration overrides */
        private var _viewConfig:Object;
        /** Track if this atom is currently being pressed (for button behavior) */
        private var _isPressed:Boolean = false;
        /** Track if Contact system is enabled */
        private var _useContactSystem:Boolean;

        /**
         * Creates a new AtomView instance.
         */
        public function AtomView(atom:Atom, windowType:String) {
            _atom = atom;
            _windowType = windowType;
            _definition = AtomDefinitions.getAtomDefinition(atom.type);
            
            // Проверяем, используем ли мы Contact систему (атом должен иметь контакты)
            _useContactSystem = (atom.contactInputs.length > 0 || atom.contactOutputs.length > 0);

            super();

            setupView();
            updateVisuals();

            // Initial position from atom model
            this.x = _atom.position.x;
            this.y = _atom.position.y;
            Impulsys.subscribeToImpulse("WINDOW_LEFT_RELEASE", handle_release_outside);

            trace("✅ AtomView created for: " + atom.name + 
                  (_useContactSystem ? 
                   " (Contact system: " + atom.contactInputs.length + " in, " + atom.contactOutputs.length + " out)" :
                   " (Pin system: " + atom.inputs.length + " in, " + atom.outputs.length + " out)"));
        }

        /**
         * Sets up the view with event listeners and basic styling.
         */
        private function setupView():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            this.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);

            createLabel();
        }

        /**
         * Handles mouse up events for button release behavior.
         */
        private function onMouseUp(event:MouseEvent):void {
            // If button was pressed, handle release
            if (_isPressed) {
                _isPressed = false;
                handleInteraction("release");
            }
        }

        /**
         * Handles right mouse down for context menu.
         */
        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            Impulsys.emit(new Impulse("ATOM_RIGHT_CLICK", {
                atom: _atom,
                view: this,
                globalPosition: new Point(event.stageX, event.stageY),
                window: this.stage ? this.stage.nativeWindow as Window : null,
                windowType: _windowType
            }));
        }

        /**
         * Sets background color for the atom view.
         */
        public function setBackgroundColor(color:uint):void {
            if (!_viewConfig) _viewConfig = {};
            _viewConfig.backgroundColor = color;
            updateVisuals();
        }

        /**
         * Sets width for the atom view.
         */
        public function setWidth(width:Number):void {
            if (!_viewConfig) _viewConfig = {};
            _viewConfig.width = width;
            updateVisuals();
        }

        /**
         * Sets height for the atom view.
         */
        public function setHeight(height:Number):void {
            if (!_viewConfig) _viewConfig = {};
            _viewConfig.height = height;
            updateVisuals();
        }

        /**
         * Creates the display label for the atom.
         */
        private function createLabel():void {
            _label = new TextField();
            _label.selectable = false;
            _label.mouseEnabled = false;

            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0x000000;
            _label.defaultTextFormat = format;

            this.addChild(_label);
        }

        /**
         * Updates the view with a new atom model.
         */
        public function updateAtom(newAtom:Atom):void {
            _atom = newAtom;

            // Sync visual position with logical model
            this.x = _atom.position.x;
            this.y = _atom.position.y;

            updateVisuals();
        }

        /**
         * Draws default atom visualization.
         */
        private function drawDefault(graphics:Graphics, config:Object):void {
            var width:Number = validateDimension(config.width, 60);
            var height:Number = validateDimension(config.height, 40);
            var color:uint = config.color || 0xCCCCCC;

            graphics.beginFill(color);

            if (config.cornerRadius && !isNaN(config.cornerRadius) && config.cornerRadius > 0) {
                graphics.drawRoundRect(0, 0, width, height, config.cornerRadius, config.cornerRadius);
            } else {
                graphics.drawRect(0, 0, width, height);
            }

            graphics.endFill();
        }

        /**
         * Validates dimension values with fallback.
         */
        private function validateDimension(value:*, defaultValue:Number):Number {
            if (value === undefined || value === null || isNaN(value) || value <= 0) {
                return defaultValue;
            }
            return Number(value);
        }

        /**
         * Updates the label with current atom data.
         */
        private function updateLabel(config:Object):void {
            _label.text = _atom.name;
            _label.width = config.width;
            _label.height = 20;
            _label.y = (config.height - 20) / 2;
            _label.textColor = config.textColor || 0x000000;
        }

        /**
         * Updates pin views based on current atom pins.
         */
        private function updatePins(config:Object):void {
            // Remove existing pin views
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is PinView) {
                    this.removeChildAt(i);
                }
            }

            // Create input pin views
            for (var j:int = 0; j < _atom.inputs.length; j++) {
                var inputPin:PinView = new PinView(_atom.inputs[j]);
                inputPin.x = 0;
                inputPin.y = config.height * (j + 1) / (_atom.inputs.length + 1);

                // ENSURE THESE FLAGS ARE SET:
                inputPin.mouseEnabled = true;
                inputPin.mouseChildren = false;

                this.addChild(inputPin);
            }

            // Create output pin views
            for (var k:int = 0; k < _atom.outputs.length; k++) {
                var outputPin:PinView = new PinView(_atom.outputs[k]);
                outputPin.x = config.width;
                outputPin.y = config.height * (k + 1) / (_atom.outputs.length + 1);

                // ENSURE THESE FLAGS ARE SET:
                outputPin.mouseEnabled = true;
                outputPin.mouseChildren = false;

                this.addChild(outputPin);
            }
        }

        /**
         * Обновляет ContactView для всех контактов атома.
         */
        private function updateContacts(config:Object):void {
            // Удаляем существующие ContactView
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is ContactView) {
                    this.removeChildAt(i);
                }
            }

            // Создаем ContactView для входных контактов
            for (var j:int = 0; j < _atom.contactInputs.length; j++) {
                var inputContact:Contact = _atom.contactInputs[j];
                var inputContactView:ContactView = new ContactView(inputContact);
                inputContactView.x = 0;
                inputContactView.y = config.height * (j + 1) / (_atom.contactInputs.length + 1);

                inputContactView.mouseEnabled = true;
                inputContactView.mouseChildren = false;

                this.addChild(inputContactView);
            }

            // Создаем ContactView для выходных контактов
            for (var k:int = 0; k < _atom.contactOutputs.length; k++) {
                var outputContact:Contact = _atom.contactOutputs[k];
                var outputContactView:ContactView = new ContactView(outputContact);
                outputContactView.x = config.width;
                outputContactView.y = config.height * (k + 1) / (_atom.contactOutputs.length + 1);

                outputContactView.mouseEnabled = true;
                outputContactView.mouseChildren = false;

                this.addChild(outputContactView);
            }
        }

        /**
         * Handles mouse down for dragging or interaction.
         */
        private function onMouseDown(event:MouseEvent):void {
            // Check if click was on a pin or contact
            var target:DisplayObject = event.target as DisplayObject;
            while (target && target != this) {
                if (target is PinView || target is ContactView) {
                    // Click was on pin or contact - let them handle it
                    return;
                }
                target = target.parent;
            }

            if (event.ctrlKey) {
                startDragMode(event);
            } else {
                _isPressed = true; // Mark that button is pressed
                handleInteraction("press");
            }
        }

        /**
         * Handles atom interactions (press and release).
         */
        private function handleInteraction(interactionType:String):void {
            trace("=== ATOM INTERACTION ===");
            trace("Atom: " + _atom.type + " (" + _atom.id + ")");
            trace("Interaction type: " + interactionType);
            var definition:Object = AtomDefinitions.getAtomDefinition(_atom.type);
            if (definition && definition.behavior) {
                try {
                    var newAtom:Atom = _atom;
                    if (interactionType == "press" && definition.behavior.onInteraction) {
                        newAtom = definition.behavior.onInteraction(_atom, interactionType);
                    }
                    else if (interactionType == "release" && definition.behavior.onRelease) {
                        newAtom = definition.behavior.onRelease(_atom);
                    }
                    if (newAtom !== _atom) {
                        var atomManager:AtomManager = AtomManager.getInstance();
                        atomManager.updateAtom(newAtom);
                    }
                } catch (error:Error) {
                    trace("ERROR in atom interaction: " + error.message);
                }
            }
            trace("=== END INTERACTION ===");
        }

        /**
         * Finds a pin by name in a pin vector.
         */
        private function findPinByName(pins:Vector.<Pin>, pinName:String):Pin {
            for each (var pin:Pin in pins) {
                if (pin.name == pinName) {
                    return pin;
                }
            }
            return null;
        }

        /**
         * Starts atom dragging mode.
         */
        private function startDragMode(event:MouseEvent):void {
            if (!parent || !_atom) return;

            _isDragging = true;
            this.alpha = 0.7;

            // Get mouse position in world coordinates
            var mouseWorld:Point = parent.globalToLocal(new Point(event.stageX, event.stageY));

            // Calculate drag offset
            _dragOffset.x = mouseWorld.x - _atom.position.x;
            _dragOffset.y = mouseWorld.y - _atom.position.y;

            stage.addEventListener(MouseEvent.MOUSE_MOVE, onDrag);
            stage.addEventListener(MouseEvent.MOUSE_UP, onDragEnd);

            trace("🚀 DRAG STARTED for atom: " + _atom.name);
            Impulsys.emit(new Impulse("ATOM_DRAG_START", {
                atom: _atom,
                view: this,
                startPosition: _atom.position.clone()
            }));
        }

        /**
         * Handles dragging motion.
         */
        private function onDrag(event:MouseEvent):void {
            if (!_isDragging || !parent) return;

            var mouseWorld:Point = parent.globalToLocal(new Point(event.stageX, event.stageY));
            var newX:Number = mouseWorld.x - _dragOffset.x;
            var newY:Number = mouseWorld.y - _dragOffset.y;

            var newAtom:Atom = _atom.setPosition(new Point(newX, newY));

            Impulsys.emit(new Impulse("ATOM_MOVED", {
                oldAtom: _atom,
                newAtom: newAtom,
                updateTracks: true,
                isDragging: false
            }));

            _atom = newAtom;
            this.x = _atom.position.x;
            this.y = _atom.position.y;

            // Обновляем визуальные представления пинов или контактов
            updateVisualsDuringDrag();
        }

        /**
         * Обновляет визуальные представления во время перетаскивания.
         */
        private function updateVisualsDuringDrag():void {
            // Обновляем PinView или ContactView в зависимости от системы
            var config:Object = getVisualConfig();
            if (_useContactSystem) {
                updateContacts(config);
            } else {
                updatePins(config);
            }
        }

        /**
         * Handles drag end.
         */
        private function onDragEnd(event:MouseEvent):void {
            if (!_isDragging) return;

            _isDragging = false;
            this.alpha = 1.0;

            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);

            // Final position update
            var finalAtom:Atom = _atom.setPosition(new Point(this.x, this.y));

            trace("🛑 DRAG ENDED for atom: " + _atom.name);

            Impulsys.emit(new Impulse("ATOM_DRAG_END", {
                atom: _atom,
                view: this,
                finalPosition: new Point(this.x, this.y)
            }));

            _atom = finalAtom;
            this.x = _atom.position.x;
            this.y = _atom.position.y;
        }

        /**
         * Updates all visual elements of the atom.
         */
        public function updateVisuals():void {
            // Добавить визуальную индикацию состояния нажатия
            if (_isPressed) {
                this.filters = [new GlowFilter(0xFFFFFF, 0.8, 1, 1, 2, 3)];
            } else {
                this.filters = [];
            }
            
            if (!_definition) {
                drawFallback();
                return;
            }

            var visualConfig:Object = getVisualConfig();
            if (_viewConfig) {
                visualConfig = mergeConfig(visualConfig, _viewConfig);
            }

            this.graphics.clear();

            // If configuration has draw function, use it
            if (visualConfig.draw is Function) {
                try {
                    visualConfig.draw(this.graphics, _atom, visualConfig);
                } catch (error:Error) {
                    trace("Error in custom draw function for " + _atom.type + ": " + error.message);
                    drawDefault(this.graphics, visualConfig);
                }
            } else {
                drawDefault(this.graphics, visualConfig);
            }

            updateLabel(visualConfig);
            
            // Обновляем либо PinView, либо ContactView в зависимости от системы
            if (_useContactSystem) {
                updateContacts(visualConfig);
            } else {
                updatePins(visualConfig);
            }
        }

        /**
         * Gets visual configuration for current window type.
         */
        private function getVisualConfig():Object {
            if (!_definition) {
                return getFallbackConfig();
            }

            var config:Object = null;

            // First try window-specific configuration
            if (_definition.visuals && _definition.visuals[_windowType]) {
                config = _definition.visuals[_windowType];

                // If window-specific lacks draw function, try base
                if (!config.draw && _definition.visuals.base) {
                    var baseConfig:Object = _definition.visuals.base;
                    // Merge configurations, prioritizing window-specific
                    config = mergeConfig(baseConfig, config);
                }
            }
            // If no window-specific, try base
            else if (_definition.visuals && _definition.visuals.base) {
                config = _definition.visuals.base;
            }
            // If no visuals, try viewConfig
            else if (_definition.viewConfig) {
                config = _definition.viewConfig;
            }
            // Fallback
            else {
                config = getFallbackConfig();
            }

            return config;
        }

        /**
         * Gets fallback visual configuration.
         */
        private function getFallbackConfig():Object {
            return {
                width: 60,
                height: 40,
                color: 0xCCCCCC,
                textColor: 0x000000
            };
        }

        /**
         * Draws fallback visualization for undefined atoms.
         */
        private function drawFallback():void {
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000);
            this.graphics.drawRect(0, 0, 60, 40);
            this.graphics.endFill();
        }

        /**
         * Merges base and override configurations.
         */
        private function mergeConfig(base:Object, overrides:Object):Object {
            var result:Object = {};
            for (var key:String in base) result[key] = base[key];
            for (key in overrides) result[key] = overrides[key];
            return result;
        }

        /**
         * Handles release outside the atom.
         */
        private function handle_release_outside(impulse:Impulse):void {
            if (_isPressed) {
                _isPressed = false;
                handleInteraction("release");
            }
        }

        /**
         * Cleans up resources and event listeners.
         */
        public function dispose():void {
            trace("🧹 Disposing AtomView: " + _atom.name);

            removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);

            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);
            }

            // Remove all child views
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                var child:DisplayObject = this.getChildAt(i);
                if (child is PinView) {
                    PinView(child).dispose();
                    this.removeChildAt(i);
                } else if (child is ContactView) {
                    ContactView(child).dispose();
                    this.removeChildAt(i);
                }
            }

            // Remove label
            if (_label && this.contains(_label)) {
                this.removeChild(_label);
                _label = null;
            }
            
            Impulsys.removeImpulse("WINDOW_LEFT_RELEASE", handle_release_outside);
        }

        /**
         * Gets the logical atom model.
         */
        public function get atom():Atom {
            return _atom;
        }

        /**
         * Checks if Contact system is enabled for this view.
         */
        public function get useContactSystem():Boolean {
            return _useContactSystem;
        }

        /**
         * Toggles between Contact and Pin systems.
         */
        public function toggleSystem():void {
            _useContactSystem = !_useContactSystem;
            updateVisuals();
            trace("🔄 Toggled system to: " + (_useContactSystem ? "Contact" : "Pin"));
        }
    }
}