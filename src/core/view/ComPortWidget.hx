#if cpp
package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;

/**
 * COM PORT WIDGET v1.0
 * Интерактивная панель управления COM-портом.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * ComPortWidget - это ЛИЦО (Face) для ComPortAtom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ComPortWidget                                                         │
 * │                                                                         │
 * │   ┌───────────────────────────────────────────────────────────────┐     │
 * │   │  [Title: COM Port]                               [LED ●]      │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │                                                               │     │
 * │   │  PORT: [COM1        ]    BAUD: [9600       ]                  │     │
 * │   │                                                               │     │
 * │   │  [  OPEN  ]  [  CLOSE  ]     DTR: [ON/OFF]                    │     │
 * │   │                                                               │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │  TX: [_________________________] [SEND]                       │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │  ┌──────────────────────────────────────────────────────────┐ │     │
 * │   │  │  RX DATA:                                                │ │     │
 * │   │  │  Hello World                                             │ │     │
 * │   │  │                                                          │ │     │
 * │   │  └──────────────────────────────────────────────────────────┘ │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │  RX: ●  TX: ●  ERR: ●                                         │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget ЧИТАЕТ состояние из контактов атома (Databank)                 │
 * │   Widget ПИШЕТ в контакты при взаимодействии с пользователем            │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * ЭЛЕМЕНТЫ УПРАВЛЕНИЯ:
 * ───────────────────
 * 1. Поле имени порта и скорости (редактируемые)
 * 2. Кнопки OPEN / CLOSE для управления соединением
 * 3. Поле ввода TX и кнопка SEND для отправки данных
 * 4. Переключатель DTR
 * 5. Область отображения принятых данных (RX)
 * 6. LED-индикаторы: статус соединения, RX/TX/Error импульсы
 */
class ComPortWidget extends DeviceView
{
        // =========================================================================
        // КОНСТАНТЫ
        // =========================================================================
        private static var DEFAULT_BAUD_RATES:Array<Int> = [9600, 19200, 38400, 57600, 115200];

        // =========================================================================
        // UI КОМПОНЕНТЫ
        // =========================================================================

        // Фон и заголовок
        private var _bg:Sprite;
        private var _header:Sprite;
        private var _titleLabel:TextField;

        // Настройки порта
        private var _portLabel:TextField;
        private var _portInput:TextField;
        private var _baudLabel:TextField;
        private var _baudInput:TextField;

        // Кнопки управления
        private var _openBtn:Sprite;
        private var _closeBtn:Sprite;
        private var _dtrBtn:Sprite;
        private var _dtrLabel:TextField;

        // TX секция
        private var _txSection:Sprite;
        private var _txInput:TextField;
        private var _sendBtn:Sprite;

        // RX секция
        private var _rxSection:Sprite;
        private var _rxDisplay:TextField;
        private var _rxScrollPos:Int = 0;

        // Индикаторы
        private var _statusLed:Sprite;
        private var _statusGlow:Sprite;
        private var _rxLed:Sprite;
        private var _txLed:Sprite;
        private var _errLed:Sprite;

        // Статусная строка
        private var _statusBar:TextField;
        private var _errorDisplay:TextField;

        // =========================================================================
        // КОНФИГУРАЦИЯ
        // =========================================================================

		// Widget dimensions
        public var widgetWidth:Float = 300;
        public var widgetHeight:Float = 380;
		// widget size return (из за Reflect)
		override public function getWidgetSize():{width:Float, height:Float} {
			return {width: widgetWidth, height: widgetHeight};
		}

        private var _colorBg:Int = 0x1a1a24;
        private var _colorHeader:Int = 0x2a2a3a;
        private var _colorAccent:Int = 0x00AAFF;
        private var _colorActive:Int = 0x00FF88;
        private var _colorDanger:Int = 0xFF4444;
        private var _colorWarning:Int = 0xFFAA00;
        private var _colorInactive:Int = 0x333344;
        private var _colorText:Int = 0xFFFFFF;
        private var _colorMuted:Int = 0x888899;
        private var _colorInputBg:Int = 0x0d0d18;
        private var _colorRxGreen:Int = 0x00CC66;

        // =========================================================================
        // СОСТОЯНИЕ
        // =========================================================================

