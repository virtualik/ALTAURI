package Application.MultiPulsator {
    /**
     * Base interface for impulses - data contract for communication system
     * Defines standard interface for all messages transmitted via MultiPulsator
     */
    public interface IImpulse {
        /**
         * Impulse type - message identifier
         * Used by MultiPulsator for message routing to subscribers
         */
        function get type():String;

        /**
         * Impulse data - message payload
         * Contains arbitrary data associated with the impulse
         */
        function get data():Object;
    }
}
