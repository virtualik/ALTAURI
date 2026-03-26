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
import core.logic.Impulsys;
import core.logic.EventType;

/**
* ASSEMBLY v5.7 (Hot Start Protocol)
* Universal base class for ALL nodes.
*
* v5.7 Changes (HOT START PROTOCOL):
* - FIXED: Internal atoms now get isInitializing=true during creation.
* - FIXED: State restored while atoms are "frozen".
* - FIXED: _processPendingSignals forces output sync BEFORE unfreezing atoms.
* - RESULT: Toggle sets output -> LED gets signal. TextInput ignores inputs until unfrozen.
*
* v5.6 Changes (CRITICAL FIX):
* - FIXED: Changed tick() back to resume() - tick() doesn't unsuspend the queue!
* - FIXED: resume() properly sets _suspended = false BEFORE processing
*/
class Assembly extends Atom
{
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
    public function getTemplateId(runtimeId:String):String
    {
        for (templateId => rId in _idMap)
        {
            if (rId == runtimeId) return templateId;
        }
        return runtimeId;
    }
    private function get_inputs():Map<String, Contact>
    {
        var map = new Map<String, Contact>();
        for (p in ports)
        {
            if (p != null && p.type != null && p.type == INPUT)
            {
                map.set(p.name, p.external);
            }
        }
        return map;
    }
    private function get_outputs():Map<String, Contact>
    {
        var map = new Map<String, Contact>();
        for (p in ports)
        {
            if (p != null && p.type != null && p.type == OUTPUT)
            {
                map.set(p.name, p.external);
            }
        }
        return map;
    }

// =========================================================================
// LOGIC MODE SWITCH v5.3
// =========================================================================
    private var _portCallbacks:Map<String, Dynamic -> Void>;
    override private function set_isLogic(value:Bool):Bool
    {
        if (_isLogic != value)
        {
            _isLogic = value;
            _updatePortLinks();
        }
        return _isLogic;
    }

// ============================================================================
// ИНИЦИАЛИЗАЦИЯ v5.7 - Протокол горячего старта
// ============================================================================
    // isInitializing наследуется от Atom. 
    // Мы используем его напрямую (isInitializing = true/false).

    private var _quarantineReason:String = null;
    private var _isInQuarantine:Bool = false;

    public function quarantine(reason:String):Void
    {
        if (_isInQuarantine) return;
        _isInQuarantine = true;
        _quarantineReason = reason;
        trace('🚨 ASSEMBLY QUARANTINE: ${this.id} - ${reason}');
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port != null)
            {
                if (port.external.hasLink(port.internal))
                {
                    port.external.unlink(port.internal);
                }
                if (port.internal.hasLink(port.external))
                {
                    port.internal.unlink(port.external);
                }
            }
        }
        for (name in _portCallbacks.keys())
        {
            var port = ports.get(name);
            if (port != null)
            {
                port.internal.unsubscribe(_portCallbacks.get(name));
            }
        }
        _portCallbacks.clear();
        Impulsys.quickEmit(EventType.ATOM_DELETED, {
            assemblyId: this.id,
            id: this.id,
            reason: reason
        });
    }
    public function isInQuarantine():Bool return _isInQuarantine;
    public function getQuarantineReason():String return _quarantineReason;

