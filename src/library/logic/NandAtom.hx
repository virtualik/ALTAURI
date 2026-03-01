package library.logic;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * NAND Atom
 * Universal logic gate.
 * Returns TRUE only if NOT both inputs are TRUE.
 * From this single gate, all other logic (NOT, AND, OR, XOR) can be built.
 */
class NandAtom extends Atom {
    
    public function new(id:String) {
        super(
            // 2 Входа (A и B)
            [
                new Contact(false, INPUT, "A"), 
                new Contact(false, INPUT, "B")
            ],
            // 1 Выход (Q)
            [
                new Contact(false, OUTPUT, "Q")
            ],
            // --- ЛОГИКА (Мгновенная, без парсинга строк) ---
            function(inputs:Array<Dynamic>):Array<Dynamic> {
                var a = inputs[0];
                var b = inputs[1];
                
                // NAND = NOT (A AND B)
                return [!(a && b)]; 
            },
            // -----------------------------------------------
            id,
            "NAND"
        );
    }
}