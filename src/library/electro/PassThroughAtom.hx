package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.TickGenerator;
import core.types.ContactType.*;

/**
 * PASS-THROUGH ATOM v1.4 (Link-Based + Active Timer)
 * 
 * Мгновенно транслирует значение с входа на выход через link().
 * Генерирует импульс changed (50ms) через subscribe + update timer.
 * 
 * ──────────────────────────────────────────────────────┐
 * │  in ──[LINK]──► out                                  │
 * │   │                                                  │
 * │   └──► changed (bool pulse, 50ms via update timer)   │
 * └──────────────────────────────────────────────────────┘
 */
class PassThroughAtom extends Atom
{
    /** Длительность импульса changed в секундах */
    private static inline var PULSE_DURATION:Float = 0.05;
    
    /** Таймер обратного отсчёта для сброса changed */
    private var _changedTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [new Contact(null, INPUT, "in")],
            [
                new Contact(null, OUTPUT, "out"),
                new Contact(false, OUTPUT, "changed")
            ],
            null,
            id,
            "PassThrough",
            false
        );
        
        var input = getInput("in");
        var output = getOutput("out");
        var changed = getOutput("changed");
        
        if (input != null && output != null)
        {
            // Прямая трансляция значений (без _calculate, без рекурсии)
            input.link(output);
            
            // Подписка на изменения для генерации импульса changed
			input.subscribe(function(v:Dynamic) {
				if (changed != null && changed.value == false)
				{
					changed.value = true;
					// Сброс через 3 кадра (~50ms при 60 FPS)
					TickGenerator.getInstance().scheduleNextTick(function() {
						TickGenerator.getInstance().scheduleNextTick(function() {
							TickGenerator.getInstance().scheduleNextTick(function() {
								if (changed != null) changed.value = false;
							});
						});
					});
				}
			});
            
            input.ignoreOscillation = true;
        }
    }
    
    /**
     * Вызывается DriverManager каждый кадр (isActive = true).
     * Единственная задача — сбросить changed по истечении таймера.
     */
    override public function update(dt:Float):Void
    {
        super.update(dt);
        
        if (_changedTimer > 0)
        {
            _changedTimer -= dt;
            if (_changedTimer <= 0)
            {
                var changed = getOutput("changed");
                if (changed != null) changed.value = false;
            }
        }
    }
}