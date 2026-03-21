package core.base;

import core.types.ContactType;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ATOM BASE CLASS v6.1 (Databank & Compute Core Architecture)
 * Fundamental unit of logic. Independent of rendering engine.
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 *                          ┌─────────────────┐
 *                          │      АТОМ       │
 *                          │   (Сущность)    │
 *                          └────────┬────────┘
 *                                   │
 *             ┌─────────────────────┼─────────────────────┐
 *             │                     │                     │
 *             ▼                     ▼                     ▼
 *    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
 *    │   А) COMPUTE    │  │   Б) DATABANK   │  │     В) FACE     │
 *    │     MODULE      │  │                 │  │   (DeviceView)  │
 *    ├─────────────────┤  ├─────────────────┤  ├─────────────────┤
 *    │                 │  │                 │  │                 │
 *    │ • _process()    │  │ • _buffer[]     │  │ • ЕДИНСТВЕННЫЙ  │
 *    │ • _calculate()  │  │ • _state        │  │   экземпляр     │
 *    │ • _onUpdate()   │  │ • _variables    │  │                 │
 *    │                 │  │ • _history      │  │ • DeviceView    │
 *    │ • Входы/Выходы  │  │                 │  │   Registry      │
 *    │   обрабатывают- │  │ • Сериализуется │  │                 │
 *    │   ся через      │  │   через         │  │ • Не является   │
 *    │   Contact       │  │   getPersistent │  │   частью атома! │
 *    │                 │  │   State()       │  │                 │
 *    │ • Активен через │  │                 │  │ • Атом может    │
 *    │   DriverManager │  │ • Headless:     │  │   работать без  │
 *    │   (isActive)    │  │   работает      │  │   него          │
 *    │                 │  │   автономно     │  │                 │
 *    └─────────────────┘  └─────────────────┘  └─────────────────┘
 * 
 * Headless Mode:
 * ─────────────
 *   А) работает ✓        Б) работает ✓       В) не нужен ✗
 *   Атом полностью функционален без UI.
 *   Данные накапливаются в Databank.
 *   Вычисления выполняются в Compute Module.
 * 
 * Normal Mode:
 * ────────────
 *   А) работает ✓        Б) работает ✓       В) создаётся DeviceView
 *   DeviceView подписывается на Contact и
 *   отображает данные из Databank.
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * v6.1 Changes:
 * - FIXED: _bind() now binds BOTH inputs and outputs to atom
 * - This allows atoms to receive onContactChanged() for their own outputs
 * - Important for atoms that need to react to their own output changes
 * - FIXED: onContactChanged() now ignores OWN OUTPUT changes to prevent
 *          recursive notifications that break ToggleAtom and similar atoms
 * 
 * v6.0 Changes:
 * - Added architecture documentation
 * - Improved onContactChanged() for passive atoms (Oscilloscope, LED, etc.)
 * - Passive atoms now process incoming data through onContactChanged()
 * - Full separation: Model (Atom) vs View (DeviceView)
 * 
 * v5.3 Changes:
 * - Added getPersistentState() for saving atom state
 * - Added restoreState() for restoring atom state on load
 * - Default implementations return null (no state to save)
 */
class Atom implements IDisposable implements Driver {

    // =========================================================================
    // IDENTITY
    // =========================================================================

    public var id(get, never):String;
    private function get_id():String return _id;
    private var _id:String;

    public var type(default, null):String;
    public var name(default, null):String;

    // =========================================================================
    // CONTACTS (Ports)
    // =========================================================================

    // В Haxe private = protected (доступен в подклассах)
    private var _inputs:Array<Contact>;
    private var _outputs:Array<Contact>;

    // =========================================================================
    // COMPUTE MODULE (Processing Logic)
    // =========================================================================

    private var _process:Array<Dynamic> -> Array<Dynamic>;

    // Кэш входных значений для _process()
    private var _inputCache:Array<Dynamic>;

