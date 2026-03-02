package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionPoint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.AssemblyFactory;
import core.base.IDisposable;
import core.types.ContactType;
import core.logic.Impulsys;
import library.AtomRegistry;
import haxe.Json;
import openfl.net.FileReference;

class GroupAtomsCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _selectedNodeIds:Array<String>;

    public function new(blueprint:Blueprint, assembly:Assembly, selectedIds:Array<String>) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _selectedNodeIds = selectedIds;
    }

    override private function executeInternal():Void {
        if (_selectedNodeIds.length == 0) {
            trace("Nothing to group.");
            complete();
            return;
        }

        // 1. Сбор данных о внутренних атомах
        var newInternalAtoms:Array<AtomDef> = [];
        var newInternalConnections:Array<ConnectionDef> = [];
        
        var newPins:Array<PinDef> = [];
        var externalConnections:Array<{conn:ConnectionDef, isSourceSelected:Bool}> = [];

        // Карта для переноса ID: старый ID -> новый ID (если нужно, но мы сохраним старые)
        // Но для простоты оставим ID как есть, они уникальны.

        // Разделяем связи
        for (conn in _blueprint.internalConnections) {
            var fromSel = _selectedNodeIds.indexOf(conn.from.atomId) != -1;
            var toSel = _selectedNodeIds.indexOf(conn.to.atomId) != -1;

            if (fromSel && toSel) {
                // Внутренняя связь
                newInternalConnections.push(conn);
            } else {
                // Внешняя связь (граница)
                externalConnections.push({conn: conn, isSourceSelected: fromSel});
            }
        }

        // Список атомов для включения
        for (atomDef in _blueprint.internalAtoms) {
            if (_selectedNodeIds.indexOf(atomDef.instanceId) != -1) {
                newInternalAtoms.push(atomDef);
            }
        }

        // 2. Создание интерфейса (Pins) на основе внешних связей
        var pinCounter = 0;
        var mapping:Array<{oldConn:ConnectionDef, newPinName:String, isInput:Bool}> = [];

        for (item in externalConnections) {
            var conn = item.conn;
            var pinName = "pin_" + pinCounter++;
            var pinType:ContactType = item.isSourceSelected ? OUTPUT : INPUT;

            // Создаем Pin Definition
            newPins.push({name: pinName, type: pinType, defaultValue: null});

            // Создаем связь внутри новой сборки
            // Если источник выделен (Source -> Outside), значит внутри это Output -> Self.Pin(Input? No, внутри это Output для внешнего мира, но на схеме это выход)
            // Давай разберем:
            // Case A: Selected(Atom) -> Unselected(Atom). 
            //         Это Выход сборки. Pin Type = OUTPUT.
            //         Внутри новой сборки: Atom.Out -> Self.Pin (Pin ведет наружу).
            //         Connection: {from: Atom, to: SELF, contact: PinName}.
            
            // Case B: Unselected(Atom) -> Selected(Atom).
            //         Это Вход сборки. Pin Type = INPUT.
            //         Внутри новой сборки: Self.Pin -> Atom.In.
            //         Connection: {from: SELF, to: Atom, contact: PinName}.

            if (item.isSourceSelected) {
                // Case A: Outgoing
                newInternalConnections.push({
                    from: conn.from,
                    to: {atomId: "SELF", contactName: pinName}
                });
            } else {
                // Case B: Incoming
                newInternalConnections.push({
                    from: {atomId: "SELF", contactName: pinName},
                    to: conn.to
                });
            }
            
            mapping.push({oldConn: conn, newPinName: pinName, isInput: !item.isSourceSelected});
        }

        // 3. Создание и сохранение Blueprint
        var newTypeId = "CustomAssembly_" + Std.random(10000);
        var newBp = new Blueprint(newTypeId, "Custom Assembly", newPins, null, newInternalAtoms, newInternalConnections);
        
        // Сохраняем на диск (автоматически в файл)
        saveNewAssembly(newBp);

        // Регистрируем в рантайме
        AtomRegistry.registerBlueprint(newTypeId, newBp);

        // 4. Модификация текущей схемы (Замена группы на один атом)
        
        // Удаляем старые атомы из Blueprint и Assembly
        for (id in _selectedNodeIds) {
            var def = findAtomDef(id);
            if (def != null) _blueprint.internalAtoms.remove(def);
            
            var inst = _assembly.internalAtoms.get(id);
            if (inst != null) {
                 cast(inst, IDisposable).dispose();
                 _assembly.internalAtoms.remove(id);
            }
        }

        // Удаляем старые связи
        for (item in externalConnections) {
            _blueprint.internalConnections.remove(item.conn);
        }

        // Создаем новый атом
        var newAtomInstance = AssemblyFactory.createAtom(newTypeId, newTypeId + "_inst");
        _assembly.internalAtoms.set(newAtomInstance.id, newAtomInstance);
        _blueprint.internalAtoms.push({instanceId: newAtomInstance.id, typeId: newTypeId, x: 300, y: 300}); // Center pos

        // Восстанавливаем связи снаружи
        for (m in mapping) {
            // m.oldConn содержит внешние точки.
            // Если это был Incoming (Unselected -> Selected), то m.oldConn.from это внешний источник.
            // Нам нужно соединить: m.oldConn.from -> NewAtom.NewPinName
            
            var newConn:ConnectionDef;
            if (m.isInput) {
                // Incoming
                newConn = {
                    from: m.oldConn.from,
                    to: {atomId: newAtomInstance.id, contactName: m.newPinName}
                };
            } else {
                // Outgoing
                newConn = {
                    from: {atomId: newAtomInstance.id, contactName: m.newPinName},
                    to: m.oldConn.to
                };
            }
            
            _blueprint.internalConnections.push(newConn);
            
            // Физическое соединение
            var c1 = resolveContact(newConn.from);
            var c2 = resolveContact(newConn.to);
            if(c1!=null && c2!=null) c1.link(c2);
        }

        Impulsys.quickEmit("REDRAW_WIRES");
        // UI обновится через импульсы или пересоздание, лучше дать команду редактору обновиться
        Impulsys.quickEmit("ATOM_RESTORED", {id: newAtomInstance.id, x: 300, y: 300, atom: newAtomInstance}); 
        
        // Удаляем старые виды
        for (id in _selectedNodeIds) Impulsys.quickEmit("ATOM_DELETED", {id: id});

        complete();
    }

    private function saveNewAssembly(bp:Blueprint):Void {
        // Простое сохранение через ProjectIO (дописать туда метод для сохранения "как в библиотеку")
        // Для примера сохраняем в файл рядом с exe
        var data:Dynamic = {
            version: "1.0",
            blueprint: bp // Serializer должен уметь сворачивать bp в JSON
        };
        
        // Используем FileReference для сохранения без диалога (Lime/OpenFL специфично, но save открывает диалог)
        // Чтобы сохранить тихо, нужен sys.io.File на Desktop.
        #if sys
        var path = "library/" + bp.id + ".atom";
        sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
        trace("Assembly saved to: " + path);
        #else
        trace("Auto-save only supported on Desktop target.");
        #end
    }

    private function findAtomDef(id:String):AtomDef {
        for (a in _blueprint.internalAtoms) if (a.instanceId == id) return a;
        return null;
    }
    
    private function resolveContact(point:ConnectionPoint):Contact {
        // Копия логики из NodeEditor/ConnectCommand
        if (point.atomId == "SELF") return null; // Не должно быть SELF на уровне текущей сборки
        var atom = _assembly.internalAtoms.get(point.atomId);
        if (atom == null) return null;
        var a:Atom = cast atom;
        return (a.getInput(point.contactName) != null) ? a.getInput(point.contactName) : a.getOutput(point.contactName);
    }
}