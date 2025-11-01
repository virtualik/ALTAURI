ALTARUS

"ИТ Проект" — это конкретно очерченный и ограниченный по времени комплекс взаимосвязанных задач,
направленный на создание, разработку,
внедрение или существенное усовершенствование программного продукта, информационной системы,
аппаратного комплекса или иного решения, функционирующего с использованием Компьютерных Систем и технологий,
с целью достижения заранее определенных бизнес- или технических результатов.

"Приложение" — это самостоятельная или взаимосвязанная компьютерная программа (или набор программ),
предназначенная для прямого взаимодействия с пользователем с целью выполнения конкретной практической задачи
или предоставления определенного сервиса (например, обработка текста,
управление финансами, развлечения) на конкретной целевой платформе (десктоп, мобильное устройство, веб-браузер).

"Программа" (в информатике) — это упорядоченная последовательность команд (инструкций),
написанная на языке программирования и предназначенная для исполнения Компьютерной Системой (процессором)
с целью обработки данных и выполнения определенного алгоритма.

В современной практике программирования (например, в Объектно-Ориентированном Программировании — ООП),
эта последовательность команд часто структурируется как совокупность объектов,
объединяющих в себе данные (свойства) и операции для работы с ними (методы),
что обеспечивает более модульный, гибкий и масштабируемый подход к решению сложных задач.

"Инициализация базового программного пространства" — это критически важная задача Ядра приложения,
которая закладывает его минимально необходимый архитектурный фундамент путем создания основного контекста исполнения,
необходимого для последующей, отложенной загрузки модулей.
Этот процесс включает:
Формирование Оболочки: Создание главных окон или визуальных контейнеров (UI Shell) на целевой платформе (Windows/Android).
Централизация Действий: Регистрация базовой системы Команд (Command Pattern), которая служит точкой входа для пользовательских действий.
Установление Связи: Запуск системы обмена сообщениями (Event Bus), которая становится единственным каналом для асинхронного взаимодействия
и управления зависимостями между полностью разделенными модулями.вого програмного пространства" закладывает основу реализации Приложения


ALTAURUS - имя прототипа приложения

Это моё видение структуры папок Проекта:

#[ Структура папок проекта ]

Src                          #[ ИСХОДНЫЙ КОД ПРИЛОЖЕНИЯ ]
└📁 Prog                      #[ КОРНЕВАЯ ПАПКА ПРОЕКТА ]
  ├📄 Main.as                  #[ ТОЧКА ВХОДА В ПРИЛОЖЕНИЕ ]
  │
  │
  ├📁 Core                     #[ ЯДРО ОСНОВА ПРИЛОЖЕНИЯ - ПРОСТРАНСТВО ИСПОЛНЕНИЯ ПРОГРАММЫ ]
  │ ├📁 Commands                #[ СИСТЕМА ПРИНУДИТЕЛЬНОГО ВЫПОЛНЕНИЯ ОПЕРАЦИЙ ]
  │ │ ├📄 Command.as             // Базовый класс команд (отложенное выполнение, шаблонный метод)
  │ │ ├📄 CommandErrorEvent.as   // Событие ошибки выполнения команды
  │ │ ├📄 ICommand.as            // Интерфейс всех команд (контракт выполнения)
  │ │ ├📄 InvokeFunction.as      // Команда-обёртка для произвольных функций
  │ │ ├📄 ParallelCommand.as     // Композитная команда параллельного выполнения
  │ │ ├📄 RegisterData.as        // Команда регистрации данных в DataManager
  │ │ ├📄 SerialCommand.as       // Композитная команда последовательного выполнения 
  │ │ ├📄 UnregisterData.as      // Команда удаления данных из DataManager
  │ │ └📄 WaitForCondition.as    // Команда ожидания условия с таймаутом
  │ │
  │ ├📁 Managers                #[ ТУТ МЕНЕДЖЕРЫ СИСТЕМЫ ]
  │ │ ├📄 AtomManager.as         // Реестр атомов, привязка к окнам
  │ │ ├📄 DataManager.as         // Глобальное хранилище данных
  │ │ ├📄 Director.as            // Последовательность запуска приложения
  │ │ └📄 WindowsManager.as      // Фабрика и реестр окон
  │ │
  │ ├📁 MultiPulsator           #[ ТУТ СИСТЕМА КОММУНИКАЦИИ ]
  │ │ ├📄 IImpulse.as            // Интерфейс импульсов (тип + данные)
  │ │ ├📄 Impulse.as             // Реализация импульса - сообщение системы
  │ │ └📄 MultiPulsator.as       // Центральный хаб сообщений (паттерн издатель-подписчик)
  │ │
  | └📄 Window.as                // Универсальное окно приложения (холст, pan/zoom, трансформатор событий)
  │
  │
  └📁 Com                      #[ ТУТ РЕАЛИЗАЦИЯ КОМПОНЕНТНЫХ ЧАСТЕЙ ПРОЕКТА - МОДУЛЕЙ ]
    ├📁 Assets                   #[ ТУТ БУДЕТ РЕАЛИЗАЦИЯ РЕСУРСОВ ]
    │ ├📄 AssetManager.as
    │ ├📁 Assets                  #[ ТУТ БУДУТ СОХРАНЯТСЯ САМИ РЕСУРСНЫЕ ФАЙЛЫ ]
    │ └📁 Services                #[ ТУТ БУДЕТ РЕАЛИЗАЦИЯ СЕРВИСОВ ДОМЕНА РЕСУРСОВ ]
    │   ├📄 AssetLоader.as
    │   ├📄 AssetRegistry.as
    │   └📄 AssetSaver.as
    │
    ├📁 Atoms                   #[ АТОМЫ КАК СУЩНОСТИ ]
    │ ├📁 Core                    #[ ТУТ РЕАЛИЗАЦИЯ АТОМОВ ]
    │ │ ├📜 AtomFactory.as       // Централизованная фабрика создания атомов (логика + представление)
    │ │ ├📜 BaseAtom.as          // Базовый класс атома (иммутабельная логика, пины, позиция)
    │ │ ├📜 BaseAtomView.as      // Базовое визуальное представление (перетаскивание, пины, обновления)
    │ │ ├📜 BaseEditAtomView.as  // Устаревший класс редактора (дублирует BaseAtomView)
    │ │ ├📜 DeviceAtomView.as    // Представление для симуляции (взаимодействие, отображение состояния)
    │ │ ├📜 EditorAtomView.as    // Представление для редактирования (позиционирование, соединения)
    │ │ ├📜 IAtomView.as         // Интерфейс всех представлений атомов (контракт визуализации)
    │ │ ├📜 Pin.as               // Визуальный и логический контакт атома (вход/выход, соединения)
    │ │ ├📜 Track.as             // Визуальное соединение между пинами (линии, передача данных)   
    │ │ └📜 TrackManager.as      // Центральный менеджер соединений (создание, удаление, обновление треков
    │ │ 
    │ ├📁 Logic                  #[ ТУТ БУДЕТ РЕАЛИЗАЦИЯ ПОВЕДЕНИЯ АТОМОВ ИХ КОМПЬЮТИНГОВЫЕ КЛАССЫ ]
    │ │
    │ ├📁 Linker                 #[ ТУТ БУДЕТ РЕАЛИЗАЦИЯ СОЕДИНЕНИЙ АТОМОВ ]
    │ │ └📄 ... .as
    │ │
    │ └📁 Assembly               #[ ТУТ БУДЕТ РЕАЛИЗАЦИЯ СБОРОК АТОМОВ ]
    │   └📄 ... .as
    ├📁 ... 



Класс Window это "Визуальная Песочница Элементов" в которой будет развиваться интеракции с пользователем.
Главное конструктивное решение это предоставление Элементу изолированность от платформы приложения которая стоит за Объектом класса Window.
Элементы способны осуществлять обмен сообщениями с подписчиками и это единственный путь коммуницирования между собой.



Это все классы проекта:

package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import flash.utils.Dictionary;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Managers.DataManager;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Atoms.Custom.ButtonAtom;
    import Src.Prog.Com.Atoms.Custom.CounterAtom;
    import Src.Prog.Com.Atoms.Custom.NumberDisplayAtom;
    import Src.Prog.Com.Atoms.Custom.ButtonAtom_EditorView;
    import Src.Prog.Com.Atoms.Custom.CounterAtom_EditorView;
    import Src.Prog.Com.Atoms.Custom.NumberDisplayAtom_EditorView;

    /**
     * Centralized factory for creating atom instances (BaseAtom + BaseAtomView).
     * Uses a registry in DataManager to map atom types to their concrete classes.
     * Integrates with MultiPulsator for system communication.
     */
    public class AtomFactory {
        // Используем DataManager как DataBank для хранения реестра
        public static const REGISTRY_KEY:String = "ATOM_FACTORY_REGISTRY";

        /**
         * Initializes the factory by ensuring the registry exists in DataManager.
         * This should be called during application startup.
         */
        public static function initialize():void {
            if (!DataManager.hasData(REGISTRY_KEY)) {
                DataManager.registerData(REGISTRY_KEY, new Dictionary());
            }

            // Register default atom types
            registerDefaultAtomTypes();

            MultiPulsator.emit(new Impulse("ATOM_FACTORY_INITIALIZED"));
        }

		/**
		 * Registers default atom types.
		 */
		private static function registerDefaultAtomTypes():void {
			// Register Button atom
			registerAtomType("Button",
				ButtonAtom,
				ButtonAtom_EditorView,
				"Button",
				"Input"
			);

			// Register Counter atom
			registerAtomType("Counter",
				CounterAtom,
				CounterAtom_EditorView,
				"Counter",
				"Logic"
			);

			// Register NumberDisplay atom
			registerAtomType("NumberDisplay",
				NumberDisplayAtom,
				NumberDisplayAtom_EditorView,
				"Number Display",
				"Output"
			);
		}

        /**
         * Registers a new atom type with its concrete BaseAtom and BaseAtomView classes.
         * @param atomType The unique identifier for the atom type (e.g., "Button").
         * @param atomClass The BaseAtom subclass used for the atom's logic.
         * @param viewClass The BaseAtomView subclass used for the atom's view (e.g., EditorAtomView, DeviceAtomView).
         * @param displayName An optional human-readable name for the atom type.
         * @param category An optional category for grouping the atom type.
         */
        public static function registerAtomType(atomType:String, atomClass:Class, viewClass:Class, displayName:String = null, category:String = "General"):void {
            var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
            if (!atomType || !atomClass || !viewClass) {
                MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Cannot register invalid atom type: " + atomType }));
                return;
            }
            registry[atomType] = {
                atomClass: atomClass,
                viewClass: viewClass,
                displayName: displayName || atomType,
                category: category
            };
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", { level: "DEBUG", source: "AtomFactory", message: "Registered atom type: " + atomType }));
        }

        /**
         * Creates a new atom instance (BaseAtom + BaseAtomView) of the specified type.
         * The created atom and view are linked and returned as an object.
         * @param atomType The type of atom to create (e.g., "Button").
         * @param position The initial position for the atom.
         * @param name An optional name for the atom (defaults to the display name of the type).
         * @return An object containing {atom: BaseAtom, view: BaseAtomView}, or null if creation failed.
         */
		public static function createAtom(atomType:String, position:Point, name:String = null):Object {
			trace("AtomFactory.createAtom called: " + atomType + " at " + position);

			if (!atomType || !position) {
				trace("ERROR: Invalid parameters");
				MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Invalid parameters for createAtom: type=" + atomType + ", pos=" + position }));
				return null;
			}

			var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
			var typeInfo:Object = registry[atomType];

			if (!typeInfo) {
				trace("ERROR: Atom type not found in registry: " + atomType);
				MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Atom type not found in registry: " + atomType }));
				return null;
			}

			trace("Found atom type info: " + typeInfo.displayName);

			var atomInfo:Object = typeInfo;
			var atomName:String = name || atomInfo.displayName;
			var atomId:String = generateId();

			trace("Creating atom with ID: " + atomId);

			try {
				// 1. Создать визуальное представление
				var ViewClass:Class = atomInfo.viewClass;
				trace("ViewClass: " + ViewClass);
				var view:BaseAtomView = new ViewClass() as BaseAtomView;
				trace("View created: " + view);

				// 2. Создать логическое представление
				var AtomClass:Class = atomInfo.atomClass;
				trace("AtomClass: " + AtomClass);
				var inputPins:Vector.<Pin> = createPinsForType(atomType, Pin.TYPE_INPUT);
				var outputPins:Vector.<Pin> = createPinsForType(atomType, Pin.TYPE_OUTPUT);
				trace("Pins created - inputs: " + inputPins.length + ", outputs: " + outputPins.length);

				var atom:BaseAtom = new AtomClass(atomId, position, atomName, atomType, inputPins, outputPins);
				trace("Atom created: " + atom);

				// 3. Связать атом и вью
				view.initWithAtom(atom);
				trace("View initialized with atom");

				MultiPulsator.emit(new Impulse("LOG_MESSAGE", { level: "INFO", source: "AtomFactory", message: "Atom created: " + atomId + " (" + atomType + ")" }));

				trace("SUCCESS: Atom creation completed");
				return { atom: atom, view: view };

			} catch (e:Error) {
				trace("ERROR in atom creation: " + e.message + "\n" + e.getStackTrace());
				MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Error creating atom type " + atomType + ": " + e.message }));
				return null;
			}
		return null;
		}

        /**
         * Generates a unique identifier for an atom.
         * @return A unique string ID.
         */
        private static function generateId():String {
            // Простой генератор ID, можно улучшить
            return "atom_" + new Date().getTime() + "_" + Math.round(Math.random() * 1000000);
        }

        /**
         * Creates and configures the pins (input or output) for a specific atom type.
         * This is a simplified version. In practice, pin creation might be part of the ConcreteAtom constructor.
         * @param type The atom type (e.g., "Button").
         * @param pinType The type of pins to create (Pin.TYPE_INPUT or Pin.TYPE_OUTPUT).
         * @return A Vector of Pin instances.
         */
        private static function createPinsForType(type:String, pinType:String):Vector.<Pin> {
            var pins:Vector.<Pin> = new Vector.<Pin>();
            // Пример на основе старого кода
            switch (type) {
                case "Button":
                    if (pinType === Pin.TYPE_OUTPUT) pins.push(new Pin("out", Pin.TYPE_OUTPUT, null));
                    break;
                case "Counter":
                    if (pinType === Pin.TYPE_INPUT) pins.push(new Pin("in", Pin.TYPE_INPUT, null));
                    if (pinType === Pin.TYPE_OUTPUT) pins.push(new Pin("out", Pin.TYPE_OUTPUT, null));
                    break;
                case "NumberDisplay":
                    if (pinType === Pin.TYPE_INPUT) pins.push(new Pin("in", Pin.TYPE_INPUT, null));
                    break;
                default:
                    // Пины по умолчанию, если тип неизвестен
                    if (pinType === Pin.TYPE_INPUT) pins.push(new Pin("in", Pin.TYPE_INPUT, null));
                    if (pinType === Pin.TYPE_OUTPUT) pins.push(new Pin("out", Pin.TYPE_OUTPUT, null));
            }
            return pins;
        }

        // --- Утилиты ---

        /**
         * Gets all registered atom type names.
         * @return Array of registered atom type names.
         */
        public static function getRegisteredTypeNames():Array {
            var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
            if (!registry) return [];

            var names:Array = [];
            for (var type:String in registry) {
                names.push(type);
            }
            return names;
        }

        /**
         * Gets information about a specific atom type.
         * @param atomType The atom type to get information for.
         * @return Object with atom type information, or null if not found.
         */
        public static function getAtomInfo(atomType:String):Object {
            var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
            if (!registry) return null;

            return registry[atomType];
        }
    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Represents the base immutable class for computational components (atoms).
     * Contains core properties like ID, position, name, type, and input/output pins.
     * Implements immutable behavior: methods that change state return a *new* BaseAtom instance.
     * Integrates with MultiPulsator for system communication.
     */
    public class BaseAtom {
        public var id:String;
        public var position:Point;
        // Убран displayObject - визуализацией управляет BaseAtomView
        public var name:String;
        public var type:String;
        private var _inputContacts:Vector.<Pin>;
        private var _outputContacts:Vector.<Pin>;

        /**
         * Constructs a BaseAtom instance.
         * @param id The unique identifier for the atom.
         * @param pos The initial position of the atom.
         * @param name The name of the atom.
         * @param type The type of the atom (e.g., "Button", "Counter").
         * @param inputContacts An optional vector of input pins.
         * @param outputContacts An optional vector of output pins.
         */
        public function BaseAtom(id:String, pos:Point, name:String, type:String, inputContacts:Vector.<Pin> = null, outputContacts:Vector.<Pin> = null) {
            this.id = id;
            this.position = pos ? pos.clone() : new Point(); // Клонируем Point для безопасности
            this.name = name;
            this.type = type;
            // Клонируем векторы и пины для иммутабельности
            this._inputContacts = inputContacts ? clonePins(inputContacts) : new Vector.<Pin>();
            this._outputContacts = outputContacts ? clonePins(outputContacts) : new Vector.<Pin>();

            // Устанавливаем ссылки на родительский атом для всех пинов
            updatePinsParentAtom();
        }

        /**
         * Creates a new atom instance with an updated position.
         * This method implements the immutable pattern.
         * @param newPosition The new position for the atom.
         * @return A new BaseAtom instance with the updated position.
         */
        public function setPosition(newPosition:Point):BaseAtom {
            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                newPosition ? newPosition.clone() : new Point(), // Клонируем новую позицию
                this.name,
                this.type,
                this._inputContacts, // Используем клоны, созданные в конструкторе
                this._outputContacts
            );
            return newAtom;
        }

        /**
         * Creates a new atom instance with an updated value for a specific input pin.
         * This method implements the immutable pattern.
         * @param pinName The name of the input pin to update.
         * @param newValue The new value for the pin.
         * @return A new BaseAtom instance with the updated input pin, or the same instance if the pin was not found.
         */
        public function setInputPinValue(pinName:String, newValue:*):BaseAtom {
            var pinIndex:int = -1;
            for (var i:int = 0; i < _inputContacts.length; i++) {
                if (_inputContacts[i].name == pinName) {
                    pinIndex = i;
                    break;
                }
            }
            if (pinIndex == -1) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "WARN",
                    source: "BaseAtom",
                    message: "Input pin '" + pinName + "' not found for atom '" + this.name + "' (" + this.id + "). Returning same instance."
                }));
                return this; // Pin not found, return the same instance
            }

            // Создаём копию вектора и обновлённый пин
            var newInputContacts:Vector.<Pin> = this._inputContacts.concat(); // Копируем вектор
            var updatedPin:Pin = _inputContacts[pinIndex].setValue(newValue); // Создаём новый пин
            newInputContacts[pinIndex] = updatedPin;

            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                this.position, // Клонируется в конструкторе
                this.name,
                this.type,
                newInputContacts, // Передаём новый вектор с обновлённым пином
                this._outputContacts // Клонируется в конструкторе
            );
            return newAtom;
        }

        /**
         * Creates a new atom instance with an updated value for a specific output pin.
         * This method implements the immutable pattern.
         * @param pinName The name of the output pin to update.
         * @param newValue The new value for the pin.
         * @return A new BaseAtom instance with the updated output pin, or the same instance if the pin was not found.
         */
        public function setOutputPinValue(pinName:String, newValue:*):BaseAtom {
            var pinIndex:int = -1;
            for (var i:int = 0; i < _outputContacts.length; i++) {
                if (_outputContacts[i].name == pinName) {
                    pinIndex = i;
                    break;
                }
            }
            if (pinIndex == -1) {
                 MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "WARN",
                    source: "BaseAtom",
                    message: "Output pin '" + pinName + "' not found for atom '" + this.name + "' (" + this.id + "). Returning same instance."
                }));
                return this; // Pin not found, return the same instance
            }

            // Создаём копию вектора и обновлённый пин
            var newOutputContacts:Vector.<Pin> = this._outputContacts.concat(); // Копируем вектор
            var updatedPin:Pin = _outputContacts[pinIndex].setValue(newValue); // Создаём новый пин
            newOutputContacts[pinIndex] = updatedPin;

            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                this.position, // Клонируется в конструкторе
                this.name,
                this.type,
                this._inputContacts, // Клонируется в конструкторе
                newOutputContacts // Передаём новый вектор с обновлённым пином
            );
            return newAtom;
        }

        /**
         * Updates the `_parentAtom` reference on all input and output pins of *this* atom instance.
         * This is necessary to maintain the link between pins and their parent atom after creating a new atom instance.
         */
        private function updatePinsParentAtom():void {
            for each (var inputPin:Pin in this._inputContacts) {
                 inputPin.setParentAtom(this); // Используем setter вместо прямого доступа
            }
            for each (var outputPin:Pin in this._outputContacts) {
                 outputPin.setParentAtom(this); // Используем setter вместо прямого доступа
            }
        }

        /**
         * Gets a copy of the vector containing all input pins.
         * @return A copy of the input pins vector.
         */
        public function get inputContacts():Vector.<Pin> {
            return this._inputContacts.concat(); // Return a copy to prevent external modification
        }

        /**
         * Gets a copy of the vector containing all output pins.
         * @return A copy of the output pins vector.
         */
        public function get outputContacts():Vector.<Pin> {
            return this._outputContacts.concat(); // Return a copy to prevent external modification
        }

        /**
         * Gets a combined vector containing all input and output pins.
         * @return A new vector containing all pins.
         */
        public function getAllContacts():Vector.<Pin> {
            var all:Vector.<Pin> = new Vector.<Pin>();
            all = all.concat(this._inputContacts); // Add input pins
            all = all.concat(this._outputContacts); // Add output pins
            return all; // Return the combined vector
        }

        // --- Утилиты ---

        /**
         * Helper function to deeply clone a vector of Pin objects.
         * This ensures immutability of the pins themselves when creating new BaseAtom instances.
         * @param originalPins The original vector of pins.
         * @return A new vector containing cloned pin instances.
         */
        private function clonePins(originalPins:Vector.<Pin>):Vector.<Pin> {
            var clonedPins:Vector.<Pin> = new Vector.<Pin>();
            for each (var originalPin:Pin in originalPins) {
                // Используем setValue(null) как способ клонирования пина с сохранением его состояния
                var clonedPin:Pin = originalPin.setValue(originalPin.value);
                clonedPins.push(clonedPin);
            }
            return clonedPins;
        }
    }
}
 
