package core.view;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import core.base.Contact;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import library.electro.OscilloscopeAtom;

/**
 * OSCILLOSCOPE WIDGET v2.4 (History Mode Default + No Width Clamp)
 * 
 * v2.4 Changes:
 * - History mode ENABLED BY DEFAULT (10-layer ring buffer)
 * - NO width clamping — wave can extend beyond widgetWidth (for timeScale testing)
 * - Vector graphics + ENTER_FRAME sync
 * - Atomic buffer snapshot
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OscilloscopeWidget (History Mode)                                     │
 * │                                                                         │
 * │   _historyContainer (Sprite)                                            │
 * │   ├── _historyLayers[0] (y = 0)              ← Wave N-9 or N          │
 * │   ├── _historyLayers[1] (y = widgetHeight)   ← Wave N-8 or N+1        │
 * │   ├── _historyLayers[2] (y = 2*widgetHeight) ← Wave N-7 or N+2        │
 * │   ├── ...                                                               │
 * │   └── _historyLayers[9] (y = 9*widgetHeight) ← Wave N or N+9          │
 * │                                                                         │
 * │   Ring Buffer Logic:                                                    │
 * │   ─────────────────────────────────────────────────────────────────┐   │
 * │   │  _currentLayer starts at 0                                      │   │
 * │   │                                                                 │   │
 * │   │  Frame 1:  draw on layer[0], _currentLayer = 1                  │   │
 * │   │  Frame 2:  draw on layer[1], _currentLayer = 2                  │   │
 * │   │  ...                                                             │   │
 * │   │  Frame 10: draw on layer[9], _currentLayer = 0 (wrap!)          │   │
 * │   │  Frame 11: CLEAR layer[0], draw new wave, _currentLayer = 1     │   │
 * │   │  Frame 12: CLEAR layer[1], draw new wave, _currentLayer = 2     │   │
 * │   │  ... (ring repeats)                                              │   │
 * │   ─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Width Behavior:                                                       │
 * │   ───────────────                                                       │
 * │   - NO clamp at widgetWidth                                            │
 * │   - Wave extends to the right as timeScale increases                   │
 * │   - At timeScale=10, wave is 10x wider than widget                     │
 * │   - Useful for debugging buffer artifacts                              │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class OscilloscopeWidget extends DeviceView
{
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 150;
    public var colorLine:Int = 0xFFFFFF;
    public var colorBg:Int = 0x0a0a12;
    public var colorGrid:Int = 0x1a2a1a;
    
    // =========================================================================
    // HISTORY MODE (v2.2) — ENABLED BY DEFAULT
    // =========================================================================
    private static inline var HISTORY_LAYERS:Int = 5;
    
    /** History mode is ON by default */
    private var _historyMode:Bool = false;
    
    /** Container holding all history layers */
    private var _historyContainer:Sprite;
    
    /** Array of 10 sprite layers, each at y = i * widgetHeight */
    private var _historyLayers:Array<Sprite>;
    
    /** Current write position in ring buffer (0..9) */
    private var _currentLayer:Int = 0;
    
    /** Frame counter for history mode (for debugging) */
    private var _historyFrameCount:Int = 0;
    
    // =========================================================================
    // NORMAL MODE COMPONENTS (kept for fallback)
    // =========================================================================
    private var _canvas:Sprite;
    private var _grid:Sprite;
    private var _mask:Shape;
    private var _oscAtom:OscilloscopeAtom;
    
    // =========================================================================
    // FRAME SYNCHRONIZATION
    // =========================================================================
    private var _hasNewFrame:Bool = false;
    private var _isRendering:Bool = false;
    private var _renderBuffer:Array<Float>;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom, contactName:String = "in")
    {
        super(atom);
        
        if (Std.isOfType(atom, OscilloscopeAtom)) {
            _oscAtom = cast(atom, OscilloscopeAtom);
        }
        else if (Std.isOfType(atom, Assembly)) {
            var asm = cast(atom, Assembly);
            for (internalAtom in asm.internalAtoms) {
                if (Std.isOfType(internalAtom, OscilloscopeAtom)) {
                    _oscAtom = cast(internalAtom, OscilloscopeAtom);
                    break;
                }
            }
        }
        
        buildUI();
        Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
        Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
        
        addEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
    }
    
    // =========================================================================
    // WIDGET SIZE
    // =========================================================================
    override public function getWidgetSize():{width:Float, height:Float} {
        if (_historyMode) {
            return {width: widgetWidth, height: widgetHeight * HISTORY_LAYERS};
        }
        return {width: widgetWidth, height: widgetHeight};
    }
    
    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void
    {
        updateDimensions();
        drawBackground();
        
        _grid = new Sprite(); 
        addChild(_grid);
        
        _mask = new Shape(); 
        addChild(_mask);
        _grid.mask = _mask;
        
        drawGrid();
        drawMask();
        
        if (_historyMode) {
            initHistoryLayers();
        } else {
            _canvas = new Sprite(); 
            addChild(_canvas);
            _canvas.mask = _mask;
        }
    }
    
    private function initHistoryLayers():Void
    {
        _historyContainer = new Sprite();
        addChild(_historyContainer);
        
        _historyLayers = [];
        for (i in 0...HISTORY_LAYERS) {
            var layer = new Sprite();
            layer.y = i * widgetHeight;
            _historyContainer.addChild(layer);
            _historyLayers.push(layer);
        }
        
        _currentLayer = 0;
        _historyFrameCount = 0;
        //trace('OscilloscopeWidget: History mode initialized with ${HISTORY_LAYERS} layers');
    }
    
    private function updateDimensions():Void {
        if (_oscAtom == null) return;
        var shape = _oscAtom.getDisplayShape();
        switch (shape) {
            case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR: 
                widgetWidth = 200; 
                widgetHeight = 200;
            default: 
                widgetWidth = 300; 
                widgetHeight = 150;
        }
    }
    
    private function drawBackground():Void {
        var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
        graphics.clear();
        graphics.beginFill(colorBg);
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) 
            graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
        else 
            graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
        graphics.endFill();
        graphics.lineStyle(3, 0x333355);
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) 
            graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
        else 
            graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
    }
    
    private function drawGrid():Void {
        var g = _grid.graphics; 
        g.clear(); 
        g.lineStyle(1, colorGrid, 0.7);
        var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) {
            var cx = widgetWidth / 2; 
            var cy = widgetHeight / 2; 
            var radius = widgetWidth / 2;
            for (i in 1...6) g.drawCircle(cx, cy, radius * (i / 5.0));
            g.moveTo(cx - radius, cy); g.lineTo(cx + radius, cy);
            g.moveTo(cx, cy - radius); g.lineTo(cx, cy + radius);
        } else {
            var stepX = widgetWidth / 10; 
            for (i in 0...11) { 
                g.moveTo(i * stepX, 0); 
                g.lineTo(i * stepX, widgetHeight); 
            }
            var stepY = widgetHeight / 6; 
            for (i in 0...7) { 
                g.moveTo(0, i * stepY); 
                g.lineTo(widgetWidth, i * stepY); 
            }
            g.lineStyle(1, colorGrid, 1.0); 
            g.moveTo(0, widgetHeight / 2); 
            g.lineTo(widgetWidth, widgetHeight / 2);
        }
    }
    
    private function drawMask():Void {
        var g = _mask.graphics; 
        g.clear(); 
        g.beginFill(0xFFFFFF);
        g.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2 - 2);
        g.endFill();
    }
    
    // =========================================================================
    // HISTORY MODE API
    // =========================================================================
    public function setHistoryMode(enabled:Bool):Void
    {
        if (_historyMode == enabled) return;
        _historyMode = enabled;
        //trace('OscilloscopeWidget: History mode ${enabled ? "ENABLED" : "DISABLED"}');
        
        removeChildren();
        buildUI();
        if (_oscAtom != null) syncFromAtom();
    }
    
    public function isHistoryMode():Bool return _historyMode;
    public function getCurrentLayer():Int return _currentLayer;
    public function getHistoryFrameCount():Int return _historyFrameCount;
    
    // =========================================================================
    // LIFECYCLE
    // =========================================================================
    override private function onActivate():Void { 
        syncFromAtom(); 
    }
    
    override private function syncFromAtom():Void {
        if (_oscAtom == null) return;
        updateDimensions(); 
        drawBackground(); 
        drawGrid(); 
        drawMask();
        
        if (_historyMode) {
			//trace('OscilloscopeWidget: History mode ready, waiting for frames...');
        } else {
            redrawFromAtom();
        }
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (isDisposed || _oscAtom == null) return;
        if (contact.name == "in") return;
        drawGrid(); 
        redrawFromAtom();
    }
    
    private function onFrameReady(impulse:Impulse):Void {
        if (isDisposed || impulse == null || impulse.data == null) return;
        if (_oscAtom == null || impulse.data.atomId != _oscAtom.id) return;
        _hasNewFrame = true;
    }
    
    private function onShapeChanged(impulse:Impulse):Void {
        if (isDisposed || impulse == null || impulse.data == null) return;
        if (_oscAtom == null || impulse.data.atomId != _oscAtom.id) return;
        var newShape:Int = impulse.data.shape;
        switch (newShape) {
            case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR: 
                widgetWidth = 200; 
                widgetHeight = 200;
            default: 
                widgetWidth = 300; 
                widgetHeight = 150;
        }
        removeChildren(); 
        buildUI();
    }
    
    private function onEnterFrame(e:openfl.events.Event):Void {
        if (_hasNewFrame && !_isRendering) {
            _hasNewFrame = false;
            redrawFromAtom();
        }
    }
    
    // =========================================================================
    // REDRAW LOGIC
    // =========================================================================
    private function redrawFromAtom():Void {
        if (_oscAtom == null) return;
        
        var buffer = _oscAtom.getBuffer();
        if (buffer == null || buffer.length == 0) return;
        
        _isRendering = true;
        
        // Atomic snapshot
        var count = buffer.length;
        if (_renderBuffer == null || _renderBuffer.length != count) {
            _renderBuffer = new Array<Float>();
            for (i in 0...count) _renderBuffer.push(0.0);
        }
        for (i in 0...count) {
            _renderBuffer[i] = buffer[i];
        }
        
        if (_historyMode) {
            redrawHistory(_renderBuffer);
        } else {
            redrawNormal(_renderBuffer);
        }
        
        _isRendering = false;
    }
    
	private function redrawNormal(buffer:Array<Float>):Void {
		var shape = _oscAtom.getDisplayShape();
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) {
			drawWaveCircular(buffer);
		} else {
			drawWaveLinear(buffer);
		}
	}

	private function redrawHistory(buffer:Array<Float>):Void {
		var layer = _historyLayers[_currentLayer];
		var g = layer.graphics;
		
		// Clear this layer (oldest wave in ring buffer)
		g.clear();
		
		// Draw new wave on this layer
		var shape = _oscAtom.getDisplayShape();
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) {
			drawWaveCircular(buffer, g);
		} else {
			drawWaveLinear(buffer, g);
		}
		
		// Advance ring buffer pointer
		_currentLayer = (_currentLayer + 1) % HISTORY_LAYERS;
		_historyFrameCount++;
		
		if (_historyFrameCount % 10 == 0) {
			trace('OscilloscopeWidget: History frame $_historyFrameCount, next layer to clear: $_currentLayer');
		}
	}
    
    // =========================================================================
    // WAVE DRAWING (NO WIDTH CLAMP)
    // =========================================================================
    
    /**
     * Draw linear waveform. 
     * NO width clamp — wave can extend beyond widgetWidth.
     * This allows timeScale=10 to show full wave length.
	 */
	private function drawWaveLinear(buffer:Array<Float>, ?targetGraphics:openfl.display.Graphics = null):Void {
		var g = targetGraphics != null ? targetGraphics : _canvas.graphics;
		if (targetGraphics == null) {
			_canvas.mask = _mask;
			g.clear();
		}
		
		var count = buffer.length;
		var zoom = _oscAtom.getZoom();
		var timeScale = _oscAtom.getTimeScale();
		var centerY = widgetHeight / 2.0;
		var scale = (widgetHeight / 2.0) * 0.9 * zoom;
		
		// === НОВАЯ ЛОГИКА: Берём только первый чанк и растягиваем на всю ширину ===
		// При timeScale=1.0 берём весь буфер
		// При timeScale=2.0 берём половину буфера (первые count/2 сэмплов)
		// При timeScale=10.0 берём 1/10 буфера (первые count/10 сэмплов)
		var samplesToShow = Math.ceil(count / timeScale);
		if (samplesToShow < 2) samplesToShow = 2;  // Минимум 2 точки для линии
		if (samplesToShow > count) samplesToShow = count;
		
		var stepX = widgetWidth / (samplesToShow - 1);
		
		g.lineStyle(1.0, colorLine, 1.0);
		
		// Рисуем только первые samplesToShow сэмплов
		var sample = buffer[0];
		if (!Math.isFinite(sample)) sample = 0.0;
		if (sample > 10) sample = 10; 
		if (sample < -1.5) sample = -1.5;
		g.moveTo(0, centerY - sample * scale);
		
		for (i in 1...samplesToShow) {
			sample = buffer[i];
			if (!Math.isFinite(sample)) sample = 0.0;
			if (sample > 10) sample = 10; 
			if (sample < -1.5) sample = -1.5;
			g.lineTo(i * stepX, centerY - sample * scale);
		}
	}
	private function drawWaveCircular(buffer:Array<Float>, ?targetGraphics:openfl.display.Graphics = null):Void {
		var g = targetGraphics != null ? targetGraphics : _canvas.graphics;
		if (targetGraphics == null) {
			g.clear();
		}
		
		var count = buffer.length;
		var zoom = _oscAtom.getZoom();
		var cx = widgetWidth / 2; 
		var cy = widgetHeight / 2;
		var maxRadius = (widgetWidth / 2) * 0.9 * zoom;
		
		g.lineStyle(1.0, colorLine, 1.0);
		
		var sample = buffer[0];
		if (!Math.isFinite(sample)) sample = 0.0;
		if (sample > 1.0) sample = 1.0; 
		if (sample < -1.0) sample = -1.0;
		var angle:Float = 0.0;
		var r = ((sample + 1.0) / 2.0) * maxRadius;
		g.moveTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
		
		for (i in 1...count) {
			sample = buffer[i];
			if (!Math.isFinite(sample)) sample = 0.0;
			if (sample > 1.0) sample = 1.0; 
			if (sample < -1.0) sample = -1.0;
			angle = (i / count) * Math.PI * 2;
			r = ((sample + 1.0) / 2.0) * maxRadius;
			g.lineTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
		}
	}
    
    // =========================================================================
    // CLEAR & DISPOSE
    // =========================================================================
    public function clearDisplay():Void { 
        if (_historyMode) {
            for (layer in _historyLayers) {
                if (layer != null) layer.graphics.clear();
            }
            _currentLayer = 0;
            _historyFrameCount = 0;
        } else if (_canvas != null) {
            _canvas.graphics.clear();
        }
    }
    
    public function clearAll():Void { 
        clearDisplay(); 
    }
    
    override public function dispose():Void {
        removeEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
        Impulsys.removeImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
        Impulsys.removeImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
        
        _canvas = null;
        _grid = null; 
        _mask = null; 
        _oscAtom = null;
        _renderBuffer = null;
        _historyLayers = null;
        _historyContainer = null;
        
        super.dispose();
    }
}