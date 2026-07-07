package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * DEVICE CARD v1.1 (Fixed Header Button Interaction)
 * Card holding a DeviceView inside a DevicePanel or DeviceWindow.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeviceCard                                                            │
 * │                                                                         │
 * │   ┌──────────────────────────────────┐                                  │
 * │   │  Title Bar  [label]         [x]  │  ← Title + close button          │
 * │   ├──────────────────────────────────┤                                  │
 * │   │                                  │                                  │
 * │   │  DeviceView (full size)          │  ← Interactive widget            │
 * │   │                                  │                                  │
 * │   └──────────────────────────────────┘                                  │
 * │                                                                         │
 * │   Title bar: drag to move card                                          │
 * │   [x] button: close/remove card                                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.1 Changes:
 * - FIXED: Close button MOUSE_DOWN now calls stopPropagation() to prevent
 *   the MOUSE_DOWN event from bubbling up to the title bar and starting
 *   an unwanted card drag.
 */
class DeviceCard extends Sprite {
    // =========================================================================
    // PUBLIC PROPERTIES
    // =========================================================================
    public var atom(default, null):Atom;
    public var cardWidth(default, null):Float = 100;
    public var cardHeight(default, null):Float = 80;
    
    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================
    private var _owner:Dynamic; // DeviceWindow or DevicePanel
    private var _deviceView:DeviceView;
    private var _titleBar:Sprite;
    private var _titleLabel:TextField;
    
    // Drag state
    private var _cardVisibility:Bool = false;
    private var _cardDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;
    private var _isDisposed:Bool = false;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
     * Create a new DeviceCard for the given atom.
     * The card will automatically obtain the widget from DeviceViewRegistry
     * and place it inside itself.
     *
     * @param atom          The atom to display
     * @param owner         Reference to the parent (DeviceWindow or DevicePanel)
     * @param x             Initial X position in the container
     * @param y             Initial Y position in the container
     */
    public function new(atom:Atom, owner:Dynamic, ?x:Float = 0, ?y:Float = 0) {
        super();
        this.atom = atom;
        _owner = owner;
        this.x = x;
        this.y = y;
        buildCard();
    }
    
    // =========================================================================
    // BUILD UI
    // =========================================================================
    private function buildCard():Void {
        // 1. Get the widget from the registry (guaranteed single instance)
        var registry = DeviceViewRegistry.getInstance();
        _deviceView = registry.getOrCreate(atom, true);
        
        if (_deviceView == null) {
            trace('DeviceCard: Could not get widget for atom "${atom.name}"');
            createFallbackCard();
            return;
        }
        
        // 2. Move the widget into the card via the registry
        //    (the widget will be removed from its previous container, if any)
        //    We pass `this` as the container.
        _deviceView = registry.moveToDeviceWindow(atom.id, this, 0, 20);
        
        if (_deviceView == null) {
            trace('DeviceCard: Failed to move widget for atom "${atom.name}"');
            createFallbackCard();
            return;
        }
        
        // 3. Determine card dimensions based on widget size
        var viewWidth = _deviceView.width;
        var viewHeight = _deviceView.height;
        
        if (viewWidth < 50) viewWidth = 100;
        if (viewHeight < 30) viewHeight = 60;
        
        cardWidth = viewWidth + 30;   // left/right padding
        cardHeight = viewHeight + 40; // title 20 + bottom padding
        
        // 4. Title bar
        _titleBar = new Sprite();
        _titleBar.graphics.beginFill(0x3a3a4a);
        _titleBar.graphics.drawRect(0, 0, viewWidth + 20, 20);
        _titleBar.graphics.endFill();
        addChild(_titleBar);
        
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 10, 0xFFFFFF);
		_titleLabel.text = " " + (atom != null ? (atom.displayName != null ? atom.displayName : atom.name) : "Device");
        _titleLabel.width = viewWidth;
        _titleLabel.height = 20;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _titleBar.addChild(_titleLabel);
        
