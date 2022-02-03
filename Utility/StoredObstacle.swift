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
    //Lista delle predizioni memorizzate per ogni ostacolo (label, peso, timestamp)
    private var predictionsTimeline : [(String, Float, Double)]
    
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
        obstacle.closestWorldPosition = closestWorldPosition
        obstacle.distanceFromCamera = distanceFromCamera
        obstacle.predictionsTimeline = predictionsTimeline
        return obstacle
    }
    
    public func addNewPrediction(label : String, weight : Float)
    {
        let currentTime = Double(DispatchTime.now().uptimeNanoseconds) / 1000000000.0
        predictionsTimeline.append((label, weight, currentTime))
    }
    
    public func getBestPrediction() -> String
    {
        if(predictionsTimeline.count==0)
        {
            return Constants.OBSTACLE_DEFAULT_PREDICTION.label
        }
        
        var oldestPrediction = predictionsTimeline[0].2
        let currentTime = Double(DispatchTime.now().uptimeNanoseconds) / 1000000000.0
        
        var weights : [String : Float] = [:]
        
        for i in stride(from: predictionsTimeline.count-1, to: 0, by: -1)
        {
            let label = predictionsTimeline[i].0
            let weight = predictionsTimeline[i].1
            let predictionTime = predictionsTimeline[i].2
            
            if(predictionTime<oldestPrediction)
            {
                oldestPrediction=predictionTime
            }
            let interval = currentTime-predictionTime
            
            if(interval<Constants.PREDICTION_WINDOWS)
            {
                if(weights[label] != nil)
                {
                    weights[label]=weights[label]!+weight
                }
                else
                {
                    weights[label]=weight
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
        
        if(maxDifference>Constants.CONFIDENCE_MIN_DELTA)
        {
            return bestPrediction
        }
        return Constants.OBSTACLE_DEFAULT_PREDICTION.label
    }
    
    public func getPredictionsTimeline() -> [(String, Float, Double)]
    {
        return predictionsTimeline
    }
    
    public func setPredictionTimeline(predictionsTimeline : [(String, Float, Double)])
    {
        self.predictionsTimeline=predictionsTimeline
    }
    
    public func mergeWithOther(other : StoredObstacle)
    {
        for prediction in other.predictionsTimeline
        {
            predictionsTimeline.append(prediction)
        }
        super.mergeWithOther(other: other)
    }
}
