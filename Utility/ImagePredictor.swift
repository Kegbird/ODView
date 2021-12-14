import Vision
import UIKit

class ImagePredictor
{
    static func createImageClassifier() -> VNCoreMLModel
    {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        
        let imageClassifierWrapper = try? ImageClassifier(configuration: config)

        guard let imageClassifier = imageClassifierWrapper else {
            fatalError("App failed to create an image classifier model instance.")
        }

        let imageClassifierModel = imageClassifier.model

        guard let imageClassifierVisionModel = try? VNCoreMLModel(for: imageClassifierModel) else {
            fatalError("App failed to create a `VNCoreMLModel` instance.")
        }
        return imageClassifierVisionModel
    }

    private static let imageClassifier = createImageClassifier()

    typealias ImagePredictionHandler = (_ prediction: Prediction, _ index: Int) -> Void

    private var predictionHandlers = [VNRequest: (ImagePredictionHandler, Int)]()

    private func createImageClassificationRequest(regionOfInterest : CGRect) -> VNImageBasedRequest
    {
        let imageClassificationRequest = VNCoreMLRequest(model: ImagePredictor.imageClassifier, completionHandler: visionRequestHandler)
        imageClassificationRequest.imageCropAndScaleOption = .scaleFit
        imageClassificationRequest.regionOfInterest = regionOfInterest
        return imageClassificationRequest
    }
    
    func classifyNewObstacles(cgImage: CGImage?, for obstacles : inout [Obstacle])
    {
        guard cgImage != nil else
        {
            return
        }
        
        var predictions : [Prediction?] = Array.init(repeating: nil, count: obstacles.count)
        var requests : [VNRequest] = []
        var i = 0
        for obstacle in obstacles
        {
            if(obstacle.getObstaclePixelRectArea()<Constants.MIN_BOUNDING_BOX_AREA)
            {
                continue
            }
            let completionHandler = {
            (bestPrediction : Prediction, index : Int) -> Void in
                predictions[index]=bestPrediction
            }
            let pointRegionOfInterest = obstacle.getObstaclePointRect()
            var regionOfInterest = VNNormalizedRectForImageRect(pointRegionOfInterest, cgImage!.width, cgImage!.height)
            var minY = 1-regionOfInterest.minY-regionOfInterest.height
            if(minY<=0) { minY = 0 }
            var height = regionOfInterest.height
            if(height+minY>=1) { height=1-minY }
            regionOfInterest = CGRect(x: regionOfInterest.minX, y: minY, width: regionOfInterest.width, height: height)
            let request = createImageClassificationRequest(regionOfInterest: regionOfInterest)
            predictionHandlers[request] = (completionHandler, i)
            requests.append(request)
            i=i+1
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage!)
        do
        {
            try handler.perform(requests)
            i = 0
            for obstacle in obstacles
            {
                if(predictions[i] != nil)
                {
                    obstacle.addNewPrediction(newPrediction: predictions[i]!)
                }
                i=i+1
            }
        }
        catch
        {
            print(error)
            return
        }
    }

    private func visionRequestHandler(_ request: VNRequest, error: Error?)
    {
        if(predictionHandlers[request]==nil) { return }
        
        let predictionHandler = predictionHandlers[request]!.0
        let index = predictionHandlers[request]!.1
        predictionHandlers.removeValue(forKey: request)

        var predictions: [Prediction]? = nil

        if let error = error {
            print("Vision image classification error...\n\n\(error.localizedDescription)")
            return
        }

        if request.results == nil {
            print("Vision request had no results.")
            return
        }

        guard let observations = request.results as? [VNClassificationObservation] else
        {
            print("VNRequest produced the wrong result type: \(type(of: request.results)).")
            return
        }

        predictions = observations.map
        {
            observation in
            Prediction(classification: observation.identifier,
                       confidencePercentage: observation.confidence)
        }
        
        predictions = predictions?.sorted
        {
            $0.confidencePercentage>$1.confidencePercentage
        }
        
        if(predictions != nil && predictions!.count>0)
        {
            predictionHandler(predictions!.first!, index)
        }
    }
}
