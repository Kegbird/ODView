import UIKit
import ARKit
import RealityKit
import SceneKit
import Vision
import KDTree

class ViewController: UIViewController, ARSCNViewDelegate
{
    @IBOutlet weak var arscnView : ARSCNView!
    
    @IBOutlet weak var clusterLbl : UILabel!
    
    private var labels : [ARMeshClassification]!
    
    private var colorPerLabel : [ARMeshClassification : CGColor]!
    
    private var floors : [UUID:SCNNode]!
    
    private var walls : [UUID:SCNNode]!
    
    private var obstacles : [UUID: SCNNode]!
    
    private var queue : DispatchQueue!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard #available(iOS 14.0, *) else { return }
        queue = DispatchQueue(label: "com.ODView.serial", qos: .userInteractive)
        obstacles=[:]
        colorPerLabel=[:]
        floors=[:]
        walls=[:]
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
    
    func createLine(vertices:[SCNVector3], indices:[Int32], node: SCNNode) -> SCNNode
    {
        let indices = [Int32(0), Int32(1)]
        let geometry = createGeometry(vertices: vertices, indices: indices, primitiveType: SCNGeometryPrimitiveType.line)
        geometry.firstMaterial?.diffuse.contents=CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let line = SCNNode(geometry: geometry)
        return line
    }
    
