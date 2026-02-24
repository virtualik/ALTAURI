package core;

/**
 * REGISTRY v1.0
 * Global access point for all active instances.
 * Mimics the AS2/AS3 centralized management style.
 */
class Registry {

    private static var _instance:Registry;
    
    public var atoms:Array<Atom>;
    public var assemblies:Array<Assembly>;

    public static function getInstance():Registry {
        if (_instance == null) _instance = new Registry();
        return _instance;
    }

    private function new() {
        atoms = [];
        assemblies = [];
    }

    public function registerAtom(a:Atom):Void {
        atoms.push(a);
    }

    public function registerAssembly(a:Assembly):Void {
        assemblies.push(a);
    }
}