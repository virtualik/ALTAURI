package Src.Prog.Com.Atoms.Data {
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.display.Graphics;

    /**
     * Central registry for all atom definitions in the system
     * ALL atoms must be registered here to be available in the application
     */
    public class AtomDefinitions {
        private static var _definitions:Object = {};
        private static var _initialized:Boolean = false;

        /**
         * Static helper function for drawing LED atoms
         * 
         * @public
         * @static
         * @param {Graphics} graphics - Graphics object to draw on
         * @param {Atom} atom - Atom instance with data
         * @param {Object} config - Visual configuration
         */
        public static function drawLED(graphics:Graphics, atom:Atom, config:Object):void {
            trace("=== LED CUSTOM DRAW FUNCTION EXECUTING ===");
            trace("Atom data in draw: " + JSON.stringify(atom.data));
            trace("isOn value: " + atom.data.isOn);
            trace("Config width: " + config.width + ", height: " + config.height);
            
            // Защита от невалидных параметров
            var width:Number = config.width || 30;
            var height:Number = config.height || 30;
            var centerX:Number = width / 2;
            var centerY:Number = height / 2;
            
            var isOn:Boolean = atom.data.isOn === true;
            var color:uint = isOn ? 0x00FF00 : 0x333333;
            var glowColor:uint = isOn ? 0x80FF80 : 0x666666;

            trace("Drawing LED - isOn: " + isOn + ", color: " + color.toString(16) + ", center: " + centerX + "," + centerY);

            graphics.clear();

            try {
                // Рисуем свечение (только когда включен)
                if (isOn) {
                    graphics.beginFill(glowColor, 0.3);
                    var glowRadius:Number = Math.max(1, width / 1.5);
                    graphics.drawCircle(centerX, centerY, glowRadius);
                    graphics.endFill();
                }

                // Рисуем основной светодиод
                graphics.beginFill(color);
                var ledRadius:Number = Math.max(1, width / 2 - 2);
                graphics.drawCircle(centerX, centerY, ledRadius);
                graphics.endFill();

                // Обводка
                graphics.lineStyle(1, 0x666666);
                graphics.drawCircle(centerX, centerY, ledRadius);
                
                trace("=== LED CUSTOM DRAW FUNCTION COMPLETED ===");
            } catch (error:Error) {
                trace("ERROR in LED drawing: " + error.message);
                // Фолбэк: простой прямоугольник
                graphics.beginFill(0xFF0000);
                graphics.drawRect(0, 0, width, height);
                graphics.endFill();
            }
        }

        /**
         * Register all atom definitions - call this once at app startup
         */
        public static function initialize():void {
            if (_initialized) {
                trace("AtomDefinitions: Already initialized");
                return;
            }

            trace("AtomDefinitions: Initializing atom registry...");

            // Input Atoms
			registerAtomType("Button", {
				displayName: "Button",
				category: "Input",
				description: "A simple push button that sends TRUE when pressed and FALSE when released",
				pins: [
					{name: "output", type: "output", dataType: "boolean", description: "Sends TRUE when pressed, FALSE when released"}
				],
				behavior: {
					onInteraction: function(atom:Atom, interactionType:String):Atom {
						if (interactionType == "press") {
							trace("Button pressed - sending TRUE signal");
							
							// Создаем новый атом с обновленным значением пина
							var newAtom:Atom = atom.setPinValue("output", true, false);
							
							// Эмитим импульс о изменении значения пина
							MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
								atomId: newAtom.id,
								pinName: "output",
								newValue: true,
								oldValue: atom.outputs[0].value,
								source: "button_press"
							}));
							
							return newAtom;
						}
						return atom;
					},
					
					onRelease: function(atom:Atom):Atom {
						trace("Button released - sending FALSE signal");
						
						var newAtom:Atom = atom.setPinValue("output", false, false);
						
						MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
							atomId: newAtom.id,
							pinName: "output",
							newValue: false,
							oldValue: atom.outputs[0].value,
							source: "button_release"
						}));
						
						return newAtom;
					},

					onRightClick: function(atom:Atom):Atom {
						trace("Button right-click - sending FALSE signal");
						
						var newAtom:Atom = atom.setPinValue("output", false, false);
						
						MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
							atomId: newAtom.id,
							pinName: "output", 
							newValue: false,
							oldValue: atom.outputs[0].value,
							source: "button_right_click"
						}));
						
						return newAtom;
					}
				},
				viewConfig: {
					width: 60,
					height: 30,
					backgroundColor: 0x3366CC
				},
				visuals: {
					base: {
						width: 60,
						height: 30,
						color: 0x3366CC,
						textColor: 0x000000,
						cornerRadius: 8
					},
					Editor: {
						// специфичные настройки для Editor
					}
				}
			});

            registerAtomType("Toggle", {
                displayName: "Toggle Switch", 
                category: "Input",
                description: "A switch that toggles between on/off states",
                pins: [
                    {name: "state", type: "output", dataType: "boolean", description: "Current toggle state"}
                ],
                viewConfig: {
                    width: 50,
                    height: 25,
                    backgroundColor: 0x66AA66
                },
                visuals: {
                    base: {
                        width: 50,
                        height: 25,
                        color: 0x66AA66,
                        textColor: 0x000000
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("Slider", {
                displayName: "Slider",
                category: "Input",
                description: "A slider for selecting numeric values",
                pins: [
                    {name: "value", type: "output", dataType: "number", description: "Current slider value"}
                ],
                viewConfig: {
                    width: 100,
                    height: 30,
                    backgroundColor: 0xCC6633
                },
                visuals: {
                    base: {
                        width: 100,
                        height: 30,
                        color: 0xCC6633,
                        textColor: 0x000000
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            // Logic Atoms
			registerAtomType("AND", {
				displayName: "AND Gate",
				category: "Logic",
				description: "Logical AND gate - output is TRUE only when both inputs are TRUE",
				pins: [
					{name: "input1", type: "input", dataType: "boolean", description: "First input signal"},
					{name: "input2", type: "input", dataType: "boolean", description: "Second input signal"},
					{name: "output", type: "output", dataType: "boolean", description: "Output signal (input1 AND input2)"}
				],
				behavior: {
					onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
						trace("=== AND GATE INPUT CHANGE ===");
						trace("Pin: " + pinName + ", Value: " + value);
						
						// Обновляем значение входящего пина в данных атома
						var newAtom:Atom = atom.setData(pinName, Boolean(value));
						
						// Получаем текущие значения обоих входов
						var input1:Boolean = newAtom.data.input1 === true;
						var input2:Boolean = newAtom.data.input2 === true;
						
						trace("Input1: " + input1 + ", Input2: " + input2);
						
						// Вычисляем результат AND
						var result:Boolean = input1 && input2;
						trace("AND Result: " + result);
						
						// Создаем атом с обновленным выходным значением
						var finalAtom:Atom = newAtom.setPinValue("output", result, false);
						
						// Эмитим импульс об изменении выходного значения
						MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
							atomId: finalAtom.id,
							pinName: "output",
							newValue: result,
							oldValue: atom.outputs[0] ? atom.outputs[0].value : false,
							source: "and_gate"
						}));
						
						trace("=== END AND GATE ===");
						return finalAtom;
					},
					
					// Инициализация - устанавливаем начальные значения
					initialize: function(atom:Atom):Atom {
						trace("AND Gate initialized");
						// Инициализируем данные входов как false, если они не установлены
						var newAtom:Atom = atom;
						if (!atom.hasValue("input1")) {
							newAtom = newAtom.setData("input1", false);
						}
						if (!atom.hasValue("input2")) {
							newAtom = newAtom.setData("input2", false);
						}
						// Устанавливаем начальное выходное значение
						newAtom = newAtom.setPinValue("output", false, false);
						return newAtom;
					}
				},
				viewConfig: {
					width: 70,
					height: 50,
					backgroundColor: 0x6666CC
				},
				visuals: {
					base: {
						width: 70,
						height: 50,
						color: 0x6666CC,
						textColor: 0xFFFFFF,
						cornerRadius: 5,
					draw: function(graphics:Graphics, atom:Atom, config:Object):void {
						var width:Number = config.width || 70;
						var height:Number = config.height || 50;
						
						graphics.clear();
						
						// Заливка
						graphics.beginFill(config.color || 0x6666CC);
						graphics.drawRoundRect(0, 0, width, height, 10, 10);
						graphics.endFill();
						
						// Обводка
						graphics.lineStyle(2, 0xFFFFFF);
						graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
						
						// Текст "AND"
						graphics.lineStyle(1, 0xFFFFFF);
						graphics.moveTo(width * 0.3, height * 0.4);
						graphics.lineTo(width * 0.7, height * 0.4);
					}
					},
					Editor: {
						// Можно добавить специфичные настройки для редактора
					},
					Device: {
						// Можно добавить псевдо-реалистичный вид для устройства
					}
				}
			});
			registerAtomType("OR", {
				displayName: "OR Gate",
				category: "Logic",
				description: "Logical OR gate - output is TRUE when at least one input is TRUE",
				pins: [
					{name: "input1", type: "input", dataType: "boolean", description: "First input signal"},
					{name: "input2", type: "input", dataType: "boolean", description: "Second input signal"},
					{name: "output", type: "output", dataType: "boolean", description: "Output signal (input1 OR input2)"}
				],
				behavior: {
					onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
						trace("=== OR GATE INPUT CHANGE ===");
						trace("Pin: " + pinName + ", Value: " + value);
						
						// Обновляем значение входящего пина в данных атома
						var newAtom:Atom = atom.setData(pinName, Boolean(value));
						
						// Получаем текущие значения обоих входов
						var input1:Boolean = newAtom.data.input1 === true;
						var input2:Boolean = newAtom.data.input2 === true;
						
						trace("Input1: " + input1 + ", Input2: " + input2);
						
						// Вычисляем результат OR
						var result:Boolean = input1 || input2;
						trace("OR Result: " + result);
						
						// Создаем атом с обновленным выходным значением
						var finalAtom:Atom = newAtom.setPinValue("output", result, false);
						
						// Эмитим импульс об изменении выходного значения
						MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
							atomId: finalAtom.id,
							pinName: "output",
							newValue: result,
							oldValue: atom.outputs[0] ? atom.outputs[0].value : false,
							source: "or_gate"
						}));
						
						trace("=== END OR GATE ===");
						return finalAtom;
					},
					
					// Инициализация - устанавливаем начальные значения
					initialize: function(atom:Atom):Atom {
						trace("OR Gate initialized");
						// Инициализируем данные входов как false, если они не установлены
						var newAtom:Atom = atom;
						if (!atom.hasValue("input1")) {
							newAtom = newAtom.setData("input1", false);
						}
						if (!atom.hasValue("input2")) {
							newAtom = newAtom.setData("input2", false);
						}
						// Устанавливаем начальное выходное значение
						newAtom = newAtom.setPinValue("output", false, false);
						return newAtom;
					}
				},
				viewConfig: {
					width: 70,
					height: 50,
					backgroundColor: 0xCC6666
				},
				visuals: {
					base: {
						width: 70,
						height: 50,
						color: 0xCC6666,
						textColor: 0xFFFFFF,
						cornerRadius: 5,
						draw: function(graphics:Graphics, atom:Atom, config:Object):void {
							var width:Number = config.width || 70;
							var height:Number = config.height || 50;
							
							graphics.clear();
							
							// Заливка
							graphics.beginFill(config.color || 0xCC6666);
							graphics.drawRoundRect(0, 0, width, height, 10, 10);
							graphics.endFill();
							
							// Обводка
							graphics.lineStyle(2, 0xFFFFFF);
							graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
							
							// Символ OR - изогнутая линия с входными точками
							graphics.lineStyle(2, 0xFFFFFF);
							
							// Левый вход 1
							graphics.moveTo(0, height * 0.3);
							graphics.lineTo(width * 0.3, height * 0.3);
							
							// Левый вход 2
							graphics.moveTo(0, height * 0.7);
							graphics.lineTo(width * 0.3, height * 0.7);
							
							// Изогнутая линия символа OR
							graphics.moveTo(width * 0.3, height * 0.3);
							graphics.curveTo(width * 0.5, height * 0.5, width * 0.3, height * 0.7);
							
							// Выходная линия
							graphics.moveTo(width * 0.7, height * 0.5);
							graphics.lineTo(width, height * 0.5);
						}
					},
					Editor: {
						// Специфичные настройки для редактора
					},
					Device: {
						// Псевдо-реалистичный вид для устройства
					}
				}
			});
			registerAtomType("NOT", {
				displayName: "NOT Gate",
				category: "Logic",
				description: "Logical NOT gate (inverter) - output is the opposite of input",
				pins: [
					{name: "input", type: "input", dataType: "boolean", description: "Input signal"},
					{name: "output", type: "output", dataType: "boolean", description: "Output signal (inverse of input)"}
				],
				behavior: {
					onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
						trace("=== NOT GATE INPUT CHANGE ===");
						trace("Pin: " + pinName + ", Value: " + value);
						
						// Получаем текущее значение входа
						var inputValue:Boolean = Boolean(value);
						trace("Input: " + inputValue);
						
						// Вычисляем результат NOT (инверсия)
						var result:Boolean = !inputValue;
						trace("NOT Result: " + result);
						
						// Создаем атом с обновленным выходным значением
						var newAtom:Atom = atom.setPinValue("output", result, false);
						
						// Эмитим импульс об изменении выходного значения
						MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
							atomId: newAtom.id,
							pinName: "output",
							newValue: result,
							oldValue: atom.outputs[0] ? atom.outputs[0].value : false,
							source: "not_gate"
						}));
						
						trace("=== END NOT GATE ===");
						return newAtom;
					},
					
					// Инициализация - устанавливаем начальные значения
					initialize: function(atom:Atom):Atom {
						trace("NOT Gate initialized");
						// Устанавливаем начальное выходное значение (инверсия от false = true)
						return atom.setPinValue("output", true, false);
					}
				},
				viewConfig: {
					width: 60,
					height: 40,
					backgroundColor: 0x66CC66
				},
				visuals: {
					base: {
						width: 60,
						height: 40,
						color: 0x66CC66,
						textColor: 0xFFFFFF,
						cornerRadius: 5,
						draw: function(graphics:Graphics, atom:Atom, config:Object):void {
							var width:Number = config.width || 60;
							var height:Number = config.height || 40;
							
							graphics.clear();
							
							// Заливка
							graphics.beginFill(config.color || 0x66CC66);
							graphics.drawRoundRect(0, 0, width, height, 10, 10);
							graphics.endFill();
							
							// Обводка
							graphics.lineStyle(2, 0xFFFFFF);
							graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
							
							// Символ NOT - треугольник с кружком на выходе
							graphics.lineStyle(2, 0xFFFFFF);
							
							// Входная линия
							graphics.moveTo(0, height * 0.5);
							graphics.lineTo(width * 0.3, height * 0.5);
							
							// Треугольник (основной символ инвертора)
							graphics.moveTo(width * 0.3, height * 0.2);
							graphics.lineTo(width * 0.7, height * 0.5);
							graphics.lineTo(width * 0.3, height * 0.8);
							graphics.lineTo(width * 0.3, height * 0.2);
							
							// Кружок инверсии на выходе
							graphics.drawCircle(width * 0.8, height * 0.5, 3);
							
							// Выходная линия после кружка
							graphics.moveTo(width * 0.83, height * 0.5);
							graphics.lineTo(width, height * 0.5);
						}
					},
					Editor: {
						// Специфичные настройки для редактора
					},
					Device: {
						// Псевдо-реалистичный вид для устройства
					}
				}
			});
			registerAtomType("NAND", {
				displayName: "NAND Gate",
				category: "Logic",
				description: "Logical NAND gate - output is FALSE only when both inputs are TRUE",
				pins: [
					{name: "input1", type: "input", dataType: "boolean", description: "First input signal"},
					{name: "input2", type: "input", dataType: "boolean", description: "Second input signal"},
					{name: "output", type: "output", dataType: "boolean", description: "Output signal (NOT (input1 AND input2))"}
				],
				behavior: {
					onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
						trace("=== NAND GATE INPUT CHANGE ===");
						trace("Pin: " + pinName + ", Value: " + value);
						
						// Обновляем значение входящего пина в данных атома
						var newAtom:Atom = atom.setData(pinName, Boolean(value));
						
						// Получаем текущие значения обоих входов
						var input1:Boolean = newAtom.data.input1 === true;
						var input2:Boolean = newAtom.data.input2 === true;
						
						trace("Input1: " + input1 + ", Input2: " + input2);
						
						// Вычисляем результат NAND (NOT AND)
						var result:Boolean = !(input1 && input2);
						trace("NAND Result: " + result);
						
						// Создаем атом с обновленным выходным значением
						var finalAtom:Atom = newAtom.setPinValue("output", result, false);
						
						// Эмитим импульс об изменении выходного значения
						MultiPulsator.emit(new Impulse("PIN_VALUE_CHANGED", {
							atomId: finalAtom.id,
							pinName: "output",
							newValue: result,
							oldValue: atom.outputs[0] ? atom.outputs[0].value : false,
							source: "nand_gate"
						}));
						
						trace("=== END NAND GATE ===");
						return finalAtom;
					},
					
					// Инициализация - устанавливаем начальные значения
					initialize: function(atom:Atom):Atom {
						trace("NAND Gate initialized");
						// Инициализируем данные входов как false, если они не установлены
						var newAtom:Atom = atom;
						if (!atom.hasValue("input1")) {
							newAtom = newAtom.setData("input1", false);
						}
						if (!atom.hasValue("input2")) {
							newAtom = newAtom.setData("input2", false);
						}
						// Устанавливаем начальное выходное значение (NAND от false,false = true)
						newAtom = newAtom.setPinValue("output", true, false);
						return newAtom;
					}
				},
				viewConfig: {
					width: 70,
					height: 50,
					backgroundColor: 0xCC66CC
				},
				visuals: {
					base: {
						width: 70,
						height: 50,
						color: 0xCC66CC,
						textColor: 0xFFFFFF,
						cornerRadius: 5,
						draw: function(graphics:Graphics, atom:Atom, config:Object):void {
							var width:Number = config.width || 70;
							var height:Number = config.height || 50;
							
							graphics.clear();
							
							// Заливка
							graphics.beginFill(config.color || 0xCC66CC);
							graphics.drawRoundRect(0, 0, width, height, 10, 10);
							graphics.endFill();
							
							// Обводка
							graphics.lineStyle(2, 0xFFFFFF);
							graphics.drawRoundRect(2, 2, width-4, height-4, 8, 8);
							
							// Символ NAND - комбинация AND и NOT
							graphics.lineStyle(2, 0xFFFFFF);
							
							// Левый вход 1
							graphics.moveTo(0, height * 0.3);
							graphics.lineTo(width * 0.2, height * 0.3);
							
							// Левый вход 2
							graphics.moveTo(0, height * 0.7);
							graphics.lineTo(width * 0.2, height * 0.7);
							
							// Основной прямоугольник AND
							graphics.moveTo(width * 0.2, height * 0.2);
							graphics.lineTo(width * 0.6, height * 0.2);
							graphics.lineTo(width * 0.6, height * 0.8);
							graphics.lineTo(width * 0.2, height * 0.8);
							graphics.lineTo(width * 0.2, height * 0.2);
							
							// Кружок инверсии на выходе
							graphics.drawCircle(width * 0.7, height * 0.5, 3);
							
							// Выходная линия после кружка
							graphics.moveTo(width * 0.73, height * 0.5);
							graphics.lineTo(width, height * 0.5);
						}
					},
					Editor: {
						// Специфичные настройки для редактора
					},
					Device: {
						// Псевдо-реалистичный вид для устройства
					}
				}
			});
            registerAtomType("Counter", {
                displayName: "Counter",
                category: "Logic", 
                description: "Counts impulses and outputs the current count",
                pins: [
                    {name: "input", type: "input", dataType: "impulse", description: "Increment counter"},
                    {name: "reset", type: "input", dataType: "impulse", description: "Reset counter to zero"},
                    {name: "count", type: "output", dataType: "number", description: "Current count value"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        // Counter logic here
                        return atom;
                    }
                },
                viewConfig: {
                    width: 80,
                    height: 40,
                    backgroundColor: 0x9966CC
                },
                visuals: {
                    base: {
                        width: 80,
                        height: 40,
                        color: 0x9966CC,
                        textColor: 0x000000
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("Timer", {
                displayName: "Timer",
                category: "Logic",
                description: "Generates impulses at regular intervals", 
                pins: [
                    {name: "start", type: "input", dataType: "impulse", description: "Start timer"},
                    {name: "stop", type: "input", dataType: "impulse", description: "Stop timer"},
                    {name: "interval", type: "input", dataType: "number", description: "Timer interval in ms"},
                    {name: "output", type: "output", dataType: "impulse", description: "Timer impulse output"}
                ],
                viewConfig: {
                    width: 70,
                    height: 35,
                    backgroundColor: 0xCC9966
                },
                visuals: {
                    base: {
                        width: 70,
                        height: 35,
                        color: 0xCC9966,
                        textColor: 0x000000
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            // Output Atoms
            registerAtomType("NumberDisplay", {
                displayName: "Number Display",
                category: "Output",
                description: "Displays numeric values on screen",
                pins: [
                    {name: "value", type: "input", dataType: "number", description: "Numeric value to display"},
                    {name: "trigger", type: "input", dataType: "impulse", description: "Update display"}
                ],
                behavior: {
                    onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
                        trace("NumberDisplay: Value changed to " + value);
                        return atom;
                    }
                },
                viewConfig: {
                    width: 80,
                    height: 40,
                    backgroundColor: 0x222266
                },
                visuals: {
                    base: {
                        width: 80,
                        height: 40,
                        color: 0x222266,
                        textColor: 0xFFFFFF
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("TextDisplay", {
                displayName: "Text Display",
                category: "Output",
                description: "Displays text messages on screen",
                pins: [
                    {name: "text", type: "input", dataType: "string", description: "Text to display"},
                    {name: "trigger", type: "input", dataType: "impulse", description: "Update display"}
                ],
                viewConfig: {
                    width: 120,
                    height: 50,
                    backgroundColor: 0x226622
                },
                visuals: {
                    base: {
                        width: 120,
                        height: 50,
                        color: 0x226622,
                        textColor: 0xFFFFFF
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

			registerAtomType("LED", {
				displayName: "LED Indicator",
				category: "Output",
				description: "Visual indicator that lights up when active",
				pins: [
					{name: "input", type: "input", dataType: "boolean", description: "LED state (on/off)"}
				],
				behavior: {
					onInputChange: function(atom:Atom, pinName:String, value:*):Atom {
						trace("=== LED INPUT CHANGE ===");
						trace("LED " + atom.id + " received value: " + value);

						var newAtom:Atom = atom.setData("isOn", Boolean(value));
						trace("LED data updated - isOn: " + newAtom.data.isOn);

						MultiPulsator.emit(new Impulse("ATOM_VISUAL_UPDATE", {
							atomId: newAtom.id,
							data: newAtom.data
						}));

						return newAtom;
					}
				},
				visuals: {
					base: {
						width: 30,
						height: 30,
						color: 0x333333,
						textColor: 0xFFFFFF,
						draw: function(graphics:Graphics, atom:Atom, config:Object):void {
							AtomDefinitions.drawLED(graphics, atom, config);
						}
					},
					Editor: {
						width: 30,
						height: 30,
						color: 0x333333,
						textColor: 0xFFFFFF,
						draw: function(graphics:Graphics, atom:Atom, config:Object):void {
							AtomDefinitions.drawLED(graphics, atom, config);
						}
					},
					Device: {
						width: 30,
						height: 30,
						color: 0x333333,
						textColor: 0xFFFFFF,
						draw: function(graphics:Graphics, atom:Atom, config:Object):void {
							AtomDefinitions.drawLED(graphics, atom, config);
						}
					}
				}
			});

            // System Atoms
            registerAtomType("Clock", {
                displayName: "System Clock", 
                category: "System",
                description: "Provides system time information",
                pins: [
                    {name: "time", type: "output", dataType: "number", description: "Current time in ms"},
                    {name: "tick", type: "output", dataType: "impulse", description: "Clock tick impulse"}
                ],
                viewConfig: {
                    width: 90,
                    height: 45,
                    backgroundColor: 0x666633
                },
                visuals: {
                    base: {
                        width: 90,
                        height: 45,
                        color: 0x666633,
                        textColor: 0xFFFFFF
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            registerAtomType("Random", {
                displayName: "Random Generator",
                category: "System",
                description: "Generates random values",
                pins: [
                    {name: "generate", type: "input", dataType: "impulse", description: "Generate new random value"},
                    {name: "min", type: "input", dataType: "number", description: "Minimum value"},
                    {name: "max", type: "input", dataType: "number", description: "Maximum value"},
                    {name: "value", type: "output", dataType: "number", description: "Random value output"}
                ],
                viewConfig: {
                    width: 85,
                    height: 42,
                    backgroundColor: 0x663366
                },
                visuals: {
                    base: {
                        width: 85,
                        height: 42,
                        color: 0x663366,
                        textColor: 0xFFFFFF
                    },
                    Editor: {
                        // специфичные настройки для Editor
                    }
                }
            });

            _initialized = true;
            trace("AtomDefinitions: Initialization complete - " + getSupportedTypes().length + " atom types registered");
        }

        /**
         * Register a single atom type
         */
        public static function registerAtomType(type:String, definition:Object):void {
            if (_definitions[type]) {
                trace("WARNING: Overwriting existing atom definition: " + type);
            }
            
            _definitions[type] = definition;
            trace("AtomDefinitions: Registered - " + type);
        }

        /**
         * Get atom definition by type
         */
        public static function getAtomDefinition(type:String):Object {
            if (!_initialized) {
                trace("ERROR: AtomDefinitions not initialized!");
                return null;
            }
            
            var definition:Object = _definitions[type];
            if (!definition) {
                trace("WARNING: Atom definition not found: " + type);
            }
            
            return definition;
        }

        /**
         * Get all supported atom types
         */
        public static function getSupportedTypes():Array {
            if (!_initialized) {
                trace("ERROR: AtomDefinitions not initialized!");
                return [];
            }
            
            var types:Array = [];
            for (var key:String in _definitions) {
                types.push(key);
            }
            types.sort(); // Alphabetical order
            return types;
        }

        /**
         * Get atom types by category
         */
        public static function getTypesByCategory(category:String):Array {
            var result:Array = [];
            var allTypes:Array = getSupportedTypes();
            
            for each (var type:String in allTypes) {
                var definition:Object = getAtomDefinition(type);
                if (definition && definition.category == category) {
                    result.push(type);
                }
            }
            
            return result;
        }

        /**
         * Get all available categories
         */
        public static function getCategories():Array {
            var categories:Object = {};
            var allTypes:Array = getSupportedTypes();
            
            for each (var type:String in allTypes) {
                var definition:Object = getAtomDefinition(type);
                if (definition && definition.category) {
                    categories[definition.category] = true;
                }
            }
            
            var result:Array = [];
            for (var category:String in categories) {
                result.push(category);
            }
            result.sort();
            return result;
        }

        /**
         * Check if atom type is registered
         */
        public static function isAtomTypeRegistered(type:String):Boolean {
            return _definitions[type] != null;
        }

        /**
         * Validate all atom definitions
         */
        public static function validateDefinitions():void {
            trace("=== ATOM DEFINITIONS VALIDATION ===");
            
            var supportedTypes:Array = getSupportedTypes();
            trace("Total registered atoms: " + supportedTypes.length);
            
            var errors:int = 0;
            var warnings:int = 0;
            
            for each (var type:String in supportedTypes) {
                var definition:Object = getAtomDefinition(type);
                
                if (!definition) {
                    trace("ERROR: " + type + " - definition missing");
                    errors++;
                    continue;
                }
                
                // Check required fields
                if (!definition.displayName) {
                    trace("WARNING: " + type + " - missing displayName");
                    warnings++;
                }
                
                if (!definition.category) {
                    trace("WARNING: " + type + " - missing category");
                    warnings++;
                }
                
                if (!definition.pins || definition.pins.length == 0) {
                    trace("WARNING: " + type + " - no pins defined");
                    warnings++;
                } else {
                    // Validate pins
                    for each (var pin:Object in definition.pins) {
                        if (!pin.name) {
                            trace("WARNING: " + type + " - pin missing name");
                            warnings++;
                        }
                        if (!pin.type || (pin.type != "input" && pin.type != "output")) {
                            trace("WARNING: " + type + " - pin '" + pin.name + "' has invalid type: " + pin.type);
                            warnings++;
                        }
                    }
                }
                
                trace("VALID: " + type + " (" + definition.displayName + ") - " + 
                      (definition.pins ? definition.pins.length : 0) + " pins");
            }
            
            trace("Validation complete - Errors: " + errors + ", Warnings: " + warnings);
            trace("=== END VALIDATION ===");
        }

        /**
         * Clear all definitions (for testing)
         */
        public static function clear():void {
            _definitions = new Object();
            _initialized = false;
            trace("AtomDefinitions: Cleared all definitions");
        }
    }
}
