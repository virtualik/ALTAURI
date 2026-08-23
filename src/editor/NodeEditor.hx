package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.events.TouchEvent;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Lib;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import core.types.ContactType;
import library.AtomRegistry;
import editor.SelectionManager;
import editor.EditorActionHandler;
import editor.ViewportManager;
import editor.WireRenderer;
import editor.NodeView;
import editor.EditorTheme;
import core.view.DeviceViewRegistry;
import system.managers.UndoManager;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.base.MacroCommand;
import utils.UID;
import ecs.ECS;
import ui.NodeVisualMode;
using StringTools;

/**
* NODE EDITOR v4.10 (Zoom Traps + Zoom Performance Fix + Listener Leak Fix + Reattach API + Broadcast Storm Prevention)
* Visual schematic editing coordinator.
*
* ═══════════════════════════════════════════════════════════════════════════
* v4.9 CHANGES (Zoom Performance Fix — Android Touch Optimization)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM:
*  On Android tablets, pinch-to-zoom caused severe UI stuttering and GC
*  spikes because OpenFL's cacheAsBitmap=true forced every NodeView to
*  recreate its canvas buffer on every frame during scaleX/scaleY changes.
*
*  SOLUTION:
*  Subscribe to ViewportManager.onZoomStart / onZoomEnd callbacks.
*  During active zoom, set cacheAsBitmap=false on all visible NodeViews
*  to switch to cheaper dynamic rendering. After zoom ends, restore
*  cacheAsBitmap=true for crisp static rendering and force a final
*  wire redraw to ensure vector clarity at the new scale.
*
*  Flow:
*  ┌──────────────────────────────────────────────────────────────────┐
*  │  User starts pinch-to-zoom                                       │
*  │       │                                                          │
*  │       ▼                                                          │
*  │  ViewportManager detects 2-finger touch                          │
*  │       │                                                          │
*  │       ├──► onZoomStart callback fires                            │
*  │       │         │                                                │
*  │       │         ▼                                                │
*  │       │    NodeEditor iterates _nodes                            │
*  │       │         │                                                │
*  │       │         ▼                                                │
*  │       │    view.setCacheAsBitmapState(false)                     │
*  │       │         │                                                │
*  │       │         ▼                                                │
*  │       │    OpenFL uses dynamic rendering (cheaper)               │
*  │       │                                                          │
*  │       └──► User releases fingers                                 │
*  │                 │                                                │
*  │                 ▼                                                │
*  │            onZoomEnd callback fires                              │
*  │                 │                                                │
*  │                 ▼                                                │
*  │            view.setCacheAsBitmapState(true)                      │
*  │                 │                                                │
*  │                 ▼                                                │
*  │            _wireRenderer.rebuildAll()                            │
*  │                 │                                                │
*  │                 ▼                                                │
*  │            Crisp vector rendering at new scale                   │
*  └──────────────────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════════
* v4.8 CHANGES (Global Name Uniqueness)
* ═══════════════════════════════════════════════════════════════════════════
*
*  ADDED: Accepts `isNameTakenGlobally` callback from EditorContext.
*  Passes it down to EditorActionHandler (for CreateAtomCommand) and
*  to each NodeView (for inline name editing validation).
*
* ═══════════════════════════════════════════════════════════════════════════
* v4.7 CHANGES (isActive Flag — Broadcast Storm Prevention)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM:
*  When entering a nested assembly (EditorContext.push), the previous
*  NodeEditor stays alive behind a blocker. All 9 of its Impulsys
*  subscriptions remain active. On nesting level N, every REDRAW_WIRES
*  emit triggers N concurrent rebuildAll() calls — O(N) work per event,
*  causing UI freezes during pan/zoom at deep nesting.
*
*  SOLUTION:
*  Added `isActive:Bool = true` field. EditorContext.push() sets the
*  parent editor's isActive = false. EditorContext.pop() sets it back
*  to true and calls forceFullRedraw() to catch up on missed events.
*
*  The _onRedrawWires and _onAssemblyPortsChanged handlers now early-
*  return when !isActive. Other handlers (ATOM_DELETED etc.) already
*  filter by assemblyId, so they don't need the guard.
*
* ═══════════════════════════════════════════════════════════════════════════
* v4.6 CHANGES (NodeView Reattach API)
* ═══════════════════════════════════════════════════════════════════════════
*
*  ADDED: reattachNodeView(atomId, newAtom)
*  See method doc below.
*
* ═══════════════════════════════════════════════════════════════════════════
* v4.5 CHANGES (Listener Leak Fix + Dispose Safety)
* ═══════════════════════════════════════════════════════════════════════════
*
* v4.4 Changes:
* - FIXED: forceFullRedraw() now also redraws edge ports and forces stage invalidate.
* - ADDED: Additional safety redraw in onAddedToStage_Frame to ensure wires appear.
*
* v4.3 Changes:
* - ADDED: isDisposed flag for safe delayed operations.
* - FIXED: forceFullRedraw() uses isDisposed instead of non-existing _isDisposed.
* - FIXED: onAddedToStage_Frame now calls rebuildAll() and updateVisibility().
*
* v4.2 Changes:
* - FIXED: Restored delegation in setWireType() to properly forward
*   settings from SettingsPanel to WireRenderer. Removed legacy stubs.
*
* v4.1 Changes:
* - ADDED: restoreAllWidgets() method to return DeviceViews to NodeViews.
* - FIXED: Widgets now properly return to schematic nodes when switching from Device Mode.
*
* v4.0 Changes (Refactored: Selection Extracted):
* - Removed Selection logic -> SelectionManager.
* - Removed Lasso logic -> SelectionManager.
* - Clearer separation of concerns.
*
* Architecture:
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   NodeEditor                                                            │
* │                                                                         │
* │   ┌─────────────────────────────────────────────────────────────────┐   │
* │   │  CORE COMPONENTS:                                               │   │
* │   │  - _assembly:Assembly           → Current assembly being edited │   │
* │   │  - _blueprint:Blueprint         → Schematic definition          │   │
* │   │  - _canvas:Sprite               → Pan/zoom container            │   │
* │   │  - _nodes:Map<String,NodeView>  → All node views                │   │
* │   │                                                                 │   │
* │   │  MANAGERS:                                                      │   │
* │   │  - _viewport:ViewportManager    → Pan, Zoom, Visibility         │   │
* │   │  - _selection:SelectionManager  → Node/wire selection + Lasso   │   │
* │   │  - _actions:EditorActionHandler → Undo/Redo command dispatch    │   │
* │   │  - _wireRenderer:WireRenderer   → Wire visualization            │   │
* │   │                                                                 │   │
* │   │  EDGE PORTS (Assembly boundary):                                │   │
* │   │  - _frame:Sprite                → Assembly frame border         │   │
* │   │  - _edgePorts:Map<String,Sprite>→ Boundary port sprites         │   │
* │   │                                                                 │   │
* │   │  PUBLIC API:                                                    │   │
* │   │  - setSize(w, h)                                                │   │
* │   │  - refreshAssemblyViews()                                       │   │
* │   │  - restoreAllWidgets()    → Return DeviceViews to NodeViews     │   │
* │   │  - deselectAll()                                                │   │
* │   │  - selectAll()                                                  │   │
* │   │  - selectNode(id, view)                                         │   │
* │   │  - isSelected(id) → Bool                                        │   │
* │   │  - getSelectedNodeIds() → Array<String>                         │   │
* │   │  - getSelectedNodeCount() → Int                                 │   │
* │   │  - getSelectedWireIds() → Array<String>                         │   │
* │   │  - clearWireSelection()                                         │   │
* │   │  - getViewState() → {x, y, zoom}                                │   │
* │   └─────────────────────────────────────────────────────────────────┘   │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class NodeEditor extends Sprite
{
        // =========================================================================
        // CORE
        // =========================================================================
        private var _assembly:Assembly;
        private var _blueprint:core.data.Blueprint;
        private var _theme:EditorTheme;
        private var _isNameTakenGlobally:(String, ?String) -> Bool; // v4.8: Global name uniqueness checker
        private var _hitLayer:Sprite;
        // =========================================================================
        // MANAGERS
        // =========================================================================
        private var _viewport:ViewportManager;
        private var _actions:EditorActionHandler;
        private var _wireRenderer:WireRenderer;
        private var _selection:SelectionManager;

        // =========================================================================
        // NODE MANAGEMENT
        // =========================================================================
        private var _nodes:Map<String, NodeView> = new Map();
        private var _editorContainer:Sprite;
        private var _canvas:Sprite;
        
        /**
        * Creates atom in setted up lication with particular ID.
        * It's good for demo-scheme creation with code.
        */
        public function createAtomWithId(typeId:String, instanceId:String, posX:Float, posY:Float):Void
        {
                var localPoint = _canvas.globalToLocal(new Point(posX, posY));
                _actions.createAtomWithId(typeId, instanceId, localPoint.x, localPoint.y);
        }

        /**
        * Connects two atoms using their ID and contact names.
        */
        public function connectAtoms(fromId:String, fromContact:String, toId:String, toContact:String):Void
        {
                _actions.connect(fromId, fromContact, toId, toContact);
        }
        // =========================================================================
        // PORT DRAG
        // =========================================================================
        private var _isDraggingPort:Bool = false;
        private var _dragNodeId:String;
        private var _dragContactName:String;
        private var _dragStartX:Float = 0;
        private var _dragStartY:Float = 0;
        private var _dragStartIsInput:Bool = false;

        // =========================================================================
        // NODE DRAG
        // =========================================================================
        private var _draggingNode:NodeView = null;
        private var _dragStartPositions:Map<String, {x:Float, y:Float}>;

        // =========================================================================
        // EDGE PORTS
        // =========================================================================
        private var _frame:Sprite;
        private var _edgePortsContainer:Sprite;
        private var _edgePorts:Map<String, Sprite> = new Map();
        private var _fileNameField:openfl.text.TextField;
        private var _forcedWidth:Float = 0;
        private var _forcedHeight:Float = 0;

        // =========================================================================
        // VISIBILITY
        // =========================================================================
        private var _lastVisibilityUpdate:Float = 0;

        // =========================================================================
        // LIFECYCLE FLAG (v4.3)
        // =========================================================================
        /** Флаг, указывающий, что редактор уничтожен (для безопасных отложенных вызовов). */
        public var isDisposed(default, null):Bool = false;

        // =========================================================================
        // TOUCH STATE (v5.0 — Android single-finger gestures)
        // =========================================================================
        /** True while a 1-finger touch is being tracked by NodeEditor. */
        private var _singleTouchActive:Bool = false;
        /** Stage position where the single touch began. */
        private var _touchStartX:Float = 0;
        private var _touchStartY:Float = 0;
        /** Long-press timer (2 s hold on background). */
        private var _longPressTimer:haxe.Timer = null;
        /** Whether the long-press has already fired (prevents re-fire). */
        private var _longPressFired:Bool = false;
        /** Whether the finger moved beyond the dead-zone (cancels long-press). */
        private var _touchMoved:Bool = false;
        /** Pixel-squared threshold to cancel long-press (~10 px). */
        private static inline var LONG_PRESS_DEAD_ZONE_SQ:Float = 100.0;

        // =========================================================================
        // v4.5: NAMED IMPULSYS LISTENER FIELDS
        // =========================================================================
        // These hold the exact function references used in subscribeToImpulse()
        // so that removeImpulse() in dispose() can unsubscribe the SAME
        // reference. Previously, REDRAW_WIRES and ASSEMBLY_PORTS_CHANGED used
        // inline anonymous functions, and dispose() created NEW anonymous
        // functions for unsubscribe — which never matched (Array.remove uses
        // reference equality). The stale listeners stayed in the bus forever,
        // firing on every event and touching disposed graphics state.
        private var _onPortDragStart:Impulse -> Void;
        private var _onNodeMoved:Impulse -> Void;
        private var _onNodeDragFinished:Impulse -> Void;
        private var _onForceUpdatePosition:Impulse -> Void;
        private var _onRedrawWires:Impulse -> Void;
        private var _onAssemblyPortsChanged:Impulse -> Void;
        private var _onAtomDeleted:Impulse -> Void;
        private var _onAtomRestored:Impulse -> Void;
        private var _onNodeClicked:Impulse -> Void;

        // =========================================================================
        // v4.7: ACTIVE FLAG (Broadcast Storm Prevention)
        // =========================================================================
        /**
        * When false, this editor ignores global broadcast impulses
        * (REDRAW_WIRES, ASSEMBLY_PORTS_CHANGED) to avoid O(N) work on
        * every event when N editors are stacked in a deep nesting.
        *
        * Set to false by EditorContext.push() when this editor becomes
        * a background (covered by a child editor). Set back to true by
        * EditorContext.pop() when this editor becomes the top again.
        *
        * ATOM_DELETED / ATOM_RESTORED / NODE_CLICKED / PORT_DRAG_START etc.
        * are NOT gated by isActive because they already filter by assemblyId
        * in their handlers. Only the no-payload broadcast events need this.
        */
        public var isActive:Bool = true;

        // =========================================================================
        // CONSTRUCTOR
        // =========================================================================

        public function new(assembly:Assembly, ?isNameTakenGlobally:(String, ?String) -> Bool) // v4.8: Added callback
        {
                super();
                this._assembly = assembly;
                this._blueprint = assembly.blueprint;
                _theme = EditorTheme.getInstance();
                _isNameTakenGlobally = isNameTakenGlobally; // v4.8: Store callback

                // Selection Manager
                _selection = new SelectionManager();

                // =========================================================================
                // DISPLAY LAYERS
                // =========================================================================
                // _editorContainer holds _hitLayer (bottom) and _canvas (top).
                // scrollRect clips everything to the frame area.
                // _hitLayer: invisible glass pane, catches mouse/touch on background.
                // _canvas: holds nodes, wires. mouseEnabled=false so events
                //   pass through to _hitLayer, but mouseChildren=true so
                //   nodes (which have mouseEnabled=true) can catch events.
                // =========================================================================
                _editorContainer = new Sprite();
                addChild(_editorContainer);

                _hitLayer = new Sprite();
                _hitLayer.graphics.beginFill(0x000000, 0.01); // Transparent
                // Size it to the stage (viewport size).
                // We will update this in onResize if needed, but stage size is a good start.
                var w = (stage != null) ? stage.stageWidth : 1024;
                var h = (stage != null) ? stage.stageHeight : 600;
                _hitLayer.graphics.drawRect(0, 0, w, h);
                _hitLayer.graphics.endFill();
                _hitLayer.mouseEnabled = true;
                _editorContainer.addChild(_hitLayer);

                // Canvas holds the actual content (Nodes, Wires).
                _canvas = new Sprite();
                // ═══════════════════════════════════════════════════════════════
                // CRITICAL FIX FOR ANDROID WEBGL:
                // Disable canvas caching. When zooming, OpenFL tries to
                // recreate the texture of the entire container if this is true, which kills FPS
                // and causes artifacts (missing nodes) when switching visibility.
                // ═══════════════════════════════════════════════════════════════
                _canvas.cacheAsBitmap = false;
                _canvas.cacheAsBitmapMatrix = null;
                // CRITICAL: Disable mouse on canvas so events pass through to _hitLayer
                _canvas.mouseEnabled = false;
                _canvas.mouseChildren = true; // But children (Nodes) can still catch clicks!
                _editorContainer.addChild(_canvas);
                
                // Managers
                // Pass _hitLayer instead of _bgHitArea
                _viewport = new ViewportManager(_canvas, _hitLayer); 
                
                _actions = new EditorActionHandler(_assembly, _blueprint, _isNameTakenGlobally); // v4.8: Pass callback
                _wireRenderer = new WireRenderer();
                _wireRenderer.configure(
                        _blueprint, _assembly, _canvas,
                        getNodeViewById, getEdgePortById,
                        function() return _selection.getSelectedWireIds()
                );

                /**
                * Subscribe to ViewportManager zoom callbacks to toggle cacheAsBitmap
                * on all NodeViews during pinch-to-zoom gestures.
                * 
                * During zoom:  cacheAsBitmap=false → cheaper dynamic rendering
                * After zoom:   cacheAsBitmap=true  → crisp static rendering
                * 
                * Wire redraw is deferred via haxe.Timer.delay to decouple the heavy
                * rebuildAll() operation from the zoom gesture completion. The canvas
                * is already scaled via the hardware display list, so the zoom feels
                * immediate. The wire redraw happens asynchronously to make them crisp
                * at the new scale without blocking the UI thread.
                */
                _viewport.onZoomStart = function() {
                        utils.Trap.log("ZOOM", "start: nodes=" + Lambda.count(_nodes));
                        for (view in _nodes) {
                                if (view != null) view.setCacheAsBitmapState(false);
                        }
                };

                _viewport.onZoomEnd = function() {
                        utils.Trap.log("ZOOM", "end: scaleX=" + _canvas.scaleX + " -> cache reset for " + Lambda.count(_nodes) + " views");
                        for (view in _nodes) {
                                if (view != null) view.setCacheAsBitmapState(true);
                        }
                        /**
                        * Defer wire redraw to allow the UI to settle after zoom.
                        * Wires are already scaled via the hardware display list,
                        * so the zoom feels immediate. The redraw makes them crisp
                        * at the new scale without blocking the gesture completion.
                        */
                        haxe.Timer.delay(function() {
                                utils.Trap.log("ZOOM", "deferred rebuildAll firing");
                                if (_wireRenderer != null) _wireRenderer.rebuildAll();
                        }, 100);
                };

                /**
                * Update node visibility after completing any touch gesture (pan or zoom).
                * No wire redraw here — that is handled by onZoomEnd with a delay.
                */
                _viewport.onTransformEnd = function() {
                        updateVisibility();
                };

                /**
                * VM grabbed 2-finger control — cancel any in-progress 1-finger gesture
                * (lasso rectangle drawn on screen, or pending long-press timer).
                */
                _viewport.onViewportGesturingStart = function() {
                        if (_selection.isLassoing()) {
                                _selection.handleMouseUp();
                                _wireRenderer.rebuildAll();
                        }
                        _cancelTouchGesture();
                };
                
                // Pass reference to setWires method so WireRenderer can update selection
                _wireRenderer.setSelectionCallback(function(ids:Array<String>)
                {
                        _selection.clearNodeSelection();
                        _selection.setWires(ids);
                        _wireRenderer.rebuildAll();
                });

                // Frame
                _frame = new Sprite();
                _frame.mouseEnabled = false;
                addChild(_frame);

                _edgePortsContainer = new Sprite();
                _edgePortsContainer.mouseEnabled = true;
                addChild(_edgePortsContainer);

                _fileNameField = new openfl.text.TextField();
                _fileNameField.defaultTextFormat = new openfl.text.TextFormat("_typewriter", 12, _theme.NODE_TEXT_COLOR);
                // Display Assembly name
                _fileNameField.text = _assembly.displayName;
                _fileNameField.autoSize = LEFT;
                _fileNameField.selectable = false;
                addChild(_fileNameField);

                addEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);

                // =========================================================================
                // v4.5: Impulse listeners — assign to named fields first, then subscribe.
                // This guarantees dispose() can unsubscribe the SAME reference.
                // =========================================================================
                _onPortDragStart = onPortDragStart;
                _onNodeMoved = onNodeMoved;
                _onNodeDragFinished = onNodeDragFinished;
                _onForceUpdatePosition = onForceUpdatePosition;

                // Inline-redraw handlers carry an isDisposed guard so that even a
                // very late event (scheduled before unsubscribe completes) cannot
                // touch disposed graphics state.
                _onRedrawWires = function(_)
                {
                        if (isDisposed || !isActive) return;
                        if (_wireRenderer != null) _wireRenderer.rebuildAll();
                };
                _onAssemblyPortsChanged = function(_)
                {
                        if (isDisposed || !isActive) return;
                        drawFrame();
                        if (_wireRenderer != null) _wireRenderer.rebuildAll();
                };

                _onAtomDeleted = onAtomDeleted;
                _onAtomRestored = onAtomRestored;
                _onNodeClicked = onNodeClicked;

                Impulsys.subscribeToImpulse(EventType.PORT_DRAG_START, _onPortDragStart);
                Impulsys.subscribeToImpulse(EventType.EDITOR_NODE_MOVED, _onNodeMoved);
                Impulsys.subscribeToImpulse(EventType.NODE_DRAG_FINISHED, _onNodeDragFinished);
                Impulsys.subscribeToImpulse(EventType.FORCE_UPDATE_NODE_POSITION, _onForceUpdatePosition);
                Impulsys.subscribeToImpulse(EventType.REDRAW_WIRES, _onRedrawWires);
                Impulsys.subscribeToImpulse(EventType.ASSEMBLY_PORTS_CHANGED, _onAssemblyPortsChanged);
                Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, _onAtomDeleted);
                Impulsys.subscribeToImpulse(EventType.ATOM_RESTORED, _onAtomRestored);
                Impulsys.subscribeToImpulse(EventType.NODE_CLICKED, _onNodeClicked);
				Impulsys.subscribeToImpulse(EventType.NODE_VISUAL_MODE_CHANGED, onVisualModeChanged);
        }

        // =========================================================================
        // INIT
        // =========================================================================
        private function onAddedToStage_Frame(e:Event):Void
        {
                removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);
                stage.addEventListener(Event.RESIZE, onResize);
                initListeners();
                drawFrame();
                restoreExistingAtoms();
                _selection.setContext(_assembly, _canvas, getNodeViewById, _blueprint);
                _wireRenderer.setSelectionCallback(function(ids:Array<String>)
                {
                        _selection.clearNodeSelection();
                        _selection.setWires(ids);
                        _wireRenderer.rebuildAll();
                });
                // ===== v4.4: Двойная перерисовка для гарантии =====
                _wireRenderer.rebuildAll();
                updateVisibility();
                // Дополнительный вызов через кадр для надёжности
                haxe.Timer.delay(() -> {
                        if (!isDisposed)
                        {
                                forceFullRedraw();
                        }
                }, 10);
        }

        private function onResize(e:Event):Void
        {
                if (_forcedWidth == 0 && _forcedHeight == 0) drawFrame();
                
                // Update Glass Pane size to match new stage dimensions
                if (_hitLayer != null && stage != null)
                {
                        _hitLayer.graphics.clear();
                        _hitLayer.graphics.beginFill(0x000000, 0.01);
                        _hitLayer.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
                        _hitLayer.graphics.endFill();
                }
        }

        private function initListeners():Void
        {
                // Stage-level mouse handlers (desktop)
                stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
                stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
                stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
                stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);

                // Glass-pane handlers — lasso + context menu (desktop) + touch (Android)
                _hitLayer.addEventListener(MouseEvent.MOUSE_DOWN, onHitLayerMouseDown);
                _hitLayer.addEventListener(MouseEvent.RIGHT_CLICK, onHitLayerRightClick);
                _hitLayer.addEventListener(TouchEvent.TOUCH_BEGIN, onHitLayerTouchBegin);
                _hitLayer.addEventListener(TouchEvent.TOUCH_MOVE, onHitLayerTouchMove);
                _hitLayer.addEventListener(TouchEvent.TOUCH_END, onHitLayerTouchEnd);
        }

        private function drawFrame(e:Event = null):Void
        {
                if (isDisposed) return;
                var w:Float = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
                var h:Float = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);

                _frame.graphics.clear();
                _frame.graphics.lineStyle(5, _theme.FRAME_BORDER_COLOR);
                _frame.graphics.drawRect(0, 0, w, h);

                _editorContainer.scrollRect = new Rectangle(0, 0, w, h);

                _fileNameField.x = w - 10 - _fileNameField.width - 24; // 24 = grip clearance
                _fileNameField.y = h - 20;

                _edgePortsContainer.removeChildren();
                _edgePorts = new Map();

                var leftPorts = _assembly.getOrderedPorts(INPUT);
                var rightPorts = _assembly.getOrderedPorts(OUTPUT);

                var leftStep:Float = h / (leftPorts.length + 1);
                var rightStep:Float = h / (rightPorts.length + 1);

                var leftIdx:Int = 0;
                for (p in leftPorts)
                {
                        var c:Contact = p.internal;
                        var portView = createEdgePort(c, false, p.name);
                        portView.x = 0;
                        portView.y = leftStep * (leftIdx + 1);
                        _edgePortsContainer.addChild(portView);
                        _edgePorts.set(p.name, portView);
                        leftIdx++;
                }

                var rightIdx:Int = 0;
                for (p in rightPorts)
                {
                        var c:Contact = p.internal;
                        var portView = createEdgePort(c, true, p.name);
                        portView.x = w;
                        portView.y = rightStep * (rightIdx + 1);
                        _edgePortsContainer.addChild(portView);
                        _edgePorts.set(p.name, portView);
                        rightIdx++;
                }

                _wireRenderer.updateEdgeWires();
        }

        private function createEdgePort(contact:Contact, isInput:Bool, portName:String):Sprite
        {
                var s = new Sprite();
                s.graphics.beginFill(_theme.PORT_COLOR_DEFAULT);
                s.graphics.drawCircle(0, 0, 6);
                s.graphics.endFill();
                s.buttonMode = true;
                s.useHandCursor = true;
                s.name = portName;

                s.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
                {
                        e.stopPropagation();
                        var globalPos = s.localToGlobal(new Point(0, 0));
                        Impulsys.quickEmit(EventType.PORT_DRAG_START,
                        {
                                nodeId: "SELF",
                                contactName: portName,
                                isInput: isInput,
                                startX: globalPos.x,
                                startY: globalPos.y
                        });
                });

                s.addEventListener(MouseEvent.RIGHT_CLICK, function(e:MouseEvent)
                {
                        e.stopPropagation();
                        Impulsys.quickEmit(EventType.PORT_RIGHT_CLICKED,
                        {
                                portName: portName,
                                x: e.stageX,
                                y: e.stageY
                        });
                });

                return s;
        }

        // =========================================================================
        // NODE MANAGEMENT
        // =========================================================================
		private function restoreExistingAtoms():Void
		{
			if (_blueprint.internalAtoms == null) return;
			for (atomDef in _blueprint.internalAtoms)
			{
				var runtimeId = _assembly.idMap.get(atomDef.instanceId);
				if (runtimeId == null) runtimeId = atomDef.instanceId;
				var atomInstance = _assembly.internalAtoms.get(runtimeId);
				if (atomInstance != null)
				{
					// v3.9: Pass saved visual mode
					createViewForAtom(cast atomInstance, runtimeId, atomDef.x, atomDef.y, atomDef.visualMode);
				}
			}
		}

		private function createViewForAtom(atom:Atom, id:String, x:Float, y:Float, ?visualModeStr:String):Void
		{
			if (_nodes.exists(id)) return;
			var view:NodeView = new NodeView(atom, id);
			view.setPosition(x, y);
			view.setParentAssembly(_assembly);
			view.isNameTakenGlobally = _isNameTakenGlobally;
			
			var modeToRestore:String = null;
			
			if (visualModeStr != null && visualModeStr != "")
			{
				modeToRestore = visualModeStr;
				trace('createViewForAtom: using visualModeStr from AtomDef = "$modeToRestore"');
			}
			
			// ═══════════════════════════════════════════════════════════════
			// v3.9 FIX: Apply visualMode after creating view
			// ═══════════════════════════════════════════════════════════════
			if (modeToRestore != null && modeToRestore != "MEDIUM")
			{
				trace('createViewForAtom: applying visualMode "$modeToRestore" to view');
				view.setVisualModeFromString(modeToRestore);
			}
			else
			{
				trace('createViewForAtom: using default MEDIUM mode');
				view.setVisualMode(NodeVisualMode.MEDIUM);
			}
			
			_canvas.addChild(view);
			_nodes.set(id, view);
		}

        public function createAtom(typeId:String, posX:Float, posY:Float):Atom
        {
                var bp = AtomRegistry.get(typeId);
                if (bp == null) return null;
                var localPoint = _canvas.globalToLocal(new Point(posX, posY));
                _actions.createAtom(typeId, localPoint.x, localPoint.y);
                return null;
        }

        public function refreshAssemblyViews():Void
        {
                for (view in _nodes)
                {
                        if (Std.isOfType(view.atom, Assembly))
                        {
                                view.redraw();
                        }
                }
                _wireRenderer.rebuildAll();
        }

        /**
        * v4.6: Reattaches the NodeView for `atomId` to a new Atom instance.
        *
        * Called by EditorContext.updateInstancesOf() AFTER the old Assembly
        * has been disposed and replaced with a fresh one (same runtimeId).
        *
        * Without this, the existing NodeView would keep holding a reference
        * to the disposed Assembly. The first time createPorts() ran after a
        * mode switch (Editor → Device → Editor), atom.getInputs() returned
        * null and no ports were created, manifesting as "графика контактов
        * и названия контактов пропадают".
        *
        * @param atomId  Runtime ID of the atom (unchanged by reconstruction)
        * @param newAtom The freshly constructed Atom instance
        */
        public function reattachNodeView(atomId:String, newAtom:Atom):Void
        {
                trace('🔄 reattachNodeView: atomId="$atomId", newAtom.id="${newAtom.id}"');
                var view = _nodes.get(atomId);
                if (view == null)
                {
                        trace('❌ reattachNodeView: NO NodeView found for "$atomId"!');
                        trace('   Available keys: ${[for(k in _nodes.keys()) k]}');
                        return;
                }
                trace('✅ reattachNodeView: Found NodeView, calling reattachToAtom');
                view.reattachToAtom(newAtom);
                _wireRenderer.rebuildAll();
                trace('✅ reattachNodeView: rebuildAll completed');
        }

