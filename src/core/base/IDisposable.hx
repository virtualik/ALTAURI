package core.base;

/**
 * Interface for objects that require explicit cleanup.
 */
interface IDisposable {
    function dispose():Void;
}
