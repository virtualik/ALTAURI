package ui.virtual;

import lime.ui.Window;
import lime.ui.WindowAttributes;
import openfl.display.Sprite;
import openfl.Lib;

class WindowManager {
    
    /**
     * Создает окно Player.
     * На C++ это будет обычное окно Lime.
     * На HL это будет обычное окно Lime.
     */
    public static function createPlayerWindow(width:Int, height:Int, title:String):Window {
        var attributes:WindowAttributes = {
            width: width,
            height: height,
            title: title,
            // Стандартные настройки: непрозрачное, с рамкой
            transparent: false, 
            resizable: true,
            borderless: false
        };

        // Создаем окно через Lime Application
        var window = Lib.application.createWindow(attributes);
        
        // Lime автоматически создает Stage для нового окна
        // Можно добавить спрайт сразу
        var sprite = new Sprite();
        sprite.graphics.beginFill(0x303030);
        sprite.graphics.drawRect(0, 0, width, height);
        sprite.graphics.endFill();
        
        // Важно: window.stage может быть null в первый момент, 
        // но обычно в Lime он готов сразу.
        if (window.stage != null) {
            window.stage.addChild(sprite);
        }
        
        return window;
    }

    /**
     * Создает Overlay окно.
     * На C++ (windows) использует наш нативный хак.
     * На HL выводит предупреждение, так как нативный код не совместим.
     */
    public static function createOverlayWindow(width:Int, height:Int, title:String):Void {
        #if windows
        // Этот код скомпилируется только для C++ цели
        NativeWindowExtension.createWindow(width, height, title);
        #else
        trace("Overlay Window (Native) поддерживается только в C++ build.");
        #end
    }

    /**
     * Обновление содержимого Overlay.
     */
    public static function updateOverlay(sprite:Sprite):Void {
        #if windows
        NativeWindowExtension.updateFromSprite(sprite);
        #end
    }
    
    /**
     * Опрос событий Overlay.
     */
    public static function pollOverlayEvents():Void {
        #if windows
        NativeWindowExtension.pollEvents();
        #end
    }
}