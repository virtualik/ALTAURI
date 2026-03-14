package core.base;

import library.AtomRegistry;
import core.data.Blueprint;
import utils.UID;

// Импорты нативных классов
import library.drivers.SignalGeneratorAtom;
import library.drivers.FPSMonitorAtom;
import library.drivers.FrameTimeAtom;
import library.drivers.AudioInputAtom;
import library.logic.NandAtom;
import library.electro.ButtonAtom;
import library.electro.LedAtom;
import library.electro.RelayAtom;
import library.electro.OscilloscopeAtom;

/**
 * ASSEMBLY FACTORY v4.1 (Native Class Support)
 * Создает правильные экземпляры классов для нативных атомов.
 */
class AssemblyFactory {

    /**
     * Creates an Atom or Assembly instance.
     * If forcedId is null, generates a new UUID.
     */
    public static function createAtom(typeId:String, ?forcedId:String):Atom {
        var bp = AtomRegistry.get(typeId);
        var id:String = (forcedId != null) ? forcedId : UID.generate();

        if (bp == null) {
            trace('ERROR: Blueprint not found: $typeId');
            return null;
        }

        // === ВАЖНОЕ ИСПРАВЛЕНИЕ: Проверка типа для создания нужного класса ===
        // Мы проверяем ID чертежа и возвращаем соответствующий Java-класс (Haxe класс).
        // Assembly создается только для пользовательских сборок (где logic == null и есть internalAtoms)
        // или если это "пустая" нативная сборка.
        
        switch (typeId) {
            // Active Drivers
            case "SignalGen": return new SignalGeneratorAtom(id);
            case "FPSMonitor": return new FPSMonitorAtom(id);
            case "FrameTime": return new FrameTimeAtom(id);
            case "AudioIn": return new AudioInputAtom(id);
            
            // Logic
            case "NAND": return new NandAtom(id);
            
            // Electro
            case "Button": return new ButtonAtom(id);
            case "LED": return new LedAtom(id);
            case "Relay": return new RelayAtom(id);
            case "Oscilloscope": return new OscilloscopeAtom(id);
        }

        // Если это не нативный атом, создаем Assembly (составную сборку)
        return new Assembly(id, bp);
    }

    public static function createAssembly(typeId:String):Assembly {
        var atom = createAtom(typeId);
        if (Std.isOfType(atom, Assembly)) {
            return cast atom;
        } else {
            // Если это нативный атом, а не сборка, можно обернуть его или вернуть null/ошибку
            trace('WARN: $typeId is a native Atom, not an Assembly.');
            return null; 
        }
    }

    public static function isComposite(typeId:String):Bool {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return false;
        
        // Если есть зарегистрированный нативный класс, это не композит (с точки зрения редактора)
        // Или если logic задан, это нативный функционал.
        // Но для вашего редактора "Composite" означает "можно открыть внутрь".
        // Сигнал генератор нельзя открыть внутрь.
        if (bp.logic != null) return false;
        
        return (bp.internalAtoms != null && bp.internalAtoms.length > 0);
    }
}