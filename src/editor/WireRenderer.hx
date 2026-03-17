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
 * WireRenderer v1.2 (Memory Leak Fix)
 * Отвечает за визуализацию всех проводов (связей) в NodeEditor.
 *
 * v1.2 Changes:
 * - Clear selection callback in dispose()
 * - Null checks for all external references
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

    public function setSelectionCallback(callback:Array<String> -> Void):Void {
        _onWireSelectionChanged = callback;
    }

    // ========================================================================
    // ACTIVE WIRES (during drag)
    // ========================================================================

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

    public function addActiveWire(sprite:Sprite):Void {
        if (_isDisposed) return;
        if (_activeWires.indexOf(sprite) == -1) {
            _activeWires.push(sprite);
        }
    }

    public function clearActiveWires():Void {
        _activeWires = [];
    }

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

    public function clearGhostWire():Void {
        if (_ghostWire != null) {
            _ghostWire.graphics.clear();
        }
    }

    // ========================================================================
    // WIRE DELETION
    // ========================================================================

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

    private function handleWireRightClick(wireId:String):Void {
        if (_isDisposed) return;
        
        var selectedIds = _getSelectedWireIds();
        if (selectedIds.indexOf(wireId) == -1) {
            selectedIds = [wireId];
            if (_onWireSelectionChanged != null) {
                _onWireSelectionChanged(selectedIds);
            }
        }
        Impulsys.emit(new Impulse(EventType.WIRE_RIGHT_CLICKED, { ids: selectedIds.copy() }));
    }

    // ========================================================================
    // INTERNAL: WIRE DRAWING
    // ========================================================================

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

    private function getWirePoint(point:ConnectionPoint):{x:Float, y:Float} {
        if (point.atomId == "SELF") {
            var portSpr = _getEdgePort(point.contactName);
            if (portSpr == null) return null;
            var pt = _canvas.globalToLocal(portSpr.localToGlobal(new Point(0, 0)));
            return { x: pt.x, y: pt.y };
        } else {
            var runtimeId = _assembly.idMap.get(point.atomId);
            if (runtimeId == null) runtimeId = point.atomId;

            var view = _getNodeView(runtimeId);
            if (view == null) return null;

            return view.getPortPosition(point.contactName);
        }
    }

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

    private function drawWireBezier(g:Graphics, p1:{x:Float, y:Float}, p2:{x:Float, y:Float},
                                     isFromInput:Bool, isToInput:Bool):Void {
        var dist = Math.abs(p2.x - p1.x);
        var tension = dist * 0.5;
        if (tension < 50) tension = 50;

        var c1x = p1.x + (isFromInput ? -tension : tension);
        var c2x = p2.x + (isToInput ? -tension : tension);

        g.cubicCurveTo(c1x, p1.y, c2x, p2.y, p2.x, p2.y);
    }

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

    private function drawGhostBezier(g:Graphics, p1:{x:Float, y:Float}, p2:{x:Float, y:Float}, isInput:Bool):Void {
        var dx = Math.abs(p2.x - p1.x) * 0.5;
        if (dx < 50) dx = 50;

        if (isInput) {
            g.cubicCurveTo(p1.x - dx, p1.y, p2.x + dx, p2.y, p2.x, p2.y);
        } else {
            g.cubicCurveTo(p1.x + dx, p1.y, p2.x - dx, p2.y, p2.x, p2.y);
        }
    }

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

    public static function getWireIDStatic(link:ConnectionDef):String {
        return '${link.from.atomId}_${link.from.contactName}->${link.to.atomId}_${link.to.contactName}';
    }

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

    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;

        clearAll();
        
        // === FIX: Очистка callback ===
        _onWireSelectionChanged = null;
        // =============================

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
