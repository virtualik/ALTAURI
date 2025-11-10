package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import flash.utils.getQualifiedClassName;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.display.DisplayObjectContainer;

    /**
     * Visual representation of a pin with interactive capabilities.
     * Now initiates track creation directly through Pin class but preserves all search logic.
     */
    public class PinView extends Sprite {
        private var _pin:Pin;

        public function PinView(pin:Pin) {
            _pin = pin;
            super();
            draw();
            setupInteractions();
            this.name = "PinView_" + pin.name;
        }

        private function draw():void {
            this.graphics.clear();
            this.graphics.beginFill(0x000000, 0);
            this.graphics.drawCircle(0, 0, 8);
            this.graphics.endFill();

            var color:uint = (_pin.type == Pin.TYPE_INPUT) ? 0xFF4444 : 0x44FF44;
            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 4);
            this.graphics.endFill();

            this.buttonMode = true;
            this.useHandCursor = true;
        }

        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.mouseEnabled = true;
            this.mouseChildren = false;
        }

        /**
         * Handles mouse down for starting track creation (output pins only).
         * For input pins, falls back to original drag behavior.
         */
        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation();

            if (_pin.type === Pin.TYPE_OUTPUT) {
                // НОВАЯ ЛОГИКА: output pins создают треки напрямую
                trace("=== PINVIEW MOUSE DOWN (OUTPUT) ===");
                trace("Output pin clicked: " + _pin.name);

                var startPos:Point = new Point(event.stageX, event.stageY);
                _pin.startTrackCreation(startPos);
                
                trace("Track creation initiated for pin: " + _pin.name);
            } else {
                // СТАРАЯ ЛОГИКА: input pins используют импульсную систему для обратной совместимости
                trace("=== PINVIEW MOUSE DOWN (INPUT) ===");
                
                Impulsys.emit(new Impulse("PIN_DRAG_START", {
                    pin: _pin,
                    startX: event.stageX,
                    startY: event.stageY,
                    windowType: "Editor"
                }));

                if (stage) {
                    stage.addEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
                    stage.addEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
                }
            }
        }

        // =========================================================================
        // СУЩЕСТВУЮЩИЕ МЕТОДЫ ПОИСКА ПИНОВ (СОХРАНЯЕМ)
        // =========================================================================

        private function on_MouseMove(event:MouseEvent):void {
            Impulsys.emit(new Impulse("PIN_DRAG_UPDATE", {
                pin: _pin,
                currentX: event.stageX,
                currentY: event.stageY
            }));
        }

        private function on_MouseUp(event:MouseEvent):void {
            trace("[--TEST [in PinView]--]")
            try {
                event.stopPropagation();
                event.stopImmediatePropagation();

                trace("=== PIN MOUSE_UP HANDLER ===");
                trace("Pin: " + _pin.name + " (" + _pin.type + ")");

                if (stage) {
                    stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
                    stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
                }

                // Для обратной совместимости пока используем старую логику поиска
                var targetPin:Pin = findPinUnderMouseEx(event.stageX, event.stageY, _pin);
                
                trace("Target pin found: " + (targetPin ? targetPin.name : "null"));

                Impulsys.emit(new Impulse("PIN_DRAG_END", {
                    pin: _pin,
                    toPin: targetPin,
                    endX: event.stageX,
                    endY: event.stageY,
                    currentDragPin: _pin
                }));

                trace("=== END PIN MOUSE_UP ===");
            } catch (error:Error) {
                trace("ERROR in PinView.on_MouseUp: " + error.message);
                if (stage) {
                    stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
                    stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
                }
            }
        }

        private function findPinUnderMouseEx(stageX:Number, stageY:Number, currentDragPin:Pin):Pin {
            try {
                if (!stage) return null;
                
                var mousePos:Point = new Point(stageX, stageY);
                var allPins:Array = getAllPinsInView();
                var closestPin:Pin = null;
                var minDistance:Number = 25;
                
                trace("=== ENHANCED PIN SEARCH ===");
                trace("Mouse: " + stageX + ", " + stageY);
                trace("Pins in view: " + allPins.length);

                for each (var pinView:PinView in allPins) {
                    if (!pinView || !pinView.pin) continue;
                    
                    var pin:Pin = pinView.pin;
                    if (pin === currentDragPin) continue;
                    
                    var pinGlobalPos:Point = pinView.localToGlobal(new Point(0, 0));
                    var distance:Number = Point.distance(mousePos, pinGlobalPos);
                    
                    trace("Checking pin: " + pin.name + " at distance " + distance.toFixed(1));
                    
                    if (distance <= minDistance) {
                        if (isValidConnection(currentDragPin, pin)) {
                            closestPin = pin;
                            minDistance = distance;
                            trace("VALID PIN: " + pin.name + " at " + distance.toFixed(1));
                        }
                    }
                }
                
                trace("Final closest pin: " + (closestPin ? closestPin.name : "null"));
                trace("=== END ENHANCED SEARCH ===");
                
            } catch (error:Error) {
                trace("ERROR in findPinUnderMouseEx: " + error.message);
                return null;
            }
            return closestPin;
        }

        private function getAllPinsInView():Array {
            var pins:Array = [];
            var atomManager:AtomManager = AtomManager.getInstance();
            
            if (!atomManager) return pins;
            
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");
            for each (var atomData:Object in allAtoms) {
                var atomView:AtomView = atomData.view;
                if (!atomView) continue;
                
                for (var i:int = 0; i < atomView.numChildren; i++) {
                    var child:DisplayObject = atomView.getChildAt(i);
                    if (child is PinView) {
                        pins.push(child as PinView);
                    }
                }
            }
            
            return pins;
        }

        private function findPinUnderMouse(stageX:Number, stageY:Number, currentDragPin:Pin):Pin {
            try {
                if (!stage || isNaN(stageX) || isNaN(stageY)) {
                    trace("Invalid parameters for pin search");
                    return null;
                }

                var mousePos:Point = new Point(stageX, stageY);
                trace("=== PIN SEARCH DEBUG ===");
                trace("Mouse position: " + stageX + ", " + stageY);

                var closestPin:PinView = null;
                var minDistance:Number = Number.MAX_VALUE;
                var searchRadius:Number = 35;

                var objects:Array = stage.getObjectsUnderPoint(mousePos);
                trace("Total objects under mouse: " + (objects ? objects.length : 0));

                if (objects) {
                    for (var i:int = 0; i < objects.length; i++) {
                        var debugObj:DisplayObject = objects[i];
                        if (debugObj) {
                            var debugPos:Point = debugObj.localToGlobal(new Point(0, 0));
                            trace("Object " + i + ": " + getQualifiedClassName(debugObj) +
                                  ", name: " + debugObj.name +
                                  ", globalPos: " + debugPos.x + ", " + debugPos.y +
                                  ", parent: " + (debugObj.parent ? getQualifiedClassName(debugObj.parent) : "none"));
                        }
                    }

                    for each (var obj:DisplayObject in objects) {
                        if (!obj) continue;
                        
                        var className:String = getQualifiedClassName(obj);
                        trace("Checking object: " + className + ", name: " + obj.name);

                        if (obj is PinView) {
                            var targetPinView:PinView = obj as PinView;
                            
                            if (!targetPinView || !targetPinView.pin) {
                                trace("  - Skipping invalid PinView");
                                continue;
                            }
                            
                            var targetPin:Pin = targetPinView.pin;

                            if (targetPin === currentDragPin) {
                                trace("  - Skipping current drag pin");
                                continue;
                            }

                            trace("  - Found PinView: " + targetPin.name);

                            var pinPos:Point = targetPinView.localToGlobal(new Point(0, 0));
                            var distance:Number = Point.distance(mousePos, pinPos);

                            trace("  - Pin global position: " + pinPos.x + ", " + pinPos.y);
                            trace("  - Distance: " + distance + " pixels");

                            if (distance <= searchRadius && distance < minDistance) {
                                if (currentDragPin && isValidConnection(currentDragPin, targetPin)) {
                                    closestPin = targetPinView;
                                    minDistance = distance;
                                    trace("  - VALID PIN FOUND!");
                                }
                            }
                        }
                    }
                }

                if (closestPin && closestPin.pin) {
                    trace("FOUND TARGET PIN IN MAIN SEARCH: " + closestPin.pin.name);
                    return closestPin.pin;
                }

                trace("No pin found in main search");
                trace("=== ALTERNATIVE SEARCH ===");
                var alternativePin:Pin = findPinRecursive(stage, mousePos, currentDragPin, searchRadius);
                if (alternativePin) {
                    trace("Found pin via alternative search: " + alternativePin.name);
                    return alternativePin;
                }

                trace("=== END PIN SEARCH ===");
            } catch (error:Error) {
                trace("ERROR in findPinUnderMouse: " + error.message);
                return null;
            }
            return null;
        }

		private function findPinRecursive(container:DisplayObjectContainer, mousePos:Point, currentDragPin:Pin, radius:Number):Pin {
			try {
				if (!container) return null;

				var closestPin:Pin = null;
				var minDistance:Number = Number.MAX_VALUE;

				for (var i:int = 0; i < container.numChildren; i++) {
					var child:DisplayObject = container.getChildAt(i);
					if (!child) continue;

					if (child is PinView) {
						var pinView:PinView = child as PinView;
						
						if (!pinView || !pinView.pin) continue;
						
						var pin:Pin = pinView.pin;

						if (pin === currentDragPin) continue;

						var pinPos:Point = pinView.localToGlobal(new Point(0, 0));
						var distance:Number = Point.distance(mousePos, pinPos);

						trace("Alternative found PinView: " + pin.name + " at distance " + distance.toFixed(2));

						if (distance <= radius && distance < minDistance) {
							if (isValidConnection(currentDragPin, pin)) {
								closestPin = pin;
								minDistance = distance;
							}
						}
					}

					if (child is DisplayObjectContainer) {
						var foundPin:Pin = findPinRecursive(child as DisplayObjectContainer, mousePos, currentDragPin, radius);
						if (foundPin) {
							// Используем TrackRegistry вместо TrackManager
							var trackRegistry:TrackRegistry = TrackRegistry.getInstance();
							if (trackRegistry) {
								var foundAtom:Atom = trackRegistry.getAtomByPin(foundPin);
								var foundAtomView:AtomView = trackRegistry.getAtomView(foundAtom);
								if (foundAtomView) {
									// ВМЕСТО TrackRegistry.getPinIndex() используем локальный расчет:
									var foundPinIndex:int = calculatePinIndex(foundAtom, foundPin);
									var totalPins:int = foundPin.type == Pin.TYPE_INPUT ? foundAtom.inputs.length : foundAtom.outputs.length;
									var foundPinY:Number = foundAtomView.height * (foundPinIndex + 1) / (totalPins + 1);
									var foundPinX:Number = foundPin.type == Pin.TYPE_INPUT ? 0 : foundAtomView.width;
									var foundPinPos:Point = foundAtomView.localToGlobal(new Point(foundPinX, foundPinY));
									
									var foundDistance:Number = Point.distance(mousePos, foundPinPos);

									if (foundDistance <= radius && foundDistance < minDistance) {
										closestPin = foundPin;
										minDistance = foundDistance;
									}
								}
							}
						}
					}
				}

			} catch (error:Error) {
				trace("ERROR in findPinRecursive: " + error.message);
				return null;
			}
			return closestPin;
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

        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            try {
                if (!fromPin || !toPin) {
                    trace("Invalid: one or both pins are null");
                    return false;
                }

                if (fromPin === toPin) {
                    trace("Invalid: cannot connect to self");
                    return false;
                }

                var validTypes:Boolean = (fromPin.type == Pin.TYPE_OUTPUT && toPin.type == Pin.TYPE_INPUT);
                if (!validTypes) {
                    trace("Invalid pin types: " + fromPin.type + " -> " + toPin.type);
                    return false;
                }

                // Используем TrackRegistry вместо TrackManager
                var trackRegistry:TrackRegistry = TrackRegistry.getInstance();
                if (!trackRegistry) {
                    trace("Invalid: TrackRegistry not available");
                    return false;
                }

                var fromAtom:Atom = trackRegistry.getAtomByPin(fromPin);
                var toAtom:Atom = trackRegistry.getAtomByPin(toPin);

                if (!fromAtom || !toAtom) {
                    trace("Invalid: could not find atoms for pins");
                    return false;
                }

                if (fromAtom.id == toAtom.id) {
                    trace("Invalid: cannot connect pins of the same atom");
                    return false;
                }

                trace("Connection VALID: " + fromAtom.type + "." + fromPin.name +
                      " -> " + toAtom.type + "." + toPin.name);
            } catch (error:Error) {
                trace("ERROR in isValidConnection: " + error.message);
                return false;
            }
            return true;
        }

        public function get pin():Pin {
            return _pin;
        }

        public function dispose():void {
            try {
                this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
                
                if (stage) {
                    stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
                    stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
                }
                
                _pin = null;
            } catch (error:Error) {
                trace("ERROR in PinView.dispose: " + error.message);
            }
        }
    }
}