// File: Src.Prog.Com.Atoms.Core.BaseAtomView.as

package Src.Prog.Com.Atoms.Core {
    import flash.display.MovieClip;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    // import Src.Prog.Core.Managers.AtomManager; // Предполагаем, что AtomManager будет использоваться
    // import Src.Prog.Com.Atoms.Linker.Track; // Предполагаем, что Track будет реализован и использован
    // import Src.Prog.Com.AssetsDomain.AssetManager; // Предполагаем, что AssetManager будет использоваться

    /**
     * Base class for all atom views.
     * Provides common functionality such as drag/drop, bringToFront, and common interactions.
     * Integrates with MultiPulsator for system communication and expects integration
     * with AtomManager and AssetDomain for updates and visuals.
     */
    public class BaseAtomView extends MovieClip implements IAtomView {
        protected var _parentAtom:BaseAtom;
        protected var _isDragging:Boolean = false;
        protected var _dragOffset:Point = new Point();
        protected static const GRID_SIZE:int = 10;
        protected static const SNAP_TO_GRID:Boolean = true;

        /**
         * Constructs the BaseAtomView.
         * Sets up base mouse interactions.
         */
        public function BaseAtomView() {
            super();
            setupBaseInteractions();
        }

        /**
         * Updates the reference to the atom this view represents and refreshes the view.
         * @param newAtom The new atom instance to represent.
         */
        public function updateAtomReference(newAtom:BaseAtom):void {
            if (_parentAtom !== newAtom) {
                _parentAtom = newAtom;
                updateVisuals(); // Update visual representation based on new atom state
                refreshPins(); // Refresh pins based on new atom's contacts
            }
        }

        /**
         * Sets up base mouse event listeners for dragging and bringing the view to the front.
         */
        private function setupBaseInteractions():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onBaseMouseDown);
        }

        /**
         * Handles the base mouse down event.
         * Brings the view to the front and starts dragging if the Ctrl key is pressed.
         */
        private function onBaseMouseDown(event:MouseEvent):void {
            // Always bring to front on click
            if (!_isDragging) {
                bringToFront();
            }

            // Start dragging if Ctrl key is pressed
            if (event.ctrlKey) {
                _isDragging = true;
                _dragOffset.x = event.localX;
                _dragOffset.y = event.localY;
                stage.addEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                onDragStart(new Point(event.localX, event.localY));
                event.stopPropagation();
            }

            // Call specific mouse down handler in child class
            onSpecificMouseDown(event);
        }

        /**
         * Handles the base mouse move event during dragging.
         */
        private function onBaseMouseMove(event:MouseEvent):void {
            if (_isDragging) {
                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);
                var newX:Number = localPos.x - _dragOffset.x;
                var newY:Number = localPos.y - _dragOffset.y;
                if (SNAP_TO_GRID) {
                    newX = Math.round(newX / GRID_SIZE) * GRID_SIZE;
                    newY = Math.round(newY / GRID_SIZE) * GRID_SIZE;
                }
                onDrag(new Point(newX, newY));
            }
        }

        /**
         * Handles the base mouse up event after dragging.
         */
        private function onBaseMouseUp(event:MouseEvent):void {
            if (_isDragging) {
                _isDragging = false;
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);
                var newX:Number = localPos.x - _dragOffset.x;
                var newY:Number = localPos.y - _dragOffset.y;
                if (SNAP_TO_GRID) {
                    newX = Math.round(newX / GRID_SIZE) * GRID_SIZE;
                    newY = Math.round(newY / GRID_SIZE) * GRID_SIZE;
                }
                onDragEnd(new Point(newX, newY));
            }
        }

        /**
         * Updates the tracks connected to this atom during dragging.
         * Placeholder: Requires ConnectionManager or similar service to be implemented.
         * Example integration with MultiPulsator or direct call to Linker domain.
         */
        protected function updateTracksDuringDrag():void {
            // Example: Emit an impulse for the Linker domain to handle
            if (_parentAtom) {
                 MultiPulsator.emit(new Impulse("ATOM_DRAGGING", {
                    atom: _parentAtom,
                    position: new Point(this.x, this.y) // Current visual position during drag
                }));
            }
        }

        /**
         * Brings this atom view to the front of its parent's display list.
         */
        public function bringToFront():void {
            if (this.parent) {
                this.parent.setChildIndex(this, this.parent.numChildren - 1);

                // Also bring pins to front within this view
                for (var i:int = 0; i < this.numChildren; i++) {
                    var child:* = this.getChildAt(i);
                    if (child is Pin) {
                        this.setChildIndex(child, this.numChildren - 1);
                    }
                }
                // Optional: Emit an impulse if other parts of the system need to know
                // MultiPulsator.emit(new Impulse("ATOM_BROUGHT_TO_FRONT", { atomId: _parentAtom?.id }));
            }
        }

        /**
         * Removes any existing pin objects from the display list.
         */
        protected function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * Draws the contact pins. This method should be overridden by child classes.
         * It should create visual Pin instances and add them to this view's display list.
         */
        protected function drawContacts():void {
            // Override in child classes to implement pin drawing
            // Example: Create Pin sprites based on _parentAtom.inputContacts and outputContacts
            // and add them as children to this MovieClip.
        }

        /**
         * Ensures pins are visible and properly positioned by removing and re-adding them.
         */
        public function refreshPins():void {
            if (_parentAtom) {
                // Remove and re-add pins to ensure they're visible and reflect atom state
                removeExistingPins();
                drawContacts();
            }
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Can be overridden in child classes for specific cleanup.
         */
        public function dispose():void {
            // Basic event cleanup
            removeEventListener(MouseEvent.MOUSE_DOWN, onBaseMouseDown);

            // Stop drag if active
            if (_isDragging && stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                _isDragging = false;
            }

            // Remove pins
            removeExistingPins();

            // Clear atom reference
            _parentAtom = null;
        }

        // --- Methods to be implemented by child classes ---

        /**
         * Handles the specific mouse down event for child classes.
         * Override in child classes for specific click behavior.
         */
        protected function onSpecificMouseDown(event:MouseEvent):void {
            // Override in child classes for specific click behavior
        }

        /**
         * Initializes the view with a specific atom.
         * @param atom The atom to initialize the view with.
         */
        public function initWithAtom(atom:BaseAtom):void {
            _parentAtom = atom;
            refreshPins(); // Ensure pins are visible and reflect initial atom state
            updateVisuals(); // Initial visual update
        }

        /**
         * Updates the visual representation of the atom.
         * Override in child classes to implement specific visual updates.
         */
        public function updateVisuals():void {
             // Override in child classes to update visuals based on _parentAtom state
             // e.g., update display based on pin values, name, type, etc.
        }

        /**
         * Handles the start of a drag operation.
         * @param mousePos The mouse position when dragging started.
         */
        public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7; // Visual feedback for dragging
        }

        /**
         * Handles the movement during a drag operation.
         * @param mousePos The current mouse position during dragging.
         */
        public function onDrag(mousePos:Point):void {
            this.x = mousePos.x;
            this.y = mousePos.y;
            updateTracksDuringDrag(); // Notify system about ongoing drag
        }

        /**
         * Handles the end of a drag operation.
         * Updates the atom's position and notifies the system via MultiPulsator.
         * Expects AtomManager or similar service to handle the ATOM_MOVED impulse.
         */
        public function onDragEnd(mousePos:Point):void {
            this.alpha = 1.0; // Reset visual feedback
            if (_parentAtom) {
                var newPosition:Point = new Point(mousePos.x, mousePos.y);
                // Create new atom with updated position using immutable pattern
                var newAtom:BaseAtom = _parentAtom.setPosition(newPosition);

                // Notify the system about the change
                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    oldAtom: _parentAtom,
                    newAtom: newAtom,
                    oldPosition: _parentAtom.position,
                    newPosition: newPosition
                }));

                // The AtomManager (or whoever listens to ATOM_MOVED) should now
                // update its registry and potentially call updateAtomReference(newAtom) on this view.
            }
        }

        /**
         * Handles the completion of an asset load.
         * Override in child classes if specific asset loading logic is needed.
         * @param assetUrl The URL of the loaded asset.
         * @param assetData The loaded asset data.
         */
        public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
             // Override in child classes if needed
             // e.g., apply loaded asset to a display object
        }

        /**
         * Handles an error during asset loading.
         * Override in child classes if specific asset loading error logic is needed.
         * @param assetUrl The URL of the asset that failed to load.
         * @param errorMessage The error message describing the failure.
         */
        public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
             // Override in child classes if needed
             // e.g., show error state visually
        }

        /**
         * Gets the atom this view represents.
         * @return The parent atom.
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }
    }
}
 
package Application.AtomICLinker.View {
    import flash.display.MovieClip;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Application.AtomICLinker.View.Pin;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.AtomManager;
    import Application.Managers.ConnectionManager;
    import Application.AtomICLinker.View.Track;
    import Application.AtomICCore.Atom.BaseAtom;

    /**
     * Base class for all atom views.
     * Provides common functionality such as drag/drop, bringToFront, and common interactions.
     */
    public class BaseEditAtomView extends MovieClip implements IAtomView {
        protected var _parentAtom:BaseAtom;
        protected var _isDragging:Boolean = false;
        protected var _dragOffset:Point = new Point();
        protected static const GRID_SIZE:int = 10;
        protected static const SNAP_TO_GRID:Boolean = true;

        /**
         * Constructs the BaseAtomView.
         * Sets up base mouse interactions.
         */
        public function BaseEditAtomView() {
            super();
            setupBaseInteractions();
        }

        /**
         * Updates the reference to the atom this view represents and refreshes the view.
         * @param newAtom The new atom instance to represent.
         */
        public function updateAtomReference(newAtom:BaseAtom):void {
            if (_parentAtom !== newAtom) {
                _parentAtom = newAtom;
                updateVisuals(); // Update visual representation
            }
        }

        /**
         * Sets up base mouse event listeners for dragging and bringing the view to the front.
         */
        private function setupBaseInteractions():void {
            this.buttonMode = true;
            this.useHandCursor = true;
            this.addEventListener(MouseEvent.MOUSE_DOWN, onBaseMouseDown);
        }

        /**
         * Handles the base mouse down event.
         * Brings the view to the front and starts dragging if the Ctrl key is pressed.
         */
        private function onBaseMouseDown(event:MouseEvent):void {
            // Always bring to front on click
            if (!_isDragging) {
                bringToFront();
            }

            // Start dragging if Ctrl key is pressed
            if (event.ctrlKey) {
                _isDragging = true;
                _dragOffset.x = event.localX;
                _dragOffset.y = event.localY;
                stage.addEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                onDragStart(new Point(event.localX, event.localY));
                event.stopPropagation();
            }

            // Call specific mouse down handler in child class
            onSpecificMouseDown(event);
        }

        /**
         * Handles the base mouse move event during dragging.
         */
        private function onBaseMouseMove(event:MouseEvent):void {
            if (_isDragging) {
                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);
                var newX:Number = localPos.x - _dragOffset.x;
                var newY:Number = localPos.y - _dragOffset.y;
                if (SNAP_TO_GRID) {
                    newX = Math.round(newX / GRID_SIZE) * GRID_SIZE;
                    newY = Math.round(newY / GRID_SIZE) * GRID_SIZE;
                }
                onDrag(new Point(newX, newY));
            }
        }

        /**
         * Handles the base mouse up event after dragging.
         */
        private function onBaseMouseUp(event:MouseEvent):void {
            if (_isDragging) {
                _isDragging = false;
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                var globalPos:Point = new Point(event.stageX, event.stageY);
                var localPos:Point = parent.globalToLocal(globalPos);
                var newX:Number = localPos.x - _dragOffset.x;
                var newY:Number = localPos.y - _dragOffset.y;
                if (SNAP_TO_GRID) {
                    newX = Math.round(newX / GRID_SIZE) * GRID_SIZE;
                    newY = Math.round(newY / GRID_SIZE) * GRID_SIZE;
                }
                onDragEnd(new Point(newX, newY));
            }
        }

        /**
         * Updates the tracks connected to this atom during dragging.
         */
        protected function updateTracksDuringDrag():void {
            var connectionManager:ConnectionManager = ConnectionManager.getInstance();
            if (!connectionManager) return;
            var tracks:Array = connectionManager.getTracksByAtom(_parentAtom);
            for each (var track:Track in tracks) {
                track.update();
            }
            if (stage) {
                stage.invalidate();
            }
        }

        /**
         * Brings this atom view to the front of its parent's display list.
         */
        public function bringToFront():void {
            if (this.parent) {
                this.parent.setChildIndex(this, this.parent.numChildren - 1);

                // Also bring pins to front within this view
                for (var i:int = 0; i < this.numChildren; i++) {
                    var child:* = this.getChildAt(i);
                    if (child is Pin) {
                        this.setChildIndex(child, this.numChildren - 1);
                    }
                }

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "BaseAtomView",
                    message: "Atom brought to front: " + (_parentAtom ? _parentAtom.name : "Unknown")
                }));
            }
        }

        /**
         * Removes any existing pin objects from the display list.
         */
        protected function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * Draws the contact pins. This method should be overridden by child classes.
         */
        protected function drawContacts():void {
            // Override in child classes to implement pin drawing
        }

        /**
         * Ensures pins are visible and properly positioned by removing and re-adding them.
         */
        public function refreshPins():void {
            if (_parentAtom) {
                // Remove and re-add pins to ensure they're visible
                removeExistingPins();
                drawContacts();

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "BaseAtomView",
                    message: "Pins refreshed for: " + (_parentAtom ? _parentAtom.name : "Unknown")
                }));
            }
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Can be overridden in child classes for specific cleanup.
         */
        public function dispose():void {
            // Basic event cleanup
            removeEventListener(MouseEvent.MOUSE_DOWN, onBaseMouseDown);

            // Stop drag if active
            if (_isDragging && stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBaseMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onBaseMouseUp);
                _isDragging = false;
            }

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "DEBUG",
                source: "BaseAtomView",
                message: "BaseAtomView disposed: " + (_parentAtom ? _parentAtom.name : "Unknown")
            }));
        }

        // --- Abstract methods to be implemented by child classes ---

        /**
         * Handles the disconnection of a pin.
         * @param pinName The name of the pin that was disconnected.
         */
        protected function handlePinDisconnection(pinName:String):void {
            if (_parentAtom) {
                // Find pin and reset its value
                for each(var inputPin:Pin in _parentAtom.inputContacts) {
                    if (inputPin.name == pinName) {
                        var newAtom:BaseAtom = _parentAtom.setInputPinValue(pinName, null);
                        updateAtomReference(newAtom);
                        break;
                    }
                }
            }
        }

        /**
         * Handles the specific mouse down event for child classes.
         * Override in child classes for specific click behavior.
         */
        protected function onSpecificMouseDown(event:MouseEvent):void {
            // Override in child classes for specific click behavior
        }

        /**
         * Initializes the view with a specific atom.
         * @param atom The atom to initialize the view with.
         */
        public function initWithAtom(atom:BaseAtom):void {
            _parentAtom = atom;
            refreshPins(); // Ensure pins are visible
        }

        /**
         * Updates the visual representation of the atom.
         * Override in child classes to implement specific visual updates.
         */
        public function updateVisuals():void { }

        /**
         * Handles the start of a drag operation.
         * @param mousePos The mouse position when dragging started.
         */
        public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7;
        }

        /**
         * Handles the movement during a drag operation.
         * @param mousePos The current mouse position during dragging.
         */
        public function onDrag(mousePos:Point):void {
            this.x = mousePos.x;
            this.y = mousePos.y;
            updateTracksDuringDrag();
        }

        /**
         * Handles the end of a drag operation.
         * @param mousePos The mouse position when dragging ended.
         */
        public function onDragEnd(mousePos:Point):void {
            this.alpha = 1.0;
            if (_parentAtom) {
                var newPosition:Point = new Point(mousePos.x, mousePos.y);
                var newAtom:BaseAtom = _parentAtom.setPosition(newPosition);
                var atomManager:AtomManager = AtomManager.getInstance();
                if (atomManager) {
                    atomManager.updateAtom(newAtom);
                }
                MultiPulsator.emit(new Impulse("ATOM_UPDATED", {
                    oldAtom: _parentAtom,
                    newAtom: newAtom
                }));
                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    atom: newAtom,
                    oldPosition: _parentAtom.position,
                    newPosition: newPosition
                }));
            }
        }

        /**
         * Handles the completion of an asset load.
         * @param assetUrl The URL of the loaded asset.
         * @param assetData The loaded asset data.
         */
        public function onAssetLoadComplete(assetUrl:String, assetData:*):void { }

        /**
         * Handles an error during asset loading.
         * @param assetUrl The URL of the asset that failed to load.
         * @param errorMessage The error message describing the failure.
         */
        public function onAssetLoadError(assetUrl:String, errorMessage:String):void { }

        /**
         * Gets the atom this view represents.
         * @return The parent atom.
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }
    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    // import Src.Prog.Core.Managers.AtomManager; // Предполагаем, что AtomManager может использоваться для симуляции
    // import Src.Prog.Com.AssetsDomain.AssetManager; // Предполагаем, что AssetManager будет использоваться для ассетов в Device

    /**
     * Base class for atom views in a device/simulation context (e.g., Device window).
     * Extends BaseAtomView to provide specific behavior for simulation scenarios,
     * such as reacting to input/output changes and displaying current state.
     * Integrates with MultiPulsator for system communication and expects integration
     * with AtomManager (or SimulationManager) and AssetDomain for updates and visuals.
     * This view focuses on simulation behavior and output display (e.g., button press, display updates).
     */
    public class DeviceAtomView extends BaseAtomView { // Наследуемся от BaseAtomView

        /**
         * Constructs the DeviceAtomView.
         * Sets up base interactions and potentially subscribes to simulation-specific impulses.
         */
        public function DeviceAtomView() {
            super(); // Вызываем конструктор родителя
            // Настройка специфичного для Device поведения
            setupDeviceInteractions();
            // subscribeToSimulationImpulses(); // Пример: слушать импульсы симуляции
        }

        /**
         * Sets up mouse interactions for the device view.
         * Adds listeners for mouse down and up events if the view is interactive.
         * Override if specific interaction logic is needed.
         */
        protected function setupDeviceInteractions():void {
            // Пример: разрешить взаимодействие для "кнопок"
            // if (_parentAtom.type === "Button" || _parentAtom.type === "PushButton") {
                this.buttonMode = true;
                this.addEventListener(MouseEvent.MOUSE_DOWN, onDeviceInteraction);
                this.addEventListener(MouseEvent.MOUSE_UP, onDeviceRelease);
            // }
        }

        /**
         * Handles the mouse down interaction event in the device context.
         * Emits an impulse to signal the interaction (e.g., button press).
         */
        protected function onDeviceInteraction(event:MouseEvent):void {
            // Пример: эмит импульса для симуляции
            if (_parentAtom) {
                MultiPulsator.emit(new Impulse("DEVICE_ATOM_INTERACTION", {
                    atom: _parentAtom,
                    interactionType: "button_press",
                    source: "device_window",
                    view: this
                }));
            }
            // Не вызываем базовый onBaseMouseDown, так как поведение перетаскивания не нужно в Device
            event.stopPropagation(); // Останавливаем всплытие, если нужно
        }

        /**
         * Handles the mouse up interaction event in the device context.
         * Emits an impulse to signal the release (e.g., button release).
         */
        protected function onDeviceRelease(event:MouseEvent):void {
            // Пример: эмит импульса для симуляции
            if (_parentAtom) {
                MultiPulsator.emit(new Impulse("DEVICE_ATOM_INTERACTION", {
                    atom: _parentAtom,
                    interactionType: "button_release",
                    source: "device_window",
                    view: this
                }));
            }
            event.stopPropagation(); // Останавливаем всплытие, если нужно
        }

        // --- Переопределение методов BaseAtomView для Device ---

        /**
         * Handles the end of a drag operation in the device context.
         * Override to prevent dragging in the Device window.
         */
        override public function onDragEnd(mousePos:Point):void {
            // Не меняем позицию атома в Device
            this.alpha = 1.0; // Сбрасываем визуальный эффект
            // Можно эмитить импульс, если попытка перетаскивания в Device значима
            // MultiPulsator.emit(new Impulse("DEVICE_ATOM_DRAG_ATTEMPT", { atom: _parentAtom }));
        }

        /**
         * Handles the specific mouse down event for child classes in the device.
         * Override in child classes for specific click behavior (e.g., triggering simulation).
         * This is called by onBaseMouseDown, which we might not trigger in Device,
         * so onDeviceInteraction is the primary handler.
         */
        override protected function onSpecificMouseDown(event:flash.events.MouseEvent):void {
            // Для Device, возможно, не используется, так как onDeviceInteraction переопределяет базовое поведение.
            // Или может использоваться для других типов взаимодействий.
        }

        /**
         * Updates the visual representation of the atom in the device.
         * Override in child classes to implement specific visual updates based on atom state (e.g., display value).
         */
        override public function updateVisuals():void {
             // Override in child classes to update visuals based on _parentAtom state in device
             // e.g., update display text, button color based on output pin value, etc.
             super.updateVisuals(); // Вызываем базовое обновление, если нужно
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Removes device-specific subscriptions.
         */
        override public function dispose():void {
            // Отписка от специфичных для Device импульсов
            // MultiPulsator.removeImpulse("SOME_DEVICE_IMPULSE", handler);
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onDeviceInteraction);
            this.removeEventListener(MouseEvent.MOUSE_UP, onDeviceRelease);
            super.dispose(); // Вызываем базовую очистку
        }
    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    // import Src.Prog.Core.Managers.AtomManager; // Предполагаем, что AtomManager будет использоваться
    // import Src.Prog.Com.Atoms.Linker.Track; // Предполагаем, что Track будет реализован и использован

    /**
     * Base class for atom views in an editing context (e.g., Editor window).
     * Extends BaseAtomView to provide specific behavior for editing scenarios,
     * such as dragging, pin interaction, and potential property modification.
     * Integrates with MultiPulsator for system communication and expects integration
     * with AtomManager and AssetDomain for updates and visuals.
     * This view focuses on editability (positioning, connections).
     */
    public class EditorAtomView extends BaseAtomView { // Наследуемся от BaseAtomView

        // Режимы взаимодействия, если потребуется
        // protected static const MODE_DEFAULT:String = "default";
        // protected static const MODE_CONNECTING:String = "connecting";

        /**
         * Constructs the EditorAtomView.
         * Sets up base mouse interactions (inherited from BaseAtomView).
         */
        public function EditorAtomView() {
            super(); // Вызываем конструктор родителя
            // Можно добавить специфичные для редактора настройки здесь,
            // например, изменение курсора или начального состояния.
        }

        // --- Переопределение методов BaseAtomView для редактора ---

        /**
         * Handles the base mouse down event in the editor context.
         * Brings the view to the front and starts dragging if the Ctrl key is pressed.
         * Can be overridden for more specific editor behaviors (e.g., selecting multiple atoms).
         */
        override protected function onBaseMouseDown(event:flash.events.MouseEvent):void {
            // Вызов родительской реализации для базового поведения (всплытие, перетаскивание с Ctrl)
            super.onBaseMouseDown(event);

            // Можно добавить специфичное поведение для редактора здесь,
            // например, обработка кликов без Ctrl (для выделения, открытия настроек и т.д.)
            // if (!event.ctrlKey) {
            //     MultiPulsator.emit(new Impulse("ATOM_SELECTED", { atom: _parentAtom, view: this }));
            // }
        }

        /**
         * Handles the end of a drag operation in the editor.
         * Updates the atom's position via MultiPulsator, expecting AtomManager to handle the update.
         * This is where the immutable pattern is crucial: we create a *new* atom with the new position.
         */
        override public function onDragEnd(mousePos:Point):void {
            this.alpha = 1.0; // Сброс визуальной обратной связи
            if (_parentAtom) {
                var newPosition:Point = new Point(mousePos.x, mousePos.y);
                // Создаём новый атом с обновлённой позицией, используя иммутабельный паттерн
                var newAtom:BaseAtom = _parentAtom.setPosition(newPosition);

                // Уведомляем систему об изменении через MultiPulsator
                // Предполагается, что AtomManager или другой слушатель обработает этот импульс,
                // обновит свою внутреннюю базу данных и, возможно, вызовет updateAtomReference на этом view.
                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    oldAtom: _parentAtom,
                    newAtom: newAtom,
                    oldPosition: _parentAtom.position,
                    newPosition: newPosition
                }));

                // *Не* вызываем AtomManager.updateAtom(newAtom) напрямую здесь,
                // чтобы сохранить слабую связанность через MultiPulsator.
                // AtomManager (или эквивалент) должен слушать "ATOM_MOVED".
            }
        }

        /**
         * Updates the tracks connected to this atom during dragging in the editor.
         * Placeholder: Requires Linker domain (e.g., ConnectionManager, Track) to be implemented.
         * Example integration with MultiPulsator or direct call to Linker service.
         */
        override protected function updateTracksDuringDrag():void {
            // Пример: отправка импульса для домена Linker
            if (_parentAtom) {
                 MultiPulsator.emit(new Impulse("ATOM_DRAGGING", {
                    atom: _parentAtom,
                    position: new Point(this.x, this.y), // Текущая визуальная позиция во время перетаскивания
                    view: this // Возможно, передать и сам view, если нужно
                }));
            }
            // В будущем, Linker домен может слушать "ATOM_DRAGGING" и обновлять позиции Track'ов.
        }

        // --- Методы для переопределения дочерними классами (если нужно) ---

        /**
         * Handles the specific mouse down event for child classes in the editor.
         * Override in child classes for specific click behavior (e.g., opening properties).
         */
        override protected function onSpecificMouseDown(event:flash.events.MouseEvent):void {
            // Override in child classes for specific click behavior in editor
            // Например, MultiPulsator.emit(new Impulse("ATOM_EDIT_REQUEST", { atom: _parentAtom }));
        }

        /**
         * Updates the visual representation of the atom in the editor.
         * Override in child classes to implement specific visual updates based on atom state.
         */
        override public function updateVisuals():void {
             // Override in child classes to update visuals based on _parentAtom state in editor
             // e.g., update display based on pin values, name, type, selection state, etc.
             super.updateVisuals(); // Вызываем базовое обновление, если нужно
        }

        /**
         * Handles the start of a drag operation.
         * @param mousePos The mouse position when dragging started.
         */
        override public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7; // Визуальная обратная связь для перетаскивания
            super.onDragStart(mousePos); // Вызываем базовую логику, если нужно
        }

        /**
         * Handles the movement during a drag operation.
         * @param mousePos The current mouse position during dragging.
         */
        override public function onDrag(mousePos:Point):void {
            super.onDrag(mousePos); // Обновляем позицию (this.x, this.y) и вызываем updateTracksDuringDrag
        }

        /**
         * Brings this atom view to the front of its parent's display list.
         */
        override public function bringToFront():void {
            super.bringToFront(); // Вызываем базовую логику
            // Можно добавить специфичную для редактора логику, например, сброс выделения с других
        }

        /**
         * Ensures pins are visible and properly positioned by removing and re-adding them.
         */
        override public function refreshPins():void {
            super.refreshPins(); // Вызываем базовую логику
            // Можно добавить специфичную для редактора логику, например, обновление стиля пинов
        }

        /**
         * Updates the reference to the atom this view represents and refreshes the view.
         * @param newAtom The new atom instance to represent.
         */
        override public function updateAtomReference(newAtom:BaseAtom):void {
            super.updateAtomReference(newAtom); // Вызываем базовую логику
            // Можно добавить специфичную для редактора логику, например, обновление стиля в зависимости от состояния
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Can be overridden in child classes for specific cleanup.
         */
        override public function dispose():void {
            // Можно добавить специфичную для редактора очистку
            super.dispose(); // Вызываем базовую очистку
        }

    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;

    /**
     * IAtomView interface - contract for atom visual representations.
     * Defines the methods that all atom view classes must implement.
     */
    public interface IAtomView {
        /**
         * Initialize the view with a specific atom.
         * @param atom - The BaseAtom instance this view represents.
         */
        function initWithAtom(atom:BaseAtom):void;

        /**
         * Handle the completion of an asset load.
         * @param assetUrl - The URL of the loaded asset.
         * @param assetData - The loaded asset data.
         */
        function onAssetLoadComplete(assetUrl:String, assetData:*):void;

        /**
         * Handle an error during asset loading.
         * @param assetUrl - The URL of the asset that failed to load.
         * @param errorMessage - The error message describing the failure.
         */
        function onAssetLoadError(assetUrl:String, errorMessage:String):void;

        /**
         * Update the visual representation of the atom based on its current state.
         */
        function updateVisuals():void;

        /**
         * Bring this atom view to the front of its parent's display list.
         */
        function bringToFront():void;

        /**
         * Handle the start of a drag operation.
         * @param mousePos - The mouse position when dragging started.
         */
        function onDragStart(mousePos:Point):void;

        /**
         * Handle the movement during a drag operation.
         * @param mousePos - The current mouse position during dragging.
         */
        function onDrag(mousePos:Point):void;

        /**
         * Handle the end of a drag operation.
         * @param mousePos - The mouse position when dragging ended.
         */
        function onDragEnd(mousePos:Point):void;

        /**
         * Get the BaseAtom instance this view represents.
         * @return BaseAtom - The associated atom instance.
         */
        function get parentAtom():BaseAtom;
    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.display.DisplayObject;
    import flash.events.MouseEvent;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;

    /**
     * Pin - Connection point for atoms with impulse-based interaction system.
     * Represents input/output contacts and handles connection creation through direct mouse interactions.
     * Now includes temporary track visualization during connection creation.
     */
    public class Pin extends Sprite {
        /** Pin type constants */
        public static const TYPE_INPUT:String = "In";
        public static const TYPE_OUTPUT:String = "Out";

        /** Pin properties */
        private var _pinName:String;
        private var _pinType:String;
        private var _parentAtom:BaseAtom;
        private var _value:* = null;

        /** Connection creation state */
        private var _isConnecting:Boolean = false;
        private var _tempTrack:Sprite;
        private var _currentWindowType:String;

        /**
         * Pin constructor
         * @param name Unique name of the pin within its parent atom
         * @param type Type of the pin (TYPE_INPUT or TYPE_OUTPUT)
         * @param parentAtom Reference to the atom this pin belongs to
         * @param value Optional initial value for the pin
         */
        public function Pin(name:String, type:String, parentAtom:BaseAtom, value:* = null) {
            if (type != Pin.TYPE_INPUT && type != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("Invalid pin type: " + type + ". Use Pin.TYPE_INPUT or Pin.TYPE_OUTPUT.");
            }

            this._pinName = name;
            this._pinType = type;
            this._parentAtom = parentAtom;
            this._value = value;

            setupPinVisual();
            setupMouseInteractions();
            _currentWindowType = getCurrentWindowType();
        }

        /**
         * Setup pin visual representation
         */
        private function setupPinVisual():void {
            this.graphics.clear();

            // Different colors for input/output pins
            var color:uint = (_pinType == TYPE_INPUT) ? 0xFF4444 : 0x44FF44;

            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 6);
            this.graphics.endFill();

            // Add subtle border
            this.graphics.lineStyle(1, 0x000000, 0.3);
            this.graphics.drawCircle(0, 0, 6);

            this.buttonMode = true;
            this.mouseChildren = false;
        }

        /**
         * Setup direct mouse event listeners for connection creation
         */
        private function setupMouseInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            this.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        }

        /**
         * Handle mouse down event - start connection creation for output pins
         */
        private function onMouseDown(event:MouseEvent):void {
            if (_pinType == TYPE_OUTPUT) {
                startConnectionCreation();
                event.stopPropagation(); // Prevent atom drag when connecting
            }
        }

        /**
         * Handle mouse over - visual feedback
         */
        private function onMouseOver(event:MouseEvent):void {
            this.scaleX = this.scaleY = 1.2;
        }

        /**
         * Handle mouse out - restore visual state
         */
        private function onMouseOut(event:MouseEvent):void {
            this.scaleX = this.scaleY = 1.0;
        }

        /**
         * Start the connection creation process
         */
        private function startConnectionCreation():void {
            _isConnecting = true;

            // Create temporary track
            createTempTrack();

            // Subscribe to stage events for tracking mouse
            if (stage) {
                stage.addEventListener(MouseEvent.MOUSE_MOVE, onStageMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, onStageMouseUp);
            }

            // Visual feedback
            this.alpha = 0.7;

            trace("Pin: Started connection creation from " + this.getFullName());
        }

        /**
         * Create temporary track visualization
         */
        private function createTempTrack():void {
            _tempTrack = new Sprite();

            // Add to the overlay layer of current window
            var window:Window = findParentWindow();
            if (window && window.overlayLayer) {
                window.overlayLayer.addChild(_tempTrack);
                trace("Temp track created and added to overlay layer");
            } else {
                trace("ERROR: Could not find window or overlay layer");
            }

            updateTempTrack(stage.mouseX, stage.mouseY);
        }

        /**
         * Update temporary track during mouse movement
         */
        private function updateTempTrack(mouseX:Number, mouseY:Number):void {
            if (!_tempTrack) return;

            // Get the pin position in global coordinates
            var startPos:Point = this.localToGlobal(new Point(0, 0));

            // Convert to overlay layer coordinates
            var overlayLayer:Sprite = _tempTrack.parent as Sprite;
            if (!overlayLayer) return;

            var localStart:Point = overlayLayer.globalToLocal(startPos);
            var localEnd:Point = overlayLayer.globalToLocal(new Point(mouseX, mouseY));

            _tempTrack.graphics.clear();
            _tempTrack.graphics.lineStyle(3, 0xFF0000, 0.8); // Красная толстая линия для отладки
            _tempTrack.graphics.moveTo(localStart.x, localStart.y);
            _tempTrack.graphics.lineTo(localEnd.x, localEnd.y);

            trace("Temp track updated: " + localStart + " -> " + localEnd);
        }

        /**
         * Handle mouse movement during connection creation
         */
        private function onStageMouseMove(event:MouseEvent):void {
            if (_isConnecting && _tempTrack) {
                updateTempTrack(event.stageX, event.stageY);

                // Visual feedback for potential target pins
                updatePotentialTargetHighlight(event.stageX, event.stageY);
            }
        }

        /**
         * Handle mouse up - complete or cancel connection creation
         */
        private function onStageMouseUp(event:MouseEvent):void {
            if (_isConnecting) {
                var targetPin:Pin = findPinUnderMouse(event.stageX, event.stageY);

                if (targetPin && isValidConnectionTarget(targetPin)) {
                    completeConnection(targetPin);
                } else {
                    cancelConnection();
                }

                cleanupConnectionState();
            }
        }

        /**
         * Find pin under mouse coordinates
         */
        private function findPinUnderMouse(stageX:Number, stageY:Number):Pin {
            var objects:Array = stage.getObjectsUnderPoint(new Point(stageX, stageY));

            for (var i:int = objects.length - 1; i >= 0; i--) {
                var obj:DisplayObject = objects[i] as DisplayObject;
                var pin:Pin = findPinInHierarchy(obj);

                if (pin && pin != this) {
                    trace("Found potential target pin: " + pin.getFullName());
                    return pin;
                }
            }

            return null;
        }

        /**
         * Find Pin in display object hierarchy
         */
        private function findPinInHierarchy(obj:DisplayObject):Pin {
            while (obj && !(obj is Pin) && obj.parent) {
                obj = obj.parent;
            }
            return obj as Pin;
        }

        /**
         * Check if target pin is valid for connection
         */
        private function isValidConnectionTarget(targetPin:Pin):Boolean {
            if (!targetPin) return false;

            var isValid:Boolean = targetPin.pinType == TYPE_INPUT &&
                   targetPin.parentAtom != this.parentAtom &&
                   !isAlreadyConnected(targetPin);

            trace("Connection validation: " + this.getFullName() + " -> " + targetPin.getFullName() + " = " + isValid);
            return isValid;
        }

        /**
         * Check if already connected to target pin
         */
        private function isAlreadyConnected(targetPin:Pin):Boolean {
            // This would check existing connections - to be implemented with TrackRegistry
            return false;
        }

        /**
         * Complete connection to target pin
         */
        private function completeConnection(targetPin:Pin):void {
            trace("Pin: Creating connection from " + this.getFullName() + " to " + targetPin.getFullName());

            // Emit impulse for track creation
            MultiPulsator.emit(new Impulse("TRACK_CREATION_REQUEST", {
                fromPin: this,
                toPin: targetPin,
                windowType: _currentWindowType
            }));
        }

        /**
         * Cancel connection creation
         */
        private function cancelConnection():void {
            trace("Pin: Connection creation cancelled");
        }

        /**
         * Update visual feedback for potential target pins
         */
        private function updatePotentialTargetHighlight(stageX:Number, stageY:Number):void {
            var targetPin:Pin = findPinUnderMouse(stageX, stageY);

            // Reset all pins highlight
            // In a complete implementation, you'd track and reset previous highlights

            if (targetPin && isValidConnectionTarget(targetPin)) {
                targetPin.scaleX = targetPin.scaleY = 1.3;
                targetPin.alpha = 0.9;
            }
        }

        /**
         * Clean up connection creation state
         */
        private function cleanupConnectionState():void {
            _isConnecting = false;

            // Remove temporary track
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
                _tempTrack = null;
                trace("Temp track removed");
            }

            // Remove stage listeners
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onStageMouseMove);
                stage.removeEventListener(MouseEvent.MOUSE_UP, onStageMouseUp);
            }

            // Restore visual state
            this.alpha = 1.0;
            this.scaleX = this.scaleY = 1.0;
        }

        /**
         * Find parent window in hierarchy
         */
        private function findParentWindow():Window {
            var parent:DisplayObject = this.parent;
            while (parent) {
                if (parent is Window) {
                    return parent as Window;
                }
                parent = parent.parent;
            }
            return null;
        }

        /**
         * Get current window type through parent hierarchy
         * @return Current window type or "unknown"
         */
        private function getCurrentWindowType():String {
            var window:Window = findParentWindow();
            return window ? window.windowType : "unknown";
        }

        /**
         * Create new pin instance with updated value (immutable pattern)
         * @param newValue New value for the pin
         * @return New Pin instance with updated value
         */
        public function setValue(newValue:*):Pin {
            var newPin:Pin = new Pin(_pinName, _pinType, _parentAtom, newValue);

            // Copy visual properties
            newPin.x = this.x;
            newPin.y = this.y;
            newPin.alpha = this.alpha;
            newPin.scaleX = this.scaleX;
            newPin.scaleY = this.scaleY;

            return newPin;
        }

        /**
         * Sets the parent atom for this pin.
         * @param parentAtom The parent atom to set
         */
        public function setParentAtom(parentAtom:BaseAtom):void {
            _parentAtom = parentAtom;
        }

        /**
         * Emit value change impulse to notify connected tracks
         * @param newValue New value to emit
         */
        public function emitValueChange(newValue:*):void {
            _value = newValue;

            MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED_" + _parentAtom.id + "_" + _pinName, {
                pin: this,
                value: newValue,
                atomId: _parentAtom.id,
                pinName: _pinName
            }));

            // Also emit general pin value change for global listeners
            MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
                pin: this,
                value: newValue,
                atomId: _parentAtom.id,
                pinName: _pinName
            }));
        }

        /**
         * Handle input value change from connected track
         * @param newValue New input value
         */
        public function handleInputChange(newValue:*):void {
            _value = newValue;

            // Notify parent atom about input change
            if (_parentAtom) {
                MultiPulsator.emit(new Impulse("ATOM_INPUT_CHANGED", {
                    atom: _parentAtom,
                    pin: this,
                    value: newValue
                }));
            }
        }

        /**
         * Clean up pin resources
         */
        public function dispose():void {
            // Remove mouse listeners
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            this.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);

            // Clean up connection state if active
            if (_isConnecting) {
                cleanupConnectionState();
            }

            this.graphics.clear();
            _parentAtom = null;
        }

        // =========================================================================
        // PUBLIC GETTERS
        // =========================================================================

        /**
         * Get pin name
         * @return Pin name
         */
        public function get pinName():String {
            return _pinName;
        }

        /**
         * Get pin type
         * @return Pin type (TYPE_INPUT or TYPE_OUTPUT)
         */
        public function get pinType():String {
            return _pinType;
        }

        /**
         * Get parent atom
         * @return Parent BaseAtom instance
         */
        public function get parentAtom():BaseAtom {
            return _parentAtom;
        }

        /**
         * Get current pin value
         * @return Current pin value
         */
        public function get value():* {
            return _value;
        }

        /**
         * Check if pin has active value
         * @return True if pin has non-null value
         */
        public function get isActive():Boolean {
            return _value !== null && _value !== undefined;
        }

        /**
         * Get string representation for debugging
         * @return String representation of pin
         */
        public function toStringRepresentation():String {
            var atomName:String = _parentAtom ? _parentAtom.name : "UnknownAtom";
            return "Pin(" + atomName + "." + _pinName + ":" + _pinType + ")";
        }

        /**
         * Get full pin identifier
         * @return Full pin identifier string
         */
        public function getFullName():String {
            var parentName:String = _parentAtom ? _parentAtom.name : "UnknownAtom";
            return parentName + "." + _pinName;
        }
    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.utils.setTimeout;

    /**
     * Track - Visual and logical connection between two pins.
     * Handles data flow between output and input pins with automatic updates.
     */
    public class Track extends Sprite {
        /** Connected pins */
        private var _fromPin:Pin;
        private var _toPin:Pin;

        /** Track properties */
        private var _connectionId:String;
        private var _isActive:Boolean = false;

        /**
         * Track constructor
         * @param fromPin Source pin (output)
         * @param toPin Target pin (input)
         */
        public function Track(fromPin:Pin, toPin:Pin) {
            if (fromPin.pinType != Pin.TYPE_OUTPUT) {
                throw new ArgumentError("From pin must be OUTPUT type");
            }
            if (toPin.pinType != Pin.TYPE_INPUT) {
                throw new ArgumentError("To pin must be INPUT type");
            }

            _fromPin = fromPin;
            _toPin = toPin;
            _connectionId = generateConnectionId();

            drawTrack();
            setupImpulseListeners();
        }

        /**
         * Generate unique connection identifier
         * @return Unique connection ID string
         */
        private function generateConnectionId():String {
            return "track_" + _fromPin.parentAtom.id + "_" + _fromPin.pinName +
                   "_to_" + _toPin.parentAtom.id + "_" + _toPin.pinName;
        }

        /**
         * Setup impulse listeners for track functionality
         */
        private function setupImpulseListeners():void {
            // Listen for atom movements to update visual
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);

            // Listen for source pin value changes
            var sourceImpulseKey:String = "PIN_VALUE_CHANGED_" + _fromPin.parentAtom.id + "_" + _fromPin.pinName;
            MultiPulsator.subscribeToImpulse(sourceImpulseKey, onSourceValueChanged);

            // Listen for track-specific impulses
            MultiPulsator.subscribeToImpulse("TRACK_UPDATE_REQUEST", onTrackUpdateRequest);
        }

        /**
         * Create logical connection between pins
         */
        public function createLogicalConnection():void {
            _isActive = true;

            // Initial value transfer
            if (_fromPin.value !== null) {
                transferValue(_fromPin.value);
            }

            MultiPulsator.emit(new Impulse("TRACK_CONNECTED", {
                track: this,
                fromPin: _fromPin,
                toPin: _toPin,
                connectionId: _connectionId
            }));
        }

        /**
         * Handle atom movement to update track visual
         * @param impulse ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:BaseAtom = impulse.data.newAtom;
            if (movedAtom.id == _fromPin.parentAtom.id || movedAtom.id == _toPin.parentAtom.id) {
                drawTrack();

                MultiPulsator.emit(new Impulse("TRACK_UPDATED", {
                    track: this,
                    reason: "atom_moved"
                }));
            }
        }

        /**
         * Handle source pin value changes
         * @param impulse PIN_VALUE_CHANGED impulse
         */
        private function onSourceValueChanged(impulse:Impulse):void {
            var newValue:* = impulse.data.value;
            transferValue(newValue);

            // Visual feedback for active data transfer
            showDataFlowFeedback();
        }

        /**
         * Handle track update requests
         * @param impulse TRACK_UPDATE_REQUEST impulse
         */
        private function onTrackUpdateRequest(impulse:Impulse):void {
            if (impulse.data.track == this || impulse.data.connectionId == _connectionId) {
                drawTrack();
            }
        }

        /**
         * Transfer value from source to target pin
         * @param value Value to transfer
         */
        private function transferValue(value:*):void {
            // Emit input change to target pin
            MultiPulsator.emit(new Impulse("PIN_INPUT_CHANGE_" + _toPin.parentAtom.id + "_" + _toPin.pinName, {
                value: value,
                sourceTrack: this,
                sourcePin: _fromPin
            }));

            // Also update the pin directly for immediate feedback
            _toPin.handleInputChange(value);
        }

        /**
         * Show visual feedback for data flow
         */
        private function showDataFlowFeedback():void {
            // Temporary visual effect for data flow
            this.alpha = 1.0;

            // You could add more sophisticated animations here
            // For now, just reset alpha after short delay
            setTimeout(function():void {
                if (parent) { // Check if still in display list
                    alpha = 0.7;
                }
            }, 200);
        }

        /**
         * Draw or update track visual representation
         */
        public function drawTrack():void {
            this.graphics.clear();

            var fromPos:Point = getGlobalPinPosition(_fromPin);
            var toPos:Point = getGlobalPinPosition(_toPin);

            // Convert to local coordinates of this track sprite
            var localFrom:Point = this.globalToLocal(fromPos);
            var localTo:Point = this.globalToLocal(toPos);

            // Draw track line
            var lineColor:uint = _isActive ? 0x00FF00 : 0x666666;
            var lineAlpha:Number = _isActive ? 0.7 : 0.4;
            var lineThickness:Number = _isActive ? 2 : 1;

            this.graphics.lineStyle(lineThickness, lineColor, lineAlpha);
            this.graphics.moveTo(localFrom.x, localFrom.y);
            this.graphics.lineTo(localTo.x, localTo.y);

            // Add arrowhead for direction indication
            drawArrowhead(localFrom, localTo);
        }

        /**
         * Draw direction arrowhead on track
         * @param from Start point
         * @param to End point
         */
        private function drawArrowhead(from:Point, to:Point):void {
            var length:Number = Point.distance(from, to);
            if (length < 20) return; // Don't draw arrowhead for very short tracks

            var angle:Number = Math.atan2(to.y - from.y, to.x - from.x);
            var arrowSize:Number = 6;

            // Calculate arrowhead points
            var arrow1:Point = new Point(
                to.x - arrowSize * Math.cos(angle - Math.PI/6),
                to.y - arrowSize * Math.sin(angle - Math.PI/6)
            );
            var arrow2:Point = new Point(
                to.x - arrowSize * Math.cos(angle + Math.PI/6),
                to.y - arrowSize * Math.sin(angle + Math.PI/6)
            );

            // Draw arrowhead
            this.graphics.lineStyle(1, 0x00FF00, 0.7);
            this.graphics.moveTo(to.x, to.y);
            this.graphics.lineTo(arrow1.x, arrow1.y);
            this.graphics.moveTo(to.x, to.y);
            this.graphics.lineTo(arrow2.x, arrow2.y);
        }

        /**
         * Get global position of a pin
         * @param pin Pin to get position for
         * @return Global position point
         */
        private function getGlobalPinPosition(pin:Pin):Point {
            return pin.localToGlobal(new Point(0, 0));
        }

        /**
         * Update track visual (alias for drawTrack)
         */
        public function updateVisual():void {
            drawTrack();
        }

        /**
         * Check if track is connected to specific atom
         * @param atomId Atom ID to check
         * @return True if connected to atom
         */
        public function isConnectedToAtom(atomId:String):Boolean {
            return _fromPin.parentAtom.id == atomId || _toPin.parentAtom.id == atomId;
        }

        /**
         * Check if track is connected to specific pin
         * @param pin Pin to check
         * @return True if connected to pin
         */
        public function isConnectedToPin(pin:Pin):Boolean {
            return _fromPin == pin || _toPin == pin;
        }

        /**
         * Get connection information
         * @return Connection info object
         */
        public function getConnectionInfo():Object {
            return {
                fromAtom: _fromPin.parentAtom.id,
                fromPin: _fromPin.pinName,
                toAtom: _toPin.parentAtom.id,
                toPin: _toPin.pinName,
                connectionId: _connectionId,
                isActive: _isActive
            };
        }

        /**
         * Clean up track resources
         */
        public function dispose():void {
            _isActive = false;

            // Remove all impulse listeners
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);

            var sourceImpulseKey:String = "PIN_VALUE_CHANGED_" + _fromPin.parentAtom.id + "_" + _fromPin.pinName;
            MultiPulsator.removeImpulse(sourceImpulseKey, onSourceValueChanged);

            MultiPulsator.removeImpulse("TRACK_UPDATE_REQUEST", onTrackUpdateRequest);

            // Emit disconnect impulse
            MultiPulsator.emit(new Impulse("TRACK_DISCONNECTED", {
                track: this,
                connectionId: _connectionId
            }));

            // Clear graphics
            this.graphics.clear();

            _fromPin = null;
            _toPin = null;

            if (parent) {
                parent.removeChild(this);
            }
        }

        // =========================================================================
        // PUBLIC GETTERS
        // =========================================================================

        /**
         * Get source pin
         * @return From pin (output)
         */
        public function get fromPin():Pin {
            return _fromPin;
        }

        /**
         * Get target pin
         * @return To pin (input)
         */
        public function get toPin():Pin {
            return _toPin;
        }

        /**
         * Get connection ID
         * @return Unique connection identifier
         */
        public function get connectionId():String {
            return _connectionId;
        }

        /**
         * Get track active state
         * @return True if track is active
         */
        public function get isActive():Boolean {
            return _isActive;
        }
    }
}
 
