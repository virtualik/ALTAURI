package core.base;

/**
 * INTERFACE FOR DISPOSABLE OBJECTS
 * 
 * Marks objects that require explicit cleanup of resources.
 * 
 * Implementations should:
 * - Release references to other objects
 * - Unregister from managers
 * - Clear internal state
 * - Close external resources (files, sockets, etc.)
 * 
 * After dispose() is called, the object should not be used.
 */
interface IDisposable 
{
    /**
     * Release all resources held by this object.
     * 
     * This method should be idempotent (safe to call multiple times).
     */
    function dispose():Void;
}