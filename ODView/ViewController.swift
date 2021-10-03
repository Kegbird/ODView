import UIKit
import ARKit
import AVFoundation
import Vision

class ViewController: UIViewController, ARSCNViewDelegate
{
    @IBOutlet weak var arscnView: ARSCNView!
    
    @IBOutlet weak var infoLabel : UILabel!
    
    private var processing : Bool = false
    
    private var begin : DispatchTime!
    
    let screenSubdivisionFactor : Float = 1.0/3.0
    
    var obstacles = [Obstacle]()
    
    var lastVisionUpdate : DispatchTime?
    
    var visionUpdatePerSec = 0
    
    let coreMLModel = MobileNetV2_SSDLite()
    
    private let visionQueue = DispatchQueue.init(label: "visionQueue", qos: .userInitiated)
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arscnView.delegate=self
        visionModel.inputImageFeatureName="image"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        arscnView.debugOptions=[SCNDebugOptions.showFeaturePoints]
        arscnView.session.run(configuration)
        begin=DispatchTime.now()
        self.setUpConstants()
        self.lastVisionUpdate=DispatchTime.now()
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arscnView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func setUpConstants()
    {
        Constants.WIDTH=self.view.bounds.width
        Constants.HEIGHT=Constants.WIDTH*16/9
        Constants.OFFSET_Y = (self.view.bounds.height - Constants.HEIGHT) / 2
        Constants.SCALE = CGAffineTransform.identity.scaledBy(x: Constants.WIDTH, y: Constants.HEIGHT)
        Constants.TRANSFORM = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -Constants.HEIGHT - Constants.OFFSET_Y - CGFloat(Constants.OFFSET))
    }
    
    func drawVisionRequestResults(_ request: VNRequest, frame: ARFrame)
    {
        guard let predictions = request.results as? [VNRecognizedObjectObservation] else { return }
        
        DispatchQueue.main.async
        {
            let points=frame.rawFeaturePoints
            var obstacleUpdated : [Bool] = []
            for _ in 0..<self.obstacles.count
            {
                obstacleUpdated.append(false)
            }
            
            let deltaTime = (Float)(DispatchTime.now().uptimeNanoseconds-(self.lastVisionUpdate!.uptimeNanoseconds))/1000000000.0
            self.lastVisionUpdate=DispatchTime.now()
            
            for i in 0..<predictions.count
            {
                let prediction = predictions[i]
                let label=prediction.labels[0].identifier
                let confidence=prediction.labels[0].confidence
                if(confidence>Constants.MIN_CONFIDENCE_PREDICTION)
                {
                    let adjustedBoundingBox = prediction.boundingBox.applying(Constants.SCALE).applying(Constants.TRANSFORM)
                    var maxOverlap : Float = 0.0
                    var mostSimilar = -1
                    for j in 0..<self.obstacles.count
                    {
                        let obstacle = self.obstacles[j]
                        if(obstacle.intersect(otherLabel: label, otherBoundingBox: adjustedBoundingBox))
                        {
                            let overlap=obstacle.evaluateOverlap(otherBoundingBox: adjustedBoundingBox)
                            if(overlap>maxOverlap)
                            {
                                mostSimilar=j
                                maxOverlap=overlap
                            }
                        }
                    }
                    
                    if(mostSimilar>=0)
                    {
                        print(label, "already known")
                        obstacleUpdated[mostSimilar]=true
                        self.obstacles[mostSimilar].updateParameters(boundingBox: adjustedBoundingBox, points: points, frame: frame, view: self.arscnView, viewport: self.arscnView.currentViewport, deltaTime: deltaTime)
                        continue
                    }
                    print(label, "is new")
                    obstacleUpdated.append(true)
                    let obstacle = Obstacle(label: label,
                                            boundingBox: adjustedBoundingBox)
                    obstacle.evaluateRelativePosition(view: self.arscnView)
                    obstacle.evaluateClosestPointAndDistance(points: points, frame: frame, viewport: self.arscnView.currentViewport)
                    obstacle.addBoundingBoxViewToLayer(parent:self.arscnView.layer)
                    obstacle.showBoundingBoxView()
                    self.obstacles.append(obstacle)
                }
            }
            
            for i in stride(from: self.obstacles.count-1, to: -1, by: -1)
            {
                if(!obstacleUpdated[i])
                {
                    print("Removed ", self.obstacles[i].label)
                    self.obstacles[i].removeObstacleBoundingBox()
                    self.obstacles.remove(at: i)
                }
            }
            self.visionUpdatePerSec+=1
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
