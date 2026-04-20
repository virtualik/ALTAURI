#if cpp
package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Contact;

/**
 * COM ENUMERATOR WIDGET v1.0
 * Виджет отображения списка доступных COM-портов.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * ComEnumeratorWidget - это ЛИЦО (Face) для ComEnumeratorAtom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ComEnumeratorWidget                                                   │
 * │                                                                         │
 * │   ┌───────────────────────────────────────────────────────────────┐     │
 * │   │  [Title: COM Enumerator]                          [LED ●]    │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │                                                             │     │
 * │   │  Available Ports:                                           │     │
 * │   │                                                             │     │
 * │   │  ┌──────────────────────────────────────────────────────┐    │     │
 * │   │  │  COM1                              [Copy]            │    │     │
 * │   │  │  COM3                              [Copy]            │    │     │
 * │   │  │  COM5                              [Copy]            │    │     │
 * │   │  └──────────────────────────────────────────────────────┘    │     │
 * │   │                                                             │     │
 * │   │  Total: 3 ports                                             │     │
 * │   │  Raw: COM1,COM3,COM5                                        │     │
 * │   │                                                             │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget ЧИТАЕТ состояние из контакта "ports" атома                     │
 * │   Атом обновляет контакт через фоновый поток сканирования реестра       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * ОСОБЕННОСТИ:
 * ───────────
 * 1. Автоматическое обновление при подключении/отключении USB-COM адаптеров
 * 2. Отображение списка портов с кнопками копирования имени
 * 3. LED-индикатор активности сканирования
 * 4. Отображение сырой строки (raw) для отладки
 * 5. Счётчик обнаруженных портов
 */
class ComEnumeratorWidget extends DeviceView
{
	// =========================================================================
	// UI КОМПОНЕНТЫ
	// =========================================================================

	// Фон и заголовок
	private var _bg:Sprite;
	private var _header:Sprite;
	private var _titleLabel:TextField;

	// LED индикатор
	private var _statusLed:Sprite;
	private var _statusGlow:Sprite;

	// Список портов
	private var _portListContainer:Sprite;
	private var _portItems:Array<Sprite>;
	private var _copyButtons:Array<Sprite>;

	// Информационные поля
	private var _countLabel:TextField;
	private var _rawLabel:TextField;
	private var _rawValue:TextField;

	// Подпись
	private var _subtitleLabel:TextField;

	// =========================================================================
	// КОНФИГУРАЦИЯ
	// =========================================================================

	public var widgetWidth:Float = 250;
	public var widgetHeight:Float = 260;

	private var _colorBg:Int = 0x1a1a24;
	private var _colorHeader:Int = 0x2a2a3a;
	private var _colorAccent:Int = 0x00AAFF;
	private var _colorActive:Int = 0x00FF88;
	private var _colorInactive:Int = 0x333344;
	private var _colorText:Int = 0xFFFFFF;
	private var _colorMuted:Int = 0x888899;
	private var _colorInputBg:Int = 0x0d0d18;
	private var _colorPortItem:Int = 0x151528;
	private var _colorPortHover:Int = 0x252545;

	// =========================================================================
	// СОСТОЯНИЕ
	// =========================================================================

	private var _portsContact:Contact;
	private var _lastPortsStr:String = "";

	// Таймер LED пульсации при обновлении списка
	private var _ledPulseTimer:Float = 0;
	private var _ledPulseDuration:Float = 0.3;

	// =========================================================================
	// КОНСТРУКТОР
	// =========================================================================

	public function new(atom:Atom)
	{
		super(atom);

		// Находим контакты
		findContacts();

		// Строим UI
		buildUI();

		// Синхронизируем начальное состояние
		syncFromAtom();
	}

	// =========================================================================
	// ИНИЦИАЛИЗАЦИЯ
	// =========================================================================

	private function findContacts():Void
	{
		if (atom == null) return;
		_portsContact = atom.getOutput("ports");
	}

	override private function onActivate():Void
	{
		findContacts();
		syncFromAtom();
	}

	// =========================================================================
	// ПОСТРОЕНИЕ UI
	// =========================================================================

