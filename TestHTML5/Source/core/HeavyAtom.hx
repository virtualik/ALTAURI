package core;

/**
 * HEAVY ATOM v1.0
 * Атом с поддержкой Load Shedding (Сброса нагрузки).
 * Если система перегружена, он откладывает вычисления.
 */
class HeavyAtom extends Atom {

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Heavy"
    ) {
        super(inputs, outputs, processFunc, id, type);
    }

    // Переопределяем логику реакции на изменение
    override function onContactChanged(c:Contact):Void {
        // Проверяем, не устал ли "мозг" (SignalQueue)
        if (SignalQueue.getInstance().isOverloaded()) {
            
            // Если устал - отменяем немедленное выполнение.
            // Планируем задачу на следующий кадр через Таймер (или RAF в JS).
            // Это "Ленивое" поведение.
            
            // ВАЖНО: Мы должны предотвратить повторное планирование в этом кадре,
            // если данные прийдут еще раз.
            if (_isScheduled) return;
            _isScheduled = true;

            // Используем haxe.Timer для переноса на следующий тик
            haxe.Timer.delay(() -> {
                _isScheduled = false;
                _calculate(); // Выполняем тяжелую работу, когда очередь разгрузится
            }, 1); // Задержка 1мс (фактически следующий кадр/тик)
            
            return;
        }

        // Если все норм - работаем как обычно
        super.onContactChanged(c);
    }
}