package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TOGGLE ATOM v1.0 (Stateful)
 * Переключатель с сохранением состояния.
 */
class ToggleAtom extends Atom {

    public function new(id:String) {
        super(
            [], // Нет входов
            [new Contact(false, OUTPUT, "out")], // Один выход
            null,
            id,
            "Toggle"
        );
    }

    // Сохраняем текущее значение выхода
    override public function getPersistentState():Dynamic {
        return { state: _outputs[0].value };
    }

    // Восстанавливаем значение при загрузке
    override public function restoreState(state:Dynamic):Void {
        if (state != null && state.state != null) {
            _outputs[0].value = state.state;
        }
    }
}