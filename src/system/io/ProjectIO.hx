package system.io;

import haxe.Json;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.events.SecurityErrorEvent;
import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionDef;
import core.types.ContactType;
import Lambda;

/**
 * PROJECT I/O v2.0 (Fixed)
 * Safe file operations with proper listener cleanup.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ProjectIO (Static)                                                    │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Save Operations:                                               │   │
 * │   │  - save(blueprint, nodes, viewState)                            │   │
 * │   │    → Serialize to JSON                                          │   │
 * │   │    → Update atom coordinates from NodeView positions            │   │
 * │   │    → FileReference.save() with ".atom" extension                │   │
 * │   │                                                                 │   │
 * │   │  Load Operations:                                               │   │
 * │   │  - load(onComplete)                                             │   │
 * │   │    → FileReference.browse()                                     │   │
 * │   │    → Parse JSON                                                 │   │
 * │   │    → Convert String types to ContactType                        │   │
 * │   │    → Build Blueprint instance                                   │   │
 * │   │    → Call onComplete callback                                   │   │
 * │   │                                                                 │   │
 * │   │  Safety Features:                                               │   │
 * │   │  - _isLoading flag prevents duplicate load calls                │   │
 * │   │  - Named handlers allow proper cleanup                          │   │
 * │   │  - cleanupFileRef() removes all listeners                       │   │
 * │   │  - _safeParseFloat() handles invalid numeric values             │   │
 * │   │  - _parseContactType() handles String and Int formats           │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   File Format (.atom):                                                  │
 * │   ──────────────────                                                    │
 * │   {                                                                     │
 * │     "version": "1.1",                                                   │
 * │     "blueprint": {                                                      │
 * │       "id": "...",                                                      │
 * │       "name": "...",                                                    │
 * │       "category": "...",                                                │
 * │       "pins": [...],                                                    │
 * │       "internalAtoms": [...],                                           │
 * │       "internalConnections": [...]                                      │
 * │     },                                                                  │
 * │     "editor": { "x": 0, "y": 0, "zoom": 1.0 }                           │
 * │   }                                                                     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ProjectIO {
    private static var _currentFileRef:FileReference;
    private static var _onLoadComplete:{blueprint:Blueprint, viewState:{x:Float, y:Float, zoom:Float}} -> Void;
    public static var logger:String -> Void;
    
    // FIX: Flag to prevent race condition on duplicate load calls
    private static var _isLoading:Bool = false;
    
    // ========================================================================
    
    /**
     * Save blueprint to file.
     * Updates atom coordinates from NodeView positions before serialization.
     *
     * @param blueprint  Blueprint to save
     * @param nodes      Array of node positions {id, x, y}
     * @param viewState  Editor viewport state {x, y, zoom}
     */
    public static function save(blueprint:Blueprint, nodes:Array<{id:String, x:Float, y:Float}>, viewState:{x:Float, y:Float, zoom:Float}):Void {
        // 1. Update coordinates from NodeView positions
        for (atomDef in blueprint.internalAtoms) {
            var nodeData = Lambda.find(nodes, function(n) return n.id == atomDef.instanceId);
            if (nodeData != null) {
                atomDef.x = nodeData.x;
                atomDef.y = nodeData.y;
            }
        }
        
        // 2. Serialize pins
        var pinsToSave = [];
        for (p in blueprint.pins) {
            pinsToSave.push({
                name: p.name,
                type: Std.string(p.type),
                defaultValue: p.defaultValue,
                dataType: p.dataType
            });
        }
        
        var dataToSave:Dynamic = {
            version: "1.1",
            blueprint: {
                id: blueprint.id,
                name: blueprint.name,
                category: blueprint.category,
                pins: pinsToSave,
                internalAtoms: blueprint.internalAtoms,
                internalConnections: blueprint.internalConnections
            },
            editor: {
                x: viewState.x,
                y: viewState.y,
                zoom: viewState.zoom
            }
        };
        
        var json:String = Json.stringify(dataToSave, null, "  ");
        
        var fileRef = new FileReference();
        fileRef.save(json, blueprint.name + ".atom");
    }
    
    /**
     * Load blueprint from file.
     * Opens file browser and parses selected .atom file.
     *
     * @param onComplete Callback receiving {blueprint, viewState}
     */
    public static function load(onComplete:{blueprint:Blueprint, viewState:{x:Float, y:Float, zoom:Float}} -> Void):Void {
        if (logger == null) logger = function(s) trace(s);
        
        // FIX: Check for duplicate load calls
        if (_isLoading) {
            logger("IO: WARNING - Load already in progress, ignoring duplicate call");
            return;
        }
        _isLoading = true;
        
        // FIX: Cleanup previous FileReference
        cleanupFileRef();
        
        logger("IO: Creating FileRef...");
        _onLoadComplete = onComplete;
        _currentFileRef = new FileReference();
        
        // FIX: Named handlers for proper cleanup
        _currentFileRef.addEventListener(Event.SELECT, onSelect);
        _currentFileRef.addEventListener(Event.COMPLETE, onCompleteLoad);
        _currentFileRef.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
        _currentFileRef.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
        _currentFileRef.addEventListener(Event.CANCEL, onCancel);
        
        logger("IO: Opening browse()...");
        try {
            _currentFileRef.browse();
            logger("IO: browse() called successfully");
        } catch (e:Dynamic) {
            logger("IO: CRASH in browse() - " + Std.string(e));
            _isLoading = false;
            cleanupFileRef();
        }
    }
    
    // ========================================================================
    // NAMED HANDLERS (for proper cleanup)
    // ========================================================================
    
    /**
     * File selected handler.
     * Triggers file loading.
     */
    private static function onSelect(e:Event):Void {
        if (logger != null) logger("IO: File SELECTED - " + _currentFileRef.name);
        _currentFileRef.load();
    }
    
    /**
     * File load complete handler.
     * Parses JSON and builds Blueprint.
     */
    /**
     * File load complete handler.
     * Parses JSON and builds Blueprint.
     */
    private static function onCompleteLoad(e:Event):Void {
        if (logger != null) logger("IO: File COMPLETE! Parsing...");
        
        try {
            var data:String = _currentFileRef.data.toString();
            var json:Dynamic = Json.parse(data);
            var rawBp:Dynamic = json.blueprint;
            
            // Делегируем парсинг графа нашему новому единому методу
            var bp = parseBlueprint(rawBp);
            
            // FIX: Safe editor state parsing
            var viewState:{x:Float, y:Float, zoom:Float} = {x: 0.0, y: 0.0, zoom: 1.0};
            if (json.editor != null) {
                viewState.x = _safeParseFloat(json.editor.x, 0.0);
                viewState.y = _safeParseFloat(json.editor.y, 0.0);
                viewState.zoom = _safeParseFloat(json.editor.zoom, 1.0);
            }
            
            if (logger != null) logger("IO: Blueprint built OK: " + bp.name);
            
            // Cleanup before callback
            _isLoading = false;
            cleanupFileRef();
            
            // Call callback
            if (_onLoadComplete != null) {
                _onLoadComplete({blueprint: bp, viewState: viewState});
            }
            _onLoadComplete = null;
            
        } catch (err:Dynamic) {
            if (logger != null) logger("IO: PARSE ERROR! " + Std.string(err));
            _isLoading = false;
            cleanupFileRef();
            _onLoadComplete = null;
        }
    }
    
    /**
     * IO error handler.
     */
    private static function onIOError(e:IOErrorEvent):Void {
        if (logger != null) logger("IO: IO_ERROR! " + e.text);
        _isLoading = false;
        cleanupFileRef();
        _onLoadComplete = null;
    }
    
    /**
     * Security error handler.
     */
    private static function onSecurityError(e:SecurityErrorEvent):Void {
        if (logger != null) logger("IO: SECURITY_ERROR! " + e.text);
        _isLoading = false;
        cleanupFileRef();
        _onLoadComplete = null;
    }
    
    /**
     * Cancel handler (user closed file browser).
     */
    private static function onCancel(e:Event):Void {
        if (logger != null) logger("IO: Dialog CANCELLED");
        _isLoading = false;
        cleanupFileRef();
        _onLoadComplete = null;
    }
    
    // ========================================================================
    // CLEANUP
    // ========================================================================
    
    /**
     * Cleanup FileReference and remove all listeners.
     * Prevents memory leaks and duplicate event handling.
     */
    private static function cleanupFileRef():Void {
        if (_currentFileRef != null) {
            _currentFileRef.removeEventListener(Event.SELECT, onSelect);
            _currentFileRef.removeEventListener(Event.COMPLETE, onCompleteLoad);
            _currentFileRef.removeEventListener(IOErrorEvent.IO_ERROR, onIOError);
            _currentFileRef.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
            _currentFileRef.removeEventListener(Event.CANCEL, onCancel);
            _currentFileRef = null;
        }
    }
    
    // ========================================================================
    // SAFE PARSING
    // ========================================================================
    
	/**
     * Parses raw JSON Dynamic object into a Blueprint instance.
     * Public so Main.hx can use it for HTML5 AJAX loads.
     */
    public static function parseBlueprint(rawBp:Dynamic):Blueprint {
        // --- 1. PINS ---
        var pins:Array<PinDef> = [];
        if (rawBp.pins != null) {
            for (p in cast(rawBp.pins, Array<Dynamic>)) {
                pins.push({
                    name: Std.string(p.name),
                    type: _parseContactType(p.type),
                    defaultValue: p.defaultValue,
                    dataType: Std.string(p.dataType)
                });
            }
        }
        
        // --- 2. ATOMS ---
        var atoms:Array<AtomDef> = [];
        if (rawBp.internalAtoms != null) {
            for (a in cast(rawBp.internalAtoms, Array<Dynamic>)) {
                var posX:Float = 0.0;
                var posY:Float = 0.0;
                
                if (a.x != null) {
                    var vx = Std.parseFloat(Std.string(a.x));
                    if (!Math.isNaN(vx)) posX = vx;
                }
                if (a.y != null) {
                    var vy = Std.parseFloat(Std.string(a.y));
                    if (!Math.isNaN(vy)) posY = vy;
                }
                
                atoms.push({
                    instanceId: Std.string(a.instanceId),
                    typeId: Std.string(a.typeId),
                    x: posX,
                    y: posY
                });
            }
        }
        
        // --- 3. CONNECTIONS ---
        var conns:Array<ConnectionDef> = [];
        if (rawBp.internalConnections != null) {
            for (c in cast(rawBp.internalConnections, Array<Dynamic>)) {
                conns.push({
                    from: {
                        atomId: Std.string(c.from.atomId),
                        contactName: Std.string(c.from.contactName)
                    },
                    to: {
                        atomId: Std.string(c.to.atomId),
                        contactName: Std.string(c.to.contactName)
                    }
                });
            }
        }
        
        return new Blueprint(
            Std.string(rawBp.id),
            Std.string(rawBp.name),
            pins,
            null,
            atoms,
            conns,
            Std.string(rawBp.category)
        );
    }

    /**
     * Safe float parsing with default value.
     * Handles null, NaN, and invalid strings.
     *
     * @param value        Value to parse
     * @param defaultValue Default if parsing fails
     * @return Parsed float or default
     */
    private static function _safeParseFloat(value:Dynamic, defaultValue:Float):Float {
        if (value == null) return defaultValue;
        var result = Std.parseFloat(Std.string(value));
        if (Math.isNaN(result)) return defaultValue;
        return result;
    }
    
    /**
     * Parse ContactType from dynamic value.
     * Handles both String ("INPUT") and Int (0) formats.
     *
     * @param val Dynamic value from JSON
     * @return Parsed ContactType
     */
    private static function _parseContactType(val:Dynamic):ContactType {
        if (Std.isOfType(val, ContactType)) return val;
        
        if (Std.isOfType(val, String)) {
            switch(Std.string(val)) {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        // FIX: Handle numeric indices
        if (Std.isOfType(val, Int) || Std.isOfType(val, Float)) {
            switch(Std.int(val)) {
                case 0: return INPUT;
                case 1: return OUTPUT;
                case 2: return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        return UNDEFINED;
    }
}