        private var _portNameContact:Contact;
        private var _baudRateContact:Contact;
        private var _openContact:Contact;
        private var _closeContact:Contact;
        private var _sendContact:Contact;
        private var _txDataContact:Contact;
        private var _setDTRContact:Contact;

        private var _isOpenContact:Contact;
        private var _rxDataContact:Contact;
        private var _rxTickContact:Contact;
        private var _txTickContact:Contact;
        private var _errorContact:Contact;
        private var _errorTickContact:Contact;

        private var _lastRxData:String = "";
        private var _lastError:String = "";

        // Таймеры для LED импульсов
        private var _rxLedTimer:Float = 0;
        private var _txLedTimer:Float = 0;
        private var _errLedTimer:Float = 0;
        private var _ledPulseDuration:Float = 0.15;

        // DTR состояние
        private var _dtrState:Bool = false;

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

                // Inputs
                _portNameContact = atom.getInput("portName");
                _baudRateContact = atom.getInput("baudRate");
                _openContact     = atom.getInput("open");
                _closeContact    = atom.getInput("close");
                _sendContact     = atom.getInput("send");
                _txDataContact   = atom.getInput("txData");
                _setDTRContact   = atom.getInput("setDTR");

                // Outputs
                _isOpenContact   = atom.getOutput("isOpen");
                _rxDataContact   = atom.getOutput("rxData");
                _rxTickContact   = atom.getOutput("rxTick");
                _txTickContact   = atom.getOutput("txTick");
                _errorContact    = atom.getOutput("error");
                _errorTickContact = atom.getOutput("errorTick");
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
                _titleLabel.text = "  COM PORT";
                _titleLabel.width = widgetWidth - 40;
                _titleLabel.height = 28;
                _titleLabel.selectable = false;
                _titleLabel.mouseEnabled = false;
                _header.addChild(_titleLabel);

                // Статус LED (правый верхний угол)
                _statusGlow = new Sprite();
                _statusGlow.graphics.beginFill(_colorDanger, 0.2);
                _statusGlow.graphics.drawCircle(0, 0, 12);
                _statusGlow.graphics.endFill();
                _statusGlow.x = widgetWidth - 18;
                _statusGlow.y = 14;
                _statusGlow.visible = false;
                _header.addChild(_statusGlow);

                _statusLed = new Sprite();
                _statusLed.graphics.beginFill(0x440000);
                _statusLed.graphics.drawCircle(0, 0, 6);
                _statusLed.graphics.endFill();
                _statusLed.x = widgetWidth - 18;
                _statusLed.y = 14;
                _header.addChild(_statusLed);

                yPos += 32;

                // === НАСТРОЙКИ ПОРТА ===
                _portLabel = createLabel("PORT");
                _portLabel.y = yPos;
                addChild(_portLabel);

                _baudLabel = createLabel("BAUD");
                _baudLabel.x = 150;
                _baudLabel.y = yPos;
                addChild(_baudLabel);

                yPos += 18;

                _portInput = createInputField("COM1", 130);
                _portInput.x = 10;
                _portInput.y = yPos;
                _portInput.addEventListener(Event.CHANGE, onPortNameChanged);
                addChild(_portInput);

                _baudInput = createInputField("9600", 100);
                _baudInput.x = 150;
                _baudInput.y = yPos;
                _baudInput.addEventListener(Event.CHANGE, onBaudRateChanged);
                addChild(_baudInput);

                yPos += 30;

                // === КНОПКИ OPEN / CLOSE ===
                _openBtn = createActionButton("OPEN", 0x225533, onOpenClick);
                _openBtn.x = 10;
                _openBtn.y = yPos;
                addChild(_openBtn);

                _closeBtn = createActionButton("CLOSE", 0x553322, onCloseClick);
                _closeBtn.x = 95;
                _closeBtn.y = yPos;
                addChild(_closeBtn);

                // DTR toggle
                _dtrBtn = new Sprite();
                _dtrBtn.graphics.beginFill(_colorInactive);
                _dtrBtn.graphics.drawRoundRect(0, 0, 50, 26, 4, 4);
                _dtrBtn.graphics.endFill();

