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
     * Handles mouse interactions for creating connections between atoms.
     * FIXED: Null object reference errors and improved pin targeting logic.
     *
     * @class PinView
     * @extends Sprite
     * @public
     */
    public class PinView extends Sprite {
        private var _pin:Pin;

        /**
         * Creates a new PinView instance.
         *
         * @constructor
         * @param {Pin} pin - Logical pin model for visualization
         */
        public function PinView(pin:Pin) {
            _pin = pin;
            super();
            draw();
            setupInteractions();
            this.name = "PinView_" + pin.name;
        }

        /**
         * Draws the visual representation of the pin.
         * Uses color coding based on pin type (input/output).
         * Increases hit box for better user experience.
         *
         * @private
         */
        private function draw():void {
            this.graphics.clear();

            // Invisible area for increased hit box (better UX)
            this.graphics.beginFill(0x000000, 0);
            this.graphics.drawCircle(0, 0, 8); // Hit box radius increased
            this.graphics.endFill();

            // Visual pin representation
            var color:uint = (_pin.type == Pin.TYPE_INPUT) ? 0xFF4444 : 0x44FF44;
            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 4); // Visual size remains compact
            this.graphics.endFill();

            this.buttonMode = true;
            this.useHandCursor = true;
        }

        /**
         * Sets up mouse handlers for drag and connection creation operations.
         *
         * @private
         */
        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);

            // Ensure these flags are set:
            this.mouseEnabled = true;
            this.mouseChildren = false; // Prevent children from intercepting events
        }

        /**
         * Handles mouse down for starting pin drag operation.
         * Stops event propagation to prevent atom processing.
         *
         * @private
         * @param {MouseEvent} event - Mouse down event
         */
        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation(); // Prevent atom processing
           // event.stopImmediatePropagation(); // Immediate stop to prevent conflicts

            Impulsys.emit(new Impulse("PIN_DRAG_START", {
                pin: _pin,
                startX: event.stageX,
                startY: event.stageY,
                windowType: "Editor"
            }));

            // Subscribe to mouse move and up events on stage
            if (stage) {
                stage.addEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
            }
        }

        /**
         * Handles mouse movement during dragging.
         * Updates real-time visual feedback.
         *
         * @private
         * @param {MouseEvent} event - Mouse move event
         */
        private function on_MouseMove(event:MouseEvent):void {
            Impulsys.emit(new Impulse("PIN_DRAG_UPDATE", {
                pin: _pin,
                currentX: event.stageX,
                currentY: event.stageY
            }));
        }

        /**
         * Handles mouse up for completing drag operations.
         * Performs target pin search and creates connection on validation.
         * FIXED: Added null checks and error handling to prevent crashes.
         *
         * @private
         * @param {MouseEvent} event - Mouse up event
         */
		// В PinView - улучшенная версия on_MouseUp
		private function on_MouseUp(event:MouseEvent):void {
			trace("[--TEST [in PinView]--]")
			try {
				event.stopPropagation();
				event.stopImmediatePropagation();

				trace("=== PIN MOUSE_UP HANDLER ===");
				trace("Pin: " + _pin.name + " (" + _pin.type + ")");

				// удаляем обработчики stage
				if (stage) {
					stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
					stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
				}

				var trackManager:TrackManager = TrackManager.getInstance();
				var currentDragPin:Pin = trackManager ? trackManager.getCurrentDragPin() : null;
				
				trace("-=[]=- Current drag pin: " + (currentDragPin ? currentDragPin.name : "null"));

				// Ищем целевой пин с улучшенной логикой
				var targetPin:Pin = findPinUnderMouseEx(event.stageX, event.stageY, currentDragPin);
				
				trace("Target pin found: " + (targetPin ? targetPin.name : "null"));
trace("---------> pin: " + _pin + "toPin: " + targetPin + "endX: " + event.stageX + "endY: " + event.stageY + "currentDragPin: " + currentDragPin);

			
			
			
			
				Impulsys.emit(new Impulse("PIN_DRAG_END", {
					pin: _pin,
					toPin: targetPin,
					endX: event.stageX,
					endY: event.stageY,
					currentDragPin: currentDragPin
				}));

				trace("=== END PIN MOUSE_UP ===");
			} catch (error:Error) {
				trace("ERROR in PinView.on_MouseUp: " + error.message);
				// Аварийная очистка
				if (stage) {
					stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
					stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
				}
			}
		}

        /** PinView - улучшенный поиск пинов 
         */
		private function findPinUnderMouseEx(stageX:Number, stageY:Number, currentDragPin:Pin):Pin {
			try {
				if (!stage) return null;
				
				var mousePos:Point = new Point(stageX, stageY);
				var allPins:Array = getAllPinsInView();
				var closestPin:Pin = null;
				var minDistance:Number = 25; // Уменьшенный радиус для точности
				
				trace("=== ENHANCED PIN SEARCH ===");
				trace("Mouse: " + stageX + ", " + stageY);
				trace("Pins in view: " + allPins.length);

				for each (var pinView:PinView in allPins) {
					if (!pinView || !pinView.pin) continue;
					
					var pin:Pin = pinView.pin;
					if (pin === currentDragPin) continue;
					
					// Получаем глобальную позицию пина
					var pinGlobalPos:Point = pinView.localToGlobal(new Point(0, 0));
					var distance:Number = Point.distance(mousePos, pinGlobalPos);
					
					trace("Checking pin: " + pin.name + " at distance " + distance.toFixed(1));
					
					if (distance <= minDistance) {
						if (isValidConnection(currentDragPin, pin)) {
							closestPin = pin;
							minDistance = distance; // Обновляем для поиска ближайшего
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

		// Получить все PinView в текущем виде
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

        /**
         * Finds pin under mouse coordinates with extended validation.
         * Uses spatial search and distance checking for precise targeting.
         * FIXED: Added comprehensive null checking and error handling.
         *
         * @private
         * @param {Number} stageX - Mouse X coordinate in stage space
         * @param {Number} stageY - Mouse Y coordinate in stage space
         * @param {Pin} currentDragPin - Currently dragging pin
         * @return {Pin} Found target pin or null
         */
        private function findPinUnderMouse(stageX:Number, stageY:Number, currentDragPin:Pin):Pin {
            try {
                // FIXED: Validate input parameters
                if (!stage || isNaN(stageX) || isNaN(stageY)) {
                    trace("Invalid parameters for pin search");
                    return null;
                }

                var mousePos:Point = new Point(stageX, stageY);

                trace("=== PIN SEARCH DEBUG ===");
                trace("Mouse position: " + stageX + ", " + stageY);

                var closestPin:PinView = null;
                var minDistance:Number = Number.MAX_VALUE;
                var searchRadius:Number = 35; // INCREASED: Better targeting

                var objects:Array = stage.getObjectsUnderPoint(mousePos);
                trace("Total objects under mouse: " + (objects ? objects.length : 0));

                // DIAGNOSTICS: Output all objects under cursor
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

                    // MAIN SEARCH: Look for PinView
                    for each (var obj:DisplayObject in objects) {
                        if (!obj) continue;
                        
                        var className:String = getQualifiedClassName(obj);
                        trace("Checking object: " + className + ", name: " + obj.name);

                        if (obj is PinView) {
                            var targetPinView:PinView = obj as PinView;
                            
                            // FIXED: Validate PinView and its pin
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

                // ALTERNATIVE SEARCH: Recursively search all scene objects
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

        /**
         * Recursive pin search throughout display hierarchy.
         * FIXED: Added null checking and error handling.
         *
         * @private
         * @param {DisplayObjectContainer} container - Container to search in
         * @param {Point} mousePos - Mouse position
         * @param {Pin} currentDragPin - Currently dragging pin
         * @param {Number} radius - Search radius
         * @return {Pin} Found pin or null
         */
        private function findPinRecursive(container:DisplayObjectContainer, mousePos:Point, currentDragPin:Pin, radius:Number):Pin {
            try {
                if (!container) return null;

                var closestPin:Pin = null;
                var minDistance:Number = Number.MAX_VALUE;

                for (var i:int = 0; i < container.numChildren; i++) {
                    var child:DisplayObject = container.getChildAt(i);
                    if (!child) continue;

                    // If this is PinView
                    if (child is PinView) {
                        var pinView:PinView = child as PinView;
                        
                        // FIXED: Validate PinView and its pin
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

                    // Recursively check child containers
                    if (child is DisplayObjectContainer) {
                        var foundPin:Pin = findPinRecursive(child as DisplayObjectContainer, mousePos, currentDragPin, radius);
                        if (foundPin) {
                            var trackManager:TrackManager = TrackManager.getInstance();
                            if (trackManager) {
                                var foundPinPos:Point = trackManager.getGlobalPinPosition(foundPin);
                                var foundDistance:Number = Point.distance(mousePos, foundPinPos);

                                if (foundDistance <= radius && foundDistance < minDistance) {
                                    closestPin = foundPin;
                                    minDistance = foundDistance;
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
         * Validates connection possibility between two pins.
         * Checks pin types, atom ownership and existing connections.
         * FIXED: Added null safety and better error reporting.
         *
         * @private
         * @param {Pin} fromPin - Source pin (must be output)
         * @param {Pin} toPin - Target pin (must be input)
         * @return {Boolean} True if connection is allowed
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            try {
                if (!fromPin || !toPin) {
                    trace("Invalid: one or both pins are null");
                    return false;
                }

                // Prevent self-connection
                if (fromPin === toPin) {
                    trace("Invalid: cannot connect to self");
                    return false;
                }

                // Check type compatibility: output → input
                var validTypes:Boolean = (fromPin.type == Pin.TYPE_OUTPUT && toPin.type == Pin.TYPE_INPUT);
                if (!validTypes) {
                    trace("Invalid pin types: " + fromPin.type + " -> " + toPin.type);
                    return false;
                }

                // Get atoms for ownership validation
                var trackManager:TrackManager = TrackManager.getInstance();
                if (!trackManager) {
                    trace("Invalid: TrackManager not available");
                    return false;
                }

                var fromAtom:Atom = trackManager.getAtomByPin(fromPin);
                var toAtom:Atom = trackManager.getAtomByPin(toPin);

                if (!fromAtom || !toAtom) {
                    trace("Invalid: could not find atoms for pins");
                    return false;
                }

                // Prevent connection of pins from same atom
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

        /**
         * Returns the logical pin model associated with this view.
         *
         * @public
         * @return {Pin} Associated pin model
         */
        public function get pin():Pin {
            return _pin;
        }

        /**
         * Clean up resources and event listeners.
         * FIXED: Added comprehensive cleanup.
         *
         * @public
         */
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
