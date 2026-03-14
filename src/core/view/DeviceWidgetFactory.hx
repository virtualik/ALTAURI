package core.view;

import core.base.Atom;
import core.base.Assembly;
import core.data.Blueprint;

/**
 * DEVICE WIDGET FACTORY v1.1
 * Фабрика для создания DeviceView по типу или Blueprint.
 */
class DeviceWidgetFactory {

    /**
     * Создать DeviceView для атома по его типу.
     */
    public static function create(atom:Atom):DeviceView {
        if (atom == null) return null;

        try {
            // 1. СНАЧАЛА проверяем Assembly (это предотвращает рекурсию)
            if (Std.isOfType(atom, Assembly)) {
                var asm:Assembly = cast(atom, Assembly);
                return createForAssembly(asm);
            }

            // 2. Для обычных атомов проверяем их собственный метод создания
            var view = atom.createDeviceView();
            if (view != null) return view;

            // 3. Fallback - определяем по типу атома
            return createByAtomType(atom);
        } catch (e:Dynamic) {
            trace('Error creating DeviceView: $e');
            return null;
        }
    }

    /**
     * Создать DeviceView для Assembly по blueprint.deviceType.
     */
    private static function createForAssembly(asm:Assembly):DeviceView {
        if (asm == null || asm.blueprint == null) return null;

        var bp = asm.blueprint;
        var deviceType:String = bp.deviceType;

        if (deviceType == null || deviceType == "") {
            // Нет типа устройства - используем PanelWidget
            return new PanelWidget(asm);
        }

        return switch (deviceType.toLowerCase()) {
            case "led", "indicator", "light":
                new LEDWidget(asm, getContactName(bp, "in"));

            case "toggle", "switch":
                new ToggleWidget(asm, getContactName(bp, "out"));

            case "button", "push":
                new ButtonWidget(asm, getContactName(bp, "out"));

            case "text", "display", "label":
                new TextWidget(asm, getContactName(bp, "value"));

            case "panel", "container", "group":
                new PanelWidget(asm);

            case "oscilloscope", "scope":
                // ИСПРАВЛЕНО: Ищем первый контакт, если имя не задано
                new OscilloscopeWidget(asm, getContactName(bp, "in"));

            default:
                createByClassName(deviceType, asm);
        }
    }

    /**
     * Создать DeviceView по типу атома.
     */
    private static function createByAtomType(atom:Atom):DeviceView {
        if (atom == null) return null;

        var type = atom.type.toLowerCase();

        return switch (type) {
            case "led", "led indicator":
                new LEDWidget(atom, "in");

            case "button", "push button":
                new ButtonWidget(atom, "out");
                
            case "oscilloscope":
                new OscilloscopeWidget(atom, "in");

            default:
                // Универсальный виджет - текстовое отображение
                new TextWidget(atom);
        }
    }

    /**
     * Попытка создать виджет по имени класса.
     */
    private static function createByClassName(className:String, atom:Atom):DeviceView {
        var fullClassName = "core.view." + className;

        try {
            var cls = Type.resolveClass(fullClassName);
            if (cls != null) {
                var instance = Type.createInstance(cls, [atom]);
                if (Std.isOfType(instance, DeviceView)) {
                    return cast(instance, DeviceView);
                }
            }
        } catch (e:Dynamic) { }

        // Fallback
        return new TextWidget(atom);
    }

    /**
     * Получить имя контакта из Blueprint.
     * Ищет любой контакт, приоритет -- заданному defaultName, иначе первый попавшийся.
     */
    private static function getContactName(bp:Blueprint, defaultName:String):String {
        if (bp == null || bp.pins == null) return defaultName;

        // Сначала ищем точное совпадение с defaultName
        for (pin in bp.pins) {
            if (pin.name == defaultName) return pin.name;
        }

        // Если не нашли, возвращаем имя первого пина
        for (pin in bp.pins) {
            if (pin.name != null) return pin.name;
        }

        return defaultName;
    }
}