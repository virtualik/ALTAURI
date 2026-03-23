package core.base;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.ConnectionPoint;
import core.base.Contact;
import core.base.IDisposable;
import core.types.ContactType;
import utils.UID;
import library.AtomRegistry;
import system.managers.DriverManager;
import core.logic.SignalQueue;
import core.logic.Impulsys; // Added Import
import core.logic.EventType; // Added Import

/**
 * ASSEMBLY v5.3 (Logic Mode Switch)
 * Universal base class for ALL nodes.
 *
 * v5.3 Changes:
 * - ADDED: isLogic property override.
 * - ADDED: _updatePortLinks() to switch between Analog (Direct) and Digital (Delayed) modes.
 * - FIXED: Loops in feedback circuits when isLogic = true.
 *
 * v5.2 Changes:
 * - Emit ASSEMBLY_PORTS_CHANGED when ports are added/removed.
 *
 * v5.1 Changes:
 * - Suspended SignalQueue during initialization to prevent race conditions.
 */
class Assembly extends Atom {

    public static inline var MAX_INPUT_PORTS:Int = 20;
    public static inline var MAX_OUTPUT_PORTS:Int = 20;

    public var blueprint:Blueprint;

    public var ports(default, null):Map<String, ConductorPort>;
    public var internalAtoms(default, null):Map<String, Dynamic>;

    public var inputs(get, null):Map<String, Contact>;
    public var outputs(get, null):Map<String, Contact>;

    private var _idMap:Map<String, String>;

    public var idMap(get, never):Map<String, String>;
    private function get_idMap():Map<String, String> return _idMap;