package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Core.Managers.WindowsManager;

    /**
     * TrackManager - Centralized manager for track creation and lifecycle management.
     * Handles the complete track creation process from pin interactions to visual representation.
     */
    public class TrackManager {
        /** Singleton instance */
        private static var _instance:TrackManager;

        /** Active tracks storage */
        private var _activeTracks:Object;

        /** Temporary track during drag operations */
        private var _tempTrack:Sprite;

        /** Currently dragging pin reference */
        private var _currentDragPin:Pin;

        /** Current window context */
        private var _currentWindow:Window;

        /**
         * Private constructor for singleton pattern
         */
        public function TrackManager() {
            _activeTracks = {};
            setupImpulseListeners();
        }

        /**
         * Get singleton instance
         * @return TrackManager singleton instance
         */
        public static function getInstance():TrackManager {
            if (!_instance) {
                _instance = new TrackManager();
            }
            return _instance;
        }

        /**
         * Initialize track manager system
         */
        public static function initialize():void {
            getInstance(); // Ensures instance creation and setup
        }

        /**
         * Setup all impulse listeners for track management
         */
        private function setupImpulseListeners():void {
            // Track creation process
            MultiPulsator.subscribeToImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_END", onPinDragEnd);

            // System events for track updates
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.subscribeToImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.subscribeToImpulse("WINDOW_CLOSING", onWindowClosing);

            // Track management commands
            MultiPulsator.subscribeToImpulse("TRACK_DISCONNECT", onTrackDisconnect);
            MultiPulsator.subscribeToImpulse("TRACK_UPDATE_ALL", onTrackUpdateAll);
        }

        /**
         * Handle pin drag start impulse
         * @param impulse PIN_DRAG_START impulse
         */
        private function onPinDragStart(impulse:Impulse):void {
            _currentDragPin = impulse.data.pin;
            _currentWindow = findWindowByType(impulse.data.windowType);

            if (_currentWindow && _currentDragPin) {
                startTempTrack(impulse.data.startX, impulse.data.startY);
            }
        }

        /**
         * Handle pin drag update impulse
         * @param impulse PIN_DRAG_UPDATE impulse
         */
        private function onPinDragUpdate(impulse:Impulse):void {
            if (_tempTrack && _currentDragPin) {
                updateTempTrack(impulse.data.currentX, impulse.data.currentY);
            }
        }

        /**
         * Handle pin drag end impulse
         * @param impulse PIN_DRAG_END impulse
         */
        private function onPinDragEnd(impulse:Impulse):void {
            if (!_currentDragPin) return;

            var fromPin:Pin = _currentDragPin;
            var toPin:Pin = impulse.data.toPin;

            cleanupTempTrack();

            // Validate and create track if connection is valid
            if (toPin && isValidConnection(fromPin, toPin)) {
                createTrack(fromPin, toPin);
            }

            _currentDragPin = null;
        }

        /**
         * Start temporary track visualization
         * @param startX Starting X coordinate
         * @param startY Starting Y coordinate
         */
        private function startTempTrack(startX:Number, startY:Number):void {
            _tempTrack = new Sprite();

            if (_currentWindow && _currentWindow.overlayLayer) {
                _currentWindow.overlayLayer.addChild(_tempTrack);
                updateTempTrack(startX, startY);
            }
        }

        /**
         * Update temporary track during drag operation
         * @param currentX Current mouse X coordinate
         * @param currentY Current mouse Y coordinate
         */
        private function updateTempTrack(currentX:Number, currentY:Number):void {
            if (!_tempTrack || !_currentDragPin || !_currentWindow) return;

            var fromPos:Point = _currentDragPin.localToGlobal(new Point(0, 0));

            _tempTrack.graphics.clear();
            _tempTrack.graphics.lineStyle(2, 0x00FF00, 0.8);
            _tempTrack.graphics.moveTo(fromPos.x, fromPos.y);
            _tempTrack.graphics.lineTo(currentX, currentY);
        }

        /**
         * Clean up temporary track
         */
        private function cleanupTempTrack():void {
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
            }
            _tempTrack = null;
        }

        /**
         * Validate connection between pins
         * @param fromPin Source pin (must be output)
         * @param toPin Target pin (must be input)
         * @return True if connection is valid
         */
        private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
            return toPin &&
                   toPin.pinType == Pin.TYPE_INPUT &&
                   toPin.parentAtom != fromPin.parentAtom &&
                   !connectionExists(fromPin, toPin);
        }

        /**
         * Check if connection already exists
         * @param fromPin Source pin
         * @param toPin Target pin
         * @return True if connection already exists
         */
        private function connectionExists(fromPin:Pin, toPin:Pin):Boolean {
            var connectionId:String = generateConnectionId(fromPin, toPin);
            return _activeTracks[connectionId] != null;
        }

        /**
         * Create a new track between pins
         * @param fromPin Source pin
         * @param toPin Target pin
         */
        private function createTrack(fromPin:Pin, toPin:Pin):void {
            try {
                var track:Track = new Track(fromPin, toPin);
                var connectionId:String = generateConnectionId(fromPin, toPin);

                // Add to content layer of current window
                if (_currentWindow && _currentWindow.contentLayer) {
                    _currentWindow.contentLayer.addChild(track);
                }

                // Store track reference
                _activeTracks[connectionId] = track;

                // Create logical connection
                track.createLogicalConnection();

                MultiPulsator.emit(new Impulse("TRACK_CREATED", {
                    track: track,
                    fromPin: fromPin,
                    toPin: toPin,
                    connectionId: connectionId,
                    windowType: _currentWindow ? _currentWindow.windowType : "unknown"
                }));

            } catch (error:Error) {
                MultiPulsator.emit(new Impulse("TRACK_CREATION_ERROR", {
                    fromPin: fromPin,
                    toPin: toPin,
                    error: error.message
                }));
            }
        }

        /**
         * Handle atom movement to update connected tracks
         * @param impulse ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:BaseAtom = impulse.data.newAtom;
            var atomId:String = movedAtom.id;

            // Update all tracks connected to this atom
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) {
                    track.updateVisual();
                }
            }
        }

        /**
         * Handle window activation to update track context
         * @param impulse WINDOW_ACTIVATED impulse
         */
        private function onWindowActivated(impulse:Impulse):void {
            _currentWindow = impulse.data.window;
        }

        /**
         * Handle window closing to cleanup tracks
         * @param impulse WINDOW_CLOSING impulse
         */
        private function onWindowClosing(impulse:Impulse):void {
            var closingWindow:Window = impulse.data.window;
            var windowType:String = closingWindow.windowType;

            // Remove tracks associated with this window
            cleanupTracksByWindow(windowType);
        }

        /**
         * Handle track disconnect command
         * @param impulse TRACK_DISCONNECT impulse
         */
        private function onTrackDisconnect(impulse:Impulse):void {
            var track:Track = impulse.data.track;
            var connectionId:String = impulse.data.connectionId;

            if (track) {
                removeTrack(track);
            } else if (connectionId) {
                removeTrackById(connectionId);
            }
        }

        /**
         * Handle update all tracks command
         * @param impulse TRACK_UPDATE_ALL impulse
         */
        private function onTrackUpdateAll(impulse:Impulse):void {
            for each (var track:Track in _activeTracks) {
                track.updateVisual();
            }
        }

        /**
         * Generate unique connection ID
         * @param fromPin Source pin
         * @param toPin Target pin
         * @return Unique connection identifier
         */
        private function generateConnectionId(fromPin:Pin, toPin:Pin):String {
            return "track_" + fromPin.parentAtom.id + "_" + fromPin.pinName +
                   "_to_" + toPin.parentAtom.id + "_" + toPin.pinName;
        }

        /**
         * Find window by type
         * @param windowType Window type to find
         * @return Found window or null
         */
        private function findWindowByType(windowType:String):Window {
            var windowsManager:WindowsManager = WindowsManager.getInstance();
            if (windowsManager) {
                return windowsManager.findWindow(windowType);
            }
            return null;
        }

        /**
         * Cleanup tracks by window type
         * @param windowType Window type to cleanup
         */
        private function cleanupTracksByWindow(windowType:String):void {
            // Implementation depends on track-window association strategy
            // For now, we'll keep it simple and not remove tracks based on window
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Remove track by track instance
         * @param track Track to remove
         */
        public function removeTrack(track:Track):void {
            var connectionId:String = track.connectionId;

            if (_activeTracks[connectionId]) {
                track.dispose();
                delete _activeTracks[connectionId];

                MultiPulsator.emit(new Impulse("TRACK_REMOVED", {
                    track: track,
                    connectionId: connectionId
                }));
            }
        }

        /**
         * Remove track by connection ID
         * @param connectionId Connection ID to remove
         */
        public function removeTrackById(connectionId:String):void {
            var track:Track = _activeTracks[connectionId];
            if (track) {
                removeTrack(track);
            }
        }

        /**
         * Get all active tracks
         * @return Object of active tracks
         */
        public function getActiveTracks():Object {
            return _activeTracks;
        }

        /**
         * Get track by connection ID
         * @param connectionId Connection ID to find
         * @return Found track or null
         */
        public function getTrackById(connectionId:String):Track {
            return _activeTracks[connectionId];
        }

        /**
         * Get tracks connected to specific atom
         * @param atomId Atom ID to find connections for
         * @return Array of connected tracks
         */
        public function getTracksByAtom(atomId:String):Array {
            var connectedTracks:Array = [];

            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) {
                    connectedTracks.push(track);
                }
            }

            return connectedTracks;
        }

        /**
         * Get tracks connected to specific pin
         * @param pin Pin to find connections for
         * @return Array of connected tracks
         */
        public function getTracksByPin(pin:Pin):Array {
            var connectedTracks:Array = [];

            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToPin(pin)) {
                    connectedTracks.push(track);
                }
            }

            return connectedTracks;
        }

        /**
         * Cleanup all resources
         */
        public function dispose():void {
            // Remove all impulse listeners
            MultiPulsator.removeImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.removeImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.removeImpulse("PIN_DRAG_END", onPinDragEnd);
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.removeImpulse("WINDOW_CLOSING", onWindowClosing);
            MultiPulsator.removeImpulse("TRACK_DISCONNECT", onTrackDisconnect);
            MultiPulsator.removeImpulse("TRACK_UPDATE_ALL", onTrackUpdateAll);

            // Dispose all active tracks
            for each (var track:Track in _activeTracks) {
                track.dispose();
            }
            _activeTracks = {};

            // Cleanup temporary track
            cleanupTempTrack();

            _currentDragPin = null;
            _currentWindow = null;
        }
    }
}
 
