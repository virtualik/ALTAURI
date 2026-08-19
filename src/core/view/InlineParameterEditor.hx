// FILE: core/view/InlineParameterEditor.hx
package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Contact;
import core.data.Blueprint.PinDef;

/**
 * INLINE PARAMETER EDITOR v1.1 (Functionality Toggle)
 * Inline contact value editor directly on node body in Editor.
 *
 * v1.1 Changes:
 * - ADDED: setFunctionality(enabled:Bool) to completely disable/enable
 *   contact subscription and UI updates. When disabled, the editor
 *   does NOT subscribe to contact changes, does NOT update text,
 *   and consumes zero CPU cycles.
 * - Used by NodeView in LIGHT visual mode to prevent hidden editors
 *   from consuming resources.
 *
 * Logic:
 * - If contact has incoming connection → editor hidden
 * - Otherwise → show default value from PinDef
 * - On change → write to contact.value
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  NodeView (Editor Mode)                                         │
 * │                                                                 │
 * │  INPUTS:                                                        │
 * │  ○ freq    [440.0]  ← InlineParameterEditor (if no wire)        │
 * │  ○ quantum [0.10]   ← InlineParameterEditor                     │
 * │  ○ in      ━━━━━━   ← port only (wire connected)                │
 * └─────────────────────────────────────────────────────────────────┘
 */
class InlineParameterEditor extends Sprite
{
    private var _contact:Contact;
    private var _pinDef:PinDef;
    private var _inputField:TextField;
    private var _labelField:TextField;
    private var _isEditing:Bool = false;
    
    /** v1.1: Functionality flag. When false, editor is completely disabled. */
    private var _isFunctioning:Bool = true;
    
    /** v1.1: Saved callback reference for unsubscribe. */
    private var _contactCallback:Dynamic -> Void;
    
    public function new(contact:Contact, pinDef:PinDef)
    {
        super();
        _contact = contact;
        _pinDef = pinDef;
        
        // Protection against null pinDef
        if (_pinDef == null)
        {
            _pinDef = {
                name: contact.name,
                type: contact.type,
                defaultValue: contact.value,
                label: contact.name,
                priority: core.data.Blueprint.ParameterPriority.OPTIONAL,
                visibleInEditor: true,
                editable: true
            };
        }
        
        buildUI();
        subscribeToContact();
        updateDisplay();
    }
    
    private function buildUI():Void
    {
        // Label (parameter name)
        _labelField = new TextField();
        _labelField.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFCFC);
        _labelField.text = (_pinDef.label != null) ? _pinDef.label : _pinDef.name;
        _labelField.width = 77;
        _labelField.y = 6;
        _labelField.height = 16;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;
        addChild(_labelField);
        
        // Input field (value editor)
        _inputField = new TextField();
        _inputField.type = TextFieldType.INPUT;
        _inputField.defaultTextFormat = new TextFormat("_sans", 10, 0x00AAFF, true);
        _inputField.width = 70;
        _inputField.height = 16;
        _inputField.y = 21;
        _inputField.border = true;
        _inputField.borderColor = 0x333344;
        _inputField.background = true;
        _inputField.backgroundColor = 0x1a1a24;
        _inputField.selectable = true;
        _inputField.mouseEnabled = true;
        
        // Set default value
        if (_pinDef.defaultValue != null)
        {
            _inputField.text = Std.string(_pinDef.defaultValue);
        }
        
        _inputField.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
        _inputField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _inputField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
        addChild(_inputField);
    }
    
    /**
     * v1.1: Subscribe to contact changes with saved callback reference.
     */
    private function subscribeToContact():Void
    {
        _contactCallback = function(v:Dynamic)
        {
            // v1.1: Only update if functioning and not editing
            if (!_isEditing && _isFunctioning)
            {
                updateDisplay();
            }
        };
        _contact.subscribe(_contactCallback);
    }
    
    private function updateDisplay():Void
    {
        if (_contact.value != null)
        {
            _inputField.text = Std.string(_contact.value);
        }
        else if (_pinDef.defaultValue != null)
        {
            _inputField.text = Std.string(_pinDef.defaultValue);
        }
    }
    
    private function onFocusIn(e:FocusEvent):Void
    {
        _isEditing = true;
    }
    
    private function onFocusOut(e:FocusEvent):Void
    {
        _isEditing = false;
        pushValue();
    }
    
    private function onKeyDown(e:KeyboardEvent):Void
    {
        if (e.keyCode == Keyboard.ENTER)
        {
            pushValue();
            if (stage != null) stage.focus = null;
        }
    }
    
    private function pushValue():Void
    {
        var text = _inputField.text;
        var floatVal = Std.parseFloat(text);
        if (!Math.isNaN(floatVal))
        {
            _contact.value = floatVal;
        }
        else if (text.toLowerCase() == "true")
        {
            _contact.value = true;
        }
        else if (text.toLowerCase() == "false")
        {
            _contact.value = false;
        }
        else {
            _contact.value = text;
        }
    }
    
    /**
     * Hide editor (when wire connected).
     */
    public function hideEditor():Void
    {
        _inputField.visible = false;
        _labelField.x = 0;
    }
    
    /**
     * Show editor (when wire disconnected).
     */
    public function showEditor():Void
    {
        _inputField.visible = true;
        _labelField.x = 0;
        _inputField.x = 55;
        updateDisplay();
    }
    
    /**
     * v1.1: Enable or disable editor functionality.
     * 
     * When disabled:
     * - Unsubscribes from contact (no CPU cycles on updates)
     * - Hides all UI elements
     * - Ignores all events
     * 
     * When enabled:
     * - Subscribes to contact
     * - Shows UI elements
     * - Resumes normal operation
     * 
     * @param enabled true = fully functional, false = completely disabled
     */
    public function setFunctionality(enabled:Bool):Void
    {
        if (_isFunctioning == enabled) return;
        _isFunctioning = enabled;
        
        if (enabled)
        {
            // Re-subscribe to contact
            if (_contact != null && _contactCallback != null && !_contact.isDisposed)
            {
                _contact.subscribe(_contactCallback);
            }
            // Show UI
            _inputField.visible = true;
            _labelField.visible = true;
            this.visible = true;
            // Update display with current value
            updateDisplay();
        }
        else
        {
            // Unsubscribe from contact (stop all updates)
            if (_contact != null && _contactCallback != null && !_contact.isDisposed)
            {
                _contact.unsubscribe(_contactCallback);
            }
            // Hide UI
            _inputField.visible = false;
            _labelField.visible = false;
            this.visible = false;
        }
    }
    
    /**
     * v1.1: Check if editor is currently functioning.
     */
    public function isFunctioning():Bool
    {
        return _isFunctioning;
    }
    
    public function dispose():Void
    {
        // v1.1: Unsubscribe before disposing
        if (_contact != null && _contactCallback != null && !_contact.isDisposed)
        {
            _contact.unsubscribe(_contactCallback);
        }
        _contactCallback = null;
        
        _inputField.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
        _inputField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _inputField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
        if (_inputField.parent != null) _inputField.parent.removeChild(_inputField);
        if (_labelField.parent != null) _labelField.parent.removeChild(_labelField);
        
        _inputField = null;
        _labelField = null;
    }
}