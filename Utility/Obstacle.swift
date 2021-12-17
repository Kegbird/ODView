//
//  Obstacle.swift
//  ODView
//
//  Created by Pietro Prebianca on 08/09/21.
//

import Foundation
import ARKit

class Obstacle
{
    private var minPointBoundingBox : CGPoint!
    private var maxPointBoundingBox : CGPoint!
    private var minWorldPosition : SCNVector3!
    private var maxWorldPosition : SCNVector3!
    private var predictions : [String : Float]!
    private var predictionFrequencies : [String : Int]!
    
    public init()
    {
        predictions = [:]
        minPointBoundingBox = nil
        maxPointBoundingBox = nil
        minWorldPosition = nil
        maxWorldPosition = nil
        predictions=[:]
        predictionFrequencies=[:]
    }
    
    public init(_ obstacle : Obstacle)
    {
        predictions = obstacle.predictions
        predictionFrequencies = obstacle.predictionFrequencies
        minPointBoundingBox = obstacle.minPointBoundingBox
        maxPointBoundingBox = obstacle.maxPointBoundingBox
        minWorldPosition = obstacle.minWorldPosition
        maxWorldPosition = obstacle.maxWorldPosition
    }
    
    public func resetBoundingBox()
    {
        minPointBoundingBox = nil
        maxPointBoundingBox = nil
        minWorldPosition = nil
        maxWorldPosition = nil
    }
    
    public func addNewPrediction(newPrediction : Prediction)
    {
        let classification = newPrediction.classification
        let confidence = newPrediction.confidencePercentage
        guard predictions[classification] != nil else
        {
            self.predictions[classification]=confidence
            self.predictionFrequencies[classification]=1
            return
        }
        if(confidence>predictions[classification]!)
        {
            predictions[classification]=confidence
        }
        if(confidence>Constants.MIN_PREDICTION_CONFIDENCE)
        {
            predictionFrequencies[classification]!+=1
        }
    }
    
    public func getMostFrequentPrediction() -> Prediction
    {
        var prediction : Prediction = Constants.OBSTACLE_DEFAULT_PREDICTION
        var max = 0
        
        for key in predictionFrequencies.keys
        {
            if(predictionFrequencies[key]!>max)
            {
                prediction=Prediction(classification: key, confidencePercentage: Constants.OBSTACLE_DEFAULT_CONFIDENCE)
                max=predictionFrequencies[key]!
            }
        }
        
        if(max<Constants.MIN_NUMBER_OF_PREDICTIONS)
        {
            return Constants.OBSTACLE_DEFAULT_PREDICTION
        }
        return prediction
    }
    
    public func getMostProbablePrediction() -> Prediction
    {
        var prediction : Prediction = Constants.OBSTACLE_DEFAULT_PREDICTION
        var max : Float = prediction.confidencePercentage
        for key in predictions.keys
        {
            if(max<predictions[key]!)
            {
                prediction=Prediction(classification: key, confidencePercentage: predictions[key]!)
                max=predictions[key]!
            }
        }
        return prediction
    }
    
    public func getMinPointBoundingBox() -> CGPoint
    {
        guard (minPointBoundingBox != nil) else { return CGPoint.zero }
        return minPointBoundingBox
    }
    
    public func getMaxPointBoundingBox() -> CGPoint
    {
        guard (maxPointBoundingBox != nil) else { return CGPoint.zero }
        return maxPointBoundingBox
    }
    
    public func getMinWorldPosition() -> SCNVector3
    {
        guard (minWorldPosition != nil) else { return SCNVector3Zero }
        return minWorldPosition
    }
    
    public func getMaxWorldPosition() -> SCNVector3
    {
        guard (maxWorldPosition != nil) else { return SCNVector3Zero }
        return maxWorldPosition
    }
    
    private func clampScreenPoint(screenPoint : CGPoint, viewportSize : CGSize) -> CGPoint
    {
        var clampedScreenPoint = screenPoint
        if(screenPoint.x<0)
        {
            clampedScreenPoint.x=0
        }
        else if(screenPoint.x>viewportSize.width)
        {
            clampedScreenPoint.x=viewportSize.width
        }
        
        if(screenPoint.y<0)
        {
            clampedScreenPoint.y=0
        }
        else if(screenPoint.y>viewportSize.height)
        {
            clampedScreenPoint.y=viewportSize.height
        }
        return clampedScreenPoint
    }
    
