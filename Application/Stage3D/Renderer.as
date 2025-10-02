package Application.Stage3D {
    import flash.display3D.*;
    import flash.geom.Matrix3D;
    import Application.Stage3D.com.adobe.utils.AGALMiniAssembler;
    import flash.display.Stage;

    /** 
	 * Main rendering system for Stage3D 
	 */
    public class Renderer {
        private var context3D:Context3D;
        private var camera:Camera;
        private var sceneManager:SceneManager;
        private var stage:Stage;

        private var textProgram:Program3D;
        private var colorProgram:Program3D;

        private const GRID_ALPHA:Number = 0.35;

        /** Create renderer with context and scene */
        public function Renderer(context3D:Context3D, camera:Camera, sceneManager:SceneManager, stage:Stage) {
            this.context3D = context3D;
            this.camera = camera;
            this.sceneManager = sceneManager;
            this.stage = stage;

            initPrograms();
        }

        /** Initialize shader programs */
        private function initPrograms():void {
            var vAsm:AGALMiniAssembler = new AGALMiniAssembler();
            vAsm.assemble(Context3DProgramType.VERTEX,
                "m44 op, va0, vc0     \n" +
                "mov v0, va1          \n"
            );

            var fAsm:AGALMiniAssembler = new AGALMiniAssembler();
            fAsm.assemble(Context3DProgramType.FRAGMENT,
                "tex ft0, v0, fs0 <2d,linear,nomip,repeat> \n" +
                "mul ft0, ft0, fc1                         \n" +
                "mov oc, ft0                               \n"
            );

            textProgram = context3D.createProgram();
            textProgram.upload(vAsm.agalcode, fAsm.agalcode);

            vAsm = new AGALMiniAssembler();
            vAsm.assemble(Context3DProgramType.VERTEX,
                "m44 op, va0, vc0     \n"
            );

            fAsm = new AGALMiniAssembler();
            fAsm.assemble(Context3DProgramType.FRAGMENT,
                "mov oc, fc0          \n"
            );

            colorProgram = context3D.createProgram();
            colorProgram.upload(vAsm.agalcode, fAsm.agalcode);
        }

        /** Render complete scene */
        public function render():void {
            context3D.clear(0.1, 0.1, 0.1, 1.0);
            sceneManager.updateAnimations();

            var viewMatrix:Matrix3D = camera.getViewMatrix();
            var projMatrix:Matrix3D = camera.getProjectionMatrix(stage.stageWidth / stage.stageHeight);

            context3D.setDepthTest(true, Context3DCompareMode.LESS_EQUAL);
            context3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);

            for each (var node:SceneNode in sceneManager.getNodes()) {
                renderNode(node, viewMatrix, projMatrix, false);
            }

            context3D.setBlendFactors(Context3DBlendFactor.SOURCE_ALPHA, Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
            context3D.setDepthTest(false, Context3DCompareMode.LESS_EQUAL);

            for each (var sprite:Sprite3D in sceneManager.getSprites()) {
                renderNode(sprite, viewMatrix, projMatrix, true);
            }

            for each (var grid:SceneNode in sceneManager.getGridNodes()) {
                renderNode(grid, viewMatrix, projMatrix, true);
            }

            context3D.present();
        }

        /** Render single scene node */
        private function renderNode(node:SceneNode, viewMatrix:Matrix3D, projMatrix:Matrix3D, isGrid:Boolean):void {
            var modelMatrix:Matrix3D = node.getTransform();
            var mvpMatrix:Matrix3D = modelMatrix.clone();
            mvpMatrix.append(viewMatrix);
            mvpMatrix.append(projMatrix);

            context3D.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 0, mvpMatrix, true);

            if (node.texture) {
                context3D.setProgram(textProgram);
                var alpha:Number = isGrid ? GRID_ALPHA : 1.0;
                context3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, Vector.<Number>([1.0, 1.0, 1.0, alpha]));

                context3D.setVertexBufferAt(0, node.vertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
                context3D.setVertexBufferAt(1, node.vertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);
                context3D.setTextureAt(0, node.texture);
            } else {
                context3D.setProgram(colorProgram);
                var r:Number = ((node.color >> 16) & 0xFF) / 255.0;
                var g:Number = ((node.color >> 8) & 0xFF) / 255.0;
                var b:Number = (node.color & 0xFF) / 255.0;
                context3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, Vector.<Number>([r, g, b, 1.0]));

                context3D.setVertexBufferAt(0, node.vertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
                context3D.setVertexBufferAt(1, null);
                context3D.setTextureAt(0, null);
            }

            context3D.drawTriangles(node.indexBuffer);
            context3D.setVertexBufferAt(0, null);
            context3D.setVertexBufferAt(1, null);
            context3D.setTextureAt(0, null);
        }
    }
}