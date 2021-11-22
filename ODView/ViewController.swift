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
    
    private var boundingBoxes : [ObstacleBoundingBoxView]!
    
    private var planeQueue : DispatchQueue!
    
    private var obstacleQueue : DispatchQueue!
    
    private var lockQueue : DispatchQueue!
    
    private var fileName : String!
    
    private var viewportSize : CGSize!
    
    private var obstaclePerAnchor : [UUID: [Obstacle]]!
    
    private var colorPerAnchor : [UUID : UIColor]!
    
    private var refNode : SCNNode!
    
    //Facce e performance: Facce totali, Totale tempo
    private var performances : [(Int, Float)]!
    
    @IBOutlet private var clusterLbl : UILabel!
    
    @IBOutlet private var anchorLbl : UILabel!
    
    @IBOutlet private var wallLbl : UILabel!
    
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
            content=content+"\n"+String(format: "%d;%.2f", record.0, record.1)
        }
        do {
              try content.write(to: fileUrl, atomically: true, encoding: String.Encoding.utf8)
        }
        catch let error as NSError
        {
            print (error)
        }
    }
    
    func setupViewVariables()
    {
        UIApplication.shared.isIdleTimerDisabled = true
        performances=[]
        colorPerAnchor=[:]
        floors=[:]
        walls=[:]
        planeQueue = DispatchQueue(label: "com.odview.planequeue.serial", qos: .userInteractive)
        obstacleQueue = DispatchQueue(label: "com.odview.obstaclequeue.serial", qos: .userInteractive)
        lockQueue = DispatchQueue(label: "com.odview.lockqueue.serial")
        viewportSize = CGSize(width: 390, height: 763)
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
        refNode = SCNNode()
        arscnView.scene.rootNode.addChildNode(refNode)
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
    
    func calculateTriangleNormal(_ vertices : [SCNVector3]) -> SCNVector3
    {
        if(vertices.count<2) { return SCNVector3Zero }
        let firstVector = vertices[1].getSimd()-vertices[0].getSimd()
        let secondVector = vertices[2].getSimd()-vertices[0].getSimd()
        let normal = cross(firstVector, secondVector)
        return SCNVector3(normal)
    }
    
    func addFloorWallPlane(planeAnchor : ARPlaneAnchor, node : SCNNode)
    {
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        let plane: SCNPlane = SCNPlane(width: width, height: height)
        let planeNode = SCNNode(geometry: plane)
        planeNode.simdPosition = planeAnchor.center
        planeNode.eulerAngles.x = -.pi / 2
        
        if(colorPerAnchor[planeAnchor.identifier]==nil)
        {
            let color = CGColor(red: CGFloat.random(in: 0..<255.0)/255.0, green: CGFloat.random(in: 0..<255.0)/255.0, blue: CGFloat.random(in: 0..<255.0)/255.0, alpha: 0.8)
            colorPerAnchor[planeAnchor.identifier]=UIColor(cgColor: color)
        }
        
        //Understand if its floor or ceiling
        if(planeAnchor.alignment == .horizontal)
        {
            guard let frame = arscnView.session.currentFrame else { return }
            let cameraWorldPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
            let planeWorldPosition = SCNVector3(node.simdConvertPosition(planeNode.position.getSimd(), to: nil))
            if(cameraWorldPosition.y<planeWorldPosition.y)
            {
                node.removeFromParentNode()
                return
            }
            planeNode.geometry?.firstMaterial?.diffuse.contents=UIColor(cgColor: CGColor(red: 0, green: 1, blue: 1, alpha: 0.8))
            floors[planeAnchor.identifier]=planeNode
        }
        else
        {
            planeNode.geometry?.firstMaterial?.diffuse.contents=UIColor(cgColor: CGColor(red: 0, green: 1, blue: 0, alpha: 0.8))
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
    }
    
    func findObstacles(node: SCNNode, anchor: ARAnchor, renderer: SCNSceneRenderer)
    {
        let meshAnchor = anchor as! ARMeshAnchor
        var walls : [(SCNVector3, SCNVector3)] = []
        var floors : [(SCNVector3, SCNVector3)] = []
        guard let pointOfView = renderer.pointOfView else { return }
        //Recupero normale e posizione di tutti i muri e pavimenti
        planeQueue.sync
        { [weak self] in
            for uuid in self!.walls.keys
            {
                if(self!.walls[uuid] != nil)
                {
                    let wall = self!.walls[uuid]!
                    //Rimuovo i muri non più visibili
                    if(!renderer.isNode(wall, insideFrustumOf: pointOfView))
                    {
                        wall.removeFromParentNode()
                        self!.walls[uuid]=nil
                        continue
                    }
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
                    //Rimuovo i piani pavimento non più visibili
                    if(!renderer.isNode(floor, insideFrustumOf: pointOfView))
                    {
                        floor.removeFromParentNode()
                        self!.floors[uuid]=nil
                        continue
                    }
                    var normal = SCNVector3(floor.simdConvertVector(simd_float3(x: 0, y: 0, z: 1), to: nil))
                    normal = normal.normalize()
                    let floorWorldPosition = floor.worldPosition
                    floors.append((floorWorldPosition, normal))
                }
            }
        }
        //Eseguo l'obstacle detection a livello di ancora
        obstacleQueue.async
        { [weak self] in
            guard let frame = self!.arscnView.session.currentFrame else
            {
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
                return
            }
            
            var points : [SCNVector3] = []
            var indices : [Int32] = []
            
            let color : UIColor!
            if(self!.colorPerAnchor[anchor.identifier]==nil)
            {
                let color = CGColor(red: CGFloat.random(in: 0..<255.0)/255.0, green: CGFloat.random(in: 0..<255.0)/255.0, blue: CGFloat.random(in: 0..<255.0)/255.0, alpha: 1)
                self!.colorPerAnchor[anchor.identifier] = UIColor(cgColor: color)
            }
            color = self!.colorPerAnchor[anchor.identifier]
            let meshGeometry = meshAnchor.geometry
            
            //MARK: Filtro facce
            for i in 0..<meshAnchor.geometry.faces.count
            {
                let triangleLocalPosition = meshAnchor.geometry.centerOf(faceWithIndex: i)
                let triangleWorldPosition = node.convertPosition(triangleLocalPosition, to: nil)
                let triangleScreenPoint = frame.camera.projectPoint(triangleWorldPosition.getSimd(), orientation: .portrait, viewportSize: self!.viewportSize)
                
                //Rimuovo i triangolo fuori dallo schermo
                if(triangleScreenPoint.x<0 || self!.viewportSize.width<triangleScreenPoint.x || triangleScreenPoint.y<0 || triangleScreenPoint.y>self!.viewportSize.height)
                {
                    continue
                }
                //Rimuovo i triangoli la cui classificazione non ci interessa (muri, pavimento)
                let classification=meshAnchor.geometry.classificationOf(faceWithIndex: i)
                
                if(!self!.considerTriangle(classification)) { continue }
                
                let vertices = meshGeometry.verticesOf(faceWithIndex: i).map
                {
                    SCNVector3(x: $0.0, y: $0.1, z: $0.2)
                }
                
                let verticesWorldPosition = vertices.compactMap
                {
                    node.convertPosition($0, to: nil)
                }
                
                /*let triangleWorldNormal = self!.calculateTriangleNormal(verticesWorldPosition)
                
                if(triangleWorldNormal.dotProduct(otherPoint: SCNVector3(x:0, y: 1, z: 0))>=0.5)
                {
                    continue
                }*/
                
                var shouldContinue = false
                
                //Rimuovo triangoli vicini ai muri o dietro ai muri
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
                
                //Rimuovo triangoli del pavimento e sotto il pavimento
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
               
                let verticesLocalPosition = vertices.compactMap
                {
                     node.convertPosition($0, to: node)
                }
                
                points.append(verticesLocalPosition[0])
                indices.append(Int32(points.count-1))
                points.append(verticesLocalPosition[1])
                indices.append(Int32(points.count-1))
                points.append(verticesLocalPosition[2])
                indices.append(Int32(points.count-1))
            }
            
            node.geometry = self!.createGeometry(vertices: points, indices: indices, primitiveType: .triangles)
            node.geometry?.firstMaterial?.diffuse.contents=color
            
            var faceClusters : [Set<UInt32>] = []
            var pointClusters : [Set<UInt32>] = []
            
            //MARK: Clustering
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
            
            //MARK: Generazione mbr
            for i in stride(from: faceClusters.count-1, through: 0, by: -1)
            {
                if(faceClusters[i].count<Constants.MIN_NUMBER_TRIANGLES_FOR_CLUSTER)
                {
                    faceClusters.remove(at: i)
                    pointClusters.remove(at: i)
                    continue
                }
                
                let faceCluster = faceClusters[i]
                let obstacle = Obstacle()
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
                    
                    for j in 0..<3
                    {
                        obstacle.updateBoundaries(frame: frame, viewportSize: self!.viewportSize, worldPoint: worldVertices[j])
                    }
                }
                obstacles.append(obstacle)
            }
            
            //MARK: Merge MBR generate a partire da questa ancora
            self!.merge(obstacles: &obstacles)
            
            self!.lockQueue.async
            { [weak self] in
                self!.obstaclePerAnchor[anchor.identifier]=obstacles
            }
        }
    }
    
    func merge(obstacles : inout [Obstacle])
    {
        var i = 0
        while(i<obstacles.count)
        {
            var obstacle = obstacles[i]
            var j = obstacles.count-1
            while(j>i)
            {
                var otherObstacle = obstacles[j]
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
                    obstacle = obstacles[i]
                    otherObstacle = obstacles[j]
                }
                else
                {
                    //Altrimenti passo all'ostacolo successivo
                    j-=1
                }
            }
            i=i+1
        }
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
            findObstacles(node: node, anchor: anchor, renderer: renderer)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode?
    {
        let node = SCNNode()
        node.transform=SCNMatrix4(anchor.transform)
        return node
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        guard let frame = arscnView.session.currentFrame else { return }
        var counter = 0
        var anchorCounter = 0
        var allObstacles : [Obstacle] = []
        
        lockQueue.sync
        { [weak self] in
            let arMeshAnchors = frame.anchors.compactMap
            {
                $0 as? ARMeshAnchor
            }
            //Rimuovo i nodi non visibili
            let pointOfView = renderer.pointOfView!
            for arMeshAnchor in arMeshAnchors
            {
                let obstacleNode = self!.arscnView.node(for: arMeshAnchor)
                if((obstacleNode != nil &&
                    !renderer.isNode(obstacleNode!, insideFrustumOf: pointOfView)) || obstacleNode==nil)
                {
                    self!.obstaclePerAnchor[arMeshAnchor.identifier]=nil
                }
                else
                {
                    continue
                }
            }
            
            for key in self!.obstaclePerAnchor.keys
            {
                guard let obstacles = self!.obstaclePerAnchor[key] else { continue }
                allObstacles = allObstacles + obstacles
                counter += obstacles.count
            }
            
            anchorCounter=self!.obstaclePerAnchor.keys.count
        }
        
        //MARK: Merge close obstacle
        merge(obstacles: &allObstacles)
        
        if(allObstacles.count>=Constants.MAX_OBSTACLE_NUMBER)
        {
            for i in stride(from: allObstacles.count-1, to: Constants.MAX_OBSTACLE_NUMBER-1, by: -1)
            {
                allObstacles.remove(at: i)
            }
        }
        
        //DEBUG
        /*for i in stride(from: refNode.childNodes.count-1, through: 0, by: -1)
        {
            refNode.childNodes[i].removeFromParentNode()
        }
        
        for obstacle in allObstacles
        {
            let min = SCNNode(geometry: SCNSphere(radius: 0.01))
                        min.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
            min.worldPosition = obstacle.getMinWorldPosition()
            refNode.addChildNode(min)
                        
            let max = SCNNode(geometry: SCNSphere(radius: 0.01))
                        max.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            max.worldPosition = obstacle.getMaxWorldPosition()
            refNode.addChildNode(max)
        }*/
        
        DispatchQueue.main.sync
        { [weak self] in
            clusterLbl.text = String(format:"Clusters: %d", counter)
            anchorLbl.text = String(format:"Anchors: %d", anchorCounter)
            var i = 0
            for obstacle in allObstacles
            {
                let frame = obstacle.getFrame()
                self!.boundingBoxes[i].show(frame: frame, label: "Obstacle", color: UIColor.blue)
                i+=1
            }
            for i in stride(from: allObstacles.count, to: boundingBoxes.count, by: 1)
            {
                self!.boundingBoxes[i].hide()
            }
        }
    }
}
