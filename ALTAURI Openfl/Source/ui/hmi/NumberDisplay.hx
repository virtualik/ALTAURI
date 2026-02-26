package ui.hmi;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.Contact;

/**
 * NumberDisplay Widget
 * A read-only text field that shows Contact value.
 */
class NumberDisplay extends Sprite implements IHMIWidget {
    
    public var contact(default, null):Contact;
    
    private var _display:TextField;
    private var _label:TextField;
    
    public function new(contact:Contact, label:String = "Output") {
        super();
        this.contact = contact;
        
        // Label
        _label = new TextField();
        _label.text = label;
        _label.width = 150;
        _label.height = 20;
        _label.textColor = 0xAAAAAA;
        addChild(_label);
        
        // Display Field
        _display = new TextField();
        _display.border = true;
        _display.borderColor = 0xFF8800;
        _display.background = true;
        _display.backgroundColor = 0x112211;
        _display.textColor = 0x00FF00;
        _display.width = 150;
        _display.height = 30;
        _display.y = 20;
        _display.defaultTextFormat = new TextFormat("_typewriter", 14);
        _display.text = Std.string(contact.value);
        addChild(_display);
        
        // Subscribe
        contact.subscribe(onValueChanged);
    }
    
    public function onValueChanged(newValue:Dynamic):Void {
        _display.text = Std.string(newValue);
    }
    
    public function dispose():Void {
        contact.unsubscribe(onValueChanged);
    }
}