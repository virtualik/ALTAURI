package Src.Prog.Core {
	import flash.display.NativeWindow;
	import flash.display.NativeWindowInitOptions;
	import flash.display.NativeWindowSystemChrome;
	import flash.display.NativeWindowType;
	import flash.display.Sprite;
	import flash.display.StageQuality;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.KeyboardEvent;
	import flash.events.NativeWindowDisplayStateEvent;
	import flash.system.Capabilities;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.ui.Keyboard;
	import Src.Prog.Core.MultiPulsator.MultiPulsator;
	import Src.Prog.Core.MultiPulsator.Impulse;
	import flash.display.DisplayObject;
	import Src.Prog.Com.Atoms.Core.Atom;
	import Src.Prog.Com.Atoms.Core.AtomView;
	import Src.Prog.Com.Atoms.Core.Track;
	import Src.Prog.Com.Atoms.Core.Pin;
	// Menus
	import Src.Prog.Com.Menus.ContextMenu;
	import Src.Prog.Com.Menus.ContextMenuItem;
	import Src.Prog.Core.Managers.MenuManager;

	/**
	  *Universal window with ultra-smooth pan/zoom canvas and impulse system.
	  **Features:
	  *Frame-based panning (ENTER_FRAME on stage for smoothness)
	  *Cursor-anchored pan and zoom
	  *Debug overlay toggled with Ctrl+D
	  *Single updateViewport() call per frame
	  *@class Window
	  *@extends NativeWindow
	  *@public
	  */
	public class Window extends NativeWindow {
		private var _type: String;
		private var _content: Sprite;
		private var _canvas: Sprite;
		private var _backgroundLayer: Sprite;
		private var _tracksLayer: Sprite;
		private var _contentLayer: Sprite;
		private var _overlayLayer: Sprite;
		private var _viewPoint: Point = new Point(0, 0);
		private var _zoomLevel: Number = 0.1;
		private var _isDragging: Boolean = false;
		private var _panAnchorWorld: Point;
		private static const ZOOM_MIN: Number = 0.09;
		private static const ZOOM_MAX: Number = 0.25;
		private static const ZOOM_STEP: Number = 0.01;
		private static var _isDesktop: Boolean = Capabilities.os.indexOf("Windows") >= 0 || Capabilities.os.indexOf("Mac") >= 0 || Capabilities.os.indexOf("Linux") >= 0;
		// Debug
		private var _debugEnabled: Boolean = false;

		private var _dragStartScreen: Point;
		private var _dragStartViewPoint: Point;

		/**
			Constructor
			@param type Window type
			@param config Optional config
		*/
		public function Window(type: String, config: Object = null) {
			var options: NativeWindowInitOptions = new NativeWindowInitOptions();
			options.type = NativeWindowType.NORMAL;
			options.systemChrome = NativeWindowSystemChrome.STANDARD;
			options.transparent = false;
			super(options);
			_type = type;
			var cfg: Object = config || {};
			this.title = cfg.title || type + " Window";
			this.alwaysInFront = true;
			if(_isDesktop) {
				this.bounds = new Rectangle(cfg.x || 100, cfg.y || 100, cfg.width || 800, cfg.height || 600);
			}
			else {
				this.bounds = new Rectangle(0, 0, Capabilities.screenResolutionX, Capabilities.screenResolutionY);
			}
			setupEventToImpulseTransformers();
			if(stage) {
				initializeContent();
			}
			else {
				addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			}
		}


		private function onAddedToStage(event: Event): void {
			removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			this.activate();
			this.stage.focus = this.stage;
			initializeContent();
		}
		private function setupEventToImpulseTransformers(): void {
			addEventListener(Event.ACTIVATE, transformWindowActivate);
			addEventListener(Event.DEACTIVATE, transformWindowDeactivate);
			addEventListener(Event.CLOSING, transformWindowClosing);
			addEventListener(Event.RESIZE, transformWindowResize);
			addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);
			stage.addEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
			stage.addEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
			stage.addEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
			stage.addEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
			stage.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
			stage.addEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
			stage.addEventListener(MouseEvent.CLICK, transformClick);
		}
		private function initializeContent(): void {
			try {
				_content = new Sprite();
				_content.name = "Content";
				stage.quality = StageQuality.BEST;
				stage.addChild(_content);
				initializeCanvasSystem();
				switch(_type) {
					case "Editor":
						setupEditorContent();
						break;
					case "Device":
						setupDeviceContent();
						break;
					default:
						setupDefaultContent();
				}
				resetViewport();
				stage.addEventListener(KeyboardEvent.KEY_DOWN, transformKeyDown);
				stage.addEventListener(KeyboardEvent.KEY_UP, transformKeyUp);
				trace("Window initialized: " + _type);
			}
			catch(e: Error) {
				trace("Window init error: " + e.message);
			}
		}
		private function initializeCanvasSystem(): void {
			_canvas = new Sprite();
			_canvas.name = "Canvas";
			_content.addChild(_canvas);
			_backgroundLayer = new Sprite();
			_backgroundLayer.name = "BackgroundLayer";
			_backgroundLayer.mouseEnabled = true;
			_backgroundLayer.doubleClickEnabled = true;
			//_backgroundLayer.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onBackgroundRightClick);
			_canvas.addChild(_backgroundLayer);
			_tracksLayer = new Sprite();
			_tracksLayer.name = "TracksLayer";
			_tracksLayer.mouseEnabled = false;
			_canvas.addChild(_tracksLayer);
			_contentLayer = new Sprite();
			_contentLayer.name = "ContentLayer";
			_contentLayer.mouseEnabled = true;
			_contentLayer.doubleClickEnabled = true;
			_canvas.addChild(_contentLayer);
			_overlayLayer = new Sprite();
			_overlayLayer.name = "OverlayLayer";
			_overlayLayer.mouseEnabled = false;
			_overlayLayer.mouseChildren = true;
			_canvas.addChild(_overlayLayer);
			setupViewportControls();
		}
/*		private function onBackgroundRightClick(event: MouseEvent): void {
			 trace("--=== Window: onBackgroundRightClick ===-- " + this);
			if(_type !== "Editor") return;
			var pos: Point = new Point(event.stageX, event.stageY);
			MultiPulsator.emit(new Impulse("WINDOW_RIGHT_CLICK", {
				globalPosition: pos,
				window: this,
				windowType: _type,
				localPosition: _contentLayer.globalToLocal(pos)
			}));
			event.stopPropagation();
		}*/
		private function setupViewportControls(): void {
			stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
			stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
			stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
			stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeave);
			stage.addEventListener(Event.RESIZE, onStageResize);
		}
		// =========================================================================
		// SMOOTH PAN & ZOOM
		// =========================================================================
		private function onMiddleMouseDown(event: MouseEvent): void {
			event.stopPropagation();
			_isDragging = true;
			// Сохраняем ЭКРАННУЮ позицию курсора (stageX/Y) — она не зависит от zoom/pan
			_dragStartScreen = new Point(event.stageX, event.stageY);
			// Сохраняем текущую точку обзора
			_dragStartViewPoint = _viewPoint.clone();
			stage.addEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
		}

		/**
		Frame-based pan update — ultra-smooth
		*/
		private function onPanFrameUpdate(event: Event): void {
			if(!_isDragging || !stage || !_canvas) return;

			// Текущая экранная позиция курсора
			var currentScreen: Point = new Point(stage.mouseX, stage.mouseY);

			// Смещение в экранных координатах
			var screenDx: Number = currentScreen.x - _dragStartScreen.x;
			var screenDy: Number = currentScreen.y - _dragStartScreen.y;

			// Переводим смещение в мировые координаты (делим на zoom)
			_viewPoint.x = _dragStartViewPoint.x - screenDx / _zoomLevel;
			_viewPoint.y = _dragStartViewPoint.y - screenDy / _zoomLevel;

			// Ограничиваем, если нужно
			_viewPoint.x = Math.max(-10000, Math.min(10000, _viewPoint.x));
			_viewPoint.y = Math.max(-10000, Math.min(10000, _viewPoint.y));

			updateViewport();

			MultiPulsator.emit(new Impulse("CANVAS_PANNED", {
				windowType: _type,
				viewPoint: _viewPoint.clone(),
				movement: new Point(-screenDx / _zoomLevel, -screenDy / _zoomLevel)
			}));
		}

		private function onMiddleMouseUp(event: MouseEvent): void {
			_isDragging = false;
			stage.removeEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
			// Опционально: сбросить временные переменные
			_dragStartScreen = null;
			_dragStartViewPoint = null;
		}

		private function onMouseLeave(event: Event): void {
			_isDragging = false;
			stage.removeEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
		}

		/**
		Smooth zoom
		*/
		private function onMouseWheel(event: MouseEvent): void {
			if(!_canvas || !stage) return;

			// 1. Позиция курсора в экранных координатах
			var screenX: Number = event.stageX;
			var screenY: Number = event.stageY;

			// 2. Текущая мировая позиция под курсором
			var worldBefore: Point = _canvas.globalToLocal(new Point(screenX, screenY));

			// 3. Изменяем zoom
			_zoomLevel += (event.delta > 0) ? ZOOM_STEP : -ZOOM_STEP;
			_zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, _zoomLevel));

			// 4. Вычисляем НОВУЮ точку обзора так, чтобы worldBefore осталась под курсором
			// Формула: viewPoint = (stageCenter - screenPos) / zoom + worldPos
			var newViewX: Number = (stage.stageWidth * 0.5 - screenX) / _zoomLevel + worldBefore.x;
			var newViewY: Number = (stage.stageHeight * 0.5 - screenY) / _zoomLevel + worldBefore.y;

			_viewPoint.x = newViewX;
			_viewPoint.y = newViewY;

			// 5. Обновляем один раз
			updateViewport();

			// 6. Эмитим импульс
			MultiPulsator.emit(new Impulse("CANVAS_ZOOM_CHANGED", {
				windowType: _type,
				zoomLevel: _zoomLevel,
				viewPoint: _viewPoint.clone()
			}));
		}


		private function onStageResize(event: Event): void {
			updateViewport();
			MultiPulsator.emit(new Impulse("CANVAS_RESIZED", {
				windowType: _type,
				stageWidth: stage.stageWidth,
				stageHeight: stage.stageHeight
			}));
		}
		private function updateViewport(): void {
			if(!_canvas || !stage) return;
			if(isNaN(_zoomLevel) || _zoomLevel <= 0) _zoomLevel = 0.1;
			if(isNaN(_viewPoint.x) || isNaN(_viewPoint.y)) {
				_viewPoint.setTo(0, 0);
			}
			_canvas.scaleX = _canvas.scaleY = _zoomLevel;
			_canvas.x = stage.stageWidth * 0.5 - _viewPoint.x * _zoomLevel;
			_canvas.y = stage.stageHeight * 0.5 - _viewPoint.y * _zoomLevel;
			if(_debugEnabled) drawDebugOverlay();
		}
		// =========================================================================
		// PUBLIC API
		// =========================================================================
		public function resetViewport(): void {
			_viewPoint.setTo(0, 0);
			_zoomLevel = 0.1;
			updateViewport();
			MultiPulsator.emit(new Impulse("CANVAS_RESET", {
				windowType: _type,
				zoomLevel: _zoomLevel,
				viewPoint: _viewPoint.clone()
			}));
		}
		public function get canvas(): Sprite {
			return _canvas;
		}
		public function get backgroundLayer(): Sprite {
			return _backgroundLayer;
		}
		public function get contentLayer(): Sprite {
			return _contentLayer;
		}
		public function get overlayLayer(): Sprite {
			return _overlayLayer;
		}
		public function get tracksLayer(): Sprite {
			return _tracksLayer;
		}
		public function get zoomLevel(): Number {
			return _zoomLevel;
		}
		public function get viewPoint(): Point {
			return _viewPoint.clone();
		}
		public function get windowType(): String {
			return _type;
		}
		public function set zoomLevel(value: Number): void {
			_zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, value));
			updateViewport();
		}
		public function set viewPoint(point: Point): void {
			_viewPoint = point.clone();
			updateViewport();
		}
		// =========================================================================
		// EVENT TRANSFORMERS
		// =========================================================================
		private function transformWindowActivate(e: Event): void {
			if(!_content) initializeContent();
			MultiPulsator.emit(new Impulse("WINDOW_ACTIVATED", {
				windowType: _type,
				window: this
			}));
		}
		private function transformWindowDeactivate(e: Event): void {
			MultiPulsator.emit(new Impulse("WINDOW_DEACTIVATED", {
				windowType: _type,
				window: this
			}));
		}
		private function transformWindowClosing(e: Event): void {
			MultiPulsator.emit(new Impulse("WINDOW_CLOSING", {
				windowType: _type,
				window: this
			}));
			MultiPulsator.emit(new Impulse("APP_CLOSE"));
		}
		private function transformWindowResize(e: Event): void {
			MultiPulsator.emit(new Impulse("WINDOW_RESIZED", {
				windowType: _type,
				window: this,
				width: this.width,
				height: this.height
			}));
		}
		private function transformDisplayStateChange(e: NativeWindowDisplayStateEvent): void {
			MultiPulsator.emit(new Impulse("WINDOW_DISPLAY_STATE_CHANGED", {
				windowType: _type,
				window: this,
				displayState: this.displayState
			}));
		}
		private function transformKeyDown(e: KeyboardEvent): void {
			if(e.keyCode == Keyboard.ESCAPE) {
				MultiPulsator.emit(new Impulse("KEY_ESC_PRESSED", {
					window: this,
					windowType: _type
				}));
				e.stopPropagation();
			}
			// TOGGLE DEBUG WITH Ctrl+D
			if(e.keyCode == Keyboard.D && e.ctrlKey) {
				_debugEnabled = !_debugEnabled;
				trace("Debug overlay: " + (_debugEnabled ? "ON" : "OFF"));
				if(!_debugEnabled) {
					var overlay: Sprite = _content.getChildByName("debugOverlay") as Sprite;
					if(overlay) _content.removeChild(overlay);
				}
			}
			MultiPulsator.emit(new Impulse("WINDOW_KEY_DOWN", {
				windowType: _type,
				window: this,
				keyCode: e.keyCode,
				charCode: e.charCode,
				ctrlKey: e.ctrlKey,
				altKey: e.altKey,
				shiftKey: e.shiftKey
			}));
		}
		private function transformKeyUp(e: KeyboardEvent): void {
			MultiPulsator.emit(new Impulse("WINDOW_KEY_UP", {
				windowType: _type,
				window: this,
				keyCode: e.keyCode,
				charCode: e.charCode
			}));
		}
	
		private function transformMouseDown(e: MouseEvent): void {
			var isMenu: Boolean = isMenuElement(e.target as DisplayObject);
			if(!isMenu) {
				MultiPulsator.emit(new Impulse("WINDOW_LEFT_CLICK", {
					windowType: _type,
					window: this,
					stageX: e.stageX,
					stageY: e.stageY
				}));
				closeContextMenus();
			}
			var pin: Pin = getPinFromTarget(e.target as DisplayObject);
			if(pin) {
				MultiPulsator.emit(new Impulse("PIN_MOUSE_DOWN", {
					pin: pin,
					windowType: _type,
					stageX: e.stageX,
					stageY: e.stageY
				}));
			}
			MultiPulsator.emit(new Impulse("WINDOW_MOUSE_DOWN", {
				windowType: _type,
				window: this,
				stageX: e.stageX,
				stageY: e.stageY
			}));
		}
		private function transformMouseUp(e: MouseEvent): void {
			var pin: Pin = getPinFromTarget(e.target as DisplayObject);
			if(pin) {
				MultiPulsator.emit(new Impulse("PIN_MOUSE_UP", {
					pin: pin,
					windowType: _type
				}));
			}
			MultiPulsator.emit(new Impulse("WINDOW_MOUSE_UP", {
				windowType: _type,
				window: this,
				stageX: e.stageX,
				stageY: e.stageY
			}));
		}
		private function transformMouseMove(e: MouseEvent): void {
			MultiPulsator.emit(new Impulse("WINDOW_MOUSE_MOVE", {
				windowType: _type,
				window: this,
				stageX: e.stageX,
				stageY: e.stageY
			}));
		}
		private function transformMouseWheel(e: MouseEvent): void {
			MultiPulsator.emit(new Impulse("WINDOW_MOUSE_WHEEL", {
				windowType: _type,
				window: this,
				delta: e.delta,
				stageX: e.stageX,
				stageY: e.stageY
			}));
		}

		private function transformClick(e: MouseEvent): void {
			trace("--=== transformClick ===-- " + e.target)
			var isMenu: Boolean = isMenuElement(e.target as DisplayObject);
			if(!isMenu) {
				MultiPulsator.emit(new Impulse("WINDOW_CLICK", {
					windowType: _type,
					window: this,
					stageX: e.stageX,
					stageY: e.stageY
				}));
				MenuManager.getInstance().closeCurrentMenu();
			}
		}
	
		private function transformRightMouseDown(e: MouseEvent): void {
			trace("--===[!][transformRightMouseDown][!] ===-- " + e.target)

			if(_type !== "Editor" || isMenuElement(e.target as DisplayObject)) return;
			var target: DisplayObject = e.target as DisplayObject;
			var pos: Point = new Point(e.stageX, e.stageY);
			var atom: Atom = findClickedAtom(target);
			var track: Track = findClickedTrack(target);
			if(atom) {
				MultiPulsator.emit(new Impulse("ATOM_RIGHT_CLICK", {
					atom: atom,
					globalPosition: pos,
					window: this,
					windowType: _type
				}));
				e.stopPropagation();
			}
			else if(track) {
			trace("--===[!][     track     ][!] ===-- " + e.target)
				MultiPulsator.emit(new Impulse("TRACK_RIGHT_CLICK", {
					track: track,
					globalPosition: pos,
					window: this,
					windowType: _type
				}));
				e.stopPropagation();
			}
			else {
				MultiPulsator.emit(new Impulse("WINDOW_RIGHT_CLICK", {
					globalPosition: pos,
					window: this,
					windowType: _type,
					localPosition: _contentLayer.globalToLocal(pos)
				}));
			}
		}
		private function transformRightMouseUp(e: MouseEvent): void {}
		// =========================================================================
		// UTILS
		// =========================================================================
		/**
		 * Check if a display object is part of any context menu
		 * @param {DisplayObject} obj - Target display object
		 * @return {Boolean} True if object belongs to a context menu
		 */
		private function isMenuElement(obj:DisplayObject):Boolean {
			var current:DisplayObject = obj;
			while (current && current != stage) {
				if (current is ContextMenuItem || current is ContextMenu) {
					return true;
				}
				current = current.parent;
			}
			return false;
		}

	private function findClickedAtom(target: DisplayObject): Atom {
			var cur: DisplayObject = target;
			while(cur && cur != stage) {
				if(cur is AtomView) return(cur as AtomView).atom;
				if(cur is Pin) {
					var p: DisplayObject = cur.parent;
					while(p && p != stage) {
						if(p is AtomView) return(p as AtomView).atom;
						p = p.parent;
					}
				}
				cur = cur.parent;
			}
			return null;
		}
		private function findClickedTrack(target: DisplayObject): Track {
			var cur: DisplayObject = target;
			while(cur && cur != stage) {
				if(cur is Track) return cur as Track;
				cur = cur.parent;
			}
			return null;
		}
		private function getPinFromTarget(target: DisplayObject): Pin {
			var cur: DisplayObject = target;
			while(cur && !(cur is Pin) && cur.parent) {
				cur = cur.parent;
			}
			return cur as Pin;
		}
		public function closeContextMenus(): void {
			MenuManager.getInstance().closeCurrentMenu();
		}
		// =========================================================================
		// CONTENT
		// =========================================================================
		private function setupEditorContent(): void {
			_backgroundLayer.graphics.clear();
			_backgroundLayer.graphics.beginFill(0x1a1a2e);
			_backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
			_backgroundLayer.graphics.endFill();
			drawGrid();
			_contentLayer.addChild(createLabel("Editor | R-Click: Menu | Wheel: Zoom | MMB: Pan | Ctrl+D: Debug", -380, -280));
		}
		private function drawGrid(): void {
			var s: int = 10,
				c: uint = 0x2d2d4d;
			_backgroundLayer.graphics.lineStyle(1, c, 0.77);
			for(var x: int = -400; x <= 400; x += s) {
				_backgroundLayer.graphics.moveTo(x, -300);
				_backgroundLayer.graphics.lineTo(x, 300);
			}
			for(var y: int = -300; y <= 300; y += s) {
				_backgroundLayer.graphics.moveTo(-400, y);
				_backgroundLayer.graphics.lineTo(400, y);
			}
		}
		private function setupDeviceContent(): void {
			_backgroundLayer.graphics.clear();
			_backgroundLayer.graphics.beginFill(0x077770);
			_backgroundLayer.graphics.drawRect(-320, -240, 640, 480);
			_backgroundLayer.graphics.endFill();
			_contentLayer.addChild(createLabel("Device Window", 10, 10));
			if(!_isDesktop) this.alwaysInFront = false;
		}
		private function setupDefaultContent(): void {
			_backgroundLayer.graphics.clear();
			_backgroundLayer.graphics.beginFill(0x333333);
			_backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
			_backgroundLayer.graphics.endFill();
			_contentLayer.addChild(createLabel(_type + " Window", 10, 10));
		}
		private function createLabel(text: String, x: Number, y: Number): TextField {
			var tf: TextField = new TextField();
			tf.width = 500;
			tf.height = 60;
			tf.x = x;
			tf.y = y;
			tf.textColor = 0xFFFFFF;
			tf.selectable = false;
			tf.multiline = true;
			tf.wordWrap = true;
			var fmt: TextFormat = new TextFormat("Verdana", 12, 0xFFFFFF);
			tf.defaultTextFormat = fmt;
			tf.text = text;
			return tf;
		}
		// =========================================================================
		// DEBUG OVERLAY (Ctrl+D)
		// =========================================================================
		private function drawDebugOverlay(): void {
			var overlay: Sprite = _content.getChildByName("debugOverlay") as Sprite;
			if(!overlay) {
				overlay = new Sprite();
				overlay.name = "debugOverlay";
				overlay.mouseEnabled = false;
				_content.addChild(overlay);
			}
			overlay.graphics.clear();
			overlay.graphics.lineStyle(3, 0xFF0000, 0.8);
			overlay.graphics.drawRect(_canvas.x, _canvas.y, stage.stageWidth, stage.stageHeight);
			var tf: TextField = overlay.getChildByName("dbg") as TextField;
			if(!tf) {
				tf = new TextField();
				tf.name = "dbg";
				tf.width = 420;
				tf.height = 140;
				tf.background = true;
				tf.backgroundColor = 0x000000;
				tf.textColor = 0x00FF00;
				tf.x = 10;
				tf.y = 10;
				overlay.addChild(tf);
			}
			tf.text = "VIEWPOINT: " + _viewPoint.x.toFixed(1) + ", " + _viewPoint.y.toFixed(1) +
				"\nZOOM: " + _zoomLevel.toFixed(3) +
				"\nCANVAS: " + _canvas.x.toFixed(1) + ", " + _canvas.y.toFixed(1) +
				"\nMOUSE: " + stage.mouseX.toFixed(1) + ", " + stage.mouseY.toFixed(1) +
				"\nDRAG: " + (_isDragging ? "YES" : "NO");
		}
		// =========================================================================
		// DISPOSE
		// =========================================================================
		public function dispose(): void {
			trace("Disposing window: " + _type);
			removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			if(stage) {
				stage.removeEventListener(KeyboardEvent.KEY_DOWN, transformKeyDown);
				stage.removeEventListener(KeyboardEvent.KEY_UP, transformKeyUp);
				stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
				stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
				stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
				stage.removeEventListener(Event.MOUSE_LEAVE, onMouseLeave);
				stage.removeEventListener(Event.RESIZE, onStageResize);
				stage.removeEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
			}
			if(_backgroundLayer) {
			//	_backgroundLayer.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onBackgroundRightClick);
			}
			removeEventListener(Event.ACTIVATE, transformWindowActivate);
			removeEventListener(Event.DEACTIVATE, transformWindowDeactivate);
			removeEventListener(Event.CLOSING, transformWindowClosing);
			removeEventListener(Event.RESIZE, transformWindowResize);
			removeEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);
			stage.removeEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
			stage.removeEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
			stage.removeEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
			stage.removeEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
			stage.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
			stage.removeEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
			stage.removeEventListener(MouseEvent.CLICK, transformClick);
			if(_content && stage && stage.contains(_content)) {
				stage.removeChild(_content);
			}
			_content = _canvas = null;
		}
	}
}