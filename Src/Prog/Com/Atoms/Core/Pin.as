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
     *
     * @class Pin
     * @extends EventDispatcher
     */
    public class Pin extends EventDispatcher {

        public static const VERSION:String = "PIN_CLASS_V11_FINAL_REFACTORED";
        public static const PIN_VALUE_CHANGED:String = "pinValueChanged";
        public static const PIN_CONNECTED:String = "pinConnected";
        public static const PIN_DISCONNECTED:String = "pinDisconnected";
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";

        private static var _eventManager:PinEventManager;

        private static function initializeEventManager():void {
            if (!_eventManager) _eventManager = new PinEventManager();
        }

        public static function getSystemStats():Object {
            return _eventManager ? _eventManager.getStats() : { totalPins: 0 };
        }

        // =============================================================================
        // PROPERTIES
        // =============================================================================
        public var id:String;
        public var name:String;
        public var type:String;
        public var data:Object;

        private var _value:*;
        private var _atom:Atom;

        private var _listeners:Vector.<Function> = new Vector.<Function>();
        private var _targetedSubscriptions:Vector.<PinSubscription> = new Vector.<PinSubscription>();

        private var _tempTrack:TempTrack;
        private var _isCreatingTrack:Boolean = false;
        private var _creationStartPos:Point;

        private var _collisions:PinCollisions;

        // =============================================================================
        // CONSTRUCTOR
        // =============================================================================
        public function Pin(name:String, type:String, value:* = null, data:Object = null) {
            super();
            initializeEventManager();

            this.id = generateId();
            this.name = name;
            this.type = type;
            this._value = value;
            this.data = data || {};

            _eventManager.registerPin(this);
            _collisions = new PinCollisions(this);
        }

        // =============================================================================
        // VALUE
        // =============================================================================
        public function get value():* { return _value; }
        public function set value(newValue:*):void {
            if (_value === newValue) return;
            var oldValue:* = _value;
            _value = newValue;
            notifyListeners(newValue, oldValue);
            dispatchEvent(new PinEvent(PIN_VALUE_CHANGED, this, newValue, oldValue));
        }

        // =============================================================================
        // LIFECYCLE
        // =============================================================================
        public function setOwnerAtom(atom:Atom):void {
            _atom = atom;
        }

        public function get atom():Atom { return _atom; }

        public function dispose():void {
            _collisions.forceClearCollisions();
            _collisions.forceClearAllAutoConnections();
            notifyDisconnected();
            unsubscribeFromAllPins();
            if (_eventManager) _eventManager.unregisterPin(this);
            if (_isCreatingTrack) cancelTrackCreation();
            _listeners = null;
            _targetedSubscriptions = null;
            _atom = null;
        }

        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        // =============================================================================
        // COLLISION DELEGATION
        // =============================================================================
        public function updateCollisionsDuringDrag():void          { _collisions.updateCollisionsDuringDrag(); }
        public function forceClearCollisions():void               { _collisions.forceClearCollisions(); }
        public function cleanupInactiveAutoConnections():void     { _collisions.cleanupInactiveAutoConnections(); }
        public function forceClearAllAutoConnections():void       { _collisions.forceClearAllAutoConnections(); }

        internal function createAutoConnection(targetPin:Pin):void { _collisions.createAutoConnection(targetPin); }
        internal function removeAutoConnection(targetPin:Pin):void { _collisions.removeAutoConnection(targetPin); }

        // =============================================================================
        // INTERNAL METHODS FOR PINCOLLISIONS ACCESS
        // =============================================================================

        /**
         * Gets parent window for coordinate transformations.
         * INTERNAL: Used by PinCollisions for collision detection.
         */
        internal function getParentWindow():Window {
            return findParentWindow();
        }

        /**
         * Gets all pins in the same window for collision detection.
         * INTERNAL: Used by PinCollisions.
         */
        internal function getAllPinsInWindowInternal():Vector.<Pin> {
            return getAllPinsInWindow();
        }

        /**
         * Finds PinView for collision detection.
         * INTERNAL: Used by PinCollisions.
         */
        internal function findPinViewInternal(pin:Pin):PinView {
            return findPinView(pin);
        }

		// =============================================================================
		// MANUAL TRACK CREATION - тянуть можно с любого пина!
		// =============================================================================

		/**
		 * Starts manual track creation from this pin.
		 * Works from both OUTPUT and INPUT pins.
		 * If started from INPUT — we are looking for an OUTPUT to connect to us.
		 */
		public function startTrackCreation(globalStartPos:Point):void {
			_isCreatingTrack = true;
			_creationStartPos = globalStartPos.clone();

			var window:Window = findParentWindow();
			if (window && window.overlayLayer) {
				var localStart:Point = window.overlayLayer.globalToLocal(globalStartPos);
				_tempTrack = new TempTrack(localStart);

				// Визуальная подсказка: какого типа пин мы ищем
				if (type === TYPE_OUTPUT) {
					_tempTrack.searchingForInput = true;   // ищем вход
				} else {
					_tempTrack.searchingForOutput = true;  // ищем выход
				}

				window.overlayLayer.addChild(_tempTrack);
			}

			var stage:Stage = getStage();
			if (stage) {
				stage.addEventListener(MouseEvent.MOUSE_MOVE, handleTrackDrag);
				stage.addEventListener(MouseEvent.MOUSE_UP, handleTrackFinalize);
			}
		}

        private function handleTrackDrag(event:MouseEvent):void {
            if (!_isCreatingTrack || !_tempTrack) return;
            var win:Window = findParentWindow();
            if (win && win.overlayLayer) {
                var local:Point = win.overlayLayer.globalToLocal(new Point(event.stageX, event.stageY));
                _tempTrack.update(local);
            }
        }

		private function handleTrackFinalize(event:MouseEvent):void {
			if (!_isCreatingTrack) return;

			try {
				event.stopPropagation();

				// Находим пин под курсором
				var targetPin:Pin = findPinUnderMouse(event.stageX, event.stageY);
				cleanupTrackCreation();

				if (!targetPin) return;

				// === Логика в зависимости от того, с какого пина начали ===
				if (this.type === TYPE_OUTPUT && targetPin.type === TYPE_INPUT) {
					// Классический случай: начали с выхода → соединяем к входу
					if (isValidConnection(this, targetPin)) {
						finalizeTrackCreation(targetPin);
					}
				}
				else if (this.type === TYPE_INPUT && targetPin.type === TYPE_OUTPUT) {
					// Начинаем с входа → ищем выход → он создаёт соединение к нам
					if (targetPin.isValidConnection(targetPin, this)) {
						targetPin.finalizeTrackCreation(this);
					}
				}
				// Другие комбинации игнорируем (например, input→input)
			}
			catch (e:Error) {
				cleanupTrackCreation();
			}
		}

        public function finalizeTrackCreation(targetPin:Pin):Track {
            if (!targetPin || !isValidConnection(this, targetPin)) {
                throw new Error("Invalid track connection");
            }
            removeExistingConnections(targetPin);
            return new Track(this, targetPin);
        }

        public function cancelTrackCreation():void { cleanupTrackCreation(); }

        private function cleanupTrackCreation():void {
            _isCreatingTrack = false;
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
                _tempTrack = null;
            }
            var stage:Stage = getStage();
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, handleTrackDrag);
                stage.removeEventListener(MouseEvent.MOUSE_UP, handleTrackFinalize);
            }
            _creationStartPos = null;
        }

        // =============================================================================
        // NAVIGATION & HELPERS (internal — used by PinCollisions)
        // =============================================================================
        internal function findPinView(pin:Pin):PinView {
            if (!pin || !pin.atom) return null;
            var mgr:AtomManager = AtomManager.getInstance();
            if (!mgr) return null;
            var data:Object = mgr.getAtomById(pin.atom.id);
            if (!data || !data.view) return null;
            var view:AtomView = data.view as AtomView;
            if (!view || !view.stage) return null;
            for (var i:int = 0; i < view.numChildren; i++) {
                var child:DisplayObject = view.getChildAt(i);
                if (child is PinView && PinView(child).pin === pin) {
                    return child as PinView;
                }
            }
            return null;
        }

        internal function getAllPinsInWindow():Vector.<Pin> {
            var out:Vector.<Pin> = new Vector.<Pin>();
            var mgr:AtomManager = AtomManager.getInstance();
            var win:Window = findParentWindow();
            if (!win || !mgr) return out;
            var atoms:Array = mgr.getAtomsForWindow(win.windowType);
            for each (var a:Object in atoms) {
                var atom:Atom = a.atom;
				var p:Pin;
                for each ( p in atom.inputs) out.push(p);
                for each ( p in atom.outputs) out.push(p);
            }
            return out;
        }

        internal function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            if (!fromPin || !toPin || fromPin === toPin) return false;
            if (fromPin.type !== TYPE_OUTPUT || toPin.type !== TYPE_INPUT) return false;
            if (!fromPin.atom || !toPin.atom || fromPin.atom.id === toPin.atom.id) return false;
            return true;
        }

        private function findParentWindow():Window {
            if (!_atom) return null;
            var mgr:AtomManager = AtomManager.getInstance();
            var data:Object = mgr.getAtomById(_atom.id);
            if (!data || !data.view) return null;
            var view:AtomView = data.view as AtomView;
            return view && view.stage ? view.stage.nativeWindow as Window : null;
        }

        private function getStage():Stage {
            var win:Window = findParentWindow();
            return win ? win.stage : null;
        }

        private function removeExistingConnections(targetPin:Pin):void {
            var reg:TrackRegistry = TrackRegistry.getInstance();
            if (!reg) return;
            var tracks:Vector.<Track> = reg.getTracksByPin(targetPin);
            for each (var t:Track in tracks) t.dispose();
        }

		private function findPinUnderMouse(stageX:Number, stageY:Number):Pin {
			var mouse:Point = new Point(stageX, stageY);
			var all:Vector.<Pin> = getAllPinsInWindow();
			var closest:Pin = null;
			var minDist:Number = Number.MAX_VALUE;

			for each (var pin:Pin in all) {
				if (pin === this) continue; // не соединять с самим собой

				var view:PinView = findPinView(pin);
				if (!view) continue;

				if (view.hitTestPoint(stageX, stageY, true)) {
					var center:Point = view.localToGlobal(new Point(0, 0));
					var d:Number = Point.distance(mouse, center);
					if (d < minDist) {
						closest = pin;
						minDist = d;
					}
				}
			}
			return closest;
		}

        // =============================================================================
        // SUBSCRIPTIONS
        // =============================================================================
        public function addListener(listener:Function):void {
            if (_listeners.indexOf(listener) === -1) _listeners.push(listener);
        }

        public function removeListener(listener:Function):void {
            var i:int = _listeners.indexOf(listener);
            if (i !== -1) _listeners.splice(i, 1);
        }

        private function notifyListeners(newValue:*, oldValue:*):void {
            for each (var l:Function in _listeners) l(newValue, oldValue, this);
        }

        public function subscribeToPin(targetPin:Pin, eventTypes:*, callback:Function):Boolean {
            if (!targetPin || targetPin === this) return false;
            var events:Array = (eventTypes is String) ? [eventTypes] : (eventTypes is Array) ? eventTypes : [PIN_VALUE_CHANGED];
            var sub:PinSubscription = new PinSubscription(targetPin, events, callback);
            if (hasExistingSubscription(sub)) return false;
            for each (var e:String in events) targetPin.addEventListener(e, callback, false, 0, true);
            _targetedSubscriptions.push(sub);
            return true;
        }

        public function unsubscribeFromPin(targetPin:Pin, eventTypes:* = null):Boolean {
            var removed:Boolean = false;
            var events:Array = (eventTypes is String) ? [eventTypes] : (eventTypes is Array) ? eventTypes : [];
            for (var i:int = _targetedSubscriptions.length - 1; i >= 0; i--) {
                var sub:PinSubscription = _targetedSubscriptions[i];
                if (sub.targetPin === targetPin) {
                    if (events.length > 0) {
                        removed = removeSpecificEvents(sub, events) || removed;
                        if (sub.eventTypes.length === 0) _targetedSubscriptions.splice(i, 1);
                    } else {
                        removeAllEvents(sub);
                        _targetedSubscriptions.splice(i, 1);
                        removed = true;
                    }
                }
            }
            return removed;
        }

        public function unsubscribeFromAllPins():void {
            for each (var sub:PinSubscription in _targetedSubscriptions) removeAllEvents(sub);
            _targetedSubscriptions = new Vector.<PinSubscription>();
        }

        private function hasExistingSubscription(newSub:PinSubscription):Boolean {
            for each (var sub:PinSubscription in _targetedSubscriptions) {
                if (sub.targetPin === newSub.targetPin && sub.callback === newSub.callback) {
                    for each (var e:String in newSub.eventTypes) if (sub.eventTypes.indexOf(e) !== -1) return true;
                }
            }
            return false;
        }

        private function removeSpecificEvents(sub:PinSubscription, toRemove:Array):Boolean {
            var r:Boolean = false;
            for each (var e:String in toRemove) {
                var i:int = sub.eventTypes.indexOf(e);
                if (i !== -1) {
                    sub.eventTypes.splice(i, 1);
                    sub.targetPin.removeEventListener(e, sub.callback);
                    r = true;
                }
            }
            return r;
        }

        private function removeAllEvents(sub:PinSubscription):void {
            for each (var e:String in sub.eventTypes) sub.targetPin.removeEventListener(e, sub.callback);
        }

        // =============================================================================
        // CONNECTION EVENTS
        // =============================================================================
        public function notifyConnected():void {
            if (type === TYPE_OUTPUT) dispatchEvent(new PinEvent(PIN_CONNECTED, this, value));
        }

        public function notifyDisconnected():void {
            if (type === TYPE_OUTPUT) dispatchEvent(new PinEvent(PIN_DISCONNECTED, this, value));
        }

        // =============================================================================
        // GETTERS
        // =============================================================================
        public function get collidingPins():Vector.<Pin> { return _collisions.collidingPins; }
        public function get autoTracks():Vector.<Track> { return _collisions.autoTracks; }
        public function get isCreatingTrack():Boolean { return _isCreatingTrack; }
        public function get tempTrack():TempTrack { return _tempTrack; }
        
        /**
         * 🔥 НОВОЕ СВОЙСТВО: Проверяет, подключен ли пин через Track.
         * Используется LEDBehavior для определения источника сигнала.
         */
        public function get isConnected():Boolean {
            // Проверяем через TrackRegistry есть ли Track к этому пину
            var reg:TrackRegistry = TrackRegistry.getInstance();
            if (!reg) return false;
            
            var tracks:Vector.<Track> = reg.getTracksByPin(this);
            return tracks.length > 0;
        }
        
        /**
         * 🔥 НОВЫЙ МЕТОД: Получает информацию о подключениях пина.
         */
        public function getConnectionInfo():Object {
            var reg:TrackRegistry = TrackRegistry.getInstance();
            var tracks:Vector.<Track> = reg ? reg.getTracksByPin(this) : new Vector.<Track>();
            
            return {
                pinId: this.id,
                pinName: this.name,
                pinType: this.type,
                isConnected: tracks.length > 0,
                trackCount: tracks.length,
                tracks: tracks.map(function(track:Track):Object {
                    return {
                        connectionId: track.connectionId,
                        fromPin: track.fromPin ? track.fromPin.name : "unknown",
                        toPin: track.toPin ? track.toPin.name : "unknown"
                    };
                })
            };
        }
    }
}