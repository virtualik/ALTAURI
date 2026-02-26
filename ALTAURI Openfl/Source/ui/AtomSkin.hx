package ui;

import openfl.geom.Point;

/**
 * ATOM SKIN v1.0
 * Data object defining how an Atom looks.
 * Can be loaded from JSON or created in code.
 */
class AtomSkin {
    // Dimensions
    public var width:Float = 60;
    public var height:Float = 40;
    
    // Colors
    public var backgroundColor:Int = 0x3366CC;
    public var borderColor:Int = 0xFFFFFF;
    public var textColor:Int = 0xFFFFFF;
    
    // Layout
    public var cornerRadius:Float = 8;
    public var showLabel:Bool = true;
    
    // Context variants
    public var editorSkin:AtomSkin;
    public var deviceSkin:AtomSkin;

    public function new() {}

    /**
     * Creates a default skin for a given category.
     */
    public static function createDefault(category:String):AtomSkin {
        var skin = new AtomSkin();
        
        switch(category) {
            case "Logic": 
                skin.backgroundColor = 0x6666CC;
            case "Input": 
                skin.backgroundColor = 0x336699;
            case "Output": 
                skin.backgroundColor = 0x996633;
            default: 
                skin.backgroundColor = 0x444444;
        }
        
        // Create variants for different contexts
        // Editor: Detailed
        skin.editorSkin = skin.clone();
        
        // Device: Simplified
        var device = skin.clone();
        device.borderColor = 0x000000; // Darker border for device
        skin.deviceSkin = device;
        
        return skin;
    }

    public function clone():AtomSkin {
        var s = new AtomSkin();
        s.width = this.width;
        s.height = this.height;
        s.backgroundColor = this.backgroundColor;
        s.borderColor = this.borderColor;
        s.textColor = this.textColor;
        s.cornerRadius = this.cornerRadius;
        s.showLabel = this.showLabel;
        return s;
    }
}