package Src.Prog.Com.Atoms.Custom {
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Logical representation of a Button atom.
     */
    public class ButtonAtom extends BaseAtom {
        public function ButtonAtom(id:String, pos:Point, name:String, type:String,
                                 inputContacts:Vector.<Pin> = null,
                                 outputContacts:Vector.<Pin> = null) {
            super(id, pos, name, type, inputContacts, outputContacts);
        }
    }
}
 
package Src.Prog.Com.Atoms.Custom {
    import flash.display.BitmapData;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Com.Logics.Behaviors.ButtonAtomBehavior;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Visual representation of a button atom.
     * Inherits from BaseAtomView for common functionality.
     */
    public class ButtonAtom_EditorView extends BaseAtomView {
        private var _behavior:ButtonAtomBehavior = new ButtonAtomBehavior();
        private var _pressed:Boolean = false;
        private var _nameLabel:TextField;
        private static const WIDTH:Number = 80;
        private static const HEIGHT:Number = 30;

        /**
         * Constructs the ButtonAtomView.
         * Initializes visual elements and interactions.
         */
        public function ButtonAtom_EditorView() {
            super();
            createNameLabel();
            drawButton();
            setupButtonInteractions();
        }

        /**
         * @inheritDoc
         * Initializes the view with a specific atom and updates its visuals.
         */
        override public function initWithAtom(atom:BaseAtom):void {
            super.initWithAtom(atom);
            updateLabel();
            updateVisuals();
        }

        /**
         * @inheritDoc
         * Updates the visual representation of the button based on its state.
         */
        override public function updateVisuals():void {
            drawButton();
            drawContacts();
        }

        /**
         * Creates the text label for the button's name.
         */
        private function createNameLabel():void {
            _nameLabel = new TextField();
            _nameLabel.width = WIDTH;
            _nameLabel.height = HEIGHT;
            _nameLabel.y = 10;
            _nameLabel.selectable = false;
            _nameLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0x333333;
            _nameLabel.defaultTextFormat = format;
            this.addChild(_nameLabel);
        }

        /**
         * Sets up button-specific mouse event listeners.
         */
        private function setupButtonInteractions():void {
            // Base interactions already setup in parent
            // Add button-specific listeners
            this.addEventListener(MouseEvent.MOUSE_UP, onRelease);
            this.addEventListener(MouseEvent.ROLL_OUT, onRollOutVisual);
        }

        /**
         * @inheritDoc
         * Handles the mouse down event for the button.
         * Sets the button state to pressed and propagates a 'true' value.
         */
        override protected function onSpecificMouseDown(event:MouseEvent):void {
            if (_isDragging) return;

            _pressed = true;
            drawButton();
            drawContacts();

            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var newAtom:BaseAtom = _behavior.setPressed(_parentAtom, true);

                // Update atom in system
                var atomManager:AtomManager = AtomManager.getInstance();
                if (atomManager) {
                    atomManager.updateAtom(newAtom);
                }

                // Emit pin update
                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                    atomId: newAtom.id,
                    pinName: newAtom.outputContacts[0].name,
                    newValue: true
                }));

                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * Updates the text displayed in the name label.
         */
        private function updateLabel():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * Draws the button's background, changing color based on its pressed state.
         */
        private function drawButton():void {
            this.graphics.clear();
            var color:uint = _pressed ? 0x27AE60 : 0x2ECC71;
            this.graphics.beginFill(color);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 5, 5);
            this.graphics.endFill();
        }

        /**
         * @inheritDoc
         * Draws the contact pins for the button.
         */
        override protected function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Creates and positions the output pins based on the atom's contacts.
         * The button only has output pins.
         */
        private function createAndPositionPins():void {
            if(!_parentAtom) return;
            removeExistingPins();

            for(var j:int = 0; j < _parentAtom.outputContacts.length; j++) {
                var outputPin:Pin = _parentAtom.outputContacts[j];
                var outputY:Number = HEIGHT * (j + 1) / (_parentAtom.outputContacts.length + 1);
                outputPin.x = this.width;
                outputPin.y = outputY;
                this.addChild(outputPin);
            }
        }

        /**
         * @inheritDoc
         * Removes any existing pin objects from the display list.
         */
        override protected function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * Handles the mouse up event for the button.
         * Sets the button state to released and propagates a 'false' value.
         */
        private function onRelease(e:MouseEvent):void {
            if (_isDragging) return;
            _pressed = false;
            drawButton();
            drawContacts();

            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var newAtom:BaseAtom = _behavior.setPressed(_parentAtom, false);

                // Update atom in system
                var atomManager:AtomManager = AtomManager.getInstance();
                if (atomManager) {
                    atomManager.updateAtom(newAtom);
                }

                // Emit pin update
                MultiPulsator.emit(new Impulse("PIN_UPDATED", {
                    atomId: newAtom.id,
                    pinName: newAtom.outputContacts[0].name,
                    newValue: false
                }));

                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * Handles the mouse roll-out event.
         * Redraws the button if it's not currently pressed.
         */
        private function onRollOutVisual(e:MouseEvent):void {
            if (!_pressed) {
                drawButton();
                drawContacts();
            }
        }

        /**
         * @inheritDoc
         * Handles the completion of an asset load.
         */
        override public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "ButtonAtomView",
                message: "Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
            }));
            if (assetData is BitmapData) {
                this.graphics.clear();
                var bitmap:flash.display.Bitmap = new flash.display.Bitmap(assetData as BitmapData);
                bitmap.x = (WIDTH - bitmap.width) / 2;
                bitmap.y = (HEIGHT - bitmap.height) / 2;
                this.addChild(bitmap);
                drawContacts();
            }
        }

        /**
         * @inheritDoc
         * Handles an error during asset loading.
         */
        override public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "ERROR",
                source: "ButtonAtomView",
                message: "ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }

        /**
         * Gets the current pressed state of the button.
         * @return True if the button is pressed, false otherwise.
         */
        public function get pressed():Boolean {
            return _pressed;
        }
    }
}
 
