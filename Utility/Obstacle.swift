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
    
    public init()
    {
        minPointBoundingBox = nil
        maxPointBoundingBox = nil
        minWorldPosition = nil
        maxWorldPosition = nil
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
    
    public func updateBoundaries(frame: ARFrame, viewportSize: CGSize, worldPoint: SCNVector3)
    {
        let screenPoint = frame.camera.projectPoint(worldPoint.getSimd(), orientation: .portrait, viewportSize: viewportSize)
        
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
        if(worldPoint.x>maxWorldPosition.x) { maxWorldPosition.x = worldPoint.x }
        if(worldPoint.z>maxWorldPosition.z) { maxWorldPosition.z = worldPoint.z }
        
        if(screenPoint.x<minPointBoundingBox.x) { minPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y<minPointBoundingBox.y) { minPointBoundingBox.y = screenPoint.y }
        if(screenPoint.x>maxPointBoundingBox.x) { maxPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y>maxPointBoundingBox.y) { maxPointBoundingBox.y = screenPoint.y }
    }
    
    public func getFrame() -> CGRect
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            return CGRect.zero
        }
        
        let width = maxPointBoundingBox.x - minPointBoundingBox.x
        let height = maxPointBoundingBox.y - minPointBoundingBox.y
        let frame = CGRect(x: minPointBoundingBox.x, y: minPointBoundingBox.y, width: width, height: height)
        return frame
    }
    
    public func getDistanceWithOtherObstacle(other : Obstacle) -> Float
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            return 0
        }
        /*
         Devi calcolare la distanza. Due modi: misuri la distanza tra ogni coppia di punti (preciso ma lento) oppure fai il mbr degli oggetti e poi calcoli la distanza tra due parallelepipedi (tempo lineare nel numero di punti, secondo me sufficientemente preciso per quello che ci serve). Tra l’altro se hai un punto del codice dove scorri tutti i vertici per ogni oggetto, lì puoi aggiungere la calcolo della min/max xyz, dunque la seconda opzione arriva praticamente gratis
         */
        
        var midWordPosition = SCNVector3Zero
        midWordPosition.x = maxWorldPosition.x + minWorldPosition.x
        midWordPosition.y = maxWorldPosition.y + minWorldPosition.y
        midWordPosition.z = maxWorldPosition.z + minWorldPosition.z
        midWordPosition.x /= 2.0
        midWordPosition.y /= 2.0
        midWordPosition.z /= 2.0
        
        let otherMaxWorldPosition = other.getMaxWorldPosition()
        let otherMinWorldPosition = other.getMinWorldPosition()
        
        var otherMidWorldPosition = SCNVector3Zero
        otherMidWorldPosition.x = otherMaxWorldPosition.x + otherMinWorldPosition.x
        otherMidWorldPosition.y = otherMaxWorldPosition.y + otherMinWorldPosition.y
        otherMidWorldPosition.z = otherMaxWorldPosition.z + otherMinWorldPosition.z
        otherMidWorldPosition.x /= 2.0
        otherMidWorldPosition.y /= 2.0
        otherMidWorldPosition.z /= 2.0
        
        return SCNVector3.distanceBetween(midWordPosition, otherMidWorldPosition)
    }
    
    public func mergeWithOther(other : Obstacle)
    {
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
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
