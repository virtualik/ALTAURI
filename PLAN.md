# СВОДНЫЙ ПЛАН РАЗВИТИЯ СИСТЕМЫ ALTAURI
## Версия документа: 1.0

---

## I. ФУНДАМЕНТАЛЬНАЯ КОНЦЕПЦИЯ

### 1.1 Определение Системы

**ALTAURI** — Реактивная Система Потоковой Калькуляции с двумя лицами:
- **Editor** — конструирование логики (Схема)
- **Device** — управление и мониторинг (Интерфейс)

### 1.2 Принцип Полиморфного Атома

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    ПОЛИМОРФНЫЙ КОМПОНЕНТ                        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                     ОДИН КЛАСС                          │  │
│   │                                                         │  │
│   │   class LED extends Atom {                             │  │
│   │                                                         │  │
│   │       // В Editor: рисует круг, показывает связи        │  │
│   │       // В Device: рендерит спрайт, реагирует на value  │  │
│   │                                                         │  │
│   │       function visualize():Void {                       │  │
│   │           if (context == EDITOR) visualizeForEditor();  │  │
│   │           if (context == DEVICE) visualizeForDevice();  │  │
│   │       }                                                 │  │
│   │   }                                                     │  │
│   │                                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   Контекст определяется при размещении на сцену:               │
│   stage.nativeWindow.title → "Editor" или "Device"             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Следствие:** Каждый Атом потенциально имеет визуальное представление в обоих мирах.

---

## II. АРХИТЕКТУРА СВЯЗИ

### 2.1 Два Механизма Синхронизации

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   ВНУТРИ ОДНОЙ МАШИНЫ          │      МЕЖДУ МАШИНАМИ            │
│                                                                 │
│   ┌───────────────────┐       │       ┌───────────────────┐    │
│   │   MessageBus      │       │       │   RemoteBridge    │    │
│   │   (память)        │       │       │   (WebSocket)     │    │
│   └───────────────────┘       │       └───────────────────┘    │
│                                                                 │
│   publish/subscribe           │       request/response          │
│   мгновенно                   │       асинхронно                │
│                                                                 │
│   Editor ◄──────────────► Device │    Client ◄────────────► Host│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Протокол ALTAURI-LINK

**Канал A — Управление (Control):**
| Действие | Направление | Описание |
|----------|-------------|----------|
| SCHEME_PULL | Client → Host | Запрос схемы |
| SCHEME_PUSH | Client → Host | Отправка изменений |
| SCHEME_APPLIED | Host → Client | Подтверждение |
| COMMAND | Client → Host | Внешняя команда (set value) |

**Канал B — Телеметрия (Telemetry):**
| Действие | Направление | Описание |
|----------|-------------|----------|
| VALUES_DELTA | Host → Client | Изменённые значения |
| EVENT | Host → Client | События ядра |
| STATS | Host → Client | Статистика (FPS, queue) |

### 2.3 Режимы Развёртывания

| Режим | Editor | Device | Ядро | Применение |
|-------|--------|--------|------|------------|
| **Monolith** | Local | Local | Local | Разработка, демо |
| **Split Local** | Window | Window | Shared | Два монитора |
| **Remote Control** | Browser | — | Server | Редактирование удалённой схемы |
| **Remote Monitor** | — | Browser | Server | Dashboard удалённой системы |
| **Full Remote** | Browser | Browser | Server | Полноценная облачная работа |

---

## III. DEVICE FACE — КОНСТРУИРУЕМЫЙ ИНТЕРФЕЙС

### 3.1 Принцип

Device Face — это **холст**, на котором пользователь **сам** размещает виджеты, связывая их с Атомами схемы.

### 3.2 Типы Виджетов

| Тип | Связь с Атомом | Примеры | Assets |
|-----|----------------|---------|--------|
| **INACTIVE** | Нет | Фон, рамка, надпись | 1 (bg) |
| **DISPLAY** | Односторонняя (Atom → Widget) | LED, Meter, Display | 2 (bg + face) |
| **SOURCE** | Односторонняя (Widget → Atom) | Button, Switch | 3 (up/over/down) |
| **BIDIRECTIONAL** | Двусторонняя | Slider, Knob, Input | 2+ (bg + face/states) |

### 3.3 Структура Виджета

```haxe
typedef WidgetDef = {
    var id:String;
    var name:String;
    
    // Геометрия
    var x:Float;
    var y:Float;
    var width:Float;
    var height:Float;
    var rotation:Float;
    var alpha:Float;
    
    // Связь
    var atomId:String;           // null = decoration
    var contactName:String;
    var mode:WidgetMode;
    
    // Ресурсы
    var assetBg:String;
    var assetFace:String;
    var assetUp:String;
    var assetOver:String;
    var assetDown:String;
}
```

