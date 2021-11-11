import UIKit
import ARKit
import RealityKit
import SceneKit
import Vision
import KDTree

class ViewController: UIViewController, ARSCNViewDelegate
{
    @IBOutlet weak var arscnView : ARSCNView!
    
    private var labels : [ARMeshClassification]!
    
    private var colorPerLabel : [ARMeshClassification : CGColor]!
    
    private var floors : [UUID:SCNNode]!
    
    private var walls : [UUID:SCNNode]!
    
    private var obstacles : [Obstacle]!
    
    private var boundingBoxPerAnchor : [UUID: [ObstacleBoundingBoxView]]!
    
    private var boundingBoxes : [ObstacleBoundingBoxView]!
    
    private var planeQueue : DispatchQueue!
    
    private var obstacleQueue : DispatchQueue!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard #available(iOS 14.0, *) else { return }
        planeQueue = DispatchQueue(label: "com.ODView.planeQueue.serial", qos: .userInteractive)
        obstacleQueue = DispatchQueue(label: "com.ODView.obstacleQueue.serial", qos: .userInteractive)
        obstacles=[]
        colorPerLabel=[:]
        floors=[:]
        walls=[:]
        labels=[]
        boundingBoxPerAnchor=[:]
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
        arscnView.showsStatistics=true
        arscnView.debugOptions=[.showWorldOrigin]
        arscnView.preferredFramesPerSecond = Constants.PREFERRED_FPS
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = .meshWithClassification
        arscnView.session.run(configuration)
        