	private function buildUI():Void
	{
		var yPos:Float = 0;

		// === ФОН ===
		_bg = new Sprite();
		addChild(_bg);

		// === ЗАГОЛОВОК ===
		_header = new Sprite();
		_header.y = yPos;
		addChild(_header);

		_titleLabel = new TextField();
		_titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
		_titleLabel.text = "  COM ENUMERATOR";
		_titleLabel.width = widgetWidth - 40;
		_titleLabel.height = 28;
		_titleLabel.selectable = false;
		_titleLabel.mouseEnabled = false;
		_header.addChild(_titleLabel);

		// LED (зелёный - сканирование активно)
		_statusGlow = new Sprite();
		_statusGlow.graphics.beginFill(_colorActive, 0.15);
		_statusGlow.graphics.drawCircle(0, 0, 12);
		_statusGlow.graphics.endFill();
		_statusGlow.x = widgetWidth - 18;
		_statusGlow.y = 14;
		_statusGlow.visible = false;
		_header.addChild(_statusGlow);

		_statusLed = new Sprite();
		_statusLed.graphics.beginFill(0x004400);
		_statusLed.graphics.drawCircle(0, 0, 5);
		_statusLed.graphics.endFill();
		_statusLed.x = widgetWidth - 18;
		_statusLed.y = 14;
		_header.addChild(_statusLed);

		yPos += 32;

		// === ПОДЗАГОЛОВОК ===
		_subtitleLabel = new TextField();
		_subtitleLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
		_subtitleLabel.text = "Available Ports:";
		_subtitleLabel.width = widgetWidth - 20;
		_subtitleLabel.height = 16;
		_subtitleLabel.x = 10;
		_subtitleLabel.y = yPos;
		_subtitleLabel.selectable = false;
		addChild(_subtitleLabel);

		yPos += 20;

		// === КОНТЕЙНЕР СПИСКА ПОРТОВ ===
		_portListContainer = new Sprite();
		_portListContainer.y = yPos;
		addChild(_portListContainer);

		_portItems = [];
		_copyButtons = [];

		yPos += 140;

		// === СЧЁТЧИК ===
		_countLabel = new TextField();
		_countLabel.defaultTextFormat = new TextFormat("_typewriter", 11, _colorAccent, true);
		_countLabel.text = "Total: 0 ports";
		_countLabel.width = widgetWidth - 20;
		_countLabel.height = 18;
		_countLabel.x = 10;
		_countLabel.y = yPos;
		_countLabel.selectable = false;
		addChild(_countLabel);

		yPos += 22;

		// === RAW DATA ===
		_rawLabel = new TextField();
		_rawLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
		_rawLabel.text = "Raw:";
		_rawLabel.width = 30;
		_rawLabel.height = 14;
		_rawLabel.x = 10;
		_rawLabel.y = yPos;
		_rawLabel.selectable = false;
		addChild(_rawLabel);

		_rawValue = new TextField();
		_rawValue.defaultTextFormat = new TextFormat("_typewriter", 9, 0x666688);
		_rawValue.text = "";
		_rawValue.width = widgetWidth - 50;
		_rawValue.height = 28;
		_rawValue.x = 40;
		_rawValue.y = yPos - 2;
		_rawValue.selectable = true;
		_rawValue.mouseEnabled = true;
		_rawValue.multiline = true;
		_rawValue.wordWrap = true;
		addChild(_rawValue);

		// Финальная отрисовка фона
		redrawBackground();
	}

	private function redrawBackground():Void
	{
		// Основной фон
		_bg.graphics.clear();
		_bg.graphics.beginFill(_colorBg, 0.95);
		_bg.graphics.lineStyle(1, _colorAccent);
		_bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
		_bg.graphics.endFill();

		// Заголовок
		_header.graphics.clear();
		_header.graphics.beginFill(_colorHeader);
		_header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 28, 8, 8, 0, 0);
		_header.graphics.endFill();

