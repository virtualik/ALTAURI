package core.base;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.ConnectionPoint;
import core.base.Contact;
import core.base.IDisposable;
import core.types.ContactType;

/**
 * ASSEMBLY v4.0 (Unified Model)
 * Универсальный базовый класс для ВСЕХ узлов.
 * Объединяет возможности Atom (логика) и Assembly (контейнер).
 * 
 * Native атомы: имеют logic, не имеют internalAtoms.
 * Custom сборки: не имеют logic, имеют internalAtoms.
 */
class Assembly extends Atom {

    public static inline var MAX_INPUT_PORTS:Int = 20;
    public static inline var MAX_OUTPUT_PORTS:Int = 20;

    public var blueprint(default, null):Blueprint;
    public var ports(default, null):Map<String, ConductorPort>;
    public var internalAtoms(default, null):Map<String, Dynamic>;

    // ИСПРАВЛЕНИЕ: Объявляем свойства (Map) без override, так как в Atom их нет (там Array)
    public var inputs(get, null):Map<String, Contact>;
    public var outputs(get, null):Map<String, Contact>;

    // Геттеры для свойств Maps
    private function get_inputs():Map<String, Contact> {
        var map = new Map<String, Contact>();
        for (p in ports) if (p.type == INPUT) map.set(p.name, p.external);
        return map;
    }

    private function get_outputs():Map<String, Contact> {
        var map = new Map<String, Contact>();
        for (p in ports) if (p.type == OUTPUT) map.set(p.name, p.external);
        return map;
    }

    public function new(id:String, blueprint:Blueprint) {
        this.blueprint = blueprint;
        this.ports = new Map();
        this.internalAtoms = new Map();

        // 1. Создаем интерфейс (порты)
        _createInterface();

        // 2. Формируем массивы контактов для передачи в super (Atom)
        var inputsArr:Array<Contact> = [];
        var outputsArr:Array<Contact> = [];
        var ordered = _getOrderedPortDefs();
        
        for (pinDef in ordered) {
            var p = ports.get(pinDef.name);
            if (p != null) {
                if (p.type == INPUT) inputsArr.push(p.external);
                else outputsArr.push(p.external);
            }
        }

        var typeName = blueprint != null ? blueprint.name : "Assembly";
        
        // 3. Вызываем конструктор Atom.
        // ИСПРАВЛЕНИЕ: Передаем blueprint.logic. Если это Native атом, логика будет выполнена.
        super(inputsArr, outputsArr, blueprint.logic, id, typeName, false);

        // 4. Если логики нет (это Custom сборка), создаем внутренности.
        // Если логика есть, внутренности игнорируются (Native атом).
        if (blueprint.logic == null) {
            _createInternalInstances();
            _createInternalConnections();
        }
    }

    private function _createInterface():Void {
        if (blueprint == null || blueprint.pins == null) return;
        for (pinDef in blueprint.pins) {
            var port = new ConductorPort(pinDef.name, pinDef.type, pinDef.defaultValue);
            ports.set(pinDef.name, port);
        }
    }

    private function _createInternalInstances():Void {
        if (blueprint == null || blueprint.internalAtoms == null) return;
        for (atomDef in blueprint.internalAtoms) {
            var instance = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
            if (instance != null) internalAtoms.set(atomDef.instanceId, instance);
        }
    }

    private function _createInternalConnections():Void {
        if (blueprint == null || blueprint.internalConnections == null) return;
        for (conn in blueprint.internalConnections) {
            var fromContact = resolveContact(conn.from);
            var toContact = resolveContact(conn.to);
            if (fromContact != null && toContact != null) fromContact.link(toContact);
        }
    }

    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") {
            var port = ports.get(point.contactName);
            return (port == null) ? null : port.internal;
        } else {
            var obj = internalAtoms.get(point.atomId);
            if (obj == null) return null;
            var atom:Atom = cast obj;
            var c = atom.getInput(point.contactName);
            if (c == null) c = atom.getOutput(point.contactName);
            return c;
        }
    }

    // =========================================================================
    // PORT MANAGEMENT API
    // =========================================================================

    private function _getOrderedPortDefs():Array<PinDef> {
        if (blueprint == null || blueprint.pins == null) return [];
        return blueprint.pins.copy();
    }

    public function getOrderedPorts(type:ContactType):Array<ConductorPort> {
        var result:Array<ConductorPort> = [];
        var defs = _getOrderedPortDefs();
        for (pin in defs) {
            if (pin.type == type) {
                var p = ports.get(pin.name);
                if (p != null) result.push(p);
            }
        }
        return result;
    }

    public function addPort(name:String, type:ContactType, defaultValue:Dynamic = null):ConductorPort {
        var currentCount = 0;
        for (p in ports) if (p.type == type) currentCount++;

        var max = (type == INPUT) ? MAX_INPUT_PORTS : MAX_OUTPUT_PORTS;
        if (currentCount >= max) {
            trace('ERROR: Max ports limit reached for type $type');
            return null;
        }

        if (ports.exists(name)) {
            trace('ERROR: Port name "$name" already exists');
            return null;
        }

        var pinDef:PinDef = { name: name, type: type, defaultValue: defaultValue };
        blueprint.pins.push(pinDef);

        var port = new ConductorPort(name, type, defaultValue);
        ports.set(name, port);

        if (type == INPUT) {
            _inputs.push(port.external);
        } else {
            _outputs.push(port.external);
        }

        return port;
    }

    public function removePort(name:String):Void {
        var port = ports.get(name);
        if (port == null) return;

        var pinToRemove:PinDef = null;
        for (pin in blueprint.pins) {
            if (pin.name == name) {
                pinToRemove = pin;
                break;
            }
        }
        if (pinToRemove != null) {
            blueprint.pins.remove(pinToRemove);
        }

        if (port.type == INPUT) {
            _inputs.remove(port.external);
        } else {
            _outputs.remove(port.external);
        }

        port.dispose();
        ports.remove(name);
    }

    override public function dispose():Void {
        var keys = [for (k in internalAtoms.keys()) k];
        for (key in keys) {
            var obj = internalAtoms.get(key);
            if (obj != null) {
                if (Std.isOfType(obj, IDisposable)) {
                    try { cast(obj, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error: $e'); }
                }
            }
        }
        internalAtoms.clear();
        internalAtoms = null;

        var portKeys = [for (k in ports.keys()) k];
        for (key in portKeys) {
            var port = ports.get(key);
            if (port != null) port.dispose();
        }
        ports.clear();
        ports = null;

        super.dispose();
    }
}