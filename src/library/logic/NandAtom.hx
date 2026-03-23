package library.logic;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * NAND Atom
 * Universal logic gate.
 * 
 * v1.1 Changes:
 * - Set isLogic = true to enable Unit Delay behavior.
 * - This ensures stable operation in feedback loops (Flip-Flops).
 */
class NandAtom extends Atom {

    public function new(id:String) {
        super(
            [
                new Contact(false, INPUT, "A"),
                new Contact(false, INPUT, "B")
            ],
            [
                new Contact(false, OUTPUT, "Q")
            ],
            function(inputs:Array<Dynamic>):Array<Dynamic> {
                var a = inputs[0];
                var b = inputs[1];
                return [!(a && b)];
            },
            id,
            "NAND"
        );
        
        // ВАЖНО: Помечаем как логический вентиль
        this.isLogic = true;
    }
}