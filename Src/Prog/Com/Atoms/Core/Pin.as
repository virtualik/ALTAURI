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
    import flash.geom.Rectangle;

    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Collision detection is triggered ONLY during atom drag and uses strict visual overlap.
     *
     * @class Pin
     * @extends EventDispatcher
     */
    public class Pin extends EventDispatcher {
        // =============================================================================
        // CONSTANTS AND STATIC PROPERTIES
        // =============================================================================
        public static const VERSION:String = "PIN_CLASS_V9_FIXED_INPUT_AUTO_CONNECT";
        public static const PIN_VALUE_CHANGED:String = "pinValueChanged";
        public static const PIN_CONNECTED:String = "pinConnected";
        public static const PIN_DISCONNECTED:String = "pinDisconnected";
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";

        private static var _eventManager:PinEventManager;
        private static function initializeEventManager():void {
            if (!_eventManager) {
                _eventManager = new PinEventManager();
            }
        }

        public static function getSystemStats():Object {
            return _eventManager ? _eventManager.getStats() : { totalPins: 0 };
        }

        // =============================================================================
        // BASIC PROPERTIES AND CONSTRUCTOR
        // =============================================================================
        public var id:String;
        public var name:String;
        public var type:String;
        public var data:Object;
        private var _listeners:Vector.<Function>;
        private var _value:*;
        private var _targetedSubscriptions:Vector.<PinSubscription>;
        private var _atom:Atom;

        // Track creation properties
        private var _tempTrack:TempTrack;
        private var _isCreatingTrack:Boolean = false;
        private var _creationStartPos:Point;

        // Collision state (used ONLY during drag)
        private var _currentCollisions:Vector.<Pin> = new Vector.<Pin>();
        private var _autoTracks:Vector.<Track> = new Vector.<Track>();

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
            
            trace("✓ Pin created: " + name + " (" + type + ")");
        }

        // =============================================================================
        // PIN STATE MANAGEMENT
        // =============================================================================
        public function get value():* {
            return _value;
        }

        public function set value(newValue:*):void {
            if (_value === newValue) return;
            
            var oldValue:* = _value;
            _value = newValue;
            
            trace("=== PIN VALUE CHANGE ===");
            trace("Pin: " + this.name + " (" + this.id + ")");
            trace("Old: " + oldValue + " → New: " + newValue);
            
            // 1. Уведомляем локальных слушателей
            notifyListeners(newValue, oldValue);
            
            // 2. Диспатчим событие
            var pinEvent:PinEvent = new PinEvent(PIN_VALUE_CHANGED, this, newValue, oldValue);
            this.dispatchEvent(pinEvent);
            
            trace("=== END PIN VALUE CHANGE ===");
        }

        public function setOwnerAtom(atom:Atom):void {
            _atom = atom;
            trace("✓ Pin " + this.name + " now owned by atom: " + atom.name);
        }

        public function dispose():void {
            // Просто очищаем — таймера нет
            forceClearCollisions();
            notifyDisconnected();
            unsubscribeFromAllPins();
            if (_eventManager) {
                _eventManager.unregisterPin(this);
            }
            _listeners = null;
            _targetedSubscriptions = null;
            if (_isCreatingTrack) {
                cancelTrackCreation();
            }
            _currentCollisions = null;
            _atom = null;
        }

        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        // =============================================================================
        // COLLISION LOGIC — ONLY DURING DRAG (NO TIMER)
        // =============================================================================
        /**
         * Вызывается ВНЕШНЕ (например, из AtomView) при каждом шаге перетаскивания.
         * Обновляет коллизии ДЛЯ ВСЕХ пинов - и input и output.
         */
        public function updateCollisionsDuringDrag():void {
            if (!_atom) {
                trace("⚠ updateCollisionsDuringDrag: No atom");
                return;
            }

            trace("=== COLLISION DETECTION FOR PIN: " + this.name + " (" + this.type + ") ===");
            var current:Vector.<Pin> = findNearbyPins();
            trace("Found " + current.length + " nearby pins");
            handleCollisionChanges(current);
            trace("=== END COLLISION DETECTION ===");
        }

		/**
		 * Принудительно завершает ВСЕ текущие коллизии (вызывать при отпускании атома).
		 * 🔥 ИЗМЕНЕНИЕ: Теперь НЕ разрывает соединения, а только очищает состояние
		 */
		public function forceClearCollisions():void {
			trace("🧹 Clearing collision state (without breaking connections) for pin: " + this.name);
			
			// 🔥 Только очищаем список коллизий, НЕ вызываем onCollisionEnd
			// Это предотвращает разрыв существующих соединений
			_currentCollisions = new Vector.<Pin>();
			
			trace("✅ Collision state cleared for pin: " + this.name);
		}

        private function findNearbyPins():Vector.<Pin> {
            var nearby:Vector.<Pin> = new Vector.<Pin>();
            var thisView:PinView = findPinView(this);
            if (!thisView) {
                trace("❌ findNearbyPins: No PinView found for " + this.name);
                return nearby;
            }
            if (!thisView.stage) {
                trace("❌ findNearbyPins: PinView not on stage");
                return nearby;
            }

            var allPins:Vector.<Pin> = getAllPinsInWindow();
            trace("🔍 Scanning " + allPins.length + " pins in window");
            
            for each (var other:Pin in allPins) {
                if (other === this) {
                    trace("  ⏩ Skipping self");
                    continue;
                }
                if (other._atom === this._atom) {
                    trace("  ⏩ Skipping same atom pin");
                    continue;
                }

                // 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Для input пинов ищем output пины, и наоборот
                var isConnectionValid:Boolean = false;
                
                if (this.type === TYPE_INPUT && other.type === TYPE_OUTPUT) {
                    // Input пин ищет Output пины
                    isConnectionValid = isValidConnection(other, this); // other -> this
                } else if (this.type === TYPE_OUTPUT && other.type === TYPE_INPUT) {
                    // Output пин ищет Input пины  
                    isConnectionValid = isValidConnection(this, other); // this -> other
                } else {
                    trace("  ⏩ Skipping incompatible pin types: " + this.type + " -> " + other.type);
                    continue;
                }

                if (!isConnectionValid) {
                    trace("  ⏩ Invalid connection to: " + other.name);
                    continue;
                }

                var otherView:PinView = findPinView(other);
                if (!otherView) {
                    trace("  ❌ No PinView for: " + other.name);
                    continue;
                }

                trace("  🔍 Checking collision with: " + other.name + " (" + other.type + ")");
                if (arePinsVisuallyColliding(thisView, otherView)) {
                    trace("  ✅ COLLISION DETECTED with: " + other.name);
                    nearby.push(other);
                } else {
                    trace("  ❌ No collision with: " + other.name);
                }
            }
            return nearby;
        }

		private function arePinsVisuallyColliding(a:PinView, b:PinView):Boolean {
			var result:Boolean = false;
			
			if (!a.stage || !b.stage) {
				trace("    ❌ One pin not on stage");
				return false;
			}
			
			// 🔥 ДОПОЛНИТЕЛЬНАЯ ПРОВЕРКА - есть ли hitArea
			if (!a.hitArea || !b.hitArea) {
				trace("    ❌ One pin missing hitArea");
				return false;
			}

			try {
				// Используем hitTestObject для проверки пересечения hitArea
				result = a.hitTestObject(b);
				
				trace("    🎯 HitArea collision check:");
				trace("      A: " + a.name + " at " + a.localToGlobal(new Point(0, 0)));
				trace("      B: " + b.name + " at " + b.localToGlobal(new Point(0, 0)));
				trace("      Result: " + result);
				
			} catch (e:Error) {
				trace("    ❌ Error in collision check: " + e.message);
				result = false;
			}
			
			return result;
		}

        private function handleCollisionChanges(current:Vector.<Pin>):void {
            // Новые коллизии
            for each (var newPin:Pin in current) {
                if (_currentCollisions.indexOf(newPin) === -1) {
                    trace("🎯 NEW COLLISION with: " + newPin.name);
                    onCollisionStart(newPin);
                } else {
                    trace("🔄 EXISTING collision with: " + newPin.name);
                }
            }
            
            // Пропавшие коллизии
            for (var i:int = _currentCollisions.length - 1; i >= 0; i--) {
                var oldPin:Pin = _currentCollisions[i];
                if (current.indexOf(oldPin) === -1) {
                    trace("🚫 COLLISION ENDED with: " + oldPin.name);
                    onCollisionEnd(oldPin);
                }
            }
            _currentCollisions = current;
        }

        private function onCollisionStart(otherPin:Pin):void {
            trace("🔥 COLLISION START: " + this.name + " (" + this.type + ") → " + otherPin.name + " (" + otherPin.type + ")");
            
            // 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Определяем направление подключения
            if (this.type === TYPE_OUTPUT && otherPin.type === TYPE_INPUT) {
                // Output -> Input
                createAutoConnection(otherPin);
            } else if (this.type === TYPE_INPUT && otherPin.type === TYPE_OUTPUT) {
                // Input -> Output (обратное направление)
                otherPin.createAutoConnection(this);
            }
            
            Impulsys.emit(new Impulse("PIN_COLLISION_STARTED", {
                pin1: this,
                pin2: otherPin
            }));
        }

		private function onCollisionEnd(otherPin:Pin):void {
			trace("💤 COLLISION END: " + this.name + " (" + this.type + ") → " + otherPin.name + " (" + otherPin.type + ")");
			
			// 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Двустороннее удаление автоподключений
			if (this.type === TYPE_OUTPUT && otherPin.type === TYPE_INPUT) {
				// Output -> Input: удаляем соединение с нашей стороны
				removeAutoConnection(otherPin);
			} else if (this.type === TYPE_INPUT && otherPin.type === TYPE_OUTPUT) {
				// Input -> Output: просим output пин удалить соединение
				otherPin.removeAutoConnection(this);
			}
			
			Impulsys.emit(new Impulse("PIN_COLLISION_ENDED", {
				pin1: this,
				pin2: otherPin
			}));
		}

		/**
		 * Безопасно очищает только те автоподключения, которые больше не активны
		 * Вызывается при отпускании атома для очистки "висячих" соединений
		 */
		public function cleanupInactiveAutoConnections():void {
			trace("🧹 Cleaning up inactive auto-connections for pin: " + this.name);

			var tracksToRemove:Vector.<Track> = new Vector.<Track>();

			// Проверяем каждое автоподключение
			for each (var track:Track in _autoTracks) {
				try {
					var otherPin:Pin = (this.type === TYPE_OUTPUT) ? track.toPin : track.fromPin;
					
					// Проверяем, что пины все еще валидны
					if (!otherPin || !otherPin.atom) {
						tracksToRemove.push(track);
						trace("🗑️ Marking inactive auto-connection (invalid pin): " + this.name + " → " + (otherPin ? otherPin.name : "null"));
						continue;
					}
					
					var otherView:PinView = findPinView(otherPin);
					var thisView:PinView = findPinView(this);

					// Если не можем найти view или пины больше не пересекаются - помечаем для удаления
					if (!thisView || !otherView || !arePinsVisuallyColliding(thisView, otherView)) {
						tracksToRemove.push(track);
						trace("🗑️ Marking inactive auto-connection: " + this.name + " → " + otherPin.name);
					}
				} catch (error:Error) {
					trace("❌ Error checking auto-connection: " + error.message);
					tracksToRemove.push(track); // В случае ошибки удаляем соединение
				}
			}

			// Удаляем неактивные соединения
			for each (var inactiveTrack:Track in tracksToRemove) {
				try {
					inactiveTrack.dispose();
					removeTrackFromAutoTracks(inactiveTrack);
				} catch (error:Error) {
					trace("❌ Error disposing track: " + error.message);
				}
			}

			trace("✅ Inactive auto-connections cleaned for pin: " + this.name);
		}

		// =============================================================================
        // AUTO-CONNECTION MANAGEMENT (output pin only)
        // =============================================================================
		internal function createAutoConnection(targetPin:Pin):void {
			trace("=== ATTEMPTING AUTO-CONNECTION ===");
			trace("From: " + this.name + " (" + this.type + ") → To: " + targetPin.name + " (" + targetPin.type + ")");
			
			// 🔥 ПРОВЕРКА: Только output пины могут создавать подключения
			if (this.type !== TYPE_OUTPUT) {
				trace("❌ Only output pins can create auto-connections");
				return;
			}
			
			if (!isValidConnection(this, targetPin)) {
				trace("❌ Invalid auto-connection attempt");
				return;
			}
			if (hasExistingConnection(this, targetPin)) {
				trace("⚠ Connection already exists, skipping auto-connection");
				return;
			}
			
			try {
				trace("🔧 Creating track...");
				var track:Track = finalizeTrackCreation(targetPin);
				_autoTracks.push(track);

				trace("✅ AUTO-CONNECTION CREATED: " + this.name + " → " + targetPin.name);
				Impulsys.emit(new Impulse("AUTO_CONNECTION_CREATED", {
					fromPin: this,
					toPin: targetPin,
					track: track
				}));
			} catch (error:Error) {
				trace("❌ AUTO-CONNECTION FAILED: " + error.message);
			}
		}

		internal function removeAutoConnection(targetPin:Pin):void {
			trace("🗑️ Removing auto-connection: " + this.name + " → " + targetPin.name);
			var track:Track = findAutoTrackBetween(this, targetPin);
			if (track) {
				track.dispose();
				removeTrackFromAutoTracks(track);
				trace("✅ Auto-connection removed successfully");
			} else {
				// Также проверяем обратное направление
				track = findAutoTrackBetween(targetPin, this);
				if (track) {
					track.dispose();
					removeTrackFromAutoTracks(track);
					trace("✅ Reverse auto-connection removed successfully");
				} else {
					trace("⚠ No auto-track found to remove between " + this.name + " and " + targetPin.name);
				}
			}
		}

		/**
		 * Принудительно удаляет все автоподключения этого пина.
		 * Вызывается при остановке перетаскивания атома.
		 */
		public function forceClearAllAutoConnections():void {
			trace("🧹 Force clearing all auto-connections for pin: " + this.name);
			var tracksToRemove:Vector.<Track> = _autoTracks.concat();
			for each (var track:Track in tracksToRemove) {
				track.dispose();
			}
			_autoTracks = new Vector.<Track>();
			trace("✅ All auto-connections cleared for pin: " + this.name);
		}

		private function findAutoTrackBetween(fromPin:Pin, toPin:Pin):Track {
			for each (var t:Track in _autoTracks) {
				if ((t.fromPin === fromPin && t.toPin === toPin) || 
					(t.fromPin === toPin && t.toPin === fromPin)) {
					return t;
				}
			}
			return null;
		}

        private function removeTrackFromAutoTracks(track:Track):void {
            var i:int = _autoTracks.indexOf(track);
            if (i !== -1) {
                _autoTracks.splice(i, 1);
                trace("✓ Auto-track removed from list");
            }
        }

        private function hasExistingConnection(fromPin:Pin, toPin:Pin):Boolean {
            var reg:TrackRegistry = TrackRegistry.getInstance();
            if (!reg) {
                trace("⚠ No TrackRegistry instance");
                return false;
            }
            
            var tracks:Vector.<Track> = reg.getTracksByPin(toPin);
            trace("🔍 Checking " + tracks.length + " existing tracks for pin: " + toPin.name);
            
            for each (var t:Track in tracks) {
                if (t.fromPin === fromPin && t.toPin === toPin) {
                    trace("⚠ Connection already exists via track: " + t.connectionId);
                    return true;
                }
            }
            return false;
        }

        // =============================================================================
        // TRACK CREATION (MANUAL)
        // =============================================================================
        public function startTrackCreation(globalStartPos:Point):void {
            if (type !== TYPE_OUTPUT) return;
            _isCreatingTrack = true;
            _creationStartPos = globalStartPos.clone();
            var window:Window = findParentWindow();
            if (window && window.overlayLayer) {
                var localStart:Point = window.overlayLayer.globalToLocal(globalStartPos);
                _tempTrack = new TempTrack(localStart);
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
                var target:Pin = findPinUnderMouse(event.stageX, event.stageY);
                cleanupTrackCreation();
                if (target && isValidConnection(this, target)) {
                    finalizeTrackCreation(target);
                }
            } catch (e:Error) {
                cleanupTrackCreation();
            }
        }

        public function finalizeTrackCreation(targetPin:Pin):Track {
            if (!targetPin || !isValidConnection(this, targetPin)) {
                throw new Error("Invalid track connection");
            }
            removeExistingConnections(targetPin);
            var track:Track = new Track(this, targetPin);
            trace("✅ MANUAL TRACK CREATED: " + this.name + " → " + targetPin.name);
            return track;
        }

        public function cancelTrackCreation():void {
            cleanupTrackCreation();
        }

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
        // SEARCH & NAVIGATION
        // =============================================================================
        private function findPinUnderMouse(stageX:Number, stageY:Number):Pin {
            var mouse:Point = new Point(stageX, stageY);
            var all:Vector.<Pin> = getAllPinsInWindow();
            var closest:Pin = null;
            var minDist:Number = Number.MAX_VALUE;
            for each (var pin:Pin in all) {
                if (pin === this) continue;
                var view:PinView = findPinView(pin);
                if (!view) continue;
                if (view.hitTestPoint(stageX, stageY, true) && isValidConnection(this, pin)) {
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

        private function getAllPinsInWindow():Vector.<Pin> {
            var out:Vector.<Pin> = new Vector.<Pin>();
            var mgr:AtomManager = AtomManager.getInstance();
            var win:Window = findParentWindow();
            if (!win || !mgr) {
                trace("❌ Cannot get pins: no window or atom manager");
                return out;
            }
            
            var atoms:Array = mgr.getAtomsForWindow(win.windowType);
            trace("🔍 Found " + atoms.length + " atoms in window: " + win.windowType);
            
            for each (var a:Object in atoms) {
                var atom:Atom = a.atom;
                for each (var inp:Pin in atom.inputs) out.push(inp);
                for each (var outp:Pin in atom.outputs) out.push(outp);
            }
            
            trace("📌 Total pins found: " + out.length);
            return out;
        }

		private function findPinView(pin:Pin):PinView {
			var result:PinView = null;
			
			if (!pin) {
				trace("❌ findPinView: Pin is null");
				return result;
			}
			
			var atom:Atom = getAtomByPin(pin);
			if (!atom) {
				trace("❌ findPinView: No atom for pin " + pin.name);
				return result;
			}

			var mgr:AtomManager = AtomManager.getInstance();
			if (!mgr) {
				trace("❌ findPinView: AtomManager is null");
				return result;
			}
			
			var data:Object = mgr.getAtomById(atom.id);
			if (!data || !data.view) {
				trace("❌ findPinView: No view data for atom " + atom.id);
				return result;
			}

			var view:AtomView = data.view;
			
			if (!view.stage) {
				trace("❌ findPinView: AtomView not on stage for atom " + atom.id);
				return result;
			}

			try {
				for (var i:int = 0; i < view.numChildren; i++) {
					var child:DisplayObject = view.getChildAt(i);
					if (child is PinView && PinView(child).pin === pin) {
						trace("✅ Found PinView for pin: " + pin.name);
						result = PinView(child);
						break;
					}
				}
			} catch (error:Error) {
				trace("❌ findPinView: Error searching for PinView: " + error.message);
			}

			if (!result) {
				trace("❌ findPinView: No PinView found for pin: " + pin.name);
			}
			
			return result;
		}

        private function findParentWindow():Window {
            var atom:Atom = getAtomByPin(this);
            if (!atom) {
                trace("❌ findParentWindow: No atom for pin " + this.name);
                return null;
            }
            
            var mgr:AtomManager = AtomManager.getInstance();
            var data:Object = mgr.getAtomById(atom.id);
            if (!data || !data.view) {
                trace("❌ findParentWindow: No view for atom " + atom.id);
                return null;
            }
            
            var atomView:AtomView = data.view;
            if (!atomView.stage) {
                trace("❌ findParentWindow: AtomView not on stage");
                return null;
            }
            
            var window:Window = atomView.stage.nativeWindow as Window;
            if (window) {
                trace("✅ Found parent window: " + window.windowType);
            } else {
                trace("❌ findParentWindow: Cannot get window from stage");
            }
            return window;
        }

        private function getStage():Stage {
            var win:Window = findParentWindow();
            return win ? win.stage : null;
        }

        private function removeExistingConnections(targetPin:Pin):void {
            var reg:TrackRegistry = TrackRegistry.getInstance();
            if (!reg) return;
            var tracks:Vector.<Track> = reg.getTracksByPin(targetPin);
            trace("🗑️ Removing " + tracks.length + " existing connections from: " + targetPin.name);
            for each (var t:Track in tracks) t.dispose();
        }

        // =============================================================================
        // VALIDATION
        // =============================================================================
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            if (!fromPin || !toPin) {
                trace("❌ Invalid: null pins");
                return false;
            }
            if (fromPin === toPin) {
                trace("❌ Invalid: same pin");
                return false;
            }
            if (fromPin.type !== TYPE_OUTPUT || toPin.type !== TYPE_INPUT) {
                trace("❌ Invalid: pin types (from: " + fromPin.type + ", to: " + toPin.type + ")");
                return false;
            }
            var fromAtom:Atom = getAtomByPin(fromPin);
            var toAtom:Atom = getAtomByPin(toPin);
            if (!fromAtom || !toAtom) {
                trace("❌ Invalid: no atoms for pins");
                return false;
            }
            if (fromAtom.id == toAtom.id) {
                trace("❌ Invalid: same atom");
                return false;
            }
            
            trace("✅ Valid connection: " + fromPin.name + " → " + toPin.name);
            return true;
        }

		private function getAtomByPin(pin:Pin):Atom {
			// Создаем переменную для результата
			var result:Atom = null;
			
			if (!pin) {
				trace("❌ getAtomByPin: Pin is null");
				return result; // возвращаем null, но тип Atom (null совместим)
			}
			
			var reg:TrackRegistry = TrackRegistry.getInstance();
			if (!reg) {
				trace("❌ getAtomByPin: TrackRegistry is null");
				return result;
			}
			
			try {
				result = reg.getAtomByPin(pin);
				if (!result) {
					trace("❌ getAtomByPin: No atom found for pin " + pin.name);
				}
			} catch (error:Error) {
				trace("❌ getAtomByPin: Error getting atom: " + error.message);
				result = null;
			}
			
			return result;
		}

/** альтернативный вариант с единой точкой возврата 	
private function getAtomByPin(pin:Pin):Atom {
    var result:Atom = null;
    
    if (pin) {
        var reg:TrackRegistry = TrackRegistry.getInstance();
        if (reg) {
            try {
                result = reg.getAtomByPin(pin);
                if (!result) {
                    trace("❌ getAtomByPin: No atom found for pin " + pin.name);
                }
            } catch (error:Error) {
                trace("❌ getAtomByPin: Error getting atom: " + error.message);
            }
        } else {
            trace("❌ getAtomByPin: TrackRegistry is null");
        }
    } else {
        trace("❌ getAtomByPin: Pin is null");
    }
    
    return result;
}	
*/	
	
        // =============================================================================
        // LISTENERS & SUBSCRIPTIONS
        // =============================================================================
        public function addListener(listener:Function):void {
            if (_listeners.indexOf(listener) === -1) {
                _listeners.push(listener);
            }
        }

        public function removeListener(listener:Function):void {
            var i:int = _listeners.indexOf(listener);
            if (i !== -1) _listeners.splice(i, 1);
        }

        private function notifyListeners(newValue:*, oldValue:*):void {
            for (var i:int = 0; i < _listeners.length; i++) {
                _listeners[i](newValue, oldValue, this);
            }
        }

        public function subscribeToPin(targetPin:Pin, eventTypes:*, callback:Function):Boolean {
            if (!targetPin || targetPin === this) {
                trace("❌ Invalid subscription target");
                return false;
            }
            var events:Array = normalizeEventTypes(eventTypes);
            var sub:PinSubscription = new PinSubscription(targetPin, events, callback);
            if (hasExistingSubscription(sub)) {
                trace("⚠ Subscription already exists");
                return false;
            }
            for each (var e:String in events) {
                targetPin.addEventListener(e, callback, false, 0, true);
            }
            _targetedSubscriptions.push(sub);
            trace("✅ Pin subscription created: " + this.name + " → " + targetPin.name);
            return true;
        }

        public function unsubscribeFromPin(targetPin:Pin, eventTypes:* = null):Boolean {
            var events:Array = normalizeEventTypes(eventTypes);
            var removed:Boolean = false;
            for (var i:int = _targetedSubscriptions.length - 1; i >= 0; i--) {
                var sub:PinSubscription = _targetedSubscriptions[i];
                if (sub.targetPin === targetPin) {
                    if (events.length > 0) {
                        removed = removeSpecificEvents(sub, events) || removed;
                        if (sub.eventTypes.length === 0) {
                            _targetedSubscriptions.splice(i, 1);
                        }
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
            for each (var sub:PinSubscription in _targetedSubscriptions) {
                removeAllEvents(sub);
            }
            _targetedSubscriptions = new Vector.<PinSubscription>();
        }

        private function normalizeEventTypes(eventTypes:*):Array {
            if (eventTypes is String) return [eventTypes];
            if (eventTypes is Array) return eventTypes;
            return [PIN_VALUE_CHANGED];
        }

        private function hasExistingSubscription(newSub:PinSubscription):Boolean {
            for each (var sub:PinSubscription in _targetedSubscriptions) {
                if (sub.targetPin === newSub.targetPin && sub.callback === newSub.callback) {
                    for each (var e:String in newSub.eventTypes) {
                        if (sub.eventTypes.indexOf(e) !== -1) return true;
                    }
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
            for each (var e:String in sub.eventTypes) {
                sub.targetPin.removeEventListener(e, sub.callback);
            }
        }

        // =============================================================================
        // EVENTS & GETTERS
        // =============================================================================
        public function notifyConnected():void {
            if (type === TYPE_OUTPUT) {
                dispatchEvent(new PinEvent(PIN_CONNECTED, this, value));
            }
        }

        public function notifyDisconnected():void {
            if (type === TYPE_OUTPUT) {
                dispatchEvent(new PinEvent(PIN_DISCONNECTED, this, value));
            }
        }

        public function get isCreatingTrack():Boolean { return _isCreatingTrack; }
        public function get tempTrack():TempTrack { return _tempTrack; }
        public function get atom():Atom { return _atom; }
        public function get collidingPins():Vector.<Pin> { return _currentCollisions.concat(); }
        public function get autoTracks():Vector.<Track> { return _autoTracks.concat(); }

        // =============================================================================
        // DEBUG METHODS
        // =============================================================================
        /**
         * Отладочный метод для проверки подписок
         */
        public function debugSubscriptions():void {
            trace("=== PIN SUBSCRIPTIONS DEBUG ===");
            trace("Pin: " + this.name + " (" + this.type + ")");
            trace("Value: " + this.value);
            trace("Targeted subscriptions: " + _targetedSubscriptions.length);
            
            for each (var sub:PinSubscription in _targetedSubscriptions) {
                trace("  → Sub to: " + sub.targetPin.name + ", Events: " + sub.eventTypes.join(", "));
            }
            
            trace("Listeners: " + _listeners.length);
            trace("=== END DEBUG ===");
        }
        
        /**
         * Отладочный метод для проверки состояния
         */
        public function debugState():void {
            trace("=== PIN STATE DEBUG ===");
            trace("Name: " + this.name);
            trace("Type: " + this.type);
            trace("ID: " + this.id);
            trace("Value: " + this.value);
            trace("Atom: " + (_atom ? _atom.name : "null"));
            trace("Current collisions: " + _currentCollisions.length);
            trace("Auto tracks: " + _autoTracks.length);
            trace("=== END STATE DEBUG ===");
        }
    }
}