        // Close button
        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0x883333);
        closeBtn.graphics.drawRect(0, 0, 16, 16);
        closeBtn.graphics.endFill();
        closeBtn.x = viewWidth + 2;
        closeBtn.y = 2;
        
        var xText = new TextField();
        xText.text = "x";
        xText.width = 16;
        xText.height = 16;
        xText.selectable = false;
        xText.mouseEnabled = false;
        xText.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF, false, null, null, null, null, "center");
        closeBtn.addChild(xText);
        
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
        
        // === BUG 1 FIX: Stop MOUSE_DOWN from propagating to title bar ===
        // Without this, clicking the close button would also start a card drag
        // because MOUSE_DOWN bubbles from the button to _titleBar.
        closeBtn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        
        _titleBar.addChild(closeBtn);
        
        // 5. Card background (drawn behind everything)
        graphics.clear();
        graphics.beginFill(0x2a2a3a, 0.9);
        graphics.lineStyle(1, 0x4a4a5a);
        graphics.drawRoundRect(-5, -5, cardWidth, cardHeight, 4, 4);
        graphics.endFill();
        
        // 6. Enable dragging by title bar
        _titleBar.buttonMode = true;
        _titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
        
        trace('DeviceCard: Built card for "${atom.name}"');
    }
    
    /**
     * Fallback when no widget is available.
     */
    private function createFallbackCard():Void {
        cardWidth = 80;
        cardHeight = 50;
        
        graphics.beginFill(0x333344);
        graphics.drawRoundRect(0, 0, cardWidth, cardHeight, 4, 4);
        graphics.endFill();
        
        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        txt.text = atom != null ? atom.name : "?";
        txt.width = 80;
        txt.height = 50;
        txt.selectable = false;
        txt.mouseEnabled = false;
        addChild(txt);
    }
    
    // =========================================================================
    // CLOSE HANDLER
    // =========================================================================
    private function onCloseClick(e:MouseEvent):Void {
        e.stopPropagation();
        
        if (_owner != null) {
            // Universal call to owner's removeDevice method
            if (Reflect.hasField(_owner, 'removeDevice')) {
                Reflect.callMethod(_owner, Reflect.field(_owner, 'removeDevice'), [this]);
            }
        }
    }
    
    // =========================================================================
    // DRAG LOGIC
    // =========================================================================
    private function onCardMouseDown(e:MouseEvent):Void {
        if (_isDisposed) return;
        
        _cardDragging = true;
        _dragStartX = this.x;
        _dragStartY = this.y;
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;
        
        // Bring card to front
        if (parent != null) parent.addChild(this);
        
        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
    }
    
    private function onCardMouseMove(e:MouseEvent):Void {
        if (!_cardDragging || _isDisposed) return;
        
        this.x = _dragStartX + (e.stageX - _mouseStartX);
        this.y = _dragStartY + (e.stageY - _mouseStartY);
    }
    
    private function onCardMouseUp(e:MouseEvent):Void {
        _cardDragging = false;
        
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
        
        // Notify position change for auto-save
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }
    
    // =========================================================================
    // DISPOSE
    // =========================================================================
    /**
     * Clean up the card. The widget is returned to the registry (container cleared)
     * but NOT disposed, so it can be reused by NodeView.
     */
    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;
        
        if (_titleBar != null) {
            _titleBar.removeEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
        }
        
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
        
        // Return the widget to the registry (clear container)
        if (_deviceView != null) {
            // Remove widget from card
            if (this.contains(_deviceView)) {
                removeChild(_deviceView);
            }
            
            // Clear container record in registry
            DeviceViewRegistry.getInstance().clearContainer(atom.id);
            
            // Deactivate the widget (it will stop receiving updates, but atom data remains)
            _deviceView.deactivate();
            _deviceView = null;
        }
        
        atom = null;
        _owner = null;
        _titleBar = null;
        _titleLabel = null;
        
        trace('DeviceCard: Disposed');
    }
}