    // Флаги состояния
    private var _isScheduled:Bool = false;
    private var _isActive:Bool = false;
    private var _isDisposed:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Generic",
        ?isActive:Bool = false
    ) {
        this._id = (id != null) ? id : "atom_" + Std.random(100000);
        this.type = type;
        this.name = type;

        this._isActive = isActive;

        this._inputs = (inputs != null) ? inputs : [];
        this._outputs = (outputs != null) ? outputs : [];
        this._process = processFunc;

        _inputCache = [];
        for (i in 0..._inputs.length) _inputCache.push(null);

        _bind();

        if (_isActive) {
            DriverManager.getInstance().register(this);
        }
    }

    // =========================================================================
    // BINDING
    // =========================================================================

    /**
     * Привязать все контакты (входы И выходы) к этому атому.
     * При изменении значения контакта будет вызван onContactChanged().
     * 
     * v6.1 FIX: Теперь привязываются и inputs, и outputs.
     * Это позволяет атому реагировать на изменения своих выходов,
     * что важно для атомов с обратной связью и сложной логикой.
     * 
     * ВАЖНО: onContactChanged() теперь игнорирует изменения
     * собственных OUTPUT контактов, чтобы избежать рекурсивных
     * уведомлений, которые ломают атомы типа ToggleAtom.
     */
    private function _bind():Void {
        // Привязываем входные контакты
        for (input in _inputs) {
            if (input != null) input.owner = this;
        }
        // Привязываем выходные контакты
        for (output in _outputs) {
            if (output != null) output.owner = this;
        }
    }

    // =========================================================================
    // LIFECYCLE
    // =========================================================================

    /**
     * Инициализация атома.
     * Переопределите для выполнения начальной настройки.
     */
    public function init():Void { }

    /**
     * Обновление атома каждый кадр.
     * Вызывается DriverManager для активных атомов (isActive = true).
     * 
     * @param dt Delta time в секундах
     */
    public function update(dt:Float):Void {
        _onUpdate(dt);
    }

    /**
     * Внутренний метод обновления.
     * Переопределите для активных атомов (генераторы, драйверы).
     */
    private function _onUpdate(dt:Float):Void { }

    // =========================================================================
    // CONTACT CHANGE HANDLING
    // =========================================================================

    /**
     * Вызывается Contact'ом при изменении его значения.
     * 
     * Это ГЛАВНЫЙ метод для обработки входящих данных.
     * 
     * ДВА РЕЖИМА РАБОТЫ:
     * 
     * 1. Атом с _process функцией (комбинационная логика):
     *    - Планирует вызов _calculate()
     *    - _calculate() вызывает _process() и передаёт результаты на выходы
     *    - Примеры: NAND, Conductor
     * 
     * 2. Пассивный атом без _process (накопление данных):
     *    - Переопределите onContactChanged() для обработки данных
     *    - Данные сохраняются в Databank (_buffer, _state, etc.)
     *    - Примеры: Oscilloscope, LED, AudioInput
     * 
     * v6.1 NOTE: 
     * - Вызывается и для OUTPUT контактов атома (благодаря _bind fix)
     * - Но ИГНОРИРУЕТ изменения собственных OUTPUT, чтобы избежать
     *   рекурсивных уведомлений (ToggleAtom, ButtonAtom и др.)
     * 
     * @param c Контакт, значение которого изменилось
     */
    public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;
        
        // === v6.1 FIX: Игнорировать изменения собственных OUTPUT контактов ===
        // Это предотвращает рекурсивные уведомления, которые ломают
        // атомы с состоянием (ToggleAtom, ButtonAtom и т.д.)
        // Когда атом меняет свой выход, он не должен реагировать
        // на это изменение как на внешний сигнал.
        if (c.type == OUTPUT && c.owner == this) {
            return;
        }
        // =====================================================================
        
        // Если есть функция обработки - планируем вычисление
        if (_process != null) {
            _isScheduled = true;
            core.logic.SignalQueue.getInstance().schedule(_calculate, NORMAL);
        }
        // Примечание для пассивных атомов:
        // Переопределите этот метод для обработки входящих данных.
        // Не забудьте проверить имя контакта:
        //
        // override public function onContactChanged(c:Contact):Void {
        //     if (c.name == "in" && c.value != null) {
        //         processData(c.value);
        //     }
        // }
    }

    /**
     * Выполнить вычисление и передать результаты на выходы.
     * 
     * Вызывается из SignalQueue для атомов с _process функцией.
     */
    private function _calculate():Void {
        _isScheduled = false;

        if (_isDisposed || _process == null || _inputs == null) return;

        // Собираем входные значения
        for (i in 0..._inputs.length) {
            _inputCache[i] = _inputs[i].value;
        }

        // Вычисляем
        var results = _process(_inputCache);

        // Передаём на выходы
        if (results != null && results.length == _outputs.length) {
            for (i in 0..._outputs.length) {
                if (_outputs[i] != null) _outputs[i].value = results[i];
            }
        }
    }

    // =========================================================================
    // STATE SERIALIZATION (Databank)
    // =========================================================================

    /**
     * Получить состояние атома для сохранения.
     * 
     * Переопределите для сохранения данных Databank:
     * - Буферы (_buffer)
     * - Внутренние переменные (_state, _frequency, etc.)
     * - Историю данных (_history)
     * 
     * Примеры реализаций:
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ class OscilloscopeAtom {                                                │
     * │     override public function getPersistentState():Dynamic {            │
     * │         return {                                                        │
     * │             buffer: _buffer.copy(),                                    │
     * │             writeIndex: _writeIndex,                                   │
     * │             samplesCollected: _samplesCollected                        │
     * │         };                                                              │
     * │     }                                                                   │
     * │ }                                                                       │
     * │                                                                         │
     * │ class SignalGeneratorAtom {                                             │
     * │     override public function getPersistentState():Dynamic {            │
     * │         return { frequency: _frequency, phase: _phase };               │
     * │     }                                                                   │
     * │ }                                                                       │
     * │                                                                         │
     * │ class TextInputAtom {                                                   │
     * │     override public function getPersistentState():Dynamic {            │
     * │         return { value: _outputs[0].value };                           │
     * │     }                                                                   │
     * │ }                                                                       │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     * @return Dynamic объект с данными состояния, или null если нет состояния
     */
    public function getPersistentState():Dynamic {
        return null;
    }

    /**
     * Восстановить состояние атома из сохранённых данных.
     * 
     * Вызывается при загрузке проекта.
     * Параметр state содержит данные, возвращённые getPersistentState().
     * 
     * @param state Сохранённое состояние
     */
    public function restoreState(state:Dynamic):Void {
        // По умолчанию: ничего не делаем
        // Переопределите для восстановления Databank
    }

    // =========================================================================
    // GETTERS
    // =========================================================================

    /**
     * Получить все входные контакты.
     */
    public function getInputs():Array<Contact> return _inputs;

    /**
     * Получить все выходные контакты.
     */
    public function getOutputs():Array<Contact> return _outputs;

    /**
     * Получить входной контакт по имени.
     */
    public function getInput(name:String):Contact {
        if (_inputs == null) return null;
        for (c in _inputs) {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

    /**
     * Получить выходной контакт по имени.
     */
    public function getOutput(name:String):Contact {
        if (_outputs == null) return null;
        for (c in _outputs) {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    /**
     * Освободить все ресурсы атома.
     * 
     * ВАЖНО: Вызывается при удалении атома из проекта.
     * После вызова dispose() атом нельзя использовать.
     */
    public function dispose():Void {
        _isDisposed = true;

        // Отписываемся от DriverManager
        if (_isActive) {
            DriverManager.getInstance().unregister(this.id);
        }

        // Освобождаем контакты
        if (_inputs != null) {
            for (c in _inputs) {
                if (c != null) c.dispose();
            }
        }

        if (_outputs != null) {
            for (c in _outputs) {
                if (c != null) c.dispose();
            }
        }

        // Очищаем ссылки
        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}