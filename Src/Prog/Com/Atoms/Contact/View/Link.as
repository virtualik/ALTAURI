package Src.Prog.Com.Atoms.Contact.View {
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Com.Atoms.Contact.View.ContactView;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Core.Windows.Window;
    import flash.filters.GlowFilter;
    import flash.events.Event;

    /**
     * Визуальное представление соединения между двумя контактами.
     */
    public class Link extends Sprite {

        private var _fromContact:Contact;
        private var _toContact:Contact;
        private var _connectionId:String;
        private var _breakPoints:Vector.<Point>;
        private var _parentWindow:Window;
        private var _isHighlighted:Boolean = false;

        // Стиль линии
        private static const LINE_COLOR:uint = 0x777777;
        private static const HIGHLIGHT_COLOR:uint = 0x00AAFF;
        private static const ERROR_COLOR:uint = 0xFF0000;
        private static const LINE_ALPHA:Number = 0.7;
        private static const LINE_THICKNESS:Number = 4;

        /**
         * Создает новое визуальное соединение между контактами.
         */
		public function Link(fromContact:Contact, toContact:Contact) {
			// ВЫЗОВ SUPER() ДОЛЖЕН БЫТЬ ПЕРВЫМ!
			super();
			
			// Проверяем типы контактов
			if (fromContact.type !== Contact.TYPE_OUTPUT) {
				throw new ArgumentError("From contact must be OUTPUT type");
			}
			if (toContact.type !== Contact.TYPE_INPUT) {
				throw new ArgumentError("To contact must be INPUT type");
			}

			// Сохраняем ссылки на контакты
			_fromContact = fromContact;
			_toContact = toContact;
			_connectionId = generateConnectionId();
			_breakPoints = new Vector.<Point>();

			this.name = "Link_" + _connectionId;
			
			// Сначала создаем логическую подписку
			createLogicalConnection();
			
			// Затем настраиваем взаимодействия
			setupInteractions();
			
			
			// Добавляем в окно
			addToParentWindow();
		 // 🔥 ОТЛОЖЕННАЯ ОТРИСОВКА: ждем пока контакты будут готовы
			if (this.stage) {
				// Если уже на stage - рисуем сразу
				draw();
			} else {
				// Если еще не на stage - ждем добавления
				this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			}
			trace("✅ Link created: " + _connectionId + 
				  " from " + fromContact.name + 
				  " (" + (fromContact.atom ? fromContact.atom.name : "no atom") + ")" +
				  " to " + toContact.name + 
				  " (" + (toContact.atom ? toContact.atom.name : "no atom") + ")");
		}

		private function onAddedToStage(event:Event):void {
			this.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			trace("🎯 Link added to stage, drawing now...");
			draw();
		}

		/**
		 * Создает логическую подписку между контактами.
		 * Без этого Link будет только визуальным, без передачи данных!
		 */
		private function createLogicalConnection():void {
			trace("🔗 === LINK CREATING LOGICAL SUBSCRIPTION ===");
			trace("From: " + _fromContact.name + 
				  " (" + _fromContact.type + ")" +
				  " in atom: " + (_fromContact.atom ? _fromContact.atom.name : "none"));
			trace("To: " + _toContact.name + 
				  " (" + _toContact.type + ")" +
				  " in atom: " + (_toContact.atom ? _toContact.atom.name : "none"));
			
			if (!_fromContact || !_toContact) {
				trace("❌ Link: Missing contacts for logical connection");
				return;
			}
			
			// Проверяем что контакты принадлежат разным атомам
			if (_fromContact.atom && _toContact.atom && 
				_fromContact.atom.id === _toContact.atom.id) {
				trace("❌ Link: Cannot connect contacts of the same atom");
				return;
			}
			
			// Пытаемся создать подписку
			trace("🔄 Attempting subscription: " + _toContact.name + " → " + _fromContact.name);
			var subscriptionSuccess:Boolean = _toContact.subscribeTo(_fromContact);
			
			if (subscriptionSuccess) {
				trace("✅ Link: Logical subscription created successfully");
				
				// 🔥 НЕМЕДЛЕННАЯ ПЕРЕДАЧА ТЕКУЩЕГО ЗНАЧЕНИЯ
				if (_fromContact.value !== undefined && _fromContact.value !== null) {
					trace("➡️ Link: Propagating initial value: " + _fromContact.value);
					// Устанавливаем значение напрямую, чтобы сработал notifyAtomBehavior
					_toContact.value = _fromContact.value;
				} else {
					trace("ℹ️ Link: Source contact has no initial value to propagate");
				}
			} else {
				trace("❌ Link: Failed to create logical subscription");
				trace("   Check: ");
				trace("   - From contact type: " + _fromContact.type + " (should be OUTPUT)");
				trace("   - To contact type: " + _toContact.type + " (should be INPUT)");
				trace("   - From contact atom: " + (_fromContact.atom ? _fromContact.atom.name : "none"));
				trace("   - To contact atom: " + (_toContact.atom ? _toContact.atom.name : "none"));
			}
			
			trace("🔗 === LOGICAL SUBSCRIPTION ATTEMPT COMPLETE ===");
		}

        /**
         * Настраивает обработчики взаимодействий.
         */
        private function setupInteractions():void {
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            this.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            this.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
            this.addEventListener(MouseEvent.CLICK, onClick);
            
            this.mouseEnabled = true;
            this.buttonMode = true;
            this.useHandCursor = true;
        }

        /**
         * Добавляет Link в родительское окно.
         */
        private function addToParentWindow():void {
            _parentWindow = getParentWindow();
            if (!_parentWindow) {
                trace("❌ Link: No parent window found");
                return;
            }

            // Пытаемся добавить в tracksLayer, если он существует
            if (_parentWindow.tracksLayer) {
                _parentWindow.tracksLayer.addChild(this);
                trace("✅ Link added to tracksLayer");
            } 
            // Если нет tracksLayer, добавляем в overlayLayer
            else if (_parentWindow.overlayLayer) {
                _parentWindow.overlayLayer.addChild(this);
                trace("✅ Link added to overlayLayer");
            }
            // Если нет overlayLayer, добавляем в contentLayer
            else if (_parentWindow.contentLayer) {
                _parentWindow.contentLayer.addChild(this);
                trace("✅ Link added to contentLayer");
            } else {
                trace("❌ Link: No suitable layer found in window");
            }
        }

        /**
         * Получает родительское окно для позиционирования.
         */
        private function getParentWindow():Window {
            if (!_fromContact.atom) return null;
            
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(_fromContact.atom.id);
            if (!atomData || !atomData.view) return null;
            
            var atomView = atomData.view;
            return atomView && atomView.stage ? atomView.stage.nativeWindow as Window : null;
        }

        /**
         * Обрабатывает правый клик для показа контекстного меню.
         */
        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
			
			var pos:Point = new Point(event.stageX, event.stageY);

            Impulsys.emit(new Impulse("LINK_RIGHT_CLICK", {
                link: this,
                globalPosition: pos,
                connectionId: _connectionId,
                fromContact: _fromContact,
                toContact: _toContact
            }));
            
            trace("🖱️ Right click on link: " + _connectionId);
        }

        /**
         * Обрабатывает наведение мыши на линию.
         */
        private function onMouseOver(event:MouseEvent):void {
            _isHighlighted = true;
            draw();
            
            Impulsys.emit(new Impulse("LINK_HOVER_START", {
                link: this,
                connectionId: _connectionId
            }));
        }

        /**
         * Обрабатывает уход мыши с линии.
         */
        private function onMouseOut(event:MouseEvent):void {
            _isHighlighted = false;
            draw();
            
            Impulsys.emit(new Impulse("LINK_HOVER_END", {
                link: this,
                connectionId: _connectionId
            }));
        }

        /**
         * Обрабатывает клик по линии.
         */
        private function onClick(event:MouseEvent):void {
            Impulsys.emit(new Impulse("LINK_CLICK", {
                link: this,
                connectionId: _connectionId,
                globalPosition: new Point(event.stageX, event.stageY)
            }));
        }

        /**
         * Отрисовывает визуальное представление соединения.
         */
		public function draw():void {
			trace("🎨 Link.draw() called for: " + _connectionId);
			
			this.graphics.clear();

			// Получаем позиции контактов
			var fromPos:Point = getGlobalContactPosition(_fromContact);
			var toPos:Point = getGlobalContactPosition(_toContact);
			
			trace("   From pos: (" + fromPos.x + ", " + fromPos.y + ")");
			trace("   To pos: (" + toPos.x + ", " + toPos.y + ")");

			// Получаем контейнер для Link
			var linkContainer:Sprite = getLinkContainer();
			if (!linkContainer) {
				trace("❌ Link: No link container found - cannot draw");
				return;
			}
			
			trace("   Link container: " + linkContainer.name);

			// Конвертируем глобальные координаты в локальные координаты контейнера
			var localFrom:Point = linkContainer.globalToLocal(fromPos);
			var localTo:Point = linkContainer.globalToLocal(toPos);
			
			trace("   Local from: (" + localFrom.x + ", " + localFrom.y + ")");
			trace("   Local to: (" + localTo.x + ", " + localTo.y + ")");

			// Выбираем цвет в зависимости от состояния
			var lineColor:uint = _isHighlighted ? HIGHLIGHT_COLOR : LINE_COLOR;
			
			// Проверяем, передаются ли данные через соединение
			if (_fromContact.value !== null && _fromContact.value !== false) {
				lineColor = 0x00FF00; // Зеленый для активного соединения
			}

			trace("   Line color: 0x" + lineColor.toString(16));

			// Если есть точки излома, рисуем ломаную линию
			if (_breakPoints.length > 0) {
				trace("   Drawing broken line with " + _breakPoints.length + " break points");
				drawBrokenLine(localFrom, localTo, lineColor);
			} else {
				trace("   Drawing straight line");
				drawStraightLine(localFrom, localTo, lineColor);
			}

			// Добавляем свечение, если линия выделена
			if (_isHighlighted) {
				this.filters = [new GlowFilter(lineColor, 0.8, 10, 10, 2, 3)];
			} else {
				this.filters = [];
			}
			
			trace("✅ Link.draw() completed");
		}

        /**
         * Получает контейнер для Link (tracksLayer, overlayLayer или contentLayer).
         */
        private function getLinkContainer():Sprite {
            if (!_parentWindow) return null;
            
            if (_parentWindow.tracksLayer) return _parentWindow.tracksLayer;
            if (_parentWindow.overlayLayer) return _parentWindow.overlayLayer;
            if (_parentWindow.contentLayer) return _parentWindow.contentLayer;
            
            return null;
        }

        /**
         * Получает глобальную позицию контакта через его ContactView.
         */
        private function getGlobalContactPosition(contact:Contact):Point {
            var contactView:ContactView = findContactView(contact);
            if (contactView && contactView.stage) {
                return contactView.localToGlobal(new Point(0, 0));
            }
            
            // Fallback: получаем через AtomView
            if (!contact.atom) return new Point(100, 100);
            
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(contact.atom.id);
            if (!atomData || !atomData.view) return new Point(100, 100);
            
            var atomView = atomData.view;
            
            // Пытаемся найти ContactView
            for (var i:int = 0; i < atomView.numChildren; i++) {
                var child:Object = atomView.getChildAt(i);
                if (child is ContactView) {
                    var cv:ContactView = child as ContactView;
                    if (cv.contact === contact) {
                        return cv.localToGlobal(new Point(0, 0));
                    }
                }
            }
            
            // Если ContactView не найден, используем позицию атома
            return new Point(atomView.x + (contact.type === Contact.TYPE_INPUT ? 0 : atomView.width),
                           atomView.y + 50);
        }

        /**
         * Находит ContactView для контакта.
         */
        private function findContactView(contact:Contact):ContactView {
            if (!contact.atom) return null;
            
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(contact.atom.id);
            if (!atomData || !atomData.view) return null;
            
            var atomView = atomData.view;
            
            for (var i:int = 0; i < atomView.numChildren; i++) {
                var child:Object = atomView.getChildAt(i);
                if (child is ContactView) {
                    var contactView:ContactView = child as ContactView;
                    if (contactView.contact === contact) {
                        return contactView;
                    }
                }
            }
            
            return null;
        }

        /**
         * Рисует прямую линию между контактами.
         */
        private function drawStraightLine(fromPos:Point, toPos:Point, color:uint):void {
            this.graphics.lineStyle(LINE_THICKNESS, color, LINE_ALPHA);
            this.graphics.moveTo(fromPos.x, fromPos.y);
            this.graphics.lineTo(toPos.x, toPos.y);
            
            // Добавляем стрелку на конце
            drawArrow(fromPos, toPos, color);
        }

        /**
         * Рисует ломаную линию с учетом точек излома.
         */
        private function drawBrokenLine(fromPos:Point, toPos:Point, color:uint):void {
            this.graphics.lineStyle(LINE_THICKNESS, color, LINE_ALPHA);
            this.graphics.moveTo(fromPos.x, fromPos.y);

            // Рисуем через все точки излома
            for each (var point:Point in _breakPoints) {
                this.graphics.lineTo(point.x, point.y);
            }

            this.graphics.lineTo(toPos.x, toPos.y);
            
            // Добавляем стрелку на конце
            var lastPoint:Point = _breakPoints.length > 0 ? _breakPoints[_breakPoints.length - 1] : fromPos;
            drawArrow(lastPoint, toPos, color);
        }

        /**
         * Рисует стрелку на конце линии.
         */
private function drawArrow(fromPos:Point, toPos:Point, color:uint):void {
    var dx:Number = toPos.x - fromPos.x;
    var dy:Number = toPos.y - fromPos.y;
    var angle:Number = Math.atan2(dy, dx);
    var arrowLength:Number = 12;
    
    // Левое крыло
    var leftX:Number = toPos.x - arrowLength * Math.cos(angle - Math.PI/6);
    var leftY:Number = toPos.y - arrowLength * Math.sin(angle - Math.PI/6);
    
    // Правое крыло
    var rightX:Number = toPos.x - arrowLength * Math.cos(angle + Math.PI/6);
    var rightY:Number = toPos.y - arrowLength * Math.sin(angle + Math.PI/6);
    
    // Рисуем крылья
    this.graphics.moveTo(toPos.x, toPos.y);
    this.graphics.lineTo(leftX, leftY);
    
    this.graphics.moveTo(toPos.x, toPos.y);
    this.graphics.lineTo(rightX, rightY);
}

        /**
         * Генерирует уникальный ID соединения.
         */
        private function generateConnectionId():String {
            var fromAtomId:String = _fromContact.atom ? _fromContact.atom.id : "unknown";
            var toAtomId:String = _toContact.atom ? _toContact.atom.id : "unknown";
            
            return "contact_link_" + fromAtomId + "_" + _fromContact.name + 
                   "_to_" + toAtomId + "_" + _toContact.name + 
                   "_" + new Date().getTime();
        }

        /**
         * Добавляет точку излома на линию.
         */
        public function addBreakPoint(point:Point):void {
            _breakPoints.push(point);
            draw();
        }

        /**
         * Удаляет точку излома.
         */
        public function removeBreakPoint(point:Point):void {
            var index:int = _breakPoints.indexOf(point);
            if (index !== -1) {
                _breakPoints.splice(index, 1);
                draw();
            }
        }

        /**
         * Обновляет визуальное представление (алиас для draw).
         */
        public function updateVisual():void {
            draw();
        }

        /**
         * Проверяет, соединен ли линк с указанным контактом.
         */
        public function isConnectedToContact(contact:Contact):Boolean {
            return _fromContact === contact || _toContact === contact;
        }

        /**
         * Проверяет, соединен ли линк с указанным атомом.
         */
        public function isConnectedToAtom(atomId:String):Boolean {
            return (_fromContact.atom && _fromContact.atom.id === atomId) ||
                   (_toContact.atom && _toContact.atom.id === atomId);
        }

        /**
         * Получает информацию о соединении.
         */
        public function getConnectionInfo():Object {
            var fromAtomId:String = _fromContact.atom ? _fromContact.atom.id : "unknown";
            var toAtomId:String = _toContact.atom ? _toContact.atom.id : "unknown";
            
            return {
                fromContact: _fromContact.name,
                fromContactId: _fromContact.id,
                fromAtom: fromAtomId,
                toContact: _toContact.name,
                toContactId: _toContact.id,
                toAtom: toAtomId,
                connectionId: _connectionId,
                breakPoints: _breakPoints.length,
                isHighlighted: _isHighlighted,
                value: _fromContact.value
            };
        }

        /**
         * Освобождает ресурсы.
         */
        public function dispose():void {
            trace("🧹 Disposing Link: " + _connectionId);
            
            this.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            this.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            this.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
            this.removeEventListener(MouseEvent.CLICK, onClick);
            
            this.graphics.clear();
            this.filters = [];

            // Удаляем из родительского контейнера
            if (this.parent != null) {
                this.parent.removeChild(this);
                trace("✅ Link removed from display list");
            }

            _fromContact = null;
            _toContact = null;
            _breakPoints = null;
            _parentWindow = null;
            
            trace("✅ Link disposed: " + _connectionId);
        }

        // =========================================================================
        // PUBLIC ACCESSORS
        // =========================================================================
        public function get fromContact():Contact { return _fromContact; }
        public function get toContact():Contact { return _toContact; }
        public function get connectionId():String { return _connectionId; }
        public function get breakPoints():Vector.<Point> { return _breakPoints.slice(); }
        public function get isHighlighted():Boolean { return _isHighlighted; }
        public function get parentWindow():Window { return _parentWindow; }
    }
}