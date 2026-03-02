package core.base;

import core.types.ContactType;

/**
 * CONDUCTOR PORT v1.1
 * Пробрасывающий элемент. Пара контактов, соединяющих внешнюю и внутреннюю стороны сборки.
 * 
 * CHANGES v1.1:
 * - Contacts now use the port name directly (not with suffix)
 * - This fixes wire positioning in NodeView
 */
class ConductorPort {

    public var name(default, null):String;
    public var type(default, null):ContactType;

    // Контакт, смотрящий ВНЕ
    public var external(default, null):Contact;

    // Контакт, смотрящий ВНУТРЬ
    public var internal(default, null):Contact;

    public function new(name:String, type:ContactType, defaultValue:Dynamic = null) {
        this.name = name;
        this.type = type;

        if (type == INPUT) {
            // ВХОД СБОРКИ:
            // Снаружи это Вход (Orange). Принимает данные.
            // ИСПРАВЛЕНИЕ: используем имя порта напрямую
            external = new Contact(defaultValue, INPUT, name);

            // Внутри это Выход (Green). Раздает данные внутрь схемы.
            internal = new Contact(defaultValue, OUTPUT, name + "_int");

            external.link(internal);
        } else {
            // ВЫХОД СБОРКИ:
            // Внутри это Вход (Orange). Принимает данные из схемы.
            internal = new Contact(defaultValue, INPUT, name + "_int");

            // Снаружи это Выход (Green). Выдает данные наружу.
            // ИСПРАВЛЕНИЕ: используем имя порта напрямую
            external = new Contact(defaultValue, OUTPUT, name);

            internal.link(external);
        }
    }

    public function dispose():Void {
        external.dispose();
        internal.dispose();
    }
}