### 3.4 Создание Виджета

```
1. Пользователь открывает пустое окно Device
2. Right Click → контекстное меню
3. Меню показывает:
   - Список Атомов из текущей Схемы
   - Список Assembly из текущей Схемы
   - Опцию "Create Decoration" (без связи)
4. Пользователь выбирает Атом
5. Виджет-заготовка появляется в точке клика
6. Properties Panel позволяет:
   - Задать позицию и размер
   - Назначить Assets
   - Настроить связь
```

---

## IV. СИСТЕМА РЕСУРСОВ (ASSETS)

### 4.1 Поддерживаемые Форматы

| Формат | Применение |
|--------|------------|
| PNG | Статичные изображения, прозрачность |
| GIF | Анимированные элементы |
| Sprite Sheet | Покадровая анимация (как в ToggleSwitch) |

### 4.2 Импорт и Хранение

```
┌─────────────────────────────────────────────────────────────────┐
│                        ASSET WORKFLOW                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   [Import] ──► Assets Panel ──► Drag to Widget ──► Assign      │
│       │                               │                         │
│       │                               ▼                         │
│       │                         Properties:                     │
│       │                         - assetBg = "panel_bg.png"     │
│       │                         - assetFace = "led_on.png"     │
│       │                                                         │
│       ▼                                                         │
│   File System:                                                  │
│   project.altauri                                               │
│   ├── assets/                                                   │
│   │   ├── led_on.png                                           │
│   │   ├── led_off.png                                          │
│   │   └── btn_up.png                                           │
│   └── [embedded в .altauri как base64]                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 Состояния Интерактивных Виджетов

```
BUTTON / SWITCH:
┌─────────┐   ┌─────────┐   ┌─────────┐
│   UP    │   │  OVER   │   │  DOWN   │
│ (idle)  │ ─►│ (hover) │ ─►│ (click) │
└─────────┘   └─────────┘   └─────────┘
   assetUp     assetOver    assetDown

LED / INDICATOR:
┌─────────┐   ┌─────────┐
│  OFF    │   │   ON    │
│ value=0 │ ─►│ value=1 │
└─────────┘   └─────────┘
 assetFace     assetFace (или цветовой фильтр)
```

---

## V. ПОЛИМОРФНАЯ ВИЗУАЛИЗАЦИЯ

### 5.1 Паттерн (из исторического кода)

```haxe
class LED extends Atom {
    
    public var rectangle_for_editor:Sprite;
    public var rectangle_for_device:Sprite;
    
    private function onAddedToStage(e:Event):Void {
        var windowTitle = stage.nativeWindow.title;
        
        if (windowTitle.indexOf("Editor") != -1) {
            visualizeForEditor();
        } else if (windowTitle.indexOf("Device") != -1) {
            visualizeForDevice();
        }
    }
    
    private function visualizeForEditor():Void {
        // Простой круг, порты для связей
        // Подписка на MessageBus для синхронизации
        MessageBus.subscribe(moduleName + "_Device", onSyncFromDevice);
    }
    
    private function visualizeForDevice():Void {
        // Спрайт, анимация, пользовательские Assets
        // Подписка на MessageBus для синхронизации
        MessageBus.subscribe(moduleName + "_Editor", onSyncFromEditor);
    }
}
```

### 5.2 Синхронизация через MessageBus

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                     EDITOR WINDOW                               │
│                                                                 │
│   LED (Editor View)                                            │
│        │                                                        │
│        │ publish("led_1_Editor", "on")                         │
│        ▼                                                        │
│   ┌─────────┐                                                  │
│   │MessageBus│                                                  │
│   └─────────┘                                                  │
│        │                                                        │
└────────┼────────────────────────────────────────────────────────┘
         │
         │  Межоконная коммуникация
         │
┌────────┼────────────────────────────────────────────────────────┐
│        │                                                        │
│        ▼                                                        │
│   ┌─────────┐                                                  │
│   │MessageBus│                                                  │
│   └─────────┘                                                  │
│        │                                                        │
│        │ subscribe("led_1_Editor", callback)                   │
│        ▼                                                        │
│   LED (Device View)                                            │
│        │                                                        │
│                                                                 │
│                     DEVICE WINDOW                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## VI. МНОЖЕСТВЕННЫЕ DEVICE FACE

### 6.1 Сценарии

```
СЦЕНАРИЙ A: Несколько мониторов
┌──────────┐  ┌──────────┐  ┌──────────┐
│ Editor   │  │ Device 1 │  │ Device 2 │
│ (Main)   │  │ (Living) │  │ (Kitchen)│
└──────────┘  └──────────┘  └──────────┘
     │              │              │
     └──────────────┴──────────────┘
                    │
              One Core
              One Scheme

