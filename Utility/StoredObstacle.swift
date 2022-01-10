//
//  Obstacle.swift
//  ODView
//
//  Created by Pietro Prebianca on 08/09/21.
//

import Foundation
import ARKit

class StoredObstacle : Obstacle
{
    private var predictionsTimeline : [(Prediction, Double)]
    
    public override init()
    {
        predictionsTimeline=[]
    }
    
    public override func copy() -> StoredObstacle
    {
        let obstacle = StoredObstacle()
        obstacle.minPointBoundingBox = minPointBoundingBox
        obstacle.maxPointBoundingBox = maxPointBoundingBox
        obstacle.minWorldPosition = minWorldPosition
        obstacle.maxWorldPosition = maxWorldPosition
        obstacle.pointNumber = pointNumber
        obstacle.predictionsTimeline = predictionsTimeline
        return obstacle
    }
    
    public func addNewPrediction(newPrediction : Prediction)
    {
        let currentTime = Double(DispatchTime.now().uptimeNanoseconds) / 1000000000.0
        predictionsTimeline.append((newPrediction, currentTime))
    }
    
    public func getMostFrequentPrediction() -> String
    {
        if(predictionsTimeline.count==0)
        {
            return Constants.OBSTACLE_DEFAULT_PREDICTION.label
        }
        
        var oldestPrediction = predictionsTimeline[0].1
        let currentTime = Double(DispatchTime.now().uptimeNanoseconds) / 1000000000.0
        
        var weights : [String : Float] = [:]
        
        for i in stride(from: predictionsTimeline.count-1, to: 0, by: -1)
        {
            let prediction = predictionsTimeline[i].0.label
            let predictionTime = predictionsTimeline[i].1
            if(predictionTime<oldestPrediction)
            {
                oldestPrediction=predictionTime
            }
            let interval = currentTime-predictionTime
            let confidence = predictionsTimeline[i].0.confidence*100.0
            if(interval<Constants.PREDICTION_WINDOWS)
            {
                if(weights[prediction] != nil)
                {
                    weights[prediction]=weights[prediction]!+confidence
                }
                else
                {
                    weights[prediction]=confidence
                }
            }
            else
            {
                predictionsTimeline.remove(at: i)
            }
        }
        
        if(currentTime-oldestPrediction<Constants.PREDICTION_WINDOWS)
        {
            return Constants.OBSTACLE_DEFAULT_PREDICTION.label
        }
        
        var debugOutput = ""
        var bestPrediction = Constants.OBSTACLE_DEFAULT_PREDICTION.label
        var max : Float = 0.0
        var maxDifference : Float = 0.0
        
        for key in weights.keys
        {
            if(weights[key]!>max)
            {
                maxDifference=weights[key]!-max
                bestPrediction = key
                max=weights[key]!
            }
        }
        
        debugOutput="Predictions:"+"\n"
        
        var labels = Array.init(weights.keys)
        labels.sort()
        
        for label in labels
        {
            debugOutput=debugOutput+String("\(label):\(round(weights[label]!))%\n")
        }
        
        debugOutput=debugOutput+"\n"+"Difference:\(round(maxDifference))\n"
        
        if(maxDifference>Constants.CONFIDENCE_MIN_DELTA)
        {
            return bestPrediction
        }
        return Constants.OBSTACLE_DEFAULT_PREDICTION.label
    }
    
    public func getPredictionsTimeline() -> [(Prediction, Double)]
    {
        return predictionsTimeline
    }
    
    public func setPredictionTimeline(predictionsTimeline : [(Prediction, Double)])
    {
        self.predictionsTimeline=predictionsTimeline
    }
    
    public func mergeWithOther(other : StoredObstacle)
    {
        pointNumber=pointNumber+other.pointNumber
        
        for prediction in other.predictionsTimeline
        {
            predictionsTimeline.append(prediction)
        }
        
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
}
