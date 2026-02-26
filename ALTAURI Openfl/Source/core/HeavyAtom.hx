package core;

import haxe.Timer;

/**
 * HEAVY ATOM v1.1
 * Атом с поддержкой Load Shedding (Сброса нагрузки).
 * ИСПРАВЛЕНО: Отмена таймера при dispose.
 */
class HeavyAtom extends Atom {

    private var _delayedTimer:Timer;

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Heavy"
    ) {
        super(inputs, outputs, processFunc, id, type);
    }

    override function onContactChanged(c:Contact):Void {
        if (SignalQueue.getInstance().isOverloaded()) {
            if (_isScheduled) return;
            _isScheduled = true;

            // --- ИСПРАВЛЕНИЕ: Сохраняем таймер в переменную ---
            _delayedTimer = Timer.delay(() -> {
                _isScheduled = false;
                _delayedTimer = null; // Очистка ссылки
                if (!_isDisposed) _calculate(); // Проверка перед выполнением
            }, 1);

            return;
        }

        super.onContactChanged(c);
    }

    // --- ИСПРАВЛЕНИЕ: Переопределяем dispose ---
    override public function dispose():Void {
        if (_delayedTimer != null) {
            _delayedTimer.stop(); // Останавливаем запланированную задачу
            _delayedTimer = null;
        }
        super.dispose();
    }
}