# ALTAURI MASTER MANIFEST v6.0

**Code Name: "Resilient Foundation"**

---

## 1. Статус проекта: Production-Ready Core

**Текущая версия:** v6.0**Ключевое достижение:** Архитектура обрела "иммунитет" к ошибкам пользователя. Реализована полностью отказоустойчивая система Undo/Redo, безопасное управление памятью (Dispose) и надежная сериализация (Persistence). Технический долг по крашам закрыт.

---

## 2. Архитектурная Модель (Layered Cake)

Проект разделен на 4 независимых слоя. Взаимодействие осуществляется через **Data Binding**, **Priority Queue** и **Event Bus**.

### Слой 1: DRIVERS (Источники воздействия)

* **Роль:** Генерация данных извне и управление "активными" атомами.
* **Интеграция:** Базовый класс `Atom` реализует интерфейс `Driver`.
* **Компоненты:**`DriverManager`, `Driver` Interface, `MockSensorDriver`, `FPSDriver`.

### Слой 2: CORE / IO (Ядро логики)

* **Роль:** Чистая математика, трансформация данных, управление состоянием.
* **Ключевые сущности:**
  * **`UndoManager` (Fault Tolerant):**
    * Обертка `try-catch` для команд. Ошибка в одной команде не блокирует историю.
    * Поддержка `executeAndStore` и `storeExecuted`.
  * **`Atom`:**
    * *Safety:* Проверка `if (_process == null)` предотвращает краши "пассивных" атомов.
    * *Flag:*`_isDisposed` защита от "зомби" вызовов.
  * **`HeavyAtom`:**
    * *Resource Management:* Корректная отмена таймеров (`Timer.stop()`) при уничтожении.
  * **`SignalQueue`:** Priority-based scheduler (CRITICAL, NORMAL, BACKGROUND).

### Слой 3: EDITOR / ED (Визуализация)

* **Роль:** Инструмент управления графом.
* **Безопасность памяти (Memory Safety):**
  * **`NodeEditor`:** Исправлен паттерн Dispose. Хранение ссылок на колбэки (`_cbRedraw`) гарантирует полную отписку от `Impulsys`. Устранены утечки слушателей.
  * **`NodeView`:** Полная очистка слушателей мыши и подписок на данные.
* **Commands:**
  * `ConnectCommand`: Устойчивый `resolveContact` с проверками на `null`.
  * `CreateAtomCommand`: Реализован для полноты цикла Undo/Redo.

### Слой 4: DEVICE / GO (Интерфейс пользователя)

* **Роль:** Представление данных (HMI).
* **UI:**`PropertiesWindow` (Draggable, Dynamic), `ContextMenu`, `ButtonComponent`.

---

## 3. Протокол Взаимодействия (Interaction Protocol)

### Persistence (Save/Load)

* **Формат:** JSON (`.altauri`).
* **Safety:**`ProjectIO` использует `Std.string()` и безопасное приведение типов для защиты от ошибок парсинга (i32 vs String).
* **Coordinates:** Гарантированная запись/чтение координат с защитой от `NaN`.

### Command Pattern

* Все действия пользователя (Create, Delete, Move, Connect) обернуты в `ICommand`.
* История действий изолирована от логики рендеринга.

---

## 4. Визуальные стандарты

* **Wire Rendering:** Кубическая кривая Безье с защитой от отрисовки при `null` координатах.
* **Node Design:** Темная тема, моноширинный шрифт, цветовое кодирование портов (Input/Output).

---

## 5. Карта развития (Roadmap)

*(См. отдельный файл ROADMAP.md)*
