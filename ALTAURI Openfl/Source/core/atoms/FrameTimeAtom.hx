package core.atoms;

import core.Atom;
import core.Contact;

/**
 * FRAME TIME ATOM
 * Активный атом, измеряющий длительность кадра (Delta Time) в миллисекундах.
 * Работает через DriverManager.
 */
class FrameTimeAtom extends Atom {

    public function new(id:String) {
        // Вызываем родительский конструктор:
        // 1. Нет входов.
        // 2. Один выход "ms" (Float).
        // 3. Нет логики обработки (_process = null).
        // 4. isActive = true (ВАЖНО! Это регистрирует его в DriverManager).
        super(
            [], 
            [new Contact(0.0, OUTPUT, "ms")], 
            null, 
            id, 
            "FrameTime", 
            true
        );
    }

    // Переопределяем метод обновления, который вызывается каждый кадр
    override private function _onUpdate(dt:Float):Void {
        // dt приходит в секундах (например, 0.016). Нам нужны миллисекунды.
        var ms = dt * 1000;
        
        // Записываем результат в выходной контакт.
        // Это вызовет сигнал, и подключенные атомы получат данные.
        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = ms;
        }
    }
}