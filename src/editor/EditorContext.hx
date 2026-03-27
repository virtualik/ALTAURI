package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * EDITOR CONTEXT v1.0
 * Управляет стеком открытых редакторов (NodeEditor).
 * Отвечает за создание контейнеров, блокировку фона и переключение контекста.
 */
class EditorContext {

    private var _layer:Sprite; // Слой, куда добавляются редакторы
    private var _theme:EditorTheme;
    
    // Стек записей: {сборка, редактор, спрайт-блокировщик, контейнер}
    private var _stack:Array<EditorEntry>;

    public var currentAssembly(default, null):Assembly;
    public var currentEditor(default, null):NodeEditor;

    public function new(layer:Sprite) {
        _layer = layer;
        _stack = [];
        _theme = EditorTheme.getInstance();
    }

    /**
     * Открыть новую сборку (зайти внутрь).
     */
    public function push(assembly:Assembly, ?isRoot:Bool = false):Void {
        // Если это не корень, блокируем предыдущий редактор
        if (!isRoot && _stack.length > 0) {
            var top = _stack[_stack.length - 1];
            var blocker = new Sprite();
            blocker.graphics.beginFill(0x808080, 0.6);
            blocker.graphics.drawRect(0, 0, _layer.stage.stageWidth, _layer.stage.stageHeight);
            blocker.graphics.endFill();
            // Клики по блокировщику не проходят
            blocker.addEventListener(openfl.events.MouseEvent.CLICK, function(e) e.stopPropagation());
            
            _layer.addChild(blocker);
            top.editor.mouseEnabled = false;
            top.editor.mouseChildren = false;
            top.blocker = blocker;
        }

        // Создаем контейнер для нового редактора
        var container = new Sprite();
        drawContainerFrame(container);
        _layer.addChild(container);

        // Создаем редактор
        var editor = new NodeEditor(assembly);
        editor.setSize(container.width, container.height);
        container.addChild(editor);

        var entry:EditorEntry = {
            assembly: assembly,
            editor: editor,
            blocker: null,
            container: container
        };

        _stack.push(entry);

        currentEditor = editor;
        currentAssembly = assembly;
    }

    /**
     * Вернуться назад (закрыть текущую сборку).
     * @param updateInstances Нужно ли обновлять экземпляры в родителе (после сохранения)
     */
    public function pop(updateInstances:Bool = false):Void {
        if (_stack.length <= 1) return; // Нельзя закрыть корень

        var current = _stack.pop();
        var editedId = current.assembly.blueprint.id;

        // Удаляем текущий редактор
        current.editor.dispose();
        if (_layer.contains(current.container)) _layer.removeChild(current.container);

        // Восстанавливаем предыдущий
        var prev = _stack[_stack.length - 1];
        if (prev.blocker != null) {
            if (_layer.contains(prev.blocker)) _layer.removeChild(prev.blocker);
            prev.blocker = null;
        }
        prev.editor.mouseEnabled = true;
        prev.editor.mouseChildren = true;

        currentEditor = prev.editor;
        currentAssembly = prev.assembly;

        // Обновляем превью сборки в родителе, если она изменилась
        if (updateInstances) {
            updateInstancesOf(editedId);
        }
        currentEditor.refreshAssemblyViews();
    }

    /**
     * Обновить визуал сборок с указанным ID во всех открытых редакторах.
     */
    private function updateInstancesOf(typeId:String):Void {
        var newBp = library.AtomRegistry.get(typeId);
        if (newBp == null) return;

        // Проходим по всем атомам в ТЕКУЩЕМ редакторе
        // (так как стек иерархичен, обновление каскадное не нужно, достаточно обновить вид в родителе)
        for (id in currentAssembly.internalAtoms.keys()) {
            var atom = currentAssembly.internalAtoms.get(id);
            if (Std.isOfType(atom, Assembly)) {
                var asm = cast(atom, Assembly);
                if (asm.blueprint.id == typeId) asm.updateFromBlueprint(newBp);
            }
        }
    }

    /**
     * Сбросить весь стек (при перезагрузке проекта).
     */
    public function clear():Void {
        while (_stack.length > 0) {
            var item = _stack.pop();
            item.editor.dispose();
            if (item.container.parent != null) _layer.removeChild(item.container);
            if (item.blocker != null && item.blocker.parent != null) _layer.removeChild(item.blocker);
        }
        currentEditor = null;
        currentAssembly = null;
    }

    public function getStackLength():Int return _stack.length;

    private function drawContainerFrame(container:Sprite):Void {
		var margin = 12;
        var w = _layer.stage.stageWidth - (margin * 2);
        var h = _layer.stage.stageHeight - (margin * 2);

        container.graphics.clear();
        container.graphics.beginFill(_theme.FRAME_FILL_COLOR, _theme.FRAME_FILL_ALPHA);
        container.graphics.lineStyle(1, _theme.FRAME_BORDER_COLOR);
        container.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        container.graphics.endFill();

        container.x = margin;
        container.y = margin;
    }
}

typedef EditorEntry = {
    var assembly:Assembly;
    var editor:NodeEditor;
    var blocker:Sprite;
    var container:Sprite;
}