package system.managers;

/**
* RESOURCE REGISTRY v1.0 (FAULT_ISOLATION WP — exclusive resource contract)
*
* Static ownership map for OS-exclusive resources claimed by atoms.
*
* WHY (design Task 94, field-proven by the ComPort case): a serial port is
* OS-exclusive — two ComPort atoms aimed at the same portName fight over
* one handle and the loser gets a cryptic "WinAPI Open Failed (Error 5)"
* with no hint WHO holds the port. The registry makes the conflict a
* first-class, diagnosable event: explicit refusal + RESOURCE_BUSY fault
* latch (red frame) naming the holder.
*
* CONTRACT:
*  - Key format: "<kind>:<id>", e.g. "serial:COM3". Keys are owned by the
*    atoms that declare them via Atom.getResourceKey() overrides.
*  - Default is FREE: atoms without a resource key (null) never interact
*    with this registry — "everything is allowed unless declared" (the
*    answer to the isSingle question: no class-level singletons).
*  - acquire() is IDEMPOTENT for the same owner (close/reopen cycles).
*  - Enforcement lives at the atom's REAL activation point
*    (openDevice/openFile/...) — NOT at DriverManager.register(), because
*    resources are grabbed lazily by user action, not at construction.
*  - Release happens in the atom's close path; DriverManager.unregister()
*    sweeps as a safety net for missed releases (idempotent).
*
* NOTE (deliberate, level 1): MiniAudioAtom declares NO key — WASAPI
* loopback capture is a SHARED resource (two atoms on one endpoint are
* legal, T-AUD.3 semantics); forcing exclusivity would regress the
* accepted audio-safety test criteria.
*/
class ResourceRegistry
{
    /** resourceKey -> ownerId (runtime atom id of the current holder). */
    private static var _owners:Map<String, String> = new Map<String, String>();

    /**
    * Try to claim a resource key for an owner.
    * @return true if the owner now holds the key (or already held it);
    *         false on conflict — the key is held by a DIFFERENT atom.
    */
    public static function acquire(key:String, ownerId:String):Bool
    {
        if (key == null || ownerId == null) return false;
        var holder = _owners.get(key);
        if (holder != null && holder != ownerId)
        {
            utils.Trap.log("RESOURCE", "CONFLICT: '" + key + "' held by " + holder + ", refused for " + ownerId);
            return false;
        }
        var isNew = (holder == null);
        _owners.set(key, ownerId);
        if (isNew) utils.Trap.log("RESOURCE", "acquired: '" + key + "' by " + ownerId);
        return true;
    }

    /**
    * Release a key, but only if the given owner actually holds it
    * (an atom must never be able to release another atom's resource).
    */
    public static function release(key:String, ownerId:String):Void
    {
        if (key == null || ownerId == null) return;
        var holder = _owners.get(key);
        if (holder == ownerId)
        {
            _owners.remove(key);
            utils.Trap.log("RESOURCE", "released: '" + key + "' by " + ownerId);
        }
    }

    /**
    * Release EVERY key held by the owner (dispose-time safety sweep;
    * silent by design — teardown noise has no diagnostic value).
    */
    public static function releaseAll(ownerId:String):Void
    {
        if (ownerId == null) return;
        var doomed:Array<String> = [];
        for (key in _owners.keys())
        {
            if (_owners.get(key) == ownerId) doomed.push(key);
        }
        for (key in doomed) _owners.remove(key);
    }

    /** Current holder of a key (null = free). */
    public static function getHolder(key:String):String
    {
        if (key == null) return null;
        return _owners.get(key);
    }

    /** True if the key is free or already held by the given owner. */
    public static function isFree(key:String, ownerId:String):Bool
    {
        var holder = getHolder(key);
        return holder == null || holder == ownerId;
    }
}
