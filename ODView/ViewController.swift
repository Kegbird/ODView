import UIKit
import ARKit
import RealityKit
import SceneKit
import Vision

class ViewController: UIViewController, ARSCNViewDelegate, UIGestureRecognizerDelegate
{
    @IBOutlet weak var arscnView : ARSCNView!
    
    private var floors : [UUID:SCNNode]!
    
    private var walls : [UUID:SCNNode]!
    
    private var boundingBoxPerAnchor : [UUID: [(CGPoint, CGPoint)]]!
    
    private var boundingBoxes : [ObstacleBoundingBoxView]!
    
    private var planeQueue : DispatchQueue!
    
    private var obstacleQueue : DispatchQueue!
    
    private var lockQueue : DispatchQueue!
    
    private var fileName : String!
    
    private var viewportSize : CGSize!
    
    private var processing : Bool!
    
    private var obstaclePerAnchor : [UUID: [Obstacle]]!
    
    private var colorPerAnchor : [UUID : UIColor]!
    //Facce e performance: Facce totali, Facce filtrate, Filtering,Clustering, Creazione MBR, Merging
    private var performances : [(Int, Int, Float, Float, Float, Float)]!
    
    @IBOutlet private var clusterLbl : UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard #available(iOS 14.0, *) else { return }
        
        setupViewVariables()
        
        setupARSCNView()
        
        setupBoundingBoxes()
        
