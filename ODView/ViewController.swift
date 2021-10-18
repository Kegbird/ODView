import UIKit
import ARKit
import RealityKit
import Vision
import KDTree

class ViewController: UIViewController, ARSCNViewDelegate
{
    @IBOutlet weak var arscnView : ARSCNView!
    
    private var obstacleNodes : [UUID: SCNNode]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard #available(iOS 14.0, *) else { return }
        
        obstacleNodes=[:]
        arscnView.delegate=self
        arscnView.frame=self.view.frame
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        arscnView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard #available(iOS 14.0, *) else { return }
        arscnView.session.pause()
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
        guard #available(iOS 14.0, *) else { return }
        
        DispatchQueue.global().async
        { [weak self] in
            guard let frame = self!.arscnView.session.currentFrame else { return }
            
            let currentCameraPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
            
            var minDistance = 1000.0
            var closestObstacle : SCNNode? = nil
            
            for anchorUUID in self!.obstacleNodes.keys
            {
                guard let obstacles = self!.obstacleNodes[anchorUUID] else { continue }
                
                for obstacle in obstacles.childNodes
                {
                    let obstaclePosition = obstacle.worldPosition
                    let distance = obstaclePosition.squaredDistance(to: currentCameraPosition)
                    
                    if(distance<minDistance)
                    {
                        minDistance=distance
                        if(closestObstacle != nil)
                        {
                            //False positives will return red
                            closestObstacle!.geometry?.firstMaterial?.diffuse.contents = UIColor.red
                        }
                        closestObstacle=obstacle
                    }
                    else
                    {
                        closestObstacle!.geometry?.firstMaterial?.diffuse.contents = UIColor.red
                    }
                }
            }
            
            if(closestObstacle != nil)
            {
                //Highlight closest obstacle
                closestObstacle!.geometry?.firstMaterial?.diffuse.contents = UIColor.green
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        
        guard #available(iOS 14.0, *) else { return nil }
        
        guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
        
        DispatchQueue.global().async
        { [weak self] in
            let meshGeometry = meshAnchor.geometry
            
            let anchorNode = SCNNode()
            
            self!.obstacleNodes[anchor.identifier] = anchorNode
                
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
                anchorNode.addChildNode(obstacleNode)
            }
        }
            
        return nil
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor)
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
    }
}
