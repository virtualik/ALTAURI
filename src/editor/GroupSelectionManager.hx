package editor;

/**
 * SELECTION MANAGER v1.0
 * Чистый класс для управления списком выделенных ID.
 * Не зависит от графики (OpenFL), работает только с данными.
 */
class GroupSelectionManager {

    private var _selectedNodes:Map<String, Bool>;
    private var _selectedWires:Array<String>;

    public function new() {
        _selectedNodes = new Map();
        _selectedWires = [];
    }

    // =========================================================================
    // NODES
    // =========================================================================

    public function addNode(id:String):Void {
        if (!_selectedNodes.exists(id)) {
            _selectedNodes.set(id, true);
        }
    }

    public function removeNode(id:String):Void {
        _selectedNodes.remove(id);
    }

    public function hasNode(id:String):Bool {
        return _selectedNodes.exists(id);
    }

    public function toggleNode(id:String):Bool {
        if (hasNode(id)) {
            removeNode(id);
            return false;
        } else {
            addNode(id);
            return true;
        }
    }

    public function clearNodes():Void {
        _selectedNodes = new Map();
    }

    public function getNodeIds():Array<String> {
        return [for (id in _selectedNodes.keys()) id];
    }

    public function getNodeCount():Int {
        var c = 0;
        for (k in _selectedNodes.keys()) c++;
        return c;
    }

    // =========================================================================
    // WIRES
    // =========================================================================

    public function addWire(id:String):Void {
        if (_selectedWires.indexOf(id) == -1) {
            _selectedWires.push(id);
        }
    }

    public function removeWire(id:String):Void {
        _selectedWires.remove(id);
    }

    public function hasWire(id:String):Bool {
        return _selectedWires.indexOf(id) != -1;
    }

    public function clearWires():Void {
        _selectedWires = [];
    }

    public function getWireIds():Array<String> {
        return _selectedWires.copy();
    }

    public function getWireCount():Int {
        return _selectedWires.length;
    }

    // =========================================================================
    // GLOBAL
    // =========================================================================

    /**
     * Полная очистка выделения.
     */
    public function clear():Void {
        clearNodes();
        clearWires();
    }

    /**
     * Выделить все переданные ID узлов.
     */
    public function setNodes(ids:Array<String>):Void {
        clearNodes();
        for (id in ids) addNode(id);
    }

    /**
     * Выделить все переданные ID проводов.
     */
    public function setWires(ids:Array<String>):Void {
        clearWires();
        for (id in ids) addWire(id);
    }
}