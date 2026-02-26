package core;

/**
 * Interface for objects that require explicit cleanup.
 */
interface IDisposable {
    function dispose():Void;
}