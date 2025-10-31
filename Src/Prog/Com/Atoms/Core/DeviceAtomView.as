package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    // import Src.Prog.Core.Managers.AtomManager; // Предполагаем, что AtomManager может использоваться для симуляции
    // import Src.Prog.Com.AssetsDomain.AssetManager; // Предполагаем, что AssetManager будет использоваться для ассетов в Device

    /**
     * Base class for atom views in a device/simulation context (e.g., Device window).
     * Extends BaseAtomView to provide specific behavior for simulation scenarios,
     * such as reacting to input/output changes and displaying current state.
     * Integrates with MultiPulsator for system communication and expects integration
     * with AtomManager (or SimulationManager) and AssetDomain for updates and visuals.
     * This view focuses on simulation behavior and output display (e.g., button press, display updates).
     */
    public class DeviceAtomView extends BaseAtomView { // Наследуемся от BaseAtomView

        /**
         * Constructs the DeviceAtomView.
         * Sets up base interactions and potentially subscribes to simulation-specific impulses.
         */
        public function DeviceAtomView() {
            super(); // Вызываем конструктор родителя
            // Настройка специфичного для Device поведения
            setupDeviceInteractions();
            // subscribeToSimulationImpulses(); // Пример: слушать импульсы симуляции
        }

        /**
         * Sets up mouse interactions for the device view.
         * Adds listeners for mouse down and up events if the view is interactive.
         * Override if specific interaction logic is needed.
         */
        protected function setupDeviceInteractions():void {
            // Пример: разрешить взаимодействие для "кнопок"
            // if (_parentAtom.type === "Button" || _parentAtom.type === "PushButton") {
                this.buttonMode = true;
                this.addEventListener(MouseEvent.MOUSE_DOWN, onDeviceInteraction);
                this.addEventListener(MouseEvent.MOUSE_UP, onDeviceRelease);
            // }
        }

        /**
         * Handles the mouse down interaction event in the device context.
         * Emits an impulse to signal the interaction (e.g., button press).
         */
        protected function onDeviceInteraction(event:MouseEvent):void {
            // Пример: эмит импульса для симуляции
            if (_parentAtom) {
                MultiPulsator.emit(new Impulse("DEVICE_ATOM_INTERACTION", {
                    atom: _parentAtom,
                    interactionType: "button_press",
                    source: "device_window",
                    view: this
                }));
            }
            // Не вызываем базовый onBaseMouseDown, так как поведение перетаскивания не нужно в Device
            event.stopPropagation(); // Останавливаем всплытие, если нужно
        }

        /**
         * Handles the mouse up interaction event in the device context.
         * Emits an impulse to signal the release (e.g., button release).
         */
        protected function onDeviceRelease(event:MouseEvent):void {
            // Пример: эмит импульса для симуляции
            if (_parentAtom) {
                MultiPulsator.emit(new Impulse("DEVICE_ATOM_INTERACTION", {
                    atom: _parentAtom,
                    interactionType: "button_release",
                    source: "device_window",
                    view: this
                }));
            }
            event.stopPropagation(); // Останавливаем всплытие, если нужно
        }

        // --- Переопределение методов BaseAtomView для Device ---

        /**
         * Handles the end of a drag operation in the device context.
         * Override to prevent dragging in the Device window.
         */
        override public function onDragEnd(mousePos:Point):void {
            // Не меняем позицию атома в Device
            this.alpha = 1.0; // Сбрасываем визуальный эффект
            // Можно эмитить импульс, если попытка перетаскивания в Device значима
            // MultiPulsator.emit(new Impulse("DEVICE_ATOM_DRAG_ATTEMPT", { atom: _parentAtom }));
        }

        /**
         * Handles the specific mouse down event for child classes in the device.
         * Override in child classes for specific click behavior (e.g., triggering simulation).
         * This is called by onBaseMouseDown, which we might not trigger in Device,
         * so onDeviceInteraction is the primary handler.
         */
        override protected function onSpecificMouseDown(event:flash.events.MouseEvent):void {
            // Для Device, возможно, не используется, так как onDeviceInteraction переопределяет базовое поведение.
            // Или может использоваться для других типов взаимодействий.
        }

        /**
         * Updates the visual representation of the atom in the device.
         * Override in child classes to implement specific visual updates based on atom state (e.g., display value).
         */
        override public function updateVisuals():void {
             // Override in child classes to update visuals based on _parentAtom state in device
             // e.g., update display text, button color based on output pin value, etc.
             super.updateVisuals(); // Вызываем базовое обновление, если нужно
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Removes device-specific subscriptions.
         */
        override public function dispose():void {
            // Отписка от специфичных для Device импульсов
            // MultiPulsator.removeImpulse("SOME_DEVICE_IMPULSE", handler);
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onDeviceInteraction);
            this.removeEventListener(MouseEvent.MOUSE_UP, onDeviceRelease);
            super.dispose(); // Вызываем базовую очистку
        }
    }
}