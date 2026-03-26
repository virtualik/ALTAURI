package library.logic;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.logic.SignalQueue;
import core.types.Priority;

/**
 * OR Gate ATOM v1.2 (Stable Initialization)
 * Multi-input OR gate with dynamic port management.
 *
 * v1.2 Changes:
 * - FIXED: Default input values (false) for stable initial state.
 * - FIXED: Proper handling of null inputs in _calculate.
 *
 * v1.1 Changes:
 * - Architecture documentation added.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ConductorAtom (Databank)                                              │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   onContactChanged() → schedule(_calculate)                             │
 * │   _calculate() { result = OR(all inputs); output = result; }            │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   _ORGateInputCount:Int = 2  // Number of input ports                │
 * │   addInput()    → creates new Contact                                   │
 * │   removeLastInput() → removes last Contact                              │
 * │   getPersistentState() → { inputCount: N }                              │
 * │   restoreState() → recreates inputs                                     │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   ConductorWidget shows:                                                │
 * │   - Current ON/OFF state                                                │
 * │   - Input count                                                         │
 * │   - Add/Remove buttons                                                  │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Principle:
 * - 2-20 inputs (dynamically addable)
 * - Output = true if ANY input = true
 * - Output = false only if ALL inputs = false
 */
class ORGateAtom extends Atom {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    public static inline var MIN_INPUTS:Int = 2;
    public static inline var MAX_INPUTS:Int = 20;

    // =========================================================================
    // DATABANK
    // =========================================================================

    private var _ORGateInputCount:Int = 2;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(id:String, ?initialInputs:Int = 2) {
        _ORGateInputCount = Std.int(Math.max(MIN_INPUTS, Math.min(initialInputs, MAX_INPUTS)));

        // Create inputs
        var inputs:Array<Contact> = [];
        for (i in 0..._ORGateInputCount) {
            // === FIX v1.2: Начальное значение false (pull-down для OR) ===
            inputs.push(new Contact(false, INPUT, "in" + i));
        }

        // Create outputs
        var outputs:Array<Contact> = [
            new Contact(false, OUTPUT, "out")
        ];

        super(inputs, outputs, null, id, "Conductor");
        
        // ВАЖНО: Это логический вентиль
        this.isLogic = true;
    }

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================

    override public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;
        _isScheduled = true;
        SignalQueue.getInstance().schedule(_calculate, NORMAL);
    }

    override private function _calculate():Void {
        // ВАЖНО: Сбрасываем флаг в самом начале
        _isScheduled = false;

        if (_isDisposed || _inputs == null || _outputs == null) return;
        if (_outputs.length < 1) return;

        // OR: true if ANY input is true
        var result:Bool = false;

        for (input in _inputs) {
            // === FIX v1.2: null трактуется как false ===
            if (input != null && input.value == true) {
                result = true;
                break;
            }
        }

        // === ИСПРАВЛЕНИЕ: Уважаем флаг isLogic ===
        if (isLogic) {
            // ЦИФРОВОЙ РЕЖИМ: Записываем результат в следующем такте
            var val = result;
            var out = _outputs[0];
            
            SignalQueue.getInstance().scheduleNextTick(function() {
                if (!_isDisposed && out != null) {
                    out.value = val;
                }
            });
        } else {
            // АНАЛОГОВЫЙ РЕЖИМ: Мгновенная запись
            _outputs[0].value = result;
        }
    }

    // =========================================================================
    // DYNAMIC PORT MANAGEMENT
    // =========================================================================

    /**
     * Add a new input port.
     * @return Name of the new port, or null if limit reached
     */
    public function addInput():String {
        if (_inputs.length >= MAX_INPUTS) {
            trace('ConductorAtom: Max inputs ($MAX_INPUTS) reached');
            return null;
        }

        var newName = "in" + _inputs.length;
        var newContact = new Contact(false, INPUT, newName);
        newContact.owner = this;
        _inputs.push(newContact);
        _ORGateInputCount = _inputs.length;

        // Extend cache
        while (_inputCache.length < _inputs.length) {
            _inputCache.push(null);
        }

        // Recalculate
        _calculate();

        trace('ConductorAtom: Added $newName (total: $_ORGateInputCount)');
        return newName;
    }

    /**
     * Remove the last input port.
     * @return true if successful
     */
    public function removeLastInput():Bool {
        if (_inputs.length <= MIN_INPUTS) {
            trace('ConductorAtom: Min inputs ($MIN_INPUTS) reached');
            return false;
        }

        var removed = _inputs.pop();
        if (removed != null) {
            removed.dispose();
        }

        _ORGateInputCount = _inputs.length;
        _calculate();

        trace('ConductorAtom: Removed input (total: $_ORGateInputCount)');
        return true;
    }

    public function getInputCount():Int {
        return _inputs != null ? _inputs.length : 0;
    }

    // =========================================================================
    // STATE SERIALIZATION (Databank Persistence)
    // =========================================================================

    override public function getPersistentState():Dynamic {
        return { inputCount: _ORGateInputCount };
    }

    override public function restoreState(state:Dynamic):Void {
        if (state == null || state.inputCount == null) return;

        var targetCount = Std.int(Math.max(MIN_INPUTS, Math.min(state.inputCount, MAX_INPUTS)));

        // Add or remove inputs to match target
        while (_inputs.length < targetCount) {
            var newName = "in" + _inputs.length;
            var newContact = new Contact(false, INPUT, newName);
            newContact.owner = this;
            _inputs.push(newContact);
        }
        while (_inputs.length > targetCount) {
            var removed = _inputs.pop();
            if (removed != null) removed.dispose();
        }

        _ORGateInputCount = _inputs.length;

        // Extend cache
        while (_inputCache.length < _inputs.length) {
            _inputCache.push(null);
        }
    }
}