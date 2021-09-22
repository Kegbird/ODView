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
    private var id : UInt64
    private var label : String
    private var currentClosestPoint : SCNVector3
    private var currentClosestPointId : UInt64
    private var velocity : Float
    
    init(id: UInt64, label: String, currentClosestPoint: SCNVector3, currentClosestPointId: UInt64) {
        self.id=id
        self.label=label
        self.currentClosestPoint=currentClosestPoint
        self.currentClosestPointId=currentClosestPointId
        self.velocity=0.0
    }
    
    public func getIdentifier() -> UInt64
    {
        return self.id
    }
    
    private func updateCurrentPosition(newClosestPoint : SCNVector3)
    {
        self.currentClosestPoint=newClosestPoint
    }
    
    func calculateVelocity(newCLosestPoint : SCNVector3, deltaTime: Float) -> Float
    {
        let oldClosestPoint=self.currentClosestPoint
        updateCurrentPosition(newClosestPoint: newCLosestPoint)
        
        if(deltaTime==0.0) { return -1.0 }
        
        let velocityVector = SCNVector3(self.currentClosestPoint.x-oldClosestPoint.x,
                                            self.currentClosestPoint.y-oldClosestPoint.x,
                                            self.currentClosestPoint.z-oldClosestPoint.z)
        
        let velocityMagnitude = sqrt(pow(velocityVector.x, 2)+pow(velocityVector.y, 2)+pow(velocityVector.z, 2))
        return velocityMagnitude/deltaTime
    }
}
