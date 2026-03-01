package core.base;

import core.data.Blueprint;
import core.data.Blueprint.ConnectionPoint;
import core.base.Contact;
import core.base.Atom;
import core.base.IDisposable;
import core.types.ContactType;

class Assembly implements IDisposable {
    public var id(default, null):String;
    public var blueprint(default, null):Blueprint;

    // Хранилище портов проводников
    public var ports(default, null):Map<String, ConductorPort>;

    // Для совместимости с внешним кодом (DevicePanel, внешние подключения)
    // Возвращаем ВНЕШНИЕ контакты
    public var inputs(get, null):Map<String, Contact>;
    public var outputs(get, null):Map<String, Contact>;
    
    public var internalAtoms(default, null):Map<String, Dynamic>;

    public function new(id:String, blueprint:Blueprint) {
        this.id = id;
        this.blueprint = blueprint;

        this.ports = new Map();
        this.internalAtoms = new Map();

        _createInterface();
        _createInternalInstances();
        _createInternalConnections();
    }

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

    private function _createInterface():Void {
        if (blueprint == null) return;
        for (pinDef in blueprint.pins) {
            // Создаем Проводник
            var port = new ConductorPort(pinDef.name, pinDef.type, pinDef.defaultValue);
            ports.set(pinDef.name, port);
        }
    }

    private function _createInternalInstances():Void {
        if (blueprint.internalAtoms == null) return;
        for (atomDef in blueprint.internalAtoms) {
            var instance = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
            if (instance != null) {
                internalAtoms.set(atomDef.instanceId, instance);
            }
        }
    }

    private function _createInternalConnections():Void {
        if (blueprint.internalConnections == null) return;
        for (conn in blueprint.internalConnections) {
            var fromContact = resolveContact(conn.from);
            var toContact = resolveContact(conn.to);

            if (fromContact != null && toContact != null) {
                fromContact.link(toContact);
            } else {
                trace('WARN: Assembly resolve failed for link: ${conn.from.atomId} -> ${conn.to.atomId}');
            }
        }
    }

    // ИЗМЕНЕНИЕ: Теперь resolveContact для SELF возвращает ВНУТРЕННИЙ контакт порта
    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") {
            var port = ports.get(point.contactName);
            if (port == null) return null;
            
            // Возвращаем внутренний контакт!
            return port.internal;
            
        } else {
            var obj = internalAtoms.get(point.atomId);
            if (obj == null) return null;
            var atom:Atom = cast obj;
            for (c in atom.getInputs()) if (c.name == point.contactName) return c;
            for (c in atom.getOutputs()) if (c.name == point.contactName) return c;
        }
        return null;
    }

    public function dispose():Void {
        for (key in internalAtoms.keys()) {
            var obj = internalAtoms.get(key);
            if (Std.isOfType(obj, IDisposable)) {
                cast(obj, IDisposable).dispose();
            }
        }
        internalAtoms.clear();

        // Уничтожаем порты
        for (port in ports) port.dispose();
        ports.clear();
    }
}