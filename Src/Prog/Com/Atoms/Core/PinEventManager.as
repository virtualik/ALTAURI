package Src.Prog.Com.Atoms.Core {
/**
 * Event manager for pin system
 * FIXED: Simplified to prevent recursive notifications
 */	class PinEventManager {
		private var _allPins:Vector.<Pin> = new Vector.<Pin>();
		private var _subscriptions:Object = {};

		public function PinEventManager() {
			trace("PinEventManager initialized");
		}

		public function registerPin(pin:Pin):void {
			if (_allPins.indexOf(pin) === -1) {
				_allPins.push(pin);
				trace("Pin registered: " + pin.name + " (Total: " + _allPins.length + ")");
			}
		}

		public function unregisterPin(pin:Pin):void {
			var index:int = _allPins.indexOf(pin);
			if (index !== -1) {
				_allPins.splice(index, 1);
				trace("Pin unregistered: " + pin.name + " (Remaining: " + _allPins.length + ")");
			}
		}

		// FIXED: Remove dangerous global subscription methods that cause recursion
		/*
		public function subscribeToAll(eventType:String, listener:Function):void {
			for each (var pin:Pin in _allPins) {
				pin.addEventListener(eventType, listener);
			}
		}

		public function subscribeToPinType(eventType:String, pinType:String, listener:Function):void {
			for each (var pin:Pin in _allPins) {
				if (pin.type === pinType) {
					pin.addEventListener(eventType, listener);
				}
			}

			var key:String = eventType + "_" + pinType;
			if (!_subscriptions[key]) {
				_subscriptions[key] = new Vector.<Function>();
			}
			_subscriptions[key].push(listener);
		}

		public function subscribeToDataType(eventType:String, dataType:String, listener:Function):void {
			for each (var pin:Pin in _allPins) {
				if (pin.data && pin.data.dataType === dataType) {
					pin.addEventListener(eventType, listener);
				}
			}

			var key:String = eventType + "_datatype_" + dataType;
			if (!_subscriptions[key]) {
				_subscriptions[key] = new Vector.<Function>();
			}
			_subscriptions[key].push(listener);
		}
		*/

		/**
		 * FIXED: Limited dispatch to prevent input->input notification storms
		 */
		public function dispatchToAll(sourcePin:Pin, event:PinEvent):void {
			// FIXED: Only dispatch from output pins to prevent recursion
			if (sourcePin.type !== Pin.TYPE_OUTPUT) {
				return;
			}
			
			for each (var pin:Pin in _allPins) {
				if (pin !== sourcePin) {
					pin.dispatchEvent(event);
				}
			}
		}

		public function findPinById(pinId:String):Pin {
			for each (var pin:Pin in _allPins) {
				if (pin.id === pinId) return pin;
			}
			return null;
		}

		public function findPinByName(pinName:String):Pin {
			for each (var pin:Pin in _allPins) {
				if (pin.name === pinName) return pin;
			}
			return null;
		}

		public function findAllPinsByName(pinName:String):Vector.<Pin> {
			var result:Vector.<Pin> = new Vector.<Pin>();
			for each (var pin:Pin in _allPins) {
				if (pin.name === pinName) result.push(pin);
			}
			return result;
		}

		public function getStats():Object {
			var inputPins:int = 0;
			var outputPins:int = 0;
			var totalSubscriptions:int = 0;

			for each (var pin:Pin in _allPins) {
				if (pin.type === Pin.TYPE_INPUT) inputPins++;
				else if (pin.type === Pin.TYPE_OUTPUT) outputPins++;

				if (pin.hasOwnProperty("_targetedSubscriptions")) {
					totalSubscriptions += pin["_targetedSubscriptions"].length;
				}
			}

			return {
				totalPins: _allPins.length,
				inputPins: inputPins,
				outputPins: outputPins,
				totalTargetedSubscriptions: totalSubscriptions,
				subscriptionTypes: 0 // FIXED: Global subscriptions disabled
			};
		}

		private function getKeys(obj:Object):Array {
			var keys:Array = [];
			for (var key:String in obj) keys.push(key);
			return keys;
		}
	}
}