                _dtrLabel = new TextField();
                _dtrLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted, true, null, null, null, null, TextFormatAlign.CENTER);
                _dtrLabel.text = "DTR";
                _dtrLabel.width = 50;
                _dtrLabel.height = 26;
                _dtrLabel.selectable = false;
                _dtrLabel.mouseEnabled = false;
                _dtrBtn.addChild(_dtrLabel);

                _dtrBtn.x = 200;
                _dtrBtn.y = yPos;
                _dtrBtn.buttonMode = true;
                _dtrBtn.useHandCursor = true;
                _dtrBtn.addEventListener(MouseEvent.CLICK, onDTRClick);
                addChild(_dtrBtn);

                yPos += 36;

                // === СЕКЦИЯ TX ===
                _txSection = new Sprite();
                _txSection.y = yPos;
                addChild(_txSection);

                var txLabel = new TextField();
                txLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                txLabel.text = "TX DATA";
                txLabel.width = 60;
                txLabel.height = 15;
                txLabel.selectable = false;
                _txSection.addChild(txLabel);

                _txInput = createInputField("", Std.int(widgetWidth - 80));
                _txInput.x = 0;
                _txInput.y = 15;
                _txInput.addEventListener(KeyboardEvent.KEY_DOWN, onTxKeyDown);
                _txSection.addChild(_txInput);

                _sendBtn = createActionButton("SEND", 0x224466, onSendClick);
                _sendBtn.x = widgetWidth - 62;
                _sendBtn.y = 14;
                _txSection.addChild(_sendBtn);

                yPos += 52;

                // === СЕКЦИЯ RX ===
                _rxSection = new Sprite();
                _rxSection.y = yPos;
                addChild(_rxSection);

                var rxLabel = new TextField();
                rxLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                rxLabel.text = "RX DATA";
                rxLabel.width = 60;
                rxLabel.height = 15;
                rxLabel.selectable = false;
                _rxSection.addChild(rxLabel);

                // Область отображения принятых данных
                _rxDisplay = new TextField();
                _rxDisplay.defaultTextFormat = new TextFormat("_typewriter", 11, _colorRxGreen);
                _rxDisplay.text = "";
                _rxDisplay.width = widgetWidth - 20;
                _rxDisplay.height = 100;
                _rxDisplay.x = 5;
                _rxDisplay.y = 15;
                _rxDisplay.background = true;
                _rxDisplay.backgroundColor = _colorInputBg;
                _rxDisplay.border = true;
                _rxDisplay.borderColor = 0x222233;
                _rxDisplay.multiline = true;
                _rxDisplay.wordWrap = true;
                _rxDisplay.selectable = true;
                _rxDisplay.mouseEnabled = true;
                _rxSection.addChild(_rxDisplay);

                yPos += 125;

                // === ИНДИКАТОРЫ ===
                var indicatorY:Float = yPos;

                // Статус-бар
                _statusBar = new TextField();
                _statusBar.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
                _statusBar.text = "Disconnected";
                _statusBar.width = 140;
                _statusBar.height = 16;
                _statusBar.x = 10;
                _statusBar.y = indicatorY;
                _statusBar.selectable = false;
                addChild(_statusBar);

                // RX LED
                var rxLedLabel = new TextField();
                rxLedLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                rxLedLabel.text = "RX";
                rxLedLabel.width = 20;
                rxLedLabel.height = 14;
                rxLedLabel.x = 120;
                rxLedLabel.y = indicatorY;
                rxLedLabel.selectable = false;
                addChild(rxLedLabel);

                _rxLed = new Sprite();
                _rxLed.graphics.beginFill(0x003300);
                _rxLed.graphics.drawCircle(0, 0, 5);
                _rxLed.graphics.endFill();
                _rxLed.x = 145;
                _rxLed.y = indicatorY + 7;
                addChild(_rxLed);

                // TX LED
                var txLedLabel = new TextField();
                txLedLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                txLedLabel.text = "TX";
                txLedLabel.width = 20;
                txLedLabel.height = 14;
                txLedLabel.x = 160;
                txLedLabel.y = indicatorY;
                txLedLabel.selectable = false;
                addChild(txLedLabel);

                _txLed = new Sprite();
                _txLed.graphics.beginFill(0x003300);
                _txLed.graphics.drawCircle(0, 0, 5);
                _txLed.graphics.endFill();
                _txLed.x = 185;
                _txLed.y = indicatorY + 7;
                addChild(_txLed);

                // ERR LED
                var errLedLabel = new TextField();
                errLedLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                errLedLabel.text = "ERR";
                errLedLabel.width = 25;
                errLedLabel.height = 14;
                errLedLabel.x = 200;
                errLedLabel.y = indicatorY;
                errLedLabel.selectable = false;
                addChild(errLedLabel);

                _errLed = new Sprite();
                _errLed.graphics.beginFill(0x330000);
                _errLed.graphics.drawCircle(0, 0, 5);
                _errLed.graphics.endFill();
                _errLed.x = 228;
                _errLed.y = indicatorY + 7;
                addChild(_errLed);

                // Error display
                _errorDisplay = new TextField();
                _errorDisplay.defaultTextFormat = new TextFormat("_typewriter", 9, _colorDanger);
                _errorDisplay.text = "";
                _errorDisplay.width = widgetWidth - 20;
                _errorDisplay.height = 15;
                _errorDisplay.x = 10;
                _errorDisplay.y = indicatorY + 18;
                _errorDisplay.selectable = false;
                addChild(_errorDisplay);

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

                // TX секция фон
                _txSection.graphics.clear();
                _txSection.graphics.beginFill(0x0d0d18, 0.5);
                _txSection.graphics.lineStyle(1, 0x222244);
                _txSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 45, 4, 4);
                _txSection.graphics.endFill();

                // RX секция фон
                _rxSection.graphics.clear();
                _rxSection.graphics.beginFill(0x0d0d18, 0.5);
                _rxSection.graphics.lineStyle(1, 0x224422);
                _rxSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 120, 4, 4);
                _rxSection.graphics.endFill();
        }

        // =========================================================================
        // СОЗДАНИЕ UI ЭЛЕМЕНТОВ
        // =========================================================================

        private function createLabel(text:String):TextField
        {
                var tf = new TextField();
                tf.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                tf.text = text;
                tf.width = 60;
                tf.height = 16;
                tf.x = 10;
                tf.selectable = false;
                tf.mouseEnabled = false;
                return tf;
        }

        private function createInputField(defaultText:String, width:Int):TextField
        {
                var tf = new TextField();
                tf.defaultTextFormat = new TextFormat("_typewriter", 12, _colorText);
                tf.text = defaultText;
                tf.width = width;
                tf.height = 22;
                tf.background = true;
                tf.backgroundColor = _colorInputBg;
                tf.border = true;
                tf.borderColor = 0x333355;
                tf.type = TextFieldType.INPUT;
                tf.selectable = true;
                tf.mouseEnabled = true;
                return tf;
        }

        private function createActionButton(label:String, color:Int, callback:MouseEvent -> Void):Sprite
        {
                var btn = new Sprite();
                btn.graphics.beginFill(color);
                btn.graphics.drawRoundRect(0, 0, 75, 26, 4, 4);
                btn.graphics.endFill();

                var tf = new TextField();
                tf.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
                tf.text = label;
                tf.width = 75;
                tf.height = 26;
                tf.selectable = false;
                tf.mouseEnabled = false;
                btn.addChild(tf);

                btn.buttonMode = true;
                btn.useHandCursor = true;
                btn.addEventListener(MouseEvent.CLICK, callback);

                return btn;
        }

        // =========================================================================
        // СИНХРОНИЗАЦИЯ С АТОМОМ
        // =========================================================================

        override private function syncFromAtom():Void
        {
                // Считываем текущие значения контактов и обновляем UI
                if (_portNameContact != null && _portNameContact.value != null)
                {
                        _portInput.text = Std.string(_portNameContact.value);
                }

                if (_baudRateContact != null && _baudRateContact.value != null)
                {
                        _baudInput.text = Std.string(_baudRateContact.value);
                }

                if (_isOpenContact != null && _isOpenContact.value != null)
                {
                        updateConnectionStatus(_isOpenContact.value == true);
                }

                if (_rxDataContact != null && _rxDataContact.value != null)
                {
                        var rxStr = Std.string(_rxDataContact.value);
                        if (rxStr != "" && rxStr != _lastRxData)
                        {
                                appendRxData(rxStr);
                        }
                }

                if (_errorContact != null && _errorContact.value != null)
                {
                        var errStr = Std.string(_errorContact.value);
                        if (errStr != "" && errStr != _lastError)
                        {
                                _errorDisplay.text = "Error: " + errStr;
                                _lastError = errStr;
                        }
                }
        }

        override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
        {
                if (isDisposed) return;

                if (contact == _isOpenContact)
                {
                        updateConnectionStatus(newValue == true);
                }
                else if (contact == _rxDataContact)
                {
                        if (newValue != null && newValue != "")
                        {
                                appendRxData(Std.string(newValue));
                        }
                }
                else if (contact == _rxTickContact)
                {
                        if (newValue == true)
                        {
                                pulseLed(_rxLed, 0x00FF00, 0x003300);
                                _rxLedTimer = _ledPulseDuration;
                        }
                }
                else if (contact == _txTickContact)
                {
                        if (newValue == true)
                        {
                                pulseLed(_txLed, 0x00AAFF, 0x001133);
                                _txLedTimer = _ledPulseDuration;
                        }
                }
                else if (contact == _errorTickContact)
                {
                        if (newValue == true)
                        {
                                pulseLed(_errLed, 0xFF4444, 0x330000);
                                _errLedTimer = _ledPulseDuration;
                        }
                }
                else if (contact == _errorContact)
                {
                        if (newValue != null && newValue != "")
                        {
                                _errorDisplay.text = "Error: " + Std.string(newValue);
                                _lastError = Std.string(newValue);
                        }
                        else
                        {
                                _errorDisplay.text = "";
                                _lastError = "";
                        }
                }
        }

        // =========================================================================
        // ОБНОВЛЕНИЕ UI
        // =========================================================================

        private function updateConnectionStatus(isOpen:Bool):Void
        {
                if (isOpen)
                {
                        // Порт открыт - зелёный LED
                        _statusLed.graphics.clear();
                        _statusLed.graphics.beginFill(_colorActive);
                        _statusLed.graphics.drawCircle(0, 0, 6);
                        _statusLed.graphics.endFill();

                        _statusGlow.graphics.clear();
                        _statusGlow.graphics.beginFill(_colorActive, 0.2);
                        _statusGlow.graphics.drawCircle(0, 0, 12);
                        _statusGlow.graphics.endFill();
                        _statusGlow.visible = true;

                        _statusBar.text = "Connected";
                        _statusBar.textColor = _colorActive;
                }
                else
                {
                        // Порт закрыт - красный LED
                        _statusLed.graphics.clear();
                        _statusLed.graphics.beginFill(0x440000);
                        _statusLed.graphics.drawCircle(0, 0, 6);
                        _statusLed.graphics.endFill();

                        _statusGlow.visible = false;

                        _statusBar.text = "Disconnected";
                        _statusBar.textColor = _colorMuted;
                }
        }

        private function appendRxData(data:String):Void
        {
                if (_rxDisplay == null) return;

                _lastRxData = data;
                var currentText = _rxDisplay.text;

                // Добавляем новые данные
                if (currentText.length > 2000)
                {
                        // Ограничиваем буфер отображения - оставляем последние 1000 символов
                        currentText = currentText.substr(currentText.length - 1000);
                }

                _rxDisplay.text = currentText + data;

                // Автопрокрутка вниз
                _rxDisplay.scrollV = _rxDisplay.maxScrollV;
        }

        private function pulseLed(led:Sprite, onColor:Int, offColor:Int):Void
        {
                if (led == null) return;
                led.graphics.clear();
                led.graphics.beginFill(onColor);
                led.graphics.drawCircle(0, 0, 5);
                led.graphics.endFill();
        }

        private function resetLed(led:Sprite, offColor:Int):Void
        {
                if (led == null) return;
                led.graphics.clear();
                led.graphics.beginFill(offColor);
                led.graphics.drawCircle(0, 0, 5);
                led.graphics.endFill();
        }

        // =========================================================================
        // ОБРАБОТЧИКИ СОБЫТИЙ
        // =========================================================================

        private function onPortNameChanged(e:Event):Void
        {
                if (_portNameContact != null)
                {
                        _portNameContact.value = _portInput.text;
                }
        }

        private function onBaudRateChanged(e:Event):Void
        {
                if (_baudRateContact != null)
                {
                        var baud = Std.parseInt(_baudInput.text);
                        if (baud != null && baud > 0)
                        {
                                _baudRateContact.value = baud;
                        }
                }
        }

        private function onOpenClick(e:MouseEvent):Void
        {
                // Сначала обновляем параметры порта
                if (_portNameContact != null) _portNameContact.value = _portInput.text;

                var baud = Std.parseInt(_baudInput.text);
                if (_baudRateContact != null && baud != null && baud > 0)
                {
                        _baudRateContact.value = baud;
                }

                // Триггерим открытие
                if (_openContact != null)
                {
                        _openContact.value = true;
                }
        }

        private function onCloseClick(e:MouseEvent):Void
        {
                if (_closeContact != null)
                {
                        _closeContact.value = true;
                }
        }

        private function onSendClick(e:MouseEvent):Void
        {
                sendTxData();
        }

        private function onTxKeyDown(e:KeyboardEvent):Void
        {
                if (e.keyCode == Keyboard.ENTER)
                {
                        sendTxData();
                }
        }

        private function sendTxData():Void
        {
                if (_txDataContact != null)
                {
                        _txDataContact.value = _txInput.text;
                }
                if (_sendContact != null)
                {
                        _sendContact.value = true;
                }
                // Не очищаем поле ввода - пользователь может захотеть отправить повторно
        }

        private function onDTRClick(e:MouseEvent):Void
        {
                _dtrState = !_dtrState;

                if (_setDTRContact != null)
                {
                        _setDTRContact.value = _dtrState;
                }

                // Обновляем визуал кнопки
                _dtrBtn.graphics.clear();
                if (_dtrState)
                {
                        _dtrBtn.graphics.beginFill(_colorActive);
                        _dtrLabel.textColor = 0x000000;
                }
                else
                {
                        _dtrBtn.graphics.beginFill(_colorInactive);
                        _dtrLabel.textColor = _colorMuted;
                }
                _dtrBtn.graphics.drawRoundRect(0, 0, 50, 26, 4, 4);
                _dtrBtn.graphics.endFill();
        }

        // =========================================================================
        // ОБНОВЛЕНИЕ (для анимации LED)
        // =========================================================================

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
                // Анимация затухания LED-импульсов
                var dt:Float = 1.0 / 60.0;

                if (_rxLedTimer > 0)
                {
                        _rxLedTimer -= dt;
                        if (_rxLedTimer <= 0)
                        {
                                resetLed(_rxLed, 0x003300);
                        }
                }

                if (_txLedTimer > 0)
                {
                        _txLedTimer -= dt;
                        if (_txLedTimer <= 0)
                        {
                                resetLed(_txLed, 0x001133);
                        }
                }

                if (_errLedTimer > 0)
                {
                        _errLedTimer -= dt;
                        if (_errLedTimer <= 0)
                        {
                                resetLed(_errLed, 0x330000);
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

                // Удаляем слушатели
                if (_openBtn != null) _openBtn.removeEventListener(MouseEvent.CLICK, onOpenClick);
                if (_closeBtn != null) _closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick);
                if (_sendBtn != null) _sendBtn.removeEventListener(MouseEvent.CLICK, onSendClick);
                if (_dtrBtn != null) _dtrBtn.removeEventListener(MouseEvent.CLICK, onDTRClick);
                if (_portInput != null) _portInput.removeEventListener(Event.CHANGE, onPortNameChanged);
                if (_baudInput != null) _baudInput.removeEventListener(Event.CHANGE, onBaudRateChanged);
                if (_txInput != null) _txInput.removeEventListener(KeyboardEvent.KEY_DOWN, onTxKeyDown);

                _bg = null;
                _header = null;
                _titleLabel = null;
                _portLabel = null;
                _portInput = null;
                _baudLabel = null;
                _baudInput = null;
                _openBtn = null;
                _closeBtn = null;
                _dtrBtn = null;
                _dtrLabel = null;
                _txSection = null;
                _txInput = null;
                _sendBtn = null;
                _rxSection = null;
                _rxDisplay = null;
                _statusLed = null;
                _statusGlow = null;
                _rxLed = null;
                _txLed = null;
                _errLed = null;
                _statusBar = null;
                _errorDisplay = null;

                _portNameContact = null;
                _baudRateContact = null;
                _openContact = null;
                _closeContact = null;
                _sendContact = null;
                _txDataContact = null;
                _setDTRContact = null;
                _isOpenContact = null;
                _rxDataContact = null;
                _rxTickContact = null;
                _txTickContact = null;
                _errorContact = null;
                _errorTickContact = null;

                super.dispose();
        }
}
#end
