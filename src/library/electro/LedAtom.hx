package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.SignalQueue;
import core.types.Priority;

class LedAtom extends Atom {
    
    public function new(id:String) {
        super(
            [new Contact(false, INPUT, "in")],
            [],
            null,
            id,
            "LED"
        );
    }

    // Логика: при изменении входа, мы ничего не считаем (нет выходов),
    // но можем поменять внутреннее состояние, которое увидит View.
    
    // В текущей архитектуре Atom не знает о своей View.
    // Но View подписывается на Contact.
    
    // Поэтому просто оставим Атом "пассивным". 
    // NodeView сам подпишется на вход и покрасит ноду в зеленый, если там true.
}