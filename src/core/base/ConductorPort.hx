package core.base;

import core.types.ContactType;

/**
 * CONDUCTOR PORT v1.2 (Memory Leak Fixed)
 * Пробрасывающий элемент. Пара контактов, соединяющих внешнюю и внутреннюю стороны сборки.
 *
 * CHANGES v1.2:
 * - Fixed: dispose() now unlinks contacts before clearing
 * - Fixed: Clear owner references to prevent dangling pointers
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
            external = new Contact(defaultValue, INPUT, name);
            // Внутри это Выход (Green). Раздает данные внутрь схемы.
            internal = new Contact(defaultValue, OUTPUT, name + "_int");
            external.link(internal);
        } else {
            // ВЫХОД СБОРКИ:
            // Внутри это Вход (Orange). Принимает данные из схемы.
            internal = new Contact(defaultValue, INPUT, name + "_int");
            // Снаружи это Выход (Green). Выдает данные наружу.
            external = new Contact(defaultValue, OUTPUT, name);
            internal.link(external);
        }
    }

    /**
     * Properly dispose the port and its contacts.
     * FIX v1.2: Unlink before dispose to break reference cycles.
     */
    public function dispose():Void {
        // 1. Break the link between external and internal
        if (external != null && internal != null) {
            external.unlink(internal);
            internal.unlink(external);
        }
        
        // 2. Dispose contacts (clears their linkedTargets and callbackTargets)
        if (external != null) {
            external.dispose();
        }
        if (internal != null) {
            internal.dispose();
        }
        
        // 3. Clear references
        external = null;
        internal = null;
    }
}
