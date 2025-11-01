package Src.Prog.Com.Atoms.Custom {
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Logical representation of a Button atom.
     */
    public class ButtonAtom extends BaseAtom {
        public function ButtonAtom(id:String, pos:Point, name:String, type:String,
                                 inputContacts:Vector.<Pin> = null,
                                 outputContacts:Vector.<Pin> = null) {
            super(id, pos, name, type, inputContacts, outputContacts);
        }
    }
}