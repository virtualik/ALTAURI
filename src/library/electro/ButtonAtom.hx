package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import openfl.events.MouseEvent;

class ButtonAtom extends Atom {
    
    private var _state:Bool = false;

    public function new(id:String) {
        super(
            [],
            [new Contact(false, OUTPUT, "out")],
            null,
            id,
            "Button"
        );
    }

    // Логика нажатия будет управляться извне (например, через Click на View)
    // Но для простоты пока сделаем toggle по "активации" (если такое будет)
    // Или оставим это UI слою.
    
    // Однако, давай сделаем Toggle для теста, чтобы можно было щелкать по ноде
    // (Это нужно будет добавить в NodeView клик по самому телу атома)
    
    public function toggle():Void {
        _state = !_state;
        _outputs[0].value = _state;
    }
}