// =========================================================================
// FORCED REDRAW (v4.4)
// =========================================================================
        /**
        * Force complete visual refresh of the editor.
        *
        * Redraws ALL nodes, rebuilds ALL wires, and forces visibility update.
        * Call after:
        *   - Project load (to ensure wires and nodes are visible)
        *   - Mode switch from Device Panel back to Editor
        *   - Any situation where visuals might be stale
        *
        * v4.4: Added redraw of edge ports and stage invalidation.
        */
        public function forceFullRedraw():Void
        {
                utils.Trap.log("NE", "forceFullRedraw: nodes=" + Lambda.count(_nodes));
                if (isDisposed) return;

                // 1. Reset visibility throttle timer
                _lastVisibilityUpdate = 0;

                // 2. Redraw ALL node views (not just assemblies)
                for (view in _nodes)
                {
                        if (view != null)
                        {
                                view.visible = true;  // Force visible
                                view.redraw();
                        }
                }

                // 3. Rebuild ALL wires
                _wireRenderer.rebuildAll();

                // 4. Force visibility culling update
                updateVisibility();

                // 5. Update edge wires (assembly boundary connections)
                _wireRenderer.updateEdgeWires();

                // 6. Redraw edge ports (frame)
                drawFrame();

                // 7. Force stage redraw if available
                if (stage != null)
                {
                        stage.invalidate();
                }
        }