        boundingBoxes = []
        for _ in 0..<Constants.MAX_OBSTACLE_NUMBER
        {
            let boundingBox = ObstacleBoundingBoxView()
            boundingBox.addToLayer(arscnView.layer)
            boundingBoxes.append(boundingBox)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
    
    func calculateCentroid(_ vertices : [SCNVector3]) -> SCNVector3
    {
        var centroid = SCNVector3Zero
        
        for vertex in vertices
        {
            centroid.x = centroid.x + vertex.x
            centroid.y = centroid.y + vertex.y
            centroid.z = centroid.z + vertex.z
        }
        centroid.x /= (Float)(vertices.count)
        centroid.y /= (Float)(vertices.count)
        centroid.z /= (Float)(vertices.count)
        
        return centroid
    }
    
    func considerTriangle(_ classification : ARMeshClassification) -> Bool
    {
        return classification == .none || classification == .seat || classification == .table
    }
    
    func addFloorWallPlane(planeAnchor : ARPlaneAnchor, node : SCNNode)
    {
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        //If the area is too small, we discard it
        if(Float(width*height)<Constants.AREA_THRESHOLD)
        {
            return
        }
        let plane: SCNPlane = SCNPlane(width: width, height: height)
        let planeNode = SCNNode(geometry: plane)
        planeNode.simdPosition = planeAnchor.center
        planeNode.eulerAngles.x = -.pi / 2
        //Understand if its floor or ceiling
        if(planeAnchor.alignment == .horizontal)
        {
            guard let frame = arscnView.session.currentFrame else { return }
            let cameraPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
            let planeWorldPosition = SCNVector3(node.simdConvertPosition(planeNode.position.getSimd(), to: nil))
            if(cameraPosition.y<planeWorldPosition.y)
            {
                return
            }
            planeNode.geometry?.firstMaterial?.diffuse.contents=CGColor(red: 1, green: 0, blue: 1, alpha: 0.8)
            floors[planeAnchor.identifier]=planeNode
        }
        else
        {
            planeNode.geometry?.firstMaterial?.diffuse.contents=CGColor(red: 0, green: 1, blue: 0, alpha: 0.8)
            walls[planeAnchor.identifier]=planeNode
        }
        
        for i in stride(from: node.childNodes.count-1, through: 0, by: -1)
        {
            node.childNodes[i].removeFromParentNode()
        }
        let normal = planeNode.simdConvertVector(simd_float3(0, 0, 1), to: nil)
        let planeWorldPosition = planeNode.worldPosition
        let endPoint = SCNVector3(x: planeWorldPosition.x+normal.x, y: planeWorldPosition.y+normal.y, z: planeWorldPosition.z+normal.z)
        let line = createLine(vertices: [planeWorldPosition, SCNVector3(x: endPoint.x, y: endPoint.y, z: endPoint.z), endPoint], indices: [0,1], node: node)
        node.addChildNode(planeNode)
        node.addChildNode(line)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor)
    {
        if((anchor as? ARPlaneAnchor) != nil)
        {
            planeQueue.async
            { [weak self] in
                let planeAnchor = anchor as! ARPlaneAnchor
                self!.addFloorWallPlane(planeAnchor: planeAnchor, node: node)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        var walls : [(SCNVector3, SCNVector3)] = []
        var floors : [(SCNVector3, SCNVector3)] = []
        var viewportSize : CGSize!
        
        DispatchQueue.main.sync
        { [weak self] in
            viewportSize = self!.arscnView.bounds.size
        }
        
        planeQueue.sync
        { [weak self] in
            for uuid in self!.walls.keys
            {
                if(self!.walls[uuid] != nil)
                {
                    let wall = self!.walls[uuid]!
                    var normal = SCNVector3(wall.simdConvertVector(simd_float3(x: 0, y: 0, z: 1), to: nil))
                    normal = normal.normalize()
                    let wallWorldPosition = wall.worldPosition
                    walls.append((wallWorldPosition, normal))
                }
            }
            for uuid in self!.floors.keys
            {
                if(self!.floors[uuid] != nil)
                {
                    let floor = self!.floors[uuid]!
                    var normal = SCNVector3(floor.simdConvertVector(simd_float3(x: 0, y: 0, z: 1), to: nil))
                    normal = normal.normalize()
                    let floorWorldPosition = floor.worldPosition
                    floors.append((floorWorldPosition, normal))
                }
            }
        }
        
        obstacleQueue.async
        { [weak self] in
            guard let frame = self!.arscnView.session.currentFrame else { return }
            let anchors = frame.anchors
            
            if(floors.count==0 || walls.count==0) { return }
            
            let cameraWorldPosition = SCNVector3(
                x: frame.camera.transform.columns.3.x,
                y: frame.camera.transform.columns.3.y,
                z: frame.camera.transform.columns.3.z)
            
            var points : [SCNVector3] = []
            var indices : [Int32] = []
            
            for anchor in anchors
            {
                guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
                
                let currentAnchorWorldPosition = SCNVector3(meshAnchor.transform.position)
                
                if(SCNVector3.distanceBetween(cameraWorldPosition, currentAnchorWorldPosition)>=Constants.MAX_ANCHOR_DISTANCE) { continue }
                
                guard let meshNode = self!.arscnView.node(for: meshAnchor) else { continue }
                
                for i in 0..<meshAnchor.geometry.faces.count
                {
                    let triangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: i)
                    let triangleWorldPosition = meshNode.convertPosition(triangleLocalPosition, to: nil)
                    let triangleScreenPoint = frame.camera.projectPoint(triangleWorldPosition.getSimd(), orientation: .portrait, viewportSize: viewportSize)
                    
                    //Removing all triangles outside the screen
                    if(triangleScreenPoint.x<0 || viewportSize.width<triangleScreenPoint.x || triangleScreenPoint.y<0 || triangleScreenPoint.y>viewportSize.height)
                    {
                        continue
                    }
                    //Removing wall and floor triangles
                    let classification=meshAnchor.geometry.classificationOf(faceWithIndex: i)
                    
                    if(!self!.considerTriangle(classification)) { continue }
                        
                    var shouldContinue = false
                    
                    //Removing wall triangles
                    for wall in walls
                    {
                        let normal = wall.1.getSimd()
                        let relativePosition = triangleWorldPosition.getSimd()-wall.0.getSimd()
                        let distance = simd_dot(normal, relativePosition)
                        if(abs(distance)<Constants.PLANE_DISTANCE_THRESHOLD)
                        {
                            shouldContinue=true
                            break
                        }
                    }
                    
                    if(shouldContinue) { continue }
                    
                    //Removing floor triangles
                    for floor in floors
                    {
                        let normal = floor.1.getSimd()
                        let relativePosition = triangleWorldPosition.getSimd()-floor.0.getSimd()
                        let distance = simd_dot(normal, relativePosition)
                        if(abs(distance)<Constants.PLANE_DISTANCE_THRESHOLD)
                        {
                            shouldContinue=true
                            break
                        }
                    }
                    
                    if(shouldContinue) { continue }
                    
                    var triangleVertices = meshAnchor.geometry.verticesOf(faceWithIndex: i).compactMap({SCNVector3(x: $0.0, y: $0.1, z: $0.2)})
                    triangleVertices[0] = meshNode.convertPosition(triangleVertices[0], to: nil)
                    triangleVertices[1] = meshNode.convertPosition(triangleVertices[1], to: nil)
                    triangleVertices[2] = meshNode.convertPosition(triangleVertices[2], to: nil)
                    points.append(triangleVertices[0])
                    indices.append(Int32(points.count-1))
                    points.append(triangleVertices[1])
                    indices.append(Int32(points.count-1))
                    points.append(triangleVertices[2])
                    indices.append(Int32(points.count-1))
                }
            }
            
            let geometry = self!.createGeometry(vertices: points, indices: indices, primitiveType: .triangles)
            geometry.firstMaterial?.diffuse.contents = CGColor(red: 1, green: 0, blue: 0, alpha: 0.8)
            self!.arscnView.scene.rootNode.geometry = geometry
            
            //Sorting points
            points.sort(by:
            {
                return SCNVector3.distanceBetween($0, cameraWorldPosition)<SCNVector3.distanceBetween($1, cameraWorldPosition)
            })
            
            var currentCluster : Int = 0
            var clusters : [[SCNVector3]] = []
            //Min point, Max point and centroid for each cluster
            var bounds : [(CGPoint, CGPoint, SCNVector3)] = []
            
            for i in 0..<points.count
            {
                let screenPoint = frame.camera.projectPoint(points[i].getSimd(), orientation: .portrait, viewportSize: viewportSize)
                if(i==0)
                {
                    let cluster = [points[i]]
                    clusters.append(cluster)
                    bounds.append((screenPoint, screenPoint, points[i]))
                }
                else if(0<i)
                {
                    let lastWorldPoint = clusters[currentCluster].last!
                    if(SCNVector3.distanceBetween(points[i], lastWorldPoint)<Constants.TRIANGLE_DISTANCE_THRESHOLD)
                    {
                        clusters[currentCluster].append(points[i])
                        
                        if(screenPoint.x < bounds[currentCluster].0.x)
                        {
                            bounds[currentCluster].0.x = screenPoint.x
                        }
                        if(screenPoint.y < bounds[currentCluster].0.y)
                        {
                            bounds[currentCluster].0.y = screenPoint.y
                        }
                        
                        if(screenPoint.x > bounds[currentCluster].1.x)
                        {
                            bounds[currentCluster].1.x = screenPoint.x
                        }
                        if(screenPoint.y > bounds[currentCluster].1.y)
                        {
                            bounds[currentCluster].1.y = screenPoint.y
                        }
                        
                        bounds[currentCluster].2.x+=points[i].x
                        bounds[currentCluster].2.y+=points[i].y
                        bounds[currentCluster].2.z+=points[i].z
                    }
                    else
                    {
                        bounds[currentCluster].2.x/=Float(clusters[currentCluster].count)
                        bounds[currentCluster].2.y/=Float(clusters[currentCluster].count)
                        bounds[currentCluster].2.z/=Float(clusters[currentCluster].count)
                        let cluster = [points[i]]
                        clusters.append(cluster)
                        bounds.append((screenPoint, screenPoint, points[i]))
                        currentCluster=currentCluster+1
                    }
                }
            }
        
            DispatchQueue.main.sync
            { [weak self] in
                for boundingBox in self!.boundingBoxes
                {
                    boundingBox.hide()
                }
            }
            
            var j = 0
            for i in 0..<clusters.count
            {
                if(clusters[i].count<Constants.MIN_POINTS_NUMBER)
                {
                    /*let centroid = bounds[i].2
                    let outsider = SCNNode(geometry: SCNSphere(radius: 0.1))
                    outsider.geometry?.firstMaterial?.diffuse.contents = UIColor.purple
                    outsider.worldPosition=centroid
                    self!.arscnView.scene.rootNode.addChildNode(outsider)*/
                    continue
                }
                
                let width = bounds[i].1.x - bounds[i].0.x
                let height = bounds[i].1.y - bounds[i].0.y
                let frame = CGRect(x: bounds[i].0.x, y: bounds[i].0.y, width: width, height: height)
                
                DispatchQueue.main.sync
                { [weak self] in
                    if(j==0)
                    {
                        self!.boundingBoxes[j].show(frame: frame, color: UIColor.red)
                    }
                    else
                    {
                        self!.boundingBoxes[j].show(frame: frame, color: UIColor.blue)
                    }
                }
                j=j+1
                
                if(j == Constants.MAX_OBSTACLE_NUMBER) { break }
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor)
    {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        planeQueue.async
        { [weak self] in
            var node = self!.floors[planeAnchor.identifier]
            if(node != nil) { node!.removeFromParentNode() }
            node = self!.walls[planeAnchor.identifier]
            if (node != nil) { node!.removeFromParentNode() }
            self!.floors.removeValue(forKey: planeAnchor.identifier)
            self!.walls.removeValue(forKey: planeAnchor.identifier)
        }
    }
}