// ============================================================================
// Assembly.hx - КОНСТРУКТОР (v5.7 - ИСПРАВЛЕНО)
// ============================================================================
    public function new(id:String, blueprint:Blueprint)
    {
        this.blueprint = blueprint;
        this.ports = new Map();
        this.internalAtoms = new Map();
        _idMap = new Map();
        _portCallbacks = new Map();

        // === FIX v5.7: Устанавливаем флаг инициализации САМЫМ ПЕРВЫМ ===
        // (используем поле унаследованное от Atom)
        isInitializing = true;

        _createInterface();
        var inputsArr:Array<Contact> = [];
        var outputsArr:Array<Contact> = [];
        var ordered = _getOrderedPortDefs();
        for (pinDef in ordered)
        {
            var p = ports.get(pinDef.name);
            if (p != null)
            {
                if (p.type != null && p.type == INPUT) inputsArr.push(p.external);
                else if (p.type != null) outputsArr.push(p.external);
            }
        }
        var typeName = blueprint != null ? blueprint.name : "Assembly";
        super(inputsArr, outputsArr, blueprint.logic, id, typeName, false);

        if (blueprint != null && blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0)
        {
            if (!_isLogic)
            {
                // trace('Assembly($id): Forcing isLogic=true for stability');
                _isLogic = true;
            }
        }

        if (blueprint.logic == null && blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0)
        {
            SignalQueue.getInstance().suspend();
            try
            {
                _createInternalInstances(); // Создаем с isInitializing=true
                _createInternalConnections();

                _initializeLogicState();

                _updatePortLinks();
            }
            catch (e:Dynamic)
            {
                trace('ERROR during Assembly($id) initialization: $e');
                trace('  Stack: ${haxe.CallStack.toString(haxe.CallStack.exceptionStack())}');
            }

            // === CRITICAL FIX v5.7: Снимаем флаг с САМОЙ СБОРКИ ===
            // Внутренние атомы остаются "заморожены" до _processPendingSignals
            isInitializing = false;

            SignalQueue.getInstance().resume();

            _processPendingSignals(); // Здесь разморозим атомы
        }
        else
        {
            isInitializing = false;
        }
    }

// =========================================================================
// ИНИЦИАЛИЗАЦИЯ ЛОГИЧЕСКОГО СОСТОЯНИЯ v5.5 (без изменений логики, только вызовы)
// =========================================================================
    private function _initializeLogicState():Void
    {
        // Устанавливаем определенные начальные значения для всех контактов
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port != null)
            {
                if (port.type == INPUT)
                {
                    if (port.external != null && port.external.value == null)
                    {
                        port.external.value = true;
                    }
                    if (port.internal != null && port.internal.value == null)
                    {
                        port.internal.value = true;
                    }
                }
                else if (port.type == OUTPUT)
                {
                    if (port.external != null && port.external.value == null)
                    {
                        port.external.value = false;
                    }
                    if (port.internal != null && port.internal.value == null)
                    {
                        port.internal.value = false;
                    }
                }
            }
        }

        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                if (Std.isOfType(atom, Assembly))
                {
                    var asm = cast(atom, Assembly);
                    asm._initializeLogicState();
                }
            }
        }
        _performInitialCalculation();
    }

    private function _performInitialCalculation():Void
    {
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                if (Std.isOfType(atom, Assembly))
                {
                    var asm = cast(atom, Assembly);
                    asm._performInitialCalculation();
                }
                else
                {
                    atom._calculate();
                }
            }
        }
        _syncExternalOutputs();
    }

    private function _syncExternalOutputs():Void
    {
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port != null && port.type == OUTPUT)
            {
                if (port.internal != null && port.external != null)
                {
                    port.external.value = port.internal.value;
                }
            }
        }
    }

// =========================================================================
// ОБРАБОТКА ОТЛОЖЕННЫХ СИГНАЛОВ v5.7 (Hot Start)
// =========================================================================
    /**
     * Запускает начальное распространение сигналов после инициализации.
     * v5.7: Размораживает атомы только ПОСЛЕ обновления значений.
     */
    private function _processPendingSignals():Void
    {
        // 1. Принудительно обновляем значения на выходах памяти (Toggle)
        // и синхронизируем порты сборки.
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;

                // Для обычных атомов (не сборок) с памятью, принудительно шлем сигнал
                for (output in atom.getOutputs())
                {
                    if (output != null && output.value != null)
                    {
                        output.propagateCurrentValue();
                    }
                }
            }
        }

        // Синхронизируем порты СБОРКИ (выходы)
        _syncExternalOutputs();

        // 2. РАЗМОРОЗКА АТОМОВ
        // Теперь, когда все сигналы прошли, атомы могут начать реагировать
        // на новые изменения (например, пользовательский ввод).
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                atom.isInitializing = false;

                if (Std.isOfType(atom, Assembly))
                {
                    cast(atom, Assembly)._processPendingSignals();
                }
            }
        }

        trace('Assembly($id): Hot Start complete. Signals propagated, atoms unfrozen.');
    }

