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
    public var label : String
    private var boundingBox : CGRect
    private var closestPoint : SCNVector3?
    private var relativePosition : String
    private var distance : Float?
    private var speed : Float?
    
    init(label: String, boundingBox: CGRect, closestPoint: SCNVector3?, relativePosition: String, distance: Float?) {
        self.label=label
        self.boundingBox=boundingBox
        self.closestPoint=closestPoint
        self.relativePosition=relativePosition
        self.distance=distance
    }
    
    public func intersect(otherLabel: String, otherBoundingBox : CGRect) -> Bool
    {
        if(self.label==otherLabel)
        {
            return self.boundingBox.intersects(otherBoundingBox)
        }
        return false
    }
    
    public func evaluateOverlap(otherBoundingBox : CGRect) -> Float
    {
        let overlappingArea=self.boundingBox.intersection(otherBoundingBox)
        return Float(overlappingArea.width*overlappingArea.height)
    }
    
    public func updateDistance(distance : Float)
    {
        self.distance=distance
    }
    
    public func updateBoundingBox(newBoundingBox : CGRect)
    {
        self.boundingBox=newBoundingBox
    }
    
    public func updateClosestPoint(closestPoint : SCNVector3?)
    {
        self.closestPoint=closestPoint
    }
    
    public func updateRelativePosition(relativePosition : String)
    {
        self.relativePosition=relativePosition
    }
    
    public func evaluateSpeed(newClosestPoint : SCNVector3, deltaTime: Float)
    {
        if(deltaTime==0.0 || self.closestPoint==nil)
        {
            self.speed=nil
            return
        }
        let velocityVector = SCNVector3(newClosestPoint.x-closestPoint!.x,
                                        newClosestPoint.y-closestPoint!.x,
                                        newClosestPoint.z-closestPoint!.z)
        let velocityMagnitude = sqrt(pow(velocityVector.x, 2)+pow(velocityVector.y, 2)+pow(velocityVector.z, 2))
        self.speed=velocityMagnitude/deltaTime
    }
    
    public func getDescription() -> String
    {
        return String(format:"%@ %@ %f %f",label, relativePosition, distance ?? 0, speed ?? 0)
    }
}
