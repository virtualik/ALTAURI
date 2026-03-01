package core.base;

import core.types.ContactType;

/**
 * CONDUCTOR PORT v1.0
 * "Пробрасывающий" элемент. Пара контактов, соединяющих внешнюю и внутреннюю стороны сборки.
 */
class ConductorPort {
    
    public var name(default, null):String;
    public var type(default, null):ContactType; // Тип порта СБОРОЧНЫЙ (INPUT или OUTPUT)

    // Контакт, смотрящий ВНЕ (используется, когда сборка - это атом в другой схеме)
    public var external(default, null):Contact;

    // Контакт, смотрящий ВНУТРЬ (используется при редактировании схемы)
    public var internal(default, null):Contact;

    public function new(name:String, type:ContactType, defaultValue:Dynamic = null) {
        this.name = name;
        this.type = type;

        if (type == INPUT) {
            // ВХОД СБОРКИ:
            // Снаружи это Вход (Orange). Принимает данные.
            external = new Contact(defaultValue, INPUT, name + "_ext_in");
            
            // Внутри это Выход (Green). Раздает данные внутрь схемы.
            internal = new Contact(defaultValue, OUTPUT, name + "_int_out");

            // Связь: Данные вливаются в external -> вытекают из internal
            // Контакт типа INPUT при получении значения (set_value) оповещает подписчиков.
            // Мы просто линкуем external -> internal.
            external.link(internal);
        } else {
            // ВЫХОД СБОРКИ:
            // Внутри это Вход (Orange). Принимает данные из схемы.
            internal = new Contact(defaultValue, INPUT, name + "_int_in");

            // Снаружи это Выход (Green). Выдает данные наружу.
            external = new Contact(defaultValue, OUTPUT, name + "_ext_out");

            // Связь: Данные вливаются в internal -> вытекают из external
            internal.link(external);
        }
    }

    public function dispose():Void {
        external.dispose();
        internal.dispose();
    }
}