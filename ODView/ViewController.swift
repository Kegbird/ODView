import UIKit
import ARKit
import RealityKit
import SceneKit
import Vision
import KDTree

class ViewController: UIViewController, ARSCNViewDelegate
{
    @IBOutlet weak var arscnView : ARSCNView!
    
    private var obstacleNodes : [UUID: SCNNode]!
    
    private var labels : [ARMeshClassification]!
    
    private var colorPerLabel : [ARMeshClassification : CGColor]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard #available(iOS 14.0, *) else { return }
        obstacleNodes=[:]
        colorPerLabel=[:]
        labels=[]
        labels.append(.wall)
        labels.append(.ceiling)
        labels.append(.door)
        labels.append(.floor)
        labels.append(.none)
        labels.append(.seat)
        labels.append(.table)
        labels.append(.window)
        //rosso muro
        colorPerLabel[.wall]=CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.8)
        //verde porta
        colorPerLabel[.door]=CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.8)
        //soffitto blu
        colorPerLabel[.ceiling]=CGColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.8)
        //pavimento viola
        colorPerLabel[.floor]=CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.8)
        //sedia arancione
        colorPerLabel[.seat]=CGColor(red: 1.0, green: 165.0/255.0, blue: 0, alpha: 0.8)
        //tavolo blu chiaro
        colorPerLabel[.table]=CGColor(red: 173.0/255.0, green: 216.0/255.0, blue: 230.0/255.0, alpha: 0.8)
        //finestra rosa
        colorPerLabel[.window]=CGColor(red:1.0, green: 192.0/255.0, blue: 203/255.0, alpha: 0.8)
        //bianco none
        colorPerLabel[.none] = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.8)
        arscnView.delegate=self
        arscnView.frame=self.view.frame
        arscnView.debugOptions.insert(SCNDebugOptions.showWorldOrigin)
        arscnView.debugOptions.insert(SCNDebugOptions.showFeaturePoints)
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = .meshWithClassification
        arscnView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard #available(iOS 14.0, *) else { return }
        arscnView.session.pause()
    }
    
    func createGeometry(vertices:[SCNVector3], indices:[Int32], primitiveType:SCNGeometryPrimitiveType) -> SCNGeometry
    {
        
        // Computed property that indicates the number of primitives to create based on primitive type
        var primitiveCount:Int
        {
            get {
                switch primitiveType
                {
                case SCNGeometryPrimitiveType.line:
                    return indices.count / 2
                case SCNGeometryPrimitiveType.point:
                    return indices.count
                default:
                    return indices.count / 3
                }
            }
        }
        
        // Create the source and elements in the appropriate format
        let data = NSData(bytes: vertices, length: MemoryLayout<SCNVector3>.size * vertices.count)
        let vertexSource = SCNGeometrySource(
            data: data as Data, semantic: SCNGeometrySource.Semantic.vertex,
            vectorCount: vertices.count, usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.size)
        
        let indexData = NSData(bytes: indices, length: MemoryLayout<Int32>.size * indices.count)
        let element = SCNGeometryElement(
            data: indexData as Data, primitiveType: primitiveType,
            primitiveCount: primitiveCount, bytesPerIndex: MemoryLayout<Int32>.size)
        
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }
    
    func createLine(vertices:[SCNVector3], indices:[Int32], node: SCNNode)
    {
        let indices = [Int32(0), Int32(1)]
        let geometry = createGeometry(vertices: vertices, indices: indices, primitiveType: SCNGeometryPrimitiveType.line)
        geometry.firstMaterial?.diffuse.contents=CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let line = SCNNode(geometry: geometry)
        line.position=SCNVector3Zero
        node.addChildNode(line)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor)
    {
        if((anchor as? ARPlaneAnchor) != nil)
        {
            let planeAnchor = anchor as! ARPlaneAnchor
            let width = CGFloat(planeAnchor.extent.x)
            let height = CGFloat(planeAnchor.extent.z)
            let plane: SCNPlane = SCNPlane(width: width, height: height)
            let planeNode = SCNNode(geometry: plane)
            planeNode.simdPosition = planeAnchor.center
            planeNode.eulerAngles.x = -.pi / 2
            //Understand if its floor or ceiling
            if(planeAnchor.alignment == .horizontal)
            {
                guard let frame = arscnView.session.currentFrame else { return }
                let cameraPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
                let planeWorldTransform = node.simdConvertTransform(simd_float4x4(planeNode.transform), to: nil)
                let planeWorldPosition = SCNVector3(x: planeWorldTransform.columns.3.x, y:
                    planeWorldTransform.columns.3.y, z:
                    planeWorldTransform.columns.3.z)
                //let normal = simd_float4(0, 0 ,1, 1) * planeWorldTransform
                if(cameraPosition.y<planeWorldPosition.y)
                {
                    return
                }
                planeNode.geometry?.firstMaterial?.diffuse.contents=CGColor(red: 1, green: 0, blue: 1, alpha: 0.8)
            }
            else
            {
                planeNode.geometry?.firstMaterial?.diffuse.contents=CGColor(red: 0, green: 1, blue: 0, alpha: 0.8)
            }
            
            for i in stride(from: node.childNodes.count-1, through: 0, by: -1)
            {
                node.childNodes[i].removeFromParentNode()
            }
            node.addChildNode(planeNode)
        }
        else if ((anchor as? ARMeshAnchor) != nil)
        {
        }
    }
}
