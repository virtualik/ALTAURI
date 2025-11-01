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

    /**
     * Universal view class that renders any atom type based on its data definition.
     * Handles visualization, user interactions, and pin management.
     * 
     * @class AtomView
     * @public
     */
    public class AtomView extends Sprite {
        /** The atom data this view represents */
        private var _atom:Atom;
        
        /** Window type for context-specific rendering */
        private var _windowType:String;
        
        /** Atom definition from AtomDefinitions */
        private var _definition:Object;
        
        /** Text label for atom name */
        private var _label:TextField;
        
        /** Dragging state flag */
        private var _isDragging:Boolean = false;
        
        /** Mouse offset during dragging */
        private var _dragOffset:Point = new Point();

        /**
         * Creates a new AtomView instance.
         * 
         * @constructor
         * @param {Atom} atom - The atom to visualize
         * @param {String} windowType - Window context ("Editor", "Device", etc.)
         */
        public function AtomView(atom:Atom, windowType:String) {
            _atom = atom;
            _windowType = windowType;
            _definition = AtomDefinitions.getAtomDefinition(atom.type);
            
            super();
            setupView();
            updateVisuals();
        }

        /**
         * Sets up the view with event listeners and initial configuration.
         * 
         * @private
         */
        private function setupView():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            createLabel();
        }

        /**
         * Creates the text label for displaying the atom name.
         * 
         * @private
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
         * Updates the view with a new atom instance (for immutable updates).
         * 
         * @param {Atom} newAtom - New atom instance
         */
        public function updateAtom(newAtom:Atom):void {
            _atom = newAtom;
            updateVisuals();
        }

        /**
         * Updates the visual representation based on atom state and definition.
         * 
         * @private
         */
        private function updateVisuals():void {
            var visualConfig:Object = _definition.visuals[_windowType] || _definition.visuals.default;
            
            // Clear previous graphics
            this.graphics.clear();
            
            // Use custom draw function or default
            if (visualConfig.draw is Function) {
                visualConfig.draw(this.graphics, _atom, visualConfig);
            } else {
                drawDefault(this.graphics, visualConfig);
            }
            
            updateLabel(visualConfig);
            updatePins(visualConfig);
        }

        /**
         * Default drawing implementation when no custom draw function is provided.
         * 
         * @private
         * @param {Graphics} graphics - Graphics object to draw on
         * @param {Object} config - Visual configuration object
         */
        private function drawDefault(graphics:Graphics, config:Object):void {
            graphics.beginFill(config.color || 0xCCCCCC);
            if (config.cornerRadius) {
                graphics.drawRoundRect(0, 0, config.width, config.height, config.cornerRadius, config.cornerRadius);
            } else {
                graphics.drawRect(0, 0, config.width, config.height);
            }
            graphics.endFill();
        }

        /**
         * Updates the text label based on visual configuration.
         * 
         * @private
         * @param {Object} config - Visual configuration object
         */
        private function updateLabel(config:Object):void {
            _label.text = _atom.name;
            _label.width = config.width;
            _label.height = 20;
            _label.y = (config.height - 20) / 2;
            _label.textColor = config.textColor || 0x000000;
        }

        /**
         * Updates the pin visualizations based on atom's current pins.
         * 
         * @private
         * @param {Object} config - Visual configuration object
         */
        private function updatePins(config:Object):void {
            // Remove existing pins
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is PinView) {
                    this.removeChildAt(i);
                }
            }
            
            // Add input pins (left side)
            for (var j:int = 0; j < _atom.inputs.length; j++) {
                var inputPin:PinView = new PinView(_atom.inputs[j]);
                inputPin.x = 0;
                inputPin.y = config.height * (j + 1) / (_atom.inputs.length + 1);
                this.addChild(inputPin);
            }
            
            // Add output pins (right side)
            for (var k:int = 0; k < _atom.outputs.length; k++) {
                var outputPin:PinView = new PinView(_atom.outputs[k]);
                outputPin.x = config.width;
                outputPin.y = config.height * (k + 1) / (_atom.outputs.length + 1);
                this.addChild(outputPin);
            }
        }

        /**
         * Handles mouse down events for dragging and interactions.
         * 
         * @private
         * @param {MouseEvent} event - Mouse event
         */
        private function onMouseDown(event:MouseEvent):void {
            if (event.ctrlKey) {
                startDragMode(event);
            } else {
                handleInteraction("press");
            }
        }

        /**
         * Enters drag mode for atom repositioning.
         * 
         * @private
         * @param {MouseEvent} event - Mouse event that started dragging
         */
        private function startDragMode(event:MouseEvent):void {
            _isDragging = true;
            _dragOffset.setTo(event.localX, event.localY);
            this.alpha = 0.7;
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onDrag);
            stage.addEventListener(MouseEvent.MOUSE_UP, onDragEnd);
        }

        /**
         * Handles atom movement during dragging.
         * 
         * @private
         * @param {MouseEvent} event - Mouse move event
         */
        private function onDrag(event:MouseEvent):void {
            if (_isDragging) {
                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);
                this.x = localPos.x - _dragOffset.x;
                this.y = localPos.y - _dragOffset.y;
                
                MultiPulsator.emit(new Impulse("ATOM_DRAGGING", {
                    atom: _atom,
                    position: new Point(this.x, this.y)
                }));
            }
        }

        /**
         * Handles end of drag operation and updates atom position.
         * 
         * @private
         * @param {MouseEvent} event - Mouse up event
         */
        private function onDragEnd(event:MouseEvent):void {
            if (_isDragging) {
                _isDragging = false;
                this.alpha = 1.0;
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);
                
                var newAtom:Atom = _atom.setPosition(new Point(this.x, this.y));
                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    oldAtom: _atom,
                    newAtom: newAtom
                }));
            }
        }

        /**
         * Handles atom-specific interactions (clicks, presses, etc.).
         * 
         * @private
         * @param {String} interactionType - Type of interaction
         */
        private function handleInteraction(interactionType:String):void {
            MultiPulsator.emit(new Impulse("ATOM_INTERACTION", {
                atom: _atom,
                interactionType: interactionType,
                view: this
            }));
        }

        /**
         * Gets the atom associated with this view.
         * 
         * @return {Atom} The atom instance
         */
        public function get atom():Atom { return _atom; }

        /**
         * Cleans up resources and event listeners.
         */
        public function dispose():void {
            removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);
            }
            // Remove all pin views
            for (var i:int = this.numChildren - 1; i >= 0; i--) {
                if (this.getChildAt(i) is PinView) {
                    this.removeChildAt(i);
                }
            }
        }
    }
}