// =========================================================================
// WIDGET RESTORATION (v4.1 FIX)
// =========================================================================
        /**
        * Returns all DeviceViews from external containers (DevicePanel/Window)
        * back to their NodeViews.
        * Called by Main.hx when switching from Device Mode to Editor Mode.
        */
        public function restoreAllWidgets():Void
        {
                for (id in _nodes.keys())
                {
                        var view = _nodes.get(id);
                        if (view != null)
                        {
                                view.acceptWidget();
                        }
                }
        }

// =========================================================================
// SELECTION API (Delegation)
// =========================================================================
        public function deselectAll():Void
        {
                _selection.deselectAll();
                _wireRenderer.rebuildAll();
        }

        public function selectAll():Void
        {
                var allIds = [for (id in _nodes.keys()) id];
                _selection.selectAll(allIds);
        }

        public function selectNode(id:String, view:NodeView):Void _selection.selectNode(id, view);
        public function isSelected(nodeId:String):Bool return _selection.hasNode(nodeId);
        public function getSelectedNodeIds():Array<String> return _selection.getSelectedNodeIds();
        public function getSelectedNodeCount():Int return _selection.getSelectedNodeCount();
        public function getSelectedWireIds():Array<String> return _selection.getSelectedWireIds();
        public function clearWireSelection():Void {_selection.clearWires(); _wireRenderer.rebuildAll(); }