		// Контейнер списка - фон
		_portListContainer.graphics.clear();
		_portListContainer.graphics.beginFill(_colorInputBg, 0.7);
		_portListContainer.graphics.lineStyle(1, 0x222233);
		_portListContainer.graphics.drawRoundRect(0, 0, widgetWidth - 20, 135, 4, 4);
		_portListContainer.graphics.endFill();
	}

	// =========================================================================
	// СИНХРОНИЗАЦИЯ С АТОМОМ
	// =========================================================================

	override private function syncFromAtom():Void
	{
		if (_portsContact != null && _portsContact.value != null)
		{
			var portsStr = Std.string(_portsContact.value);
			if (portsStr != _lastPortsStr)
			{
				updatePortsList(portsStr);
			}
		}
	}

	override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
	{
		if (isDisposed) return;

		if (contact == _portsContact)
		{
			var portsStr = (newValue != null) ? Std.string(newValue) : "";
			if (portsStr != _lastPortsStr)
			{
				updatePortsList(portsStr);
				pulseStatusLed();
			}
		}
	}

	// =========================================================================
	// ОБНОВЛЕНИЕ СПИСКА ПОРТОВ
	// =========================================================================

	private function updatePortsList(portsStr:String):Void
	{
		_lastPortsStr = portsStr;

		// Очищаем старые элементы
		clearPortItems();

		// Парсим строку "COM1,COM3,COM5"
		var ports:Array<String> = [];
		if (portsStr != null && portsStr != "")
		{
			ports = portsStr.split(",");
		}

		// Обновляем счётчик
		_countLabel.text = 'Total: ${ports.length} port${ports.length != 1 ? "s" : ""}';

		// Обновляем raw display
		_rawValue.text = portsStr != null ? portsStr : "";

		// Создаём элементы списка
		var itemY:Float = 5;
		var itemHeight:Float = 28;
		var maxVisible:Int = 4;

		for (i in 0...Std.int(Math.min(ports.length, maxVisible)))
		{
			var portName:String = StringTools.trim(ports[i]);

			// Контейнер элемента
			var item:Sprite = new Sprite();
			item.graphics.beginFill(_colorPortItem);
			item.graphics.drawRoundRect(0, 0, widgetWidth - 50, itemHeight, 3, 3);
			item.graphics.endFill();
			item.x = 5;
			item.y = itemY;
			item.buttonMode = true;
			item.useHandCursor = true;

			// Иконка порта
			var portIcon:Sprite = new Sprite();
			portIcon.graphics.beginFill(_colorAccent, 0.6);
			portIcon.graphics.drawRoundRect(4, 6, 16, 16, 2, 2);
			portIcon.graphics.endFill();

			var iconText:TextField = new TextField();
			iconText.defaultTextFormat = new TextFormat("_typewriter", 8, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
			iconText.text = "P";
			iconText.width = 16;
			iconText.height = 16;
			iconText.x = 4;
			iconText.y = 6;
			iconText.selectable = false;
			iconText.mouseEnabled = false;
			portIcon.addChild(iconText);
			item.addChild(portIcon);

			// Название порта
			var portLabel:TextField = new TextField();
			portLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
			portLabel.text = portName;
			portLabel.width = 120;
			portLabel.height = itemHeight;
			portLabel.x = 25;
			portLabel.selectable = false;
			portLabel.mouseEnabled = false;
			item.addChild(portLabel);

			// Кнопка Copy
			var copyBtn:Sprite = new Sprite();
			copyBtn.graphics.beginFill(0x334455);
			copyBtn.graphics.drawRoundRect(0, 3, 45, 22, 3, 3);
			copyBtn.graphics.endFill();
			copyBtn.x = widgetWidth - 100;
			copyBtn.y = 0;
			copyBtn.buttonMode = true;
			copyBtn.useHandCursor = true;

			var copyLabel:TextField = new TextField();
			copyLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted, null, null, null, null, null, TextFormatAlign.CENTER);
			copyLabel.text = "Copy";
			copyLabel.width = 45;
			copyLabel.height = 22;
			copyLabel.selectable = false;
			copyLabel.mouseEnabled = false;
			copyBtn.addChild(copyLabel);

			// Сохраняем имя порта для callback
			copyBtn.name = portName;
			copyBtn.addEventListener(MouseEvent.CLICK, onCopyClick);

			item.addChild(copyBtn);

			// Hover эффект
			item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent)
			{
				if (item != null)
				{
					item.graphics.clear();
					item.graphics.beginFill(_colorPortHover);
					item.graphics.drawRoundRect(0, 0, widgetWidth - 50, itemHeight, 3, 3);
					item.graphics.endFill();
				}
			});
			item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent)
			{
				if (item != null)
				{
					item.graphics.clear();
					item.graphics.beginFill(_colorPortItem);
					item.graphics.drawRoundRect(0, 0, widgetWidth - 50, itemHeight, 3, 3);
					item.graphics.endFill();
				}
			});

			_portListContainer.addChild(item);
			_portItems.push(item);
			_copyButtons.push(copyBtn);

			itemY += itemHeight + 3;
		}

		// Если портов больше, чем видно
		if (ports.length > maxVisible)
		{
			var moreLabel:TextField = new TextField();
			moreLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
			moreLabel.text = '... and ${ports.length - maxVisible} more';
			moreLabel.width = widgetWidth - 50;
			moreLabel.height = 16;
			moreLabel.x = 10;
			moreLabel.y = itemY;
			moreLabel.selectable = false;
			_portListContainer.addChild(moreLabel);
		}

		// Если портов нет
		if (ports.length == 0)
		{
			var emptyLabel:TextField = new TextField();
			emptyLabel.defaultTextFormat = new TextFormat("_typewriter", 11, _colorMuted, null, null, null, null, null, TextFormatAlign.CENTER);
			emptyLabel.text = "No COM ports found";
			emptyLabel.width = widgetWidth - 30;
			emptyLabel.height = 30;
			emptyLabel.x = 5;
			emptyLabel.y = 40;
			emptyLabel.selectable = false;
			_portListContainer.addChild(emptyLabel);
		}
	}

	private function clearPortItems():Void
	{
		// Удаляем все дочерние элементы контейнера, кроме первого (фон)
		while (_portListContainer.numChildren > 0)
		{
			var child = _portListContainer.getChildAt(_portListContainer.numChildren - 1);
			_portListContainer.removeChild(child);
		}

		// Очищаем массивы и снимаем слушатели
		for (btn in _copyButtons)
		{
			btn.removeEventListener(MouseEvent.CLICK, onCopyClick);
		}
		_portItems = [];
		_copyButtons = [];
	}

	// =========================================================================
	// ОБРАБОТЧИКИ СОБЫТИЙ
	// =========================================================================

	private function onCopyClick(e:MouseEvent):Void
	{
		var btn:Sprite = cast(e.currentTarget, Sprite);
		var portName:String = btn.name;

		// Копируем имя порта в системный буфер обмена (если доступно)
		try
		{
			openfl.Lib.current.stage.application.onWindowClose;
			// OpenFL Clipboard
			openfl.system.System.setClipboard(portName);
		}
		catch (e:Dynamic)
		{
			trace('ComEnumeratorWidget: Cannot copy to clipboard: $e');
		}

		// Визуальная обратная связь - кратковременно меняем цвет кнопки
		btn.graphics.clear();
		btn.graphics.beginFill(_colorActive);
		btn.graphics.drawRoundRect(0, 3, 45, 22, 3, 3);
		btn.graphics.endFill();

		// Восстанавливаем через 300мс
		haxe.Timer.delay(function()
		{
			if (btn != null)
			{
				btn.graphics.clear();
				btn.graphics.beginFill(0x334455);
				btn.graphics.drawRoundRect(0, 3, 45, 22, 3, 3);
				btn.graphics.endFill();
			}
		}, 300);
	}

	// =========================================================================
	// LED АНИМАЦИЯ
	// =========================================================================

	private function pulseStatusLed():Void
	{
		_statusLed.graphics.clear();
		_statusLed.graphics.beginFill(_colorActive);
		_statusLed.graphics.drawCircle(0, 0, 5);
		_statusLed.graphics.endFill();

		_statusGlow.graphics.clear();
		_statusGlow.graphics.beginFill(_colorActive, 0.3);
		_statusGlow.graphics.drawCircle(0, 0, 12);
		_statusGlow.graphics.endFill();
		_statusGlow.visible = true;

		_ledPulseTimer = _ledPulseDuration;
	}

	private function resetStatusLed():Void
	{
		_statusLed.graphics.clear();
		_statusLed.graphics.beginFill(0x004400);
		_statusLed.graphics.drawCircle(0, 0, 5);
		_statusLed.graphics.endFill();

		_statusGlow.visible = false;
	}

	override public function activate():Void
	{
		super.activate();
		if (stage != null)
		{
			stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		}
	}

	override public function deactivate():Void
	{
		super.deactivate();
		if (stage != null)
		{
			stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
	}

	private function onAddedToStage(e:Event):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
	}

	private function onEnterFrame(e:Event):Void
	{
		// Анимация затухания LED
		if (_ledPulseTimer > 0)
		{
			_ledPulseTimer -= 1.0 / 60.0;
			if (_ledPulseTimer <= 0)
			{
				_ledPulseTimer = 0;
				resetStatusLed();
			}
		}
	}

	// =========================================================================
	// DISPOSE
	// =========================================================================

	override public function dispose():Void
	{
		if (stage != null)
		{
			stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		}

		// Удаляем слушатели кнопок копирования
		for (btn in _copyButtons)
		{
			btn.removeEventListener(MouseEvent.CLICK, onCopyClick);
		}

		_bg = null;
		_header = null;
		_titleLabel = null;
		_statusLed = null;
		_statusGlow = null;
		_portListContainer = null;
		_portItems = null;
		_copyButtons = null;
		_countLabel = null;
		_rawLabel = null;
		_rawValue = null;
		_subtitleLabel = null;
		_portsContact = null;

		super.dispose();
	}
}
#end
