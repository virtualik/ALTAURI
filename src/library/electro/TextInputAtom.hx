package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TEXT INPUT ATOM v1.3 (Correctness Pass)
 *
 * Passive atom for string or numeric input.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   TextInputAtom (Databank)                                              │
 * │                                                                         │
 * │   Contact "set" ──► _calculate() ──► Contact "out"                      │
 * │                                                                         │
 * │   Widget (TextInputWidget) writes to "set" contact.                     │
 * │   Atom passes value through to "out" contact.                           │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.3 Changes:
 * - _calculate() uses getInput()/getOutput() by name
 * - Fixed getPersistentState() to merge with super result
 * - Fixed restoreState() to call super.restoreState() first
 */
class TextInputAtom extends Atom
{
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact(null, INPUT, "set")
            ],
            [
                new Contact("", OUTPUT, "out")
            ],
            null,
            id,
            "TextInput"
        );
    }

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================
    /**
     * If "set" input received value — pass it to "out" output.
     *
     * Note: _isScheduled is reset explicitly here for safety,
     * though base class Atom._calculate() also resets it in first line.
     * Double reset is harmless — it's a safety for direct calls.
     */
    override private function _calculate():Void
    {
        _isScheduled = false;
        
        var setContact = getInput("set");
        var outContact = getOutput("out");
        
        if (setContact == null || outContact == null) return;
        
        var val = setContact.value;
        if (val != null)
        {
            outContact.value = val;
        }
    }

    // =========================================================================
    // STATE SERIALIZATION v1.3
    // =========================================================================
    /**
     * Save current output value.
     *
     * Merges with super result to preserve base class fields (isLogic).
     */
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var outContact = getOutput("out");
        var currentValue:Dynamic = (outContact != null) ? outContact.value : null;
        
        var result:Dynamic = { value: currentValue };
        
        if (base != null)
        {
            if (Reflect.hasField(base, "isLogic"))
            {
                Reflect.setField(result, "isLogic", Reflect.field(base, "isLogic"));
            }
        }
        return result;
    }

    /**
     * On load, restore value.
     *
     * Calls super.restoreState() first so base class fields are restored
     * before subclass-specific logic runs.
     */
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        
        super.restoreState(state);
        
        if (state.value != null)
        {
            var outContact = getOutput("out");
            if (outContact != null)
            {
                outContact.value = state.value;
            }
        }
    }
}