package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint.PinDef;
import core.types.ContactType;

/**
 * PANEL WIDGET
 * Container widget for Assembly showing internal elements.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Assembly (Databank)                                                   │
 * │                                                                         │
 * │   Ports (ConductorPort) ◄──► PanelWidget                                │
 * │                              ┌─────────────────────────────────────────┐│
 * │                              │ Shows:                                  ││
 * │                              │ - Assembly name                         ││
 * │                              │ - Input ports (left side)               ││
 * │                              │ - Output ports (right side)             ││
 * │                              │ - Port values (from Databank)           ││
 * │                              └─────────────────────────────────────────┘│
 * │                                                                         │
 * │   Widget READS port contact values (display only)                       │
 * │   Ports are part of Assembly Databank                                   │
 * │   Internal atoms have their own DeviceViews (managed by Registry)       │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class PanelWidget extends DeviceView 
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _content:Sprite;
    private var _inputPorts:Map<String, Sprite>;
    private var _outputPorts:Map<String, Sprite>;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    // Widget dimensions
    public var panelWidth:Float = 200;
    public var panelHeight:Float = 150;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return {width: panelWidth, height: panelHeight};
    }

    public var headerHeight:Float = 24;
    public var portRadius:Float = 6;
    public var bgColor:Int = 0x2A2A3A;
    public var headerColor:Int = 0x3A3A4A;
    public var borderColor:Int = 0x4A4A6A;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(asm:Assembly) 
    {
        super(asm);
        _inputPorts = new Map();
        _outputPorts = new Map();
        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void 
    {
        // Background panel
        graphics.clear();
        graphics.beginFill(bgColor);
        graphics.lineStyle(1, borderColor);
        graphics.drawRoundRect(0, 0, panelWidth, panelHeight, 6, 6);
        graphics.endFill();

        // Header
        _header = new Sprite();
        _header.graphics.beginFill(headerColor);
        _header.graphics.drawRoundRect(0, 0, panelWidth, headerHeight, 6, 6);
        _header.graphics.endFill();
        addChild(_header);

        _titleLabel = new TextField();
        _titleLabel.width = panelWidth - 10;
        _titleLabel.height = headerHeight;
        _titleLabel.x = 5;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        var fmt = new TextFormat("_sans", 12, 0xFFFFFF, true);
        _titleLabel.defaultTextFormat = fmt;
        _titleLabel.text = (assembly != null && assembly.blueprint != null) ? assembly.blueprint.name : "Panel";
        _header.addChild(_titleLabel);

        // Content area
        _content = new Sprite();
        _content.y = headerHeight + 5;
        addChild(_content);

        // Create ports
        createPorts();
		trace('PanelWidget: assembly=${assembly != null}, blueprint=${assembly != null ? assembly.blueprint : null}');
		
		if (assembly != null && assembly.blueprint != null) {
			trace('PanelWidget: blueprint.name="${assembly.blueprint.name}"');
		}
		_titleLabel.text = (assembly != null && assembly.blueprint != null) ? assembly.blueprint.name : "Panel";
    }

    // =========================================================================
    // PORT CREATION
    // =========================================================================
    private function createPorts():Void 
    {
        if (assembly == null || assembly.blueprint == null) return;
        var pins = assembly.blueprint.pins;
        if (pins == null) return;

        var inputs:Array<PinDef> = [];
        var outputs:Array<PinDef> = [];

        for (pin in pins) 
        {
            if (pin == null) continue;
            if (pin.type == INPUT) 
            {
                inputs.push(pin);
            } 
            else if (pin.type == OUTPUT) 
            {
                outputs.push(pin);
            }
        }

        // Calculate step for port positioning
        var inputStep = inputs.length > 0 ? (panelHeight - headerHeight - 20) / (inputs.length + 1) : 0;
        var outputStep = outputs.length > 0 ? (panelHeight - headerHeight - 20) / (outputs.length + 1) : 0;

        // Create input ports (left side)
        for (i in 0...inputs.length) 
        {
            var pin = inputs[i];
            if (pin == null || pin.name == null) continue;
            var port = createPortSprite(pin.name, true);
            port.x = -portRadius;
            port.y = headerHeight + inputStep * (i + 1);
            addChild(port);
            _inputPorts.set(pin.name, port);
        }

        // Create output ports (right side)
        for (i in 0...outputs.length) 
        {
            var pin = outputs[i];
            if (pin == null || pin.name == null) continue;
            var port = createPortSprite(pin.name, false);
            port.x = panelWidth + portRadius;
            port.y = headerHeight + outputStep * (i + 1);
            addChild(port);
            _outputPorts.set(pin.name, port);
        }
    }

    private function createPortSprite(name:String, isInput:Bool):Sprite 
    {
        var s = new Sprite();
        s.graphics.beginFill(isInput ? 0xFFAA00 : 0x00AAFF);
        s.graphics.drawCircle(0, 0, portRadius);
        s.graphics.endFill();
        s.name = name != null ? name : "port";

        // Port label
        var label = new TextField();
        label.width = 60;
        label.height = 14;
        label.selectable = false;
        label.mouseEnabled = false;
        var fmt = new TextFormat("_sans", 9, 0xAAAAAA);
        label.defaultTextFormat = fmt;
        label.text = name != null ? name : "?";
        
        if (isInput) 
        {
            label.x = portRadius + 3;
        } 
        else 
        {
            label.x = -portRadius - 63;
        }
        label.y = -7;
        s.addChild(label);

        return s;
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void 
    {
        // Update port visual based on value
        // Could add highlighting for active ports
    }

    public function getPortPosition(name:String, isInput:Bool):{x:Float, y:Float} 
    {
        var ports = isInput ? _inputPorts : _outputPorts;
        var port = ports.get(name);
        if (port != null) 
        {
            return {x: port.x, y: port.y};
        }
        return {x: 0, y: 0};
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void 
    {
        _header = null;
        _titleLabel = null;
        _content = null;
        
        if (_inputPorts != null) 
        {
            for (name in _inputPorts.keys()) 
            {
                var port = _inputPorts.get(name);
                if (port != null && port.parent != null) 
                {
                    port.parent.removeChild(port);
                }
            }
            _inputPorts.clear();
        }
        
        if (_outputPorts != null) 
        {
            for (name in _outputPorts.keys()) 
            {
                var port = _outputPorts.get(name);
                if (port != null && port.parent != null) 
                {
                    port.parent.removeChild(port);
                }
            }
            _outputPorts.clear();
        }
        super.dispose();
    }
}