package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;
import library.electro.OscilloscopeAtom;
import ui.widgets.NumberInput;
import ui.widgets.NumberDisplay;
import ui.widgets.IHMIWidget;

/**
 * PROPERTIES WINDOW v2.4 (Oscilloscope Shape Instant Update)
 * Atom properties editor with logic mode switch and oscilloscope shape selector.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   PropertiesWindow                                                      │
 * │                                                                         │
 * │   ┌──────────────────────────────────┐                                  │
 * │   │  Atom: [name]              [x]   │  ← Title + close button          │
 * │   ├──────────────────────────────────┤                                  │
 * │   │                                  │                                  │
 * │   │  Simulation Mode:                │  ← Logic mode switch (Assembly)  │
 * │   │  [Digital (Delayed)]             │                                  │
 * │   │                                  │                                  │
 * │   │  Display Shape:                  │  ← Shape selector (Oscilloscope) │
 * │   │  [Rectangular]                   │                                  │
 * │   │  [Square]                        │                                  │
 * │   │  [Circular]                      │                                  │
 * │   │                                  │                                  │
 * │   │  In: [contact1]  [input]         │  ← NumberInput widgets           │
 * │   │  In: [contact2]  [input]         │                                  │
 * │   │                                  │                                  │
 * │   │  Out: [contact1] [display]       │  ← NumberDisplay widgets         │
 * │   │  Out: [contact2] [display]       │                                  │
 * │   │                                  │                                  │
 * │   └──────────────────────────────────┘                                  │
 * │                                                                         │
 * │   Title bar: drag to move window                                        │
 * │   [x] button: close window                                              │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v2.4 CHANGES (Oscilloscope Shape Instant Update):
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  PROBLEM (v2.3):                                                        │
 * │  When user clicked shape button in PropertiesWindow:                    │
 * │  1. atom.setDisplayShape() was called                                   │
 * │  2. VALUE_COMMITTED event was emitted                                   │
 * │  3. BUT OscilloscopeWidget did NOT update immediately                   │
 * │  4. User had to switch to DevicePanel and back to see the change        │
 * │                                                                         │
 * │  SOLUTION (v2.4):                                                       │
 * │  1. atom.setDisplayShape() now emits OSCILLOSCOPE_SHAPE_CHANGED         │
 * │  2. OscilloscopeWidget subscribes to this event                         │
 * │  3. Widget rebuilds UI instantly (no mode switch needed)                │
 * │  4. VALUE_COMMITTED still emitted for project save                      │
 * │                                                                         │
 * │  Flow:                                                                  │
 * │  ┌──────────────────────────────────────────────────────────────────┐   │
 * │  │  User clicks [Square] button                                     │   │
 * │  │       │                                                          │   │
 * │  │       ▼                                                          │   │
 * │  │  oscAtom.setDisplayShape(SHAPE_SQUARE)                           │   │
 * │  │       │                                                          │   │
 * │  │       ├──► Emits OSCILLOSCOPE_SHAPE_CHANGED                      │   │
 * │  │       │         │                                                │   │
 * │  │       │         ▼                                                │   │
 * │  │       │    OscilloscopeWidget.onShapeChanged()                   │   │
 * │  │       │         │                                                │   │
 * │  │       │         ▼                                                │   │
 * │  │       │    rebuildUI() → instant visual update                   │   │
 * │  │       │                                                          │   │
 * │  │       └──► Emits VALUE_COMMITTED                                 │   │
 * │  │                 │                                                │   │
 * │  │                 ▼                                                │   │
 * │  │            Main.saveCurrentContext()                             │   │
 * │  └──────────────────────────────────────────────────────────────────┘   │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.3 Changes:
 * - FIXED: Close button MOUSE_DOWN now calls stopPropagation() to prevent
 *   it from triggering the header drag.
 *
 * @author ALTAURI Team
 * @version 2.4
 */
