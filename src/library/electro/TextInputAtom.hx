package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TEXT INPUT ATOM v1.4 (Explicit Contact Change Handling)
 *
 * Passive atom for string or numeric input.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   TextInputAtom (Databank)                                              │
 * │                                                                         │
 * │   Contact "set" ──► onContactChanged() ──► _calculate() ──► "out"       │
 * │                                                                         │
 * │   Widget (TextInputWidget) writes to "set" contact.                     │
 * │   Programmatic injection also writes to "set" contact.                  │
 * │   Atom reliably passes value through to "out" contact in both cases.    │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.4 Changes:
 * - ADDED: override onContactChanged() to explicitly trigger _calculate() 
 *   when "set" changes, bypassing the base class _process == null guard.
 * - _calculate() uses getInput()/getOutput() by name.
 * - Fixed getPersistentState() to merge with super result.
 * - Fixed restoreState() to call super.restoreState() first.
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
            null, // _process is null, so base class won't auto-schedule _calculate
            id,
            "TextInput"
        );
    }

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================
    /**
     * Overrides base behavior to explicitly trigger calculation 
     * when the "set" input changes.
     * 
     * WHY THIS IS NEEDED:
     * The base Atom.onContactChanged() checks `if (_process != null)` before 
     * scheduling _calculate(). Since TextInputAtom passes `null` as _process, 
     * base class ignores contact changes. 
     * 
     * By overriding this, we guarantee that both UI interactions (Widget) 
     * and programmatic injections (Databank Injection) immediately propagate 
     * the value to the "out" contact.
     * 
     * @param c The contact that changed
     */
    override public function onContactChanged(c:Contact):Void
    {
        if (c.name == "set") 
        {
            // Force recalculation to propagate "set" value to "out"
            _calculate();
        }
        
        // Call base logic to handle standard scheduling flags safely
        // (It will safely do nothing since _process == null, but maintains contract)
        super.onContactChanged(c);
    }

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
			for (field in Reflect.fields(base))
			{
				Reflect.setField(result, field, Reflect.field(base, field));
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
				// КРИТИЧЕСКИ ВАЖНО ДЛЯ HTML5:
                // Принудительно уведомляем Виджет(ы), чтобы они перерисовали TextField,
                // даже если Виджет был создан и добавлен на сцену ДО загрузки состояния.
                super.onContactChanged(outContact);
            }
        }
    }
}