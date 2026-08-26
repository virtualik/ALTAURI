package editor;

import openfl.display.Sprite;
import openfl.display.Stage;
import openfl.events.MouseEvent;

/**
 * EDITOR VISUALS v1.0
 * ═══════════════════════════════════════════════════════════════════════════
 * EXTRACTED FROM EditorContext v2.13 — Episod C of the Editor de-god-ification.
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Stateless rendering helpers for the editor chrome — the rounded-rectangle
 * frame around each editor container and the semi-transparent blocker overlay
 * that intercepts mouse events on the parent editor behind a freshly pushed
 * child.
 *
 * Both helpers depend ONLY on the Stage dimensions (passed in by the caller).
 * No EditorContext state, no Impulsys, no subscriptions.
 *
 * Migration guide for EditorContext callers:
 *   ─ drawContainerFrame(container)               → _visuals.drawContainerFrame(container, _layer.stage)
 *   ─ (inline blocker creation in push())         → _visuals.createBlocker(_layer.stage)
 */
class EditorVisuals
{
        /** Margin between the editor container and the stage edges, in pixels. */
        public static inline var FRAME_MARGIN:Int = 12;

        /** Corner radius of the rounded-rectangle container frame, in pixels. */
        public static inline var FRAME_CORNER_RADIUS:Float = 10;

        /** Blocker fill color (mid-gray) and alpha (60% opacity). */
        public static inline var BLOCKER_COLOR:Int = 0x808080;
        public static inline var BLOCKER_ALPHA:Float = 0.6;

        public function new() {}

        /**
         * Draws the rounded-rectangle frame on the editor container's
         * graphics surface and positions it inside the parent layer with
         * a uniform FRAME_MARGIN on all sides.
         *
         * The caller (EditorContext.push) creates an empty Sprite and passes
         * it here for visual setup, then adds the NodeEditor as a child
         * inside it.
         */
        public function drawContainerFrame(container:Sprite, stage:Stage):Void
        {
                var w = stage.stageWidth - (FRAME_MARGIN * 2);
                var h = stage.stageHeight - (FRAME_MARGIN * 2);

                container.graphics.clear();
                //container.graphics.beginFill(_theme.FRAME_FILL_COLOR, _theme.FRAME_FILL_ALPHA);
                //container.graphics.lineStyle(1, _theme.FRAME_BORDER_COLOR);
                container.graphics.drawRoundRect(0, 0, w, h,
                        FRAME_CORNER_RADIUS, FRAME_CORNER_RADIUS);
                container.graphics.endFill();

                container.x = FRAME_MARGIN;
                container.y = FRAME_MARGIN;
        }

        /**
         * Creates a semi-transparent blocker overlay that fills the entire
         * stage and intercepts mouse clicks (so the parent editor behind it
         * cannot receive input while a child is open).
         *
         * The caller (EditorContext.push) is responsible for adding the
         * returned Sprite to the layer (and removing it on pop). The blocker
         * self-registers a click handler that stops propagation.
         *
         * Why a separate Sprite instead of just disabling mouse on the
         * parent editor: openfl's mouseChildren=false / mouseEnabled=false
         * on the parent stops its OWN children from receiving events, but
         * does not block the underlying layer from picking up background
         * clicks. The blocker overlay ensures clicks anywhere in the
         * viewport are absorbed by the overlay.
         */
        public function createBlocker(stage:Stage):Sprite
        {
                var blocker = new Sprite();
                blocker.graphics.beginFill(BLOCKER_COLOR, BLOCKER_ALPHA);
                blocker.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
                blocker.graphics.endFill();

                // Blocker intercepts clicks (prevents interaction with background)
                blocker.addEventListener(MouseEvent.CLICK,
                        function(e:MouseEvent) e.stopPropagation());

                return blocker;
        }
}
