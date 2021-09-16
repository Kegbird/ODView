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
    
    private let minConfidence: Float = 0.90
    
    private var detectionOverlay: CALayer! = nil
    
    var bufferSize: CGSize = .zero
    
    @IBOutlet weak var arscnView: ARSCNView!
    
    private var requests = [VNRequest]()
    
    private var processing : Bool = false
    
    private var obstaacleList = [SCNNode]()
    
    private var lastCalculus : DispatchTime!
    
    private let queue = DispatchQueue.init(label: "vision-queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var stop : Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAR()
        setupVision()
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
        setupLayers()
    }
    
    func setupVision(){
        // Setup Vision parts
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3Int8LUT", withExtension: "mlmodelc") else {
            return
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
    }
    
    func setupLayers() {
        bufferSize.width = CGFloat(arscnView.bounds.width)
        bufferSize.height = CGFloat(arscnView.bounds.height)
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: arscnView.layer.bounds.midX, y: arscnView.layer.bounds.midY)
        arscnView.layer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = arscnView.bounds
        var scale: CGFloat
        
        let yScale: CGFloat = bounds.size.width / bufferSize.height
        let xScale: CGFloat = bounds.size.height / bufferSize.width
        
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: xScale, y: -yScale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.name = "Found Object"
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }

    func deleteAllAnchors()
    {
       /* let limit=arscnView.scene.rootNode.childNodes.count-1
        for i in 0...limit
        {
            arscnView.scene.rootNode.childNodes[arscnView.scene.rootNode.childNodes.count-1-i].removeFromParentNode()
        }*/
        
        arscnView.scene.rootNode.enumerateChildNodes({(node, stop) in node.removeFromParentNode()})

        //arscnView.scene.rootNode.childNodes.remove(at: 0)
        /*if(frame.anchors.count>0)
        {
            for i in frame.anchors.count-1...0
            {
                let anchor = frame.anchors[i]
                self.arscnView.session.remove(anchor: anchor)
            }
        }*/
    }
    
    func distance(a: SCNVector3, b: SCNVector3) -> Float
    {
        return sqrt(pow(a.x-b.x, 2)+pow(a.y-b.y, 2)+pow(a.z+b.z, 2))
    }
    
    func calculateCentroidOfBoundingBox(points: ARPointCloud, boundingBox: CGRect, camera: ARCamera) -> SCNVector3!
    {
        var numeberOfPoints = 0
        var centroid = SCNVector3(0, 0, 0)
        //print("Bounding box:", boundingBox.minX, boundingBox.minY, boundingBox.maxX, boundingBox.maxY)
        for point in points.points
        {
            let screenPoint=camera.projectPoint(point, orientation: UIInterfaceOrientation.portrait, viewportSize: self.arscnView.currentViewport.size)
            if(boundingBox.contains(screenPoint))
            {
                //print("Point Screen:",screenPoint.x, screenPoint.y)
                //print("Point world:", point.x, point.y, point.z)
                centroid.x=centroid.x+point.x
                centroid.y=centroid.y+point.y
                centroid.z=centroid.z+point.z
                numeberOfPoints=numeberOfPoints+1
                
                /*let sphere = SCNNode(geometry: SCNSphere(radius: 0.001))
                sphere.geometry?.firstMaterial?.diffuse.contents = UIColor.purple
                sphere.position=SCNVector3(point)
                self.arscnView.scene.rootNode.addChildNode(sphere)*/
            }
        }
        if(numeberOfPoints>0)
        {
            centroid.x=centroid.x/Float(numeberOfPoints)
            centroid.y=centroid.y/Float(numeberOfPoints)
            centroid.z=centroid.z/Float(numeberOfPoints)
            //print("centroid:", centroid.x, centroid.y, centroid.z)
            return centroid
        }
        return nil
    }
    
    func drawVisionRequestResults(_ results: [Any])
    {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        self.detectionOverlay.sublayers = nil
        self.deleteAllAnchors()
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
                
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
                
            if(topLabelObservation.confidence<self.minConfidence)
            {
                continue
            }
                
            
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(self.arscnView.bounds.width), Int(self.arscnView.bounds.height))
                
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                                identifier: topLabelObservation.identifier,
                                                                confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            self.detectionOverlay.addSublayer(shapeLayer)
    
            guard let points=self.arscnView.session.currentFrame?.rawFeaturePoints else { continue }
            
            let viewTransform = arscnView.session.currentFrame?.displayTransform(for: .portrait, viewportSize: arscnView.currentViewport.size)
            
            var transformedBoundingBox = objectObservation.boundingBox
            
            transformedBoundingBox = transformedBoundingBox.applying(viewTransform!)
            
            transformedBoundingBox = transformedBoundingBox.applying(CGAffineTransform(scaleX: arscnView.currentViewport.size.width, y: arscnView.currentViewport.size.height))
            
            guard let centroid = calculateCentroidOfBoundingBox(points: points, boundingBox: transformedBoundingBox, camera: self.arscnView.session.currentFrame!.camera) else { continue }
            
            
            let sphereNode = SCNNode(geometry: SCNSphere(radius: 0.01))
            sphereNode.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            sphereNode.position=centroid
            self.arscnView.scene.rootNode.addChildNode(sphereNode)
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
    
    func runObjectDetectionOnCurrentFrame(frame: ARFrame)
    {
        let pixelBuffer = frame.capturedImage
        self.processing=true
        queue.async
        {
            let exifOrientation = self.exifOrientationFromDeviceOrientation()
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
            do
            {
                defer {self.processing=false}
                try imageRequestHandler.perform(self.requests)
            }
            catch
            {
                print(error)
            }
            
            /*let end=DispatchTime.now()
            let nanoTime = end.uptimeNanoseconds - self.lastCalculus.uptimeNanoseconds
            let timeInterval = Double(nanoTime) / 1_000_000_000
            print("Time vision computation:",timeInterval,"s")*/
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        let frame = self.arscnView.session.currentFrame
        guard (frame != nil) else {
            return
        }
        if(processing)
        {
            return
        }
        lastCalculus=DispatchTime.now()
        self.runObjectDetectionOnCurrentFrame(frame: frame!)
    }
}

