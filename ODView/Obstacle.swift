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
    private var distanceFromUser : Float
    private var speed : Float?
    private var boundingBoxView : BoundingBoxView
    
    init(label: String,
         boundingBox: CGRect)
    {
        self.label=label
        self.boundingBox=boundingBox
        self.relativePosition=""
        self.distanceFromUser=0
        self.boundingBoxView=BoundingBoxView()
    }
    
    public func addBoundingBoxViewToLayer(parent : CALayer)
    {
        self.boundingBoxView.addToLayer(parent)
    }
    
    public func updateBoundingBox(boundingBox: CGRect)
    {
        self.boundingBox=boundingBox
        self.boundingBoxView.updateShape(frame: boundingBox, label: getDescription())
    }
    
    public func showBoundingBoxView()
    {
        self.boundingBoxView.show(frame: boundingBox, label: getDescription(), color: UIColor.red)
    }
    
    public func removeObstacleBoundingBox()
    {
        self.boundingBoxView.removeFromLayer()
    }
    
    public func evaluateRelativePosition(view: UIView)
    {
        let boundingBoxCenter = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        
        if(boundingBoxCenter.x<view.bounds.width/3)
        {
            self.relativePosition="Left"
        }
        else if(view.bounds.width/3<=boundingBoxCenter.x && boundingBoxCenter.x<2*view.bounds.width/3)
        {
            self.relativePosition="Middle"
        }
        else
        {
            self.relativePosition="Right"
        }
    }
    
    public func evaluateClosestPointAndDistance(points: ARPointCloud?, frame: ARFrame, viewport : CGRect)
    {
        if points == nil
        {
            self.closestPoint=nil
            return
        }
        
        var minDistance : Float = 100.0
        let currentCameraPosition = SCNVector3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
        var closestPoint : SCNVector3!
        
        print(points!.points.count)
        for i in 0..<points!.points.count
        {
            let screenPoint=frame.camera.projectPoint(points!.points[i], orientation: UIInterfaceOrientation.portrait, viewportSize: viewport.size)
            
            if(boundingBox.contains(screenPoint))
            {
                let point = SCNVector3(points!.points[i].x, points!.points[i].y, points!.points[i].z)
                let distance=SCNVector3.distance(startPoint: point, endPoint: currentCameraPosition)
                if(minDistance>distance)
                {
                    minDistance=distance
                    closestPoint=point
                }
            }
        }
        
        if closestPoint==nil
        {
            self.closestPoint=nil
            return
        }
        self.closestPoint=closestPoint
        self.distanceFromUser=SCNVector3.distance(startPoint: self.closestPoint!, endPoint: currentCameraPosition)
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
    
    public func updateParameters(boundingBox: CGRect, points: ARPointCloud?, frame: ARFrame, view: UIView, viewport: CGRect, deltaTime: Float)
    {
        self.boundingBox=boundingBox
        self.evaluateRelativePosition(view: view)
        let oldClosestPoint = self.closestPoint
        self.evaluateClosestPointAndDistance(points: points, frame: frame, viewport: viewport)
        
        if(oldClosestPoint == nil || self.closestPoint == nil)
        {
            self.speed=nil
        }
        else
        {
            let velocityVector = SCNVector3(closestPoint!.x-oldClosestPoint!.x,
                           closestPoint!.y-oldClosestPoint!.x,
                           closestPoint!.z-oldClosestPoint!.z)
            self.speed=velocityVector.magnitude()/deltaTime
        }
        self.boundingBoxView.updateShape(frame: boundingBox, label: getDescription())
    }

    public func getDescription() -> String
    {
        return String(format:"%@ %@ %.2f %.2f", self.label, self.relativePosition, self.distanceFromUser, self.speed ?? 0)
    }
}