// =========================================================================
// CLIPBOARD API (Restored)
// =========================================================================
        public function copySelection():Void
        {
                _actions.copySelection(getSelectedNodeIds());
        }

        public function cutSelection():Void
        {
                _actions.cutSelection(getSelectedNodeIds());
                deselectAll();
        }

        public function pasteSelection():Void
        {
                var idMap = _actions.pasteSelection(25.0);
                if (idMap != null)
                {
                        deselectAll();
                        for (newId in idMap)
                        {
                                var view = _nodes.get(newId);
                                if (view != null)
                                {
                                        _selection.selectNode(newId, view);
                                }
                        }
                }
        }

// =========================================================================
// SELECTION EVENTS
// =========================================================================
        /**
        * Handle NODE_CLICKED event from NodeView.
        *
        * v3.4.2: Added support for null view/id to signal "deselect all".
        * This allows widgets to clear selection when clicked without selecting a node.
        *
        * @param impulse Contains {view:NodeView, id:String, ctrlKey:Bool} or {view:null, id:null}
        */
        private function onNodeClicked(impulse:Impulse):Void
        {
                if (impulse == null || impulse.data == null) return;

                // Dismiss context menu on any node interaction
                Impulsys.quickEmit(EventType.CLOSE_CONTEXT_MENU, null);

                var data = impulse.data;

                // === v3.4.2: Handle "deselect all" signal ===
                // When view/id is null, it means: "clear all selection, don't select anything"
                // This is emitted when user clicks on a widget/inline editor inside a node
                if (data.view == null || data.id == null)
                {
                        _selection.deselectAll();
                        _wireRenderer.rebuildAll();
                        return;
                }

                // === Normal behavior: handle node selection ===
                _selection.handleNodeClick(data.id, data.view, data.ctrlKey);
        }

        /**
        * Handle MOUSE_DOWN on canvas background.
        * Initiates lasso selection (rectangle selection of multiple nodes).
        *
        * @param e Mouse event from _canvas
        */
        private function onCanvasMouseDown(e:MouseEvent):Void
        {
                var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
                _selection.handleCanvasMouseDown(local.x, local.y);
                // =====================================================================
                // FIX: Clear TextField focus when clicking empty canvas.
                // Ensures lasso selection and subsequent shortcuts work correctly.
                // =====================================================================
                if (stage != null) stage.focus = null;
        }

        /**
        * Handle RIGHT_CLICK on canvas background.
        * Opens context menu for adding atoms.
        *
        * v4.3: Clears ALL selection before showing menu.
        * Right-click on empty canvas = user wants to add new atom,
        * not work with currently selected objects.
        */
        private function onCanvasRightClick(e:MouseEvent):Void
        {
                e.stopPropagation();

                // === v4.3: Clear all selection (nodes + wires) ===
                _selection.deselectAll();
                _wireRenderer.rebuildAll();

                Impulsys.quickEmit(EventType.CANVAS_RIGHT_CLICKED, {
                        x: e.stageX,
                        y: e.stageY
                });
        }
		
		/**
		 * v2.0: Handle global visual mode change.
		 * Iterates through all NodeViews and updates their visualization mode.
		 */
		private function onVisualModeChanged(impulse:Impulse):Void {
			if (impulse == null || impulse.data == null || impulse.data.mode == null) return;
			var mode:NodeVisualMode = impulse.data.mode;
			
			for (view in _nodes) {
				if (view != null) {
					view.setVisualMode(mode);
				}
			}
			// Force wire redraw to adapt to new port positions
			_wireRenderer.rebuildAll();
		}

