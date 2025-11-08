package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Windows.Window;

    /**
     * Visual and logical connection between two pins.
     * Manages data flow and visualization between connected atoms.
     * 
     * Key improvements:
     * - Fixed boolean evaluation warnings
     * - Enhanced error handling and resource cleanup
     * - Improved pin subscription management
     * - Better visualization updates
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

        /** Handler reference for proper cleanup */
        private var _pinDataListener:Function;

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

          //  setupPinSubscription();
            setupEventListeners();
            drawTrack();
        }

        /**
         * Sets up direct pin-to-pin data subscription.
         * Establishes listener for source pin value changes.
         *
         * @private
         */
		//private function setupPinSubscription():void {
		//	trace("Track setting up impulse subscription for: " + _connectionId);
		//	
		//	// Подписываемся на импульсы от исходного пина
		//	Impulsys.subscribeToImpulse("PIN_VALUE_CHANGED", onPinValueChanged);
		//}

        /**
         * Sets up impulse event listeners for system coordination.
         * Subscribes to atom movement and pin value change events.
         *
         * @private
         */
        private function setupEventListeners():void {
            Impulsys.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.subscribeToImpulse("PIN_VALUE_CHANGED", onPinValueChanged);
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
        }

        /**
         * Handles data changes from the source pin.
         * Transfers data to target pin and triggers visualization.
         *
         * @private
         * @param {*} newValue - New data value
         * @param {*} oldValue - Previous data value
         * @param {Pin} sourcePin - Source pin that changed
         */
		private function onSourceDataChanged(newValue:*, oldValue:*, sourcePin:Pin):void {
			trace("=== TRACK DATA FLOW ===");
			trace("Track " + _connectionId + " received data:");
			trace("From pin: " + sourcePin.name + " (" + sourcePin.type + ")");
			trace("Value: " + newValue + " (old: " + oldValue + ")");
			trace("To pin: " + _toPin.name + " (" + _toPin.type + ")");
			
			// 1. Transfer data to target pin
			transferValueToTarget(newValue);

			// 2. Visualize data flow
			startDataFlowAnimation(newValue);

			// 3. Activate logical connection if not already active
			if (!_isActive) {
				createLogicalConnection();
			}
			
			trace("=== END TRACK DATA FLOW ===");
		}

        /**
         * Transfers data value to the target pin.
         *
         * @private
         * @param {*} value - Data value to transfer
         */
		private function transferValueToTarget(value:*):void {
			trace("Transferring value " + value + " to target pin: " + _toPin.name);
			
			var oldValue:* = _toPin.value;
			_toPin.value = value;
			
			trace("Target pin value set to: " + _toPin.value);
			
			// Отправляем импульс для целевого атома
			var toAtom:Atom = _trackManager.getAtomByPin(_toPin);
			if (toAtom) {
				trace("Emitting PIN_VALUE_CHANGED for target atom: " + toAtom.id);
				Impulsys.emit(new Impulse("PIN_VALUE_CHANGED", {
					atomId: toAtom.id,
					pinName: _toPin.name,
					newValue: value,
					oldValue: oldValue,
					source: "track_transfer"
				}));
			}
		}

        /**
         * Starts data flow visualization animation.
         *
         * @private
         * @param {*} value - Data value for visualization styling
         */
        private function startDataFlowAnimation(value:*):void {
            if (!_flowAnimation) {
                _flowAnimation = new DataFlowAnimation();
                this.addChild(_flowAnimation);
            }
            _flowAnimation.animate(_fromPin, _toPin, value);
        }

        /**
         * Activates the logical connection and notifies system.
         * Marks track as active and emits connection event.
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
         * Handles pin value changes for visualization updates.
         * Redraws track when connected pin values change.
         *
         * @private
         * @param {Impulse} impulse - PIN_VALUE_CHANGED impulse
         */
		private function onPinValueChanged(impulse:Impulse):void {
			var atomId:String = impulse.data.atomId;
			var pinName:String = impulse.data.pinName;
			var newValue:* = impulse.data.newValue;
			
			// Проверяем, что импульс от нашего исходного пина
			var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
			if (fromAtom && fromAtom.id == atomId && pinName == _fromPin.name) {
				trace("Track " + _connectionId + " forwarding data from " + fromAtom.type + "." + pinName);
				transferValueToTarget(newValue);
				startDataFlowAnimation(newValue);
				
				if (!_isActive) {
					createLogicalConnection();
				}
			}
		}

        /**
         * Generates unique connection identifier.
         * Uses atom and pin information for meaningful ID.
         *
         * @private
         * @return {String} Unique connection ID
         */
        private function generateConnectionId():String {
            var fromAtom:Atom = _trackManager.getAtomByPin(_fromPin);
            var toAtom:Atom = _trackManager.getAtomByPin(_toPin);

            if (!fromAtom || !toAtom) {
                return "track_invalid_" + Math.random().toString(36).substr(2, 9);
            }

            return "track_" + fromAtom.id + "_" + _fromPin.name + "_to_" +
                   toAtom.id + "_" + _toPin.name;
        }

        /**
         * Handles atom movement to update track visualization.
         * Redraws track when connected atoms are moved.
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
         * Emits track right-click event for menu system.
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
         * Redraws the track visualization.
         * Updates line position and appearance based on pin positions.
         *
         * @public
         */
        public function drawTrack():void {
            this.graphics.clear();

            var fromPos:Point = _trackManager.getGlobalPinPosition(_fromPin);
            var toPos:Point = _trackManager.getGlobalPinPosition(_toPin);

            // Convert to local coordinates
            var tracksLayer:Sprite = this.parent as Sprite;
            if (!tracksLayer) return;

            var localFrom:Point = tracksLayer.globalToLocal(fromPos);
            var localTo:Point = tracksLayer.globalToLocal(toPos);

            // Draw connection line with style based on activity state
            var lineColor:uint = _isActive ? 0x777777 : 0x777777;
            var lineAlpha:Number = _isActive ? 0.5 : 0.5;
            var lineThickness:Number = _isActive ? 3 : 2;

            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);
        }

        /**
         * Updates track visual representation.
         * Alias for drawTrack() for consistency with other components.
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
            return _connectionId.indexOf(atomId) !== -1;
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
         * Gets track connection information.
         * Returns comprehensive connection data for debugging and UI.
         *
         * @public
         * @return {Object} Connection information object
         */
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

        /**
         * Cleans up resources and removes connections.
         * Safely disposes all track components and removes listeners.
         * FIXED: Proper boolean evaluation in condition checks.
         *
         * @public
         */
        public function dispose():void {
            _isActive = false;

			// Убираем подписку на импульс
			Impulsys.removeImpulse("PIN_VALUE_CHANGED", onPinValueChanged);

            // Remove pin subscription - use explicit null checks
            if (_fromPin != null && _pinDataListener != null) {
                try {
                    _fromPin.removeListener(_pinDataListener);
                } catch (error:Error) {
                    trace("Track.dispose: Error removing pin listener - " + error.message);
                }
            }

            // Remove impulse listeners with proper function references
            Impulsys.removeImpulse("ATOM_MOVED", onAtomMoved);
            Impulsys.removeImpulse("PIN_VALUE_CHANGED", onPinValueChanged);

            // Remove event listeners with proper function references
            this.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);

            // Clean up visualization - use explicit null checks
            if (_flowAnimation != null) {
                // Check if DataFlowAnimation has dispose method before calling
                if (_flowAnimation.hasOwnProperty("dispose")) {
                    try {
                        _flowAnimation["dispose"]();
                    } catch (e:Error) {
                        trace("Track.dispose: Error disposing flow animation - " + e.message);
                    }
                }
                
                // Remove from display list if present
                if (this.contains(_flowAnimation)) {
                    this.removeChild(_flowAnimation);
                }
                _flowAnimation = null;
            }

            // Clear graphics
            this.graphics.clear();

            // Notify system about track disconnection
            Impulsys.emit(new Impulse("TRACK_DISCONNECTED", {
                track: this,
                connectionId: _connectionId
            }));

            // Remove from parent display container
            if (this.parent != null) {
                this.parent.removeChild(this);
            }

            // Explicitly nullify references for garbage collection
            _fromPin = null;
            _toPin = null;
            _trackManager = null;
            _pinDataListener = null;
        }

        // =========================================================================
        // PUBLIC GETTERS
        // =========================================================================

        /**
         * Gets the source pin of the track.
         *
         * @public
         * @return {Pin} Source pin (output)
         */
        public function get fromPin():Pin { 
            return _fromPin; 
        }

        /**
         * Gets the target pin of the track.
         *
         * @public
         * @return {Pin} Target pin (input)
         */
        public function get toPin():Pin { 
            return _toPin; 
        }

        /**
         * Gets the unique connection identifier.
         *
         * @public
         * @return {String} Connection identifier
         */
        public function get connectionId():String { 
            return _connectionId; 
        }

        /**
         * Gets the active state of the track.
         *
         * @public
         * @return {Boolean} True if track is actively transferring data
         */
        public function get isActive():Boolean { 
            return _isActive; 
        }
    }
}
