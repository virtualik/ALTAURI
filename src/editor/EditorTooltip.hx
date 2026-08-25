package editor;

import openfl.display.Sprite;
import openfl.display.Stage;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;

/**
* EDITOR TOOLTIP v1.0 (Stable Port Naming companion)
*
* Lightweight hover tooltip used by NodeView ports, NodeEditor wall
* ports and WireRenderer wires. With the v3.0 stable naming scheme
* ("Inlet_3") the port name alone carries no semantics — the tooltip
* shows the BENEFICIARY ("Inlet_3 -> Button.set"), derived live from
* blueprint connections.
*
* Design notes:
*   - One static overlay sprite, added DIRECTLY to the stage: above all
*     editor layers, immune to canvas zoom/pan transforms.
*   - Text labels use ASCII arrows ("->", "<-") only — the project has
*     a field-proven lesson about glyphs missing from target fonts.
*   - mouseEnabled=false everywhere: the tooltip never steals events.
*   - hide() is safe to call from any context (dispose, drag start...).
*/
class EditorTooltip
{
        private static var _tip:Sprite = null;
        private static var _label:TextField = null;

        /**
        * Show (or move) the tooltip near the given stage coordinates.
        * Clamps to stage bounds; flips side when near the right edge.
        */
        public static function show(stage:Stage, stageX:Float, stageY:Float, text:String):Void
        {
                if (stage == null || text == null || text.length == 0) return;
                if (_tip == null) build();

                _label.text = text;
                var w:Float = _label.textWidth + 12;
                var h:Float = _label.textHeight + 8;

                var g = _tip.graphics;
                g.clear();
                g.beginFill(0x111122, 0.95);
                g.lineStyle(1, 0x00AAFF);
                g.drawRoundRect(0, 0, w, h, 4, 4);
                g.endFill();

                if (_tip.parent != stage) stage.addChild(_tip);

                var px:Float = stageX + 14;
                var py:Float = stageY + 16;
                if (px + w > stage.stageWidth - 4) px = stageX - w - 12;
                if (py + h > stage.stageHeight - 4) py = stageY - h - 12;
                if (px < 4) px = 4;
                if (py < 4) py = 4;
                _tip.x = px;
                _tip.y = py;
        }

        /** Hide the tooltip. Always safe; never throws. */
        public static function hide():Void
        {
                if (_tip != null && _tip.parent != null)
                {
                        _tip.parent.removeChild(_tip);
                }
        }

        private static function build():Void
        {
                _tip = new Sprite();
                _tip.mouseEnabled = false;
                _tip.mouseChildren = false;
                _label = new TextField();
                _label.selectable = false;
                _label.mouseEnabled = false;
                _label.x = 6;
                _label.y = 4;
                _label.autoSize = TextFieldAutoSize.LEFT;
                _label.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFCC);
                _tip.addChild(_label);
        }
}
