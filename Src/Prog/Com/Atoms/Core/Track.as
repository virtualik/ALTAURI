package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.display.Graphics;

    /**
     * Visual and logical connection between two pins.
     * Now fully autonomous - manages its own lifecycle and event subscriptions.
     *
     * Key changes:
     * - Removed TrackManager dependency
     * - Self-registration in TrackRegistry
     * - Autonomous event handling
     * - Self-contained visual management
     */
    public class Track extends Sprite {
        /** Source pin (output) */
        private var _fromPin:Pin;
        /** Target pin (input) */
        private var _toPin:Pin;
        /** Unique connection identifier */
        private var _connectionId:String;
        /** Whether the track is actively transferring data */
        private var _isActive:Boolean = false;
        /** Parent window reference */
        private var _parentWindow:Window;

        /**
         * Creates a new Track connection between pins.
         * Automatically registers itself and sets up subscriptions.
         *
         * @constructor
         * @param {Pin} fromPin - Source pin (must be OUTPUT type)
         * @param {Pin} toPin - Target pin (must be INPUT type)
         */
        public function Track(fromPin:Pin, toPin:Pin) {
            if (fromPin.type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("From pin must be OUTPUT type");
            }
            if (toPin.type != Pin.TYPE_INPUT) {
                throw new ArgumentError("To pin must be INPUT type");
            }

            _fromPin = fromPin;
            _toPin = toPin;
            _connectionId = generateConnectionId();
            _parentWindow = findParentWindow();

            // Auto-register with track registry
            TrackRegistry.getInstance().registerTrack(this);

            // Setup all necessary components
            setupEventListeners();
            setupPinSubscription();
            addToVisualLayer();
            drawTrack();
            createLogicalConnection();

            trace("Track created: " + _connectionId);
        }

        /**
         * Sets up all event listeners for autonomous operation.
         *
         * @private
         */
        private function setupEventListeners():void {
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
        }

        /**
         * Sets up direct pin-to-pin data subscription.
         * Entirely self-contained: calls onInputChange → updateAtom().
         *
         * @private
         */
        private function setupPinSubscription():void {
            trace("Track setting up DIRECT pin subscription for: " + _connectionId);
            trace("From pin: " + _fromPin.name + " (" + _fromPin.type + ", id: " + _fromPin.id + ")");
            trace("To pin: " + _toPin.name + " (" + _toPin.type + ", id: " + _toPin.id + ")");

            // Колбэк подписки
            var onPinEvent:Function = function(event:PinEvent):void {
                if (event.type == Pin.PIN_VALUE_CHANGED) {
                    handleValueChange(event);
                }
                else if (event.type == Pin.PIN_DISCONNECTED) {
                    handleDisconnection();
                }
            };

            // 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Правильная подписка
            var subscriptionCreated:Boolean = _toPin.subscribeToPin(_fromPin,
                [Pin.PIN_VALUE_CHANGED, Pin.PIN_DISCONNECTED], onPinEvent);

            if (subscriptionCreated) {
                trace("✓ Direct pin subscription created successfully");

                // === НЕМЕДЛЕННАЯ ПЕРЕДАЧА ТЕКУЩЕГО ЗНАЧЕНИЯ ===
                if (_fromPin.value !== undefined && _fromPin.value !== null) {
                    trace("➡️ Propagating initial value on connection: " + _fromPin.value);
                    // Создаем событие для немедленной передачи текущего значения
                    var initialEvent:PinEvent = new PinEvent(
                        Pin.PIN_VALUE_CHANGED, 
                        _fromPin, 
                        _fromPin.value, 
                        undefined
                    );
                    onPinEvent(initialEvent);
                }
            } else {
                trace("✗ Failed to create direct pin subscription");
            }
        }

        /**
         * Handles value changes from source pin.
         * FIXED: Proper value propagation to target atom
         *
         * @private
         * @param {PinEvent} event - Pin value change event
         */
        private function handleValueChange(event:PinEvent):void {
            trace("=== DIRECT PIN SUBSCRIPTION TRIGGERED ===");
            trace("Track: " + _connectionId);
            trace("From: " + event.sourcePin.name + " → To: " + _toPin.name + " = " + event.newValue);

            var targetAtom:Atom = getAtomByPin(_toPin);
            if (!targetAtom) {
                trace("ERROR: Target atom not found for pin: " + _toPin.name);
                return;
            }

            var newAtom:Atom;
            var definition:Object = AtomDefinitions.getAtomDefinition(targetAtom.type);
            
            // 🔥 ИСПРАВЛЕНИЕ: Правильное обновление атома
            if (definition && definition.behavior && definition.behavior.onInputChange) {
                newAtom = definition.behavior.onInputChange(targetAtom, _toPin.name, event.newValue);
            } else {
                // Прямое обновление значения пина
                newAtom = targetAtom.setPinValue(_toPin.name, event.newValue, true);
            }
            
            if (newAtom !== targetAtom) {
                AtomManager.getInstance().updateAtom(newAtom);
                trace("✓ Atom updated via behavior");
            } else {
                trace("⚠ Atom not changed by behavior");
            }
            
            trace("=== DIRECT SUBSCRIPTION COMPLETE ===");
        }

        /**
         * Handles pin disconnection events.
         *
         * @private
         */
		private function handleDisconnection():void {
			trace("=== TRACK DISCONNECTION HANDLER ===");

			var targetAtom:Atom = getAtomByPin(_toPin);
			if (!targetAtom) {
				trace("WARNING: Target atom not found for pin: " + _toPin.name);
				return;
			}

			trace("Resetting input pin: " + _toPin.name + " to undefined");

			var definition:Object = AtomDefinitions.getAtomDefinition(targetAtom.type);
			var newAtom:Atom;

			if (definition && definition.behavior && definition.behavior.onInputChange) {
				// Используем behavior для правильного сброса
				newAtom = definition.behavior.onInputChange(targetAtom, _toPin.name, undefined);
			} else {
				// Прямое обновление пина
				newAtom = targetAtom.setPinValue(_toPin.name, undefined, true);
			}

			AtomManager.getInstance().updateAtom(newAtom);
			trace("Input pin successfully reset to undefined");
		}

        /**
         * Adds track to the appropriate visual layer.
         *
         * @private
         */
        private function addToVisualLayer():void {
            if (_parentWindow && _parentWindow.tracksLayer) {
                _parentWindow.tracksLayer.addChild(this);
                trace("Track added to tracksLayer");
            } else if (_parentWindow && _parentWindow.contentLayer) {
                _parentWindow.contentLayer.addChild(this);
                trace("Track added to contentLayer (fallback)");
            } else {
                trace("WARNING: No suitable layer found for track");
            }
        }

        /**
         * Finds parent window for this track.
         *
         * @private
         * @return {Window} Parent window or null
         */
        private function findParentWindow():Window {
            var fromAtom:Atom = getAtomByPin(_fromPin);
            if (!fromAtom) return null;

            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(fromAtom.id);
            if (!atomData || !atomData.view) return null;

            var atomView:AtomView = atomData.view;
            if (!atomView.stage) return null;

            return atomView.stage.nativeWindow as Window;
        }

        /**
         * Gets atom that owns the specified pin.
         *
         * @private
         * @param {Pin} pin - Pin to find owner for
         * @return {Atom} Atom that owns the pin, or null if not found
         */
        private function getAtomByPin(pin:Pin):Atom {
            return TrackRegistry.getInstance().getAtomByPin(pin);
        }

        /**
         * Handles atom movement to update track visualization.
         *
         * @private
         * @param {Impulse} impulse - ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:Atom = impulse.data.newAtom;
            if (isConnectedToAtom(movedAtom.id)) {
                drawTrack();
            }
        }

        /**
         * Handles right-click for context menu.
         *
         * @private
         * @param {MouseEvent} event - Right mouse down event
         */
        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            Impulsys.emit(new Impulse("TRACK_RIGHT_CLICK", {
                track: this,
                globalPosition: new Point(event.stageX, event.stageY),
                connectionId: _connectionId,
                window: event.currentTarget.root.nativeWindow
            }));
        }

        /**
         * Draws the track visualization between pins.
         *
         * @public
         */
        public function drawTrack():void {
            this.graphics.clear();

            var fromPos:Point = getGlobalPinPosition(_fromPin);
            var toPos:Point = getGlobalPinPosition(_toPin);

            if (!_parentWindow) return;

            var tracksLayer:Sprite = this.parent as Sprite;
            if (!tracksLayer) return;

            var localFrom:Point = tracksLayer.globalToLocal(fromPos);
            var localTo:Point = tracksLayer.globalToLocal(toPos);

            var lineColor:uint = 0x777777;
            var lineAlpha:Number = 0.5;
            var lineThickness:Number = 4;

            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);
        }

        /**
         * Gets global position of a pin.
         *
         * @private
         * @param {Pin} pin - Pin to get position for
         * @return {Point} Global position coordinates
         */
		private function getGlobalPinPosition(pin:Pin):Point {
			var pinView:PinView = findPinView(pin);
			if (pinView && pinView.stage) {
				return pinView.localToGlobal(new Point(0, 0));
			}

			// Fallback: calculate from atom position
			var atom:Atom = getAtomByPin(pin);
			var atomView:AtomView = TrackRegistry.getInstance().getAtomView(atom);
			if (atomView && atomView.stage) {
				// ВМЕСТО TrackRegistry.getInstance().getPinIndex() используем локальный расчет:
				var pinIndex:int = calculatePinIndex(atom, pin);
				var totalPins:int = pin.type == Pin.TYPE_INPUT ? atom.inputs.length : atom.outputs.length;
				var pinY:Number = atomView.height * (pinIndex + 1) / (totalPins + 1);
				var pinX:Number = pin.type == Pin.TYPE_INPUT ? 0 : atomView.width;

				var atomGlobal:Point = atomView.localToGlobal(new Point(pinX, pinY));
				return atomGlobal;
			}

			return new Point(100, 100); // Fallback position
		}

		/**
		 * Calculates pin index within its parent atom's pin collection.
		 * @private
		 */
		private function calculatePinIndex(atom:Atom, pin:Pin):int {
			var pins:Vector.<Pin> = pin.type == Pin.TYPE_INPUT ? atom.inputs : atom.outputs;
			for (var i:int = 0; i < pins.length; i++) {
				if (pins[i] === pin) {
					return i;
				}
			}
			return 0;
		}

		/**
         * Finds PinView for a given Pin.
         *
         * @private
         * @param {Pin} pin - Pin to find view for
         * @return {PinView} Found PinView or null
         */
        private function findPinView(pin:Pin):PinView {
            var atom:Atom = getAtomByPin(pin);
            if (!atom) return null;

            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(atom.id);
            if (!atomData || !atomData.view) return null;

            var atomView:AtomView = atomData.view;

            // Search through atom view children for PinView
            for (var i:int = 0; i < atomView.numChildren; i++) {
                var child:Object = atomView.getChildAt(i);
                if (child is PinView) {
                    var pinView:PinView = child as PinView;
                    if (pinView.pin === pin) {
                        return pinView;
                    }
                }
            }

            return null;
        }

        /**
         * Updates track visual (alias for drawTrack).
         *
         * @public
         */
        public function updateVisual():void {
            drawTrack();
        }

        /**
         * Checks if track is connected to specified atom.
         *
         * @public
         * @param {String} atomId - Atom identifier to check
         * @return {Boolean} True if connected to atom
         */
        public function isConnectedToAtom(atomId:String):Boolean {
            var fromAtom:Atom = getAtomByPin(_fromPin);
            var toAtom:Atom = getAtomByPin(_toPin);

            return (fromAtom && fromAtom.id == atomId) || (toAtom && toAtom.id == atomId);
        }

        /**
         * Checks if track is connected to specified pin.
         *
         * @public
         * @param {Pin} pin - Pin to check
         * @return {Boolean} True if connected to pin
         */
        public function isConnectedToPin(pin:Pin):Boolean {
            return _fromPin == pin || _toPin == pin;
        }

        /**
         * Gets connection information.
         *
         * @public
         * @return {Object} Connection information object
         */
        public function getConnectionInfo():Object {
            var fromAtom:Atom = getAtomByPin(_fromPin);
            var toAtom:Atom = getAtomByPin(_toPin);
            return {
                fromAtom: fromAtom ? fromAtom.id : "unknown",
                fromPin: _fromPin.name,
                toAtom: toAtom ? toAtom.id : "unknown",
                toPin: _toPin.name,
                connectionId: _connectionId,
                isActive: _isActive
            };
        }

        /**
         * Generates unique connection identifier.
         *
         * @private
         * @return {String} Unique connection ID
         */
        private function generateConnectionId():String {
            var fromAtom:Atom = getAtomByPin(_fromPin);
            var toAtom:Atom = getAtomByPin(_toPin);
            if (!fromAtom || !toAtom) {
                return "track_invalid_" + Math.random().toString(36).substr(2, 9);
            }
            return "track_" + fromAtom.id + "_" + _fromPin.name + "_to_" +
                   toAtom.id + "_" + _toPin.name;
        }

        /**
         * Creates logical connection and notifies system.
         *
         * @public
         */
        public function createLogicalConnection():void {
            _isActive = true;
            Impulsys.emit(new Impulse("TRACK_CONNECTED", {
                track: this,
                fromPin: _fromPin,
                toPin: _toPin,
                connectionId: _connectionId
            }));
        }

        /**
         * Completely disposes the track and all its resources.
         * Enhanced with autonomous cleanup.
         *
         * @public
         */
        public function dispose():void {
            trace("=== TRACK DISPOSE ===");
            trace("Disposing track: " + _connectionId);

            _isActive = false;

            // 1. Сбрасываем значение входного пина в undefined
            handleDisconnection();

            // 2. Отписываемся от событий пинов
            if (_toPin && _fromPin) {
                _toPin.unsubscribeFromPin(_fromPin);
                trace("Track: Removed pin subscription");
            }

            // 3. Удаляем слушатели Impulsys
            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            this.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);

            // 4. Очищаем графику
            this.graphics.clear();

            // 5. Удаляем из TrackRegistry
            TrackRegistry.getInstance().unregisterTrack(this);

            // 6. Уведомляем систему
            Impulsys.emit(new Impulse("TRACK_DISCONNECTED", {
                track: this,
                connectionId: _connectionId
            }));

            // 7. Удаляем из родительского контейнера
            if (this.parent != null) {
                this.parent.removeChild(this);
                trace("Track: Removed from display list");
            }

            // 8. Очищаем ссылки
            _fromPin = null;
            _toPin = null;
            _parentWindow = null;

            trace("=== TRACK DISPOSED: " + _connectionId + " ===");
        }

        // =========================================================================
        // PUBLIC ACCESSORS
        // =========================================================================

        public function get fromPin():Pin { return _fromPin; }
        public function get toPin():Pin { return _toPin; }
        public function get connectionId():String { return _connectionId; }
        public function get isActive():Boolean { return _isActive; }
        public function get parentWindow():Window { return _parentWindow; }
    }
}