// =========================================================================
// PORT LINKING LOGIC v5.3
// =========================================================================
    private function _updatePortLinks():Void
    {
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port == null) continue;
            if (port.type == null) continue;
            if (port.external == null) continue;
            if (port.internal == null) continue;
            
            if (port.external.hasLink(port.internal)) port.external.unlink(port.internal);
            if (port.internal.hasLink(port.external)) port.internal.unlink(port.external);
            
            if (_portCallbacks.exists(name))
            {
                port.internal.unsubscribe(_portCallbacks.get(name));
                _portCallbacks.remove(name);
            }
            
            if (this.isLogic)
            {
                if (port.type == INPUT)
                {
                    port.external.link(port.internal);
                }
                else
                {
                    var callback = function(v:Dynamic)
                    {
                        var targetPort = port;
                        SignalQueue.getInstance().scheduleNextTick(function()
                        {
                            if (!_isDisposed && targetPort != null && !isInitializing)
                            {
                                targetPort.external.value = v;
                            }
                        });
                    };
                    port.internal.subscribe(callback);
                    _portCallbacks.set(name, callback);
                }
            }
            else
            {
                if (port.type == INPUT)
                {
                    port.external.link(port.internal);
                }
                else
                {
                    port.internal.link(port.external);
                }
            }
        }
    }

// =========================================================================
// HOT RELOAD SUPPORT
// =========================================================================
    public function updateFromBlueprint(newBp:Blueprint):Void
    {
        if (newBp.id != this.blueprint.id) return;
        this.name = newBp.name;
        var currentPortNames = [for (name in ports.keys()) name];
        var targetPinNames = new Map<String, Bool>();
        for (pin in newBp.pins)
        {
            targetPinNames.set(pin.name, true);
        }
        for (name in currentPortNames)
        {
            if (!targetPinNames.exists(name))
            {
                var port = ports.get(name);
                if (port != null)
                {
                    if (port.type == INPUT)
                    {
                        _inputs.remove(port.external);
                        if (_inputCache.length > _inputs.length) _inputCache.pop();
                    }
                    else
                    {
                        _outputs.remove(port.external);
                    }
                    port.dispose();
                    ports.remove(name);
                }
            }
        }
        for (pin in newBp.pins)
        {
            var port = ports.get(pin.name);
            if (port == null)
            {
                var currentCount = 0;
                for (p in ports) if (p != null && p.type != null && p.type == pin.type) currentCount++;
                var max = (pin.type == INPUT) ? MAX_INPUT_PORTS : MAX_OUTPUT_PORTS;
                if (currentCount < max)
                {
                    var newPort = new ConductorPort(pin.name, pin.type, pin.defaultValue);
                    ports.set(pin.name, newPort);
                    if (pin.type == INPUT)
                    {
                        _inputs.push(newPort.external);
                        newPort.external.owner = this;
                        while (_inputCache.length < _inputs.length) _inputCache.push(null);
                    }
                    else
                    {
                        _outputs.push(newPort.external);
                        newPort.external.owner = this;
                    }
                }
            }
        }
        this.blueprint = newBp;
        _updatePortLinks();
    }