СЦЕНАРИЙ B: Распределённая система
┌──────────┐  ┌──────────┐  ┌──────────┐
│ Device 1 │  │ Device 2 │  │ Device 3 │
│ (Room A) │  │ (Room B) │  │ (Mobile) │
└──────────┘  └──────────┘  └──────────┘
     │              │              │
     └──────────────┴──────────────┘
                    │
              WebSocket
                    │
              ┌──────────┐
              │   Host   │
              │  (Core)  │
              └──────────┘
```

### 6.2 Подписки

```
Device 1 подписан на: led_1, button_2, slider_3
Device 2 подписан на: led_4, led_5, meter_6
Device 3 подписан на: ALL (stats, all values)

Ядро рассылает только то, что изменилось
Каждый клиент фильтрует по своим подпискам
```

---

## VII. ШАБЛОНЫ (TEMPLATES)

### 7.1 Определение

**Шаблон** — предустановленный набор:
- Атомов и связей (Blueprint)
- Виджетов и Assets (DeviceFace)
- Настроек позиционирования

### 7.2 Применение

```
1. Пользователь создаёт схему "Термостат"
2. Настраивает виджеты в Device
3. Сохраняет как Template
4. При создании нового проекта выбирает Template
5. Получает готовую схему + готовый интерфейс
```

### 7.3 Структура Файла Шаблона

```json
{
  "name": "Thermostat Controller",
  "category": "HVAC",
  
  "blueprint": {
    "internalAtoms": [...],
    "internalConnections": [...]
  },
  
  "deviceFace": {
    "widgets": [...]
  },
  
  "assets": {
    "bg_panel": "base64...",
    "led_on": "base64...",
    ...
  }
}
```

---

## VIII. УНИВЕРСАЛЬНОСТЬ ВИЗУАЛИЗАЦИИ

### 8.1 Принцип

**Любой Атом может иметь визуальное представление.**

| Атом | Editor View | Device View |
|------|-------------|-------------|
| NAND | Прямоугольник с портами | (нет по умолчанию) |
| Wire | Линия Безье | Статическая линия (опционально) |
| Button | Прямоугольник с "out" | Интерактивная кнопка |
| LED | Круг, меняет цвет | Спрайт с анимацией |
| Assembly | Прямоугольник с подсказкой | Вложенное Device Face |

### 8.2 Уровни Визуализации

```
Уровень 0: Невидимый (логические атомы)
    └── По умолчанию не отображаются в Device

Уровень 1: Схематичный (Editor)
    └── Простые геометрические формы

Уровень 2: Стилизованный (Device basic)
    └── Цвет, форма по категории

Уровень 3: Кастомизированный (Device advanced)
    └── Пользовательские Assets, анимации
```

---

## IX. ОБНОВЛЁННАЯ ИЕРАРХИЯ ОТВЕТСТВЕННОСТИ

```
┌─────────────────────────────────────────────────────────────────┐
│                    УРОВНИ ALTAURI v3.0                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  8. DEVICE FACE EDITOR                                          │
│     └── Конструирование HMI: виджеты, assets, layout            │
│                                                                  │
│  7. DEVICE FACE RUNTIME                                         │
│     └── Отображение, реакция на данные, интерактивность         │
│                                                                  │
│  6. REMOTE BRIDGE                                               │
│     └── Сетевая коммуникация, сериализация, синхронизация       │
│                                                                  │
│  5. MESSAGE BUS                                                 │
│     └── Локальная синхронизация между Editor ↔ Device           │
│                                                                  │
│  4. SCHEME EDITOR                                               │
│     └── Конструирование логики: атомы, связи, сборки            │
│                                                                  │
│  3. КОМАНДНАЯ СИСТЕМА                                           │
│     └── Undo/Redo для обоих редакторов                          │
│                                                                  │
│  2. БИБЛИОТЕКА                                                   │
│     └── Каталог типов, Templates, Asset Library                 │
│                                                                  │
│  1. ЯДРО                                                         │
│     └── Atom, Contact, Assembly, Blueprint, SignalQueue         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## X. СТРУКТУРА ФАЙЛА ПРОЕКТА v2.0

