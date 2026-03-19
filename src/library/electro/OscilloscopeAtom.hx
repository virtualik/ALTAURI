package library.electro;
import core.base.Atom;
import core.base.Contact;

/**
* OSCILLOSCOPE ATOM v1.2 (Fixed Warnings)
* Passive atom display.
* Has input for sample array (Array<Float>).
*/
class OscilloscopeAtom extends Atom {
	public function new(id:String) {
		super(
			[
				// Input for sample buffer - MUST be "in"
				new Contact(null, INPUT, "in")
			],
			[], // No outputs
			null,
			id,
			"Oscilloscope"
		);
	}
}