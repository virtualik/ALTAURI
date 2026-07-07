package ui;

import editor.EditorTheme;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;
import ui.ButtonComponent;

// =========================================================================
// v3.6: NATIVE WINDOWS DRAG (OS-Level Smoothness)
// =========================================================================
// Uses Win32 SendMessage to simulate title-bar click, letting the OS
// compositor handle window movement with zero frame lag.
// Falls back to Haxe-side absolute-position drag on non-Windows platforms.
#if windows
@:cppFileCode('
			  #ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

			  static HWND _dp_findMainWindow() {
			  DWORD pid = GetCurrentProcessId();
			  HWND best = NULL;
			  HWND hWnd = GetTopWindow(NULL);
			  while (hWnd != NULL) {
			  DWORD wpid = 0;
			  GetWindowThreadProcessId(hWnd, &wpid);
			  if (wpid == pid) {
			  LONG style = GetWindowLong(hWnd, GWL_STYLE);
			  if ((style & WS_VISIBLE)) {
			  HWND owner = GetWindow(hWnd, GW_OWNER);
			  if (owner == NULL) {
			  char cls[256] = {0};
			  GetClassNameA(hWnd, cls, 255);
			  if (strstr(cls, "SDL") || strstr(cls, "HXCPP") || strstr(cls, "OpenFL")) {
			  return hWnd;
			  }
			  if (best == NULL) best = hWnd;
			  }
			  }
			  }
			  hWnd = GetNextWindow(hWnd, GW_HWNDNEXT);
			  }
			  return best;
			  }
			  #endif
			  ')
#end

/**
* DEVICE PANEL v3.5 (Flicker-Free Window Drag)
* Full-size device display panel inside the Main Window.
*
* Architecture: "ATOM IS DATABANK & COMPUTE CORE"
*
* DevicePanel — built-in device dashboard inside the main window.
* An alternative to the separate DeviceWindow.
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   SCHEMATIC                         DEVICE PANEL                        │
* │                                                                         │
* │   [Hidden]                          ┌────────────────────────────┐      │
* │                                     │       DevicePanel          │      │
* │                                     │   ┌────────────────────┐   │      │
* │                                     │   │   DeviceCard       │   │      │
* │                                     │   │ ┌────────────────┐ │   │      │
* │                                     │   │ │   DeviceView   │ │   │      │
* │                                     │   │ └────────────────┘ │   │      │
* │                                     │   └────────────────────┘   │      │
* │                                     │                            │      │
* │                                     │   [E]  [C]          [X]    │      │
* │                                     │                   ↑ 40x40  │      │
* │                                     │              Editor-style  │      │
* │                                     └────────────────────────────┘      │
* │                                              │                          │
* │                                              │                          │
* │                                              ▼                          │
* │                               Main Window Color - DEVICE_CANVAS_BG_COLOR│
* └─────────────────────────────────────────────────────────────────────────┘
*
* v3.5 Changes:
* - FIXED: Window drag flicker/doubling issue.
*   Replaced incremental delta updates with absolute position calculation.
*   Now uses onWindowDragStart() to capture initial window position,
*   and onWindowDrag(dx, dy) receives delta from START position (not previous frame).
*   This eliminates accumulated rounding errors that caused 30-50px jitter.
*
* v3.4 Changes:
* - ADDED: Editor-style close button (ButtonComponent 40x40) in the same
*   position as Main.hx: x = stageWidth - 45, y = 5 (top-right corner).
* - ADDED: Button triggers application close with save confirmation.
* - SHIFTED: [E] and [C] buttons moved left to avoid overlap with the
*   large close button.
* - ADDED: Proper resize handling for close button position.
* - ADDED: Header drag functionality for moving the main application window.
*
* v3.3 Changes:
* - FIXED: Header buttons [E], [C] now stop MOUSE_DOWN propagation to prevent
*   them from interfering with any parent mouse handlers.
*/
class DevicePanel extends Sprite
{
	// =========================================================================
	// CALLBACKS
	// =========================================================================
	/**
	* Callback to request switching back to Editor Mode.
	* Called when [E] button is pressed.
	*/
	public var onShowEditor:Void -> Void;
	/**
	* Callback to get the list of available devices.
	* Used to populate the context menu.
	*/
	public var onGetAssemblyList:Void -> Array< {id:String, name:String, atom:Atom}>;
	/**
	* Callback for closing the application.
	* Called when [X] button is pressed.
	*/
	public var onCloseApp:Void -> Void;
	/**
	* v3.5: Called when drag starts. Main.hx must capture current window position.
	*/
	public var onWindowDragStart:Void -> Void;
	/**
	* v3.5: Called during drag with DELTA from START position (not previous frame).
	* @param dx Delta X from drag start (stage coordinates)
	* @param dy Delta Y from drag start (stage coordinates)
	*/
	public var onWindowDrag:Float -> Float -> Void;

	// =========================================================================
	// PRIVATE FIELDS
	// =========================================================================
	private var _assembly:Assembly;
	private var _deviceCards:Array<DeviceCard>;
	private var _header:Sprite;
	private var _titleLabel:TextField;
	private var _contextMenu:Sprite;
	private var _menuVisible:Bool = false;
	private var _bg:Sprite;
	private var _theme:EditorTheme;

	// =========================================================================
	// v3.4: EDITOR-STYLE CLOSE BUTTON
	// =========================================================================
	/**
	 * Large close button (40x40) in the top-right corner.
	 * Same style and position as Main.hx _btnClose.
	 * Triggers application close with save confirmation.
	 */
	private var _btnClose:ButtonComponent;

	// =========================================================================
	// v3.5: DRAG STATE (Absolute Position Model)
	// =========================================================================
	/**
	 * Drag state for header movement.
	 * Uses absolute position model to prevent flicker:
	 * - _mouseStartX/Y: Mouse position at drag start (stage coords)
	 * - _dragging: Is drag active?
	 *
	 * The window's initial position is stored in Main.hx via onWindowDragStart.
	 * On each mouse move, we compute: windowPos = startPos + (currentMouse - startMouse)
	 * This avoids accumulated rounding errors.
	 */
	private var _dragging:Bool = false;
	private var _mouseStartX:Float = 0;
	private var _mouseStartY:Float = 0;

	// =========================================================================
	// v3.6: NATIVE DRAG BRIDGE
	// =========================================================================
	/**
	 * Attempt to start native OS-level window drag.
	 * On Windows, uses SendMessage(WM_NCLBUTTONDOWN, HTCAPTION) to hand
	 * control to the DWM compositor — achieving perfect 1:1 cursor tracking
	 * with zero Haxe frame lag.
	 *
	 * SendMessage is SYNCHRONOUS: it blocks the Haxe thread until the user
	 * releases the mouse button. This means no Haxe code runs during drag,
	 * eliminating all sources of jitter.
	 *
	 * @return true if native drag was performed, false if fallback needed
	 */
	#if windows
	@:functionCode('
				   #ifdef _WIN32
				   HWND hWnd = _dp_findMainWindow();
				   if (hWnd == NULL) return false;
				   ReleaseCapture();
				   SendMessage(hWnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
				   return true;
				   #else
				   return false;
				   #endif
				   ')
	private static function _nativeStartDrag():Bool { return false; }
	#else
	private static function _nativeStartDrag():Bool { return false; }
	#end

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================
	public function new()
	{
		super();
		_deviceCards = new Array();
		_theme = EditorTheme.getInstance();
		addEventListener(Event.ADDED_TO_STAGE, onAdded);
	}

	private function onAdded(e:Event):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAdded);
		setupUI();
	}

	// =========================================================================
	// PUBLIC API
	// =========================================================================
	/**
	 * Resize the panel to fit the stage.
	 */
	public function setSize(w:Float, h:Float):Void
	{
		drawBackground(w, h);
		// Resize header
		if (_header != null)
		{
			_header.graphics.clear();
			_header.graphics.beginFill(0x2a2a34);
			_header.graphics.drawRect(0, 0, w, 30);
			_header.graphics.endFill();

			// =========================================================================
			// v3.4: REPOSITION BUTTONS ON RESIZE
			// =========================================================================
			// Keep buttons in the same positions as Main.hx
			if (_btnClose != null)
			{
				_btnClose.x = w - 45;
				_btnClose.y = 5;
			}

			// Recalculate positions for [E] and [C]
			var btnX = w - 45; // Start from close button position
			for (i in 0..._header.numChildren)
			{
				var child = _header.getChildAt(_header.numChildren - 1 - i);
				if (Std.isOfType(child, Sprite) && child != _titleLabel && child != _btnClose)
				{
					btnX -= (child.width + 10);
					child.x = btnX;
				}
			}
		}
	}

	/**
	 * Set the current assembly context.
	 * Updates the title.
	 */
	public function setContext(assembly:Assembly):Void
	{
		_assembly = assembly;
		_titleLabel.text = "  Device Panel: " + assembly.blueprint.name;
	}

	/**
	 * Add a device (atom) to the panel.
	 * v3.2: Emits DEVICE_WINDOW_CHANGED to save state.
	 */
	public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null):Void
	{
		if (atom == null) return;
		// Avoid duplicates
		for (card in _deviceCards)
		{
			if (card.atom == atom) return;
		}
		var card = new DeviceCard(atom, this);
		_deviceCards.push(card);
		addChild(card);
		if (x != null && y != null)
		{
			card.x = x;
			card.y = y;
		}
		else {
			var pos = findFreePosition(card);
			card.x = pos.x;
			card.y = pos.y;
		}
		// v3.2: Emit save signal when adding a new device
		Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
	}

	/**
	 * Remove a device card from the panel.
	 */
	public function removeDevice(card:DeviceCard):Void
	{
		if (_deviceCards.remove(card))
		{
			if (this.contains(card)) removeChild(card);
			card.dispose();
			Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
		}
	}

	/**
	 * Remove all devices.
	 *
	 * v3.1 NOTE: Does NOT emit DEVICE_WINDOW_CHANGED.
	 * If called during mode switch (after syncing cache), emitting here
	 * would cause the cache to be wiped immediately.
	 * Emission is handled manually in the [C] button callback for explicit clears.
	 */
	public function clearDevices():Void
	{
		while (_deviceCards.length > 0)
		{
			var card = _deviceCards.pop();
			if (this.contains(card)) removeChild(card);
			card.dispose();
		}
		// Do NOT emit event here to prevent cache wipe during mode switch
	}

	/**
	 * Returns the list of current device cards.
	 * Used by Main.hx to sync state to cache.
	 */
	public function getDeviceCards():Array<DeviceCard>
	{
		return _deviceCards;
	}

	// =========================================================================
	// SETUP UI
	// =========================================================================
	private function setupUI():Void
	{
		drawBackground(800, 600);
		createHeader();
		// Listeners
		stage.addEventListener(MouseEvent.CLICK, onStageClick);
		stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
		Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, onAtomDeleted);
	}

	private function drawBackground(w:Float, h:Float):Void
	{
		graphics.clear();
		// Alpha = 0 makes the background transparent!
		graphics.beginFill(_theme.DEVICE_CANVAS_BG_COLOR, 1.0);
		graphics.drawRect(0, 0, w, h);
		graphics.endFill();
	}

	private function createHeader():Void
	{
		var headerWidth = (stage != null) ? stage.stageWidth : 800;

		_header = new Sprite();
		_header.graphics.beginFill(0x2a2a34);
		_header.graphics.drawRect(0, 0, headerWidth, 30);
		_header.graphics.endFill();
		addChild(_header);

		_titleLabel = new TextField();
		_titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
		_titleLabel.text = "  Device Panel";
		_titleLabel.width = 300;
		_titleLabel.height = 30;
		_titleLabel.selectable = false;
		_titleLabel.mouseEnabled = false;
		_header.addChild(_titleLabel);

		// =========================================================================
		// v3.4: SHIFTED BUTTONS — moved left to avoid overlap with large [X]
		// Large close button occupies x: headerWidth-45 .. headerWidth-5
		// [C] button: headerWidth-90 .. headerWidth-62 (safe gap)
		// [E] button: headerWidth-120 .. headerWidth-92 (safe gap)
		// =========================================================================

		// Button [E] - Editor Mode
		var editorBtn = createHeaderButton("E", 0x005500, function(_)
		{
			if (onShowEditor != null) onShowEditor();
		});
		editorBtn.x = headerWidth - 120;  // v3.4: shifted from 760
		_header.addChild(editorBtn);

		// Button [C] - Clear
		// v3.1: Explicitly emit event after clearing so the empty state is saved.
		var clearBtn = createHeaderButton("C", 0x555500, function(_)
		{
			clearDevices();
			Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
		});
		clearBtn.x = headerWidth - 90;    // v3.4: shifted from 720
		_header.addChild(clearBtn);

		// =========================================================================
		// v3.4: CREATE EDITOR-STYLE CLOSE BUTTON
		// =========================================================================
		// Same position as Main.hx: x = stageWidth - 45, y = 5
		// Added to _header so it sits on top of the header background.
		_btnClose = new ButtonComponent("X", function()
		{
			if (onCloseApp != null) onCloseApp();
		});
		_btnClose.x = headerWidth - 45;
		_btnClose.y = 5;
		_header.addChild(_btnClose);
		// =========================================================================

		// =========================================================================
		// v3.4: HEADER DRAG FUNCTIONALITY
		// =========================================================================
		_header.addEventListener(MouseEvent.MOUSE_DOWN, onHeaderMouseDown);
		_header.buttonMode = true;
	}

	/**
	 * BUG 1 FIX: Header buttons now stop MOUSE_DOWN propagation.
	 * This prevents the MOUSE_DOWN event from bubbling up from the button
	 * to any parent container that might start an unwanted drag.
	 */
	private function createHeaderButton(label:String, color:Int, onClick:MouseEvent->Void):Sprite
	{
		var btn = new Sprite();
		btn.graphics.beginFill(color);
		btn.graphics.drawRect(0, 0, 28, 26);
		btn.graphics.endFill();
		var txt = new TextField();
		txt.text = label;
		txt.width = 28;
		txt.height = 26;
		txt.selectable = false;
		txt.mouseEnabled = false;
		txt.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, "center");
		btn.addChild(txt);
		btn.buttonMode = true;
		btn.addEventListener(MouseEvent.CLICK, onClick);
		// === BUG 1 FIX: Stop MOUSE_DOWN from propagating ===
		btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
		return btn;
	}

	// =========================================================================
	// v3.6: HEADER DRAG HANDLERS (Native-First with Haxe Fallback)
	// =========================================================================
	/**
	* Start dragging the MAIN WINDOW via DevicePanel header.
	*
	* v3.6 Strategy:
	*   1. Try native OS drag first (SendMessage on Windows) — perfect smoothness
	*   2. If native drag fails or on non-Windows — fall back to absolute-position Haxe drag
	*
	* Native drag blocks the thread until mouse-up, so no Haxe listeners are needed.
	*/
	private function onHeaderMouseDown(e:MouseEvent):Void
	{
		if (_dragging) return;

		// Check if click was on a button
		var targetObj:openfl.display.DisplayObject = cast e.target;
		while (targetObj != null && targetObj != _header)
		{
			if (Std.isOfType(targetObj, Sprite))
			{
				var s = cast(targetObj, Sprite);
				if (s.buttonMode && targetObj.parent == _header) return;
			}
			targetObj = targetObj.parent;
		}

		// =========================================================================
		// v3.6: TRY NATIVE OS DRAG FIRST
		// =========================================================================
		// On Windows, SendMessage(WM_NCLBUTTONDOWN, HTCAPTION) hands control
		// to the OS compositor. It BLOCKS until mouse-up — zero Haxe lag.
		// If it succeeds, we return immediately (no Haxe drag state needed).
		if (_nativeStartDrag())
		{
			// Native drag completed (user released mouse).
			// Window is now at its final position. Done.
			return;
		}
		//	MOUSE_DOWN
		//	  │
		//	  ▼
		//_nativeStartDrag()
		//	  │
		//	  ├── SendMessage(WM_NCLBUTTONDOWN, HTCAPTION)
		//	  │       │
		//	  │       ├── Windows OS берёт управление
		//	  │       ├── DWM compositor двигает окно (0 задержка)
		//	  │       ├── Haxe thread ЗАБЛОКИРОВАН (не тратит CPU)
		//	  │       └── Возврат только после MOUSE_UP
		//	  │
		//	  ▼
		//return;  // ← управление возвращается уже после завершения drag

		// =========================================================================

		// =========================================================================
		// FALLBACK: Haxe-side absolute-position drag (non-Windows or native failed)
		// =========================================================================
		_dragging = true;
		// v3.5: Store START mouse position (absolute, not delta)
		_mouseStartX = e.stageX;
		_mouseStartY = e.stageY;

		// v3.5: Notify Main.hx to capture current window position
		if (onWindowDragStart != null) onWindowDragStart();

		if (stage != null)
		{
			stage.addEventListener(MouseEvent.MOUSE_MOVE, onHeaderMouseMove);
			stage.addEventListener(MouseEvent.MOUSE_UP, onHeaderMouseUp);
		}

	
	}

	/**
	* Move the MAIN APPLICATION WINDOW during drag.
	* Computes delta from START position (not previous frame).
	*
	* v3.5: This eliminates accumulated rounding errors that caused flicker.
	* Main.hx computes: window.x = windowStartX + (currentMouseX - mouseStartX)
	*/
	private function onHeaderMouseMove(e:MouseEvent):Void
	{
		if (!_dragging) return;

		// v3.5: Delta from START position (absolute model)
		var dx = e.stageX - _mouseStartX;
		var dy = e.stageY - _mouseStartY;

		// Notify Main.hx with absolute delta
		if (onWindowDrag != null)
		{
			onWindowDrag(dx, dy);
		}
	}

	/**
	* End dragging.
	*/
	private function onHeaderMouseUp(e:MouseEvent):Void
	{
		_dragging = false;

		if (stage != null)
		{
			stage.removeEventListener(MouseEvent.MOUSE_MOVE, onHeaderMouseMove);
			stage.removeEventListener(MouseEvent.MOUSE_UP, onHeaderMouseUp);
		}
	}

	// =========================================================================
	// CONTEXT MENU
	// =========================================================================
	private function onRightClick(e:MouseEvent):Void
	{
		if (_menuVisible) hideContextMenu();
		else showContextMenu(e.stageX, e.stageY);
	}

	private function showContextMenu(x:Float, y:Float):Void
	{
		hideContextMenu(); // Clean previous
		_contextMenu = new Sprite();
		var yPos = 5;
		var headerItem = createMenuItem("Add Device:", null, true);
		headerItem.y = yPos;
		_contextMenu.addChild(headerItem);
		yPos += 28;
		// Get list from Main
		var devices = (onGetAssemblyList != null) ? onGetAssemblyList() : [];
		devices = [for (d in devices) if (d.id != "selfrun") d];
		if (devices.length == 0)
		{
			var emptyItem = createMenuItem("(No devices)", null, true);
			emptyItem.y = yPos;
			_contextMenu.addChild(emptyItem);
			yPos += 26;
		}
		else {
			for (item in devices)
			{
				var displayName = item.atom.displayName != null ? item.atom.displayName : item.atom.name;
				var menuItem = createMenuItem(displayName, item.atom, false);
				menuItem.y = yPos;
				_contextMenu.addChild(menuItem);
				yPos += 26;
			}
		}
		// Draw background
		_contextMenu.graphics.beginFill(0x333344, 0.98);
		_contextMenu.graphics.lineStyle(1, 0x555566);
		_contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 10, 6, 6);
		_contextMenu.graphics.endFill();
		_contextMenu.x = Math.min(x, stage.stageWidth - 200);
		_contextMenu.y = Math.min(Math.max(y - 30, 0), stage.stageHeight - yPos - 20);
		addChild(_contextMenu);
		_menuVisible = true;
	}

	private function hideContextMenu():Void
	{
		if (_contextMenu != null && _contextMenu.parent != null)
		{
			removeChild(_contextMenu);
		}
		_contextMenu = null;
		_menuVisible = false;
	}

	private function onStageClick(e:MouseEvent):Void
	{
		if (_menuVisible && _contextMenu != null)
		{
			if (!_contextMenu.hitTestPoint(e.stageX, e.stageY))
			{
				hideContextMenu();
			}
		}
	}

	private function createMenuItem(label:String, atom:Atom, disabled:Bool):Sprite
	{
		var item = new Sprite();
		item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
		item.graphics.drawRect(0, 0, 180, 24);
		item.graphics.endFill();
		var txt = new TextField();
		txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
		txt.text = (disabled || atom == null) ? label : "+ " + label;
		txt.width = 170;
		txt.height = 24;
		txt.x = 8;
		txt.selectable = false;
		txt.mouseEnabled = false;
		item.addChild(txt);
		if (!disabled && atom != null)
		{
			item.buttonMode = true;
			final capturedAtom = atom;
			item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent)
			{
				addDevice(capturedAtom);
				hideContextMenu();
				// Save state when adding via context menu
				// Note: addDevice() already emits DEVICE_WINDOW_CHANGED in v3.2
			});
			item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent)
			{
				item.graphics.clear();
				item.graphics.beginFill(0x556677);
				item.graphics.drawRect(0, 0, 180, 24);
				item.graphics.endFill();
			});
			item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent)
			{
				item.graphics.clear();
				item.graphics.beginFill(0x444455);
				item.graphics.drawRect(0, 0, 180, 24);
				item.graphics.endFill();
			});
		}
		return item;
	}

	// =========================================================================
	// EVENTS & HELPERS
	// =========================================================================
	private function onAtomDeleted(impulse:Impulse):Void
	{
		if (impulse.data == null) return;
		var deletedId:String = impulse.data.id;
		var toRemove:Array<DeviceCard> = [];
		for (card in _deviceCards)
		{
			if (card.atom != null && card.atom.id == deletedId)
			{
				toRemove.push(card);
			}
		}
		for (card in toRemove)
		{
			removeDevice(card);
		}
	}

	private function findFreePosition(card:DeviceCard): {x:Float, y:Float}
	{
		var startX = 10;
		var startY = 50; // Below header
		var stepX = 120;
		var stepY = 100;
		for (y in 0...10)
		{
			for (x in 0...5)
			{
				var px = startX + x * stepX;
				var py = startY + y * stepY;
				if (isPositionFree(px, py)) return {x: px, y: py};
			}
		}
		return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
	}

	private function isPositionFree(x:Float, y:Float):Bool
	{
		for (card in _deviceCards)
		{
			if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) return false;
		}
		return true;
	}

	public function dispose():Void
	{
		clearDevices();
		// =========================================================================
		// v3.4: CLEANUP CLOSE BUTTON
		// =========================================================================
		if (_btnClose != null)
		{
			if (_btnClose.parent != null)
			{
				_btnClose.parent.removeChild(_btnClose);
			}
			_btnClose = null;
		}
		// =========================================================================
		stage.removeEventListener(MouseEvent.CLICK, onStageClick);
		stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
		Impulsys.removeImpulse(EventType.ATOM_DELETED, onAtomDeleted);
	}
}