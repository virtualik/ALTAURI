package library.logic;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * NAND Atom v1.2
 * Universal logic gate.
 * 
 * v1.2 Changes:
 * - ADDED: Default input values (true) for stable initial state.
 * - FIXED: Cross-coupled NAND latches (SR Latch, T-TRIGGER) initialize without oscillation.
 * 
 * v1.1 Changes:
 * - Set isLogic = true to enable Unit Delay behavior.
 * - This ensures stable operation in feedback loops (Flip-Flops).
 */
class NandAtom extends Atom {

    public function new(id:String) {
        // === FIX v1.2: Создаем контакты с начальными значениями ===
        var inputA = new Contact(true, INPUT, "A");  // По умолчанию true
        var inputB = new Contact(true, INPUT, "B");  // По умолчанию true
        
        super(
            [inputA, inputB],
            [
                new Contact(false, OUTPUT, "Q")  // NAND(1,1) = 0
            ],
            function(inputs:Array<Dynamic>):Array<Dynamic> {
                var a = inputs[0];
                var b = inputs[1];
                // === FIX v1.2: Обработка null как true (pull-up) ===
                if (a == null) a = true;
                if (b == null) b = true;
                return [!(a && b)];
            },
            id,
            "NAND"
        );
        
        // ВАЖНО: Помечаем как логический вентиль
        this.isLogic = true;
    }
}