// =========================================================================
// HIT LAYER HANDLERS (v5.0 — Desktop mouse + Android touch)
// =========================================================================

        /**
        * MOUSE_DOWN on the glass pane.
        * Desktop: starts lasso selection on the canvas background.
        * Android: skipped when a touch gesture is already tracked (TouchEvent
        * handles it to avoid double-processing synthetic mouse events).
        */
        private function onHitLayerMouseDown(e:MouseEvent):Void
        {
                // Android: if a real touch is driving, ignore synthetic mouse
                if (_singleTouchActive) return;
                // ViewportManager is doing 2-finger pan/zoom
                if (_viewport.isViewportActive()) return;

                // Dismiss context menu immediately on any click
                Impulsys.quickEmit(EventType.CLOSE_CONTEXT_MENU, null);

                // Clear selection immediately on canvas click
                _selection.deselectAll();
                _wireRenderer.rebuildAll();

                var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
                _selection.handleCanvasMouseDown(local.x, local.y);

                if (stage != null) stage.focus = null;
        }

        /**
        * RIGHT_CLICK on the glass pane.
        * Desktop: opens the atom-add context menu.
        * Android: unused (long-press fires CANVAS_RIGHT_CLICKED instead).
        */
        private function onHitLayerRightClick(e:MouseEvent):Void
        {
                e.stopPropagation();

                Impulsys.quickEmit(EventType.CLOSE_CONTEXT_MENU, null);

                _selection.deselectAll();
                _wireRenderer.rebuildAll();

                Impulsys.quickEmit(EventType.CANVAS_RIGHT_CLICKED, {
                        x: e.stageX,
                        y: e.stageY
                });
        }

        /**
        * TOUCH_BEGIN on the glass pane — 1-finger gesture entry point (Android).
        *
        * ViewportManager already received this event (same target, earlier listener).
        * For 1 finger it does NOT call stopImmediatePropagation, so we get here.
        * For 2+ fingers VM blocks the event — we never see it.
        *
        * Rules handled:
        *   4 — 1 finger on bg + move  → lasso   (started on first TOUCH_MOVE)
        *   5 — 1 finger on bg + hold  → context menu (via 2 s timer)
        */
        private function onHitLayerTouchBegin(e:TouchEvent):Void
        {
                // ViewportManager is doing 2-finger pan/zoom — stay out
                if (_viewport.isViewportActive()) return;

                // Dismiss context menu + clear selection immediately on touch
                Impulsys.quickEmit(EventType.CLOSE_CONTEXT_MENU, null);
                _selection.deselectAll();
                _wireRenderer.rebuildAll();

                _singleTouchActive = true;
                _touchStartX = e.stageX;
                _touchStartY = e.stageY;
                _touchMoved = false;
                _longPressFired = false;

                // Start 2-second long-press timer (rule 5)
                _cancelLongPress();
                var sx = e.stageX;
                var sy = e.stageY;
                _longPressTimer = haxe.Timer.delay(function():Void {
                        if (isDisposed || !_singleTouchActive) return;
                        if (_viewport.isViewportActive()) { _cancelTouchGesture(); return; }
                        _longPressFired = true;
                        // Cancel any in-progress lasso before showing menu
                        if (_selection.isLassoing()) {
                                _selection.handleMouseUp();
                                _wireRenderer.rebuildAll();
                        }
                        Impulsys.quickEmit(EventType.CANVAS_RIGHT_CLICKED, { x: sx, y: sy });
                }, 2000);
        }

        /**
        * TOUCH_MOVE on the glass pane — drive lasso or cancel long-press.
        *
        * If the viewport becomes active (2nd finger arrived), we abort our
        * 1-finger gesture and let ViewportManager take over.
        */
        private function onHitLayerTouchMove(e:TouchEvent):Void
        {
                if (!_singleTouchActive) return;

                // ViewportManager grabbed control (2nd finger) — abort
                if (_viewport.isViewportActive()) {
                        _cancelTouchGesture();
                        return;
                }

                // Check dead-zone for long-press cancellation
                if (!_touchMoved) {
                        var dx = e.stageX - _touchStartX;
                        var dy = e.stageY - _touchStartY;
                        if (dx * dx + dy * dy > LONG_PRESS_DEAD_ZONE_SQ) {
                                _touchMoved = true;
                                _cancelLongPress();
                        }
                }

                // Drive lasso (rule 4)
                if (_touchMoved && !_longPressFired) {
                        var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
                        if (!_selection.isLassoing()) {
                                _selection.handleCanvasMouseDown(local.x, local.y);
                        }
                        _selection.handleMouseMove(local.x, local.y);
                }
        }

        /**
        * TOUCH_END on the glass pane — finalize lasso or cancel gesture.
        */
        private function onHitLayerTouchEnd(e:TouchEvent):Void
        {
                if (!_singleTouchActive) return;

                if (_viewport.isViewportActive()) {
                        _cancelTouchGesture();
                        return;
                }

                if (_selection.isLassoing()) {
                        _selection.handleMouseUp();
                        _autoSelectWires();
                        _wireRenderer.rebuildAll();
                }

                _cancelTouchGesture();
        }

        /**
         * Auto-select wires that connect currently-selected nodes.
         * Called after lasso finalization (both mouse and touch paths).
         */
        private function _autoSelectWires():Void
        {
                if (_selection.getSelectedNodeCount() < 2) return;
                var wireIds = _selection.findWiresBetweenSelectedNodes();
                if (wireIds.length > 0)
                {
                        _selection.setWires(wireIds);
                }
        }

        /**
        * Cancel the long-press timer (if running).
        */
        private function _cancelLongPress():Void
        {
                if (_longPressTimer != null) {
                        _longPressTimer.stop();
                        _longPressTimer = null;
                }
        }

        /**
        * Cancel the entire 1-finger touch gesture (timer + state).
        */
        private function _cancelTouchGesture():Void
        {
                _cancelLongPress();
                _singleTouchActive = false;
                _touchMoved = false;
                _longPressFired = false;
        }

