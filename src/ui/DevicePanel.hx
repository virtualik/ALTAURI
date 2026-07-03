package ui;

import editor.EditorTheme;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;

/**
 * DEVICE PANEL v3.3 (Fixed Header Button Interaction)
 * Full-size device display panel inside the Main Window.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * DevicePanel — built-in device dashboard inside the main window.
 * An alternative to the separate DeviceWindow.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SCHEMATIC                         DEVICE PANEL                        │
 * │                                                                         │
 * │   [Hidden]                          ┌────────────────────────────┐      │
 * │                                     │       DevicePanel          │      │
 * │                                     │   ┌────────────────────┐   │      │
 * │                                     │   │   DeviceCard       │   │      │
 * │                                     │   │ ┌────────────────┐ │   │      │
 * │                                     │   │ │   DeviceView   │ │   │      │
 * │                                     │   │ └────────────────┘ │   │      │
 * │                                     │   └────────────────────┘   │      │
 * │                                     │                            │      │
 * │                                     │   [E]  [C]  (Header)       │      │
 * │                                     └────────────────────────────┘      │
 * │                                              │                          │
 * │                                              │                          │
 * │                                              ▼                          │
 * │                               Main Window Color - DEVICE_CANVAS_BG_COLOR│
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v3.3 Changes:
 * - FIXED: Header buttons [E], [C] now stop MOUSE_DOWN propagation to prevent
 *   them from interfering with any parent mouse handlers.
 */
class DevicePanel extends Sprite
{
    // =========================================================================
    // CALLBACKS
    // =========================================================================
    /**
     * Callback to request switching back to Editor Mode.
     * Called when [E] button is pressed.
     */
    public var onShowEditor:Void -> Void;
    
    /**
     * Callback to get the list of available devices.
     * Used to populate the context menu.
     */
    public var onGetAssemblyList:Void -> Array<{id:String, name:String, atom:Atom}>;
    
    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================
    private var _assembly:Assembly;
    private var _deviceCards:Array<DeviceCard>;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _contextMenu:Sprite;
    private var _menuVisible:Bool = false;
    private var _bg:Sprite;
    private var _theme:EditorTheme;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new()
    {
        super();
        _deviceCards = new Array();
        _theme = EditorTheme.getInstance();
        addEventListener(Event.ADDED_TO_STAGE, onAdded);
    }
    
    private function onAdded(e:Event):Void
    {
        removeEventListener(Event.ADDED_TO_STAGE, onAdded);
        setupUI();
    }
    
    // =========================================================================
    // PUBLIC API
    // =========================================================================
    /**
     * Resize the panel to fit the stage.
     */
    public function setSize(w:Float, h:Float):Void
    {
        drawBackground(w, h);
        
        // Resize header
        if (_header != null)
        {
            _header.graphics.clear();
            _header.graphics.beginFill(0x2a2a34);
            _header.graphics.drawRect(0, 0, w, 30);
            _header.graphics.endFill();
            
            // Shift buttons to the right
            var btnX = w - 10;
            for (i in 0..._header.numChildren)
            {
                var child = _header.getChildAt(_header.numChildren - 1 - i);
                if (Std.isOfType(child, Sprite) && child != _titleLabel)
                {
                    child.x = btnX - child.width;
                    btnX = child.x - 10;
                }
            }
        }
    }
    
    /**
     * Set the current assembly context.
     * Updates the title.
     */
    public function setContext(assembly:Assembly):Void
    {
        _assembly = assembly;
        _titleLabel.text = "  Device Panel: " + assembly.blueprint.name;
    }
    
