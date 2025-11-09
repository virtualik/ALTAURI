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
     * Manages data flow and visualization between connected atoms.
     *
     * Key changes:
     * - All data propagation now handled via direct onInputChange → updateAtom()
     * - On dispose, emits PIN_DISCONNECTED to reset target pin to null
     *
     * @class Track
     * @extends Sprite
     * @public
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
        /** Reference to track manager for coordinate calculations */
        private var _trackManager:TrackManager;
        /** Data flow animation visual */
        private var _flowAnimation:DataFlowAnimation;

        /**
         * Creates a new Track connection between pins.
         *
         * @constructor
         * @param {Pin} fromPin - Source pin (must be OUTPUT type)
         * @param {Pin} toPin - Target pin (must be INPUT type)
         * @param {TrackManager} trackManager - Track manager reference
         */
        public function Track(fromPin:Pin, toPin:Pin, trackManager:TrackManager) {
            if (fromPin.type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("From pin must be OUTPUT type");
            }
            if (toPin.type != Pin.TYPE_INPUT) {
                throw new ArgumentError("To pin must be INPUT type");
            }
            _fromPin = fromPin;
            _toPin = toPin;
            _trackManager = trackManager;
            _connectionId = generateConnectionId();
            setupPinSubscription();
            setupEventListeners();
            drawTrack();
        }

        /**
         * Sets up direct pin-to-pin data subscription.
         * Entirely self-contained: calls onInputChange → updateAtom().
         */
        private function setupPinSubscription():void {
            trace("Track setting up DIRECT pin subscription for: " + _connectionId);
            trace("From pin: " + _fromPin.name + " (" + _fromPin.type + ", id: " + _fromPin.id + ")");
            trace("To pin: " + _toPin.name + " (" + _toPin.type + ", id: " + _toPin.id + ")");

            // Колбэк подписки
            var onPinEvent:Function = function(event:PinEvent):void {
                if (event.type == Pin.PIN_VALUE_CHANGED) {
                    trace("=== DIRECT PIN SUBSCRIPTION TRIGGERED ===");
                    trace("Track: " + _connectionId);
                    trace("From: " + event.sourcePin.name + " → To: " + _toPin.name + " = " + event.newValue);

                    var targetAtom:Atom = _trackManager.getAtomByPin(_toPin);
                    if (!targetAtom) {
                        trace("ERROR: Target atom not found for pin: " + _toPin.name);
                        return;
                    }
                    var newAtom:Atom;
                    var definition:Object = AtomDefinitions.getAtomDefinition(targetAtom.type);
                    if (definition && definition.behavior && definition.behavior.onInputChange) {
                        newAtom = definition.behavior.onInputChange(targetAtom, _toPin.name, event.newValue);
                        AtomManager.getInstance().updateAtom(newAtom);
                    } else {
                        newAtom = targetAtom.setPinValue(_toPin.name, event.newValue, true);
                        AtomManager.getInstance().updateAtom(newAtom);
                    }
                    trace("=== DIRECT SUBSCRIPTION → VIEW UPDATED ===");
                }
                else if (event.type == Pin.PIN_DISCONNECTED) {
                    trace("=== DIRECT PIN SUBSCRIPTION: DISCONNECTED ===");
                    // При отключении — сбрасываем значение на null
                    var targetAtom:Atom = _trackManager.getAtomByPin(_toPin);
                    if (!targetAtom) return;
                    var definition:Object = AtomDefinitions.getAtomDefinition(targetAtom.type);
                    if (definition && definition.behavior && definition.behavior.onInputChange) {
                        var newAtom:Atom = definition.behavior.onInputChange(targetAtom, _toPin.name, null);
                        AtomManager.getInstance().updateAtom(newAtom);
                    } else {
                        var newAtom:Atom = targetAtom.setPinValue(_toPin.name, null, true);
                        AtomManager.getInstance().updateAtom(newAtom);
                    }
                }
            };

            var subscriptionCreated:Boolean = _toPin.subscribeToPin(_fromPin, [Pin.PIN_VALUE_CHANGED, Pin.PIN_DISCONNECTED], onPinEvent);

            if (subscriptionCreated) {
                trace("✓ Direct pin subscription created successfully");

                // === ПЕРЕДАЧА НАЧАЛЬНОГО ЗНАЧЕНИЯ ===
                if (_fromPin.value !== undefined && _fromPin.value !== null) {
                    trace("➡️ Propagating initial value on connection: " + _fromPin.value);
                    var initEvent:PinEvent = new PinEvent(Pin.PIN_VALUE_CHANGED, _fromPin, _fromPin.value, undefined);
                    onPinEvent(initEvent);
                }
            } else {
                trace("✗ Failed to create direct pin subscription");
            }
        }

        private function setupEventListeners():void {
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
        }

        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:Atom = impulse.data.newAtom;
            if (isConnectedToAtom(movedAtom.id)) {
                drawTrack();
            }
        }

        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            Impulsys.emit(new Impulse("TRACK_RIGHT_CLICK", {
                track: this,
                globalPosition: new Point(event.stageX, event.stageY),
                connectionId: _connectionId,
                window: event.currentTarget.root.nativeWindow
            }));
        }

        public function drawTrack():void {
            this.graphics.clear();
            var fromPos:Point = _trackManager.getGlobalPinPosition(_fromPin);
            var toPos:Point = _trackManager.getGlobalPinPosition(_toPin);
            var tracksLayer:Sprite = this.parent as Sprite;
            if (!tracksLayer) return;
            var localFrom:Point = tracksLayer.globalToLocal(fromPos);
            var localTo:Point = tracksLayer.globalToLocal(toPos);
            var lineColor:uint = 0x777777;
            var lineAlpha:Number = 0.5;
            var lineThickness:Number = 2;
            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);
        }

        public function updateVisual():void {
            drawTrack();
        }

        public function isConnectedToAtom(atomId:String):Boolean {
            return _connectionId.indexOf(atomId) !== -1;
        }

        public function isConnectedToPin(pin:Pin):Boolean {
            return _fromPin == pin || _toPin == pin;
        }

        public function getConnectionInfo():Object {
            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);
            return {
                fromAtom: fromAtom ? fromAtom.id : "unknown",
                fromPin: _fromPin.name,
                toAtom: toAtom ? toAtom.id : "unknown",
                toPin: _toPin.name,
                connectionId: _connectionId,
                isActive: _isActive
            };
        }

        private function generateConnectionId():String {
            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);
            if (!fromAtom || !toAtom) {
                return "track_invalid_" + Math.random().toString(36).substr(2, 9);
            }
            return "track_" + fromAtom.id + "_" + _fromPin.name + "_to_" +
                   toAtom.id + "_" + _toPin.name;
        }

        private function startDataFlowAnimation(value:*):void {
            if (!_flowAnimation) {
                _flowAnimation = new DataFlowAnimation();
                this.addChild(_flowAnimation);
            }
            _flowAnimation.animate(_fromPin, _toPin, value);
        }

        public function createLogicalConnection():void {
            _isActive = true;
            Impulsys.emit(new Impulse("TRACK_CONNECTED", {
                track: this,
                fromPin: _fromPin,
                toPin: _toPin,
                connectionId: _connectionId
            }));
        }

        public function dispose():void {
            _isActive = false;

			if (_toPin && _fromPin) {
				// === СБРОС ЗНАЧЕНИЯ В ПОЛУЧАТЕЛЕ ===
				var targetAtom:Atom = _trackManager.getAtomByPin(_toPin);
				if (targetAtom) {
					var definition:Object = AtomDefinitions.getAtomDefinition(targetAtom.type);
					if (definition.behavior.onInputChange) {
						// Вызываем onInputChange с null
						var newAtom:Atom = definition.behavior.onInputChange(targetAtom, _toPin.name, null);
						AtomManager.getInstance().updateAtom(newAtom);
					} else {
						var newAtom:Atom = targetAtom.setPinValue(_toPin.name, null, true);
						AtomManager.getInstance().updateAtom(newAtom);
					}
				}

				// Теперь отписываемся
				_toPin.unsubscribeFromPin(_fromPin, Pin.PIN_VALUE_CHANGED);
				trace("Track: Removed direct pin subscription and reset receiver to null");
			}

            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            this.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            
            if (_flowAnimation != null) {
                if (_flowAnimation.hasOwnProperty("dispose")) {
                    try {
                        _flowAnimation["dispose"]();
                    } catch (e:Error) {
                        trace("Track.dispose: Error disposing flow animation - " + e.message);
                    }
                }
                if (this.contains(_flowAnimation)) {
                    this.removeChild(_flowAnimation);
                }
                _flowAnimation = null;
            }
            this.graphics.clear();
            Impulsys.emit(new Impulse("TRACK_DISCONNECTED", {
                track: this,
                connectionId: _connectionId
            }));
            if (this.parent != null) {
                this.parent.removeChild(this);
            }
            _fromPin = null;
            _toPin = null;
            _trackManager = null;
        }

        public function get fromPin():Pin { return _fromPin; }
        public function get toPin():Pin { return _toPin; }
        public function get connectionId():String { return _connectionId; }
        public function get isActive():Boolean { return _isActive; }
    }
}
