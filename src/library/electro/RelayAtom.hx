package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

class RelayAtom extends Atom {
    
    public function new(id:String) {
        super(
            [
                new Contact(null, INPUT, "signal"),   // Что передаем
                new Contact(false, INPUT, "control")  // Открываем (True) или Закрываем (False)
            ],
            [new Contact(null, OUTPUT, "out")],
            null,
            id,
            "Relay"
        );
    }

    // Логика реле
    override function onContactChanged(c:Contact):Void {
        // Если изменился сигнал или управление - пересчитываем
        super.onContactChanged(c);
    }

    override function _calculate():Void {
        var signal = _inputs[0].value;
        var control = _inputs[1].value;

        if (control == true) {
            // Если управление активно, пропускаем сигнал
            _outputs[0].value = signal; 
        } else {
            // Если закрыто, можно слать null или false (зависит от логики схемы)
            _outputs[0].value = null; 
        }
    }
}