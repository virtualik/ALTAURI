package core.base;

import core.logic.SignalQueue;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ATOM BASE CLASS v6.4
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
 * * v6.4 Changes:
 * - CRITICAL FIX: Constructor now SCHEDULES calculation instead of running it immediately.
 * - This allows `isLogic` flag to be set via `restoreState` BEFORE the first calculation runs.
 * - Prevents immediate feedback loops in complex circuits (like T-Trigger) during load.
 * - Ensures "Digital" nodes behave as "Digital" from the very first calculation.
 * 
 * v6.3 Changes:
 * - FIXED: Atoms now perform an initial calculation in constructor.
 * - This ensures outputs match logic based on default input values immediately on load.
 * - Prevents "stale" state where gates (like NAND) output 'false' when logic dictates 'true'.
 * 
 * v6.2 Changes:
 * - ADDED: isLogic is now a property with a setter to allow runtime switching.
 * - ADDED: isLogic is now serialized in getPersistentState/restoreState.
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
    // CONFIGURATION
    // =========================================================================

    /**
     * Determines the timing model for this atom.
     *
     * - true (Digital/Logic): Output changes are scheduled for the NEXT tick.
     *   Stabilizes feedback loops. Essential for gates (NAND, NOT).
     *
     * - false (Analog/Driver): Output changes happen IMMEDIATELY.
     *   Zero latency. Essential for Audio, Visuals, wires.
     */
    public var isLogic(get, set):Bool;
    private var _isLogic:Bool = false;

    private function get_isLogic():Bool return _isLogic;
    
    /**
     * Setter allows changing logic mode at runtime.
     * Override in Assembly to update port connections.
     */
    private function set_isLogic(value:Bool):Bool {
        _isLogic = value;
        return _isLogic;
    }

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

        // === v6.4 FIX: SCHEDULE INITIAL CALCULATION ===
        // Мы не вызываем _calculate() напрямую, потому что в этот момент
        // isLogic еще false (для наследников вроде NandAtom, которые ставят true после super).
        // Планирование задачи решает проблему:
        // 1. При загрузке схемы SignalQueue suspended -> задача ждет.
        // 2. restoreState() ставит isLogic = true.
        // 3. resume() запускает задачу -> _calculate видит уже правильный isLogic.
        if (_process != null) {
            _isScheduled = true;
            SignalQueue.getInstance().schedule(_calculate, NORMAL);
        }
        // =============================================

        if (_isActive) {
            DriverManager.getInstance().register(this);
        }
    }

    // =========================================================================
    // BINDING
    // =========================================================================

    private function _bind():Void {
        for (input in _inputs) {
            if (input != null) input.owner = this;
        }
        for (output in _outputs) {
            if (output != null) output.owner = this;
        }
    }

    // =========================================================================
    // LIFECYCLE
    // =========================================================================

    public function init():Void { }

    public function update(dt:Float):Void {
        _onUpdate(dt);
    }

    private function _onUpdate(dt:Float):Void { }

    // =========================================================================
    // CONTACT CHANGE HANDLING
    // =========================================================================

    public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;

        if (c.type == OUTPUT && c.owner == this) {
            return;
        }

        if (_process != null) {
            _isScheduled = true;
            core.logic.SignalQueue.getInstance().schedule(_calculate, NORMAL);
        }
    }

    /**
     * Выполнить вычисление и передать результаты на выходы.
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

            if (isLogic) {
                // ЦИФРОВОЙ РЕЖИМ (Unit Delay)
                var outs = _outputs;
                var vals = results;

                SignalQueue.getInstance().scheduleNextTick(function() {
                    if (_isDisposed) return;
                    for (i in 0...outs.length) {
                        if (outs[i] != null) outs[i].value = vals[i];
                    }
                });

            } else {
                // АНАЛОГОВЫЙ РЕЖИМ (Immediate)
                for (i in 0..._outputs.length) {
                    if (_outputs[i] != null) _outputs[i].value = results[i];
                }
            }
        }
    }

    // =========================================================================
    // STATE SERIALIZATION (Databank)
    // =========================================================================

    public function getPersistentState():Dynamic {
        return { isLogic: _isLogic };
    }

    public function restoreState(state:Dynamic):Void {
        if (state == null) return;
        if (Reflect.hasField(state, "isLogic")) {
            this.isLogic = state.isLogic;
        }
    }

    // =========================================================================
    // GETTERS
    // =========================================================================

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    public function getInput(name:String):Contact {
        if (_inputs == null) return null;
        for (c in _inputs) {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

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

    public function dispose():Void {
        _isDisposed = true;

        if (_isActive) {
            DriverManager.getInstance().unregister(this.id);
        }

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

        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}