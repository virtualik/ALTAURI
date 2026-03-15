package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TEXT INPUT ATOM v1.2
 * Пассивный атом для ввода строковых или числовых значений.
 * v1.2 Fix: Correctly resets _isScheduled flag.
 * v1.2 New: Implements State Serialization.
 */
class TextInputAtom extends Atom {

    public function new(id:String) {
        super(
            [
                new Contact(null, INPUT, "set")
            ],
            [
                new Contact("", OUTPUT, "out")
            ],
            null,
            id,
            "TextInput"
        );
    }

    // Если на вход "set" пришло значение, транслируем его на выход
    override private function _calculate():Void {
        // ВАЖНО: Сбрасываем флаг планировщика, иначе этот метод больше никогда не вызовется
        _isScheduled = false; 
        
        var val = _inputs[0].value;
        if (val != null) {
            _outputs[0].value = val;
        }
    }

    // --- STATE SERIALIZATION ---

    // Сохраняем текущее значение выхода
    override public function getPersistentState():Dynamic {
        return { value: _outputs[0].value };
    }

    // При загрузке восстанавливаем значение
    override public function restoreState(state:Dynamic):Void {
        if (state != null && state.value != null) {
            _outputs[0].value = state.value;
        }
    }
}