    public func updateBoundaries(frame: ARFrame, viewportSize: CGSize, worldPoint: SCNVector3)
    {
        var screenPoint = frame.camera.projectPoint(worldPoint.getSimd(), orientation: .portrait, viewportSize: viewportSize)
        screenPoint = clampScreenPoint(screenPoint: screenPoint, viewportSize: viewportSize)
        
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            minWorldPosition = worldPoint
            maxWorldPosition = worldPoint
            minPointBoundingBox = screenPoint
            maxPointBoundingBox = screenPoint
            return
        }
        
        if(worldPoint.x<minWorldPosition.x) { minWorldPosition.x = worldPoint.x }
        if(worldPoint.y<minWorldPosition.y) { minWorldPosition.y = worldPoint.y }
        if(worldPoint.z<minWorldPosition.z) { minWorldPosition.z = worldPoint.z }
        if(worldPoint.x>maxWorldPosition.x) { maxWorldPosition.x = worldPoint.x }
        if(worldPoint.y>maxWorldPosition.y) { maxWorldPosition.y = worldPoint.y }
        if(worldPoint.z>maxWorldPosition.z) { maxWorldPosition.z = worldPoint.z }
        
        if(screenPoint.x<minPointBoundingBox.x) { minPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y<minPointBoundingBox.y) { minPointBoundingBox.y = screenPoint.y }
        if(screenPoint.x>maxPointBoundingBox.x) { maxPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y>maxPointBoundingBox.y) { maxPointBoundingBox.y = screenPoint.y }
    }
    
    public func getObstacleRect() -> CGRect
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            return CGRect.zero
        }
        
        let width = maxPointBoundingBox.x - minPointBoundingBox.x
        let height = maxPointBoundingBox.y - minPointBoundingBox.y
        let minX = minPointBoundingBox.x
        let minY = minPointBoundingBox.y
        let rect = CGRect(x: minX, y: minY, width: width, height: height)
        return rect
    }
    
    public func getObstacleRectArea() -> CGFloat
    {
        let rect = getObstacleRect()
        let area = rect.width * rect.height
        return area
    }
    
    public func getWorldCornerPositions() -> [SCNVector3]
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            return []
        }
        var cornerWorldPositions : [SCNVector3] = []
        //Primo spigolo
        cornerWorldPositions.append(maxWorldPosition)
        var otherCorner = SCNVector3(x: minWorldPosition.x, y: maxWorldPosition.y, z: maxWorldPosition.z)
        //Secondo spigolo
        cornerWorldPositions.append(otherCorner)
        otherCorner.x=maxWorldPosition.x
        otherCorner.y=minWorldPosition.y
        otherCorner.z=maxWorldPosition.z
        //Terzo spigolo
        cornerWorldPositions.append(otherCorner)
        otherCorner.x=maxWorldPosition.x
        otherCorner.y=maxWorldPosition.y
        otherCorner.z=minWorldPosition.z
        //Quarto spigolo
        cornerWorldPositions.append(otherCorner)
        //Quinto spigolo
        cornerWorldPositions.append(minWorldPosition)
        otherCorner.x=maxWorldPosition.x
        otherCorner.y=minWorldPosition.y
        otherCorner.z=minWorldPosition.z
        //Sesto spigolo
        cornerWorldPositions.append(otherCorner)
        otherCorner.x=minWorldPosition.x
        otherCorner.y=maxWorldPosition.y
        otherCorner.z=minWorldPosition.z
        //Settimo spigolo
        cornerWorldPositions.append(otherCorner)
        otherCorner.x=minWorldPosition.x
        otherCorner.y=minWorldPosition.y
        otherCorner.z=maxWorldPosition.z
        //Ottavo spigolo
        cornerWorldPositions.append(otherCorner)
        return cornerWorldPositions
    }
    
    public func areIntersected(other : Obstacle) -> Bool
    {
        if((maxWorldPosition.x>=other.minWorldPosition.x &&
           minWorldPosition.x<=other.maxWorldPosition.x &&
           maxWorldPosition.y>=other.minWorldPosition.y &&
           minWorldPosition.y<=other.maxWorldPosition.y &&
           maxWorldPosition.z>=other.minWorldPosition.z &&
           minWorldPosition.z<=other.maxWorldPosition.z) ||
          (other.maxWorldPosition.x>=minWorldPosition.x &&
           other.minWorldPosition.x<=maxWorldPosition.x &&
           other.maxWorldPosition.y>=minWorldPosition.y &&
           other.minWorldPosition.y<=maxWorldPosition.y &&
           other.maxWorldPosition.z>=minWorldPosition.z &&
           other.minWorldPosition.z<=maxWorldPosition.z))
        {
            return true
        }
        return false
    }
    
    public func getDistanceWithOtherObstacle(other : Obstacle) -> Float
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            return 0
        }
        
        if(areIntersected(other: other))
        { return 0 }
        
        let minMinDistance = SCNVector3.distanceBetween(minWorldPosition, other.minWorldPosition)
        let maxMaxDistance = SCNVector3.distanceBetween(maxWorldPosition, other.maxWorldPosition)
        let minMaxDistance = SCNVector3.distanceBetween(minWorldPosition, other.maxWorldPosition)
        let maxMinDistance = SCNVector3.distanceBetween(maxWorldPosition, other.minWorldPosition)
        let distances = [minMinDistance, maxMaxDistance, minMaxDistance, maxMinDistance]
        return distances.min()!
    }
    
    static func == (lhs: Obstacle, rhs: Obstacle) -> Bool {
        return
            lhs.getDescription()==rhs.getDescription()
    }
    
    public func mergeWithOther(other : Obstacle)
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            minWorldPosition = other.minWorldPosition
            maxWorldPosition = other.maxWorldPosition
            minPointBoundingBox = other.minPointBoundingBox
            maxPointBoundingBox = other.maxPointBoundingBox
            return
        }
        //Min world position
        if(other.minWorldPosition.x<minWorldPosition.x)
        {
            minWorldPosition.x = other.minWorldPosition.x
        }
        if(other.minWorldPosition.y<minWorldPosition.y)
        {
            minWorldPosition.y = other.minWorldPosition.y
        }
        if(other.minWorldPosition.z<minWorldPosition.z)
        {
            minWorldPosition.z = other.minWorldPosition.z
        }
        //Max world position
        if(other.maxWorldPosition.x>maxWorldPosition.x)
        {
            maxWorldPosition.x = other.maxWorldPosition.x
        }
        if(other.maxWorldPosition.y>maxWorldPosition.y)
        {
            maxWorldPosition.y = other.maxWorldPosition.y
        }
        if(other.maxWorldPosition.z>maxWorldPosition.z)
        {
            maxWorldPosition.z = other.maxWorldPosition.z
        }
        //Min bounding box
        if(other.minPointBoundingBox.x<minPointBoundingBox.x)
        {
            minPointBoundingBox.x=other.minPointBoundingBox.x
        }
        if(other.minPointBoundingBox.y<minPointBoundingBox.y)
        {
            minPointBoundingBox.y=other.minPointBoundingBox.y
        }
        //Max bounding box
        if(other.maxPointBoundingBox.x>maxPointBoundingBox.x)
        {
            maxPointBoundingBox.x=other.maxPointBoundingBox.x
        }
        if(other.maxPointBoundingBox.y>maxPointBoundingBox.y)
        {
            maxPointBoundingBox.y=other.maxPointBoundingBox.y
        }
    }
    
    public func getDescription() -> String
    {
        var description : String = ""
        
        description = "Obstacle BB:\n"
        description += String(format: "Min: %f, %f\n", minPointBoundingBox.x, minPointBoundingBox.y)
        description += String(format: "Max: %f, %f\n", maxPointBoundingBox.x, maxPointBoundingBox.y)
        description += "World pos:\n"
        description += String(format: "Min: %f, %f, %f\n", minWorldPosition.x, minWorldPosition.y, minWorldPosition.z)
        description += String(format: "Max: %f, %f, %f\n", maxWorldPosition.x, maxWorldPosition.y, maxWorldPosition.z)
        return description
    }
}