package Src.Prog.Com.Atoms.Custom {
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Logical representation of a Counter atom.
     */
    public class CounterAtom extends BaseAtom {
        public function CounterAtom(id:String, pos:Point, name:String, type:String,
                                  inputContacts:Vector.<Pin> = null,
                                  outputContacts:Vector.<Pin> = null) {
            super(id, pos, name, type, inputContacts, outputContacts);
        }
    }
}
 
package Src.Prog.Com.Atoms.Custom {
    import flash.display.BitmapData;
    import flash.events.MouseEvent;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Visual representation of a counter atom.
     * Inherits from BaseAtomView for common functionality.
     */
    public class CounterAtom_EditorView extends BaseAtomView {
        private var _valueLabel:TextField;
        private var _nameLabel:TextField;
        public static const WIDTH:Number = 120;
        public static const HEIGHT:Number = 60;

        /**
         * Constructs the CounterAtomView.
         * Initializes visual elements and interactions.
         */
        public function CounterAtom_EditorView() {
            super();
            createVisuals();
            setupCounterInteractions();
        }

        /**
         * @inheritDoc
         * Initializes the view with a specific atom, subscribes to updates, and updates visuals.
         */
        override public function initWithAtom(atom:BaseAtom):void {
            super.initWithAtom(atom);
            MultiPulsator.subscribeToImpulse("ATOM_UPDATED", onAtomUpdated);
            updateLabels();
            updateVisuals();
        }

        /**
         * Handles the ATOM_UPDATED impulse to refresh the display if the atom changes.
         */
        private function onAtomUpdated(impulse:Impulse):void {
            var newAtom:BaseAtom = impulse.data.newAtom as BaseAtom;
            if (newAtom && newAtom.id == _parentAtom.id) {
                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * @inheritDoc
         * Updates the visual representation, including the background, contacts, and value display.
         */
        override public function updateVisuals():void {
            drawBackground();
            drawContacts();
            if (_parentAtom && _parentAtom.outputContacts.length > 0) {
                var outputPin:Pin = _parentAtom.outputContacts[0];
                _valueLabel.text = (outputPin.value !== null && outputPin.value !== undefined) ? outputPin.value.toString() : "0";
            } else {
                _valueLabel.text = "0";
            }
        }

        /**
         * Creates the necessary visual elements like labels.
         */
        private function createVisuals():void {
            createValueLabel();
            createNameLabel();
        }

        /**
         * Sets up counter-specific interactions.
         * Currently, the counter does not require additional mouse listeners.
         */
        private function setupCounterInteractions():void {
            // Base interactions already setup in parent
            // Counter doesn't need additional mouse listeners
        }

        /**
         * @inheritDoc
         * Handles the mouse down event for the counter.
         * The counter only supports dragging, handled by the parent class.
         */
        override protected function onSpecificMouseDown(event:MouseEvent):void {
            // Counter doesn't have click behavior, only drag
            // BaseAtomView already handles bringToFront and drag
        }

        /**
         * Draws the background of the counter.
         */
        private function drawBackground():void {
            this.graphics.clear();
            this.graphics.beginFill(0x3498DB);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 10, 10);
            this.graphics.endFill();
        }

        /**
         * Creates the text label for displaying the numeric value.
         */
        private function createValueLabel():void {
            _valueLabel = new TextField();
            _valueLabel.width = WIDTH;
            _valueLabel.height = HEIGHT;
            _valueLabel.selectable = false;
            _valueLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 18;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xFFFFFF;
            format.bold = true;
            _valueLabel.defaultTextFormat = format;
            this.addChild(_valueLabel);
        }

        /**
         * Creates the text label for displaying the atom's name.
         */
        private function createNameLabel():void {
            _nameLabel = new TextField();
            _nameLabel.width = WIDTH;
			_nameLabel.height = 20;
            _nameLabel.y = 40;
            _nameLabel.selectable = false;
            _nameLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xEEEEEE;
            _nameLabel.defaultTextFormat = format;
            this.addChild(_nameLabel);
        }

        /**
         * Updates the text displayed in the name label.
         */
        private function updateLabels():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * @inheritDoc
         * Draws the contact pins for the counter.
         */
        override protected function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Creates and positions the input and output pins based on the atom's contacts.
         */
        private function createAndPositionPins():void {
            if(!_parentAtom) return;

            // Use parent class method to remove existing pins
            removeExistingPins();

            // Input pins
            for(var i:int = 0; i < _parentAtom.inputContacts.length; i++) {
                var inputPin:Pin = _parentAtom.inputContacts[i];
                var inputY:Number = HEIGHT * (i + 1) / (_parentAtom.inputContacts.length + 1);
                inputPin.x = 0;
                inputPin.y = inputY;
                this.addChild(inputPin);
            }

            // Output pins
            for(var j:int = 0; j < _parentAtom.outputContacts.length; j++) {
                var outputPin:Pin = _parentAtom.outputContacts[j];
                var outputY:Number = HEIGHT * (j + 1) / (_parentAtom.outputContacts.length + 1);
                outputPin.x = this.width;
                outputPin.y = outputY;
                this.addChild(outputPin);
            }
        }

        /**
         * @inheritDoc
         * Handles the completion of an asset load.
         */
        override public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "CounterAtomView",
                message: "Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
            }));
            if (assetData is BitmapData) {
                this.graphics.clear();
                var bitmap:flash.display.Bitmap = new flash.display.Bitmap(assetData as BitmapData);
                bitmap.x = (WIDTH - bitmap.width) / 2;
                bitmap.y = (HEIGHT - bitmap.height) / 2;
                this.addChild(bitmap);
                drawContacts();
            }
        }

        /**
         * @inheritDoc
         * Handles an error during asset loading.
         */
        override public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "ERROR",
                source: "CounterAtomView",
                message: "ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }
    }
}
 
package Src.Prog.Com.Atoms.Custom {
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Logical representation of a Number Display atom.
     */
    public class NumberDisplayAtom extends BaseAtom {
        public function NumberDisplayAtom(id:String, pos:Point, name:String, type:String,
                                        inputContacts:Vector.<Pin> = null,
                                        outputContacts:Vector.<Pin> = null) {
            super(id, pos, name, type, inputContacts, outputContacts);
        }
    }
}
 
package Src.Prog.Com.Atoms.Custom {
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.Pin;

	// НАДО ДОБАВИТЬ НЕДОСТАЮЩИЕ import

    /**
     * Visual representation of a number display atom.
     * Inherits from BaseAtomView for common functionality.
     */
    public class NumberDisplayAtom_EditorView extends BaseAtomView {
        private var _valueLabel:TextField;
        private var _nameLabel:TextField;
        public static const WIDTH:Number = 100;
        public static const HEIGHT:Number = 50;

        /**
         * Constructs the NumberDisplayAtomView.
         * Initializes visual elements and interactions.
         */
        public function NumberDisplayAtom_EditorView() {
            super();
            createVisuals();
            setupDisplayInteractions();
        }

        /**
         * @inheritDoc
         * Initializes the view with a specific atom, subscribes to updates, and updates visuals.
         */
        override public function initWithAtom(atom:BaseAtom):void {
            super.initWithAtom(atom);
            MultiPulsator.subscribeToImpulse("ATOM_UPDATED", onAtomUpdated);
            updateLabels();
            updateVisuals();
        }

        /**
         * Handles the ATOM_UPDATED impulse to refresh the display if the atom changes.
         */
        private function onAtomUpdated(impulse:Impulse):void {
            var newAtom:BaseAtom = impulse.data.newAtom as BaseAtom;
            if (newAtom && newAtom.id == _parentAtom.id) {
                _parentAtom = newAtom;
                updateVisuals();
            }
        }

        /**
         * @inheritDoc
         * Updates the visual representation, including the background, contacts, and value display.
         */
        override public function updateVisuals():void {
            drawBackground();
            drawContacts();
            if (_parentAtom && _parentAtom.inputContacts.length > 0) {
                var inputPin:Pin = _parentAtom.inputContacts[0];
                _valueLabel.text = inputPin.value !== undefined && inputPin.value !== null ? inputPin.value.toString() : "0";
            } else {
                _valueLabel.text = "0";
            }
        }

        /**
         * Creates the necessary visual elements like labels.
         */
        private function createVisuals():void {
            createValueLabel();
            createNameLabel();
        }

        /**
         * Sets up display-specific interactions.
         * Currently, the display does not require additional mouse listeners.
         */
        private function setupDisplayInteractions():void {
            // Base interactions already setup in parent
            // Display doesn't need additional mouse listeners
        }

        /**
         * @inheritDoc
         * Handles the mouse down event for the display.
         * The display only supports dragging, handled by the parent class.
         */
        override protected function onSpecificMouseDown(event:MouseEvent):void {
            // Display doesn't have click behavior, only drag
            // BaseAtomView already handles bringToFront and drag
        }

        /**
         * Draws the background of the display.
         */
        private function drawBackground():void {
            this.graphics.clear();
            this.graphics.beginFill(0x34495E);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 5, 5);
            this.graphics.endFill();
        }

        /**
         * Creates the text label for displaying the numeric value.
         */
        private function createValueLabel():void {
            _valueLabel = new TextField();
            _valueLabel.width = WIDTH;
            _valueLabel.height = HEIGHT;
            _valueLabel.selectable = false;
            _valueLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 16;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xECF0F1;
            format.bold = true;
            _valueLabel.defaultTextFormat = format;
            this.addChild(_valueLabel);
        }

        /**
         * Creates the text label for displaying the atom's name.
         */
        private function createNameLabel():void {
            _nameLabel = new TextField();
            _nameLabel.width = WIDTH;
            _nameLabel.y = 30;
            _nameLabel.selectable = false;
            _nameLabel.mouseEnabled = false;
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.align = TextFormatAlign.CENTER;
            format.color = 0xBDC3C7;
            _nameLabel.defaultTextFormat = format;
            this.addChild(_nameLabel);
        }

        /**
         * Updates the text displayed in the name label.
         */
        private function updateLabels():void {
            if (_parentAtom) {
                _nameLabel.text = _parentAtom.name;
            }
        }

        /**
         * @inheritDoc
         * Draws the contact pins for the display.
         */
        override protected function drawContacts():void {
            createAndPositionPins();
        }

        /**
         * Creates and positions the input pins based on the atom's contacts.
         * The display only has input pins.
         */
        private function createAndPositionPins():void {
            if(!_parentAtom) return;
            removeExistingPins();

            // Input pins only (display has no outputs)
            for(var i:int = 0; i < _parentAtom.inputContacts.length; i++) {
                var inputPin:Pin = _parentAtom.inputContacts[i];
                var inputY:Number = HEIGHT * (i + 1) / (_parentAtom.inputContacts.length + 1);
                inputPin.x = 0;
                inputPin.y = inputY;
                this.addChild(inputPin);
            }
        }

        /**
         * @inheritDoc
         * Removes any existing pin objects from the display list.
         */
        override protected function removeExistingPins():void {
            for(var i:int = this.numChildren - 1; i >= 0; i--) {
                if(this.getChildAt(i) is Pin) {
                    this.removeChildAt(i);
                }
            }
        }

        /**
         * @inheritDoc
         * Handles the completion of an asset load.
         */
        override public function onAssetLoadComplete(assetUrl:String, assetData:*):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "NumberDisplayAtomView",
                message: "Asset loaded for atom: " + (_parentAtom ? _parentAtom.name : "Unknown")
            }));
            if (assetData is BitmapData) {
                this.graphics.clear();
                var bitmap:flash.display.Bitmap = new flash.display.Bitmap(assetData as BitmapData);
                bitmap.x = (WIDTH - bitmap.width) / 2;
                bitmap.y = (HEIGHT - bitmap.height) / 2;
                this.addChild(bitmap);
                drawContacts();
            }
        }

        /**
         * @inheritDoc
         * Handles an error during asset loading.
         */
        override public function onAssetLoadError(assetUrl:String, errorMessage:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "ERROR",
                source: "NumberDisplayAtomView",
                message: "ERROR loading asset for atom '" + (_parentAtom ? _parentAtom.name : "Unknown") + "': " + errorMessage
            }));
            this.graphics.clear();
            this.graphics.beginFill(0xFF0000, 0.7);
            this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 8, 8);
            this.graphics.endFill();
            drawContacts();
        }
    }
}
 
package Src.Prog.Com.Logics {

    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.utils.Dictionary;

    import Src.Prog.Com.Logics.Behaviors.ButtonAtomBehavior;

    /**
     * Manages the behaviors associated with different atom types.
     * Stores and provides IAtomBehavior instances based on the atom type.
     * Integrates with AtomFactory and ConnectionManager to handle pin changes and device interactions.
     */
    public class AtomICScriptManager {
        private static var _instance:AtomICScriptManager;
        private var _behaviors:Dictionary;

        /**
         * Initializes the AtomICScriptManager and subscribes to device interaction impulses.
         */
        public function AtomICScriptManager() {
            _behaviors = new Dictionary();
            MultiPulsator.subscribeToImpulse("DEVICE_ATOM_INTERACTION", onDeviceAtomInteraction);
        }

        /**
         * Gets the singleton instance of the AtomICScriptManager.
         * Creates the instance if it does not exist.
         * @return The singleton AtomICScriptManager instance.
         */
        public static function getInstance():AtomICScriptManager {
            if (!_instance) {
                _instance = new AtomICScriptManager();
            }
            return _instance;
        }

        /**
         * Registers a behavior for a specific atom type.
         * @param atomType The type of the atom (e.g., "Counter").
         * @param behavior The behavior instance to register.
         */
        public function registerBehavior(atomType:String, behavior:IAtomBehavior):void {
            _behaviors[atomType] = behavior;
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "AtomICScriptManager",
                message: "Registered behavior for: " + atomType
            }));
        }

        /**
         * Gets the behavior associated with a specific atom type.
         * @param atomType The type of the atom.
         * @return The registered behavior instance, or null if not found.
         */
        public function getBehavior(atomType:String):IAtomBehavior {
            return _behaviors[atomType];
        }

        /**
         * Invokes the behavior for an atom when one of its input pins changes.
         * @param atom The atom whose pin changed.
         * @param changedPin The pin that changed.
         * @return A new atom instance if the behavior modified it, or the original atom otherwise.
         */
        public function handlePinChange(atom:BaseAtom, changedPin:Pin):BaseAtom {
            if (changedPin.type != Pin.TYPE_INPUT) {
                return atom; // Only inputs trigger behavior
            }
            var behavior:IAtomBehavior = getBehavior(atom.type);
            if (behavior) {
                return behavior.onInputPinChanged(atom, changedPin);
            }
            return atom;
        }

        /**
         * Handles device interaction impulses (e.g., button press/release).
         */
        private function onDeviceAtomInteraction(impulse:Impulse):void {
            var atom:BaseAtom = impulse.data.atom;
            var interactionType:String = impulse.data.interactionType;

            if (!atom) return;

            var behavior:IAtomBehavior = getBehavior(atom.type);
            if (behavior) {
                handleDeviceInteraction(behavior, atom, interactionType);
            }
        }

        /**
         * Executes the appropriate behavior based on the type of device interaction.
         */
        private function handleDeviceInteraction(behavior:IAtomBehavior, atom:BaseAtom, interactionType:String):void {
            switch(interactionType) {
                case "button_press":
                    if (behavior is ButtonAtomBehavior) {
                        var newAtom:BaseAtom = ButtonAtomBehavior(behavior).setPressed(atom, true);
                        updateAtomAndPropagate(newAtom);
					}
                    break;

                case "button_release":
                    if (behavior is ButtonAtomBehavior) {
                        var releasedAtom:BaseAtom = ButtonAtomBehavior(behavior).setPressed(atom, false);
                        updateAtomAndPropagate(releasedAtom);
                    }
                    break;
            }
        }

        /**
         * Updates the atom in the AtomManager and propagates the change.
         */
        private function updateAtomAndPropagate(newAtom:BaseAtom):void {
            var atomManager:AtomManager = AtomManager.getInstance();
            if (atomManager) {
                atomManager.updateAtom(newAtom);
            }
        }
    }
}
 
package Src.Prog.Com.Logics.Behaviors {
    import Src.Prog.Com.Logics.IAtomBehavior;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Implements the behavior for a Button atom.
     * A button typically has no input pins, so `onInputPinChanged` is not used.
     * The primary behavior is triggered directly by the view on click/release,
     * handled by the `setPressed` method.
     */
    public class ButtonAtomBehavior implements IAtomBehavior {
        /**
         * @inheritDoc
         * Initializes the button atom by setting its output pin value to false (released state).
         */
        public function initializeAtom(atom:BaseAtom):BaseAtom {
            if (atom.outputContacts.length > 0) {
                var outPin:Pin = atom.outputContacts[0];
                return atom.setOutputPinValue(outPin.name, false);
            }
            return atom;
        }

        /**
         * @inheritDoc
         * Handles changes to an input pin. This method is not used for a button atom,
         * as buttons typically do not have input pins.
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Button has no inputs - method not used
            return atom;
        }

        /**
         * Sets the pressed state of the button atom.
         * Updates the output pin value based on the pressed state.
         * @param atom The current atom instance.
         * @param isPressed True if the button is pressed, false if released.
         * @return A new BaseAtom instance with the updated output value.
         */
        public function setPressed(atom:BaseAtom, isPressed:Boolean):BaseAtom {
            if (atom.outputContacts.length > 0) {
                var outPin:Pin = atom.outputContacts[0];
                return atom.setOutputPinValue(outPin.name, isPressed);
            }
            return atom;
        }
    }
}
 