// =========================================================================
// MOUSE MOVE
// =========================================================================
        private function onMouseMove(e:MouseEvent):Void
        {
                // Android: synthetic mouse from touch — drive lasso as fallback
                // (TOUCH_MOVE on _hitLayer may not fire on some Android WebGL configs;
                //  synthetic MOUSE_MOVE on stage always fires, so use it as belt-and-suspenders)
                if (_singleTouchActive) {
                        if (_viewport.isViewportActive()) { _cancelTouchGesture(); return; }

                        // Check dead-zone for long-press cancellation
                        if (!_touchMoved) {
                                var dx = e.stageX - _touchStartX;
                                var dy = e.stageY - _touchStartY;
                                if (dx * dx + dy * dy > LONG_PRESS_DEAD_ZONE_SQ) {
                                        _touchMoved = true;
                                        _cancelLongPress();
                                }
                        }

                        // Drive lasso (rule 4)
                        if (_touchMoved && !_longPressFired) {
                                var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
                                if (!_selection.isLassoing()) {
                                        _selection.handleCanvasMouseDown(local.x, local.y);
                                }
                                _selection.handleMouseMove(local.x, local.y);
                        }
                        return;
                }

                if (_viewport.isPanning())
                {
                        _viewport.handlePanMove(e.stageX, e.stageY);
                        _wireRenderer.updateEdgeWires();
                        updateVisibility();
                        return;
                }

                if (_isDraggingPort)
                {
                        _wireRenderer.drawGhostWire(_dragStartX, _dragStartY, e.stageX, e.stageY, _dragStartIsInput);
                        return;
                }

                if (_selection.isLassoing())
                {
                        var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
                        _selection.handleMouseMove(local.x, local.y);
                }
        }

// =========================================================================
// MOUSE UP
// =========================================================================
        private function onMouseUp(e:MouseEvent):Void
        {
                // Android: touch is driving — finalize lasso as fallback
                if (_singleTouchActive) {
                        if (_selection.isLassoing()) {
                                _selection.handleMouseUp();
                                _autoSelectWires();
                                _wireRenderer.rebuildAll();
                        }
                        _cancelTouchGesture();
                        return;
                }

                if (_viewport.isPanning())
                {
                        _viewport.handlePanEnd();
                        _wireRenderer.rebuildAll();
                        updateVisibility();
                        return;
                }

                if (_isDraggingPort)
                {
                        handleWireDragEnd(e);
                        return;
                }

                if (_selection.isLassoing())
                {
                        _selection.handleMouseUp();
                        _autoSelectWires();
                        // After lasso/click on empty space, redraw wires
                        // because selection may have been reset.
                        _wireRenderer.rebuildAll();
                }
        }

        private function handleWireDragEnd(e:MouseEvent):Void
        {
                var target = findPortAt(e.stageX, e.stageY);
                if (target != null)
                {
                        var isSameContact = (_dragNodeId == target.nodeId && _dragContactName == target.contactName);
                        var startIsSource = !_dragStartIsInput;
                        var targetIsSource = !target.isInput;

                        if (!isSameContact && (startIsSource != targetIsSource))
                        {
                                var realFromId:String; var realFromContact:String;
                                var realToId:String; var realToContact:String;

                                if (startIsSource)
                                {
                                        realFromId = _dragNodeId; realFromContact = _dragContactName;
                                        realToId = target.nodeId; realToContact = target.contactName;
                                }
                                else
                                {
                                        realFromId = target.nodeId; realFromContact = target.contactName;
                                        realToId = _dragNodeId; realToContact = _dragContactName;
                                }

                                _actions.connect(realFromId, realFromContact, realToId, realToContact);
                                _wireRenderer.rebuildAll();
                        }
                }

                _isDraggingPort = false;
                _wireRenderer.clearGhostWire();
        }

// =========================================================================
// NODE DRAG
// =========================================================================
        private function onNodeMoved(impulse:Impulse):Void
        {
                var sourceView:NodeView = impulse.data.view;
                var dx:Float = impulse.data.dx;
                var dy:Float = impulse.data.dy;

                // 1. Initialization (first frame of dragging)
                if (_draggingNode == null)
                {
                        _draggingNode = sourceView;
                        _dragStartPositions = new Map();

                        // === FIX: Determine drag type ===
                        var isMovingGroup = _selection.hasNode(sourceView.nodeId);
                        var nodesToMove:Array<String> = [];

                        if (isMovingGroup)
                        {
                                // Moving group: take all selected
                                nodesToMove = _selection.getSelectedNodeIds();
                        }
                        else
                        {
                                // Moving solo: take only current node
                                nodesToMove = [sourceView.nodeId];
                        }

                        // Tell renderer to track these wires
                        _wireRenderer.setActiveWiresForNodes(nodesToMove);

                        // Save start positions for Undo
                        for (id in nodesToMove)
                        {
                                var v = _nodes.get(id);
                                if (v != null) _dragStartPositions.set(id, {x: v.x, y: v.y});
                        }
                }

                // 2. Movement
                // SourceView moves itself in NodeView.onMouseMoveDrag.
                // Here we move "the rest".
                if (_selection.hasNode(sourceView.nodeId))
                {
                        // This is group dragging. Move everyone except source.
                        for (id in _selection.getSelectedNodeIds())
                        {
                                if (id == sourceView.nodeId) continue; // Source already moved
                                var view = _nodes.get(id);
                                if (view != null)
                                {
                                        view.x += dx;
                                        view.y += dy;
                                        ECS.updatePosition(id, view.x, view.y);
                                }
                        }
                }

                // If this was Single Drag (node not selected), no one else needs to move.

                // 3. Update wire visuals
                _wireRenderer.updateActiveWires();
                _wireRenderer.updateEdgeWires();
        }

        private function onNodeDragFinished(impulse:Impulse):Void
        {
                var moves:Array<{id:String, fromX:Float, fromY:Float, toX:Float, toY:Float}> = [];

                if (_dragStartPositions != null)
                {
                        for (id in _dragStartPositions.keys())
                        {
                                var startPos = _dragStartPositions.get(id);
                                var view = _nodes.get(id);
                                if (view != null)
                                {
                                        var templateId = _assembly.getTemplateId(id);
                                        moves.push({id: templateId, fromX: startPos.x, fromY: startPos.y, toX: view.x, toY: view.y});

                                        // Save to Blueprint
                                        for (atom in _blueprint.internalAtoms)
                                        {
                                                if (atom.instanceId == templateId)
                                                {
                                                        atom.x = view.x;
                                                        atom.y = view.y;
                                                        break;
                                                }
                                        }
                                }
                        }
                }

                if (moves.length > 0) _actions.moveAtoms(moves);

                _wireRenderer.clearActiveWires();
                _draggingNode = null;
                _dragStartPositions = null;

                _wireRenderer.rebuildAll();
        }

