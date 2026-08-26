package editor;

import core.base.Assembly;
import openfl.display.Sprite;

/**
 * EDITOR ENTRY typedef — per-stack entry in EditorContext's editor stack.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * Episod D (v1.0): typedef extracted from EditorContext.hx to its own file
 * editor/EditorEntry.hx so it is visible to other classes in the `editor`
 * package (notably editor.AssemblyReconstructor, which accepts an
 * Array<EditorEntry> as the editor stack parameter for
 * onAssemblyPortsChanged).
 *
 * Haxe rule: a top-level type must live in a file with the same name as the
 * type. `typedef EditorEntry` declared inside EditorContext.hx was invisible
 * to AssemblyReconstructor.hx — the compiler refused to resolve
 * `Array<EditorEntry>` from there. Moving the typedef here makes it a
 * first-class citizen of the `editor` package.
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * SEMANTICS:
 *   assembly           — the Assembly being edited at this stack level
 *   editor             — the NodeEditor instance rendering `assembly`
 *   blocker            — semi-transparent overlay blocking parent editor
 *                         input while this entry is the active top-of-stack
 *                         (Episod C → editor.EditorVisuals.createBlocker)
 *   container          — Sprite holding `editor`'s display tree
 *   parentCameraState  — per-stack-entry scratch: parent's viewport captured
 *                         on push() so it can be restored on pop(). Distinct
 *                         from editor.EditorCameraStore (which is
 *                         cross-cycle persistent storage keyed by blueprint.id).
 *                         @:optional because root push() has no parent.
 */
typedef EditorEntry =
{
        var assembly:Assembly;
        var editor:NodeEditor;
        var blocker:Sprite;
        var container:Sprite;
        @:optional var parentCameraState:{x:Float, y:Float, zoom:Float};
}
