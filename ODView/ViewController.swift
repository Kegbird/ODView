/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Contains the view controller for the Breakfast Finder.
 */

import UIKit
import ARKit
import AVFoundation
import Vision

class ViewController: UIViewController, ARSCNViewDelegate {
    
    private let minConfidence: Float = 0.70
    
    private let minTrackingConfidence : Float = 0.1
    
    var bufferSize: CGSize = .zero
    
    @IBOutlet weak var arscnView: ARSCNView!
    
    @IBOutlet weak var infoLabel : UILabel!
    
    private var processing : Bool = false
    
    private var begin : DispatchTime!
    
    let maxBoundingBoxViews = 10
    
    let screenSubdivisionFactor : Float = 1.0/3.0
    
    var visionUpdatePerSec = 0
    
    var offset = -20
    
    var stop = false
    
    var obstaclesList = [Obstacle]()
    
    var boundingBoxViews = [BoundingBoxView]()
    
    var colors: [String: UIColor] = [:]
    
    let coreMLModel = MobileNetV2_SSDLite()
    
    var lastVisionUpdate : DispatchTime?
    
    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()
    
    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel, completionHandler: {
            [weak self] request, error in
            guard let frame = self!.arscnView.session.currentFrame else { return }
            if let results = request.results {
                self!.drawVisionRequestResults(request, frame: frame)
            }
        })
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()
    
    private let visionQueue = DispatchQueue.init(label: "com.apple.Vision", qos: .userInitiated)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAR()
        setupBoundingBoxViews()
        self.lastVisionUpdate=DispatchTime.now()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        arscnView.session.run(configuration)
        begin=DispatchTime.now()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arscnView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func setupAR()
    {
        arscnView.delegate=self
        //arscnView.debugOptions=[ARSCNDebugOptions.showFeaturePoints]
    }
    
    func setupBoundingBoxViews()
    {
        for _ in 0..<maxBoundingBoxViews {
            boundingBoxViews.append(BoundingBoxView())
        }
        
        // The label names are stored inside the MLModel's metadata.
        guard let userDefined =
                coreMLModel.model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String],
              let allLabels = userDefined["classes"] else {
            fatalError("Missing metadata")
        }
        
        let labels = allLabels.components(separatedBy: ",")
        
        /*let labels = ["person", "bicycle", "car", "motorcycle", "airplane", "bus",                  "train", "truck", "boat", "traffic light", "fire hydrant",
         "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
         "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard",
         "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
         "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
         "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone",
         "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors", "teddy bear",
         "hair drier", "toothbrush"]*/
        // Assign random colors to the classes.
        for label in labels {
            colors[label] = UIColor(red: CGFloat.random(in: 0...1),
                                    green: CGFloat.random(in: 0...1),
                                    blue: CGFloat.random(in: 0...1),
                                    alpha: 0.5)
        }
        
        for box in self.boundingBoxViews {
            box.addToLayer(self.arscnView.layer)
        }
    }
    
    func distance(a: SCNVector3, b: SCNVector3) -> Float
    {
        return sqrt(pow(a.x-b.x, 2)+pow(a.y-b.y, 2)+pow(a.z+b.z, 2))
    }
    
    func evaluateObstacleRelativePositionOnScreen(boundingBoxCenter : CGPoint) -> String
    {
        if(boundingBoxCenter.x<arscnView.bounds.width/3)
        {
            return "Left"
        }
        else if(arscnView.bounds.width/3<=boundingBoxCenter.x && boundingBoxCenter.x<2*arscnView.bounds.width/3)
        {
            return "Middle"
        }
        return "Right"
    }
    
    func getObstacleClosestPoint(points: ARPointCloud?, boundingBox: CGRect, frame: ARFrame) -> SCNVector3?
    {
        if points==nil { return nil }
        
        var minDistance : Float = 100.0
        var closestPoint : SCNVector3!
        let currentCameraPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
        
        for i in 0...points!.points.count-1
        {
            let point = points!.points[i]
            
            let screenPoint=frame.camera.projectPoint(point, orientation: UIInterfaceOrientation.portrait, viewportSize: self.arscnView.bounds.size)
            
            if(boundingBox.contains(screenPoint))
            {
                let p = SCNVector3(point.x, point.y, point.z)
                let distance=distance(a: currentCameraPosition, b: p)
                if(minDistance>distance)
                {
                    minDistance=distance
                    closestPoint=p
                }
            }
            
        }
        
        if(closestPoint==nil) { return nil }
        return closestPoint
    }
    
    func drawVisionRequestResults(_ request: VNRequest, frame: ARFrame)
    {
        DispatchQueue.main.sync
        { [weak self] in
            guard let predictions = request.results as? [VNRecognizedObjectObservation] else { return }
            
            var obstacleUpdated : [Bool] = []
            for _ in 0..<self!.obstaclesList.count
            {
                obstacleUpdated.append(false)
            }
            
            let width = view.bounds.width
            let height = width * 16 / 9
            let offsetY = (view.bounds.height - height) / 2
            let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY - CGFloat(offset))
            let deltaTime = (Float)(DispatchTime.now().uptimeNanoseconds-(self?.lastVisionUpdate!.uptimeNanoseconds)!)/1000000000.0
            self?.lastVisionUpdate=DispatchTime.now()
            
            let points=frame.rawFeaturePoints
            for i in 0..<self!.boundingBoxViews.count {
                if i < predictions.count && predictions[i].confidence>self!.minConfidence
                {
                    let prediction = predictions[i]
                    let label = prediction.labels[0].identifier
                    let confidence = prediction.labels[0].confidence
                    let rect = prediction.boundingBox.applying(scale).applying(transform)
                    let currentPosition=SCNVector3(frame.camera.transform.columns.3.x,
                                                   frame.camera.transform.columns.3.y,
                                                   frame.camera.transform.columns.3.z)
                    let closestPoint=self!.getObstacleClosestPoint(points: points, boundingBox: rect, frame: frame)
                    
                    var distanceFromObstacle:Float!
                    
                    if((closestPoint) != nil)
                    {
                        distanceFromObstacle = self!.distance(a: closestPoint!, b: currentPosition)
                    }
                    else
                    {
                        distanceFromObstacle = 0
                    }
                    
                    let relativePosition = self!.evaluateObstacleRelativePositionOnScreen(boundingBoxCenter: CGPoint(x: rect.midX, y: rect.midY))
                    
                    var maxOverlap : Float = 0.0
                    var mostSimilar = -1
                    for j in 0..<self!.obstaclesList.count
                    {
                        let obstacle = self!.obstaclesList[j]
                        if(obstacle.intersect(otherLabel: label, otherBoundingBox: prediction.boundingBox))
                        {
                            let overlap=obstacle.evaluateOverlap(otherBoundingBox: prediction.boundingBox)
                            
                            if(overlap>maxOverlap)
                            {
                                mostSimilar=j
                                maxOverlap=overlap
                            }
                        }
                    }
                    
                    var obstacle : Obstacle!
                    
                    if(mostSimilar>=0)
                    {
                        //Allora l'ostacolo rilevato era già stato rilevato
                        print(label, "è già stato rilevato prima")
                        self!.obstaclesList[mostSimilar].updateBoundingBox(newBoundingBox: prediction.boundingBox)
                        
                        if(closestPoint != nil)
                        {
                            self!.obstaclesList[mostSimilar].evaluateSpeed(newClosestPoint: closestPoint!, deltaTime: deltaTime)
                            
                            self!.obstaclesList[mostSimilar].updateClosestPoint(closestPoint: closestPoint)
                            
                            self!.obstaclesList[mostSimilar].updateDistance(distance: distanceFromObstacle)
                        }
                        
                        self!.obstaclesList[mostSimilar].updateRelativePosition(relativePosition: relativePosition)
                        obstacle=self!.obstaclesList[mostSimilar]
                        obstacleUpdated[mostSimilar]=true
                    }
                    else
                    {
                        //L'ostacolo rilevato è nuovo
                        print(label, "è un nuovo ostacolo")
                        obstacle = Obstacle(label: label, boundingBox: prediction.boundingBox, closestPoint: closestPoint, relativePosition: relativePosition,
                            distance: distanceFromObstacle)
                        
                        if(closestPoint != nil)
                        {
                            obstacle.evaluateSpeed(newClosestPoint: closestPoint!, deltaTime: deltaTime)
                        }
                        
                        self!.obstaclesList.append(obstacle)
                        obstacleUpdated.append(true)
                        //sonifyNewObstacle(obstacle: obstacle)
                    }
                    
                    let description = obstacle.getDescription()
                    
                    let color = UIColor(red: 1, green: 0, blue: 0, alpha: 0.5)
                        self!.boundingBoxViews[i].show(frame: rect, label: description, color: color)
                    
                }
                else
                {
                    self!.boundingBoxViews[i].hide()
                }
            }
            
            for i in stride(from: self!.obstaclesList.count-1, to: -1, by: -1)
            {
                if(!obstacleUpdated[i])
                {
                    print("Removed ",obstaclesList[i].label)
                    self!.obstaclesList.remove(at: i)
                }
            }
            self?.visionUpdatePerSec+=1
        }
    }
    
    func runObjectDetectionOnCurrentFrame(frame: ARFrame)
    {
        let pixelBuffer = frame.capturedImage
        self.processing=true
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        visionQueue.async
        { [weak self] in
            do
            {
                defer {self!.processing=false}
                try handler.perform([self!.visionRequest])
            }
            catch
            {
                print(error)
            }
            self!.processing=false
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        let frame = self.arscnView.session.currentFrame
        guard (frame != nil) else {
            return
        }
        
        let nanoTime = DispatchTime.now().uptimeNanoseconds - self.begin.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        
        if(timeInterval>=1)
        {
            DispatchQueue.main.async
            { [weak self] in
                self!.infoLabel.text=String(format:"Update x sec: %d",self!.visionUpdatePerSec)
                self!.visionUpdatePerSec=0
            }
            begin=DispatchTime.now()
        }
        
        if(self.processing) { return }
        
        self.runObjectDetectionOnCurrentFrame(frame: frame!)
    }
}