// =========================================================================
// VIEWPORT
// =========================================================================
        public function getViewState(): {x:Float, y:Float, zoom:Float} return _viewport.getViewState();

        public function setViewState(state: {x:Float, y:Float, zoom:Float}):Void
        {
                _viewport.setViewState(state);
                updateVisibility();
        }

        private function onMiddleMouseDown(e:MouseEvent):Void _viewport.handlePanStart(e.stageX, e.stageY);

        private function onMiddleMouseUp(e:MouseEvent):Void
        {
                if (_viewport.isPanning())
                {
                        _viewport.handlePanEnd();
                        _wireRenderer.rebuildAll();
                        updateVisibility();
                }
        }

        private function onMouseWheel(e:MouseEvent):Void
        {
                utils.Trap.log("ZOOM", "wheel: delta=" + e.delta + " canvas.scaleX=" + _canvas.scaleX);
                _viewport.handleZoom(e.delta, e.stageX, e.stageY, this);
                // НЕ вызываем _wireRenderer.rebuildAll(); здесь — провода масштабируются 
                // автоматически вместе с canvas. Перерисуем после зума.
                updateVisibility();
        }

        private function updateVisibility():Void
        {
                var w = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
                var h = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);
                _viewport.updateVisibility(_nodes.iterator(), w, h);
        }

// =========================================================================
// v1.2: AUTO-CENTER VIEWPORT ON CONTENT
// =========================================================================
        /**
        * Automatically centers the viewport so that all internal atoms and ports
        * are visible with a comfortable margin.
        *
        * This is called when entering an assembly for the first time, or when
        * the user requests a reset view (e.g., via a shortcut).
        *
        * Algorithm:
        * 1. Iterate over all NodeViews in _nodes.
        * 2. Compute their bounding box (including port positions).
        * 3. Add the assembly's edge ports (SELF) to the bounding box.
        * 4. If no nodes exist, center on (0,0) with zoom=1.0.
        * 5. Calculate required zoom to fit everything in view (with margin).
        * 6. Center the viewport on the middle of the bounding box.
        */
        public function centerOnContent():Void
        {
                // 1. Collect all node positions and sizes
                var minX:Float = 0, minY:Float = 0, maxX:Float = 0, maxY:Float = 0;
                var hasNodes = false;

                for (view in _nodes)
                {
                        if (view == null) continue;
                        var size = view.getNodeSize();
                        var x = view.x;
                        var y = view.y;

                        // Include port positions (extend bounding box)
                        var nodeMinX = x;
                        var nodeMinY = y;
                        var nodeMaxX = x + size.width;
                        var nodeMaxY = y + size.height;

                        // Also check input/output port positions (they may extend beyond node bounds)
                        for (port in view.inputPorts)
                        {
                                if (port == null) continue;
                                var globalPos = port.localToGlobal(new openfl.geom.Point(0, 0));
                                var localPos = _canvas.globalToLocal(globalPos);
                                if (localPos.x < nodeMinX) nodeMinX = localPos.x;
                                if (localPos.y < nodeMinY) nodeMinY = localPos.y;
                                if (localPos.x > nodeMaxX) nodeMaxX = localPos.x;
                                if (localPos.y > nodeMaxY) nodeMaxY = localPos.y;
                        }
                        for (port in view.outputPorts)
                        {
                                if (port == null) continue;
                                var globalPos = port.localToGlobal(new openfl.geom.Point(0, 0));
                                var localPos = _canvas.globalToLocal(globalPos);
                                if (localPos.x < nodeMinX) nodeMinX = localPos.x;
                                if (localPos.y < nodeMinY) nodeMinY = localPos.y;
                                if (localPos.x > nodeMaxX) nodeMaxX = localPos.x;
                                if (localPos.y > nodeMaxY) nodeMaxY = localPos.y;
                        }

                        if (!hasNodes)
                        {
                                minX = nodeMinX; minY = nodeMinY;
                                maxX = nodeMaxX; maxY = nodeMaxY;
                                hasNodes = true;
                        }
                        else
                        {
                                if (nodeMinX < minX) minX = nodeMinX;
                                if (nodeMinY < minY) minY = nodeMinY;
                                if (nodeMaxX > maxX) maxX = nodeMaxX;
                                if (nodeMaxY > maxY) maxY = nodeMaxY;
                        }
                }

                // 2. Also include edge ports (SELF) from assembly frame
                // The frame is drawn on _frame sprite, but its coordinates are in _canvas space
                if (_frame != null)
                {
                        var frameBounds = _frame.getBounds(_canvas);
                        if (frameBounds != null && frameBounds.width > 0 && frameBounds.height > 0)
                        {
                                if (!hasNodes)
                                {
                                        minX = frameBounds.x; minY = frameBounds.y;
                                        maxX = frameBounds.x + frameBounds.width;
                                        maxY = frameBounds.y + frameBounds.height;
                                        hasNodes = true;
                                }
                                else
                                {
                                        if (frameBounds.x < minX) minX = frameBounds.x;
                                        if (frameBounds.y < minY) minY = frameBounds.y;
                                        if (frameBounds.x + frameBounds.width > maxX) maxX = frameBounds.x + frameBounds.width;
                                        if (frameBounds.y + frameBounds.height > maxY) maxY = frameBounds.y + frameBounds.height;
                                }
                        }
                }

                // 3. If no nodes or ports, center on (0,0)
                if (!hasNodes)
                {
                        _viewport.setViewState({x: 0, y: 0, zoom: 1.0});
                        return;
                }

                // 4. Add margin (10% of viewport size, but at least 50 pixels)
                var margin = 50.0;
                var viewWidth = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
                var viewHeight = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);
                var marginX = Math.max(margin, viewWidth * 0.1);
                var marginY = Math.max(margin, viewHeight * 0.1);

                var contentWidth = maxX - minX;
                var contentHeight = maxY - minY;
                if (contentWidth < 1) contentWidth = 1;
                if (contentHeight < 1) contentHeight = 1;

                // 5. Calculate required zoom to fit content with margins
                var zoomX = (viewWidth - marginX * 2) / contentWidth;
                var zoomY = (viewHeight - marginY * 2) / contentHeight;
                var zoom = Math.min(zoomX, zoomY);
                // Clamp zoom to reasonable range
                if (zoom < 0.1) zoom = 0.1;
                if (zoom > 3.0) zoom = 3.0;

                // 6. Calculate center position in canvas coordinates
                var centerX = (minX + maxX) / 2;
                var centerY = (minY + maxY) / 2;

                // 7. Set viewport so that the center is in the middle of the view
                // We need to set _canvas.x and _canvas.y such that the point (centerX, centerY)
                // in canvas space maps to the center of the visible area.
                // The visible center in world coordinates is ( -_canvas.x / _canvas.scaleX + viewWidth/2, ... )
                // We want: centerX = -_canvas.x / zoom + viewWidth/2
                // => _canvas.x = -(centerX - viewWidth/2) * zoom
                // => _canvas.x = (viewWidth/2 - centerX) * zoom
                var targetX = (viewWidth / 2 - centerX) * zoom;
                var targetY = (viewHeight / 2 - centerY) * zoom;

                // Apply
                _canvas.scaleX = zoom;
                _canvas.scaleY = zoom;
                _canvas.x = targetX;
                _canvas.y = targetY;

                // Force redraw
                _wireRenderer.rebuildAll();
                updateVisibility();

                trace('NodeEditor: Auto-centered on content (zoom=$zoom)');
        }

