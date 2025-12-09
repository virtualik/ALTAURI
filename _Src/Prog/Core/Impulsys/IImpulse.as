package Src.Prog.Core.Impulsys {
    /**
     * Base interface for impulses - data contract for communication system
     * Defines standard interface for all messages transmitted via Impulsys.
     *
     * Core contract for all application messages ensuring consistent
     * data structure across the event-driven architecture
     */
    public interface IImpulse {
        /**
         * Impulse type - message identifier
         * Used by Impulsys. for message routing to subscribers
         * @return String - impulse type identifier
         */
        function get type():String;

        /**
         * Impulse data - message payload
         * Contains arbitrary data associated with the impulse
         * @return Object - impulse data payload
         */
        function get data():Object;
    }
}
