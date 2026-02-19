package Src.Impulsator {
    public class Impulse implements IImpulse {
        private var _type:String;
        private var _data:Object;

        public function Impulse(type:String, data:Object = null) {
            _type = type;
            _data = data;
        }

        public function get type():String {
            return _type;
        }

        public function get data():Object {
            return _data;
        }
    }
}
