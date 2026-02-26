package core.atoms;

import core.Atom;
import core.Contact;

class FPSMonitorAtom extends Atom {
    
    private var _frames:Int = 0;
    private var _elapsed:Float = 0;

    public function new(id:String) {
        // Вызываем родительский конструктор с флагом isActive = true
        // У него нет входов, 1 выход, и нет функции _process (математической)
        super(
            [], 
            [new Contact(0, OUTPUT, "fps")], 
            null, 
            id, 
            "FPSMonitor", 
            true // ACTIVE!
        );
    }

    // Переопределяем метод обновления Драйвера
    override private function _onUpdate(dt:Float):Void {
        _frames++;
        _elapsed += dt;

        if (_elapsed >= 0.5) {
            var fps = Math.round(_frames / _elapsed);
            
            // Записываем результат в свой выходной контакт
            // Это запустит сигнал дальше по графу
            _outputs[0].value = fps;

            _frames = 0;
            _elapsed = 0;
        }
    }
}