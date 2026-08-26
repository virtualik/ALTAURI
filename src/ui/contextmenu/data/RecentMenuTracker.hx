package ui.contextmenu.data;

import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     RECENT MENU TRACKER                                   ║
 * ║          (Tracks last N menu actions for Recent section)                  ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Singleton that tracks the last N menu actions and exposes them           ║
 * ║  as MenuEntry instances for the "Recent" category in the sidebar.         ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  RecentMenuTracker (Singleton)                                      │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  Fields:                                                      │  │  ║
 * ║  │  │  - _history: Array<MenuEntry>  → Last N entries (FIFO)        │  │  ║
 * ║  │  │  - _maxHistory: Int          → Maximum entries to track (5)   │  │  ║
 * ║  │  │                                                               │  │  ║
 * ║  │  │  Methods:                                                     │  │  ║
 * ║  │  │  - record(entry: MenuEntry)  → Add to history                 │  │  ║
 * ║  │  │  - getRecent() → Array<MenuEntry>  → Get last N entries       │  │  ║
 * ║  │  │  - clear()                   → Clear history                  │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Subscription:                                                            ║
 * ║  - Subscribes to CONTEXT_MENU_ACTION via Impulsys                         ║
 * ║  - Automatically records actions when menu items are clicked              ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class RecentMenuTracker
{
    /** Singleton instance. */
    private static var _instance:RecentMenuTracker;
    
    /** Maximum number of recent entries to track. */
    private static inline var MAX_HISTORY:Int = 5;
    
    /** FIFO history of recent menu entries. */
    private var _history:Array<MenuEntry>;
    
    /** Subscription callback reference for cleanup. */
    private var _onMenuAction:Impulse -> Void;
    
    /**
     * Get singleton instance.
     * 
     * @return RecentMenuTracker instance
     */
    public static function getInstance():RecentMenuTracker
    {
        if (_instance == null)
        {
            _instance = new RecentMenuTracker();
        }
        return _instance;
    }
    
    /**
     * Private constructor (singleton pattern).
     * Initializes history array and subscribes to Impulsys.
     */
    private function new()
    {
        _history = [];
        _onMenuAction = onMenuAction;
        Impulsys.subscribeToImpulse(EventType.CONTEXT_MENU_ACTION, _onMenuAction);
        // v2.0 (Episod F-bold): auto-restore after Impulsys.clear().
        Impulsys.registerResubscriber(resubscribe);
    }
    
    /**
     * Record a menu entry in the recent history.
     * 
     * @param entry MenuEntry to record
     */
    public function record(entry:MenuEntry):Void
    {
        if (entry == null) return;
        
        // Remove duplicate if exists (to move it to top)
        var existingIndex = -1;
        for (i in 0..._history.length)
        {
            if (_history[i].actionId == entry.actionId)
            {
                existingIndex = i;
                break;
            }
        }
        if (existingIndex != -1)
        {
            _history.splice(existingIndex, 1);
        }
        
        // Add to front (most recent first)
        _history.unshift(entry);
        
        // Trim to max history size
        while (_history.length > MAX_HISTORY)
        {
            _history.pop();
        }
    }
    
    /**
     * Get recent menu entries (last N actions).
     * 
     * @return Array of MenuEntry instances (most recent first)
     */
    public function getRecent():Array<MenuEntry>
    {
        return _history.copy();
    }
    
    /**
     * Clear all recent history.
     */
    public function clear():Void
    {
        _history = [];
    }
        
    /**
        * Re-subscribe to Impulsys after a clear() event.
        * v2.0 (Episod F-bold): registered with Impulsys.registerResubscriber()
        * in the constructor — Impulsys.clear() invokes this automatically,
        * so Main.hx no longer calls it manually.
        */
        public function resubscribe():Void
        {
                if (_onMenuAction != null)
                {
                        Impulsys.removeImpulse(EventType.CONTEXT_MENU_ACTION, _onMenuAction);
                }
                _onMenuAction = onMenuAction;
                Impulsys.subscribeToImpulse(EventType.CONTEXT_MENU_ACTION, _onMenuAction);
        }

    /**
     * Impulsys handler for CONTEXT_MENU_ACTION.
     * Automatically records actions when menu items are clicked.
     * 
     * @param impulse Impulse containing action data
     */
    private function onMenuAction(impulse:Impulse):Void
    {
        if (impulse == null || impulse.data == null) return;
        
        var action:String = Std.string(impulse.data.action);
        var data:Dynamic = impulse.data.data;
        
        // Create a MenuEntry from the action data
        var entry = new MenuEntry(
            "recent_" + action,
            action,
            "recent",
            MenuCategory.RECENT,
            action,
            data
        );
        
        record(entry);
    }
    
    /**
     * Cleanup: unsubscribe from Impulsys.
     * Call before application shutdown.
     */
    public function dispose():Void
    {
        // v2.0 (Episod F-bold): also drop the resubscriber registration so a
        // disposed tracker is not resurrected by a later Impulsys.clear().
        Impulsys.unregisterResubscriber(resubscribe);
        Impulsys.removeImpulse(EventType.CONTEXT_MENU_ACTION, _onMenuAction);
        _onMenuAction = null;
        _history = [];
    }
}
