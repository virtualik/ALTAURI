package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.display.Graphics;
    import Src.Prog.Core.Window;

    /**
     * Universal view class that renders any atom type based on its data definition.
     * Handles visualization, user interactions, and pin management.
     * Fully synchronized with logical atom model — no direct x/y manipulation during drag.
     */
    public class AtomView extends Sprite {
        private var _atom:Atom;
        private var _windowType:String;
        private var _definition:Object;
        private var _label:TextField;
        private var _isDragging:Boolean = false;
        private var _dragOffset:Point = new Point();
        private var _viewConfig:Object;

        public function AtomView(atom:Atom, windowType:String) {
            _atom = atom;
            _windowType = windowType;
            _definition = AtomDefinitions.getAtomDefinition(atom.type);
            super();
            setupView();
            updateVisuals();
            // Initial position from atom model
            this.x = _atom.position.x;
            this.y = _atom.position.y;
        }

        private function setupView():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            createLabel();
        }

        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            MultiPulsator.emit(new Impulse("ATOM_RIGHT_CLICK", {
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
            // Sync visual position with logical model
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

        private function updatePins(config:Object):void {
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is PinView) {
                    this.removeChildAt(i);
                }
            }
            for (var j:int = 0; j < _atom.inputs.length; j++) {
                var inputPin:PinView = new PinView(_atom.inputs[j]);
                inputPin.x = 0;
                inputPin.y = config.height * (j + 1) / (_atom.inputs.length + 1);
                this.addChild(inputPin);
            }
            for (var k:int = 0; k < _atom.outputs.length; k++) {
                var outputPin:PinView = new PinView(_atom.outputs[k]);
                outputPin.x = config.width;
                outputPin.y = config.height * (k + 1) / (_atom.outputs.length + 1);
                this.addChild(outputPin);
            }
        }

        private function onMouseDown(event:MouseEvent):void {
            if (event.ctrlKey) {
                startDragMode(event);
            } else {
                handleInteraction("press");
            }
        }

		private function startDragMode(event:MouseEvent):void {
			if (!parent || !_atom) return;

			_isDragging = true;
			this.alpha = 0.7;

			// Получаем позицию курсора в мировых координатах (contentLayer)
			var mouseWorld:Point = parent.globalToLocal(new Point(event.stageX, event.stageY));
			
			// Текущая позиция атома — это _atom.position (уже в мировых координатах)
			// Смещение = где кликнули относительно центра/начала атома в мире
			_dragOffset.x = mouseWorld.x - _atom.position.x;
			_dragOffset.y = mouseWorld.y - _atom.position.y;

			stage.addEventListener(MouseEvent.MOUSE_MOVE, onDrag);
			stage.addEventListener(MouseEvent.MOUSE_UP, onDragEnd);

			MultiPulsator.emit(new Impulse("ATOM_DRAG_START", {
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

    // ... emit impulses ...
            MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                oldAtom: _atom,
                newAtom: newAtom,
                updateTracks: true,
                isDragging: false
            }));

    _atom = newAtom;
    this.x = _atom.position.x;
    this.y = _atom.position.y;
}

        private function onDragEnd(event:MouseEvent):void {
            if (!_isDragging) return;

            _isDragging = false;
            this.alpha = 1.0;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);

            // Final update (should already be in sync, but ensure)
            var finalAtom:Atom = _atom.setPosition(new Point(this.x, this.y));
            MultiPulsator.emit(new Impulse("ATOM_DRAG_END", {
                atom: _atom,
                view: this,
                finalPosition: new Point(this.x, this.y)
            }));

            _atom = finalAtom;
            this.x = _atom.position.x;
            this.y = _atom.position.y;
        }

        private function handleInteraction(interactionType:String):void {
            MultiPulsator.emit(new Impulse("ATOM_INTERACTION", {
                atom: _atom,
                interactionType: interactionType,
                view: this
            }));
        }

        public function get atom():Atom { return _atom; }

        private function updateVisuals():void {
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
                visualConfig.draw(this.graphics, _atom, visualConfig);
            } else {
                drawDefault(this.graphics, visualConfig);
            }

            updateLabel(visualConfig);
            updatePins(visualConfig);
        }

        private function getVisualConfig():Object {
            if (!_definition) return getFallbackConfig();
            if (_definition.visuals && _definition.visuals[_windowType]) {
                return _definition.visuals[_windowType];
            }
            if (_definition.visuals && _definition.visuals.base) {
                return _definition.visuals.base;
            }
            if (_definition.viewConfig) {
                return _definition.viewConfig;
            }
            return getFallbackConfig();
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

        public function dispose():void {
            removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);
            }
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is PinView) {
                    this.removeChildAt(i);
                }
            }
        }
    }
}