package Src.Prog.Com.Logics.Behaviors {
    import Src.Prog.Com.Logics.IAtomBehavior;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Implements the behavior for a Counter atom.
     * Responds to a 'true' value on its input pin by incrementing an internal counter
     * and updating its output pin with the new value.
     */
    public class CounterAtomBehavior implements IAtomBehavior {
        /**
         * @inheritDoc
         * Initializes the counter atom by setting its output pin value to 0.
         */
        public function initializeAtom(atom:BaseAtom):BaseAtom {
            if (atom.outputContacts.length > 0) {
                var outPin:Pin = atom.outputContacts[0];
                return atom.setOutputPinValue(outPin.name, 0);
            }
            return atom;
        }

        /**
         * @inheritDoc
         * Handles changes to an input pin. The counter increments its value
         * only when the input pin receives a 'true' value.
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Counter triggers only on 'true'
            if (changedPin.value === true) {
                var currentValue:int = 0;
                if (atom.outputContacts.length > 0) {
                    var currentOutputPin:Pin = atom.outputContacts[0];
                    if (currentOutputPin.value !== null && currentOutputPin.value !== undefined) {
                        currentValue = int(currentOutputPin.value);
                    }
                }
                var newCounterValue:int = currentValue + 1;
                if (atom.outputContacts.length > 0) {
                    var outPin:Pin = atom.outputContacts[0];
                    return atom.setOutputPinValue(outPin.name, newCounterValue);
                }
            }
            return atom;
        }
    }
}
 
package Src.Prog.Com.Logics.Behaviors {
    import Src.Prog.Com.Logics.IAtomBehavior;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Implements the behavior for a Number Display atom.
     * The display atom does not change its internal state or generate outputs;
     * it simply reflects the input value visually. This behavior implementation
     * does nothing and returns the atom unchanged.
     */
    public class NumberDisplayAtomBehavior implements IAtomBehavior {
        /**
         * @inheritDoc
         * Initializes the number display atom. The display does not require specific initialization,
         * so it returns the atom as-is.
         */
        public function initializeAtom(atom:BaseAtom):BaseAtom {
            // Display doesn't need initialization - just return atom
            return atom;
        }

        /**
         * @inheritDoc
         * Handles changes to an input pin. The display atom does not generate outputs,
         * so it returns the atom unchanged.
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Display doesn't generate outputs - just return atom
            return atom;
        }
    }
}
 
package Src.Prog.Com.Logics {
	import Src.Prog.Com.Atoms.Core.BaseAtom;
	import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Interface defining the contract for an atom's behavior.
     * Specifies the lifecycle methods for atom initialization and
     * reaction to input pin changes. Used in an immutable architecture,
     * meaning implementations must return a *new* BaseAtom instance.
     */
    public interface IAtomBehavior {
        /**
         * Initializes the atom after its creation.
         * @param atom The newly created atom instance.
         * @return A new BaseAtom instance representing the initialized state.
         */
        function initializeAtom(atom:BaseAtom):BaseAtom;

        /**
         * Called when an input pin's value changes.
         * @param atom The current (new) atom instance.
         * @param changedPin The input pin that changed.
         * @return A new BaseAtom instance with updated outputs, or the same atom if no changes are needed.
         */
        function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom;
    }
}
 
package Src.Prog.Com.Menus {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.MouseEvent;

    /**
     * Represents a single item in the AtomContextMenu.
     * Displays the atom type name and category, and provides visual feedback on hover.
     */
    public class AtomContextMenuItem extends Sprite {
        public var atomType:String;
        private var _label:TextField;
        private var _isHighlighted:Boolean = false;
        private var _category:String;

        /**
         * Constructs an AtomContextMenuItem instance.
         * @param type The type of atom this item represents.
         * @param label The display name for the atom type.
         * @param category The optional category for the atom type.
         */
        public function AtomContextMenuItem(type:String, label:String, category:String = "") {
            _category = category;
            this.atomType = type;
            _label = new TextField();
            _label.text = label + (category ? " (" + category + ")" : "");
            _label.x = 5;
            _label.y = 2;
            _label.width = 150;
            _label.height = 16;
            _label.selectable = false;
            _label.mouseEnabled = false;
            var fmt:TextFormat = new TextFormat("Consolas", 10, 0x000000);
            _label.setTextFormat(fmt);
            addChild(_label);

            updateAppearance();
            buttonMode = true;
            addEventListener(MouseEvent.MOUSE_OVER, onHover);
            addEventListener(MouseEvent.MOUSE_OUT, onOut);
            addEventListener(MouseEvent.CLICK, onClick);
        }

        /**
         * Handles the mouse over event to highlight the item.
         */
        private function onHover(e:MouseEvent):void {
            _isHighlighted = true;
            updateAppearance();
        }

        /**
         * Handles the mouse out event to remove the highlight.
         */
        private function onOut(e:MouseEvent):void {
            _isHighlighted = false;
            updateAppearance();
        }

        /**
         * Handles the click event.
         * Stops event propagation to prevent it from bubbling up to the parent menu.
         */
        private function onClick(e:MouseEvent):void {
            e.stopPropagation();
        }

        /**
         * Updates the visual appearance of the item based on its highlighted state.
         */
        private function updateAppearance():void {
            graphics.clear();

            var color:uint = 0xFFFFFF;
            if (_category == "Danger") color = _isHighlighted ? 0xFF6666 : 0xFFCCCC;
            else if (_category == "Info") color = _isHighlighted ? 0x66A3FF : 0xCCE0FF;
            else color = _isHighlighted ? 0x3399FF : 0xFFFFFF;

            graphics.beginFill(color);
            graphics.drawRect(0, 0, this.width, 22);
            graphics.endFill();
        }
    }
}
 
package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Context menu for creating new atoms on the canvas
     */
    public class AtomCreationContextMenu extends BaseContextMenu {
        private var _clickPosition:Point;
        private var _items:Array = [];

        public function AtomCreationContextMenu(localClickPos:Point, canvasPos:Point) {
            super();
            _clickPosition = canvasPos;

            trace("AtomCreationContextMenu created at: " + localClickPos);

            // Build menu UI
            buildMenuUI();

            // Position menu - используем переданные локальные координаты
            this.x = localClickPos.x;
            this.y = localClickPos.y;

            trace("Menu positioned at: " + this.x + ", " + this.y);
        }

        /**
         * Builds the menu user interface with temporary atom types
         */
        private function buildMenuUI():void {
            // Временный список типов атомов
            var atomTypes:Array = [
                {type: "Button", displayName: "Button", category: "Input"},
                {type: "Counter", displayName: "Counter", category: "Logic"},
                {type: "NumberDisplay", displayName: "Number Display", category: "Output"}
            ];

            // Рисуем яркий видимый фон для отладки
            graphics.beginFill(0x333333, 0.95);
            graphics.lineStyle(2, 0xFFFFFF);
            graphics.drawRect(0, 0, 170, 10 + 22 * atomTypes.length);
            graphics.endFill();

            var y:Number = 5;

            for each (var atomType:Object in atomTypes) {
                var item:AtomContextMenuItem = new AtomContextMenuItem(
                    atomType.type,
                    atomType.displayName,
                    atomType.category
                );
                item.y = y;
                item.addEventListener(MouseEvent.CLICK, onItemClick);
                addChild(item);
                _items.push(item);
                y += 22;
            }

            trace("Menu UI built with " + atomTypes.length + " items");
        }

        /**
         * Handles menu item click
         */
		private function onItemClick(event:MouseEvent):void {
			var item:AtomContextMenuItem = event.currentTarget as AtomContextMenuItem;
			trace("Menu item clicked: " + item.atomType + " at position: " + _clickPosition);
			close();

			MultiPulsator.emit(new Impulse("ATOM_CONTEXT_MENU_SELECTED", {
				atomType: item.atomType,
				position: _clickPosition
			}));
		}
    }
}
 
package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Context menu for atom operations (delete, properties, etc.)
     * Provides options for managing individual atoms in the editor
     */
    public class AtomOptionsContextMenu extends BaseContextMenu {
        private var _targetAtom:BaseAtom;

        /**
         * Constructs an AtomOptionsContextMenu instance
         * @param globalClickPos - global stage coordinates of the click
         * @param targetAtom - atom that the menu operates on
         */
        public function AtomOptionsContextMenu(globalClickPos:Point, targetAtom:BaseAtom) {
            super();
            _targetAtom = targetAtom;

            // Build menu UI
            graphics.beginFill(0x333333, 0.3);
            graphics.drawRect(-5, 0, 160, 60);
            graphics.endFill();

            // Delete item
            var deleteItem:AtomContextMenuItem = new AtomContextMenuItem("delete", "Delete Atom", "Danger");
            deleteItem.y = 5;
            deleteItem.addEventListener(MouseEvent.CLICK, onDeleteClick);
            addChild(deleteItem);

            // Properties item (for future use)
            var propsItem:AtomContextMenuItem = new AtomContextMenuItem("properties", "Properties", "Info");
            propsItem.y = 27;
            propsItem.addEventListener(MouseEvent.CLICK, onPropertiesClick);
            addChild(propsItem);

            // Position menu
            this.x = globalClickPos.x;
            this.y = globalClickPos.y;
        }

        /**
         * Handles delete menu item click
         * Emits impulse to request atom deletion
         */
        private function onDeleteClick(event:MouseEvent):void {
            close();
            MultiPulsator.emit(new Impulse("ATOM_DELETE_REQUEST", {
                atom: _targetAtom
            }));
        }

        /**
         * Handles properties menu item click
         * Emits impulse to request atom properties dialog (future feature)
         */
        private function onPropertiesClick(event:MouseEvent):void {
            close();
            MultiPulsator.emit(new Impulse("ATOM_PROPERTIES_REQUEST", {
                atom: _targetAtom
            }));
        }
    }
}
 
package Src.Prog.Com.Menus {
    import flash.display.Sprite;
    import flash.events.MouseEvent;

    /**
     * Base class for all context menus in ALTAURUS
     * Provides common functionality and ensures consistent behavior
     */
    public class BaseContextMenu extends Sprite {

        public function BaseContextMenu() {
            // Add common mouse handling to prevent event propagation
            addEventListener(MouseEvent.MOUSE_DOWN, onMenuMouseDown);
        }

        /**
         * Prevents the menu from closing when clicking inside it
         */
        protected function onMenuMouseDown(event:MouseEvent):void {
            event.stopPropagation();
        }

        /**
         * Removes the context menu from display list
         * Override in child classes if additional cleanup is needed
         */
        public function close():void {
            if (parent) {
                parent.removeChild(this);
            }
        }
    }
}
 
package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Context menu for track operations
     */
    public class TrackContextMenu extends BaseContextMenu {
        private var _targetTrack:Track;

        public function TrackContextMenu(globalClickPos:Point, targetTrack:Track) {
            super();
            _targetTrack = targetTrack;

            graphics.beginFill(0x333333, 0.3);
            graphics.drawRect(-5, 0, 160, 32);
            graphics.endFill();

            var deleteItem:AtomContextMenuItem = new AtomContextMenuItem("delete_track", "Delete Track", "Danger");
            deleteItem.y = 5;
            deleteItem.addEventListener(MouseEvent.CLICK, onDeleteClick);
            addChild(deleteItem);

            this.x = globalClickPos.x;
            this.y = globalClickPos.y;
        }

        private function stopPropagation(event:MouseEvent):void {
            event.stopPropagation();
            event.stopImmediatePropagation();
        }

        private function onDeleteClick(event:MouseEvent):void {
            event.stopPropagation(); // Останавливаем всплытие
            close();
            MultiPulsator.emit(new Impulse("TRACK_DELETE_REQUEST", {
                track: _targetTrack
            }));
        }
    }
}
 
package Src.Prog.Core.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.TimerEvent;
    import flash.utils.Timer;

    import Src.Prog.Core.Commands.CommandErrorEvent;

    /**
     * Base Command Class - abstract implementation of Command pattern
     * Provides common infrastructure for all application commands
     *
     * Implements core command functionality:
     * - Delayed execution support via Timer
     * - Error handling and event dispatching
     * - Template method pattern for concrete implementations
     * - Integration with command composition system
     */
    public class Command extends EventDispatcher implements ICommand {
        private var _timer:Timer;
        public var title:String;

        /**
         * Base Command constructor
         * @param delay - delay in seconds before command execution (default 0)
         * @param title - optional command title for identification
         */
        public function Command(delay:Number = 0, title:String = null) {
            this.title = title;
            _timer = new Timer(int(1000 * delay), 1);
            _timer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimerComplete);
        }

        /**
         * Timer complete handler
         * @param e - timer completion event
         */
        private function onTimerComplete(e:TimerEvent):void {
            execute();
        }

        /**
         * Start command execution
         * @param e - optional event (not used in base implementation)
         */
        public final function start(e:Event = null):void {
            _timer.start();
        }

        /**
         * Execute command - ICommand interface implementation
         * Wraps internal execution with error handling
         */
        public function execute():void {
            try {
                executeInternal();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, error.message));
            }
        }

        /**
         * Internal command execution - template method
         * Override in child classes with specific command logic
         */
        protected function executeInternal():void {
            complete();
        }

        /**
         * Complete command execution
         * @param e - optional event (not used)
         */
        protected final function complete(e:Event = null):void {
            dispatchEvent(new Event(Event.COMPLETE));
        }
    }
}
 
package Src.Prog.Core.Commands {
    import flash.events.Event;

    /**
     * Command Error Event - specialized event for command system
     * Packages and transmits error information from command execution
     *
     * Used throughout command system to standardize error reporting
     * and enable error handling in composite command structures
     */
    public class CommandErrorEvent extends Event {
        public static const ERROR:String = "commandError";
        public var errorMessage:String;

        /**
         * Command Error Event constructor
         * @param type - event type (use CommandErrorEvent.ERROR)
         * @param message - error description text
         * @param bubbles - event bubbling (default false)
         * @param cancelable - event cancelable (default false)
         */
        public function CommandErrorEvent(type:String, message:String = "", bubbles:Boolean = false, cancelable:Boolean = false) {
            super(type, bubbles, cancelable);
            this.errorMessage = message;
        }

        /**
         * Override clone method
         * @return Event - new event instance with same parameters
         */
        override public function clone():Event {
            return new CommandErrorEvent(type, errorMessage, bubbles, cancelable);
        }

        /**
         * Override toString method
         * @return String - string event description
         */
        override public function toString():String {
            return formatToString("CommandErrorEvent", "type", "errorMessage", "bubbles", "cancelable", "eventPhase");
        }
    }
}
 
package Src.Prog.Core.Commands {
    /**
     * ICommand Interface - base contract for all application commands
     * Defines standard interface for Command pattern implementation
     *
     * Core component of command system - all commands must implement this interface
     * Enables uniform command execution and composition in command sequences
     */
    public interface ICommand {
        /**
         * Execute command - main interface method
         * Starts execution of logic encapsulated in command
         * Implementation should handle command-specific logic and error cases
         */
        function execute():void;
    }
}
 
package Src.Prog.Core.Commands {
    import Src.Prog.Core.Commands.Command;
    import Src.Prog.Core.Commands.CommandErrorEvent;

    /**
     * Function invocation command wrapper
     * Encapsulates arbitrary function calls as command objects for integration with command system
     *
     * Primary use cases:
     * - Integrating legacy code with command pattern
     * - Wrapping simple function calls for command sequences
     * - Rapid prototyping without creating dedicated command classes
     *
     * Usage examples:
     * - new InvokeFunction(someFunction)
     * - new InvokeFunction(object.method, [param1, param2])
     * - new InvokeFunction(closureFunction)
     */
    public class InvokeFunction extends Command {
        /**
         * Function reference to be executed
         * Can be any Function object including methods, closures, or static functions
         */
        public var func:Function;

        /**
         * Optional arguments array for function invocation
         * Passed to function using Function.apply() when provided
         */
        public var args:Array;

        /**
         * Invoke function command constructor
         * @param func - Function object to be executed when command runs
         * @param args - Optional array of arguments to pass to the function (default null)
         */
        public function InvokeFunction(func:Function, args:Array = null) {
            super(0, null);
            this.func = func;
            this.args = args;
        }

        /**
         * Execute command - invoke wrapped function with provided arguments
         * Handles both parameterized and parameter-less function calls
         * Includes error handling for function execution failures
         */
        override protected function executeInternal():void {
            try {
                if (args != null && args.length > 0) {
                    func.apply(null, args);
                } else {
                    func();
                }
                complete();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "InvokeFunction: Function execution failed - " + error.message));
            }
        }
    }
}
 
package Src.Prog.Core.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Core.Commands.ICommand;

    /**
     * Parallel Command - composite command for parallel execution
     * Executes all subcommands simultaneously and completes when all finish
     *
     * Key features:
     * - Concurrent execution of multiple commands
     * - Configurable initial delay
     * - Error handling with proper cleanup
     * - Completion when all subcommands finish
     */
    public class ParallelCommand extends EventDispatcher implements ICommand {
        private var _commands:Array;
        private var _completeCommandCount:int;
        private var _delay:Number;

        /**
         * Parallel Command constructor
         * @param delay - delay in seconds before execution start
         * @param commands - variable number of subcommands for parallel execution
         */
        public function ParallelCommand(delay:Number, ...commands) {
            _delay = delay;

            if (commands.length == 1 && commands[0] is Array) {
                _commands = commands[0];
            } else {
                _commands = commands;
            }

            _completeCommandCount = 0;
        }

        /**
         * Execute parallel command
         * Starts parallel execution process of subcommands
         */
        public function execute():void {
            _completeCommandCount = 0;

            if (_commands.length == 0) {
                dispatchEvent(new Event(Event.COMPLETE));
                return;
            }

            if (_delay > 0) {
                var timer:Timer = new Timer(int(1000 * _delay), 1);
                timer.addEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
                timer.start();
            } else {
                startAllCommands();
            }
        }

        /**
         * Delay completion handler
         * @param e - timer completion event
         */
        private function onDelayComplete(e:TimerEvent):void {
            var timer:Timer = e.target as Timer;
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
            startAllCommands();
        }

        /**
         * Start all subcommands
         * Starts all subcommands simultaneously and subscribes to their events
         */
        private function startAllCommands():void {
            for each (var command:ICommand in _commands) {
                if (command is EventDispatcher) {
                    (command as EventDispatcher).addEventListener(Event.COMPLETE, onSubcommandComplete);
                    (command as EventDispatcher).addEventListener(CommandErrorEvent.ERROR, onSubcommandError);
                }
                command.execute();
            }
        }

        /**
         * Subcommand completion handler
         * @param e - subcommand completion event
         */
        private function onSubcommandComplete(e:Event):void {
            var command:ICommand = e.target as ICommand;

            if (command is EventDispatcher) {
                (command as EventDispatcher).removeEventListener(Event.COMPLETE, onSubcommandComplete);
                (command as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onSubcommandError);
            }

            _completeCommandCount++;

            if (_completeCommandCount == _commands.length) {
                dispatchEvent(new Event(Event.COMPLETE));
            }
        }

        /**
         * Subcommand error handler
         * @param event - subcommand error event
         */
        private function onSubcommandError(event:CommandErrorEvent):void {
            var failedCommand:ICommand = event.target as ICommand;

            if (failedCommand is EventDispatcher) {
                (failedCommand as EventDispatcher).removeEventListener(Event.COMPLETE, onSubcommandComplete);
                (failedCommand as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onSubcommandError);
            }

            cleanupAllListeners();

            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                "Error in parallel command: " + event.errorMessage));
        }

        /**
         * Clean up all listeners
         * Unsubscribes from all subcommands to prevent memory leaks
         */
        private function cleanupAllListeners():void {
            for each (var command:ICommand in _commands) {
                if (command is EventDispatcher) {
                    (command as EventDispatcher).removeEventListener(Event.COMPLETE, onSubcommandComplete);
                    (command as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onSubcommandError);
                }
            }
        }
    }
}
 
package Src.Prog.Core.Commands {
    import Src.Prog.Core.Commands.Command;
    import Src.Prog.Core.Managers.DataManager;

    /**
     * Register Data Command - encapsulates data registration in DataManager
     * Encapsulates data saving operation into command object
     *
     * Provides command pattern interface for data storage operations
     * Enables data registration to be used in command sequences and compositions
     */
    public class RegisterData extends Command {
        public var key:String;
        public var data:*;

        /**
         * Register Data Command constructor
         * @param key - string data identifier
         * @param data - data to save in storage
         */
        public function RegisterData(key:String, data:*) {
            this.key = key;
            this.data = data;
        }

        /**
         * Execute command - register data
         */
        override protected function executeInternal():void {
            DataManager.registerData(key, data);
            complete();
        }
    }
}
 
package Src.Prog.Core.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Core.Commands.ICommand;

    /**
     * Serial Command - composite command for sequential execution
     * Executes subcommands one after another in strict order
     *
     * Key features:
     * - Sequential execution of command arrays
     * - Configurable initial delay
     * - Error propagation from subcommands
     * - Automatic cleanup of event listeners
     */
    public class SerialCommand extends EventDispatcher implements ICommand {
        private var _commands:Array;
        private var _currentIndex:int;
        private var _delay:Number;
        private var _commandId:String;

        /**
         * Serial Command constructor
         * @param delay - delay in seconds before execution start
         * @param commands - variable number of subcommands or command array
         */
        public function SerialCommand(delay:Number, ...commands) {
            _delay = delay;
            _commandId = "SC_" + new Date().getTime() + "_" + Math.random().toString().substr(2, 5);

            if (commands.length == 1 && commands[0] is Array) {
                _commands = commands[0];
            } else {
                _commands = commands;
            }

            _currentIndex = 0;
        }

        /**
         * Execute serial command
         * Starts sequential execution process of subcommands
         */
        public function execute():void {
            if (_commands.length == 0) {
                dispatchEvent(new Event(Event.COMPLETE));
                return;
            }

            if (_delay > 0) {
                var timer:Timer = new Timer(int(1000 * _delay), 1);
                timer.addEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
                timer.start();
            } else {
                executeNextCommand();
            }
        }

        /**
         * Delay completion handler
         * @param e - timer completion event
         */
        private function onDelayComplete(e:TimerEvent):void {
            var timer:Timer = e.target as Timer;
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
            executeNextCommand();
        }

        /**
         * Execute next subcommand
         * Recursive method for sequential command execution
         */
        private function executeNextCommand():void {
            if (_currentIndex >= _commands.length) {
                dispatchEvent(new Event(Event.COMPLETE));
                return;
            }

            var command:ICommand = _commands[_currentIndex] as ICommand;

            if (command) {
                if (command is EventDispatcher) {
                    (command as EventDispatcher).addEventListener(Event.COMPLETE, onCommandComplete);
                    (command as EventDispatcher).addEventListener(CommandErrorEvent.ERROR, onCommandError);
                    command.execute();
                } else {
                    _currentIndex++;
                    executeNextCommand();
                }
            } else {
                _currentIndex++;
                executeNextCommand();
            }
        }

        /**
         * Subcommand completion handler
         * @param event - subcommand completion event
         */
        private function onCommandComplete(event:Event):void {
            var command:ICommand = event.target as ICommand;

            if (command is EventDispatcher) {
                (command as EventDispatcher).removeEventListener(Event.COMPLETE, onCommandComplete);
                (command as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onCommandError);
            }

            _currentIndex++;
            executeNextCommand();
        }

        /**
         * Subcommand error handler
         * @param event - subcommand error event
         */
        private function onCommandError(event:CommandErrorEvent):void {
            var failedCommand:ICommand = event.target as ICommand;

            if (failedCommand is EventDispatcher) {
                (failedCommand as EventDispatcher).removeEventListener(Event.COMPLETE, onCommandComplete);
                (failedCommand as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onCommandError);
            }

            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                "Error in command sequence: " + event.errorMessage));
        }
    }
}
 
package Src.Prog.Core.Commands {
    import Src.Prog.Core.Commands.Command;
    import Src.Prog.Core.Managers.DataManager;

    /**
     * Unregister Data Command - encapsulates data removal from DataManager
     * Encapsulates data clearing operation into command object
     *
     * Provides command pattern interface for data removal operations
     * Enables clean data management within command sequences
     */
    public class UnregisterData extends Command {
        public var key:String;

        /**
         * Unregister Data Command constructor
         * @param key - string data identifier to remove
         */
        public function UnregisterData(key:String) {
            this.key = key;
        }

        /**
         * Execute command - unregister data
         */
        override protected function executeInternal():void {
            DataManager.unregisterData(key);
            complete();
        }
    }
}
 
package Src.Prog.Core.Commands {
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.Commands.Command;
    import Src.Prog.Core.Commands.CommandErrorEvent;

    /**
     * Wait for condition fulfillment command
     * Periodically checks condition until it's met or timeout occurs
     * Uses Timer-based implementation for consistency with command system
     *
     * Typical use cases:
     * - Waiting for resource loading completion
     * - Waiting for system readiness
     * - Waiting for user input confirmation
     */
    public class WaitForCondition extends Command {
        private var _conditionCheck:Function;
        private var _timeoutMs:int;
        private var _checkInterval:int;
        private var _checkTimer:Timer;
        private var _timeoutTimer:Timer;
        private var _isComplete:Boolean;

        /**
         * Wait for condition command constructor
         * @param conditionCheck - function that returns Boolean when condition is met
         * @param timeoutMs - maximum waiting time in milliseconds (default 5000)
         * @param checkInterval - condition check interval in milliseconds (default 100)
         */
        public function WaitForCondition(conditionCheck:Function,
                                       timeoutMs:int = 5000,
                                       checkInterval:int = 100) {
            super();
            this._conditionCheck = conditionCheck;
            this._timeoutMs = timeoutMs;
            this._checkInterval = checkInterval;
            this._isComplete = false;
        }

        /**
         * Execute command - start condition checking process
         * Sets up periodic checking and timeout monitoring
         */
        override protected function executeInternal():void {
            _isComplete = false;

            // Start periodic condition checking
            _checkTimer = new Timer(_checkInterval);
            _checkTimer.addEventListener(TimerEvent.TIMER, onCheckTimer);
            _checkTimer.start();

            // Setup timeout monitoring
            _timeoutTimer = new Timer(_timeoutMs, 1);
            _timeoutTimer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimeout);
            _timeoutTimer.start();

            // Perform immediate first check
            checkCondition();
        }

        /**
         * Check timer handler - periodic condition verification
         * @param event - timer event
         */
        private function onCheckTimer(event:TimerEvent):void {
            if (!_isComplete) {
                checkCondition();
            }
        }

        /**
         * Timeout handler - condition not met within specified time
         * @param event - timeout timer completion event
         */
        private function onTimeout(event:TimerEvent):void {
            if (!_isComplete) {
                cleanupTimers();
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "WaitForCondition: Timeout reached after " + _timeoutMs + "ms"));
                complete();
            }
        }

        /**
         * Condition checking logic
         * Evaluates condition function and completes if condition is met
         */
        private function checkCondition():void {
            try {
                if (_conditionCheck()) {
                    _isComplete = true;
                    cleanupTimers();
                    complete();
                }
            } catch (error:Error) {
                _isComplete = true;
                cleanupTimers();
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "WaitForCondition: Condition check failed - " + error.message));
                complete();
            }
        }

        /**
         * Clean up timer resources
         * Stops and removes event listeners from both timers
         */
        private function cleanupTimers():void {
            if (_checkTimer) {
                _checkTimer.stop();
                _checkTimer.removeEventListener(TimerEvent.TIMER, onCheckTimer);
                _checkTimer = null;
            }

            if (_timeoutTimer) {
                _timeoutTimer.stop();
                _timeoutTimer.removeEventListener(TimerEvent.TIMER_COMPLETE, onTimeout);
                _timeoutTimer = null;
            }
        }

        /**
         * Command completion override
         * Ensures proper resource cleanup on completion
         */
        override protected function complete(e:Event = null):void {
            cleanupTimers();
            super.complete(e);
        }
    }
}
 
