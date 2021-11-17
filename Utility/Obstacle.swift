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
    private var worldPosition : SCNVector3
    private var minPointBoundingBox : CGPoint!
    private var maxPointBoundingBox : CGPoint!
    
    public init()
    {
        worldPosition = SCNVector3Zero
    }
    
    public func getWorldPosition() -> SCNVector3
    {
        return worldPosition
    }
    
    public func getMinPoint() -> CGPoint
    {
        return minPointBoundingBox
    }
    
    public func getMaxPoint() -> CGPoint
    {
        return maxPointBoundingBox
    }
    
    public func updateCentroid(worldPoint : SCNVector3)
    {
        worldPosition.x += worldPoint.x
        worldPosition.y += worldPoint.y
        worldPosition.z += worldPoint.z
    }
    
    public func calculateCentroid(numPoints : Int)
    {
        worldPosition.x /= Float(numPoints)
        worldPosition.y /= Float(numPoints)
        worldPosition.z /= Float(numPoints)
    }
    
    func updateBoundaries(screenPoint : CGPoint)
    {
        if(minPointBoundingBox == nil)
        {
            minPointBoundingBox = screenPoint
            maxPointBoundingBox = screenPoint
            return
        }
        
        if(screenPoint.x<minPointBoundingBox.x) { minPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y<minPointBoundingBox.y) { minPointBoundingBox.y = screenPoint.y }
        if(screenPoint.x>maxPointBoundingBox.x) { maxPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y>maxPointBoundingBox.y) { maxPointBoundingBox.y = screenPoint.y }
    }
    
    public func updateBoundaries(frame: ARFrame, viewportSize: CGSize, point: SCNVector3)
    {
        let screenPoint = frame.camera.projectPoint(point.getSimd(), orientation: .portrait, viewportSize: viewportSize)
        
        updateBoundaries(screenPoint: screenPoint)
    }
    
    public func getFrame() -> CGRect
    {
        let width = maxPointBoundingBox.x - minPointBoundingBox.x
        let height = maxPointBoundingBox.y - minPointBoundingBox.y
        let frame = CGRect(x: minPointBoundingBox.x, y: minPointBoundingBox.y, width: width, height: height)
        return frame
    }
    
    /*public func addBoundingBoxToLayer(parent: CALayer)
    {
        DispatchQueue.main.async
        { [weak self] in
            self!.boundingBoxView.addToLayer(parent)
        }
    }
    
    public func getBoundingBox() -> BoundingBoxView
    {
        return boundingBoxView
    }
    
    public func showBoundingBox()
    {
        let width = maxPointBoundingBox.x - minPointBoundingBox.x
        let height = maxPointBoundingBox.y - minPointBoundingBox.y
        let boundingBox = CGRect(x: minPointBoundingBox.x, y: minPointBoundingBox.y, width: width, height: height)
        boundingBoxView.show(frame: boundingBox, color: UIColor.blue)
    }*/
}
