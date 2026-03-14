package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * OSCILLOSCOPE ATOM v1.0
 * Пассивный атом-дисплей.
 * Имеет вход для массива сэмплов.
 */
class OscilloscopeAtom extends Atom {

    public function new(id:String) {
        super(
            [
                // Вход для буфера сэмплов
                new Contact(null, INPUT, "in")
            ],
            [], // Нет выходов
            null,
            id,
            "Oscilloscope"
        );
    }
    
    // Логика не нужна, Contact сам уведомит View через подписку
}