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
        
        let frame=CGRect(x:arscnView.bounds.width/3, y:0, width: arscnView.bounds.width/3, height: arscnView.bounds.height)
        let path = UIBezierPath(rect: frame)
        let middle=CAShapeLayer()
        middle.path=path.cgPath
        middle.fillColor = UIColor.clear.cgColor
        middle.strokeColor = UIColor.green.cgColor
        middle.lineWidth = 2
        arscnView.layer.addSublayer(middle)
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
    
    func deleteAllAnchors()
    {
        //arscnView.scene.rootNode.enumerateChildNodes({(node, stop) in node.removeFromParentNode()})
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
                /*let sphere = SCNNode(geometry: SCNSphere(radius: 0.001))
                sphere.geometry?.firstMaterial?.diffuse.contents = UIColor.purple
                sphere.position=SCNVector3(point)
                self.arscnView.scene.rootNode.addChildNode(sphere)*/
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
            
            self.deleteAllAnchors()
            
            let points=frame.rawFeaturePoints
            
            for i in 0..<self.boundingBoxViews.count {
                if i < predictions.count
                {
                    let prediction = predictions[i]
                    
                    /*
                     The predicted bounding box is in normalized image coordinates, with
                     the origin in the lower-left corner.
                     
                     Scale the bounding box to the coordinate system of the video preview,
                     which is as wide as the screen and has a 16:9 aspect ratio. The video
                     preview also may be letterboxed at the top and bottom.
                     
                     Based on code from https://github.com/Willjay90/AppleFaceDetection
                     
                     NOTE: If you use a different .imageCropAndScaleOption, or a different
                     video resolution, then you also need to change the math here!
                     */
                    
                    // Get the affine transform to convert between normalized image coordinates and view coordinates
                    /*let fromCameraImageToViewTransform = frame.displayTransform(for: .portrait, viewportSize: self.arscnView.currentViewport.size)
                     // The observation's bounding box in normalized image coordinates
                     let boundingBox = prediction.boundingBox
                     // Transform the latter into normalized view coordinates
                     let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
                     // The affine transform for view coordinates
                     let t = CGAffineTransform(scaleX: self.arscnView.currentViewport.size.width, y: self.arscnView.currentViewport.size.height)
                     // Scale up to view coordinates
                     let rect = viewNormalizedBoundingBox.applying(t)*/
                    
                    let width = self.arscnView.bounds.width
                    let height = self.arscnView.bounds.height
                    
                    //Bounding box origin flip
                    var rect=prediction.boundingBox
                    
                    let viewTransform = frame.displayTransform(for: .portrait, viewportSize: self.arscnView.bounds.size)
                    
                    rect = rect.applying(viewTransform)
                    
                    rect = rect.applying(CGAffineTransform(scaleX: width, y: height))
                    
                    rect = CGRect(x: self.arscnView.bounds.width-rect.origin.x-rect.width, y: rect.origin.y, width: rect.width, height: rect.height)
                    
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
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
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
            //let end=DispatchTime.now()
            //let nanoTime = end.uptimeNanoseconds - self.lastCalculus.uptimeNanoseconds
            //let timeInterval = Double(nanoTime) / 1_000_000_000
            //print("Time vision computation:",timeInterval,"s")
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


