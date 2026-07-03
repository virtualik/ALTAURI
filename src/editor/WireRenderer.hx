package editor;

import openfl.display.Sprite;
import openfl.display.Graphics;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.data.Blueprint;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import ui.WireType;
import ui.WireType.WireType as WireTypeEnum;

/**
 * WIRE RENDERER v1.3 (Coordinate Fix)
 * Responsible for visualizing all wires (connections) in NodeEditor.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.3 FIX:
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * PROBLEM:
 * NodeView.getPortPosition() returns GLOBAL (stage) coordinates,
 * but _container.graphics expects LOCAL coordinates relative to _canvas.
 *
 * After zoom/pan, the _canvas transformation changes, so global coordinates
 * no longer match local - wires shift relative to ports!
 *
 * SOLUTION:
 * Convert global coordinates to canvas-local coordinates,
 * just as already done for SELF (edge ports).
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   WireRenderer                                                          │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Dependencies (set via configure()):                            │   │
 * │   │  - _blueprint:Blueprint       → Connection definitions          │   │
 * │   │  - _assembly:Assembly         → Runtime atom instances          │   │
 * │   │  - _canvas:Sprite             → Main canvas                     │   │
 * │   │  - _getNodeView:String→NodeView → Port position lookup          │   │
 * │   │  - _getEdgePort:String→Sprite  → Edge port position lookup      │   │
 * │   │  - _getSelectedWireIds:Void→Array → Selection state              │   │
 * │   │                                                                 │   │
 * │   │  Internal State:                                                │   │
 * │   │  - _wireSprites:Map<String, WireEntry> → All rendered wires     │   │
 * │   │  - _activeWires:Array<Sprite>           → Wires being dragged   │   │
 * │   │  - _ghostWire:Sprite                    → Drag preview wire     │   │
 * │   │  - _wireType:WireTypeEnum               → BEZIER or STRAIGHT    │   │
 * │   │                                                                 │   │
 * │   │  Public API:                                                    │   │
 * │   │  - configure(...)                                               │   │
 * │   │  - rebuildAll()           → Redraw all wires from blueprint     │   │
 * │   │  - clearAll()             → Remove all wires                    │   │
 * │   │  - drawGhostWire(...)     → Begin drag preview                  │   │
 * │   │  - clearGhostWire()       → Remove drag preview                 │   │
 * │   │  - setActiveWiresForNodes() → Track wires during node drag      │   │
 * │   │  - updateActiveWires()    → Update tracked wires positions      │   │
 * │   │  - updateEdgeWires()      → Update SELF-connected wires         │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Wire Types:                                                           │
 * │   ───────────                                                           │
 * │   BEZIER:   ╭────────╮  (smooth cubic curve)                           │
 * │   STRAIGHT: ╱─────────╱  (horizontal tails + direct line)              │
 * │                                                                         │
 * │   v1.2 Changes:                                                         │
 * │   - Clear selection callback in dispose()                               │
 * │   - Null checks for all external references                             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class WireRenderer {
    // === Dependencies (set via configure) ===
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _canvas:Sprite;
    private var _theme:EditorTheme;
    
    // === Node/Port accessors ===
    private var _getNodeView:String -> NodeView;
    private var _getEdgePort:String -> Sprite;
    private var _getSelectedWireIds:Void -> Array<String>;
    
    // === Internal state ===
    private var _container:Sprite;
    private var _wireSprites:Map<String, WireEntry>;
    private var _activeWires:Array<Sprite>;
    private var _ghostWire:Sprite;
    private var _wireType:WireTypeEnum;
    
    // === Selection callback ===
    private var _onWireSelectionChanged:Array<String> -> Void;
    
    // === Disposed flag ===
    private var _isDisposed:Bool = false;
    
    public var wireType(get, set):WireTypeEnum;
    public var container(get, never):Sprite;
    
    public function new() {
        _wireSprites = new Map();
        _activeWires = [];
        _wireType = WireType.BEZIER;
        _theme = EditorTheme.getInstance();
    }
    
    // ========================================================================
    // CONFIGURATION
    // ========================================================================
    /**
     * Configure the renderer with all required dependencies.
     * Must be called before any rendering methods.
     */
    public function configure(
        blueprint:Blueprint,
        assembly:Assembly,
        canvas:Sprite,
        getNodeView:String -> NodeView,
        getEdgePort:String -> Sprite,
        getSelectedWireIds:Void -> Array<String>
    ):Void {
        _blueprint = blueprint;
        _assembly = assembly;
        _canvas = canvas;
        _getNodeView = getNodeView;
        _getEdgePort = getEdgePort;
        _getSelectedWireIds = getSelectedWireIds;
        
        _container = new Sprite();
        _container.mouseEnabled = false;
        _canvas.addChild(_container);
        
        _ghostWire = new Sprite();
        _ghostWire.mouseEnabled = false;
        _canvas.addChild(_ghostWire);
    }
    
    /**
     * Set callback for wire selection changes.
     */
    public function setSelectionCallback(callback:Array<String> -> Void):Void {
        _onWireSelectionChanged = callback;
    }
    
    // ========================================================================
    // ACTIVE WIRES (during drag)
    // ========================================================================
    /**
     * Mark wires connected to specified nodes as "active".
     * Active wires will be updated on every node move.
     */
    public function setActiveWiresForNodes(nodeIds:Array<String>):Void {
        if (_isDisposed) return;
        
        clearActiveWires();
        
        if (_blueprint.internalConnections == null) return;
        
        var movingSet = new Map<String, Bool>();
        for (id in nodeIds) movingSet.set(id, true);
        
        for (link in _blueprint.internalConnections) {
            var fromRuntime = _assembly.idMap.get(link.from.atomId);
            if (fromRuntime == null) fromRuntime = link.from.atomId;
            
            var toRuntime = _assembly.idMap.get(link.to.atomId);
            if (toRuntime == null) toRuntime = link.to.atomId;
            
            var isFromMoving = movingSet.exists(fromRuntime);
            var isToMoving = movingSet.exists(toRuntime);
            
            if (isFromMoving || isToMoving) {
                var id = getWireIDStatic(link);
                var entry = _wireSprites.get(id);
                if (entry != null) {
                    addActiveWire(entry.sprite);
                }
            }
        }
    }
    
    /**
     * Add a wire sprite to the active set.
     */
    public function addActiveWire(sprite:Sprite):Void {
        if (_isDisposed) return;
        if (_activeWires.indexOf(sprite) == -1) {
            _activeWires.push(sprite);
        }
    }
    
    /**
     * Clear the active wires set.
     */
    public function clearActiveWires():Void {
        _activeWires = [];
    }
    
    /**
     * Update rendering of active wires (called during node drag).
     */
    public function updateActiveWires():Void {
        if (_isDisposed || _activeWires.length == 0) return;
        
        var selectedIds = _getSelectedWireIds();
        
        for (link in _blueprint.internalConnections) {
            var id = getWireIDStatic(link);
            var entry = _wireSprites.get(id);
            
            if (entry != null && _activeWires.indexOf(entry.sprite) != -1) {
                var isSelected = selectedIds.indexOf(id) != -1;
                var thickness = isSelected ? 4 : _theme.WIRE_THICKNESS;
                var color = isSelected ? _theme.WIRE_COLOR_SELECTED : _theme.WIRE_COLOR_DEFAULT;
                drawWireGraphics(entry.sprite.graphics, link, color, thickness);
            }
        }
    }
    
    // ========================================================================
    // MAIN RENDERING
    // ========================================================================
    /**
     * Rebuild all wires from blueprint connections.
     * Creates new sprites for new connections, updates existing ones,
     * and removes sprites for deleted connections.
     */
    public function rebuildAll():Void {
        if (_isDisposed) return;
        
        var activeWireIds = new Map<String, Bool>();
        
        if (_blueprint.internalConnections != null) {
            for (link in _blueprint.internalConnections) {
                var id = getWireIDStatic(link);
                activeWireIds.set(id, true);
                
                var entry = _wireSprites.get(id);
                if (entry != null) {
                    var selectedIds = _getSelectedWireIds();
                    var isSelected = selectedIds.indexOf(id) != -1;
                    var color = isSelected ? _theme.WIRE_COLOR_SELECTED : _theme.WIRE_COLOR_DEFAULT;
                    var thickness = isSelected ? 4 : _theme.WIRE_THICKNESS;
                    drawWireGraphics(entry.sprite.graphics, link, color, thickness);
                } else {
                    createWireSprite(link);
                }
            }
        }
        
        // Remove deleted wires
        var idsToRemove:Array<String> = [];
        for (id in _wireSprites.keys()) {
            if (!activeWireIds.exists(id)) {
                idsToRemove.push(id);
            }
        }
        for (id in idsToRemove) {
            removeWireSprite(id);
        }
    }
    
    /**
     * Remove all wire sprites and clear internal state.
     */
    public function clearAll():Void {
        for (key in _wireSprites.keys()) {
            var entry = _wireSprites.get(key);
            if (entry == null) continue;
            
            entry.sprite.removeEventListener(MouseEvent.CLICK, entry.clickHandler);
            if (entry.rightClickHandler != null) {
                entry.sprite.removeEventListener(MouseEvent.RIGHT_CLICK, entry.rightClickHandler);
            }
            entry.sprite.graphics.clear();
            if (entry.sprite.parent != null) {
                entry.sprite.parent.removeChild(entry.sprite);
            }
        }
        _wireSprites.clear();
        _activeWires = [];
    }
    
    /**
     * Update wires connected to SELF (edge ports).
     * Called when the assembly frame is resized.
     */
    public function updateEdgeWires():Void {
        if (_isDisposed || _blueprint.internalConnections == null) return;
        
        for (link in _blueprint.internalConnections) {
            if (link.from.atomId == "SELF" || link.to.atomId == "SELF") {
                var wireID = getWireIDStatic(link);
                var entry = _wireSprites.get(wireID);
                if (entry != null) {
                    drawWireGraphics(entry.sprite.graphics, link);
                }
            }
        }
    }
    
    // ========================================================================
    // GHOST WIRE (drag preview)
    // ========================================================================
    /**
     * Draw the ghost wire during port drag operation.
     * 
     * @param startX Start X (global/stage coordinates)
     * @param startY Start Y (global/stage coordinates)
     * @param endX   End X (global/stage coordinates)
     * @param endY   End Y (global/stage coordinates)
     * @param isInput Whether the start port is an input
     */
    public function drawGhostWire(startX:Float, startY:Float, endX:Float, endY:Float, isInput:Bool):Void {
        if (_isDisposed || _ghostWire == null) return;
        
        var g = _ghostWire.graphics;
        g.clear();
        
        var p1 = _canvas.globalToLocal(new Point(startX, startY));
        var p2 = _canvas.globalToLocal(new Point(endX, endY));
        
        g.lineStyle(4, _theme.WIRE_COLOR_GHOST, 0.8);
        g.moveTo(p1.x, p1.y);
        
        switch (_wireType) {
            case WireType.BEZIER: drawGhostBezier(g, p1, p2, isInput);
            case WireType.STRAIGHT: drawGhostStraight(g, p1, p2, isInput);
        }
    }
    
    /**
     * Clear the ghost wire preview.
     */
    public function clearGhostWire():Void {
        if (_ghostWire != null) {
            _ghostWire.graphics.clear();
        }
    }
    
    // ========================================================================
    // WIRE DELETION
    // ========================================================================
    /**
     * Remove a specific wire sprite by its ID.
     */
    public function removeWireSprite(id:String):Void {
        var entry = _wireSprites.get(id);
        if (entry == null) return;
        
        entry.sprite.removeEventListener(MouseEvent.CLICK, entry.clickHandler);
        if (entry.rightClickHandler != null) {
            entry.sprite.removeEventListener(MouseEvent.RIGHT_CLICK, entry.rightClickHandler);
        }
        entry.sprite.graphics.clear();
        if (entry.sprite.parent != null) {
            entry.sprite.parent.removeChild(entry.sprite);
        }
        _wireSprites.remove(id);
    }
    
    /**
     * Get the total number of wires in the blueprint.
     */
    public function getWireCount():Int {
        return (_blueprint == null || _blueprint.internalConnections == null) ? 0 : _blueprint.internalConnections.length;
    }
    
    // ========================================================================
    // PROPERTIES
    // ========================================================================
    private function get_wireType():WireTypeEnum return _wireType;
    private function set_wireType(value:WireTypeEnum):WireTypeEnum {
        _wireType = value;
        rebuildAll();
        return _wireType;
    }
    
    private function get_container():Sprite return _container;
    
    // ========================================================================
    // INTERNAL: WIRE CREATION
    // ========================================================================
    /**
     * Create a new wire sprite for a connection and add it to the container.
     */
    private function createWireSprite(link:ConnectionDef):Sprite {
        var spr = new Sprite();
        spr.mouseEnabled = true;
        spr.buttonMode = true;
        
        var id = getWireIDStatic(link);
        var selectedIds = _getSelectedWireIds();
        var isSelected = selectedIds.indexOf(id) != -1;
        var color = isSelected ? _theme.WIRE_COLOR_SELECTED : _theme.WIRE_COLOR_DEFAULT;
        var thickness = isSelected ? 4 : _theme.WIRE_THICKNESS;
        
        drawWireGraphics(spr.graphics, link, color, thickness);
        
        spr.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        
        var clickHandler = function(e:MouseEvent) {
            e.stopPropagation();
            handleWireClick(id, e.ctrlKey);
        };
        var rightClickHandler = function(e:MouseEvent) {
            e.stopPropagation();
            handleWireRightClick(id);
        };
        
        spr.addEventListener(MouseEvent.CLICK, clickHandler);
        spr.addEventListener(MouseEvent.RIGHT_CLICK, rightClickHandler);
        
        _container.addChild(spr);
        _wireSprites.set(id, {
            sprite: spr,
            clickHandler: clickHandler,
            rightClickHandler: rightClickHandler
        });
        
        return spr;
    }
    
    /**
     * Handle left-click on a wire (selection toggle).
     */
    private function handleWireClick(wireId:String, ctrlKey:Bool):Void {
        if (_isDisposed) return;
        
        var selectedIds = _getSelectedWireIds();
        
        if (!ctrlKey) {
            selectedIds = [wireId];
        } else {
            var idx = selectedIds.indexOf(wireId);
            if (idx != -1) selectedIds.splice(idx, 1);
            else selectedIds.push(wireId);
        }
        
        if (_onWireSelectionChanged != null) {
            _onWireSelectionChanged(selectedIds);
        }
        
        rebuildAll();
    }
    
    /**
     * Handle right-click on a wire (context menu).
     * Selection logic:
     * - If wire is not selected: select ONLY this wire (deselecting everything else)
     * - If wire is already selected: keep current selection (group operation)
     */
    private function handleWireRightClick(wireId:String):Void {
        if (_isDisposed) return;
        
        var selectedIds = _getSelectedWireIds();
        
        // === SELECTION LOGIC ON RIGHT-CLICK ===
        // If the wire is not selected, we must select ONLY it.
        // This will deselect all nodes (via callback to NodeEditor).
        if (selectedIds.indexOf(wireId) == -1) {
            selectedIds = [wireId];
            // Notify NodeEditor: "Select only this wire (and deselect everything else)"
            if (_onWireSelectionChanged != null) {
                _onWireSelectionChanged(selectedIds);
            }
            // Redraw to update wire color
            rebuildAll();
        }
        // If the wire is already selected, we do NOT change selection (work with the group)
        
        // === SEND IMPULSE FOR CONTEXT MENU ===
        Impulsys.quickEmit(EventType.WIRE_RIGHT_CLICKED, {
            ids: selectedIds.copy(), // Pass current list (either 1 wire or a group)
            x: _canvas.stage.mouseX,
            y: _canvas.stage.mouseY
        });
    }
    
    // ========================================================================
    // INTERNAL: WIRE DRAWING
    // ========================================================================
    /**
     * Draw wire graphics for a connection.
     * 
     * @param g         Graphics object to draw into
     * @param link      Connection definition
     * @param color     Optional color override (-1 = use default)
     * @param thickness Optional thickness override (-1 = use default)
     */
    private function drawWireGraphics(g:Graphics, link:ConnectionDef, ?color:Int = -1, ?thickness:Float = -1):Void {
        if (color == -1) color = _theme.WIRE_COLOR_DEFAULT;
        if (thickness == -1) thickness = _theme.WIRE_THICKNESS;
        
        var p1 = getWirePoint(link.from);
        if (p1 == null) return;
        
        var p2 = getWirePoint(link.to);
        if (p2 == null) return;
        
        var isFromInput = isPointInput(link.from);
        var isToInput = isPointInput(link.to);
        
        g.clear();
        g.lineStyle(thickness, color);
        g.moveTo(p1.x, p1.y);
        
        switch (_wireType) {
            case WireType.BEZIER: drawWireBezier(g, p1, p2, isFromInput, isToInput);
            case WireType.STRAIGHT: drawWireStraight(g, p1, p2, isFromInput, isToInput);
        }
    }
    
    /**
     * Get the connection point for a wire endpoint.
     * 
     * ═══════════════════════════════════════════════════════════════════════
     * v1.3 FIX:
     * ═══════════════════════════════════════════════════════════════════════
     * 
     * NodeView.getPortPosition() returns GLOBAL coordinates,
     * but _container.graphics works in LOCAL coordinates of _canvas.
     * 
     * After zoom/pan, conversion global→local is required!
     */
    private function getWirePoint(point:ConnectionPoint):{x:Float, y:Float} {
        if (point.atomId == "SELF") {
            // Edge ports of the assembly
            var portSpr = _getEdgePort(point.contactName);
            if (portSpr == null) return null;
            var pt = _canvas.globalToLocal(portSpr.localToGlobal(new Point(0, 0)));
            return { x: pt.x, y: pt.y };
        } else {
            // Regular nodes
            var runtimeId = _assembly.idMap.get(point.atomId);
            if (runtimeId == null) runtimeId = point.atomId;
            
            var view = _getNodeView(runtimeId);
            if (view == null) return null;
            
            var portPos = view.getPortPosition(point.contactName);
            if (portPos == null) return null;
            
            // === v1.3 FIX: Convert global to canvas local coordinates ===
            // getPortPosition returns global (stage) coordinates
            // _container.graphics needs local coordinates relative to _canvas
            var pt = _canvas.globalToLocal(new Point(portPos.x, portPos.y));
            return { x: pt.x, y: pt.y };
        }
    }
    
    /**
     * Check if a connection point is an input port.
     */
    private function isPointInput(point:ConnectionPoint):Bool {
        if (point.atomId == "SELF") {
            var portSpr = _getEdgePort(point.contactName);
            if (portSpr == null) return false;
            return (portSpr.x != 0);
        } else {
            var runtimeId = _assembly.idMap.get(point.atomId);
            if (runtimeId == null) runtimeId = point.atomId;
            
            var view = _getNodeView(runtimeId);
            if (view == null) return false;
            
            return view.inputPorts.exists(point.contactName);
        }
    }
    
    /**
     * Draw a Bezier curve wire between two points.
     */
    private function drawWireBezier(g:Graphics, p1:{x:Float, y:Float}, p2:{x:Float, y:Float},
        isFromInput:Bool, isToInput:Bool):Void {
        var dist = Math.abs(p2.x - p1.x);
        var tension = dist * 0.5;
        if (tension < 50) tension = 50;
        
        var c1x = p1.x + (isFromInput ? -tension : tension);
        var c2x = p2.x + (isToInput ? -tension : tension);
        
        g.cubicCurveTo(c1x, p1.y, c2x, p2.y, p2.x, p2.y);
    }
    
    /**
     * Draw a straight wire with horizontal tails.
     */
    private function drawWireStraight(g:Graphics, p1:{x:Float, y:Float}, p2:{x:Float, y:Float},
        isFromInput:Bool, isToInput:Bool):Void {
        var minTail = 20.0;
        var tailDir1:Float = isFromInput ? -1 : 1;
        var tailDir2:Float = isToInput ? -1 : 1;
        
        var a = { x: p1.x + tailDir1 * minTail, y: p1.y };
        var e = { x: p2.x + tailDir2 * minTail, y: p2.y };
        
        g.lineTo(a.x, a.y);
        g.lineTo(e.x, e.y);
        g.lineTo(p2.x, p2.y);
    }
    
    /**
     * Draw ghost Bezier curve for drag preview.
     */
    private function drawGhostBezier(g:Graphics, p1:{x:Float, y:Float}, p2:{x:Float, y:Float}, isInput:Bool):Void {
        var dx = Math.abs(p2.x - p1.x) * 0.5;
        if (dx < 50) dx = 50;
        
        if (isInput) {
            g.cubicCurveTo(p1.x - dx, p1.y, p2.x + dx, p2.y, p2.x, p2.y);
        } else {
            g.cubicCurveTo(p1.x + dx, p1.y, p2.x - dx, p2.y, p2.x, p2.y);
        }
    }
    
    /**
     * Draw ghost straight wire for drag preview.
     */
    private function drawGhostStraight(g:Graphics, p1:{x:Float, y:Float}, p2:{x:Float, y:Float}, isInput:Bool):Void {
        var minTail = 20.0;
        var dir = isInput ? -1 : 1;
        
        var a = { x: p1.x + dir * minTail, y: p1.y };
        g.lineTo(a.x, a.y);
        g.lineTo(p2.x, p2.y);
    }
    
    // ========================================================================
    // INTERNAL: UTILITIES
    // ========================================================================
    /**
     * Generate a unique wire ID from a connection definition.
     * Static method - can be used without an instance.
     */
    public static function getWireIDStatic(link:ConnectionDef):String {
        return '${link.from.atomId}_${link.from.contactName}->${link.to.atomId}_${link.to.contactName}';
    }
    
    /**
     * Find a connection definition by its wire ID.
     */
    public function findLinkById(id:String):ConnectionDef {
        if (_blueprint == null || _blueprint.internalConnections == null) return null;
        
        for (link in _blueprint.internalConnections) {
            if (getWireIDStatic(link) == id) return link;
        }
        return null;
    }
    
    // ========================================================================
    // DISPOSAL v1.2
    // ========================================================================
    /**
     * Clean up all resources and event listeners.
     * v1.2: Also clears the selection callback.
     */
    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;
        
        clearAll();
        
        // FIX: Clear callback
        _onWireSelectionChanged = null;
        
        if (_container != null && _container.parent != null) {
            _container.parent.removeChild(_container);
        }
        if (_ghostWire != null && _ghostWire.parent != null) {
            _ghostWire.parent.removeChild(_ghostWire);
        }
        
        _container = null;
        _ghostWire = null;
        _blueprint = null;
        _assembly = null;
        _canvas = null;
        _getNodeView = null;
        _getEdgePort = null;
        _getSelectedWireIds = null;
    }
}

typedef WireEntry = {
    sprite:Sprite,
    clickHandler:MouseEvent -> Void,
    rightClickHandler:MouseEvent -> Void
}