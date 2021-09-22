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
    
    private let minConfidence: Float = 0.80
    
    var bufferSize: CGSize = .zero
    
    @IBOutlet weak var arscnView: ARSCNView!
    
    private var processing : Bool = false
    
    private var lastCalculus : DispatchTime!
    
    let maxBoundingBoxViews = 10
    
    let screenSubdivisionFactor : Float = 1.0/3.0
    
    var boundingBoxViews = [BoundingBoxView]()
    
    var colors: [String: UIColor] = [:]
    
    let coreMLModel = MobileNetV2_SSDLite()
    
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
    
    private let queue = DispatchQueue.init(label: "vision-queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAR()
        setupBoundingBoxViews()
        visionModel.inputImageFeatureName="image"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        arscnView.session.run(configuration)
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
        arscnView.showsStatistics=true
        arscnView.debugOptions=[ARSCNDebugOptions.showFeaturePoints]
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
        // Assign random colors to the classes.
        for label in labels {
            colors[label] = UIColor.red
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
        {
            guard let predictions = request.results as? [VNRecognizedObjectObservation] else { return }
            
            let points=frame.rawFeaturePoints
            
            for i in 0..<self.boundingBoxViews.count {
                if i < predictions.count
                {
                    let prediction = predictions[i]
                    let width = view.bounds.width
                    let height = width * 16 / 9
                    let offsetY = (view.bounds.height - height) / 2
                    let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
                    let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
                    let rect = prediction.boundingBox.applying(scale).applying(transform)
                    
                    let currentPosition=SCNVector3(frame.camera.transform.columns.3.x,
                                                   frame.camera.transform.columns.3.y,
                                                   frame.camera.transform.columns.3.z)
                    
                    let closestPoint=self.getObstacleClosestPoint(points: points, boundingBox: rect, frame: frame)
                    
                    var distanceFromObstacle:Float!
                    
                    if((closestPoint) != nil)
                    {
                        distanceFromObstacle = self.distance(a: closestPoint!, b: currentPosition)
                    }
                    else
                    {
                        distanceFromObstacle = 0
                    }
                    
                    let relativePosition = self.evaluateObstacleRelativePositionOnScreen(boundingBoxCenter: CGPoint(x: rect.midX, y: rect.midY))
                    
                    let bestClass = prediction.labels[0].identifier
                    let confidence = prediction.labels[0].confidence
                    
                    if(confidence<self.minConfidence)
                    {
                        self.boundingBoxViews[i].hide()
                    }
                    else
                    {
                        let label = String(format: "%@ Confidence:%.1f \nDistance:%.3f \n Position:%@", bestClass.uppercased(), confidence * 100, distanceFromObstacle, relativePosition)
                        let color = self.colors[bestClass] ?? UIColor.red
                        self.boundingBoxViews[i].show(frame: rect, label: label, color: color)
            
                    }
                }
                else
                {
                    self.boundingBoxViews[i].hide()
                }
            }
        }
    }
    
    func runObjectDetectionOnCurrentFrame(frame: ARFrame)
    {
        let pixelBuffer = frame.capturedImage
        self.processing=true
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        queue.async
        {
            do
            {
                defer {self.processing=false}
                try handler.perform([self.visionRequest])
            }
            catch
            {
                print(error)
            }
            
            self.processing=false
            let end=DispatchTime.now()
            let nanoTime = end.uptimeNanoseconds - self.lastCalculus.uptimeNanoseconds
            let timeInterval = Double(nanoTime) / 1_000_000_000
            print("Time vision computation:",timeInterval,"s")
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        let frame = self.arscnView.session.currentFrame
        guard (frame != nil) else {
            return
        }
        if(self.processing)
        {
            return
        }
        lastCalculus=DispatchTime.now()
        self.runObjectDetectionOnCurrentFrame(frame: frame!)
    }
}


