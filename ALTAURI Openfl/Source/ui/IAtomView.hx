package ui;

import core.Atom;

/**
 * Interface for visual representations of Atoms.
 * Allows the system to handle different view types (Editor, Device, Minimal).
 */
interface IAtomView {
    public var atom(get, null):Atom;
    
    function update():Void;
    function dispose():Void;
}