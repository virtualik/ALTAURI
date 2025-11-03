package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Core.Managers.WindowsManager;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.events.Event;
    import flash.events.MouseEvent;

    /**
     * Централизованный менеджер для создания, управления жизненным циклом треков и вычисления позиций пинов.
     * Обрабатывает все операции, связанные с треками, включая позиционирование пинов, обнаружение атомов
     * и валидацию соединений с использованием прямых подписок pin-to-pin для оптимальной производительности.
     *
     * Ключевые улучшения:
     * - Добавлена проверка существующих соединений
     * - Улучшена обработка импульсов с подробным логированием
     * - Оптимизирован поиск пинов в радиусе
     * - Расширена отладочная информация
     *
     * @class TrackManager
     * @public
     */
    public class TrackManager {

        /** Singleton instance */
        private static var _instance:TrackManager;

        /** Active tracks storage by connection ID */
        private var _activeTracks:Object;

        /** Temporary track during drag operations */
        private var _tempTrack:Sprite;

        /** Currently dragging pin reference */
        private var _currentDragPin:Pin;

        /** Current window context */
        private var _currentWindow:Window;

        /**
         * Private constructor for singleton pattern.
         * Initializes track storage and sets up impulse listeners.
         */
        public function TrackManager() {
            _activeTracks = {};
            setupImpulseListeners();
        }

        /**
         * Gets the singleton instance of TrackManager.
         *
         * @static
         * @public
         * @return {TrackManager} Singleton instance
         */
        public static function getInstance():TrackManager {
            if (!_instance) {
                _instance = new TrackManager();
            }
            return _instance;
        }

        /**
         * Gets the currently dragging pin for external access.
         * Используется PinView для валидации соединений.
         *
         * @public
         * @return {Pin} Currently dragging pin or null
         */
        public function getCurrentDragPin():Pin {
            return _currentDragPin;
        }

        /**
         * Initializes the track manager system.
         * Must be called before using track management functionality.
         *
         * @static
         * @public
         */
        public static function initialize():void {
            getInstance();
        }

        // =========================================================================
        // CONNECTION VALIDATION METHODS
        // =========================================================================

        /**
         * Checks if a connection between pins already exists in active tracks.
         * Предотвращает создание дублирующих соединений.
         *
         * @public
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         * @return {Boolean} True if connection already exists
         */
        public function connectionExists(fromPin:Pin, toPin:Pin):Boolean {
            for (var connectionId:String in _activeTracks) {
                var track:Track = _activeTracks[connectionId];
                if ((track.fromPin === fromPin && track.toPin === toPin) ||
                    (track.fromPin === toPin && track.toPin === fromPin)) {
                    return true;
                }
            }
            return false;
        }

        /**
         * Validates if a connection between two pins is allowed.
         * Checks pin types, atom ownership, and existing connections.
         *
         * @private
         * @param {Pin} fromPin - Source pin (must be output)
         * @param {Pin} toPin - Target pin (must be input)
         * @return {Boolean} True if connection is valid and allowed
         */
		private function isValidConnection(fromPin:Pin, toPin:Pin):Boolean {
			if (!fromPin || !toPin) {
				trace("Invalid: one or both pins are null");
				return false;
			}

			// Запрещаем соединение с самим собой
			if (fromPin === toPin) {
				trace("Invalid: cannot connect to self");
				return false;
			}

			// Проверяем соответствие типов: выход → вход
			var validTypes:Boolean = (fromPin.type == Pin.TYPE_OUTPUT && toPin.type == Pin.TYPE_INPUT);
			if (!validTypes) {
				trace("Invalid pin types: " + fromPin.type + " -> " + toPin.type);
				return false;
			}

			// Получаем атомы для проверки принадлежности
			var fromAtom:Atom = getAtomByPin(fromPin);
			var toAtom:Atom = getAtomByPin(toPin);

			if (!fromAtom || !toAtom) {
				trace("Invalid: could not find atoms for pins");
				return false;
			}

			// Запрещаем соединение пинов одного атома
			if (fromAtom.id == toAtom.id) {
				trace("Invalid: cannot connect pins of the same atom");
				return false;
			}

			// УБРАТЬ ПРОВЕРКУ СУЩЕСТВУЮЩИХ СОЕДИНЕНИЙ - разрешаем переподключение
			// var connectionExists:Boolean = trackManager.connectionExists(fromPin, toPin);
			// if (connectionExists) {
			//     trace("Invalid: connection already exists");
			//     return false;
			// }

			trace("Connection VALID: " + fromAtom.type + "." + fromPin.name +
				  " -> " + toAtom.type + "." + toPin.name);
			return true;
		}

        // =========================================================================
        // PIN SEARCH AND VALIDATION METHODS
        // =========================================================================

        /**
         * Finds pins within a specified radius of mouse position for connection targeting.
         * Uses spatial search to locate the closest valid pin for connection.
         * Улучшенная версия с проверкой расстояния и приоритетом ближайшего пина.
         *
         * @private
         * @param {Number} stageX - Mouse X coordinate in stage space
         * @param {Number} stageY - Mouse Y coordinate in stage space
         * @param {Number} radius - Search radius in pixels (default: 20)
         * @return {Pin} Closest valid pin within radius, or null if none found
         */
        private function findPinInRadius(stageX:Number, stageY:Number, radius:Number = 20):Pin {
            var allPins:Array = getAllPinsInWindow();
            var mousePos:Point = new Point(stageX, stageY);
            var closestPin:Pin = null;
            var minDistance:Number = Number.MAX_VALUE;

            trace("=== RADIUS PIN SEARCH ===");
            trace("Search center: " + stageX + ", " + stageY);
            trace("Search radius: " + radius);
            trace("Total pins in window: " + allPins.length);

            for each (var pin:Pin in allPins) {
                var pinPos:Point = getGlobalPinPosition(pin);
                var distance:Number = Point.distance(mousePos, pinPos);

                trace("Checking pin: " + pin.name + " at distance " + distance.toFixed(2));

                if (distance <= radius && distance < minDistance && pin != _currentDragPin) {
                    if (isValidConnection(_currentDragPin, pin)) {
                        closestPin = pin;
                        minDistance = distance;
                        trace("New closest valid pin: " + pin.name + " at " + distance.toFixed(2));
                    } else {
                        trace("Invalid connection for pin: " + pin.name);
                    }
                }
            }

            trace("Radius search result: " + (closestPin ? closestPin.name : "null"));
            trace("=== END RADIUS SEARCH ===");

            return closestPin;
        }

        /**
         * Gets all pins in the current window context for connection searching.
         *
         * @private
         * @return {Array} Array of all pins in current window
         */
        private function getAllPinsInWindow():Array {
            var allPins:Array = [];
            var atomManager:AtomManager = AtomManager.getInstance();

            if (!_currentWindow) {
                trace("WARNING: No current window for pin search");
                return allPins;
            }

            var allAtoms:Array = atomManager.getAtomsForWindow(_currentWindow.windowType);
            trace("Found " + allAtoms.length + " atoms in window: " + _currentWindow.windowType);

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;

                // Add input pins
                for each (var inputPin:Pin in atom.inputs) {
                    allPins.push(inputPin);
                }

                // Add output pins
                for each (var outputPin:Pin in atom.outputs) {
                    allPins.push(outputPin);
                }
            }

            trace("Total pins collected: " + allPins.length);
            return allPins;
        }

        // =========================================================================
        // IMPULSE LISTENERS SETUP
        // =========================================================================

        /**
         * Sets up all impulse listeners for track management system.
         * Handles pin dragging, atom movement, window events, and track commands.
         * Добавлено подробное логирование для отладки.
         *
         * @private
         */
        private function setupImpulseListeners():void {
            // Track creation process
            MultiPulsator.subscribeToImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.subscribeToImpulse("PIN_DRAG_END", onPinDragEnd);

            // Atom movement events
            MultiPulsator.subscribeToImpulse("ATOM_MOVED", onAtomMoved);

            // Window events
            MultiPulsator.subscribeToImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.subscribeToImpulse("WINDOW_CLOSING", onWindowClosing);

            // Track management commands
            MultiPulsator.subscribeToImpulse("TRACK_DELETE_REQUEST", onTrackDeleteRequest);

            trace("TrackManager: Impulse listeners setup complete");
        }

        // =========================================================================
        // EVENT HANDLERS
        // =========================================================================

        /**
         * Handles pin drag start impulse for connection creation.
         * Initializes temporary track visualization and stores drag context.
         * Добавлено логирование для отладки процесса перетаскивания.
         *
         * @private
         * @param {Impulse} impulse - PIN_DRAG_START impulse with pin and position data
         */
        private function onPinDragStart(impulse:Impulse):void {
            _currentDragPin = impulse.data.pin;
            _currentWindow = findWindowByType(impulse.data.windowType);

            trace("=== PIN DRAG START ===");
            trace("Drag pin: " + (_currentDragPin ? _currentDragPin.name : "null"));
            trace("Target window: " + (_currentWindow ? _currentWindow.windowType : "null"));

            if (_currentWindow && _currentDragPin) {
                startTempTrack(impulse.data.startX, impulse.data.startY);
                trace("Temporary track started successfully");
            } else {
                trace("ERROR: Failed to start temporary track - missing window or pin");
            }
        }

        /**
         * Handles pin drag update impulse for temporary track visualization.
         * Updates the temporary track position during drag operations.
         *
         * @private
         * @param {Impulse} impulse - PIN_DRAG_UPDATE impulse with current position
         */
        private function onPinDragUpdate(impulse:Impulse):void {
            if (_tempTrack && _currentDragPin) {
                updateTempTrack(impulse.data.currentX, impulse.data.currentY);
            }
        }

        /**
         * Handles pin drag end impulse for finalizing connections.
         * Validates and creates permanent tracks or cleans up temporary state.
         * Улучшенная логика с резервным поиском по радиусу.
         *
         * @private
         * @param {Impulse} impulse - PIN_DRAG_END impulse with end position and target pin
         */
		private function onPinDragEnd(impulse:Impulse):void {
			trace("=== PIN DRAG END PROCESSING ===");

			if (!_currentDragPin) {
				trace("WARNING: No current drag pin on drag end");
				cleanupTempTrack();
				return;
			}

			var fromPin:Pin = _currentDragPin;
			var toPin:Pin = impulse.data.toPin;

			trace("From pin: " + fromPin.name);
			trace("Direct target pin: " + (toPin ? toPin.name : "null"));

			// Если прямой целевой пин не предоставлен, выполняем поиск по радиусу
			if (!toPin) {
				trace("No direct target, performing radius search...");
				toPin = findPinInRadius(impulse.data.endX, impulse.data.endY, 25);
				trace("Radius search result: " + (toPin ? toPin.name : "null"));
			}

			cleanupTempTrack();

			// Создаем трек если соединение валидно
			if (toPin && isValidConnection(fromPin, toPin)) {
				// ПЕРЕД СОЗДАНИЕМ НОВОГО СОЕДИНЕНИЯ УДАЛЯЕМ СТАРЫЕ
				removeExistingConnections(toPin);
				
				trace("Creating track: " + fromPin.name + " -> " + toPin.name);
				createTrack(fromPin, toPin);
			} else {
				trace("Track creation skipped - invalid connection");
			}

			_currentDragPin = null;
			trace("=== PIN DRAG END COMPLETE ===");
		}

		// Новый метод для удаления существующих соединений с целевым пином
		private function removeExistingConnections(toPin:Pin):void {
			var tracksToRemove:Array = [];
			
			// Ищем все треки, подключенные к целевому пину
			for each (var track:Track in _activeTracks) {
				if (track.toPin === toPin) {
					tracksToRemove.push(track);
					trace("Found existing track to remove: " + track.connectionId);
				}
			}
			
			// Удаляем найденные треки
			for each (var trackToRemove:Track in tracksToRemove) {
				removeTrack(trackToRemove);
				trace("Removed existing track: " + trackToRemove.connectionId);
			}
		}

        /**
         * Handles atom movement to update connected track visualizations.
         * Redraws all tracks connected to moved atoms for proper visual alignment.
         *
         * @private
         * @param {Impulse} impulse - ATOM_MOVED impulse with atom data
         */
        private function onAtomMoved(impulse:Impulse):void {
            var movedAtom:Atom = impulse.data.newAtom;
            var atomId:String = movedAtom.id;
            var updateTracks:Boolean = impulse.data.updateTracks;

            trace("Atom moved: " + atomId + ", update tracks: " + updateTracks);

            if (updateTracks) {
                updateTracksForAtom(atomId);
            }
        }

        /**
         * Handles window activation to update track management context.
         * Sets the current window reference for pin searches and track operations.
         *
         * @private
         * @param {Impulse} impulse - WINDOW_ACTIVATED impulse with window data
         */
        private function onWindowActivated(impulse:Impulse):void {
            _currentWindow = impulse.data.window;
            trace("Window activated: " + (_currentWindow ? _currentWindow.windowType : "null"));
        }

        /**
         * Handles window closing to cleanup tracks associated with the window.
         * Prevents orphaned tracks and maintains clean state management.
         *
         * @private
         * @param {Impulse} impulse - WINDOW_CLOSING impulse with window data
         */
        private function onWindowClosing(impulse:Impulse):void {
            var closingWindow:Window = impulse.data.window;
            var windowType:String = closingWindow.windowType;
            trace("Window closing: " + windowType + ", cleaning up tracks...");
            cleanupTracksByWindow(windowType);
        }

        /**
         * Handles track deletion requests from context menus or commands.
         * Safely removes tracks and cleans up all associated resources.
         *
         * @private
         * @param {Impulse} impulse - TRACK_DELETE_REQUEST impulse with track reference
         */
        private function onTrackDeleteRequest(impulse:Impulse):void {
            var track:Track = impulse.data.track;
            trace("Track delete request: " + (track ? track.connectionId : "null"));

            if (track) {
                removeTrack(track);
                MultiPulsator.emit(new Impulse("TRACK_DELETED", {
                    track: track,
                    connectionId: track.connectionId
                }));
            }
        }

        // =========================================================================
        // TRACK OPERATIONS
        // =========================================================================

        /**
         * Creates a new track between pins with validation and proper setup.
         * Establishes direct pin-to-pin subscription for optimal data transfer.
         * Добавлена расширенная обработка ошибок и логирование.
         *
         * @private
         * @param {Pin} fromPin - Source pin (output)
         * @param {Pin} toPin - Target pin (input)
         */
        private function createTrack(fromPin:Pin, toPin:Pin):void {
            try {
                trace("=== TRACK CREATION START ===");
                trace("From pin: " + fromPin.name + " (" + fromPin.type + ")");
                trace("To pin: " + toPin.name + " (" + toPin.type + ")");

                var track:Track = new Track(fromPin, toPin, this);
                var connectionId:String = generateConnectionId(fromPin, toPin);

                trace("Track created, connection ID: " + connectionId);

                // Добавляем трек в соответствующий слой окна
                if (_currentWindow && _currentWindow.tracksLayer) {
                    _currentWindow.tracksLayer.addChild(track);
                    trace("Track added to tracksLayer");
                } else if (_currentWindow && _currentWindow.contentLayer) {
                    _currentWindow.contentLayer.addChild(track);
                    trace("Track added to contentLayer (fallback)");
                } else {
                    trace("ERROR: No suitable layer found for track");
                    return;
                }

                _activeTracks[connectionId] = track;

				track.drawTrack();

				track.createLogicalConnection();

                trace("Track successfully created and activated");

                MultiPulsator.emit(new Impulse("TRACK_CREATED", {
                    track: track,
                    fromPin: fromPin,
                    toPin: toPin,
                    connectionId: connectionId,
                    windowType: _currentWindow ? _currentWindow.windowType : "unknown"
                }));

                trace("=== TRACK CREATION COMPLETE ===");

            } catch (error:Error) {
                trace("ERROR in track creation: " + error.message);
                MultiPulsator.emit(new Impulse("TRACK_CREATION_ERROR", {
                    fromPin: fromPin,
                    toPin: toPin,
                    error: error.message
                }));
            }
        }

        /**
         * Updates all tracks connected to a specific atom.
         * Typically called when atoms are moved or their visual state changes.
         *
         * @private
         * @param {String} atomId - ID of the atom to update tracks for
         */
        private function updateTracksForAtom(atomId:String):void {
            var updatedCount:int = 0;
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) {
                    track.updateVisual();
                    updatedCount++;
                }
            }
            trace("Updated " + updatedCount + " tracks for atom: " + atomId);
        }

        // =========================================================================
        // TEMPORARY TRACK METHODS
        // =========================================================================

        /**
         * Starts temporary track visualization during drag operations.
         * Creates visual feedback for potential connections.
         *
         * @private
         * @param {Number} startX - Starting X coordinate
         * @param {Number} startY - Starting Y coordinate
         */
        private function startTempTrack(startX:Number, startY:Number):void {
            var fromPos:Point = getGlobalPinPosition(_currentDragPin);
            var localFrom:Point = _currentWindow.overlayLayer.globalToLocal(fromPos);

            _tempTrack = new TempTrack(localFrom);

            if (_currentWindow && _currentWindow.overlayLayer) {
                _currentWindow.overlayLayer.addChild(_tempTrack);
                updateTempTrack(startX, startY);
                trace("Temporary track visualization started");
            }
        }

        /**
         * Updates temporary track position during drag operations.
         * Provides real-time visual feedback for connection targeting.
         *
         * @private
         * @param {Number} currentX - Current X coordinate
         * @param {Number} currentY - Current Y coordinate
         */
        private function updateTempTrack(currentX:Number, currentY:Number):void {
            if (!_tempTrack || !_currentDragPin || !_currentWindow) return;

            var localTo:Point = _currentWindow.overlayLayer.globalToLocal(new Point(currentX, currentY));
            (_tempTrack as TempTrack).update(localTo);
        }

        /**
         * Cleans up temporary track resources after drag operations.
         * Removes visual elements and resets temporary state.
         *
         * @private
         */
        private function cleanupTempTrack():void {
            if (_tempTrack && _tempTrack.parent) {
                _tempTrack.parent.removeChild(_tempTrack);
                trace("Temporary track cleaned up");
            }
            _tempTrack = null;
        }

        // =========================================================================
        // UTILITY METHODS
        // =========================================================================

        /**
         * Generates a unique connection identifier based on pin and atom information.
         *
         * @private
         * @param {Pin} fromPin - Source pin
         * @param {Pin} toPin - Target pin
         * @return {String} Unique connection identifier
         */
        private function generateConnectionId(fromPin:Pin, toPin:Pin):String {
            var fromAtom:Atom = getAtomByPin(fromPin);
            var toAtom:Atom = getAtomByPin(toPin);

            if (!fromAtom || !toAtom) {
                return "invalid_connection_" + Math.random().toString(36).substr(2, 9);
            }

            return "track_" + fromAtom.id + "_" + fromPin.name +
                   "_to_" + toAtom.id + "_" + toPin.name;
        }

        /**
         * Finds a window by type using WindowsManager.
         *
         * @private
         * @param {String} windowType - Type of window to find
         * @return {Window} Found window or null
         */
        private function findWindowByType(windowType:String):Window {
            var windowsManager:WindowsManager = WindowsManager.getInstance();
            return windowsManager ? windowsManager.findWindow(windowType) : null;
        }

        /**
         * Cleans up all tracks associated with a specific window type.
         * Typically called during window closure or context switching.
         *
         * @private
         * @param {String} windowType - Window type to cleanup tracks for
         */
        private function cleanupTracksByWindow(windowType:String):void {
            var removedCount:int = 0;
            for (var connectionId:String in _activeTracks) {
                var track:Track = _activeTracks[connectionId];
                if (_currentWindow && _currentWindow.windowType == windowType) {
                    removeTrack(track);
                    removedCount++;
                }
            }
            trace("Cleaned up " + removedCount + " tracks for window: " + windowType);
        }

        // =========================================================================
        // PUBLIC API (остальные методы остаются без изменений)
        // =========================================================================

        /**
         * Removes a track from the system with proper cleanup.
         * Handles pin subscription removal and resource disposal.
         *
         * @public
         * @param {Track} track - Track to remove
         */
        public function removeTrack(track:Track):void {
            var connectionId:String = track.connectionId;

            if (_activeTracks[connectionId]) {
                track.dispose();
                delete _activeTracks[connectionId];
                trace("Track removed: " + connectionId);

                MultiPulsator.emit(new Impulse("TRACK_REMOVED", {
                    track: track,
                    connectionId: connectionId
                }));
            }
        }

        /**
         * Removes a track by its connection identifier.
         *
         * @public
         * @param {String} connectionId - Unique connection identifier
         * @return {Track} The removed track or null if not found
         */
        public function removeTrackById(connectionId:String):Track {
            var track:Track = _activeTracks[connectionId];
            if (track) removeTrack(track);
            return track;
        }

        /**
         * Gets all active tracks in the system.
         *
         * @public
         * @return {Object} Dictionary of active tracks by connection ID
         */
        public function getActiveTracks():Object {
            return _activeTracks;
        }

        /**
         * Gets a specific track by its connection identifier.
         *
         * @public
         * @param {String} connectionId - Unique connection identifier
         * @return {Track} Track instance or null if not found
         */
        public function getTrackById(connectionId:String):Track {
            return _activeTracks[connectionId];
        }

        /**
         * Gets all tracks connected to a specific atom.
         *
         * @public
         * @param {String} atomId - Atom identifier to search for
         * @return {Array} Array of connected tracks
         */
        public function getTracksByAtom(atomId:String):Array {
            var connectedTracks:Array = [];
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atomId)) connectedTracks.push(track);
            }
            return connectedTracks;
        }

        /**
         * Gets all tracks connected to a specific pin.
         *
         * @public
         * @param {Pin} pin - Pin to search for connections
         * @return {Array} Array of connected tracks
         */
        public function getTracksByPin(pin:Pin):Array {
            var connectedTracks:Array = [];
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToPin(pin)) connectedTracks.push(track);
            }
            return connectedTracks;
        }

        /**
         * Gets the total count of active tracks in the system.
         *
         * @public
         * @return {int} Number of active tracks
         */
        public function getActiveTracksCount():int {
            var count:int = 0;
            for (var key:String in _activeTracks) count++;
            return count;
        }

        // =========================================================================
        // PIN POSITION CALCULATION METHODS (остаются без изменений)
        // =========================================================================

        /**
         * Gets the global position of a pin for track visualization.
         * Searches for PinView in display hierarchy first, falls back to atom-based calculation.
         *
         * @public
         * @param {Pin} pin - Pin to get position for
         * @return {Point} Global position coordinates
         */
        public function getGlobalPinPosition(pin:Pin):Point {
            // Find the PinView in the display hierarchy
            var pinView:PinView = findPinView(pin);
            if (pinView && pinView.stage) {
                return pinView.localToGlobal(new Point(0, 0));
            }

            // Fallback: use atom position if PinView not found
            var atom:Atom = getAtomByPin(pin);
            var atomView:AtomView = getAtomView(atom);
            if (atomView && atomView.stage) {
                var pinIndex:int = getPinIndex(atom, pin);
                var totalPins:int = pin.type == Pin.TYPE_INPUT ? atom.inputs.length : atom.outputs.length;
                var pinY:Number = atomView.height * (pinIndex + 1) / (totalPins + 1);
                var pinX:Number = pin.type == Pin.TYPE_INPUT ? 0 : atomView.width;

                var atomGlobal:Point = atomView.localToGlobal(new Point(pinX, pinY));
                return atomGlobal;
            }

            return new Point(100, 100); // Fallback position
        }

        /**
         * Finds the PinView instance for a given Pin by searching through all atoms.
         *
         * @public
         * @param {Pin} pin - Pin to find view for
         * @return {PinView} Found PinView or null if not found
         */
        public function findPinView(pin:Pin):PinView {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;
                var atomView:AtomView = atomData.view;

                for (var i:int = 0; i < atomView.numChildren; i++) {
                    var child:* = atomView.getChildAt(i);
                    if (child is PinView) {
                        var pinView:PinView = child as PinView;
                        if (pinView.pin.id == pin.id) {
                            return pinView;
                        }
                    }
                }
            }

            return null;
        }

        /**
         * Gets the atom that owns the specified pin by searching through all registered atoms.
         *
         * @public
         * @param {Pin} pin - Pin to find owner for
         * @return {Atom} Atom that owns the pin, or null if not found
         */
        public function getAtomByPin(pin:Pin):Atom {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;

                // Check input pins
                for each (var inputPin:Pin in atom.inputs) {
                    if (inputPin.id == pin.id) {
                        return atom;
                    }
                }

                // Check output pins
                for each (var outputPin:Pin in atom.outputs) {
                    if (outputPin.id == pin.id) {
                        return atom;
                    }
                }
            }

            return null;
        }

        /**
         * Gets the AtomView for a given Atom instance.
         *
         * @public
         * @param {Atom} atom - Atom to find view for
         * @return {AtomView} Found AtomView or null if not found
         */
        public function getAtomView(atom:Atom):AtomView {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");

            for each (var atomData:Object in allAtoms) {
                if (atomData.atom === atom) {
                    return atomData.view;
                }
            }
            return null;
        }

        /**
         * Gets the index of a pin within its parent atom's pin collection.
         * Used for calculating pin positions relative to atom view.
         *
         * @public
         * @param {Atom} atom - Atom containing the pin
         * @param {Pin} pin - Pin to find index for
         * @return {int} Index of the pin in its collection
         */
        public function getPinIndex(atom:Atom, pin:Pin):int {
            var pins:Vector.<Pin> = pin.type == Pin.TYPE_INPUT ? atom.inputs : atom.outputs;
            for (var i:int = 0; i < pins.length; i++) {
                if (pins[i] === pin) {
                    return i;
                }
            }
            return 0;
        }

        /**
         * Disposes all track manager resources and cleans up system state.
         * Removes all impulse listeners and active tracks.
         */
        public function dispose():void {
            trace("TrackManager: Disposing all resources...");

            // Remove all impulse listeners
            MultiPulsator.removeImpulse("PIN_DRAG_START", onPinDragStart);
            MultiPulsator.removeImpulse("PIN_DRAG_UPDATE", onPinDragUpdate);
            MultiPulsator.removeImpulse("PIN_DRAG_END", onPinDragEnd);
            MultiPulsator.removeImpulse("ATOM_MOVED", onAtomMoved);
            MultiPulsator.removeImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.removeImpulse("WINDOW_CLOSING", onWindowClosing);
            MultiPulsator.removeImpulse("TRACK_DELETE_REQUEST", onTrackDeleteRequest);

            // Dispose all active tracks
            var trackCount:int = 0;
            for each (var track:Track in _activeTracks) {
                track.dispose();
                trackCount++;
            }
            _activeTracks = {};

            // Cleanup temporary state
            cleanupTempTrack();
            _currentDragPin = null;
            _currentWindow = null;

            trace("TrackManager: Disposed " + trackCount + " tracks and cleaned up resources");
        }
    }
}
