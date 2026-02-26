package Src.Managers {
    import flash.utils.Dictionary;

    public class DataManager {
        private static var _data:Dictionary = new Dictionary();

        public static function getData(key:String):* {
            return _data[key];
        }

        public static function registerData(key:String, data:*):void {
            _data[key] = data;
        }

        public static function unregisterData(key:String):void {
            delete _data[key];
        }

        public static function clearData():void {
            for (var key:String in _data) {
                delete _data[key];
            }
        }

        public static function hasData(key:String):Boolean {
            return _data[key] !== undefined;
        }

        public static function getAllKeys():Array {
            var keys:Array = [];
            for (var key:String in _data) {
                keys.push(key);
            }
            return keys;
        }
    }
}
