package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     NET RADIO PLAYER WIDGET v1.0                          ║
 * ║                     (Minimal Placeholder)                                 ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Minimal widget for NETRadioPlayerAtom.                                   ║
 * ║  Shows a simple rectangle with error indication.                          ║
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                                                                     │  ║
 * ║  │                    ◉ NET Radio                                      │  ║
 * ║  │                                                                     │  ║
 * ║  │   (Empty rectangle, border changes on error)                        │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Architecture: "ATOM IS DATABANK & COMPUTE CORE"                          ║
 * ║                                                                           ║
 * ║  Widget READS "state" contact for error indication.                       ║
 * ║  All control and data flow through Atom contacts.                         ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class NETRadioPlayerWidget extends DeviceView
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _label:TextField;
    
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    public var widgetWidth:Float = 100;
    public var widgetHeight:Float = 40;
    
    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }
    
    // Colors
    private var _colorNormal:Int = 0x2a2a3a;
    private var _colorError:Int = 0x3a1a1a;
    private var _borderNormal:Int = 0x4a4a6a;
    private var _borderError:Int = 0xAA3333;
    
    // =========================================================================
    // STATE
    // =========================================================================
    private var _stateContact:Contact;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom)
    {
        super(atom);
        findContacts();
        buildUI();
        syncFromAtom();
    }
    
    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    private function findContacts():Void
    {
        if (atom == null) return;
        _stateContact = atom.getOutput("state");
    }
    
    override private function onActivate():Void
    {
        findContacts();
        syncFromAtom();
    }
    
    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void
    {
        _bg = new Sprite();
        addChild(_bg);
        
        _label = new TextField();
        _label.defaultTextFormat = new TextFormat("_sans", 9, 0x888899);
        _label.text = "NET Radio";
        _label.width = widgetWidth;
        _label.height = 16;
        _label.selectable = false;
        _label.mouseEnabled = false;
        _label.y = widgetHeight - 16;
        
        var fmt = new TextFormat("_sans", 9, 0x888899);
        fmt.align = TextFormatAlign.CENTER;
        _label.setTextFormat(fmt);
        _label.defaultTextFormat = fmt;
        
        addChild(_label);
        
        drawNormal();
    }
    
    private function drawNormal():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(_colorNormal);
        _bg.graphics.lineStyle(1, _borderNormal);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 4, 4);
        _bg.graphics.endFill();
    }
    
    private function drawError():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(_colorError);
        _bg.graphics.lineStyle(1, _borderError);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 4, 4);
        _bg.graphics.endFill();
    }
    
    // =========================================================================
    // DATA SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void
    {
        if (_stateContact != null && _stateContact.value != null)
        {
            updateVisual(_stateContact.value == true);
        }
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;
        
        if (contact == _stateContact)
        {
            // state = true means error
            updateVisual(newValue == true);
        }
    }
    
    private function updateVisual(hasError:Bool):Void
    {
        if (hasError) drawError();
        else drawNormal();
    }
    
    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        _bg = null;
        _label = null;
        _stateContact = null;
        super.dispose();
    }
}