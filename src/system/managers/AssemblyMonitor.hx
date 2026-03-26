// ============================================================================
// system/managers/AssemblyMonitor.hx - НОВЫЙ ФАЙЛ
// ============================================================================
package system.managers;

import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * Монитор для обнаружения проблемных Сборок
 */
class AssemblyMonitor {
    private static var _instance:AssemblyMonitor;
    
    // Статистика по сборкам
    private var _assemblyStats:Map<String, {
        tickCount:Int,
        lastTickTime:Float,
        avgTickTime:Float,
        isSuspicious:Bool
    }>;
    
    private var _suspiciousThreshold:Int = 100; // Тиков без изменения состояния
    private var _maxTickTime:Float = 0.050; // 50ms на тик
    
    public static function getInstance():AssemblyMonitor {
        if (_instance == null) _instance = new AssemblyMonitor();
        return _instance;
    }
    
    private function new() {
        _assemblyStats = new Map();
        Impulsys.subscribeToImpulse(EventType.ATOM_RESTORED, onAtomRestored);
    }
    
    private function onAtomRestored(impulse:core.logic.Impulse):Void {
        if (impulse.data == null) return;
        var id:String = impulse.data.id;
        if (id == null) return;
        
        _assemblyStats.set(id, {
            tickCount: 0,
            lastTickTime: 0,
            avgTickTime: 0,
            isSuspicious: false
        });
    }
    
    /**
     * Отметить тик для сборки
     */
    public function recordTick(assemblyId:String):Void {
        if (!_assemblyStats.exists(assemblyId)) return;
        
        var stats = _assemblyStats.get(assemblyId);
        stats.tickCount++;
        
        if (stats.tickCount > _suspiciousThreshold && !stats.isSuspicious) {
            stats.isSuspicious = true;
            trace('⚠️  AssemblyMonitor: ${assemblyId} is suspicious (${stats.tickCount} ticks)');
        }
    }
    
    /**
     * Проверить все сборки на подозрительную активность
     */
    public function checkAllAssemblies():Void {
        for (id in _assemblyStats.keys()) {
            var stats = _assemblyStats.get(id);
            if (stats.isSuspicious) {
                trace('🚨 AssemblyMonitor: ${id} flagged as suspicious');
            }
        }
    }
    
    /**
     * Сбросить статистику
     */
    public function reset():Void {
        _assemblyStats.clear();
    }
}