package ui.hmi;

import core.Contact;

/**
 * HMI Widget Interface
 * Any visual control (Button, Slider, Graph) must implement this.
 */
interface IHMIWidget {
    public var contact(default, null):Contact;
    
    /**
     * Called when the associated Contact value changes.
     */
    function onValueChanged(newValue:Dynamic):Void;
    
    /**
     * Cleanup.
     */
    function dispose():Void;
}