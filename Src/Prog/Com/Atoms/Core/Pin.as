package Src.Prog.Com.Atoms.Core {
    import flash.events.EventDispatcher;
    import flash.events.Event;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import flash.display.Stage;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.display.DisplayObject;

    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Manages data listeners for direct peer-to-peer communication.
     * Enhanced with track creation management for output pins.
     *
     * Key changes:
     * - Added track creation methods for output pins
     * - Autonomous pin search and validation
     * - Direct track creation without TrackManager
     *
     * @class Pin
     * @extends EventDispatcher
     * @public
     */
    public class Pin extends EventDispatcher {
        public static const VERSION:String = "PIN_CLASS_V3_WITH_TRACK_CREATION";
        public static const PIN_VALUE_CHANGED:String = "pinValueChanged";
        public static const PIN_CONNECTED:String = "pinConnected";
        public static const PIN_DISCONNECTED:String = "pinDisconnected";
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";

        public var id:String;
        public var name:String;
        public var type:String;
        public var data:Object;

        private var _listeners:Vector.<Function>;
        private var _value:*;
        private var _targetedSubscriptions:Vector.<PinSubscription>;
        private static var _eventManager:PinEventManager;

        // Track creation properties
        private var _tempTrack:TempTrack;
        private var _isCreatingTrack:Boolean = false;
        private var _creationStartPos:Point;

        private static function initializeEventManager():void {
            if (!_eventManager) {
                _eventManager = new PinEventManager();
            }
        }

        /**
         * Creates a new Pin instance.
         *
         * @constructor
         * @param {String} name - Pin name
         * @param {String} type - Pin type (input/output)
         * @param {*} value - Initial value
         * @param {Object} data - Additional pin data
         */
        public function Pin(name:String, type:String, value:* = null, data:Object = null) {
            super();
            initializeEventManager();
            this.id = generateId();
            this.name = name;
            this.type = type;
            this._value = value;
            this.data = data || {};
            this._listeners = new Vector.<Function>();
            this._targetedSubscriptions = new Vector.<PinSubscription>();
            _eventManager.registerPin(this);
        }

        public function get value():* {
            return _value;
        }

        public function set value(newValue:*):void {
            if (_value === newValue) return;
            var oldValue:* = _value;
            _value = newValue;
            trace("=== PIN VALUE CHANGE (V3) ===");
            trace("Pin " + this.name + " (" + this.type + ")");
            trace("Old value: " + oldValue);
            trace("New value: " + newValue);
            notifyListeners(newValue, oldValue);
            var pinEvent:PinEvent = new PinEvent(PIN_VALUE_CHANGED, this, newValue, oldValue);
            trace("🚀 DISPATCHING PIN_VALUE_CHANGED EVENT FOR PIN: " + this.name);
            trace("Event details: " + pinEvent.type + ", value: " + pinEvent.newValue);
            this.dispatchEvent(pinEvent);
            trace("✅ Event dispatched successfully");
            trace("=== END PIN VALUE CHANGE ===");
        }

        // =============================================================================
        // TRACK CREATION METHODS (OUTPUT PINS ONLY)
        // =============================================================================

        /**
         * Starts track creation process for output pins.
         * Creates temporary track visualization and sets up mouse tracking.
         *
         * @public
         * @param {Point} globalStartPos - Starting position in stage coordinates
         */
        public function startTrackCreation(globalStartPos:Point):void {
            if (this.type !== TYPE_OUTPUT) return;
            
            trace("=== PIN START TRACK CREATION ===");
            trace("Output pin: " + this.name);
            
            _isCreatingTrack = true;
            _creationStartPos = globalStartPos.clone();
            
            // Create temporary track visualization
            var window:Window = findParentWindow();
            if (window && window.overlayLayer) {
                var localStartPos:Point = window.overlayLayer.globalToLocal(globalStartPos);
                _tempTrack = new TempTrack(localStartPos);
                window.overlayLayer.addChild(_tempTrack);
            }
            
            // Add global mouse listeners
            var stage:Stage = getStage();
            if (stage) {
                stage.addEventListener(MouseEvent.MOUSE_MOVE, handleTrackDrag);
                stage.addEventListener(MouseEvent.MOUSE_UP, handleTrackFinalize);
            }
            
            trace("Track creation started successfully");
        }

        /**
         * Handles track dragging during creation.
         * Updates temporary track visualization in real-time.
         *
         * @private
         * @param {MouseEvent} event - Mouse move event
         */
        private function handleTrackDrag(event:MouseEvent):void {
            if (!_isCreatingTrack || !_tempTrack) return;
            
            var window:Window = findParentWindow();
            if (window && window.overlayLayer) {
                var localPos:Point = window.overlayLayer.globalToLocal(new Point(event.stageX, event.stageY));
                _tempTrack.update(localPos);
            }
        }

        /**
         * Finalizes track creation when mouse is released.
         * Performs target pin search and creates permanent track on validation.
         *
         * @private
         * @param {MouseEvent} event - Mouse up event
         */
        private function handleTrackFinalize(event:MouseEvent):void {
            if (!_isCreatingTrack) return;
            
            trace("=== PIN FINALIZE TRACK CREATION ===");
            
            try {
                event.stopPropagation();
                event.stopImmediatePropagation();

                // Find target pin under mouse
                var targetPin:Pin = findPinUnderMouse(event.stageX, event.stageY);
                
                // Cleanup temporary track
                cleanupTrackCreation();
                
                // Create permanent track if valid connection
                if (targetPin && isValidConnection(this, targetPin)) {
                    var track:Track = finalizeTrackCreation(targetPin);
                    trace("Track created successfully: " + track.connectionId);
                } else {
                    trace("Track creation cancelled - no valid target pin");
                    Impulsys.emit(new Impulse("TRACK_CONNECTION_FAILED", {
                        fromPin: this,
                        toPin: targetPin,
                        reason: targetPin ? "Invalid connection" : "No target pin found"
                    }));
                }
                
            } catch (error:Error) {
                trace("ERROR in track finalization: " + error.message);
                cleanupTrackCreation();
            }
            
            trace("=== END TRACK FINALIZATION ===");
        }

        /**
         * Creates permanent track connection to target pin.
         *
         * @public
         * @param {Pin} targetPin - Target pin for connection
         * @return {Track} Newly created track
         * @throws {Error} If connection is invalid
         */
        public function finalizeTrackCreation(targetPin:Pin):Track {
            if (!targetPin || !isValidConnection(this, targetPin)) {
                throw new Error("Invalid track connection");
            }
            
            // Remove existing connections to target pin
            removeExistingConnections(targetPin);
            
            // Create new track
            var track:Track = new Track(this, targetPin);
            
            trace("Finalized track creation: " + this.name + " → " + targetPin.name);
            return track;
        }

        /**
         * Cancels track creation process.
         * Cleans up temporary resources and listeners.
         *
         * @public
         */
        public function cancelTrackCreation():void {
            trace("Cancelling track creation for pin: " + this.name);
            cleanupTrackCreation();
        }

        /**
         * Cleans up track creation resources.
         *
         * @private
         */
        private function cleanupTrackCreation():void {
            _isCreatingTrack = false;
            
            // Remove temporary track
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
                _tempTrack = null;
            }
            
            // Remove global listeners
            var stage:Stage = getStage();
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, handleTrackDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, handleTrackFinalize);
            }
            
            _creationStartPos = null;
        }

        /**
         * Finds pin under mouse coordinates.
         * Uses spatial search with distance checking.
         *
         * @private
         * @param {Number} stageX - Mouse X coordinate
         * @param {Number} stageY - Mouse Y coordinate
         * @return {Pin} Found target pin or null
         */
        private function findPinUnderMouse(stageX:Number, stageY:Number):Pin {
            var mousePos:Point = new Point(stageX, stageY);
            var allPins:Vector.<Pin> = getAllPinsInWindow();
            var closestPin:Pin = null;
            var minDistance:Number = 25;

            for each (var pin:Pin in allPins) {
                if (pin === this) continue;

                var pinView:PinView = findPinView(pin);
                if (!pinView) continue;

                var pinGlobalPos:Point = pinView.localToGlobal(new Point(0, 0));
                var distance:Number = Point.distance(mousePos, pinGlobalPos);

                if (distance <= minDistance && isValidConnection(this, pin)) {
                    closestPin = pin;
                    minDistance = distance;
                }
            }

            return closestPin;
        }

        /**
         * Gets all pins in current window.
         *
         * @private
         * @return {Vector.<Pin>} Array of all pins in window
         */
        private function getAllPinsInWindow():Vector.<Pin> {
            var allPins:Vector.<Pin> = new Vector.<Pin>();
            var atomManager:AtomManager = AtomManager.getInstance();
            var window:Window = findParentWindow();
            
            if (!window || !atomManager) return allPins;

            var allAtoms:Array = atomManager.getAtomsForWindow(window.windowType);
            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;
                
                // Add all pins from atom
                for each (var inputPin:Pin in atom.inputs) {
                    allPins.push(inputPin);
                }
                for each (var outputPin:Pin in atom.outputs) {
                    allPins.push(outputPin);
                }
            }

            return allPins;
        }

        /**
         * Finds PinView for a pin.
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
                var child:DisplayObject = atomView.getChildAt(i);
                if (child is PinView && (child as PinView).pin === pin) {
                    return child as PinView;
                }
            }
            
            return null;
        }

        /**
         * Finds parent window for this pin.
         *
         * @private
         * @return {Window} Parent window or null
         */
        private function findParentWindow():Window {
            var atom:Atom = getAtomByPin(this);
            if (!atom) return null;
            
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(atom.id);
            if (!atomData || !atomData.view) return null;
            
            var atomView:AtomView = atomData.view;
            if (!atomView.stage) return null;
            
            return atomView.stage.nativeWindow as Window;
        }

        /**
         * Gets stage for global event listeners.
         *
         * @private
         * @return {Stage} Stage reference or null
         */
        private function getStage():Stage {
            var window:Window = findParentWindow();
            return window ? window.stage : null;
        }

        /**
         * Removes existing connections to target pin.
         *
         * @private
         * @param {Pin} targetPin - Target pin to remove connections from
         */
        private function removeExistingConnections(targetPin:Pin):void {
            var trackRegistry:TrackRegistry = TrackRegistry.getInstance();
            if (!trackRegistry) return;
            
            var existingTracks:Vector.<Track> = trackRegistry.getTracksByPin(targetPin);
            for each (var track:Track in existingTracks) {
                track.dispose();
            }
        }

        /**
         * Validates connection between pins.
         * Checks pin types, atom ownership and prevents self-connections.
         *
         * @private
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         * @return {Boolean} True if connection is valid
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            if (!fromPin || !toPin) return false;
            if (fromPin === toPin) return false;
            
            // Check type compatibility: output → input
            if (fromPin.type !== TYPE_OUTPUT || toPin.type !== TYPE_INPUT) return false;
            
            // Check atom ownership
            var fromAtom:Atom = getAtomByPin(fromPin);
            var toAtom:Atom = getAtomByPin(toPin);
            if (!fromAtom || !toAtom) return false;
            
            // Prevent connection of pins from same atom
            if (fromAtom.id == toAtom.id) return false;
            
            return true;
        }

        /**
         * Gets atom that owns this pin.
         *
         * @private
         * @param {Pin} pin - Pin to find owner for
         * @return {Atom} Owning atom or null
         */
        private function getAtomByPin(pin:Pin):Atom {
            var trackRegistry:TrackRegistry = TrackRegistry.getInstance();
            return trackRegistry ? trackRegistry.getAtomByPin(pin) : null;
        }

        // =============================================================================
        // EXISTING METHODS (UNCHANGED)
        // =============================================================================

        public function addListener(listener:Function):void {
            if (_listeners.indexOf(listener) === -1) {
                _listeners.push(listener);
            }
        }

        public function removeListener(listener:Function):void {
            var index:int = _listeners.indexOf(listener);
            if (index !== -1) {
                _listeners.splice(index, 1);
            }
        }

        private function notifyListeners(newValue:*, oldValue:*):void {
            for (var i:int = 0; i < _listeners.length; i++) {
                _listeners[i](newValue, oldValue, this);
            }
        }

        public function notifyConnected():void {
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_CONNECTED, this, this.value);
            }
        }

        public function notifyDisconnected():void {
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_DISCONNECTED, this, this.value);
            }
        }

        public function subscribeToPin(targetPin:Pin, eventTypes:*, callback:Function):Boolean {
            if (!targetPin || targetPin === this) {
                trace("Pin.subscribeToPin: Invalid target pin");
                return false;
            }
            var events:Array = normalizeEventTypes(eventTypes);
            var subscription:PinSubscription = new PinSubscription(targetPin, events, callback);
            if (hasExistingSubscription(subscription)) {
                trace("Pin.subscribeToPin: Subscription already exists for pin: " + targetPin.name);
                return false;
            }
            for each (var eventType:String in events) {
                targetPin.addEventListener(eventType, callback);
            }
            _targetedSubscriptions.push(subscription);
            return true;
        }

        public function unsubscribeFromPin(targetPin:Pin, eventTypes:* = null):Boolean {
            var events:Array = normalizeEventTypes(eventTypes);
            var removed:Boolean = false;
            for (var i:int = _targetedSubscriptions.length - 1; i >= 0; i--) {
                var subscription:PinSubscription = _targetedSubscriptions[i];
                if (subscription.targetPin === targetPin) {
                    if (events.length > 0) {
                        removed = removeSpecificEvents(subscription, events) || removed;
                        if (subscription.eventTypes.length === 0) {
                            _targetedSubscriptions.splice(i, 1);
                        }
                    } else {
                        removeAllEvents(subscription);
                        _targetedSubscriptions.splice(i, 1);
                        removed = true;
                    }
                }
            }
            return removed;
        }

        public function unsubscribeFromAllPins():void {
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                removeAllEvents(subscription);
            }
            _targetedSubscriptions = new Vector.<PinSubscription>();
        }

        public function getSubscriptions():Array {
            var result:Array = [];
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                result.push({
                    targetPin: subscription.targetPin.name,
                    targetPinId: subscription.targetPin.id,
                    eventTypes: subscription.eventTypes.slice(),
                    callback: subscription.callback
                });
            }
            return result;
        }

        public function isSubscribedTo(targetPin:Pin, eventType:String = null):Boolean {
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                if (subscription.targetPin === targetPin) {
                    if (!eventType) return true;
                    if (subscription.eventTypes.indexOf(eventType) !== -1) return true;
                }
            }
            return false;
        }

        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        public function clone():Pin {
            var newPin:Pin = new Pin(name, type, _value, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        public function cloneWithValue(newValue:*):Pin {
            var newPin:Pin = new Pin(name, type, newValue, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        private function cloneObject(obj:Object):Object {
            var cloned:Object = {};
            for (var key:String in obj) {
                cloned[key] = obj[key];
            }
            return cloned;
        }

        /**
         * Disposes pin resources and cleans up track creation if active.
         *
         * @public
         */
        public function dispose():void {
            notifyDisconnected();
            unsubscribeFromAllPins();
            if (_eventManager) {
                _eventManager.unregisterPin(this);
            }
            _listeners = null;
            _targetedSubscriptions = null;
            
            // Cleanup track creation if active
            if (_isCreatingTrack) {
                cancelTrackCreation();
            }
        }

        private function normalizeEventTypes(eventTypes:*):Array {
            if (eventTypes is String) return [eventTypes];
            if (eventTypes is Array) return eventTypes;
            return [PIN_VALUE_CHANGED];
        }

        private function hasExistingSubscription(newSubscription:PinSubscription):Boolean {
            for each (var existing:PinSubscription in _targetedSubscriptions) {
                if (existing.targetPin === newSubscription.targetPin &&
                    existing.callback === newSubscription.callback) {
                    for each (var eventType:String in newSubscription.eventTypes) {
                        if (existing.eventTypes.indexOf(eventType) !== -1) return true;
                    }
                }
            }
            return false;
        }

        private function removeSpecificEvents(subscription:PinSubscription, eventsToRemove:Array):Boolean {
            var removed:Boolean = false;
            for each (var eventType:String in eventsToRemove) {
                var index:int = subscription.eventTypes.indexOf(eventType);
                if (index !== -1) {
                    subscription.eventTypes.splice(index, 1);
                    subscription.targetPin.removeEventListener(eventType, subscription.callback);
                    removed = true;
                }
            }
            return removed;
        }

        private function removeAllEvents(subscription:PinSubscription):void {
            for each (var eventType:String in subscription.eventTypes) {
                subscription.targetPin.removeEventListener(eventType, subscription.callback);
            }
        }

        public static function getSystemStats():Object {
            return _eventManager ? _eventManager.getStats() : { totalPins: 0 };
        }

        // =============================================================================
        // PUBLIC ACCESSORS
        // =============================================================================

        public function get isCreatingTrack():Boolean { return _isCreatingTrack; }
        public function get tempTrack():TempTrack { return _tempTrack; }
    }
}
