package Src.Prog.Com.Atoms.Contact.Core {
    import flash.events.Event;

    /**
     * Событие для системы Contact - уведомляет об изменениях значений и подключениях.
     * Упрощенный аналог PinEvent для новой системы.
     * 
     * @class ContactEvent
     * @extends Event
     */
    public class ContactEvent extends Event {
        
        // Типы событий
        public static const VALUE_CHANGED:String = "contactValueChanged";
        public static const CONNECTED:String = "contactConnected";
        public static const DISCONNECTED:String = "contactDisconnected";

        // Свойства события
        public var sourceContact:Contact;
        public var newValue:*;
        public var oldValue:*;

        /**
         * Создает новое событие Contact.
         * 
         * @param type - Тип события (VALUE_CHANGED, CONNECTED, DISCONNECTED)
         * @param sourceContact - Контакт-источник события
         * @param newValue - Новое значение (для VALUE_CHANGED)
         * @param oldValue - Старое значение (для VALUE_CHANGED)
         * @param bubbles - Всплывание события
         * @param cancelable - Возможность отмены события
         */
        public function ContactEvent(
            type:String, 
            sourceContact:Contact, 
            newValue:* = null, 
            oldValue:* = null,
            bubbles:Boolean = false, 
            cancelable:Boolean = false
        ) {
            super(type, bubbles, cancelable);
            
            this.sourceContact = sourceContact;
            this.newValue = newValue;
            this.oldValue = oldValue;
        }

        /**
         * Создает копию события.
         * 
         * @return Event - Копия события
         */
        override public function clone():Event {
            return new ContactEvent(type, sourceContact, newValue, oldValue, bubbles, cancelable);
        }

        /**
         * Строковое представление события для отладки.
         * 
         * @return String - Строковое представление
         */
        override public function toString():String {
            return formatToString(
                "ContactEvent", 
                "type", 
                "sourceContact", 
                "newValue", 
                "oldValue",
                "bubbles", 
                "cancelable", 
                "eventPhase"
            );
        }
    }
}