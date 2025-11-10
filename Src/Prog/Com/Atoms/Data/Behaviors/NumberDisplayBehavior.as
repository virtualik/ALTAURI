package Src.Prog.Com.Atoms.Data.Behaviors {
	import Src.Prog.Com.Atoms.Core.Atom;

	public class NumberDisplayBehavior extends BaseBehavior {
		override public function onInputChange(atom: Atom, pinName: String, value: * ): Atom {
			trace("NumberDisplay: Value changed to " + value);
			return atom;
		}
	}
}