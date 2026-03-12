package core.view;

import core.base.Atom;
import core.base.Assembly;
import core.data.Blueprint;

/**
 * DEVICE WIDGET FACTORY v1.0
 * Фабрика для создания DeviceView по типу или Blueprint.
 */
class DeviceWidgetFactory {

    /**
     * Создать DeviceView для атома по его типу.
     */
    public static function create(atom:Atom):DeviceView {
        if (atom == null) {
            trace('DeviceWidgetFactory.create: atom is null');
            return null;
        }
        
        trace('DeviceWidgetFactory.create: atom.type=${atom.type}');
        
        try {
            // 1. СНАЧАЛА проверяем Assembly (это предотвращает рекурсию)
            if (Std.isOfType(atom, Assembly)) {
                trace('DeviceWidgetFactory.create: atom is Assembly, calling createForAssembly');
                var asm:Assembly = cast(atom, Assembly);
                return createForAssembly(asm);
            }
            
            // 2. Для обычных атомов проверяем их собственный метод создания
            trace('DeviceWidgetFactory.create: calling atom.createDeviceView()');
            var view = atom.createDeviceView();
            if (view != null) {
                trace('DeviceWidgetFactory.create: atom returned custom view');
                return view;
            }
            
            // 3. Fallback - определяем по типу атома
            trace('DeviceWidgetFactory.create: using createByAtomType fallback');
            return createByAtomType(atom);
        } catch (e:Dynamic) {
            trace('DeviceWidgetFactory: Error creating view for ${atom.type}: $e');
            return null;
        }
    }
    
    /**
     * Создать DeviceView для Assembly по blueprint.deviceType.
     */
    private static function createForAssembly(asm:Assembly):DeviceView {
        if (asm == null || asm.blueprint == null) {
            trace('DeviceWidgetFactory.createForAssembly: asm or blueprint is null');
            return null;
        }
        
        trace('DeviceWidgetFactory.createForAssembly: blueprint.name=${asm.blueprint.name}');
        
        var bp = asm.blueprint;
        var deviceType:String = bp.deviceType;
        
        trace('DeviceWidgetFactory.createForAssembly: deviceType=$deviceType');
        
        if (deviceType == null || deviceType == "") {
            // Нет типа устройства - используем PanelWidget
            trace('DeviceWidgetFactory.createForAssembly: no deviceType, creating PanelWidget');
            return new PanelWidget(asm);
        }
        
        trace('DeviceWidgetFactory.createForAssembly: creating widget for type $deviceType');
        
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
                
            default:
                // Попытка найти класс виджета по имени
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
            case "led", "ledatom":
                new LEDWidget(atom, "in");
                
            case "button", "buttonatom":
                new ButtonWidget(atom, "out");
                
            case "relay", "relayatom":
                new ToggleWidget(atom, "control");
                
            case "display", "alphanumericline":
                new TextWidget(atom, "in");
                
            default:
                // Универсальный виджет - текстовое отображение
                new TextWidget(atom);
        }
    }
    
    /**
     * Попытка создать виджет по имени класса.
     */
    private static function createByClassName(className:String, atom:Atom):DeviceView {
        // Пытаемся найти класс в пакете core.view
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
            trace('DeviceWidgetFactory: Failed to create $className: $e');
        }
        
        // Fallback
        return new TextWidget(atom);
    }
    
    /**
     * Получить имя контакта из Blueprint.
     */
    private static function getContactName(bp:Blueprint, defaultName:String):String {
        if (bp == null || bp.pins == null) return defaultName;
        
        for (pin in bp.pins) {
            if (pin.name != null) return pin.name;
        }
        
        return defaultName;
    }
}
