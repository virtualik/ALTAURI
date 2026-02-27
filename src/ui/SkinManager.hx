package ui;

import library.AtomRegistry;
import core.data.Blueprint;

/**
 * SKIN MANAGER v1.0
 * Registry for visual resources (Skins).
 */
class SkinManager {

    private static var _instance:SkinManager;
    private var _skins:Map<String, AtomSkin>;

    public static function getInstance():SkinManager {
        if (_instance == null) _instance = new SkinManager();
        return _instance;
    }

    private function new() {
        _skins = new Map();
        initializeDefaults();
    }

    private function initializeDefaults():Void {
        // Here we could load from config files later
    }

    /**
     * Returns a skin for a specific Atom type.
     * Falls back to default if not found.
     */
    public function getSkinForType(typeId:String):AtomSkin {
        if (_skins.exists(typeId)) {
            return _skins.get(typeId);
        }

        // Generate on the fly based on definition
        var bp = AtomRegistry.get(typeId);
        var category = (bp != null) ? bp.category : "General";
        var skin = AtomSkin.createDefault(category);

        _skins.set(typeId, skin);
        return skin;
    }

    public function registerSkin(typeId:String, skin:AtomSkin):Void {
        _skins.set(typeId, skin);
    }
}