package core.base;

import core.types.ContactType;

/**
 * CONDUCTOR PORT v1.3 (DeviceView Compatible)
 * Пробрасывающий элемент. Пара контактов, соединяющих внешнюю и внутреннюю стороны сборки.
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
            external = new Contact(defaultValue, INPUT, name);
            internal = new Contact(defaultValue, OUTPUT, name + "_int");
            external.link(internal);
        } else {
            // ВЫХОД СБОРКИ:
            internal = new Contact(defaultValue, INPUT, name + "_int");
            external = new Contact(defaultValue, OUTPUT, name);
            internal.link(external);
        }
    }

    /**
     * Properly dispose the port and its contacts.
     */
    public function dispose():Void {
        if (external != null && internal != null) {
            external.unlink(internal);
            internal.unlink(external);
        }

        if (external != null) {
            external.dispose();
        }
        if (internal != null) {
            internal.dispose();
        }

        external = null;
        internal = null;
    }
}