        createFileName()
    }
    
    public func createFileName()
    {
        let date = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        fileName = String(format: "Data-%d:%d", hour, minutes)
    }
    
    public func saveFile()
    {
        let documentDirectoryUrl = try! FileManager.default.url(
            for: .documentDirectory, in: .allDomainsMask, appropriateFor: nil, create: true)
        let fileUrl = documentDirectoryUrl.appendingPathComponent(fileName).appendingPathExtension("csv")
        
        print(fileUrl.path)
        var content = ""
        content="Facce Totali;Facce Filtrate;Tempo filtraggio;Tempo clustering;Tempo MBR;Tempo merge"
        for record in performances
        {
            content=content+"\n"+String(format: "%d;%d;%.2f;%.2f;%.2f;%.2f", record.0, record.1, record.2, record.3, record.4, record.5)
        }
        do {
              try content.write(to: fileUrl, atomically: true, encoding: String.Encoding.utf8)
        } catch let error as NSError
        {
            print (error)
        }
    }
    
    func setupViewVariables()
    {
        performances=[]
        boundingBoxPerAnchor=[:]
        colorPerAnchor=[:]
        floors=[:]
        walls=[:]
        planeQueue = DispatchQueue(label: "com.odview.planequeue.serial", qos: .userInteractive)
        obstacleQueue = DispatchQueue(label: "com.odview.obstaclequeue.serial", qos: .userInteractive)
        lockQueue = DispatchQueue(label: "com.odview.lockqueue.serial")
        viewportSize = CGSize(width: 390, height: 763)
        processing = false
        obstaclePerAnchor = [:]
    }
    
    func setupARSCNView()
    {
        arscnView.delegate=self
        arscnView.frame=self.view.frame
        arscnView.showsStatistics=true
        arscnView.preferredFramesPerSecond = Constants.PREFERRED_FPS
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = .meshWithClassification
        arscnView.session.run(configuration)
    }
    
    func setupBoundingBoxes()
    {
        boundingBoxes = []
        for _ in 0..<Constants.MAX_OBSTACLE_NUMBER
        {
            let boundingBox = ObstacleBoundingBoxView()
            boundingBox.addToLayer(arscnView.layer)
            boundingBoxes.append(boundingBox)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        saveFile()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool)
    {
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
        else if((anchor as? ARMeshAnchor) != nil)
        {
            //Posizione e normale di ogni muro o piano
            var walls : [(SCNVector3, SCNVector3)] = []
            var floors : [(SCNVector3, SCNVector3)] = []
            
            planeQueue.sync
            { [weak self] in
                guard self != nil else { return }
                
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
                let begin = DispatchTime.now()
                let meshAnchor = anchor as! ARMeshAnchor
                
                guard let frame = self!.arscnView.session.currentFrame else
                {
                    self!.processing=false
                    return
                }
                
                var faceIndices : [Int] = []
                
                let cameraWorldPosition = SCNVector3(
                    x: frame.camera.transform.columns.3.x,
                    y: frame.camera.transform.columns.3.y,
                    z: frame.camera.transform.columns.3.z)
                
                let currentAnchorWorldPosition = SCNVector3(meshAnchor.transform.position)
                
                //L'ancora che voglio aggiungere è troppo distante
                if(SCNVector3.distanceBetween(cameraWorldPosition, currentAnchorWorldPosition)>=Constants.MAX_ANCHOR_DISTANCE)
                {
                    self!.processing=false
                    return
                }
                
                var points : [SCNVector3] = []
                var indices : [Int32] = []
                
                let color : UIColor!
                if(self!.colorPerAnchor[anchor.identifier]==nil)
                {
                    let color = CGColor(red: CGFloat.random(in: 0..<255.0)/255.0, green: CGFloat.random(in: 0..<255.0)/255.0, blue: CGFloat.random(in: 0..<255.0)/255.0, alpha: 0.8)
                    self!.colorPerAnchor[anchor.identifier] = UIColor(cgColor: color)
                    print("Colore ",color, " per ancora:", anchor.identifier)
                }
                color = self!.colorPerAnchor[anchor.identifier]
                let meshGeometry = meshAnchor.geometry
                
                for i in 0..<meshAnchor.geometry.faces.count
                {
                    let triangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: i)
                    let triangleWorldPosition = node.convertPosition(triangleLocalPosition, to: nil)
                    let triangleScreenPoint = frame.camera.projectPoint(triangleWorldPosition.getSimd(), orientation: .portrait, viewportSize: self!.viewportSize)
                    
                    //Removing all triangles outside the screen
                    if(triangleScreenPoint.x<0 || self!.viewportSize.width<triangleScreenPoint.x || triangleScreenPoint.y<0 || triangleScreenPoint.y>self!.viewportSize.height)
                    {
                        continue
                    }
                    let classification=meshAnchor.geometry.classificationOf(faceWithIndex: i)
                    
                    if(!self!.considerTriangle(classification)) { continue }
                        
                    var shouldContinue = false
                    
                    //Rimuovo triangoli dei muri
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
                    
                    //Rimuovo triangoli del pavimento
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
                    
                    faceIndices.append(i)
                    
                    let vertices = meshGeometry.verticesOf(faceWithIndex: i).map
                    {
                        SCNVector3(x: $0.0, y: $0.1, z: $0.2)
                    }
                    
                    let verticesNode = vertices.compactMap
                    {
                         node.convertPosition($0, to: node)
                    }
                    
                    points.append(verticesNode[0])
                    indices.append(Int32(points.count-1))
                    points.append(verticesNode[1])
                    indices.append(Int32(points.count-1))
                    points.append(verticesNode[2])
                    indices.append(Int32(points.count-1))
                }
                
                node.geometry = self!.createGeometry(vertices: points, indices: indices, primitiveType: .triangles)
                node.geometry?.firstMaterial?.diffuse.contents=color
                
                var faceClusters : [Set<UInt32>] = []
                var pointClusters : [Set<UInt32>] = []
                
                for faceIndex in faceIndices
                {
                    let vertexIndices = meshAnchor.geometry.vertexIndicesOf(faceWithIndex: faceIndex)
                    
                    var pointClustersConnected : [Set<UInt32>] = []
                    var faceClustersConnected : [Set<UInt32>] = []
                    
                    for i in stride(from: pointClusters.count-1, through: 0, by: -1)
                    {
                        if(pointClusters[i].contains(vertexIndices[0]) || pointClusters[i].contains(vertexIndices[1]) || pointClusters[i].contains(vertexIndices[2]))
                        {
                            //Allora il vertice è connesso a uno dei cluster esistenti
                            pointClustersConnected.append(pointClusters[i])
                            faceClustersConnected.append(faceClusters[i])
                            pointClusters.remove(at: i)
                            faceClusters.remove(at: i)
                        }
                    }
                    
                    var newPointCluster : Set<UInt32> = []
                    var newFaceCluster : Set<UInt32> = []
                    
                    if(pointClustersConnected.count != 0)
                    {
                        //Altrimenti bisogna fare il merge di tutti i cluster connessi
                        for i in 0..<pointClustersConnected.count
                        {
                            newPointCluster=newPointCluster.union(pointClustersConnected[i])
                            newFaceCluster=newFaceCluster.union(faceClustersConnected[i])
                        }
                    }
                    newPointCluster.insert(vertexIndices[0])
                    newPointCluster.insert(vertexIndices[1])
                    newPointCluster.insert(vertexIndices[2])
                    newFaceCluster.insert(UInt32(faceIndex))
                    pointClusters.append(newPointCluster)
                    faceClusters.append(newFaceCluster)
                }
                
                var obstacles : [Obstacle] = []
                //Per ogni cluster genero la relativa mbr
                for i in stride(from: faceClusters.count-1, through: 0, by: -1)
                {
                    if(faceClusters[i].count<Constants.MIN_NUMBER_TRIANGLES_FOR_CLUSTER)
                    {
                        faceClusters.remove(at: i)
                        pointClusters.remove(at: i)
                        continue
                    }
                    let faceCluster = faceClusters[i]
                    var indexHolder : Set<UInt32> = []
                    let obstacle = Obstacle()
                    //Generazione mbr e relativi centroidi
                    for faceIndex in faceCluster
                    {
                        let vertices = meshGeometry.verticesOf(faceWithIndex: Int(faceIndex)).map
                        {
                            SCNVector3(x: $0.0, y: $0.1, z: $0.2)
                        }
                        
                        let worldVertices = vertices.compactMap
                        {
                            node.convertPosition($0, to: nil)
                        }
                        
                        let vertexIndices = meshGeometry.vertexIndicesOf(faceWithIndex: Int(faceIndex))
                        
                        for j in 0..<vertexIndices.count-1
                        {
                            let index = vertexIndices[j]
                            if(!indexHolder.contains(index))
                            {
                                indexHolder.insert(index)
                                obstacle.updateBoundaries(frame: frame, viewportSize: self!.viewportSize, worldPoint: worldVertices[j])
                            }
                        }
                    }
                    obstacles.append(obstacle)
                }
                
                //Fondo le mbr vicine generate a partire dalla stessa ancora
                var i = 0
                while(i<obstacles.count)
                {
                    let obstacle = obstacles[i]
                    var j = obstacles.count-1
                    while(j>i)
                    {
                        let otherObstacle = obstacles[j]
                        if(obstacle.getDistanceWithOtherObstacle(other: otherObstacle)<=Constants.MERGE_DISTANCE)
                        {
                            //Se la distanza tra le due mbr è minore della
                            //merge distance, allora eseguo il merge tra i
                            //2 oggetti.
                            obstacle.mergeWithOther(other: otherObstacle)
                            obstacles[i] = obstacle
                            //Rimuovo ostacolo non necessario.
                            obstacles.remove(at: j)
                            //Riprendo lo scan per i merge dall'inizio.
                            i=0
                            j=obstacles.count-1
                        }
                        else
                        {
                            //Altrimenti passo all'ostacolo successivo
                            j-=1
                        }
                    }
                    i=i+1
                }
                
                self!.lockQueue.async
                { [weak self] in
                    self!.obstaclePerAnchor[anchor.identifier]=obstacles
                }
                
                self!.processing=false
                let end=DispatchTime.now()
                
                let time = Float(end.uptimeNanoseconds - begin.uptimeNanoseconds) / 1_000_000_000
            }
            
            
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
        node.transform=SCNMatrix4(anchor.transform)
        return node
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        var currentObstacles : [Obstacle] = []
        var identifiers : [String] = []
        
        lockQueue.sync
        { [weak self] in
            for key in self!.obstaclePerAnchor.keys
            {
                guard let obstacles = self!.obstaclePerAnchor[key] else { continue }
                var k = key as! UUID
                var kString = String(k.uuidString.prefix(5))
                identifiers = identifiers + Array(repeating: kString, count:  obstacles.count)
                currentObstacles = currentObstacles + obstacles
            }
            
        }
        
        if(currentObstacles.count>=Constants.MAX_OBSTACLE_NUMBER)
        {
            for i in stride(from: currentObstacles.count-1, to: 49, by: -1)
            {
                currentObstacles.remove(at: i)
            }
        }
        
        DispatchQueue.main.sync
        { [weak self] in
            var i = 0
            
            for obstacle in currentObstacles
            {
                let frame = obstacle.getFrame()
                self!.boundingBoxes[i].show(frame: frame, label: identifiers[i], color: UIColor.blue)
                i+=1
            }
            for i in stride(from: i, to: self!.boundingBoxes.count, by: 1)
            {
                self!.boundingBoxes[i].hide()
            }
        }
        
        //Position and normal for all walls and floors
        /*var walls : [(SCNVector3, SCNVector3)] = []
        var floors : [(SCNVector3, SCNVector3)] = []
        
        planeQueue.sync
        { [weak self] in
            guard self != nil else { return }
            
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
            guard self != nil else { return }
            
            var filteringTime : Float = 0
            var clusteringTime : Float = 0
            var mbrCreationTime : Float = 0
            var mergeTime : Float = 0
            
            guard let frame = self!.arscnView.session.currentFrame else { return }
            
            let anchors = frame.anchors.filter
            {
                ($0 as? ARMeshAnchor) != nil
            }
            
            if(anchors.count==0) { return }
            
            if(floors.count==0 || walls.count==0) { return }
            
            let cameraWorldPosition = SCNVector3(
                x: frame.camera.transform.columns.3.x,
                y: frame.camera.transform.columns.3.y,
                z: frame.camera.transform.columns.3.z)
            
            var points : [SCNVector3] = []
            var indices : [Int32] = []
            //Sono le facce che non vengono collassate a muri o pareti per anchor
            var facesPerAnchor : [ARMeshAnchor : [Int]] = [:]
            var faceTotal = 0
            var faceFiltered = 0
            
            var begin = DispatchTime.now()
            
            //Filtraggio facce per ogni ancora armesh
            for anchor in anchors
            {
                let meshAnchor = (anchor as? ARMeshAnchor)!
                
                facesPerAnchor[meshAnchor]=[]
                
                let currentAnchorWorldPosition = SCNVector3(meshAnchor.transform.position)
                
                if(SCNVector3.distanceBetween(cameraWorldPosition, currentAnchorWorldPosition)>=Constants.MAX_ANCHOR_DISTANCE) { continue }
            
                guard let meshNode = self!.arscnView.node(for: meshAnchor) else { continue }
                
                for i in 0..<meshAnchor.geometry.faces.count
                {
                    faceTotal+=1
                    
                    let triangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: i)
                    let triangleWorldPosition = meshNode.convertPosition(triangleLocalPosition, to: nil)
                    let triangleScreenPoint = frame.camera.projectPoint(triangleWorldPosition.getSimd(), orientation: .portrait, viewportSize: self!.viewportSize)
                    
                    //Removing all triangles outside the screen
                    if(triangleScreenPoint.x<0 || self!.viewportSize.width<triangleScreenPoint.x || triangleScreenPoint.y<0 || triangleScreenPoint.y>self!.viewportSize.height)
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
                    
                    faceFiltered+=1
                    
                    facesPerAnchor[meshAnchor]!.append(i)
                    
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
            
            var end = DispatchTime.now()
            
            filteringTime = Float(end.uptimeNanoseconds - begin.uptimeNanoseconds) / 1_000_000_000
            
            //Debug mesh
            /*let geometry = self!.createGeometry(vertices: points, indices: indices, primitiveType: .triangles)
            geometry.materials.first?.diffuse.contents=CGColor(red: 1.0, green: 0, blue: 0, alpha: 0.8)
            self!.arscnView.scene.rootNode.geometry = geometry*/
            
            var pointClusterPerAnchor : [ARMeshAnchor : [Set<UInt32>]] = [:]
            var faceClusterPerAnchor : [ARMeshAnchor : [Set<UInt32>]] = [:]
            
            begin = DispatchTime.now()
            
            //Clustering
            for meshAnchor in facesPerAnchor.keys
            {
                let currentAnchorWorldPosition = SCNVector3(meshAnchor.transform.position)
                
                if(SCNVector3.distanceBetween(cameraWorldPosition, currentAnchorWorldPosition)>=Constants.MAX_ANCHOR_DISTANCE) { continue }
                
                guard let faceIndices = facesPerAnchor[meshAnchor] else { continue }
                
                var faceClusters : [Set<UInt32>] = []
                var pointClusters : [Set<UInt32>] = []
                
                for faceIndex in faceIndices
                {
                    let vertexIndices = meshAnchor.geometry.vertexIndicesOf(faceWithIndex: faceIndex)
                    
                    var pointClustersConnected : [Set<UInt32>] = []
                    var faceClustersConnected : [Set<UInt32>] = []
                    
                    for i in stride(from: pointClusters.count-1, through: 0, by: -1)
                    {
                        if(pointClusters[i].contains(vertexIndices[0]) || pointClusters[i].contains(vertexIndices[1]) || pointClusters[i].contains(vertexIndices[2]))
                        {
                            //Allora il vertice è connesso a uno dei cluster esistenti
                            pointClustersConnected.append(pointClusters[i])
                            faceClustersConnected.append(faceClusters[i])
                            pointClusters.remove(at: i)
                            faceClusters.remove(at: i)
                        }
                    }
                    
                    var newPointCluster : Set<UInt32> = []
                    var newFaceCluster : Set<UInt32> = []
                    
                    if(pointClustersConnected.count != 0)
                    {
                        //Altrimenti bisogna fare il merge di tutti i cluster connessi
                        for i in 0..<pointClustersConnected.count
                        {
                            newPointCluster=newPointCluster.union(pointClustersConnected[i])
                            newFaceCluster=newFaceCluster.union(faceClustersConnected[i])
                        }
                    }
                    newPointCluster.insert(vertexIndices[0])
                    newPointCluster.insert(vertexIndices[1])
                    newPointCluster.insert(vertexIndices[2])
                    newFaceCluster.insert(UInt32(faceIndex))
                    pointClusters.append(newPointCluster)
                    faceClusters.append(newFaceCluster)
                }
                faceClusterPerAnchor[meshAnchor]=faceClusters
                pointClusterPerAnchor[meshAnchor]=pointClusters
            }
            
            end = DispatchTime.now()
            
            clusteringTime = Float(end.uptimeNanoseconds - begin.uptimeNanoseconds) / 1_000_000_000
            
            var bounds : [(CGPoint, CGPoint)] = []
            
            var centroids : [SCNVector3] = []
            
            for i in stride(from: self!.refNode.childNodes.count-1, through: 0, by: -1)
            {
                self!.refNode.childNodes[i].removeFromParentNode()
            }
            
            begin = DispatchTime.now()
            
            //Generazione mbr
            for meshAnchor in faceClusterPerAnchor.keys
            {
                guard var faceClusters = faceClusterPerAnchor[meshAnchor] else { continue }
                
                guard var pointClusters = pointClusterPerAnchor[meshAnchor] else { continue }
                
                guard let meshNode = self!.arscnView.node(for: meshAnchor) else { continue }
                
                var points : [SCNVector3] = []
                var indices : [Int32] = []
                let color = CGColor(red: CGFloat.random(in: 0..<255.0)/255.0, green: CGFloat.random(in: 0..<255.0)/255.0, blue: CGFloat.random(in: 0..<255.0)/255.0, alpha: 0.8)
                //let color = CGColor(red: 1, green: 0, blue: 0, alpha: 0.8)
                
                for i in stride(from: faceClusters.count-1, through: 0, by: -1)
                {
                    let faceCluster = faceClusters[i]
                    
                    if(faceCluster.count<Constants.MIN_NUMBER_TRIANGLES_FOR_CLUSTER)
                    {
                        faceClusters.remove(at: i)
                        pointClusters.remove(at: i)
                        continue
                    }
                    
                    let (x, y, z) : (Float, Float, Float) = meshAnchor.geometry.verticesOf(faceWithIndex: Int(faceCluster.first!)).first!
                    
                    let vertex = meshNode.convertPosition(SCNVector3(x: x, y: y, z: z), to: nil)
                    
                    let screenPoint = frame.camera.projectPoint(vertex.getSimd(), orientation: .portrait, viewportSize: self!.viewportSize)
                    
                    //Bound salverà punto minimo e massimo delle varie mbr
                    var bound = (screenPoint, screenPoint)
                    var centroid = SCNVector3Zero
                    
                    //Generazione mbr e relativi centroidi
                    for faceIndex in faceCluster
                    {
                        let vertices = meshAnchor.geometry.verticesOf(faceWithIndex: Int(faceIndex)).compactMap
                        {
                            SCNVector3(x: $0.0, y: $0.1, z: $0.2)
                        }
                        
                        let worldVertices = vertices.compactMap
                        {
                            meshNode.convertPosition($0, to: nil)
                        }
                        
                        points.append(worldVertices[0])
                        indices.append((Int32)(points.count-1))
                        points.append(worldVertices[1])
                        indices.append((Int32)(points.count-1))
                        points.append(worldVertices[2])
                        indices.append((Int32)(points.count-1))
                        
                        //Aggiorno il centroid
                        centroid.x += worldVertices[0].x
                        centroid.y += worldVertices[0].y
                        centroid.z += worldVertices[0].z
                        
                        centroid.x += worldVertices[1].x
                        centroid.y += worldVertices[1].y
                        centroid.z += worldVertices[1].z
                        
                        centroid.x += worldVertices[2].x
                        centroid.y += worldVertices[2].y
                        centroid.z += worldVertices[2].z
                        
                        let screenVertices = worldVertices.compactMap
                        {
                            frame.camera.projectPoint($0.getSimd(), orientation: .portrait, viewportSize: self!.viewportSize)
                        }
                        for screenVertex in screenVertices
                        {
                            if(screenVertex.x<bound.0.x)
                            {
                                bound.0.x=screenVertex.x
                            }
                            if(screenVertex.y<bound.0.y)
                            {
                                bound.0.y=screenVertex.y
                            }
                            if(screenVertex.x>bound.1.x)
                            {
                                bound.1.x=screenVertex.x
                            }
                            if(screenVertex.y>bound.1.y)
                            {
                                bound.1.y=screenVertex.y
                            }
                        }
                    }
                    centroid.x/=Float(faceCluster.count)
                    centroid.y/=Float(faceCluster.count)
                    centroid.z/=Float(faceCluster.count)
                    bounds.append(bound)
                    centroids.append(centroid)
                    
                    let node = SCNNode(geometry: self!.createGeometry(vertices: points, indices: indices, primitiveType: .triangles))
                    node.geometry?.firstMaterial?.diffuse.contents = UIColor(cgColor: color)
                    self!.refNode.addChildNode(node)
                }
            }
            
            end = DispatchTime.now()
            
            mbrCreationTime = Float(end.uptimeNanoseconds - begin.uptimeNanoseconds) / 1_000_000_000
            
            begin = DispatchTime.now()
            
            print("Centroids before merge:")
            for centroid in centroids
            {
                print(centroid)
            }
            
            //Merge centroidi vicini vicine
            var i = 0
            while(i>0)
            {
                var j = 0
                while(j<i)
                {
                    if(SCNVector3.distanceBetween(centroids[i], centroids[j])<=Constants.CLUSTER_MERGE_DISTANCE)
                    {
                        print("Merge between:", centroids[i], centroids[j])
                        var newCentroid = centroids[i]
                        //Calcolo il nuovo centroide
                        newCentroid.x += centroids[j].x
                        newCentroid.y += centroids[j].y
                        newCentroid.z += centroids[j].z
                        newCentroid.x /= 2.0
                        newCentroid.y /= 2.0
                        newCentroid.z /= 2.0
                        //Calcolo la nuova mbr
                        var bound = bounds[i]
                        let otherBound = bounds[j]
                        if(bound.0.x>otherBound.0.x)
                        {
                            bound.0.x=otherBound.0.x
                        }
                        if(bound.0.y>otherBound.0.y)
                        {
                            bound.0.y=otherBound.0.y
                        }
                        if(bound.1.x<otherBound.1.x)
                        {
                            bound.1.x=otherBound.1.x
                        }
                        if(bound.1.y<otherBound.1.y)
                        {
                            bound.1.y=otherBound.1.y
                        }
                        centroids[i]=newCentroid
                        bounds[i]=bound
                        bounds.remove(at: j)
                        centroids.remove(at: j)
                        i=centroids.count-1
                        j=0
                        print("New centroid:", newCentroid)
                    }
                    else
                    {
                        j+=1
                    }
                }
                i-=1
            }
            
            print("Centroids after merge:")
            for centroid in centroids
            {
                print(centroid)
            }
            
            end = DispatchTime.now()
            
            mergeTime = Float(end.uptimeNanoseconds - begin.uptimeNanoseconds) / 1_000_000_000
            
            self!.performances.append((faceTotal, faceFiltered, filteringTime, clusteringTime, mbrCreationTime, mergeTime))
            
            DispatchQueue.main.async
            {
                self!.clusterLbl.text = String(format:"Clusters: %d", bounds.count)
            }
            
            //Visualizzo mbr trovate
            for i in 0..<bounds.count
            {
                let bound = bounds[i]
                let width = bound.1.x - bound.0.x
                let height = bound.1.y - bound.0.y
                let frame = CGRect(x: bound.0.x, y: bound.0.y, width: width, height: height)
                DispatchQueue.main.async
                { [weak self] in
                    guard self != nil else { return }
                    self!.boundingBoxes[i].show(frame: frame, color: UIColor.white)
                }
                let node = SCNNode(geometry: SCNSphere(radius: 0.1))
                node.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
                self!.refNode.addChildNode(node)
                node.worldPosition = centroids[i]
            }
            
            if(0<=bounds.count && bounds.count<Constants.MAX_OBSTACLE_NUMBER)
            {
                //Nascondo le mbr non usate
                for i in bounds.count..<Constants.MAX_OBSTACLE_NUMBER
                {
                    DispatchQueue.main.async
                    { [weak self] in
                        self!.boundingBoxes[i].hide()
                    }
                }
            }
        }*/
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor)
    {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        planeQueue.async
        { [weak self] in
            guard self != nil else { return }
            
            var node = self!.floors[planeAnchor.identifier]
            if(node != nil) { node!.removeFromParentNode() }
            node = self!.walls[planeAnchor.identifier]
            if (node != nil) { node!.removeFromParentNode() }
            self!.floors.removeValue(forKey: planeAnchor.identifier)
            self!.walls.removeValue(forKey: planeAnchor.identifier)
        }
    }
}