// ============================================================================
// _createInterface() с конвертацией String → ContactType
// ============================================================================
    private function _createInterface():Void
    {
        if (blueprint == null || blueprint.pins == null) return;
        for (pinDef in blueprint.pins)
        {
            if (pinDef == null)
            {
                trace('ERROR: PinDef is null in Blueprint(${blueprint.id})');
                continue;
            }
            if (pinDef.name == null)
            {
                trace('ERROR: PinDef.name is null in Blueprint(${blueprint.id})');
                continue;
            }
// === FIX: Конвертация типа ДО создания ConductorPort ===
            var portType:ContactType = pinDef.type;
            if (pinDef.type == null)
            {
                trace('WARN: PinDef "${pinDef.name}" has null.type, using UNDEFINED');
                portType = ContactType.UNDEFINED;
            }
            else if (Std.isOfType(pinDef.type, String))
            {
                var typeStr:String = cast pinDef.type;
                trace('DEBUG: Converting String type "${typeStr}" to ContactType for pin "${pinDef.name}"');
                switch (typeStr)
                {
                    case "INPUT": portType = ContactType.INPUT;
                    case "OUTPUT": portType = ContactType.OUTPUT;
                    case "BIDIRECTIONAL": portType = ContactType.BIDIRECTIONAL;
                    default:
                        trace('WARN: Unknown type "${typeStr}", using UNDEFINED');
                        portType = ContactType.UNDEFINED;
                }
            }
            else if (!Std.isOfType(pinDef.type, ContactType))
            {
                trace('ERROR: PinDef "${pinDef.name}" has invalid type: ${pinDef.type}');
                portType = ContactType.UNDEFINED;
            }
            var port = new ConductorPort(pinDef.name, portType, pinDef.defaultValue);
            ports.set(pinDef.name, port);
        }
        _updatePortLinks();
    }

    private function _createInternalInstances():Void
    {
        if (blueprint == null || blueprint.internalAtoms == null) return;
        for (atomDef in blueprint.internalAtoms)
        {
            if (atomDef.typeId == this.blueprint.id)
            {
                trace('WARN: Skipped recursive instantiation of ${atomDef.typeId} inside itself.');
                continue;
            }
            var newInstanceID = UID.generate();
            _idMap.set(atomDef.instanceId, newInstanceID);
            var instance = AssemblyFactory.createAtom(atomDef.typeId, newInstanceID);
            if (instance != null)
            {
                // === FIX v5.7: Замораживаем атом при создании ===
                instance.isInitializing = true;

                internalAtoms.set(newInstanceID, instance);
                if (atomDef.values != null)
                {
                    instance.restoreState(atomDef.values);
                }
                var bpDef = AtomRegistry.get(atomDef.typeId);
                if (bpDef != null && bpDef.isActive && !bpDef.isNative)
                {
                    DriverManager.getInstance().register(instance);
                }
            }
        }
    }

// ============================================================================
// _createInternalConnections() с полной защитой
// ============================================================================
    private function _createInternalConnections():Void
    {
        if (blueprint == null || blueprint.internalConnections == null) return;
        for (conn in blueprint.internalConnections)
        {
            var fromContact = resolveContact(conn.from);
            var toContact = resolveContact(conn.to);
            if (fromContact == null)
            {
                trace('ERROR: Assembly(${this.id}): fromContact NULL for ${conn.from.atomId}.${conn.from.contactName}');
                continue;
            }
            if (toContact == null)
            {
                trace('ERROR: Assembly(${this.id}): toContact NULL for ${conn.to.atomId}.${conn.to.contactName}');
                continue;
            }
            if (fromContact.type == null)
            {
                trace('ERROR: Assembly(${this.id}): fromContact.type is NULL for ${conn.from.atomId}.${conn.from.contactName}');
                trace('  Contact ID: ${fromContact.id}');
                trace('  Contact name: ${fromContact.name}');
                trace('  Contact owner: ${fromContact.owner != null ? fromContact.owner.id : "null"}');
                continue;
            }
            if (toContact.type == null)
            {
                trace('ERROR: Assembly(${this.id}): toContact.type is NULL for ${conn.to.atomId}.${conn.to.contactName}');
                trace('  Contact ID: ${toContact.id}');
                trace('  Contact name: ${toContact.name}');
                trace('  Contact owner: ${toContact.owner != null ? toContact.owner.id : "null"}');
                continue;
            }
            // === FIX v5.5: Передаем suppressPropagation=true для предотвращения осцилляции ===
            // Но запоминаем связь для последующего распространения
            fromContact.link(toContact, true);
        }
    }