class PropertiesWindow extends Sprite
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    /** Background sprite (rounded rect with border) */
    private var _bg:Sprite;
    /** Title text field — shows "Atom: [name]" */
    private var _title:TextField;
    /** Content container — holds all property widgets */
    private var _content:Sprite;
    /** Currently edited target (Atom or Assembly) */
    private var _target:Dynamic;
    /** Array of HMI widgets (NumberInput, NumberDisplay) for cleanup */
    private var _widgets:Array<IHMIWidget>;
    /** Disposal flag to prevent double-dispose */
    private var _isDisposed:Bool = false;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
     * Create PropertiesWindow instance.
     * 
     * Builds static UI elements (background, title, close button).
     * Dynamic content is created in show() method.
     */
    public function new()
    {
        super();
        _widgets = new Array();
        
        // Background
        _bg = new Sprite();
        addChild(_bg);
        _drawBg(300, 200);
        
        // Title
        _title = new TextField();
        _title.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _title.width = 280;
        _title.height = 20;
        _title.x = 10;
        _title.y = 5;
        _title.selectable = false;
        _title.mouseEnabled = false;
        addChild(_title);
        
        // Content container
        _content = new Sprite();
        _content.y = 30;
        _content.x = 10;
        addChild(_content);
        
        // Close button (top-right)
        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0xAA0000);
        closeBtn.graphics.drawRect(0, 0, 15, 15);
        closeBtn.x = 280;
        closeBtn.y = 5;
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, function(_) _close());
        
        // === v2.3 FIX: Stop MOUSE_DOWN from propagating to title ===
        // Without this, clicking close would also start a drag on the header.
        closeBtn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        addChild(closeBtn);
        
        // Header drag
        _title.addEventListener(MouseEvent.MOUSE_DOWN, _onMouseDownHeader);
        if (stage != null)
        {
            stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
        }
        else
        {
            addEventListener(Event.ADDED_TO_STAGE, _onAddedToStage);
        }
    }
    
    /**
     * Deferred stage listener setup.
     * Called when window is added to stage (if stage was null in constructor).
     */
    private function _onAddedToStage(e:Event):Void
    {
        removeEventListener(Event.ADDED_TO_STAGE, _onAddedToStage);
        if (stage != null) stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
    }
    
    /**
     * Start dragging window by title bar.
     */
    private function _onMouseDownHeader(e:MouseEvent):Void
    {
        startDrag();
    }
    
    /**
     * Stop dragging window.
     */
    private function _onMouseUpStage(e:MouseEvent):Void
    {
        stopDrag();
    }
    
    // =========================================================================
    // PUBLIC API
    // =========================================================================
    /**
     * Show properties window for given target.
     * 
     * Positions window at (x, y) and populates content based on target type:
     * - Atom: shows inputs, outputs, logic mode, oscilloscope shape
     * - Other: shows "Unknown object" message
     * 
     * @param target Atom or Assembly to edit
     * @param x      Window X position
     * @param y      Window Y position
     */
    public function show(target:Dynamic, x:Float, y:Float):Void
    {
        if (_isDisposed) return;
        _target = target;
        this.x = x;
        this.y = y;
        _clearContent();
        
        if (Std.isOfType(target, Atom))
        {
            _populateAtom(cast target);
        }
        else
        {
            _title.text = "Properties";
            var tf = new TextField();
            tf.text = "Unknown object";
            tf.width = 250;
            _content.addChild(tf);
        }
        
        visible = true;
    }
    
    /**
     * Clear all dynamic content widgets.
     * 
     * Disposes all HMI widgets (NumberInput, NumberDisplay) and removes
     * all children from _content container.
     */
    private function _clearContent():Void
    {
        for (w in _widgets)
        {
            if (w != null)
            {
                try
                {
                    w.dispose();
                }
                catch (e:Dynamic)
                {
                    trace('WARN: Error disposing widget: $e');
                }
            }
        }
        _widgets = [];
        while (_content.numChildren > 0)
        {
            _content.removeChildAt(0);
        }
    }
    
    /**
     * Close properties window (public API).
     */
    public function close():Void
    {
        _close();
    }
    
    /**
     * Close properties window (internal).
     * 
     * Hides window, stops drag, clears content.
     */
    private function _close():Void
    {
        if (_isDisposed) return;
        visible = false;
        stopDrag();
        _clearContent();
    }
    
    // =========================================================================
    // ATOM POPULATION
    // =========================================================================
    /**
     * Populate window with atom properties.
     * 
     * v2.4: For OscilloscopeAtom, shows Display Shape selector with
     * instant update via OSCILLOSCOPE_SHAPE_CHANGED event.
     * 
     * Layout:
     * ┌─────────────────────────────────────────────────────────────────┐
     * │  1. Logic Mode Switch (if Assembly)                             │
     * │     [Digital (Delayed)] / [Analog (Immediate)]                  │
     * │                                                                 │
     * │  2. Display Shape (if OscilloscopeAtom)                         │
     * │     [Rectangular] [Square] [Circular]                           │
     * │     ↓                                                           │
     * │     Emits OSCILLOSCOPE_SHAPE_CHANGED → instant widget update    │
     * │                                                                 │
     * │  3. Input Contacts                                              │
     * │     In: [name] [NumberInput widget]                             │
     * │                                                                 │
     * │  4. Output Contacts                                             │
     * │     Out: [name] [NumberDisplay widget]                          │
     * └─────────────────────────────────────────────────────────────────┘
     * 
     * @param atom Atom to display properties for
     */
    private function _populateAtom(atom:Atom):Void
    {
        if (_isDisposed || atom == null) return;
        
        _title.text = "Atom: " + atom.name;
        var yPos = 0;
        
        // =================================================================
        // SECTION 1: Logic Mode Switch (Assembly only)
        // =================================================================
        var isLogicTarget = Std.isOfType(atom, Assembly);
        if (isLogicTarget)
        {
            var modeLabel = new TextField();
            modeLabel.text = "Simulation Mode:";
            modeLabel.width = 250;
            modeLabel.height = 20;
            modeLabel.selectable = false;
            modeLabel.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
            modeLabel.y = yPos;
            _content.addChild(modeLabel);
            yPos += 22;
            
            var modeText = atom.isLogic ? "Digital (Delayed)" : "Analog (Immediate)";
            var modeBtn = new Sprite();
            modeBtn.graphics.beginFill(atom.isLogic ? 0x2A5A3A : 0x3A5A4A);
            modeBtn.graphics.drawRoundRect(0, 0, 250, 25, 4, 4);
            modeBtn.graphics.endFill();
            modeBtn.y = yPos;
            modeBtn.buttonMode = true;
            
            var tf = new TextField();
            tf.text = modeText;
            tf.width = 250;
            tf.height = 25;
            tf.selectable = false;
            tf.mouseEnabled = false;
            tf.defaultTextFormat = new TextFormat("_sans", 12, 0xFFFFFF, false, null, null, null, null, "center");
            modeBtn.addChild(tf);
            
            modeBtn.addEventListener(MouseEvent.CLICK, function(e)
            {
                atom.isLogic = !atom.isLogic;
                _populateAtom(atom);
                Impulsys.quickEmit(EventType.VALUE_COMMITTED);
            });
            
            _content.addChild(modeBtn);
            yPos += 35;
        }
        
        // =================================================================
        // SECTION 2: Display Shape (OscilloscopeAtom only)
        // =================================================================
        // v2.4: Instant update via OSCILLOSCOPE_SHAPE_CHANGED event
        if (Std.isOfType(atom, OscilloscopeAtom))
        {
            var oscAtom:OscilloscopeAtom = cast atom;
            
            var shapeLabel = new TextField();
            shapeLabel.text = "Display Shape:";
            shapeLabel.width = 250;
            shapeLabel.height = 20;
            shapeLabel.selectable = false;
            shapeLabel.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
            shapeLabel.y = yPos;
            _content.addChild(shapeLabel);
            yPos += 22;
            
            // Three shape options
            var shapes = [
                { label: "Rectangular", value: OscilloscopeAtom.SHAPE_RECTANGULAR },
                { label: "Square", value: OscilloscopeAtom.SHAPE_SQUARE },
                { label: "Circular", value: OscilloscopeAtom.SHAPE_CIRCULAR }
            ];
            
            for (shape in shapes)
            {
                var isSelected = (oscAtom.getDisplayShape() == shape.value);
                var btn = new Sprite();
                btn.graphics.beginFill(isSelected ? 0x2A5A3A : 0x3A3A4A);
                btn.graphics.drawRoundRect(0, 0, 250, 25, 4, 4);
                btn.graphics.endFill();
                btn.y = yPos;
                btn.buttonMode = true;
                
                var btf = new TextField();
                btf.text = shape.label;
                btf.width = 250;
                btf.height = 25;
                btf.selectable = false;
                btf.mouseEnabled = false;
                btf.defaultTextFormat = new TextFormat("_sans", 12, isSelected ? 0x00FF88 : 0xFFFFFF, false, null, null, null, null, "center");
                btn.addChild(btf);
                
                // === v2.4: Capture shape value for closure ===
                final capturedValue = shape.value;
                
                btn.addEventListener(MouseEvent.CLICK, function(e)
                {
                    // 1. Update atom's shape
                    oscAtom.setDisplayShape(capturedValue);
                    
                    // 2. Refresh PropertiesWindow UI (highlight selected button)
                    _populateAtom(atom);
                    
                    // 3. Emit VALUE_COMMITTED for project save
                    Impulsys.quickEmit(EventType.VALUE_COMMITTED);
                    
                    // NOTE: OscilloscopeWidget updates automatically via
                    // OSCILLOSCOPE_SHAPE_CHANGED event emitted by atom.setDisplayShape()
                });
                
                _content.addChild(btn);
                yPos += 30;
            }
            yPos += 10; // Extra spacing after shape selector
			
		    // === Секция: Frame Rate Control ===
			var frLabel = new TextField();
			frLabel.text = "Frame Rate (FPS):";
			frLabel.width = 250;
			frLabel.height = 20;
			frLabel.selectable = false;
			frLabel.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
			frLabel.y = yPos;
			_content.addChild(frLabel);
			yPos += 22;
			
			var frInput = new NumberInput(oscAtom.getInput("frameRate"), "FPS");
			frInput.y = yPos;
			_content.addChild(frInput);
			_widgets.push(frInput);
			yPos += 40;
			
			// === Секция: Decimation ===
			var decLabel = new TextField();
			decLabel.text = "Sample Decimation:";
			decLabel.width = 250;
			decLabel.height = 20;
			decLabel.selectable = false;
			decLabel.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
			decLabel.y = yPos;
			_content.addChild(decLabel);
			yPos += 22;
			
			var decInput = new NumberInput(oscAtom.getInput("decimation"), "Decimation");
			decInput.y = yPos;
			_content.addChild(decInput);
			_widgets.push(decInput);
			yPos += 40;
        }
        
        // =================================================================
        // SECTION 3: Input Contacts
        // =================================================================
        if (atom.getInputs() != null)
        {
            for (c in atom.getInputs())
            {
                if (c == null || c.isDisposed) continue;
                try
                {
                    var input = new NumberInput(c, "In: " + c.name);
                    input.y = yPos;
                    _content.addChild(input);
                    _widgets.push(input);
                    yPos += 40;
                }
                catch (e:Dynamic)
                {
                    trace('ERROR: Failed to create NumberInput: $e');
                }
            }
        }
        
        // =================================================================
        // SECTION 4: Output Contacts
        // =================================================================
        if (atom.getOutputs() != null)
        {
            for (c in atom.getOutputs())
            {
                if (c == null || c.isDisposed) continue;
                try
                {
                    var output = new NumberDisplay(c, "Out: " + c.name);
                    output.y = yPos;
                    _content.addChild(output);
                    _widgets.push(output);
                    yPos += 40;
                }
                catch (e:Dynamic)
                {
                    trace('ERROR: Failed to create NumberDisplay: $e');
                }
            }
        }
        
        // Resize background to fit content
        _drawBg(300, yPos + 50);
    }
    
    /**
     * Draw background rectangle.
     * 
     * @param w Width
     * @param h Height
     */
    private function _drawBg(w:Float, h:Float):Void
    {
        if (_isDisposed) return;
        _bg.graphics.clear();
        _bg.graphics.beginFill(0x222233, 0.95);
        _bg.graphics.lineStyle(1, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        _bg.graphics.endFill();
    }
    
    // =========================================================================
    // DISPOSE
    // =========================================================================
    /**
     * Clean up all resources.
     * 
     * Removes event listeners, disposes widgets, removes from display list.
     */
    public function dispose():Void
    {
        if (_isDisposed) return;
        _isDisposed = true;
        _clearContent();
        _widgets = null;
        
        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
        }
        
        if (_bg != null && _bg.parent != null)
        {
            _bg.parent.removeChild(_bg);
            _bg = null;
        }
        if (_content != null && _content.parent != null)
        {
            _content.parent.removeChild(_content);
            _content = null;
        }
        if (_title != null && _title.parent != null)
        {
            _title.parent.removeChild(_title);
            _title = null;
        }
    }
}