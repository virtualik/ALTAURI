package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import flash.utils.getQualifiedClassName;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.display.DisplayObjectContainer;

    /**
     * Визуальное представление пина с интерактивными возможностями.
     * Обрабатывает взаимодействия мыши для создания соединений между атомами.
     * 
     * Ключевые улучшения:
     * - Улучшенный поиск пинов с проверкой расстояния
     * - Расширенный хит-бокс для лучшего UX
     * - Подробная отладочная информация
     * - Оптимизированная валидация соединений
     *
     * @class PinView
     * @extends Sprite
     * @public
     */
    public class PinView extends Sprite {
        private var _pin:Pin;

        /**
         * Создает новый экземпляр PinView.
         *
         * @constructor
         * @param {Pin} pin - Логическая модель пина для визуализации
         */
        public function PinView(pin:Pin) {
            _pin = pin;
            super();
            draw();
            setupInteractions();
            this.name = "PinView_" + pin.name;
        }

        /**
         * Рисует визуальное представление пина.
         * Использует цветовую кодировку по типу пина (вход/выход).
         * Увеличивает хит-бокс для лучшего пользовательского опыта.
         *
         * @private
         */
        private function draw():void {
            this.graphics.clear();
            
            // Невидимая область для увеличения хит-бокса (лучший UX)
            this.graphics.beginFill(0x000000, 0);
            this.graphics.drawCircle(0, 0, 8); // Радиус хит-бокса увеличен
            this.graphics.endFill();
            
            // Визуальное представление пина
            var color:uint = (_pin.type == Pin.TYPE_INPUT) ? 0xFF4444 : 0x44FF44;
            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 4); // Визуальный размер остается компактным
            this.graphics.endFill();

            this.buttonMode = true;
            this.useHandCursor = true;
        }

        /**
         * Настраивает обработчики мыши для операций перетаскивания и создания соединений.
         *
         * @private
         */
		private function setupInteractions():void {
			this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
			
			// ДОБАВЬТЕ ЭТИ СТРОЧКИ:
			this.mouseEnabled = true;
			this.mouseChildren = false; // Чтобы дети не перехватывали события
		}

		/**
         * Обрабатывает нажатие мыши для начала операции перетаскивания пина.
         * Останавливает всплытие события для предотвращения обработки атомом.
         *
         * @private
         * @param {MouseEvent} event - Событие нажатия мыши
         */
        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation(); // Предотвращаем обработку атомом

            MultiPulsator.emit(new Impulse("PIN_DRAG_START", {
                pin: _pin,
                startX: event.stageX,
                startY: event.stageY,
                windowType: "Editor"
            }));

            // Подписываемся на события движения и отпускания мыши на stage
            stage.addEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
        }

        /**
         * Обрабатывает движение мыши во время перетаскивания.
         * Обновляет визуальную обратную связь в реальном времени.
         *
         * @private
         * @param {MouseEvent} event - Событие движения мыши
         */
        private function on_MouseMove(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("PIN_DRAG_UPDATE", {
                pin: _pin,
                currentX: event.stageX,
                currentY: event.stageY
            }));
        }

        /**
         * Обрабатывает отпускание мыши для завершения операции перетаскивания.
         * Выполняет поиск целевого пина и создает соединение при валидации.
         *
         * @private
         * @param {MouseEvent} event - Событие отпускания мыши
         */
        private function on_MouseUp(event:MouseEvent):void {
            trace("=== PIN DRAG END ===");
            
            // Получаем текущий перетаскиваемый пин из TrackManager
            var trackManager:TrackManager = TrackManager.getInstance();
            var currentDragPin:Pin = trackManager.getCurrentDragPin();
            trace("Current drag pin: " + (currentDragPin ? currentDragPin.name + " (" + currentDragPin.type + ")" : "null"));

            // Поиск пина под курсором с улучшенной логикой
            var targetPin:Pin = findPinUnderMouse(event.stageX, event.stageY, currentDragPin);
            trace("Final target pin: " + (targetPin ? targetPin.name + " (" + targetPin.type + ")" : "null"));

            MultiPulsator.emit(new Impulse("PIN_DRAG_END", {
                pin: _pin,
                toPin: targetPin,
                endX: event.stageX,
                endY: event.stageY,
                currentDragPin: currentDragPin // Для отладки
            }));

            // Очистка слушателей stage
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
            
            trace("=== END PIN DRAG ===");
        }

        /**
         * Находит пин под координатами мыши с расширенной валидацией.
         * Использует пространственный поиск и проверку расстояния для точного определения.
         *
         * @private
         * @param {Number} stageX - Координата X мыши в пространстве stage
         * @param {Number} stageY - Координата Y мыши в пространстве stage
         * @param {Pin} currentDragPin - Пин, который в данный момент перетаскивается
         * @return {Pin} Найденный целевой пин или null
         */
		private function findPinUnderMouse(stageX:Number, stageY:Number, currentDragPin:Pin):Pin {
			var mousePos:Point = new Point(stageX, stageY);
			
			trace("=== PIN SEARCH DEBUG ===");
			trace("Mouse position: " + stageX + ", " + stageY);

			var closestPin:PinView = null;
			var minDistance:Number = Number.MAX_VALUE;
			var searchRadius:Number = 25;

			var objects:Array = stage.getObjectsUnderPoint(mousePos);
			trace("Total objects under mouse: " + objects.length);

			// ДИАГНОСТИКА: выводим все объекты под курсором
			for (var i:int = 0; i < objects.length; i++) {
				var debugObj:DisplayObject = objects[i];
				var debugPos:Point = debugObj.localToGlobal(new Point(0, 0));
				trace("Object " + i + ": " + getQualifiedClassName(debugObj) + 
					  ", name: " + debugObj.name + 
					  ", globalPos: " + debugPos.x + ", " + debugPos.y +
					  ", parent: " + (debugObj.parent ? getQualifiedClassName(debugObj.parent) : "none"));
			}

			// ОСНОВНОЙ ПОИСК: ищем PinView
			for each (var obj:DisplayObject in objects) {
				var className:String = getQualifiedClassName(obj);
				trace("Checking object: " + className + ", name: " + obj.name);

				if (obj is PinView) {
					var targetPinView:PinView = obj as PinView;
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

			if (closestPin) {
				trace("FOUND TARGET PIN IN MAIN SEARCH: " + closestPin.pin.name);
				return closestPin.pin;
			}

			trace("No pin found in main search");

			// АЛЬТЕРНАТИВНЫЙ ПОИСК: рекурсивно ищем во всех объектах сцены
			trace("=== ALTERNATIVE SEARCH ===");
			var alternativePin:Pin = findPinRecursive(stage, mousePos, currentDragPin, searchRadius);
			if (alternativePin) {
				trace("Found pin via alternative search: " + alternativePin.name);
				return alternativePin;
			}

			trace("=== END PIN SEARCH ===");
			return null;
		}

		// Рекурсивный поиск пинов во всей иерархии отображения
		private function findPinRecursive(container:DisplayObjectContainer, mousePos:Point, currentDragPin:Pin, radius:Number):Pin {
			var closestPin:Pin = null;
			var minDistance:Number = Number.MAX_VALUE;
			
			for (var i:int = 0; i < container.numChildren; i++) {
				var child:DisplayObject = container.getChildAt(i);
				
				// Если это PinView
				if (child is PinView) {
					var pinView:PinView = child as PinView;
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
				
				// Рекурсивно проверяем дочерние контейнеры
				if (child is DisplayObjectContainer) {
					var foundPin:Pin = findPinRecursive(child as DisplayObjectContainer, mousePos, currentDragPin, radius);
					if (foundPin) {
						var foundPinPos:Point = TrackManager.getInstance().getGlobalPinPosition(foundPin);
						var foundDistance:Number = Point.distance(mousePos, foundPinPos);
						
						if (foundDistance <= radius && foundDistance < minDistance) {
							closestPin = foundPin;
							minDistance = foundDistance;
						}
					}
				}
			}
			
			return closestPin;
		}

        /**
         * Валидирует возможность соединения между двумя пинами.
         * Проверяет типы пинов, принадлежность атомам и существующие соединения.
         *
         * @private
         * @param {Pin} fromPin - Исходный пин (должен быть выходом)
         * @param {Pin} toPin - Целевой пин (должен быть входом)
         * @return {Boolean} True если соединение допустимо
         */
		private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
			if (!fromPin || !toPin) {
				trace("Invalid: one or both pins are null");
				return false;
			}

			// Запрещаем соединение с самим собой
			if (fromPin === toPin) {
				trace("Invalid: cannot connect to self");
				return false;
			}

			// Проверяем соответствие типов: выход → вход
			var validTypes:Boolean = (fromPin.type == Pin.TYPE_OUTPUT && toPin.type == Pin.TYPE_INPUT);
			if (!validTypes) {
				trace("Invalid pin types: " + fromPin.type + " -> " + toPin.type);
				return false;
			}

			// Получаем атомы для проверки принадлежности
			var trackManager:TrackManager = TrackManager.getInstance();
			var fromAtom:Atom = trackManager.getAtomByPin(fromPin);
			var toAtom:Atom = trackManager.getAtomByPin(toPin);

			if (!fromAtom || !toAtom) {
				trace("Invalid: could not find atoms for pins");
				return false;
			}

			// Запрещаем соединение пинов одного атома
			if (fromAtom.id == toAtom.id) {
				trace("Invalid: cannot connect pins of the same atom");
				return false;
			}

			// УБРАТЬ ПРОВЕРКУ СУЩЕСТВУЮЩИХ СОЕДИНЕНИЙ
			// var connectionExists:Boolean = trackManager.connectionExists(fromPin, toPin);
			// if (connectionExists) {
			//     trace("Invalid: connection already exists");
			//     return false;
			// }

			trace("Connection VALID: " + fromAtom.type + "." + fromPin.name +
				  " -> " + toAtom.type + "." + toPin.name);
			return true;
		}

        /**
         * Возвращает логическую модель пина, ассоциированную с этим view.
         *
         * @public
         * @return {Pin} Ассоциированная модель пина
         */
        public function get pin():Pin {
            return _pin;
        }
    }
}
