package ui;

import core.base.Atom;

/**
 * Interface for visual representations of Atoms.
 */
interface IAtomView {
    public var atom(get, null):Atom;

    function update():Void;
    function dispose():Void;
}