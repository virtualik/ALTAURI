package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    // import Src.Prog.Core.Managers.AtomManager; // Предполагаем, что AtomManager будет использоваться
    // import Src.Prog.Com.Atoms.Linker.Track; // Предполагаем, что Track будет реализован и использован

    /**
     * Base class for atom views in an editing context (e.g., Editor window).
     * Extends BaseAtomView to provide specific behavior for editing scenarios,
     * such as dragging, pin interaction, and potential property modification.
     * Integrates with MultiPulsator for system communication and expects integration
     * with AtomManager and AssetDomain for updates and visuals.
     * This view focuses on editability (positioning, connections).
     */
    public class EditorAtomView extends BaseAtomView { // Наследуемся от BaseAtomView

        // Режимы взаимодействия, если потребуется
        // protected static const MODE_DEFAULT:String = "default";
        // protected static const MODE_CONNECTING:String = "connecting";

        /**
         * Constructs the EditorAtomView.
         * Sets up base mouse interactions (inherited from BaseAtomView).
         */
        public function EditorAtomView() {
            super(); // Вызываем конструктор родителя
            // Можно добавить специфичные для редактора настройки здесь,
            // например, изменение курсора или начального состояния.
        }

        // --- Переопределение методов BaseAtomView для редактора ---

        /**
         * Handles the base mouse down event in the editor context.
         * Brings the view to the front and starts dragging if the Ctrl key is pressed.
         * Can be overridden for more specific editor behaviors (e.g., selecting multiple atoms).
         */
        override protected function onBaseMouseDown(event:flash.events.MouseEvent):void {
            // Вызов родительской реализации для базового поведения (всплытие, перетаскивание с Ctrl)
            super.onBaseMouseDown(event);

            // Можно добавить специфичное поведение для редактора здесь,
            // например, обработка кликов без Ctrl (для выделения, открытия настроек и т.д.)
            // if (!event.ctrlKey) {
            //     MultiPulsator.emit(new Impulse("ATOM_SELECTED", { atom: _parentAtom, view: this }));
            // }
        }

        /**
         * Handles the end of a drag operation in the editor.
         * Updates the atom's position via MultiPulsator, expecting AtomManager to handle the update.
         * This is where the immutable pattern is crucial: we create a *new* atom with the new position.
         */
        override public function onDragEnd(mousePos:Point):void {
            this.alpha = 1.0; // Сброс визуальной обратной связи
            if (_parentAtom) {
                var newPosition:Point = new Point(mousePos.x, mousePos.y);
                // Создаём новый атом с обновлённой позицией, используя иммутабельный паттерн
                var newAtom:BaseAtom = _parentAtom.setPosition(newPosition);

                // Уведомляем систему об изменении через MultiPulsator
                // Предполагается, что AtomManager или другой слушатель обработает этот импульс,
                // обновит свою внутреннюю базу данных и, возможно, вызовет updateAtomReference на этом view.
                MultiPulsator.emit(new Impulse("ATOM_MOVED", {
                    oldAtom: _parentAtom,
                    newAtom: newAtom,
                    oldPosition: _parentAtom.position,
                    newPosition: newPosition
                }));

                // *Не* вызываем AtomManager.updateAtom(newAtom) напрямую здесь,
                // чтобы сохранить слабую связанность через MultiPulsator.
                // AtomManager (или эквивалент) должен слушать "ATOM_MOVED".
            }
        }

        /**
         * Updates the tracks connected to this atom during dragging in the editor.
         * Placeholder: Requires Linker domain (e.g., ConnectionManager, Track) to be implemented.
         * Example integration with MultiPulsator or direct call to Linker service.
         */
        override protected function updateTracksDuringDrag():void {
            // Пример: отправка импульса для домена Linker
            if (_parentAtom) {
                 MultiPulsator.emit(new Impulse("ATOM_DRAGGING", {
                    atom: _parentAtom,
                    position: new Point(this.x, this.y), // Текущая визуальная позиция во время перетаскивания
                    view: this // Возможно, передать и сам view, если нужно
                }));
            }
            // В будущем, Linker домен может слушать "ATOM_DRAGGING" и обновлять позиции Track'ов.
        }

        // --- Методы для переопределения дочерними классами (если нужно) ---

        /**
         * Handles the specific mouse down event for child classes in the editor.
         * Override in child classes for specific click behavior (e.g., opening properties).
         */
        override protected function onSpecificMouseDown(event:flash.events.MouseEvent):void {
            // Override in child classes for specific click behavior in editor
            // Например, MultiPulsator.emit(new Impulse("ATOM_EDIT_REQUEST", { atom: _parentAtom }));
        }

        /**
         * Updates the visual representation of the atom in the editor.
         * Override in child classes to implement specific visual updates based on atom state.
         */
        override public function updateVisuals():void {
             // Override in child classes to update visuals based on _parentAtom state in editor
             // e.g., update display based on pin values, name, type, selection state, etc.
             super.updateVisuals(); // Вызываем базовое обновление, если нужно
        }

        /**
         * Handles the start of a drag operation.
         * @param mousePos The mouse position when dragging started.
         */
        override public function onDragStart(mousePos:Point):void {
            this.alpha = 0.7; // Визуальная обратная связь для перетаскивания
            super.onDragStart(mousePos); // Вызываем базовую логику, если нужно
        }

        /**
         * Handles the movement during a drag operation.
         * @param mousePos The current mouse position during dragging.
         */
        override public function onDrag(mousePos:Point):void {
            super.onDrag(mousePos); // Обновляем позицию (this.x, this.y) и вызываем updateTracksDuringDrag
        }

        /**
         * Brings this atom view to the front of its parent's display list.
         */
        override public function bringToFront():void {
            super.bringToFront(); // Вызываем базовую логику
            // Можно добавить специфичную для редактора логику, например, сброс выделения с других
        }

        /**
         * Ensures pins are visible and properly positioned by removing and re-adding them.
         */
        override public function refreshPins():void {
            super.refreshPins(); // Вызываем базовую логику
            // Можно добавить специфичную для редактора логику, например, обновление стиля пинов
        }

        /**
         * Updates the reference to the atom this view represents and refreshes the view.
         * @param newAtom The new atom instance to represent.
         */
        override public function updateAtomReference(newAtom:BaseAtom):void {
            super.updateAtomReference(newAtom); // Вызываем базовую логику
            // Можно добавить специфичную для редактора логику, например, обновление стиля в зависимости от состояния
        }

        /**
         * Cleans up resources, including removing event listeners.
         * Can be overridden in child classes for specific cleanup.
         */
        override public function dispose():void {
            // Можно добавить специфичную для редактора очистку
            super.dispose(); // Вызываем базовую очистку
        }

    }
}