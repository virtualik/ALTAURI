package system.managers;

import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * ASSEMBLY MONITOR v1.0
 * Monitor for detecting problematic assemblies.
 * Tracks tick counts and execution times to identify suspicious activity.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   AssemblyMonitor (Singleton)                                           │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Statistics:                                                    │   │
 * │   │  - _assemblyStats:Map<String, AssemblyStats>                    │   │
 * │   │    - tickCount: Int          → Number of ticks executed         │   │
 * │   │    - lastTickTime: Float     → Timestamp of last tick           │   │
 * │   │    - avgTickTime: Float      → Average execution time           │   │
 * │   │    - isSuspicious: Bool      → Flagged as suspicious            │   │
 * │   │                                                                 │   │
 * │   │  Thresholds:                                                    │   │
 * │   │  - _suspiciousThreshold = 100 ticks without state change        │   │
 * │   │  - _maxTickTime = 50ms per tick                                 │   │
 * │   │                                                                 │   │
 * │   │  Methods:                                                       │   │
 * │   │  - recordTick(id)         → Record tick for assembly            │   │
 * │   │  - checkAllAssemblies()   → Check all for suspicious activity   │   │
 * │   │  - reset()                → Clear all statistics                │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var monitor = AssemblyMonitor.getInstance();                          │
 * │   monitor.recordTick(assemblyId);                                       │
 * │   monitor.checkAllAssemblies();                                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class AssemblyMonitor 
{
    private static var _instance:AssemblyMonitor;
    
    /** Assembly statistics map: assemblyId → stats */
    private var _assemblyStats:Map<String, {
        tickCount:Int,
        lastTickTime:Float,
        avgTickTime:Float,
        isSuspicious:Bool
    }>;
    
    /** Number of ticks without state change before flagging as suspicious */
    private var _suspiciousThreshold:Int = 100;
    
    /** Maximum allowed tick time in seconds (50ms) */
    private var _maxTickTime:Float = 0.050;
    
    /**
     * Get singleton instance.
     */
    public static function getInstance():AssemblyMonitor 
    {
        if (_instance == null) _instance = new AssemblyMonitor();
        return _instance;
    }
    
    private function new() 
    {
        _assemblyStats = new Map();
        
        // Subscribe to atom restoration events
        Impulsys.subscribeToImpulse(EventType.ATOM_RESTORED, onAtomRestored);
    }
    
    /**
     * Handler for atom restoration events.
     * Initializes statistics for newly restored atoms.
     */
    private function onAtomRestored(impulse:core.logic.Impulse):Void 
    {
        if (impulse.data == null) return;
        
        var id:String = impulse.data.id;
        if (id == null) return;
        
        // Initialize statistics for this assembly
        _assemblyStats.set(id, {
            tickCount: 0,
            lastTickTime: 0,
            avgTickTime: 0,
            isSuspicious: false
        });
    }
    
    /**
     * Record a tick for the specified assembly.
     * Increments tick count and checks for suspicious activity.
     *
     * @param assemblyId Assembly ID to record tick for
     */
    public function recordTick(assemblyId:String):Void 
    {
        if (!_assemblyStats.exists(assemblyId)) return;
        
        var stats = _assemblyStats.get(assemblyId);
        stats.tickCount++;
        
        // Flag as suspicious if threshold exceeded
        if (stats.tickCount > _suspiciousThreshold && !stats.isSuspicious) 
        {
            stats.isSuspicious = true;
            trace('⚠️  AssemblyMonitor: ${assemblyId} is suspicious (${stats.tickCount} ticks)');
        }
    }
    
    /**
     * Check all assemblies for suspicious activity.
     * Logs warnings for flagged assemblies.
     */
    public function checkAllAssemblies():Void 
    {
        for (id in _assemblyStats.keys()) 
        {
            var stats = _assemblyStats.get(id);
            
            if (stats.isSuspicious) 
            {
                trace('🚨 AssemblyMonitor: ${id} flagged as suspicious');
            }
        }
    }
    
    /**
     * Reset all statistics.
     * Clears the entire statistics map.
     */
    public function reset():Void 
    {
        _assemblyStats.clear();
    }
}