package ui.hmi;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.Event;
import core.Contact;

/**
 * NumberInput Widget
 * A text input field that pushes values into a Contact.
 */
class NumberInput extends Sprite implements IHMIWidget {
    
    public var contact(default, null):Contact;
    
    private var _input:TextField;
    private var _label:TextField;
    
    public function new(contact:Contact, label:String = "Input") {
        super();
        this.contact = contact;
        
        // Label
        _label = new TextField();
        _label.text = label;
        _label.width = 150;
        _label.height = 20;
        _label.textColor = 0xAAAAAA;
        addChild(_label);
        
        // Input Field
        _input = new TextField();
        _input.type = TextFieldType.INPUT; // Allow typing
        _input.border = true;
        _input.borderColor = 0x00AAFF;
        _input.background = true;
        _input.backgroundColor = 0x222233;
        _input.textColor = 0xFFFFFF;
        _input.width = 150;
        _input.height = 30;
        _input.y = 20;
        _input.defaultTextFormat = new TextFormat("_typewriter", 14);
        _input.text = Std.string(contact.value);
        addChild(_input);
        
        // Listen to user input
        _input.addEventListener(Event.CHANGE, onUserInput);
        
        // Listen to contact changes (if external update)
        contact.subscribe(onContactUpdate);
    }
    
    private function onUserInput(e:Event):Void {
        var val = Std.parseFloat(_input.text);
        if (!Math.isNaN(val)) {
            contact.value = val; // Push to Core
        }
    }
    
    public function onValueChanged(newValue:Dynamic):Void {
        // Update visual if changed externally
        if (Std.string(newValue) != _input.text) {
            _input.text = Std.string(newValue);
        }
    }
    
    private function onContactUpdate(val:Dynamic):Void {
        onValueChanged(val);
    }
    
    public function dispose():Void {
        _input.removeEventListener(Event.CHANGE, onUserInput);
        contact.unsubscribe(onContactUpdate);
    }
}