// =========================================================================
// DELETE
// =========================================================================
        public function deleteSelectedNodes():Array<String>
        {
                var ids = _selection.getSelectedNodeIds();
                _actions.deleteAtoms(ids);
                return ids;
        }

        public function deleteSelectedWires():Void
        {
                var ids = _selection.getSelectedWireIds();
                if (ids.length == 0) return;
                _actions.deleteWires(ids);
                _selection.deselectAll();
                _wireRenderer.rebuildAll();
        }

// =========================================================================
// PORT DRAG START
// =========================================================================
        private function onPortDragStart(impulse:Impulse):Void
        {
                _isDraggingPort = true;
                _dragNodeId = impulse.data.nodeId;
                _dragContactName = impulse.data.contactName;
                _dragStartX = impulse.data.startX;
                _dragStartY = impulse.data.startY;
                _dragStartIsInput = impulse.data.isInput;
        }

// =========================================================================
// EVENTS
// =========================================================================
        private function onAtomDeleted(impulse:Impulse):Void
        {
                if (impulse.data.assemblyId != _assembly.id) return;
                var id:String = impulse.data.id;
                var view = _nodes.get(id);
                if (view != null)
                {
                        view.dispose();
                        if (view.parent == _canvas) _canvas.removeChild(view);
                        _nodes.remove(id);
                        _wireRenderer.rebuildAll();
                }
        }

        private function onAtomRestored(impulse:Impulse):Void
        {
                if (impulse.data.assemblyId != _assembly.id) return;
                var id:String = impulse.data.id;
                var x:Float = impulse.data.x;
                var y:Float = impulse.data.y;
                var atom:Atom = impulse.data.atom;

                if (atom != null)
                {
                        createViewForAtom(atom, id, x, y);
                        _wireRenderer.rebuildAll();
                }
        }

        private function onForceUpdatePosition(impulse:Impulse):Void
        {
                var data = impulse.data;
                var view = _nodes.get(data.id);
                if (view != null)
                {
                        if (view.x != data.x || view.y != data.y)
                        {
                                view.setPosition(data.x, data.y);
                                _wireRenderer.rebuildAll();
                        }
                }
        }

// =========================================================================
// HELPERS
// =========================================================================
        public function getNodeViewById(id:String):NodeView return _nodes.get(id);
        private function getEdgePortById(name:String):Sprite return _edgePorts.get(name);

        private function findPortAt(x:Float, y:Float): {nodeId:String, contactName:String, isInput:Bool}
        {
                // Edge Ports
                for (name in _edgePorts.keys())
                {
                        var port = _edgePorts.get(name);
                        var local = port.globalToLocal(new Point(x, y));
                        if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10)
                        {
                                var asmPort = _assembly.ports.get(name);
                                var isInput:Bool = (asmPort.type != INPUT);
                                return { nodeId: "SELF", contactName: name, isInput: isInput };
                        }
                }

                // Node Ports
                for (nodeId in _nodes.keys())
                {
                        var view = _nodes.get(nodeId);
                        if (view != null)
                        {
                                for (name in view.inputPorts.keys())
                                {
                                        var port = view.inputPorts.get(name);
                                        if (port != null)
                                        {
                                                var local = port.globalToLocal(new Point(x, y));
                                                if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) return {nodeId: nodeId, contactName: name, isInput: true};
                                        }
                                }
                                for (name in view.outputPorts.keys())
                                {
                                        var port = view.outputPorts.get(name);
                                        if (port != null)
                                        {
                                                var local = port.globalToLocal(new Point(x, y));
                                                if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) return {nodeId: nodeId, contactName: name, isInput: false};
                                        }
                                }
                        }
                }
                return null;
        }

// =========================================================================
// PROPERTIES & SETTINGS DELEGATION (v4.2 FIX)
// =========================================================================
        public function setSize(w:Float, h:Float):Void
        {
                _forcedWidth = w;
                _forcedHeight = h;
                drawFrame();
        }

        /**
        * ECS rendering toggle.
        * Currently a phantom feature (stub) in the architecture,
        * but kept for API consistency with SettingsPanel.
        */
        public function setUseEcsRender(v:Bool):Void
        {
                // Intentionally empty: ECS rendering is managed globally via ECS facade,
                // not per-editor instance in the current hybrid architecture.
        }

        /**
        * v4.2 FIX: Forward wire type settings to the WireRenderer.
        * The WireRenderer's setter automatically triggers rebuildAll()
        * to redraw all connections with the new geometry algorithm.
        */
        public function setWireType(v:ui.WireType):Void
        {
                if (_wireRenderer != null)
                {
                        _wireRenderer.wireType = v;
                }
        }

        /**
        * Assembly creation/editing permission toggle.
        * Handled directly via SettingsPanel state in Main/ContextMenuManager,
        * so no local state needs to be updated in NodeEditor.
        */
        public function setAllowAssembly(v:Bool):Void
        {
                // Intentionally empty: ContextMenuManager reads _settingsPanel.allowAssembly directly.
        }

        public function getNodeCount():Int
        {
                var c = 0;
                for (id in _nodes.keys()) c++;
                return c;
        }

        public function getWireCount():Int
        {
                return _wireRenderer.getWireCount();
        }

// =========================================================================
// DISPOSE
// =========================================================================
        public function dispose():Void
        {
                utils.Trap.log("NE-DISPOSE", "editor down: " + (_blueprint != null ? _blueprint.id : "?"));
                if (isDisposed) return;
                isDisposed = true;

                if (stage != null)
                {
                        stage.removeEventListener(Event.RESIZE, onResize);
                        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
                        stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
                        stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
                        stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
                        stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                }

                // v5.0: Remove glass-pane listeners
                if (_hitLayer != null)
                {
                        _hitLayer.removeEventListener(MouseEvent.MOUSE_DOWN, onHitLayerMouseDown);
                        _hitLayer.removeEventListener(MouseEvent.RIGHT_CLICK, onHitLayerRightClick);
                        _hitLayer.removeEventListener(TouchEvent.TOUCH_BEGIN, onHitLayerTouchBegin);
                        _hitLayer.removeEventListener(TouchEvent.TOUCH_MOVE, onHitLayerTouchMove);
                        _hitLayer.removeEventListener(TouchEvent.TOUCH_END, onHitLayerTouchEnd);
                }

                // v5.0: Cancel any active touch gesture
                _cancelTouchGesture();

                // v4.5: Unsubscribe the EXACT same references we subscribed with.
                Impulsys.removeImpulse(EventType.PORT_DRAG_START, _onPortDragStart);
                Impulsys.removeImpulse(EventType.EDITOR_NODE_MOVED, _onNodeMoved);
                Impulsys.removeImpulse(EventType.NODE_DRAG_FINISHED, _onNodeDragFinished);
                Impulsys.removeImpulse(EventType.FORCE_UPDATE_NODE_POSITION, _onForceUpdatePosition);
                Impulsys.removeImpulse(EventType.REDRAW_WIRES, _onRedrawWires);
                Impulsys.removeImpulse(EventType.ASSEMBLY_PORTS_CHANGED, _onAssemblyPortsChanged);
                Impulsys.removeImpulse(EventType.ATOM_DELETED, _onAtomDeleted);
                Impulsys.removeImpulse(EventType.ATOM_RESTORED, _onAtomRestored);
                Impulsys.removeImpulse(EventType.NODE_CLICKED, _onNodeClicked);
				Impulsys.removeImpulse(EventType.NODE_VISUAL_MODE_CHANGED, onVisualModeChanged);

                // v4.5: Release closure references
                _onPortDragStart = null;
                _onNodeMoved = null;
                _onNodeDragFinished = null;
                _onForceUpdatePosition = null;
                _onRedrawWires = null;
                _onAssemblyPortsChanged = null;
                _onAtomDeleted = null;
                _onAtomRestored = null;
                _onNodeClicked = null;

                _selection.dispose();
                _wireRenderer.dispose();

                for (view in _nodes)
                {
                        view.dispose();
                }

                for (nodeId in _nodes.keys()) ECS.unregister(nodeId);

                _nodes.clear();
        }
}