    func considerTriangle(_ classification : ARMeshClassification) -> Bool
    {
        return classification == .none || classification == .seat || classification == .table
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor)
    {
        queue.async
        { [weak self] in
            if((anchor as? ARPlaneAnchor) != nil)
            {
                let planeAnchor = anchor as! ARPlaneAnchor
                let width = CGFloat(planeAnchor.extent.x)
                let height = CGFloat(planeAnchor.extent.z)
                //If the area is too small, we discard it
                if(Float(width*height)<Constants.AREA_THRESHOLD) { return }
                let plane: SCNPlane = SCNPlane(width: width, height: height)
                let planeNode = SCNNode(geometry: plane)
                planeNode.simdPosition = planeAnchor.center
                planeNode.eulerAngles.x = -.pi / 2
                //Understand if its floor or ceiling
                if(planeAnchor.alignment == .horizontal)
                {
                    guard let frame = self!.arscnView.session.currentFrame else { return }
                    let cameraPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
                    let planeWorldPosition = SCNVector3(node.simdConvertPosition(planeNode.position.getSimd(), to: nil))
                    if(cameraPosition.y<planeWorldPosition.y)
                    {
                        return
                    }
                    planeNode.geometry?.firstMaterial?.diffuse.contents=CGColor(red: 1, green: 0, blue: 1, alpha: 0.8)
                    self!.floors[anchor.identifier]=planeNode
                }
                else
                {
                    planeNode.geometry?.firstMaterial?.diffuse.contents=CGColor(red: 0, green: 1, blue: 0, alpha: 0.8)
                    self!.walls[anchor.identifier]=planeNode
                }
                for i in stride(from: node.childNodes.count-1, through: 0, by: -1)
                {
                    node.childNodes[i].removeFromParentNode()
                }
                let normal = planeNode.simdConvertVector(simd_float3(0, 0, 1), to: nil)
                let planeWorldPosition = planeNode.worldPosition
                let endPoint = SCNVector3(x: planeWorldPosition.x+normal.x, y: planeWorldPosition.y+normal.y, z: planeWorldPosition.z+normal.z)
                let line = self!.createLine(vertices: [planeWorldPosition, SCNVector3(x: endPoint.x, y: endPoint.y, z: endPoint.z), endPoint], indices: [0,1], node: node)
                node.addChildNode(line)
                node.addChildNode(planeNode)
            }
            else if ((anchor as? ARMeshAnchor) != nil)
            {
                //Remove all the geometry near walls or floor
                let meshAnchor = anchor as! ARMeshAnchor
                
                if(meshAnchor.geometry.faces.count<Constants.MIN_NUMBER_TRIANGLES) { return }
                
                var vertices : [SCNVector3] = []
                var indices : [Int32] = []
                var obstacleFacesIndices : [Int] = []
                //First loop finds all floor triangles
                //For those without classification,
                //I check if there are triangles near already detected planes
                for i in 0..<meshAnchor.geometry.faces.count
                {
                    let classification=meshAnchor.geometry.classificationOf(faceWithIndex: i)
                    let triangleVertices = meshAnchor.geometry.verticesOf(faceWithIndex: i)
                    let triangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: i)
                    let triangleWorldPosition = node.convertPosition(triangleLocalPosition, to: nil)
                    if(self!.considerTriangle(classification))
                    {
                        var shouldContinue = false
                        for wall in self!.walls.values
                        {
                            let normal = wall.simdConvertVector(simd_float3(x: 0, y: 0, z: 1), to: nil)
                            let wallWorldPosition = wall.worldPosition.getSimd()
                            let relativePosition = triangleWorldPosition.getSimd()-wallWorldPosition
                            let distance = simd_dot(normal, relativePosition)
                            if(abs(distance)<Constants.DISTANCE_THRESHOLD)
                            {
                                shouldContinue=true
                                break
                            }
                        }
                        
                        if(shouldContinue) { continue }
                        
                        for floor in self!.floors.values
                        {
                            let normal = floor.simdConvertVector(simd_float3(x: 0, y: 0, z: 1), to: nil)
                            let floorWorldPosition = floor.worldPosition.getSimd()
                            let relativePosition = triangleWorldPosition.getSimd()-floorWorldPosition
                            let distance = simd_dot(simd_float3(normal.x, normal.y, normal.z), relativePosition)
                            if(abs(distance)<Constants.DISTANCE_THRESHOLD)
                            {
                                shouldContinue=true
                                break
                            }
                        }
                        
                        if(shouldContinue) { continue }
                        
                        obstacleFacesIndices.append(i)
                        for i in 0..<triangleVertices.count
                        {
                            let vertex = SCNVector3(x: triangleVertices[i].0,
                                y: triangleVertices[i].1,
                                z: triangleVertices[i].2)
                            vertices.append(vertex)
                            indices.append(Int32(vertices.count-1))
                        }
                    }
                }
                
                if(vertices.count<Constants.MIN_NUMBER_TRIANGLES) { return }
                
                var clusters : [[SCNVector3]] = []
                var processed : Set<Int> = []
                
                for i in 0..<obstacleFacesIndices.count
                {
                    let faceIndex = obstacleFacesIndices[i]
                    if(processed.contains(faceIndex)){ continue }
                    let vertices = meshAnchor.geometry.verticesOf(faceWithIndex: faceIndex).compactMap({SCNVector3(x: $0.0, y: $0.1, z: $0.2)})
                    var cluster : [SCNVector3] = []
                    cluster.append(vertices[0])
                    cluster.append(vertices[1])
                    cluster.append(vertices[2])
                    let triangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: faceIndex)
                    let triangleWorldPosition = node.convertPosition(triangleLocalPosition, to: nil)
                    for j in i+1..<obstacleFacesIndices.count
                    {
                        let otherFaceIndex = obstacleFacesIndices[j]
                        if(processed.contains(otherFaceIndex)) { continue }
                        let otherTriangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: otherFaceIndex)
                        let otherTriangleWorldPosition = node.convertPosition(otherTriangleLocalPosition, to: nil)
                        if(triangleWorldPosition.squaredDistance(to: otherTriangleWorldPosition)<=Double(Constants.TRIANGLE_DISTANCE_THRESHOLD))
                        {
                            let otherVertices = meshAnchor.geometry.verticesOf(faceWithIndex: otherFaceIndex).compactMap({SCNVector3(x: $0.0, y: $0.1, z: $0.2)})
                            cluster.append(otherVertices[0])
                            cluster.append(otherVertices[1])
                            cluster.append(otherVertices[2])
                            processed.insert(otherFaceIndex)
                        }
                    }
                    processed.insert(faceIndex)
                    clusters.append(cluster)
                }
                
