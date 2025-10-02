package Application.Stage3D {
    import flash.geom.Vector3D;
    import flash.display3D.VertexBuffer3D;
    import flash.display3D.IndexBuffer3D;

    /**
     * Connection between scene nodes
     * Represents visual link with geometry
     */
    public class Edge {
        public var fromNode:SceneNode;
        public var toNode:SceneNode;
        public var vertexBuffer:VertexBuffer3D;
        public var indexBuffer:IndexBuffer3D;

        /** Create edge between two nodes */
        public function Edge(from:SceneNode, to:SceneNode) {
            this.fromNode = from;
            this.toNode = to;
        }
    }
}
