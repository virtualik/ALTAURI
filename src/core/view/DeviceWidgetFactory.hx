package core.view;

import core.base.Atom;
import core.base.Assembly;
import core.data.Blueprint;

/**
 * DEVICE WIDGET FACTORY v1.1
 * Фабрика для создания DeviceView (Лица Атома).
 *
 * Полностью отделена от логики Атома.
 * Определяет какой виджет создать на основе типа атома или Blueprint.
 *
 * Архитектура "Atom is Databank & Compute Core":
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Атом (Databank + Compute)                                             │
 * │         │                                                               │
 * │         │ DeviceWidgetFactory.create(atom)                              │
 * │         ▼                                                               │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │ DeviceWidgetFactory                                              │   │
 * │   │                                                                  │   │
 * │   │ switch (atom.type) {                                             │   │
 * │   │     case "Oscilloscope": return new OscilloscopeWidget(atom);   │   │
 * │   │     case "Button": return new ButtonWidget(atom);               │   │
 * │   │     case "Toggle": return new ToggleWidget(atom);               │   │
 * │   │     case "LED": return new LEDWidget(atom);                     │   │
 * │   │     case "TextInput": return new TextInputWidget(atom);         │   │
 * │   │     case "AudioIn": return new OscilloscopeWidget(atom, "samples"); │
 * │   │     default: return new TextWidget(atom);                       │   │
 * │   │ }                                                                │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │         │                                                               │
 * │         ▼                                                               │
 * │   DeviceView (Лицо Атома)                                               │
 * │   - Подписывается на Contact атома                                      │
 * │   - Отображает данные из Databank атома                                 │
 * │   - НЕ хранит бизнес-данные                                             │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class DeviceWidgetFactory {

    /**
     * Создать DeviceView для атома.
     *
     * Это ТОЧКА ВХОДА для создания Лица Атома.
     *
     * ПРИНЦИП: Один атом = один виджет.
     * Используйте DeviceViewRegistry.getOrCreate() вместо прямого вызова этого метода.
     *
     * @param atom Атом для которого создаётся виджет
     * @return DeviceView или null если атом null или тип не поддерживается
     */
    public static function create(atom:Atom):DeviceView {
        if (atom == null) return null;

        try {
            // 1. Сначала проверяем Assembly (это предотвращает рекурсию)
            if (Std.isOfType(atom, Assembly)) {
                var asm:Assembly = cast(atom, Assembly);
                return createForAssembly(asm);
            }

            // 2. Нативные атомы - по типу
            return createByAtomType(atom);

        } catch (e:Dynamic) {
            trace('DeviceWidgetFactory: Error creating widget for atom "${atom.name}": $e');
            return null;
        }
    }

    /**
     * Создать виджет для Assembly по blueprint.deviceType.
     */
    private static function createForAssembly(asm:Assembly):DeviceView {
        if (asm == null || asm.blueprint == null) return null;

        var bp = asm.blueprint;
        var deviceType:String = bp.deviceType;

        // Если deviceType не указан - PanelWidget (контейнер)
        if (deviceType == null || deviceType == "") {
            return new PanelWidget(asm);
        }

        // Определяем по deviceType
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
                new OscilloscopeWidget(asm, "in");

            case "textinput":
                new TextInputWidget(asm);
				
			case "signalgenerator":
				new SignalGeneratorWidget(asm);

            case "audioinput", "audio":
                // AudioInput показывает samples как осциллограмму
                new OscilloscopeWidget(asm, "samples");

            default:
                // Пробуем найти класс по имени
                createByClassName(deviceType, asm);
        }
    }

    /**
     * Создать виджет по типу атома (для нативных атомов).
     */
    private static function createByAtomType(atom:Atom):DeviceView {
        if (atom == null) return null;

        var type = atom.type.toLowerCase();

        return switch (type) {
            case "led", "led indicator":
                new LEDWidget(atom, "in");

            case "button", "push button":
                new ButtonWidget(atom, "out");

            case "toggle", "switch":
                new ToggleWidget(atom, "out");

            case "oscilloscope":
                new OscilloscopeWidget(atom, "in");

            case "textinput":
                new TextInputWidget(atom);

            case "audioin", "audioinput", "audio":
                new OscilloscopeWidget(atom, "samples");

            case "relay":
                // Показываем выход "out"
                new TextWidget(atom, "out", false);
			
			case "signalgenerator":
				new SignalGeneratorWidget(atom);

            case "universlgen", "universalgenerator":
                new TextWidget(atom, "out", false);
				
			case "miniaudioatom", "mini audio capture":
                // Временный fallback: показываем панель со всеми контактами.
                // В будущем, когда напишешь MiniAudioWidget, заменишь на:
                // return new MiniAudioWidget(atom);
                //new PanelWidget(atom);
				new TextWidget(atom);
			
            default:
                // Универсальный виджет - текстовое отображение
                new TextWidget(atom);
        }
    }

    /**
     * Попытка создать виджет по имени класса.
     * Позволяет расширять систему без изменения Factory.
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
        } catch (e:Dynamic) {
            // Игнорируем ошибки - вернём fallback
        }

        // Fallback - универсальный виджет
        return new TextWidget(atom);
    }

    /**
     * Найти имя контакта в Blueprint.
     * Используется для определения контакта для отображения.
     */
    private static function getContactName(bp:Blueprint, defaultName:String):String {
        if (bp == null || bp.pins == null) return defaultName;

        // Ищем точное совпадение
        for (pin in bp.pins) {
            if (pin.name == defaultName) return pin.name;
        }

        // Берём первый попавшийся
        for (pin in bp.pins) {
            if (pin.name != null) return pin.name;
        }

        return defaultName;
    }

    /**
     * Проверить поддерживается ли тип атома.
     */
    public static function isSupported(atomType:String):Bool {
        if (atomType == null) return false;

        var type = atomType.toLowerCase();

        return switch (type) {
            case "led" | "button" | "toggle" | "oscilloscope" | "textinput" |
                 "audioin" | "audioinput" | "relay" | "conductor" |
                 "universalgen" | "signalgen" | "fpsmonitor" | "frametime":
                true;

            default:
                // Проверяем Assembly
                true; // PanelWidget как fallback
        }
    }
}