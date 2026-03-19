package library.electro;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
* LED ATOM v1.1 (Passive Display)
* Пассивный атом-индикатор. Не имеет логики обработки.
* View подписывается на входной контакт и отображает состояние.
*/
class LedAtom extends Atom {
    public function new(id:String) {
        super(
            [new Contact(false, INPUT, "in")],
            [],  // Нет выходов
            null, // Нет функции обработки
            id,
            "LED",
            false // Не активный драйвер
        );
    }
}