                for i in stride(from: node.childNodes.count-1, through: 0, by: -1)
                {
                    node.childNodes[i].removeFromParentNode()
                }
                
                DispatchQueue.main.async
                {
                    self?.clusterLbl.text=String(format: "Clusters: %d", clusters.count)
                }
                
                let color = CGColor(red: CGFloat.random(in: 0..<255)/CGFloat(255), green: CGFloat.random(in: 0..<255)/CGFloat(255), blue: CGFloat.random(in: 0..<255)/CGFloat(255), alpha: 1.0)
                for cluster in clusters
                {
                    var centroid=cluster.reduce(SCNVector3Zero,
                    {
                        SCNVector3(x: $0.x+$1.x, y: $0.y+$1.y, z: $0.z+$1.z)
                    })
                    centroid.x = centroid.x / Float(cluster.count)
                    centroid.y = centroid.y / Float(cluster.count)
                    centroid.z = centroid.z / Float(cluster.count)
                    let centroidWorldPosition = node.simdConvertPosition( centroid.getSimd(), to: nil)
                    let obstacleNode = SCNNode(geometry: SCNSphere(radius: 0.1))
                    obstacleNode.geometry?.firstMaterial?.diffuse.contents = color
                    node.addChildNode(obstacleNode)
                    obstacleNode.worldPosition=SCNVector3(centroidWorldPosition)
                }
                let obstaclesGeometry = self!.createGeometry(vertices: vertices, indices: indices, primitiveType: .triangles)
                obstaclesGeometry.firstMaterial?.diffuse.contents=CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                let obstaclesNode = SCNNode(geometry: obstaclesGeometry)
                node.addChildNode(obstaclesNode)
            }
        }
    }
    
    /*func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor)
    {
    guard #available(iOS 14.0, *) else { return }
    
    guard let meshAnchor = anchor as? ARMeshAnchor else { return }
    
    DispatchQueue.global().async
    { [weak self] in
    
    guard let obstacleNodes = self!.obstacleNodes[anchor.identifier] else { return }
    
    for i in stride(from: obstacleNodes.childNodes.count-1, to: -1, by: -1)
    {
    obstacleNodes.childNodes[i].removeFromParentNode()
    }
    
    let meshGeometry = meshAnchor.geometry
    
    var obstaclePoints : [SCNVector3] = []
    
    //Loop over the faces belonging to the new anchor to extract
    //all points not belonging to ceiling, floor, wall and window
    for index in 0..<meshGeometry.faces.count
    {
    //If the face belong to wall/windows/ceiling, we discard that face
    let classification=meshGeometry.classificationOf(faceWithIndex: index)
    
    if(classification != .ceiling &&
    classification != .floor &&
    classification != .wall &&
    classification != .window)
    {
    let faceVertices = meshGeometry.verticesOf(faceWithIndex: index).compactMap({SCNVector3(x: $0.0, y: $0.1, z: $0.2)})
    obstaclePoints.append(faceVertices[0])
    obstaclePoints.append(faceVertices[1])
    obstaclePoints.append(faceVertices[2])
    }
    }
    
    if(obstaclePoints.count==0) { return }
    
    let kdTree : KDTree = KDTree(values: obstaclePoints)
    
    let clusters=kdTree.euclideanClustering()
    
    for cluster in clusters
    {
    let count = Float(cluster.count)
    
    if(count==0){ continue }
    
    var centroid = cluster.reduce(SCNVector3(x: 0, y: 0, z:0))
    {
    SCNVector3(x: $0.x+$1.x, y: $0.y+$1.y, z: $0.z+$1.z)
    }
    centroid.x=centroid.x/count
    centroid.y=centroid.y/count
    centroid.z=centroid.z/count
    
    let obstacleNode = SCNNode(geometry: SCNSphere(radius: 0.5))
    obstacleNode.geometry?.firstMaterial?.diffuse.contents = UIColor.red
    obstacleNode.worldPosition=centroid
    obstacleNodes.addChildNode(obstacleNode)
    }
    }
    }*/
}
