package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * RELAY ATOM v1.3 (Combined)
 * Реле - пропускает сигнал только когда управление активно.
 * 
 * Changes:
 * - v1.2: Fix: Reset Schedule Flag inside _calculate.
 * - v1.1: Added State Serialization (getPersistentState, restoreState).
 */
class RelayAtom extends Atom {

    // Кэшированные значения для быстрого доступа
    private var _signalValue:Dynamic = null;
    private var _controlValue:Bool = false;

    public function new(id:String) {
        super(
            [
                new Contact(null, INPUT, "signal"),   // Что передаем
                new Contact(false, INPUT, "control")  // Открываем (True) или Закрываем (False)
            ],
            [
                new Contact(null, OUTPUT, "out")
            ],
            null,
            id,
            "Relay"
        );
    }

    // Логика реле
    override function onContactChanged(c:Contact):Void {
        // Обновляем кэшированные значения
        if (_inputs != null && _inputs.length >= 2) {
            _signalValue = _inputs[0].value;
            _controlValue = _inputs[1].value == true;
        }
        
        // Если изменился сигнал или управление - пересчитываем
        super.onContactChanged(c);
    }

    override function _calculate():Void {
        // === ВАЖНОЕ ИСПРАВЛЕНИЕ (из v1.2) ===
        // Сбрасываем флаг планировщика, иначе этот метод больше никогда не вызовется
        _isScheduled = false;
        // ===================================

        if (_inputs == null || _inputs.length < 2) return;

        var signal = _inputs[0].value;
        var control = _inputs[1].value;

        if (control == true) {
            // Если управление активно, пропускаем сигнал
            _outputs[0].value = signal;
        } else {
            // Если закрыто, передаем null
            _outputs[0].value = null;
        }
    }

    // =========================================================================
    // STATE SERIALIZATION (из v1.1)
    // =========================================================================

    /**
     * Save relay state for persistence.
     * Returns the last output value so the relay can restore its state.
     */
    override public function getPersistentState():Dynamic {
        var outputValue:Dynamic = null;
        if (_outputs != null && _outputs.length > 0) {
            outputValue = _outputs[0].value;
        }
        
        return { 
            lastOutput: outputValue,
            controlState: _controlValue
        };
    }

    /**
     * Restore relay state from saved data.
     * Called when loading a project to restore the relay's output state.
     */
    override public function restoreState(state:Dynamic):Void {
        if (state != null) {
            // Restore the output value if it was saved
            if (state.lastOutput != null && _outputs != null && _outputs.length > 0) {
                _outputs[0].value = state.lastOutput;
            }
            // Restore control state for internal tracking
            if (state.controlState != null) {
                _controlValue = state.controlState;
            }
        }
    }

    /**
     * Check if relay is currently open (passing signal).
     */
    public function isOpen():Bool {
        return _controlValue;
    }

    /**
     * Get the last signal value that was passed through.
     */
    public function getLastSignal():Dynamic {
        return _signalValue;
    }
}