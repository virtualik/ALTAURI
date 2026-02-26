package Src.Atom.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import Src.Impulsator.Impulsys;
    import Src.Impulsator.Impulse;
    import flash.display.Graphics;
    import Src.Windows.Window;
    import Src.Managers.AtomManager;
    import Src.Atom.Data.AtomDefinitions;
    import flash.display.DisplayObject;
    import flash.filters.GlowFilter;
    import Src.Contact.Core.Contact;
    import Src.Contact.View.ContactView;

    public class AtomView extends Sprite {
        private var _atom:Atom;
        private var _windowType:String;
        private var _definition:Object;
        private var _label:TextField;
        private var _isDragging:Boolean = false;
        private var _dragOffset:Point = new Point();
        private var _viewConfig:Object;
        private var _isPressed:Boolean = false;

        public function AtomView(atom:Atom, windowType:String) {
            super();
            _atom = atom;
            _windowType = windowType;
            _definition = AtomDefinitions.getAtomDefinition(atom.type);
            setupView();
            updateVisuals();
            this.x = _atom.position.x;
            this.y = _atom.position.y;
            Impulsys.subscribeToImpulse("WINDOW_LEFT_RELEASE", handle_release_outside);
        }

        private function setupView():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            this.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            createLabel();
        }

        private function onMouseUp(event:MouseEvent):void {
            if (_isPressed) {
                _isPressed = false;
                handleInteraction("release");
            }
        }

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

        public function setBackgroundColor(color:uint):void {
            if (!_viewConfig) _viewConfig = {};
            _viewConfig.backgroundColor = color;
            updateVisuals();
        }

        public function setWidth(width:Number):void {
            if (!_viewConfig) _viewConfig = {};
            _viewConfig.width = width;
            updateVisuals();
        }

        public function setHeight(height:Number):void {
            if (!_viewConfig) _viewConfig = {};
            _viewConfig.height = height;
            updateVisuals();
        }

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

        public function updateAtom(newAtom:Atom):void {
            _atom = newAtom;
            this.x = _atom.position.x;
            this.y = _atom.position.y;
            updateVisuals();
        }

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

        private function validateDimension(value:*, defaultValue:Number):Number {
            if (value === undefined || value === null || isNaN(value) || value <= 0) {
                return defaultValue;
            }
            return Number(value);
        }

        private function updateLabel(config:Object):void {
            _label.text = _atom.name;
            _label.width = config.width;
            _label.height = 20;
            _label.y = (config.height - 20) / 2;
            _label.textColor = config.textColor || 0x000000;
        }

        private function updateContacts(config:Object):void {
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is ContactView) {
                    this.removeChildAt(i);
                }
            }

            for (var j:int = 0; j < _atom.contactInputs.length; j++) {
                var inputContact:Contact = _atom.contactInputs[j];
                var inputContactView:ContactView = new ContactView(inputContact);
                inputContactView.x = 0;
                inputContactView.y = (config.height * (j + 1) / (_atom.contactInputs.length + 1));
                inputContactView.mouseEnabled = true;
                inputContactView.mouseChildren = false;
                this.addChild(inputContactView);
            }

            for (var k:int = 0; k < _atom.contactOutputs.length; k++) {
                var outputContact:Contact = _atom.contactOutputs[k];
                var outputContactView:ContactView = new ContactView(outputContact);
                outputContactView.x = config.width;
                outputContactView.y = (config.height * (k + 1) / (_atom.contactOutputs.length + 1));
                outputContactView.mouseEnabled = true;
                outputContactView.mouseChildren = false;
                this.addChild(outputContactView);
            }
        }

        private function onMouseDown(event:MouseEvent):void {
            var target:DisplayObject = event.target as DisplayObject;
            while (target && target != this) {
                if (target is ContactView) {
                    return;
                }
                target = target.parent;
            }

            if (event.ctrlKey) {
                startDragMode(event);
            } else {
                _isPressed = true;
                handleInteraction("press");
            }
        }

        private function handleInteraction(interactionType:String):void {
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
                        AtomManager.getInstance().updateAtom(newAtom);
                    }
                } catch (error:Error) {
                }
            }
        }

        private function startDragMode(event:MouseEvent):void {
            if (!parent || !_atom) return;

            _isDragging = true;
            this.alpha = 0.7;

            var mouseWorld:Point = parent.globalToLocal(new Point(event.stageX, event.stageY));
            _dragOffset.x = mouseWorld.x - _atom.position.x;
            _dragOffset.y = mouseWorld.y - _atom.position.y;

            stage.addEventListener(MouseEvent.MOUSE_MOVE, onDrag);
            stage.addEventListener(MouseEvent.MOUSE_UP, onDragEnd);

            Impulsys.emit(new Impulse("ATOM_DRAG_START", {
                atom: _atom,
                view: this,
                startPosition: _atom.position.clone()
            }));
        }

        private function onDrag(event:MouseEvent):void {
            if (!_isDragging || !parent) return;

            var mouseWorld:Point = parent.globalToLocal(new Point(event.stageX, event.stageY));
            var newX:Number = mouseWorld.x - _dragOffset.x;
            var newY:Number = mouseWorld.y - _dragOffset.y;
            var newAtom:Atom = _atom.setPosition(new Point(newX, newY));

            Impulsys.emit(new Impulse("ATOM_MOVED", {
                oldAtom: _atom,
                newAtom: newAtom,
                updateLinks: true,
                isDragging: true
            }));

            _atom = newAtom;
            this.x = _atom.position.x;
            this.y = _atom.position.y;
            updateVisualsDuringDrag();
        }

        private function updateVisualsDuringDrag():void {
            var config:Object = getVisualConfig();
            updateContacts(config);
        }

        private function onDragEnd(event:MouseEvent):void {
            if (!_isDragging) return;

            _isDragging = false;
            this.alpha = 1.0;

            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);

            var finalAtom:Atom = _atom.setPosition(new Point(this.x, this.y));

            Impulsys.emit(new Impulse("ATOM_DRAG_END", {
                atom: _atom,
                view: this,
                finalPosition: new Point(this.x, this.y)
            }));

            _atom = finalAtom;
            this.x = _atom.position.x;
            this.y = _atom.position.y;
        }

        public function updateVisuals():void {
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

            if (visualConfig.draw is Function) {
                try {
                    visualConfig.draw(this.graphics, _atom, visualConfig);
                } catch (error:Error) {
                    drawDefault(this.graphics, visualConfig);
                }
            } else {
                drawDefault(this.graphics, visualConfig);
            }

            updateLabel(visualConfig);
            updateContacts(visualConfig);
        }

        private function getVisualConfig():Object {
            if (!_definition) {
                return getFallbackConfig();
            }

            var config:Object = null;

            if (_definition.visuals && _definition.visuals[_windowType]) {
                config = _definition.visuals[_windowType];

                if (!config.draw && _definition.visuals.base) {
                    var baseConfig:Object = _definition.visuals.base;
                    config = mergeConfig(baseConfig, config);
                }
            }
            else if (_definition.visuals && _definition.visuals.base) {
                config = _definition.visuals.base;
            }
            else if (_definition.viewConfig) {
                config = _definition.viewConfig;
            }
            else {
                config = getFallbackConfig();
            }

            return config;
        }

        private function getFallbackConfig():Object {
            return {
                width: 60,
                height: 40,
                color: 0xCCCCCC,
                textColor: 0x000000
            };
        }

        private function drawFallback():void {
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000);
            this.graphics.drawRect(0, 0, 60, 40);
            this.graphics.endFill();
        }

        private function mergeConfig(base:Object, overrides:Object):Object {
            var result:Object = {};
            for (var key:String in base) result[key] = base[key];
            for (key in overrides) result[key] = overrides[key];
            return result;
        }

        private function handle_release_outside(impulse:Impulse):void {
            if (_isPressed) {
                _isPressed = false;
                handleInteraction("release");
            }
        }

        public function dispose():void {
            removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);

            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);
            }

            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                var child:DisplayObject = this.getChildAt(i);
                if (child is ContactView) {
                    ContactView(child).dispose();
                    this.removeChildAt(i);
                }
            }

            if (_label && this.contains(_label)) {
                this.removeChild(_label);
                _label = null;
            }

            Impulsys.removeImpulse("WINDOW_LEFT_RELEASE", handle_release_outside);
        }

        public function get atom():Atom {
            return _atom;
        }
    }
}
