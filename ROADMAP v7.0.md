# ALTAURI ROADMAP v7.0

## ✅ ВЫПОЛНЕНО (Done)

### Базовая архитектура

* **Undo/Redo System:** Полная реализация паттерна Command.
* **Memory Management:** Корректный `dispose()` для всех компонентов.
* **Persistence (Save/Load):** Полный цикл с безопасным парсингом.
* **Hard Reset:** Полная очистка без крашей.

### ECS Layer (v7.0)

* **Integration:** Гибридный ECS-слой поверх существующего кода.
* **Components:** PositionComponent, VisualComponent.
* **Systems:** RenderSystem, Query (spatial).
* **Facade:** ECS — единая точка доступа.
* **Toggle:** Runtime переключение ECS / Direct.

### Settings System (v7.0)

* **Settings Panel:** UI для управления настройками.
* **ECS Toggle:** Включение/выключение ECS-рендеринга.
* **Wire Type Selector:** Выбор из 3 типов проводов.
* **Statistics Display:** Node count, Wire count, Render mode.

### Wire Rendering (v7.0)

* **Bezier Curve:** Кубические кривые (default).
* **Straight Line:** Прямые линии точка-точка.
* **Corners Line:** Ломаные с прямыми углами.
* **Ghost Wire:** Соответствует выбранному типу.
* **Persistence:** Тип провода сохраняется во всех операциях.

---

## 🚩 ПРИОРИТЕТ 1: Производительность

1. **Батчинг проводов:**
   * Рисовать все провода одной операцией.
   * Сравнить FPS на 1000+ проводах.
2. **Visibility Culling:**
   * Не рисовать ноды вне viewport.
   * Интеграция с ECS Query.
3. **FPS Monitor:**
   * Встроенный счётчик кадров.
   * Отображение в реальном времени.

---

## 🚩 ПРИОРИТЕТ 2: UI/UX и Навигация

1. **PAN и ZOOM:**
   * ✅ Pan — средняя кнопка мыши (реализовано)
   * ✅ Zoom — колесико мыши (реализовано)
2. **Групповое выделение:**
   * ✅ Lasso selection через ECS Query.getInRect (реализовано)
   * Групповое перемещение (уже работает)
   * Групповое удаление
3. **Copy/Paste:**
   * Копирование выделенных атомов.
   * Вставка с новыми ID.

---

## 🚩 ПРИОРИТЕТ 3: Расширение Библиотеки Атомов

1. **Logic Gates:**
   * `AND`, `OR`, `NOT`, `XOR`.
   * `Math`: Add, Subtract, Multiply, Divide.
2. **UI Widgets:**
   * `ButtonAtom` (генерирует true/false).
   * `ToggleAtom` (переключатель).
   * `GraphAtom` (график значений во времени).
3. **Advanced:**
   * `DelayAtom` (задержка сигнала).
   * `FilterAtom` (фильтрация значений).
   * `MergeAtom` (объединение потоков).

---

## 🚩 ПРИОРИТЕТ 4: Device Face

1. **Конструктор интерфейса:**
   * Пустой холст Device.
   * Drag & Drop виджетов из библиотеки.
   * Связывание виджетов с атомами.
2. **Типы виджетов:**
   * Display (LED, Meter, Graph).
   * Source (Button, Switch, Slider).
   * Decoration (Label, Frame).
3. **Assets System:**
   * Импорт PNG/GIF.
   * Embedding в файл проекта.

---

## 🚩 ПРИОРИТЕТ 5: Remote Architecture

1. **RemoteBridge:**
   * Интерфейс для сетевой коммуникации.
   * WebSocket Server/Client.
2. **Протокол ALTAURI-LINK:**
   * SCHEME\_PULL / SCHEME\_PUSH.
   * VALUES\_DELTA (телеметрия).
   * EVENT (события ядра).
3. **Режимы развёртывания:**
   * Monolith (local).
   * Split Local (два окна).
   * Remote Control (browser → server).

---

## 🚩 ПРИОРИТЕТ 6: Templates & Library

1. **Templates:**
   * Сохранение схемы как Template.
   * Браузер Templates.
   * Применение при создании проекта.
2. **Asset Library:**
   * Каталог пользовательских атомов.
   * Импорт/экспорт библиотек.
   * Маркетплейс (будущее).

---

## 📊 Метрики успеха

| Метрика                   | Текущая | Цель |
| -------------------------------- | -------------- | -------- |
| Ноды без лагов       | \~100          | 1000+    |
| Провода без лагов | \~50           | 500+     |
| Startup time                     | \~1s           | <500ms   |
| Memory per node                  | \~2KB          | <1KB     |
| Undo/Redo latency                | <10ms          | <5ms     |

---

## 🎯 Следующие шаги (Immediate)

1. **Протестировать производительность** — сравнить Bezier vs Straight vs Corners.
2. **Добавить FPS Counter** — встроить в UI для мониторинга.
3. **Реализовать Batch Wire Rendering** — единый проход для всех проводов.
4. **Visibility Culling через ECS** — Query.getInRect для viewport.

---

*Документ обновлён после интеграции ECS и Settings Panel.*