package Src.Prog.Core.Managers {
    import flash.utils.Dictionary;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.IAtomView;
    import flash.geom.Point;
    import Src.Prog.Core.Window;
    import flash.display.DisplayObject;
    import Src.Prog.Com.Atoms.Core.AtomFactory;

    /**
     * Manages atoms in the application - creation, deletion, and tracking.
     * Integrates with MultiPulsator for system communication.
     */
    public class AtomManager {
        private static var _instance:AtomManager;
        private var _atoms:Dictionary; // atomId -> {atom: BaseAtom, view: IAtomView}
        private var _windowAtoms:Dictionary; // windowType -> array of atomIds

        public static function getInstance():AtomManager {
            if (!_instance) {
                _instance = new AtomManager();
            }
            return _instance;
        }

        public function AtomManager() {
            _atoms = new Dictionary();
            _windowAtoms = new Dictionary();
            setupImpulseListeners();
        }

        /**
         * Sets up impulse listeners for atom management.
         */
        private function setupImpulseListeners():void {
            MultiPulsator.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.subscribeToImpulse("ATOM_DELETE_REQUEST", onAtomDeleteRequest);
        }

        /**
         * Handles atom creation from context menu selection.
         * @param impulse ATOM_CONTEXT_MENU_SELECTED impulse
         */
		private function onAtomContextMenuSelected(impulse:Impulse):void {
			var atomType:String = impulse.data.atomType;
			var position:Point = impulse.data.position;

			trace("AtomManager: Creating atom of type: " + atomType + " at position: " + position);

			// Проверка инициализации AtomFactory
			if (!DataManager.hasData(AtomFactory.REGISTRY_KEY)) {
				trace("ERROR: AtomFactory not initialized!");
				return;
			}

			var atomInfo:Object = AtomFactory.createAtom(atomType, position);
			if (atomInfo && atomInfo.atom && atomInfo.view) {
				addAtomToWindow("Editor", atomInfo.atom, atomInfo.view);
				trace("SUCCESS: Atom created and added to window");
			} else {
				trace("ERROR: Failed to create atom - atomInfo: " + atomInfo);
			}
		}

        /**
         * Handles atom movement updates.
         * @param impulse ATOM_MOVED impulse
         */
        private function onAtomMoved(impulse:Impulse):void {
            var newAtom:BaseAtom = impulse.data.newAtom;
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                // Update the view's reference to the new atom
                _atoms[newAtom.id].view.updateAtomReference(newAtom);
            }
        }

        /**
         * Handles atom deletion requests.
         * @param impulse ATOM_DELETE_REQUEST impulse
         */
        private function onAtomDeleteRequest(impulse:Impulse):void {
            var atom:BaseAtom = impulse.data.atom;
            removeAtom(atom.id);
        }

        /**
         * Adds an atom to a specific window.
         * @param windowType The type of window ("Editor", "Device")
         * @param atom The atom instance
         * @param view The atom view
         */
		public function addAtomToWindow(windowType:String, atom:BaseAtom, view:IAtomView):void {
			trace("Adding atom to window: " + windowType + ", atom: " + atom.id);

			if (!_windowAtoms[windowType]) {
				_windowAtoms[windowType] = [];
			}

			_atoms[atom.id] = { atom: atom, view: view };
			_windowAtoms[windowType].push(atom.id);

			var windowsManager:WindowsManager = WindowsManager.getInstance();
			var window:Window = windowsManager.findWindow(windowType);

			if (window && window.contentLayer) {
				window.contentLayer.addChild(view as DisplayObject);

				// Установка позиции
				(view as DisplayObject).x = atom.position.x;
				(view as DisplayObject).y = atom.position.y;

				trace("SUCCESS: Atom view added to contentLayer at: " + atom.position);

				MultiPulsator.emit(new Impulse("ATOM_ADDED", {
					windowType: windowType,
					atom: atom,
					view: view
				}));
			} else {
				trace("ERROR: Window or contentLayer not found for: " + windowType);
				if (!window) trace("Window not found");
				if (window && !window.contentLayer) trace("contentLayer not found");
			}
		}

        /**
         * Removes an atom by ID.
         * @param atomId The ID of the atom to remove
         */
        public function removeAtom(atomId:String):void {
            if (_atoms[atomId]) {
                var atomData:Object = _atoms[atomId];

                // Remove view from display
                if (atomData.view && atomData.view.parent) {
                    atomData.view.parent.removeChild(atomData.view as flash.display.DisplayObject);
                }

                // Clean up
                atomData.view.dispose();
                delete _atoms[atomId];

                // Remove from window tracking
                for (var windowType:String in _windowAtoms) {
                    var atomIds:Array = _windowAtoms[windowType];
                    var index:int = atomIds.indexOf(atomId);
                    if (index !== -1) {
                        atomIds.splice(index, 1);
                        break;
                    }
                }

                MultiPulsator.emit(new Impulse("ATOM_REMOVED", {
                    atomId: atomId
                }));
            }
        }

        /**
         * Gets all atoms for a specific window.
         * @param windowType The window type
         * @return Array of atom data objects
         */
        public function getAtomsForWindow(windowType:String):Array {
            var result:Array = [];
            if (_windowAtoms[windowType]) {
                for each (var atomId:String in _windowAtoms[windowType]) {
                    if (_atoms[atomId]) {
                        result.push(_atoms[atomId]);
                    }
                }
            }
            return result;
        }

        /**
         * Updates an atom in the manager.
         * @param newAtom The updated atom instance
         */
        public function updateAtom(newAtom:BaseAtom):void {
            if (_atoms[newAtom.id]) {
                _atoms[newAtom.id].atom = newAtom;
                _atoms[newAtom.id].view.updateAtomReference(newAtom);
            }
        }
    }
}
 
package Src.Prog.Core.Managers {
    import flash.utils.Dictionary;

    /**
     * Data Manager - centralized key-value storage for application
     * Provides static interface for global data management
     *
     * Key features:
     * - Global data storage with unique string keys
     * - Thread-safe access through static methods
     * - Support for any data type
     * - Integration with RegisterData and UnregisterData commands
     */
    public class DataManager {
        // Private static dictionary for data storage
        private static var _data:Dictionary = new Dictionary();

        /**
         * Get data by key
         * @param key - string data identifier
         * @return * - data associated with key or undefined if not found
         */
        public static function getData(key:String):* {
            return _data[key];
        }

        /**
         * Register data in storage
         * @param key - unique string data identifier
         * @param data - data to save (any type)
         */
        public static function registerData(key:String, data:*):void {
            _data[key] = data;
        }

        /**
         * Remove data from storage
         * @param key - string data identifier to remove
         */
        public static function unregisterData(key:String):void {
            delete _data[key];
        }

        /**
         * Complete storage cleanup
         * Removes all data from global storage
         */
        public static function clearData():void {
            for (var key:String in _data) {
                delete _data[key];
            }
        }

        /**
         * Check data existence
         * @param key - string data identifier
         * @return Boolean - true if data exists
         */
        public static function hasData(key:String):Boolean {
            return _data[key] !== undefined;
        }

        /**
         * Get all keys
         * @return Array - array of all registered keys
         */
        public static function getAllKeys():Array {
            var keys:Array = [];
            for (var key:String in _data) {
                keys.push(key);
            }
            return keys;
        }
    }
}
 