// ============================================================================
// resolveContact() С ПОЛНОЙ ОБРАБОТКОЙ ASSEMBLY АТОМОВ
// ============================================================================
    private function resolveContact(point:ConnectionPoint):Contact
    {
        if (point == null)
        {
            trace('ERROR: resolveContact received null point');
            return null;
        }
        if (point.atomId == "SELF")
        {
            var port = ports.get(point.contactName);
            if (port == null)
            {
                trace('WARN: Port "${point.contactName}" not found in Assembly(${this.id})');
                return null;
            }
            // Для SELF (себя) мы возвращаем внутренний контакт,
            // так как внутренние атомы подключаются к внутренней стороне границы сборки.
            var contact = port.internal;
            if (contact == null)
            {
                trace('ERROR: Port "${point.contactName}" internal contact is null!');
                return null;
            }
            return contact;
        }
        else {
            var realAtomId = _idMap.get(point.atomId);
            if (realAtomId == null)
            {
                if (internalAtoms.exists(point.atomId))
                {
                    realAtomId = point.atomId;
                }
                else
                {
                    trace('WARN: Atom "${point.atomId}" not found in Assembly(${this.id})');
                    trace('  Available keys: ${[for(k in internalAtoms.keys()) k]}');
                    return null;
                }
            }
            var obj = internalAtoms.get(realAtomId);
            if (obj == null)
            {
                trace('WARN: Instance "${realAtomId}" is null in Assembly(${this.id})');
                return null;
            }
            var atom:Atom = cast obj;

            if (Std.isOfType(atom, Assembly))
            {
                var asm = cast(atom, Assembly);
                var port = asm.ports.get(point.contactName);
                if (port == null)
                {
                    trace('ERROR: Port "${point.contactName}" NOT FOUND on Assembly ${atom.name}(${realAtomId})');
                    trace('  Available ports: ${[for(k in asm.ports.keys()) k]}');
                    return null;
                }

                // === ИСПРАВЛЕНИЕ: Для вложенных сборок используем ВНЕШНИЙ контакт ===
                // Внешний мир (родительская сборка) должен подключаться к внешней стороне порта.
                var contact:Contact = port.external;

                if (contact == null)
                {
                    trace('ERROR: External contact from port "${point.contactName}" is null!');
                    return null;
                }

                if (contact.type == null)
                {
                    trace('ERROR: Contact "${point.contactName}" has NULL type!');
                    trace('  Port type: ${port.type}');
                    trace('  Atom: ${atom.name} (${atom.id})');
                    return null;
                }
                return contact;
            }
            else {
                // Обычный атом (NAND, etc.) - используем getInput/getOutput
                var c = atom.getInput(point.contactName);
                if (c == null) c = atom.getOutput(point.contactName);
                if (c == null)
                {
                    trace('WARN: Contact "${point.contactName}" not found on atom ${atom.name}(${realAtomId})');
                    return null;
                }
                if (c.type == null)
                {
                    trace('ERROR: Contact "${point.contactName}" on ${atom.name} has null.type!');
                    return null;
                }
                return c;
            }
        }
    }

    private function _getOrderedPortDefs():Array<PinDef>
    {
        if (blueprint == null || blueprint.pins == null) return [];
        return blueprint.pins.copy();
    }

    public function getOrderedPorts(type:ContactType):Array<ConductorPort>
    {
        var result:Array<ConductorPort> = [];
        var defs = _getOrderedPortDefs();
        for (pin in defs)
        {
            if (pin.type == type)
            {
                var p = ports.get(pin.name);
                if (p != null) result.push(p);
            }
        }
        return result;
    }

    public function addPort(name:String, type:ContactType, defaultValue:Dynamic = null):ConductorPort
    {
        var currentCount = 0;
        for (p in ports) if (p != null && p.type != null && p.type == type) currentCount++;
        var max = (type == INPUT) ? MAX_INPUT_PORTS : MAX_OUTPUT_PORTS;
        if (currentCount >= max)
        {
            trace('ERROR: Max ports limit reached for type $type');
            return null;
        }
        if (ports.exists(name))
        {
            trace('ERROR: Port name "$name" already exists');
            return null;
        }
        var pinDef:PinDef = { name: name, type: type, defaultValue: defaultValue };
        if (blueprint.pins != null) blueprint.pins.push(pinDef);
        var port = new ConductorPort(name, type, defaultValue);
        ports.set(name, port);
        if (type == INPUT)
        {
            _inputs.push(port.external);
            port.external.owner = this;
            while (_inputCache.length < _inputs.length) _inputCache.push(null);
        }
        else {
            _outputs.push(port.external);
            port.external.owner = this;
        }
        _updatePortLinks();
        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
        return port;
    }

    public function removePort(name:String):Void
    {
        var port = ports.get(name);
        if (port == null) return;
        var pinToRemove:PinDef = null;
        if (blueprint.pins != null)
        {
            for (i in 0...blueprint.pins.length)
            {
                var p = blueprint.pins[i];
                if (p != null && p.name == name)
                {
                    pinToRemove = p;
                    break;
                }
            }
            if (pinToRemove != null)
            {
                blueprint.pins.remove(pinToRemove);
            }
        }
        if (port.type == INPUT)
        {
            _inputs.remove(port.external);
            if (_inputCache.length > _inputs.length) _inputCache.pop();
        }
        else {
            _outputs.remove(port.external);
        }
        port.dispose();
        ports.remove(name);
        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
    }