```json
{
  "version": "2.0",
  "name": "Smart Home Controller",
  
  "blueprint": {
    "id": "main_scheme",
    "name": "Main Scheme",
    "pins": [
      {"name": "IN", "type": "INPUT"},
      {"name": "OUT", "type": "OUTPUT"}
    ],
    "internalAtoms": [
      {"instanceId": "led_1", "typeId": "LED", "x": 100, "y": 200},
      {"instanceId": "btn_2", "typeId": "Button", "x": 300, "y": 150}
    ],
    "internalConnections": [
      {
        "from": {"atomId": "btn_2", "contactName": "out"},
        "to": {"atomId": "led_1", "contactName": "in"}
      }
    ]
  },
  
  "assets": {
    "bg_panel": "data:image/png;base64,...",
    "led_on": "data:image/png;base64,...",
    "led_off": "data:image/png;base64,...",
    "btn_up": "data:image/png;base64,...",
    "btn_over": "data:image/png;base64,...",
    "btn_down": "data:image/png;base64,..."
  },
  
  "deviceFaces": [
    {
      "id": "main_device",
      "name": "Main Panel",
      "canvasWidth": 800,
      "canvasHeight": 600,
      "widgets": [
        {
          "id": "w_bg",
          "x": 0, "y": 0,
          "width": 800, "height": 600,
          "mode": "INACTIVE",
          "assetBg": "bg_panel"
        },
        {
          "id": "w_led",
          "x": 120, "y": 100,
          "width": 32, "height": 32,
          "atomId": "led_1",
          "contactName": "in",
          "mode": "DISPLAY",
          "assetFace": "led_on"
        },
        {
          "id": "w_btn",
          "x": 300, "y": 200,
          "width": 64, "height": 64,
          "atomId": "btn_2",
          "contactName": "out",
          "mode": "SOURCE",
          "assetUp": "btn_up",
          "assetOver": "btn_over",
          "assetDown": "btn_down"
        }
      ]
    }
  ],
  
  "editorState": {
    "viewX": 0,
    "viewY": 0,
    "zoom": 1.0
  }
}
```

---

## XI. ДОРОЖНАЯ КАРТА РЕАЛИЗАЦИИ

### Фаза 1: Полиморфные Атомы
- [ ] Базовый класс PolymorphAtom
- [ ] Механизм определения контекста (Editor/Device)
- [ ] MessageBus для синхронизации
- [ ] Реализация LED как полиморфа
- [ ] Реализация Button как полиморфа

### Фаза 2: Device Face Editor
- [ ] Пустой холст Device
- [ ] Контекстное меню со списком Атомов
- [ ] Создание виджета при выборе
- [ ] Properties Panel для виджета
- [ ] Перемещение, масштабирование

### Фаза 3: Assets System
- [ ] Импорт PNG/GIF
- [ ] Assets Panel
- [ ] Drag & Drop на виджет
- [ ] Embedding в файл проекта
- [ ] Sprite Sheet поддержка

### Фаза 4: Remote Architecture
- [ ] RemoteBridge interface
- [ ] WebSocket Server (Node.js / Haxe)
- [ ] WebSocket Client (Browser)
- [ ] Протокол ALTAURI-LINK
- [ ] Телеметрический буфер

### Фаза 5: Templates
- [ ] Сохранение проекта как Template
- [ ] Браузер Templates
- [ ] Применение Template при создании

### Фаза 6: Advanced Features
- [ ] Множественные Device Faces
- [ ] Вложенные Assembly в Device
- [ ] Анимации и переходы
- [ ] Темы оформления

---

## XII. ЗАКЛЮЧЕНИЕ

Система ALTAURI развивается в направлении **двойственной архитектуры**:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                         ALTAURI                                 │
│                                                                 │
│    ┌─────────────────┐              ┌─────────────────┐        │
│    │                 │              │                 │        │
│    │    EDITOR       │              │    DEVICE       │        │
│    │                 │              │                 │        │
│    │  Логика         │              │  Интерфейс      │        │
│    │  Схемы          │◄────────────►│  Виджеты        │        │
│    │  Атомы          │              │  Assets         │        │
│    │                 │              │                 │        │
│    └─────────────────┘              └─────────────────┘        │
│              │                               │                 │
│              │     MessageBus / Bridge       │                 │
│              │                               │                 │
│              └───────────────┬───────────────┘                 │
│                              │                                 │
│                              ▼                                 │
│                    ┌─────────────────┐                        │
│                    │                 │                        │
│                    │      ЯДРО       │                        │
│                    │                 │                        │
│                    │  Вычисления     │                        │
│                    │  Поток данных   │                        │
│                    │                 │                        │
│                    └─────────────────┘                        │
│                                                                 │
│              Локально или Удалённо                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Ключевой принцип:** Полиморфный Атом знает оба своих лица, но активирует только то, которое соответствует контексту размещения.

---

*Документ сохранён для дальнейшей работы над проектом ALTAURI.*