package Src.Prog.Core.Managers {
    import flash.events.Event;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Com.Atoms.Core.AtomFactory;

    /**
     * Director - main initialization pipeline manager
     * Coordinates application startup sequence using command pattern
     */
    public class Director {
        private static var _initSequence:SerialCommand;

        /**
         * Start main initialization pipeline
         */
        public static function Start():void {
            trace("Director: Starting initialization pipeline");

            _initSequence = new SerialCommand(0,
                new InvokeFunction(initializeCoreSystems),
                new InvokeFunction(WindowsManager.createWindows),
                new InvokeFunction(initializeAtomSystem),
                new InvokeFunction(finalizeInitialization)
            );

            _initSequence.addEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.addEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence.execute();
        }

        /**
         * Initialize core systems
         */
        private static function initializeCoreSystems():void {
            trace("Director: Initializing core systems");
            MultiPulsator.emit(new Impulse("CORE_SYSTEMS_INITIALIZED"));
        }

        /**
         * Initialize atom system
         */
        private static function initializeAtomSystem():void {
            trace("Director: Initializing atom system");

            // Initialize AtomFactory
            try {
                AtomFactory.initialize();
                trace("AtomFactory initialized");
            } catch (error:Error) {
                trace("Error initializing AtomFactory: " + error.message);
            }

            // Initialize AtomManager
            try {
                AtomManager.getInstance();
                trace("AtomManager initialized");
            } catch (error:Error) {
                trace("Error initializing AtomManager: " + error.message);
            }

            MultiPulsator.emit(new Impulse("ATOM_SYSTEM_INITIALIZED"));
        }

        /**
         * Final initialization procedure
         */
        private static function finalizeInitialization():void {
            trace("Director: Finalizing initialization");
            MultiPulsator.emit(new Impulse("APP_READY"));
        }

        /**
         * Pipeline completion handler
         */
        private static function onInitSequenceComplete(event:Event):void {
            trace("Director: Initialization complete");
            MultiPulsator.emit(new Impulse("APP_STARTUP_COMPLETE"));

            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Pipeline error handler
         */
        private static function onInitSequenceError(event:CommandErrorEvent):void {
            trace("Director: Initialization error: " + event.errorMessage);
            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Force initialization abort
         */
        public static function abortInitialization():void {
            trace("Director: Aborting initialization");
            if (_initSequence) {
                _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
                _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
                _initSequence = null;
            }
        }
    }
}
 
package Src.Prog.Core.Managers {
    import flash.events.Event;
    import flash.system.Capabilities;

    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.ICommand;
    import Src.Prog.Main;

    /**
     * Unified Window Manager - handles all window operations across platforms
     * Manages window creation, lifecycle, and platform-specific behavior
     *
     * Responsibilities:
     * - Platform-aware window creation (Desktop vs Mobile)
     * - Window instance management and access
     * - Coordination with application initialization system
     * - MultiPulsator integration for window events
     */
    public class WindowsManager {
        private static var _instance:WindowsManager;
        public var nativeWindow:Window;
        public var editorWindow:Window;
        public var deviceWindow:Window;

        // Platform detection
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 ||
                                               Capabilities.os.indexOf("Mac") >= 0 ||
                                               Capabilities.os.indexOf("Linux") >= 0;

        /**
         * Get singleton instance
         * @return WindowsManager - Singleton instance
         */
        public static function getInstance():WindowsManager {
            if (!_instance) {
                _instance = new WindowsManager();
            }
            return _instance;
        }

        /**
         * Create application windows based on platform capabilities
         * Desktop: Multiple windows, Mobile: Single window with adaptive UI
         */
        public static function createWindows():void {
            var manager:WindowsManager = getInstance();
            manager.nativeWindow = Main.root.stage.nativeWindow as Window;

            // Platform-specific window creation strategy
            if (_isDesktop) {
                // Desktop environment: multiple independent windows
                manager.editorWindow = new Window("Editor", {
                    x: 100, y: 100, width: 1100, height: 600, title: "Editor"
                });
                manager.editorWindow.activate();

                manager.deviceWindow = new Window("Device", {
                    x: 1200, y: 100, width: 640, height: 480, title: "Device"
                });
                manager.deviceWindow.activate();
            } else {
                // Mobile environment: single primary window
                manager.editorWindow = new Window("Editor", {
                    title: "Editor"
                });
                manager.editorWindow.activate();
            }

            // Signal window creation completion
            MultiPulsator.emit(new Impulse("APP_WINDOWS_READY", {
                windows: manager.getAllWindows(),
                platform: _isDesktop ? "desktop" : "mobile"
            }));
        }

        /**
         * Find window by type identifier
         * @param type - Window type to locate
         * @return Window - Found window or null
         */
        public function findWindow(type:String):Window {
            switch(type.toLowerCase()) {
                case "editor": return editorWindow;
                case "device": return deviceWindow;
                case "native": return nativeWindow;
                default: return null;
            }
        }

        /**
         * Close all application windows
         * Performs clean shutdown of window resources
         */
        public function closeAllWindows():void {
            if (editorWindow) editorWindow.close();
            if (deviceWindow) deviceWindow.close();
        }

        /**
         * Get all window references
         * @return Object - Collection of window references
         */
        public function getAllWindows():Object {
            return {
                native: nativeWindow,
                editor: editorWindow,
                device: deviceWindow
            };
        }

        /**
         * Command interface for window creation
         * Provides ICommand-compatible interface for Director integration
         * @return ICommand - Window creation command
         */
        public static function Run():ICommand {
            return new InvokeFunction(createWindows);
        }
    }
}
 
package Src.Prog.Core.MultiPulsator {
    /**
     * Base interface for impulses - data contract for communication system
     * Defines standard interface for all messages transmitted via MultiPulsator
     *
     * Core contract for all application messages ensuring consistent
     * data structure across the event-driven architecture
     */
    public interface IImpulse {
        /**
         * Impulse type - message identifier
         * Used by MultiPulsator for message routing to subscribers
         * @return String - impulse type identifier
         */
        function get type():String;

        /**
         * Impulse data - message payload
         * Contains arbitrary data associated with the impulse
         * @return Object - impulse data payload
         */
        function get data():Object;
    }
}
 
package Src.Prog.Core.MultiPulsator {
    /**
     * Impulse implementation - concrete message container for MultiPulsator system
     * Universal data container providing standardized message format and type safety
     *
     * Primary message vehicle for inter-module communication
     * Implements IImpulse interface for consistent message handling
     */
    public class Impulse implements IImpulse {
        private var _type:String;
        private var _data:Object;

        /**
         * Constructor - creates new impulse with specified type and data
         * @param type - impulse type identifier
         * @param data - optional data payload (default null)
         */
        public function Impulse(type:String, data:Object = null) {
            _type = type;
            _data = data;
        }

        /**
         * Get impulse type - string identifier
         * @return String - impulse type
         */
        public function get type():String {
            return _type;
        }

        /**
         * Get impulse data - payload object
         * @return Object - impulse data
         */
        public function get data():Object {
            return _data;
        }
    }
}
 
package Src.Prog.Core.MultiPulsator {
    import flash.utils.Dictionary;

    /**
     * Impulse management system - application communication core
     * Implements Publisher-Subscriber pattern for asynchronous communication between components via impulses
     *
     * Key features:
     * - Centralized messaging between modules
     * - Multiple subscribers per impulse type support
     * - Thread-safe Singleton pattern
     * - Impulse validation and error handling
     */
    public class MultiPulsator {
        // Singleton pattern static variable
        private static var instance:MultiPulsator;

        // Dictionary for subscribers: key - impulse type, value - array of handler functions
        private var impulseListeners:Dictionary;

        /**
         * Constructor - initializes subscriber storage system
         * Private constructor as part of Singleton pattern implementation
         */
        public function MultiPulsator() {
            impulseListeners = new Dictionary();
        }

        /**
         * Debug method - outputs information about subscribers
         * Provides insight into current subscription state for debugging
         */
        public static function getImpulseListeners():void {
            var dict:Dictionary = getInstance().impulseListeners;
            var count:int = 0;

            // Count unique impulse types
            for (var key:* in dict) {
                count++;
            }
        }

        /**
         * Get Singleton instance - main access point to impulse system
         * Creates instance on first access (lazy initialization)
         * @return MultiPulsator - single system instance
         */
        public static function getInstance():MultiPulsator {
            if (!instance) {
                instance = new MultiPulsator();
            }
            return instance;
        }

        /**
         * Subscribe to impulse (static interface)
         * Convenient static wrapper for impulse subscription
         * @param type - impulse type to subscribe to
         * @param listener - impulse handler function
         */
        public static function subscribeToImpulse(type:String, listener:Function):void {
            getInstance().addImpulseListener(type, listener);
        }

        /**
         * Add impulse subscriber
         * Registers handler function for specified impulse type
         * @param type - impulse type to subscribe to
         * @param listener - function to be called when impulse is received
         */
        public function addImpulseListener(type:String, listener:Function):void {
            // Create array for impulse type if it doesn't exist
            if (!impulseListeners[type]) {
                impulseListeners[type] = [];
            }
            // Add listener to array
            impulseListeners[type].push(listener);
        }

        /**
         * Send impulse (static interface)
         * Convenient static wrapper for impulse sending
         * @param impulse - impulse object to send
         */
        public static function emit(impulse:Impulse):void {
            getInstance().fireImpulse(impulse);
        }

        /**
         * Main impulse sending method
         * Validates impulse and distributes to all subscribed listeners
         * @param impulse - impulse object to process
         */
        public function fireImpulse(impulse:Impulse):void {
            // Check for subscribers for this impulse type
            if (impulseListeners[impulse.type]) {
                // Call all registered listeners
                for each(var listener:Function in impulseListeners[impulse.type]) {
                    listener(impulse);
                }
            }
        }

        /**
         * Unsubscribe from impulse (static interface)
         * Convenient static wrapper for subscription removal
         * @param type - impulse type to unsubscribe from
         * @param listener - function to remove from subscribers
         */
        public static function removeImpulse(type:String, listener:Function):void {
            getInstance().removeImpulseListener(type, listener);
        }

        /**
         * Remove subscriber from system
         * Removes function from handlers for specified impulse type
         * @param type - impulse type
         * @param listener - function to remove
         */
        public function removeImpulseListener(type:String, listener:Function):void {
            if (impulseListeners[type]) {
                var index:int = impulseListeners[type].indexOf(listener);
                if (index != -1) {
                    // Remove listener from array
                    impulseListeners[type].splice(index, 1);

                    // Clear entry if no listeners remain
                    if (impulseListeners[type].length == 0) {
                        delete impulseListeners[type];
                    }
                }
            }
        }
    }
}
 
package Src.Prog.Core {
    import flash.display.NativeWindow;
    import flash.display.NativeWindowInitOptions;
    import flash.display.NativeWindowSystemChrome;
    import flash.display.NativeWindowType;
    import flash.display.Sprite;
    import flash.display.StageQuality;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.KeyboardEvent;
    import flash.events.FocusEvent;
    import flash.events.NativeWindowDisplayStateEvent;
    import flash.system.Capabilities;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.ui.Keyboard;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.display.DisplayObject;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Menus.AtomCreationContextMenu;
    import Src.Prog.Com.Menus.AtomContextMenuItem;

    /**
     * Universal Window with integrated canvas, pan/zoom, and detailed impulse system.
     * Provides layered content system and transforms native events into precise impulses.
     */
    public class Window extends NativeWindow {
        /** Window type identifier */
        private var _type:String;

        /** Main content container */
        private var _content:Sprite;

        // =========================================================================
        // CANVAS SYSTEM - Integrated pan/zoom functionality
        // =========================================================================

        /** Main canvas for pan/zoom operations */
        private var _canvas:Sprite;

        /** Background layer - static background elements */
        private var _backgroundLayer:Sprite;

        /** Content layer - dynamic elements that move with canvas (atoms, tracks) */
        private var _contentLayer:Sprite;

        /** Overlay layer - temporary elements (drag previews, UI) */
        private var _overlayLayer:Sprite;

		/** layer for Tracks */
		private var _trackLayer:Sprite;

        /** Current viewport position for panning */
        private var _viewPoint:Point = new Point(0, 0);

        /** Current zoom level */
        private var _zoomLevel:Number = 1.0;

        /** Dragging state for panning */
        private var _isDragging:Boolean = false;

        /** Last mouse position for movement calculations */
        private var _lastMousePos:Point = new Point();

        /** Zoom constraints */
        private static const ZOOM_MIN:Number = 0.1;
        private static const ZOOM_MAX:Number = 0.3;
        private static const ZOOM_STEP:Number = 0.03;

        /** Platform detection */
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 ||
                                               Capabilities.os.indexOf("Mac") >= 0 ||
                                               Capabilities.os.indexOf("Linux") >= 0;

        /**
         * Universal Window constructor
         * @param type Window type identifier ("Editor", "Device", etc.)
         * @param config Configuration object for window properties (optional)
         */
        public function Window(type:String, config:Object = null) {
            var options:NativeWindowInitOptions = new NativeWindowInitOptions();
            options.type = NativeWindowType.NORMAL;
            options.systemChrome = NativeWindowSystemChrome.STANDARD;
            options.transparent = false;

            super(options);

            _type = type;
            var actualConfig:Object = config || {};

            // Configure window properties
            this.title = actualConfig.title || type + " Window";
            this.alwaysInFront = true;

            // Platform-specific sizing and positioning
            if (_isDesktop) {
                this.bounds = new Rectangle(
                    actualConfig.x || 100,
                    actualConfig.y || 100,
                    actualConfig.width || 800,
                    actualConfig.height || 600
                );
            } else {
                // Mobile - full screen
                this.bounds = new Rectangle(0, 0,
                    Capabilities.screenResolutionX,
                    Capabilities.screenResolutionY);
            }

            // Setup event to impulse transformers
            setupEventToImpulseTransformers();

            // Initialize content when stage is available
            if (stage) {
                initializeContent();
            } else {
                addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            }
        }

        /**
         * Handler when window is added to stage
         * @param event ADDED_TO_STAGE event
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            initializeContent();
        }

        /**
         * Setup all event listeners that transform native events into impulses
         */
        private function setupEventToImpulseTransformers():void {
            // Window lifecycle events
            addEventListener(Event.ACTIVATE, transformWindowActivate);
            addEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            addEventListener(Event.CLOSING, transformWindowClosing);
            addEventListener(Event.RESIZE, transformWindowResize);
            addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);

            // Mouse events with pin detection
            addEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            addEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            addEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            addEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
            addEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
            addEventListener(MouseEvent.CLICK, transformClick);
        }

        /**
         * Initialize window content based on window type
         */
        private function initializeContent():void {
            try {
                _content = new Sprite();
                _content.name = "Content";
                stage.quality = StageQuality.BEST;
                stage.addChild(_content);

                // Initialize canvas system
                initializeCanvasSystem();

                // Type-specific content
                switch(_type) {
                    case "Editor":
                        setupEditorContent();
                        break;
                    case "Device":
                        setupDeviceContent();
                        break;
                    default:
                        setupDefaultContent();
                }

                // Center canvas initially
                centerCanvas();

            } catch (error:Error) {
                trace("Window content initialization error: " + error.message);
            }
        }

        /**
         * Initialize canvas system with pan/zoom functionality
         */
        private function initializeCanvasSystem():void {
            // Create main canvas container
            _canvas = new Sprite();
            _canvas.name = "Canvas";
            _content.addChild(_canvas);

            // Create background layer for static elements
            _backgroundLayer = new Sprite();
            _backgroundLayer.name = "BackgroundLayer";
            _backgroundLayer.mouseEnabled = true;
            _backgroundLayer.doubleClickEnabled = true;
            _backgroundLayer.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onBackgroundRightClick);
            _canvas.addChild(_backgroundLayer);

            // Create content layer for dynamic elements (atoms, tracks)
            _contentLayer = new Sprite();
            _contentLayer.name = "ContentLayer";
            _contentLayer.mouseEnabled = true;
            _contentLayer.doubleClickEnabled = true;
            _canvas.addChild(_contentLayer);



            // Create overlay layer for temporary elements
            _overlayLayer = new Sprite();
            _overlayLayer.name = "OverlayLayer";
            _overlayLayer.mouseEnabled = false; // Disable for menus so clicks pass through
            _overlayLayer.mouseChildren = true; // But allow children to be interactive
            _canvas.addChild(_overlayLayer);

            // Setup viewport controls
            setupViewportControls();
        }

        /**
         * Background right click handler
         */
        private function onBackgroundRightClick(event:MouseEvent):void {
            if (_type == "Editor") {
                showContextMenu(new Point(event.stageX, event.stageY));
                event.stopPropagation();
            }
        }

        /**
         * Setup viewport controls for pan/zoom operations
         */
        private function setupViewportControls():void {
            stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeave);
            stage.addEventListener(Event.RESIZE, onStageResize);
        }

        /**
         * Center canvas on stage and reset viewport - FROM WORKING VERSION
         */
        private function centerCanvas():void {
            _canvas.x = stage.stageWidth / 2;
            _canvas.y = stage.stageHeight / 2;
            _viewPoint.setTo(0, 0);
            _zoomLevel = 0.1;
            updateViewport();
        }

        /**
         * Mouse wheel handler for zoom operations - FROM WORKING VERSION
         * @param event Mouse wheel event
         */
        private function onMouseWheel(event:MouseEvent):void {
            var mouseStageX:Number = stage.mouseX;
            var mouseStageY:Number = stage.mouseY;
            var mouseLocalBefore:Point = _canvas.globalToLocal(new Point(mouseStageX, mouseStageY));

            var oldZoom:Number = _zoomLevel;
            _zoomLevel += (event.delta > 0) ? ZOOM_STEP : -ZOOM_STEP;
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, _zoomLevel));

            updateViewport();

            var mouseLocalAfter:Point = _canvas.globalToLocal(new Point(mouseStageX, mouseStageY));
            var scaleRatio:Number = _zoomLevel / oldZoom;
            _viewPoint.x += (mouseLocalAfter.x - mouseLocalBefore.x) * scaleRatio;
            _viewPoint.y += (mouseLocalAfter.y - mouseLocalBefore.y) * scaleRatio;

            updateViewport();

            MultiPulsator.emit(new Impulse("CANVAS_ZOOM_CHANGED", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

        /**
         * Middle mouse down handler - start panning - FROM WORKING VERSION
         * @param event Middle mouse button down event
         */
        private function onMiddleMouseDown(event:MouseEvent):void {
            _isDragging = true;
            _lastMousePos.setTo(stage.mouseX, stage.mouseY);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Mouse drag handler - update panning position - FROM WORKING VERSION
         * @param event Mouse move event during drag
         */
        private function onMouseDrag(event:MouseEvent):void {
            if (_isDragging) {
                var currentMousePos:Point = new Point(stage.mouseX, stage.mouseY);
                var dx:Number = currentMousePos.x - _lastMousePos.x;
                var dy:Number = currentMousePos.y - _lastMousePos.y;

                _viewPoint.x += dx / _zoomLevel;
                _viewPoint.y += dy / _zoomLevel;

                updateViewport();
                _lastMousePos = currentMousePos;

                MultiPulsator.emit(new Impulse("CANVAS_PANNED", {
                    windowType: _type,
                    viewPoint: _viewPoint.clone(),
                    movement: new Point(dx, dy)
                }));
            }
        }

        /**
         * Middle mouse up handler - end panning - FROM WORKING VERSION
         * @param event Middle mouse button up event
         */
        private function onMiddleMouseUp(event:MouseEvent):void {
            _isDragging = false;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Mouse leave handler - cancel ongoing operations - FROM WORKING VERSION
         * @param event Mouse leave event
         */
        private function onMouseLeave(event:Event):void {
            _isDragging = false;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Stage resize handler
         * @param event Stage resize event
         */
        private function onStageResize(event:Event):void {
            updateViewport();
            MultiPulsator.emit(new Impulse("CANVAS_RESIZED", {
                windowType: _type,
                stageWidth: stage.stageWidth,
                stageHeight: stage.stageHeight
            }));
        }

        /**
         * Update viewport transformation based on current zoom and position - FROM WORKING VERSION
         */
        private function updateViewport():void {
            _canvas.scaleX = _canvas.scaleY = _zoomLevel;
            _canvas.x = stage.stageWidth / 2 + _viewPoint.x * _zoomLevel;
            _canvas.y = stage.stageHeight / 2 + _viewPoint.y * _zoomLevel;
        }

        // =========================================================================
        // CONTEXT MENU HANDLING - FROM NEW VERSION
        // =========================================================================

        /**
         * Transform right mouse down event to show context menu
         * @param event Native right mouse down event
         */
        private function transformRightMouseDown(event:MouseEvent):void {
            // Only show context menu in Editor window
            if (_type != "Editor") {
                return;
            }

            // Check if click was on background or content (not on pins or existing menus)
            var target:DisplayObject = event.target as DisplayObject;
            while (target && target != stage) {
                if (target is Pin || target is AtomContextMenuItem) {
                    return;
                }
                target = target.parent;
            }

            showContextMenu(new Point(event.stageX, event.stageY));

            // Prevent default context menu
            event.stopPropagation();
        }

        /**
         * Transform right mouse up event
         * @param event Native right mouse up event
         */
        private function transformRightMouseUp(event:MouseEvent):void {
            // Don't prevent propagation here to allow menu items to work
        }

        /**
         * Transform click event
         * @param event Native click event
         */
        private function transformClick(event:MouseEvent):void {
            // Close context menus on any click (except right click)
            if (event.target != _overlayLayer && !(event.target is AtomContextMenuItem)) {
                closeContextMenus();
            }
        }

        /**
         * Show context menu at specified stage coordinates
         * @param stagePos Stage coordinates where menu should appear
         */
        private function showContextMenu(stagePos:Point):void {
            // Close any existing menus
            closeContextMenus();

            try {
                // Convert stage coordinates to overlay layer coordinates
                var overlayPos:Point = _overlayLayer.globalToLocal(stagePos);
                var contentPos:Point = _contentLayer.globalToLocal(stagePos);

                // Create context menu
                var contextMenu:AtomCreationContextMenu = new AtomCreationContextMenu(overlayPos, contentPos);
                _overlayLayer.addChild(contextMenu);

				// Debug: add marker at click position
				addDebugMarker(contentPos);

                MultiPulsator.emit(new Impulse("WINDOW_RIGHT_CLICK", {
                    windowType: _type,
                    window: this,
                    globalPosition: stagePos,
                    localPosition: contentPos
                }));

            } catch (error:Error) {
                trace("ERROR creating context menu: " + error.message);
            }
        }

        /**
         * Close any open context menus
         */
        public function closeContextMenus():void {
            for (var i:int = _overlayLayer.numChildren - 1; i >= 0; i--) {
                var child:DisplayObject = _overlayLayer.getChildAt(i);
                if (child is AtomCreationContextMenu) {
                    _overlayLayer.removeChildAt(i);
                }
            }
        }

        // =========================================================================
        // CONTENT SETUP METHODS - FROM NEW VERSION WITH IMPROVEMENTS
        // =========================================================================

        /**
         * Set up editor-specific content
         */
        private function setupEditorContent():void {
            // Clear any existing graphics
            _backgroundLayer.graphics.clear();

            // Draw background with reasonable size
            _backgroundLayer.graphics.beginFill(0x1a1a2e, 1.0);
            _backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
            _backgroundLayer.graphics.endFill();

            // Add subtle grid
            drawGrid();

            // Add informative text
            var info:TextField = createLabel("Editor - Right click to add atoms\nMouse wheel: Zoom\nMiddle mouse: Pan", -380, -280);
            _contentLayer.addChild(info);
        }

        /**
         * Draw grid on background for better orientation
         */
        private function drawGrid():void {
            var gridSize:int = 10;
            var gridColor:uint = 0x2d2d4d;
            var gridAlpha:Number = 0.5;

            _backgroundLayer.graphics.lineStyle(1, gridColor, gridAlpha);

            // Vertical lines
            for (var x:int = -400; x <= 400; x += gridSize) {
                _backgroundLayer.graphics.moveTo(x, -300);
                _backgroundLayer.graphics.lineTo(x, 300);
            }

            // Horizontal lines
            for (var y:int = -300; y <= 300; y += gridSize) {
                _backgroundLayer.graphics.moveTo(-400, y);
                _backgroundLayer.graphics.lineTo(400, y);
            }
        }

        /**
         * Set up device-specific content
         */
        private function setupDeviceContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x077770, 1.0);
            _backgroundLayer.graphics.drawRect(-320, -240, 640, 480);
            _backgroundLayer.graphics.endFill();

            var info:TextField = createLabel("Device Window", 10, 10);
            _contentLayer.addChild(info);

            if (!_isDesktop) {
                this.alwaysInFront = false;
            }
        }

        /**
         * Set up default content
         */
        private function setupDefaultContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x333333, 1.0);
            _backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
            _backgroundLayer.graphics.endFill();

            var info:TextField = createLabel(_type + " Window", 10, 10);
            _contentLayer.addChild(info);
        }

        /**
         * Create standardized text label
         * @param text Label text content
         * @param x Horizontal position
         * @param y Vertical position
         * @return Configured text field
         */
        private function createLabel(text:String, x:Number, y:Number):TextField {
            var label:TextField = new TextField();
            label.width = 400;
            label.height = 60;
            label.x = x;
            label.y = y;
            label.background = false;
            label.textColor = 0xFFFFFF;
            label.selectable = false;
            label.multiline = true;
            label.wordWrap = true;

            var format:TextFormat = new TextFormat();
            format.font = "Verdana";
            format.size = 12;
            format.color = 0xFFFFFF;
            label.defaultTextFormat = format;
            label.text = text;

            return label;
        }

        // =========================================================================
        // EVENT TRANSFORMER METHODS - Convert native events to impulses
        // =========================================================================

        /**
         * Transform mouse down event with pin detection
         * @param event Native mouse down event
         */
        private function transformMouseDown(event:MouseEvent):void {
            // Close any open context menus on regular left click
            if (!event.ctrlKey) {
                closeContextMenus();
            }

            var targetPin:Pin = getPinFromTarget(event.target as DisplayObject);

            if (targetPin) {
                MultiPulsator.emit(new Impulse("PIN_MOUSE_DOWN", {
                    pin: targetPin,
                    windowType: _type,
                    localX: event.localX,
                    localY: event.localY,
                    stageX: event.stageX,
                    stageY: event.stageY,
                    ctrlKey: event.ctrlKey,
                    altKey: event.altKey,
                    shiftKey: event.shiftKey
                }));
            }

            // Emit general window mouse down
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_DOWN", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                target: event.target
            }));
        }

        /**
         * Transform mouse up event with pin detection
         * @param event Native mouse up event
         */
        private function transformMouseUp(event:MouseEvent):void {
            var targetPin:Pin = getPinFromTarget(event.target as DisplayObject);

            if (targetPin) {
                MultiPulsator.emit(new Impulse("PIN_MOUSE_UP", {
                    pin: targetPin,
                    windowType: _type,
                    localX: event.localX,
                    localY: event.localY,
                    stageX: event.stageX,
                    stageY: event.stageY
                }));
            }

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_UP", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                target: event.target
            }));
        }

        /**
         * Transform mouse move event
         * @param event Native mouse move event
         */
        private function transformMouseMove(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_MOVE", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                movementX: event.localX - _lastMousePos.x,
                movementY: event.localY - _lastMousePos.y
            }));

            _lastMousePos.setTo(event.localX, event.localY);
        }

        /**
         * Transform mouse wheel event
         * @param event Native mouse wheel event
         */
        private function transformMouseWheel(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_WHEEL", {
                windowType: _type,
                window: this,
                delta: event.delta,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY
            }));
        }

        /**
         * Helper method to find Pin from any display object in hierarchy
         * @param target Starting display object
         * @return Found Pin or null
         */
        private function getPinFromTarget(target:DisplayObject):Pin {
            var current:DisplayObject = target;
            while (current && !(current is Pin) && current.parent) {
                current = current.parent;
            }
            return current as Pin;
        }

        // =========================================================================
        // WINDOW EVENT TRANSFORMERS
        // =========================================================================

        private function transformWindowActivate(event:Event):void {
            if (!_content) initializeContent();
            MultiPulsator.emit(new Impulse("WINDOW_ACTIVATED", {
                windowType: _type,
                window: this
            }));
        }

        private function transformWindowDeactivate(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_DEACTIVATED", {
                windowType: _type,
                window: this
            }));
        }

        private function transformWindowClosing(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_CLOSING", {
                windowType: _type,
                window: this
            }));
            MultiPulsator.emit(new Impulse("APP_CLOSE"));
        }

        private function transformWindowResize(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_RESIZED", {
                windowType: _type,
                window: this,
                width: this.width,
                height: this.height
            }));
        }

        private function transformDisplayStateChange(event:NativeWindowDisplayStateEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_DISPLAY_STATE_CHANGED", {
                windowType: _type,
                window: this,
                displayState: this.displayState
            }));
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Get main canvas reference
         * @return Main canvas container
         */
        public function get canvas():Sprite {
            return _canvas;
        }

        /**
         * Get background layer reference
         * @return Background layer for static elements
         */
        public function get backgroundLayer():Sprite {
            return _backgroundLayer;
        }

        /**
         * Get content layer reference
         * @return Content layer for dynamic elements
         */
        public function get contentLayer():Sprite {
            return _contentLayer;
        }

        /**
         * Get overlay layer reference
         * @return Overlay layer for temporary elements
         */
        public function get overlayLayer():Sprite {
            return _overlayLayer;
        }

        /**
         * Get current zoom level
         * @return Current zoom level
         */
        public function get zoomLevel():Number {
            return _zoomLevel;
        }

        /**
         * Set zoom level with bounds checking
         * @param level New zoom level
         */
        public function set zoomLevel(level:Number):void {
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, level));
            updateViewport();
        }

        /**
         * Get current viewport position
         * @return Current viewport position
         */
        public function get viewPoint():Point {
            return _viewPoint.clone();
        }

        /**
         * Set viewport position
         * @param point New viewport position
         */
        public function set viewPoint(point:Point):void {
            _viewPoint = point.clone();
            updateViewport();
        }

        /**
         * Get window type identifier
         * @return Window type
         */
        public function get windowType():String {
            return _type;
        }

        /**
         * Reset viewport to default position and zoom
         */
        public function resetViewport():void {
            centerCanvas();
            MultiPulsator.emit(new Impulse("CANVAS_RESET", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

		/**
		 * Add temporary marker at position for debugging
		 */
		private function addDebugMarker(position:Point):void {
			var marker:Sprite = new Sprite();
			marker.graphics.beginFill(0xFF0000, 0.7);
			marker.graphics.drawCircle(0, 0, 10);
			marker.graphics.endFill();
			marker.x = position.x;
			marker.y = position.y;
			_contentLayer.addChild(marker);

			// Remove after 2 seconds
			var timer:Timer = new Timer(2000, 1);
			timer.addEventListener(TimerEvent.TIMER, function(e:TimerEvent):void {
				if (_contentLayer.contains(marker)) {
					_contentLayer.removeChild(marker);
				}
			});
			timer.start();
		}

        /**
         * Clean up window resources
         */
        public function dispose():void {
            trace("Disposing window: " + _type);

            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            if (stage) {
                // Remove viewport controls
                stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
                stage.removeEventListener(Event.MOUSE_LEAVE, onMouseLeave);
                stage.removeEventListener(Event.RESIZE, onStageResize);
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
            }

            // Remove background layer listeners
            if (_backgroundLayer) {
                _backgroundLayer.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onBackgroundRightClick);
            }

            // Remove window lifecycle listeners
            removeEventListener(Event.ACTIVATE, transformWindowActivate);
            removeEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            removeEventListener(Event.CLOSING, transformWindowClosing);
            removeEventListener(Event.RESIZE, transformWindowResize);
            removeEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);

            // Remove mouse event transformers
            removeEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            removeEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            removeEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            removeEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
            removeEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
            removeEventListener(MouseEvent.CLICK, transformClick);

            if (_content && stage && stage.contains(_content)) {
                stage.removeChild(_content);
            }

            _content = null;
            _canvas = null;
            _backgroundLayer = null;
            _contentLayer = null;
            _overlayLayer = null;
        }
    }
}
 
package Src.Prog {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.Event;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.desktop.NativeApplication;
    import flash.display.NativeWindow;

    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.RegisterData;
    import Src.Prog.Core.Managers.Director;

    /**
     * Main application class - entry point
     * Initializes system, manages application lifecycle, coordinates components via Director
     * Handles system events and implements graceful shutdown through impulses
     */
    public class Main extends Sprite {
        // Singleton instance
        public static var root:Main = null;

        /**
         * Constructor - initializes root instance and prepares for stage
         */
        public function Main() {
            if (Main.root == null) {
                Main.root = this;
            }
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        /**
         * Handler when added to stage - called when app is fully loaded and ready
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            // Subscribe to impulses
            MultiPulsator.subscribeToImpulse("APP_CLOSE", reactor_APP_CLOSE);
            MultiPulsator.subscribeToImpulse("ENTER_FRAME", reactor_ENTER_FRAME);
            MultiPulsator.subscribeToImpulse("STAGE_RESIZE", reactor_STAGE_RESIZE);
            MultiPulsator.subscribeToImpulse("APP_READY", reactor_APP_READY);

            // Stage configuration
            stage.align = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.nativeWindow.title = "Native Window";

            // Event handlers
            stage.nativeWindow.addEventListener(Event.ACTIVATE, onWindowActivate);
            stage.nativeWindow.addEventListener(Event.CLOSING, onWindowClose);
            stage.addEventListener(Event.RESIZE, onStageResize);

            // Start initialization
            init();
        }

        /**
         * Stage resize handler
         */
        private function onStageResize(e:Event):void {
            MultiPulsator.emit(new Impulse("STAGE_RESIZE", {
                width: stage.stageWidth,
                height: stage.stageHeight
            }));
        }

        /**
         * Stage resize reactor
         */
        private function reactor_STAGE_RESIZE(impulse:Impulse):void {
            trace("reactor_STAGE_RESIZE");
        }

        /**
         * App ready reactor
         */
        private function reactor_APP_READY(impulse:Impulse):void {
            startRenderLoop();
        }

        /**
         * Enter frame reactor
         */
        private function reactor_ENTER_FRAME(impulse:Impulse):void {
            // Implementation for enter frame reactor
        }

        /**
         * Start main render loop
         */
        private function startRenderLoop():void {
            addEventListener(Event.ENTER_FRAME, onEnterFrame);
        }

        /**
         * Enter frame handler
         */
        private function onEnterFrame(e:Event):void {
            MultiPulsator.emit(new Impulse("ENTER_FRAME"));
        }

        /**
         * Application initialization
         * Starts system construction process via Director
         */
        private function init():void {
            Director.Start();
        }

        /**
         * Window activate handler
         * Called when app window becomes active
         */
        public function onWindowActivate(event:Event):void {
            // stage.nativeWindow.visible = false;
        }

        /**
         * Window close handler
         * Implements graceful shutdown through impulse system
         */
        public function onWindowClose(event:Event):void {
            MultiPulsator.emit(new Impulse("APP_CLOSE"));
        }

        /**
         * App close reactor
         * Handles APP_CLOSE impulse - properly terminates application
         */
        private static function reactor_APP_CLOSE(impulse:Impulse):void {
            NativeApplication.nativeApplication.exit();
        }
    }
}