    public function getTemplateId(runtimeId:String):String {
        for (templateId => rId in _idMap) {
            if (rId == runtimeId) return templateId;
        }
        return runtimeId;
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

    // =========================================================================
    // LOGIC MODE SWITCH v5.3
    // =========================================================================

    // Храним callbacks для возможности отписки
    private var _portCallbacks:Map<String, Dynamic -> Void>;

    override private function set_isLogic(value:Bool):Bool {
        if (_isLogic != value) {
            _isLogic = value;
            _updatePortLinks();
        }
        return _isLogic;
    }

    public function new(id:String, blueprint:Blueprint) {
        this.blueprint = blueprint;
        this.ports = new Map();
        this.internalAtoms = new Map();
        _idMap = new Map();
        _portCallbacks = new Map();

        _createInterface();

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

        super(inputsArr, outputsArr, blueprint.logic, id, typeName, false);

        if (blueprint.logic == null) {
            SignalQueue.getInstance().suspend();

            try {
                _createInternalInstances();
                _createInternalConnections();
            } catch (e:Dynamic) {
                trace('ERROR during Assembly($id) initialization: $e');
            }

            SignalQueue.getInstance().resume();
        }
    }

    // =========================================================================
    // PORT LINKING LOGIC v5.3
    // =========================================================================

    /**
     * Управляет связями между внешними и внутренними контактами портов.
     * 
     * Analog Mode (isLogic = false): Прямая связь (провод).
     * Digital Mode (isLogic = true): 
     *   - Входы: Прямая связь (считывание мгновенное).
     *   - Выходы: Задержка на 1 такт (Unit Delay).
     */
    private function _updatePortLinks():Void {
        for (name in ports.keys()) {
            var port = ports.get(name);
            if (port == null) continue;

            // 1. Очистка старых связей
            if (port.external.hasLink(port.internal)) port.external.unlink(port.internal);
            if (port.internal.hasLink(port.external)) port.internal.unlink(port.external);
            
            // Удаляем старые callback-подписки
            if (_portCallbacks.exists(name)) {
                port.internal.unsubscribe(_portCallbacks.get(name));
                _portCallbacks.remove(name);
            }

            // 2. Установка новых связей
            if (this.isLogic) {
                // === DIGITAL MODE ===
                if (port.type == INPUT) {
                    // Вход: Передаем сигнал внутрь мгновенно (как чтение входа)
                    port.external.link(port.internal);
                } else {
                    // Выход: Задержка через scheduleNextTick
                    var callback = function(v:Dynamic) {
                        // Важно: захватываем конкретный порт в замыкании
                        var targetPort = port; 
                        SignalQueue.getInstance().scheduleNextTick(function() {
                            if (!_isDisposed && targetPort != null) {
                                targetPort.external.value = v;
                            }
                        });
                    };
                    port.internal.subscribe(callback);
                    _portCallbacks.set(name, callback);
                }
            } else {
                // === ANALOG MODE ===
                // Прямая связь (провод)
                if (port.type == INPUT) {
                    port.external.link(port.internal);
                } else {
                    port.internal.link(port.external);
                }
            }
        }
    }

    // =========================================================================
    // HOT RELOAD SUPPORT
    // =========================================================================

    public function updateFromBlueprint(newBp:Blueprint):Void {
        if (newBp.id != this.blueprint.id) return;

        this.name = newBp.name;

        var currentPortNames = [for (name in ports.keys()) name];

        var targetPinNames = new Map<String, Bool>();
        for (pin in newBp.pins) {
            targetPinNames.set(pin.name, true);
        }

        // 1. Remove obsolete ports
        for (name in currentPortNames) {
            if (!targetPinNames.exists(name)) {
                var port = ports.get(name);
                if (port != null) {
                    if (port.type == INPUT) {
                        _inputs.remove(port.external);
                        if (_inputCache.length > _inputs.length) _inputCache.pop();
                    } else {
                        _outputs.remove(port.external);
                    }
                    port.dispose();
                    ports.remove(name);
                }
            }
        }

        // 2. Add new ports
        for (pin in newBp.pins) {
            var port = ports.get(pin.name);

            if (port == null) {
                var currentCount = 0;
                for (p in ports) if (p.type == pin.type) currentCount++;
                var max = (pin.type == INPUT) ? MAX_INPUT_PORTS : MAX_OUTPUT_PORTS;

                if (currentCount < max) {
                    var newPort = new ConductorPort(pin.name, pin.type, pin.defaultValue);
                    ports.set(pin.name, newPort);

                    if (pin.type == INPUT) {
                        _inputs.push(newPort.external);
                        newPort.external.owner = this;
                        while (_inputCache.length < _inputs.length) _inputCache.push(null);
                    } else {
                        _outputs.push(newPort.external);
                        newPort.external.owner = this;
                    }
                }
            }
        }

        this.blueprint = newBp;
        // Обновляем связи после изменения структуры портов
        _updatePortLinks();
    }

    private function _createInterface():Void {
        if (blueprint == null || blueprint.pins == null) return;
        for (pinDef in blueprint.pins) {
            var port = new ConductorPort(pinDef.name, pinDef.type, pinDef.defaultValue);
            ports.set(pinDef.name, port);
        }
        // Устанавливаем связи согласно текущему режиму isLogic
        _updatePortLinks();
    }

    private function _createInternalInstances():Void {
        if (blueprint == null || blueprint.internalAtoms == null) return;

        for (atomDef in blueprint.internalAtoms) {
            if (atomDef.typeId == this.blueprint.id) {
                trace('WARN: Skipped recursive instantiation of ${atomDef.typeId} inside itself.');
                continue;
            }

            var newInstanceID = UID.generate();
            _idMap.set(atomDef.instanceId, newInstanceID);

            var instance = AssemblyFactory.createAtom(atomDef.typeId, newInstanceID);
            if (instance != null) {
                internalAtoms.set(newInstanceID, instance);

                if (atomDef.values != null) {
                    instance.restoreState(atomDef.values);
                }

                var bpDef = AtomRegistry.get(atomDef.typeId);
                if (bpDef != null && bpDef.isActive && !bpDef.isNative) {
                    DriverManager.getInstance().register(instance);
            }
            }
        }
    }

    private function _createInternalConnections():Void {
        if (blueprint == null || blueprint.internalConnections == null) return;
        for (conn in blueprint.internalConnections) {
            var fromContact = resolveContact(conn.from);
            var toContact = resolveContact(conn.to);
            if (fromContact != null && toContact != null) {
                fromContact.link(toContact);
            }
        }
    }

    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") {
            var port = ports.get(point.contactName);
            return (port == null) ? null : port.internal;
        } else {
            var realAtomId = _idMap.get(point.atomId);
            if (realAtomId == null) {
                if (internalAtoms.exists(point.atomId)) {
                    realAtomId = point.atomId;
                } else {
                    return null;
                }
            }

            var obj = internalAtoms.get(realAtomId);
            if (obj == null) return null;

            var atom:Atom = cast obj;
            var c = atom.getInput(point.contactName);
            if (c == null) c = atom.getOutput(point.contactName);
            return c;
        }
    }

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
        if (blueprint.pins != null) blueprint.pins.push(pinDef);

        var port = new ConductorPort(name, type, defaultValue);
        ports.set(name, port);

        if (type == INPUT) {
            _inputs.push(port.external);
            port.external.owner = this;
            while (_inputCache.length < _inputs.length) _inputCache.push(null);
        } else {
            _outputs.push(port.external);
            port.external.owner = this;
        }

        // Обновляем связи для нового порта
        _updatePortLinks();

        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });

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
            if (_inputCache.length > _inputs.length) _inputCache.pop();
        } else {
            _outputs.remove(port.external);
        }

        port.dispose();
        ports.remove(name);

        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
    }

    // =========================================================================
    // STATE SERIALIZATION v5.0
    // =========================================================================

    override public function getPersistentState():Dynamic {
        var states:Dynamic = {};

        if (internalAtoms != null) {
            for (runtimeId in internalAtoms.keys()) {
                var atom:Atom = cast internalAtoms.get(runtimeId);
                if (atom != null) {
                    var state = atom.getPersistentState();
                    if (state != null) {
                        Reflect.setField(states, runtimeId, state);
                    }
                }
            }
        }

        var hasStates = false;
        for (field in Reflect.fields(states)) {
            hasStates = true;
            break;
        }

        // Возвращаем структуру, если есть данные или isLogic != false (по умолчанию)
        var baseState = super.getPersistentState();
        if (hasStates || (baseState != null && baseState.isLogic == true)) {
            return {
                isLogic: baseState != null ? baseState.isLogic : false,
                internalStates: hasStates ? states : null
            };
        }
        
        return null;
    }

    override public function restoreState(state:Dynamic):Void {
        if (state == null) return;

        // Сначала восстанавливаем флаг isLogic (это обновит связи портов)
        super.restoreState(state);

        if (internalAtoms != null && Reflect.hasField(state, "internalStates")) {
            var states = Reflect.field(state, "internalStates");
            for (runtimeId in internalAtoms.keys()) {
                if (Reflect.hasField(states, runtimeId)) {
                    var atom:Atom = cast internalAtoms.get(runtimeId);
                    if (atom != null) {
                        var atomState = Reflect.field(states, runtimeId);
                        atom.restoreState(atomState);
                    }
                }
            }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

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