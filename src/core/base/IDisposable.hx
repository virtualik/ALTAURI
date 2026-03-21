package core.base;

/**
 * Interface for objects that require explicit cleanup.
 */
interface IDisposable {
    /**
     * Release all resources held by this object.
     *
     * After dispose() is called, the object should not be used.
     * Implementations should:
     * - Release references to other objects
     * - Unregister from managers
     * - Clear internal state
     */
    function dispose():Void;
}