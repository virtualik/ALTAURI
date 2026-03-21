Полное дерево смыслов приложения с именами классов (всего 60шт)

ПРИЛОЖЕНИЕ ALTAURI (48шт)
│
├── СХЕМА
│   ├── Узлы
│   ├── Атом (простой узел с логикой)
│   │   ├── Atom, HeavyAtom
│   │   └── Конкретные реализации:
│   │       ├── NandAtom (логический элемент)
│   │       ├── ButtonAtom (кнопка)
│   │       ├── LedAtom (индикатор)
│   │       └── RelayAtom (реле)
│   ├── Сборка (составной узел-контейнер)
│   │   └── Assembly
│   ├── Контакты
│   │   ├── Контакт (точка приёма/передачи данных)
│   │   │   └── Contact
│   │   └── Порт-проброс (вход/выход сборки)
│   │       └── ConductorPort
│   ├── Соединения
│   │   └── Связь (соединение контактов)
│   │       └── [реализовано через Contact.link()]
│   ├── Данные схемы
│   │   └── Чертёж (сериализуемое описание)
│   │       └── Blueprint, PinDef, AtomDef, ConnectionDef, ConnectionPoint
│   └── Распространение сигналов
│       └── Очередь сигналов (приоритетная обработка)
│           └── SignalQueue, Priority
│
├── РЕДАКТОР СХЕМЫ
│   ├── Инструмент Выбора
│   │   └── NodeEditor (частично: selectedNodes, selectedWireIds, onNodeClicked, onLassoUp)
│   ├── Инструмент Перемещения
│   │   └── NodeEditor (частично: onNodeMoved, onMouseMove, onMouseWheel), MoveNodeCommand
│   ├── Инструмент Соединения
│   │   └── NodeEditor (частично: onPortDragStart, onMouseUp, drawGhostWire), ConnectCommand
│   ├── Инструмент Создания
│   │   └── NodeEditor (частично: createAtom, addPort), CreateAtomCommand, AddPortCommand, GroupAtomsCommand, CreateNewAssemblyCommand
│   ├── Инструмент Удаления
│   │   └── NodeEditor (частично: deleteAtom, deleteWire, removePort), DeleteAtomCommand, RemovePortCommand
│   ├── Инструмент Навигации
│   │   └── NodeEditor (частично: pushEditor, popEditor, getViewState, setViewState)
│   └── История действий (Undo/Redo)
│       └── UndoManager, Command, ICommand, MacroCommand
│
├── ПРОИГРЫВАТЕЛЬ СХЕМЫ
│   ├── Среда выполнения (цикл обновления)
│   │   └── DriverManager
│   ├── Активные драйверы (атомы с update)
│   │   └── Driver (интерфейс), FPSMonitorAtom, FrameTimeAtom
│   ├── Поток сигналов (распространение данных)
│   │   └── SignalQueue, Contact._propagate()
│   └── Интерфейс выполнения (HMI виджеты)
│       └── DevicePanel, IHMIWidget, NumberInput, NumberDisplay
│
└── ВСПОМОГАТЕЛЬНЫЕ СИСТЕМЫ
├── Система событий (глобальная шина)
│   └── Impulsys, Impulse
├── Библиотека (реестр типов узлов)
│   └── AtomRegistry, AssemblyFactory
├── Файловая система (сохранение/загрузка)
│   └── ProjectIO
├── Визуализация (ECS рендеринг)
│   └── World, RenderSystem, Query, ComponentStorage, PositionComponent, VisualComponent, ECS
└── Платформа (системные вызовы)
└── Environment, WindowController, NativeWindowExtension

Классы, не вошедшие в классификацию (12шт)
Класс
Причина
Main	Точка входа — координирует все части, не является частью схемы
NodeView	Визуальное представление узла — используется и редактором, и визуализацией
ContextMenu	UI-компонент — используется несколькими инструментами редактора
ContextMenuItem	Часть ContextMenu
PropertiesWindow	UI-окно — примыкает к редактору, но самостоятельная единица
SettingsPanel	UI-панель настроек — глобальный интерфейс приложения
ButtonComponent	UI-виджет общего назначения
TextComponent	UI-виджет общего назначения
WireType	Enum — тип данных для визуализации проводов
IDisposable	Интерфейс — технический контракт очистки ресурсов
ContactType	Enum — тип данных для контактов
Utils	Утилиты — разрозненные вспомогательные функции




| #  | Файл                                | Описание                                                                |
| -- | --------------------------------------- | ------------------------------------------------------------------------------- |
| 1  | `core/view/DeviceViewRegistry.hx`     | Singleton реестр виджетов - один атом = одно лицо |
| 2  | `core/view/DeviceWidgetFactory.hx`    | Фабрика виджетов                                                 |
| 3  | `core/base/Atom.hx`                   | Базовый класс с Databank архитектурой                  |
| 4  | `core/base/Contact.hx`                | Контакт с подпиской DeviceView                                 |
| 5  | `core/types/ContactType.hx`           | Enum типов контактов                                              |
| 6  | `core/types/Priority.hx`              | Enum приоритетов                                                     |
| 7  | `core/logic/SignalQueue.hx`           | Очередь сигналов                                                 |
| 8  | `core/logic/EventType.hx`             | Типы событий                                                         |
| 9  | `core/logic/Impulsys.hx`              | Шина событий                                                         |
| 10 | `core/logic/Impulse.hx`               | Контейнер события                                               |
| 11 | `system/managers/Driver.hx`           | Интерфейс драйвера                                             |
| 12 | `system/managers/DriverManager.hx`    | Менеджер активных атомов                                  |
| 13 | `core/base/IDisposable.hx`            | Интерфейс очистки                                               |
| 14 | `core/view/DeviceView.hx`             | Базовый класс всех виджетов                             |
| 15 | `library/electro/OscilloscopeAtom.hx` | **Databank: буфер в атоме**                                    |
| 16 | `core/view/OscilloscopeWidget.hx`     | **Face: читает из Databank**                                      |
| 17 | `core/view/LEDWidget.hx`              | Виджет LED                                                                |
| 18 | `core/view/ButtonWidget.hx`           | Виджет кнопки                                                       |
| 19 | `core/view/ToggleWidget.hx`           | Виджет переключателя                                         |
| 20 | `core/view/TextWidget.hx`             | Виджет текста                                                       |
| 21 | `core/view/TextInputWidget.hx`        | Виджет ввода текста                                            |
| 22 | `core/view/PanelWidget.hx`            | Виджет панели                                                       |
| 23 | `core/view/ConductorWidget.hx`        | Виджет проводника                                               |
| 24 | `library/logic/ConductorAtom.hx`      | Атом проводника                                                   |
| 25 | `library/electro/ToggleAtom.hx`       | Атом переключателя                                             |