    /**
     * Add a device (atom) to the panel.
     * v3.2: Emits DEVICE_WINDOW_CHANGED to save state.
     */
    public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null):Void
    {
        if (atom == null) return;
        
        // Avoid duplicates
        for (card in _deviceCards)
        {
            if (card.atom == atom) return;
        }
        
        var card = new DeviceCard(atom, this);
        _deviceCards.push(card);
        addChild(card);
        
        if (x != null && y != null)
        {
            card.x = x;
            card.y = y;
        }
        else {
            var pos = findFreePosition(card);
            card.x = pos.x;
            card.y = pos.y;
        }
        
        // v3.2: Emit save signal when adding a new device
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }
    
    /**
     * Remove a device card from the panel.
     */
    public function removeDevice(card:DeviceCard):Void
    {
        if (_deviceCards.remove(card))
        {
            if (this.contains(card)) removeChild(card);
            card.dispose();
            Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
        }
    }
    
    /**
     * Remove all devices.
     *
     * v3.1 NOTE: Does NOT emit DEVICE_WINDOW_CHANGED.
     * If called during mode switch (after syncing cache), emitting here
     * would cause the cache to be wiped immediately.
     * Emission is handled manually in the [C] button callback for explicit clears.
     */
    public function clearDevices():Void
    {
        while (_deviceCards.length > 0)
        {
            var card = _deviceCards.pop();
            if (this.contains(card)) removeChild(card);
            card.dispose();
        }
        
        // Do NOT emit event here to prevent cache wipe during mode switch
    }
    
    /**
     * Returns the list of current device cards.
     * Used by Main.hx to sync state to cache.
     */
    public function getDeviceCards():Array<DeviceCard>
    {
        return _deviceCards;
    }
    
    // =========================================================================
    // SETUP UI
    // =========================================================================
    private function setupUI():Void
    {
        drawBackground(800, 600);
        createHeader();
        
        // Listeners
        stage.addEventListener(MouseEvent.CLICK, onStageClick);
        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, onAtomDeleted);
    }
    
    private function drawBackground(w:Float, h:Float):Void
    {
        graphics.clear();
        // Alpha = 0 makes the background transparent!
        graphics.beginFill(_theme.DEVICE_CANVAS_BG_COLOR, 1.0);
        graphics.drawRect(0, 0, w, h);
        graphics.endFill();
    }
    
    private function createHeader():Void
    {
        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, 800, 30);
        _header.graphics.endFill();
        addChild(_header);
        
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _titleLabel.text = "  Device Panel";
        _titleLabel.width = 300;
        _titleLabel.height = 30;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);
        
        // Button [E] - Editor Mode
        var editorBtn = createHeaderButton("E", 0x005500, function(_)
        {
            if (onShowEditor != null) onShowEditor();
        });
        editorBtn.x = 760;
        _header.addChild(editorBtn);
        
        // Button [C] - Clear
        // v3.1: Explicitly emit event after clearing so the empty state is saved.
        var clearBtn = createHeaderButton("C", 0x555500, function(_)
        {
            clearDevices();
            Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
        });
        clearBtn.x = 720;
        _header.addChild(clearBtn);
    }
    
    /**
     * BUG 1 FIX: Header buttons now stop MOUSE_DOWN propagation.
     * This prevents the MOUSE_DOWN event from bubbling up from the button
     * to any parent container that might start an unwanted drag.
     */
    private function createHeaderButton(label:String, color:Int, onClick:MouseEvent->Void):Sprite
    {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRect(0, 0, 28, 26);
        btn.graphics.endFill();
        
        var txt = new TextField();
        txt.text = label;
        txt.width = 28;
        txt.height = 26;
        txt.selectable = false;
        txt.mouseEnabled = false;
        txt.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, "center");
        btn.addChild(txt);
        
        btn.buttonMode = true;
        btn.addEventListener(MouseEvent.CLICK, onClick);
        
        // === BUG 1 FIX: Stop MOUSE_DOWN from propagating ===
        btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        
        return btn;
    }
    
    // =========================================================================
    // CONTEXT MENU
    // =========================================================================
    private function onRightClick(e:MouseEvent):Void
    {
        if (_menuVisible) hideContextMenu();
        else showContextMenu(e.stageX, e.stageY);
    }
    
    private function showContextMenu(x:Float, y:Float):Void
    {
        hideContextMenu(); // Clean previous
        
        _contextMenu = new Sprite();
        var yPos = 5;
        
        var headerItem = createMenuItem("Add Device:", null, true);
        headerItem.y = yPos;
        _contextMenu.addChild(headerItem);
        yPos += 28;
        
        // Get list from Main
        var devices = (onGetAssemblyList != null) ? onGetAssemblyList() : [];
        devices = [for (d in devices) if (d.id != "selfrun") d];
        
        if (devices.length == 0)
        {
            var emptyItem = createMenuItem("(No devices)", null, true);
            emptyItem.y = yPos;
            _contextMenu.addChild(emptyItem);
            yPos += 26;
        }
        else {
            for (item in devices)
            {
                var menuItem = createMenuItem(item.name, item.atom, false);
                menuItem.y = yPos;
                _contextMenu.addChild(menuItem);
                yPos += 26;
            }
        }
        
        // Draw background
        _contextMenu.graphics.beginFill(0x333344, 0.98);
        _contextMenu.graphics.lineStyle(1, 0x555566);
        _contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 10, 6, 6);
        _contextMenu.graphics.endFill();
        
        _contextMenu.x = Math.min(x, stage.stageWidth - 200);
        _contextMenu.y = Math.min(Math.max(y - 30, 0), stage.stageHeight - yPos - 20);
        
        addChild(_contextMenu);
        _menuVisible = true;
    }
    
    private function hideContextMenu():Void
    {
        if (_contextMenu != null && _contextMenu.parent != null)
        {
            removeChild(_contextMenu);
        }
        _contextMenu = null;
        _menuVisible = false;
    }
    
    private function onStageClick(e:MouseEvent):Void
    {
        if (_menuVisible && _contextMenu != null)
        {
            if (!_contextMenu.hitTestPoint(e.stageX, e.stageY))
            {
                hideContextMenu();
            }
        }
    }
    
    private function createMenuItem(label:String, atom:Atom, disabled:Bool):Sprite
    {
        var item = new Sprite();
        item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
        item.graphics.drawRect(0, 0, 180, 24);
        item.graphics.endFill();
        
        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
        txt.text = (disabled || atom == null) ? label : "+ " + label;
        txt.width = 170;
        txt.height = 24;
        txt.x = 8;
        txt.selectable = false;
        txt.mouseEnabled = false;
        item.addChild(txt);
        
        if (!disabled && atom != null)
        {
            item.buttonMode = true;
            final capturedAtom = atom;
            
            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent)
            {
                addDevice(capturedAtom);
                hideContextMenu();
                // Save state when adding via context menu
                // Note: addDevice() already emits DEVICE_WINDOW_CHANGED in v3.2
            });
            
            item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent)
            {
                item.graphics.clear();
                item.graphics.beginFill(0x556677);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
            
            item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent)
            {
                item.graphics.clear();
                item.graphics.beginFill(0x444455);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
        }
        
        return item;
    }
    
    // =========================================================================
    // EVENTS & HELPERS
    // =========================================================================
    private function onAtomDeleted(impulse:Impulse):Void
    {
        if (impulse.data == null) return;
        
        var deletedId:String = impulse.data.id;
        var toRemove:Array<DeviceCard> = [];
        
        for (card in _deviceCards)
        {
            if (card.atom != null && card.atom.id == deletedId)
            {
                toRemove.push(card);
            }
        }
        
        for (card in toRemove)
        {
            removeDevice(card);
        }
    }
    
    private function findFreePosition(card:DeviceCard):{x:Float, y:Float}
    {
        var startX = 10;
        var startY = 50; // Below header
        var stepX = 120;
        var stepY = 100;
        
        for (y in 0...10)
        {
            for (x in 0...5)
            {
                var px = startX + x * stepX;
                var py = startY + y * stepY;
                if (isPositionFree(px, py)) return {x: px, y: py};
            }
        }
        
        return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
    }
    
    private function isPositionFree(x:Float, y:Float):Bool
    {
        for (card in _deviceCards)
        {
            if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) return false;
        }
        return true;
    }
    
    public function dispose():Void
    {
        clearDevices();
        stage.removeEventListener(MouseEvent.CLICK, onStageClick);
        stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        Impulsys.removeImpulse(EventType.ATOM_DELETED, onAtomDeleted);
    }
}