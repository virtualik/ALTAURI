package Application.Windows.Components {
    import flash.display.Sprite;
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import flash.events.Event;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.Commands.AtomLinker.AddAtomCommand;
    import Application.Managers.AtomManager;
    import Application.Managers.DataManager;
    import Application.AtomLinker.Services.AtomFactory;
    import Application.Managers.ConnectionManager;
    import Application.AtomLinker.Core.Track;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.AtomLinker.View.IAtomView;
    import Application.AtomLinker.Core.Pin;

    /**
     * Editor Window Content - main editor workspace management
     * Handles editor canvas, atom management, and user interaction
     */
    public class EditorWindowContent {
        private var _container:Sprite;
        private var _drawingSurface:DrawingSurface;
        private var _viewPointPosition:Point = new Point(0, 0);
        private var _zoomLevel:Number = 0.1;
        private var _zoomStep:Number = 0.1;
        private var _zoomMin:Number = 0.4;
        private var _zoomMax:Number = 1.0;
        private var _isDragging:Boolean = false;
        private var _lastMousePos:Point = new Point();
        private var _stage:flash.display.Stage;
        private var _connectionManager:ConnectionManager;

        /**
         * Editor Content constructor
         * @param container - graphic container
         * @param stage - window stage
         */
        public function EditorWindowContent(container:Sprite, stage:flash.display.Stage) {
            _container = container;
            _stage = stage;

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "EditorWindowContent",
                message: "ℹ️ Initializing editor content"
            }));

            initialize();
            _connectionManager = ConnectionManager.getInstance();
            setupMouseListeners();

            MultiPulsator.subscribeToImpulse("ADD_TO_EDITOR", onAddToEditor);
            MultiPulsator.subscribeToImpulse("ADD_TRACK_TO_EDITOR", onAddTrackToEditor);
            MultiPulsator.subscribeToImpulse("ATOM_UPDATED", onAtomUpdated);
            MultiPulsator.subscribeToImpulse("TRACK_REMOVED", onTrackRemoved);
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);
        }

        /**
         * Set up mouse event listeners
         */
        private function setupMouseListeners():void {
            _stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }

        /**
         * Handle mouse move events
         */
        private function onMouseMove(e:MouseEvent):void {
            var localMousePos:Point = _drawingSurface.globalToLocal(new Point(e.stageX, e.stageY));
            MultiPulsator.emit(new Impulse("EDITOR_MOUSE_MOVE", {
                mousePos: localMousePos
            }));
        }

        /**
         * Handle mouse up events
         */
        private function onMouseUp(e:MouseEvent):void {
            MultiPulsator.emit(new Impulse("EDITOR_MOUSE_UP", {
                mousePos: new Point(e.stageX, e.stageY)
            }));
        }

        /**
         * Handle atom movement
         */
        private function onAtomMoved(impulse:Impulse):void {
            var atom:BaseAtom = impulse.data.atom as BaseAtom;
            if (atom) {
                updateTracksForAtom(atom);

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "DEBUG",
                    source: "EditorWindowContent",
                    message: "🐛 Updated tracks for atom " + atom.name
                }));
            }
        }

        /**
         * Update tracks for moved atom
         */
        private function updateTracksForAtom(atom:BaseAtom):void {
            var connectionManager:ConnectionManager = ConnectionManager.getInstance();
            if (!connectionManager) return;

            var allPins:Vector.<Pin> = atom.getAllContacts();

            for each (var pin:Pin in allPins) {
                var tracks:Array = connectionManager.getTracksByPin(pin);
                for each (var track:Track in tracks) {
                    track.update();
                }
            }
        }

        /**
         * Initialize editor content
         */
        private function initialize():void {
            _drawingSurface = new DrawingSurface();
            _drawingSurface.name = "Face";
            _container.addChild(_drawingSurface);
            _drawingSurface.mouseEnabled = false;
            _drawingSurface.mouseChildren = true;

            centerDrawingSurface();
            _stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            _stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            _stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            _stage.addEventListener(Event.MOUSE_LEAVE, handleMouseLeave);
            _stage.addEventListener(Event.RESIZE, onResize);
            subscribeToAtomEvents();
        }

        /**
         * Subscribe to atom-related events
         */
        private function subscribeToAtomEvents():void {
            MultiPulsator.subscribeToImpulse("ATOM_CREATED", onAtomCreated);
            MultiPulsator.subscribeToImpulse("APP_STARTUP_COMPLETE", onAppStartupComplete);
        }

        /**
         * Handle app startup completion
         */
        private function onAppStartupComplete(impulse:Impulse):void {
            var atomManager:AtomManager = DataManager.getData(AtomManager.DATA_MANAGER_KEY) as AtomManager;
            if(!atomManager) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "ERROR",
                    source: "EditorWindowContent",
                    message: "❌ AtomManager not found!"
                }));
                return;
            }

            var atomsToCreate:Array = [{
                type: "Button",
                pos: new Point(-550, -300),
                name: "My Button"
            }, {
                type: "Counter",
                pos: new Point(-400, -300),
                name: "My Counter"
            }, {
                type: "NumberDisplay",
                pos: new Point(-200, -300),
                name: "My Display"
            }, {
                type: "TestType",
                pos: new Point(0, 0),
                name: "Test Atom"
            }];

            for each(var atomParams:Object in atomsToCreate) {
                var newAtom:BaseAtom = AtomFactory.createAtom(
                    atomParams.type,
                    atomParams.pos,
                    atomParams.name
                );

                if(!newAtom) {
                    MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                        level: "ERROR",
                        source: "EditorWindowContent",
                        message: "❌ Failed to create atom type: " + atomParams.type
                    }));
                    continue;
                }

                var addAtomCmd:AddAtomCommand = new AddAtomCommand(atomManager, newAtom);
                addAtomCmd.execute();

                if(newAtom.displayObject && _drawingSurface) {
                    newAtom.displayObject.x = newAtom.position.x;
                    newAtom.displayObject.y = newAtom.position.y;
                    _drawingSurface.getDynamicBackFace().addChild(newAtom.displayObject);

                    MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                        level: "INFO",
                        source: "EditorWindowContent",
                        message: "ℹ️ Atom created: " + newAtom.name + " at position " + newAtom.position
                    }));
                }
            }
        }

        /**
         * Handle atom creation
         */
        private function onAtomCreated(impulse:Impulse):void {
            if(impulse && impulse.data && impulse.data.atom) {
                var atom:BaseAtom = impulse.data.atom as BaseAtom;

                if(atom && atom.displayObject && !_drawingSurface.getDynamicBackFace().contains(atom.displayObject)) {
                    try {
                        atom.displayObject.x = atom.position.x;
                        atom.displayObject.y = atom.position.y;
                        _drawingSurface.getDynamicBackFace().addChild(atom.displayObject);

                        MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                            level: "INFO",
                            source: "EditorWindowContent",
                            message: "ℹ️ Atom added to canvas: " + atom.name
                        }));
                    }
                    catch(error:Error) {
                        MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                            level: "ERROR",
                            source: "EditorWindowContent",
                            message: "❌ Error adding atom: " + error.message
                        }));
                    }
                }
            }
        }

        /**
         * Handle atom updates
         */
        private function onAtomUpdated(impulse:Impulse):void {
            if (impulse && impulse.data && impulse.data.newAtom) {
                var newAtom:BaseAtom = impulse.data.newAtom as BaseAtom;
                if (newAtom && newAtom.displayObject) {
                    newAtom.displayObject.x = newAtom.position.x;
                    newAtom.displayObject.y = newAtom.position.y;

                    if (newAtom.displayObject is IAtomView) {
                        var atomView:IAtomView = newAtom.displayObject as IAtomView;
                        atomView.updateVisuals();

                        var atomManager:AtomManager = AtomManager.getInstance();
                        if (atomManager) {
                            atomManager.updateAtom(newAtom);
                        }

                        MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                            level: "INFO",
                            source: "EditorWindowContent",
                            message: "Atom updated: " + newAtom.name
                        }));
                    }
                }
            }
        }

        /**
         * Handle track removal
         */
        private function onTrackRemoved(impulse:Impulse):void {
            var track:Track = impulse.data.track as Track;
            if (track && _drawingSurface) {
                if (_drawingSurface.getDynamicBackFace().contains(track)) {
                    _drawingSurface.getDynamicBackFace().removeChild(track);
                }

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "INFO",
                    source: "EditorWindowContent",
                    message: "Track removed from canvas"
                }));
            }
        }

        /**
         * Handle object addition to editor
         */
        private function onAddToEditor(impulse:Impulse):void {
            var object:Sprite = impulse.data.object as Sprite;
            if(object && _drawingSurface) {
                _drawingSurface.addChild(object);
            }
        }

        /**
         * Handle track addition to editor
         */
        private function onAddTrackToEditor(impulse:Impulse):void {
            var track:Track = impulse.data.track as Track;
            if(track && _drawingSurface) {
                if (!_drawingSurface.getDynamicBackFace().contains(track)) {
                    _drawingSurface.getDynamicBackFace().addChild(track);
                    track.draw();
                }
            }
        }

        /**
         * Center drawing surface
         */
        private function centerDrawingSurface():void {
            _drawingSurface.x = _stage.stageWidth / 2;
            _drawingSurface.y = _stage.stageHeight / 2;
            _viewPointPosition.x = 0;
            _viewPointPosition.y = 0;
            _zoomLevel = 0.5;
            updateViewPointPosition();
        }

        /**
         * Handle mouse wheel for zoom
         */
        private function onMouseWheel(event:MouseEvent):void {
            var mouseStageX:Number = _stage.mouseX;
            var mouseStageY:Number = _stage.mouseY;
            var mouseLocalBefore:Point = _drawingSurface.globalToLocal(new Point(mouseStageX, mouseStageY));
            var oldZoom:Number = _zoomLevel;

            _zoomLevel += (event.delta > 0) ? _zoomStep : -_zoomStep;
            _zoomLevel = Math.max(_zoomMin, Math.min(_zoomMax, _zoomLevel));

            updateViewPointPosition();

            var mouseLocalAfter:Point = _drawingSurface.globalToLocal(new Point(mouseStageX, mouseStageY));
            var scaleRatio:Number = _zoomLevel / oldZoom;
            _viewPointPosition.x += (mouseLocalAfter.x - mouseLocalBefore.x) * scaleRatio;
            _viewPointPosition.y += (mouseLocalAfter.y - mouseLocalBefore.y) * scaleRatio;

            updateViewPointPosition();
        }

        /**
         * Handle middle mouse button down for dragging
         */
        private function onMiddleMouseDown(event:MouseEvent):void {
            _isDragging = true;
            _lastMousePos = new Point(_stage.mouseX, _stage.mouseY);
            _stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Handle mouse dragging
         */
        private function onMouseDrag(event:MouseEvent):void {
            if(_isDragging) {
                var currentMousePos:Point = new Point(_stage.mouseX, _stage.mouseY);
                var dx:Number = currentMousePos.x - _lastMousePos.x;
                var dy:Number = currentMousePos.y - _lastMousePos.y;
                _viewPointPosition.x += dx / _zoomLevel;
                _viewPointPosition.y += dy / _zoomLevel;
                updateViewPointPosition();
                _lastMousePos = currentMousePos;
            }
        }

        /**
         * Handle middle mouse button up
         */
        private function onMiddleMouseUp(event:MouseEvent):void {
            _isDragging = false;
            _stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Handle window resize
         */
        private function onResize(event:Event):void {
            centerDrawingSurface();
        }

        /**
         * Handle mouse leave
         */
        private function handleMouseLeave(event:Event):void {
            event.stopImmediatePropagation();
            _stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Update view point position
         */
        private function updateViewPointPosition():void {
            _drawingSurface.scaleX = _drawingSurface.scaleY = _zoomLevel;
            _drawingSurface.x = _stage.stageWidth / 2 + _viewPointPosition.x * _zoomLevel;
            _drawingSurface.y = _stage.stageHeight / 2 + _viewPointPosition.y * _zoomLevel;
        }

        /**
         * Get drawing surface
         * @return DrawingSurface - drawing surface reference
         */
        public function getDrawingSurface():DrawingSurface {
            return _drawingSurface;
        }
    }
}