// =========================================================================
// STATE SERIALIZATION v5.0
// =========================================================================
    override public function getPersistentState():Dynamic
    {
        var states:Dynamic = {};
        if (internalAtoms != null)
        {
            for (runtimeId in internalAtoms.keys())
            {
                var atom:Atom = cast internalAtoms.get(runtimeId);
                if (atom != null)
                {
                    var state = atom.getPersistentState();
                    if (state != null)
                    {
                        Reflect.setField(states, runtimeId, state);
                    }
                }
            }
        }
        var hasStates = false;
        for (field in Reflect.fields(states))
        {
            hasStates = true;
            break;
        }
        var baseState = super.getPersistentState();
        if (hasStates || (baseState != null && baseState.isLogic == true))
        {
            return
            {
                isLogic: baseState != null ? baseState.isLogic : false,
                internalStates: hasStates ? states : null
            };
        }
        return null;
    }

    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        if (blueprint != null && blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0)
        {
            var wasLogic = _isLogic;
            _isLogic = true;
            if (wasLogic != _isLogic)
            {
                _updatePortLinks();
            }
        }
        else if (Reflect.hasField(state, "isLogic"))
        {
            var wasLogic = _isLogic;
            _isLogic = state.isLogic;
            if (wasLogic != _isLogic)
            {
                _updatePortLinks();
            }
        }
        if (internalAtoms != null && Reflect.hasField(state, "internalStates"))
        {
            var states = Reflect.field(state, "internalStates");
            for (runtimeId in internalAtoms.keys())
            {
                if (Reflect.hasField(states, runtimeId))
                {
                    var atom:Atom = cast internalAtoms.get(runtimeId);
                    if (atom != null)
                    {
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
    override public function dispose():Void
    {
        var keys = [for (k in internalAtoms.keys()) k];
        for (key in keys)
        {
            var obj = internalAtoms.get(key);
            if (obj != null)
            {
                if (Std.isOfType(obj, IDisposable))
                {
                    try { cast(obj, IDisposable).dispose(); }
                    catch (e:Dynamic) { trace('Error: $e'); }
                }
            }
        }
        internalAtoms.clear();
        internalAtoms = null;
        var portKeys = [for (k in ports.keys()) k];
        for (key in portKeys)
        {
            var port = ports.get(key);
            if (port != null) port.dispose();
        }
        ports.clear();
        ports = null;
        super.dispose();
    }
}