package Src.Prog.Com.Atoms.Custom {
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Logical representation of a Counter atom.
     */
    public class CounterAtom extends BaseAtom {
        public function CounterAtom(id:String, pos:Point, name:String, type:String,
                                  inputContacts:Vector.<Pin> = null,
                                  outputContacts:Vector.<Pin> = null) {
            super(id, pos, name, type, inputContacts, outputContacts);
        }
    }
}