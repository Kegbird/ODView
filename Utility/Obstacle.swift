import Foundation
import ARKit

class Obstacle
{
    internal var minPointBoundingBox : CGPoint!
    internal var maxPointBoundingBox : CGPoint!
    internal var minWorldPosition : SCNVector3!
    internal var maxWorldPosition : SCNVector3!
    internal var closestWorldPosition : SCNVector3!
    internal var distanceFromCamera : Double!
    internal var pointNumber : Int
    
    public init()
    {
        minPointBoundingBox = nil
        maxPointBoundingBox = nil
        minWorldPosition = nil
        maxWorldPosition = nil
        closestWorldPosition = nil
        distanceFromCamera = nil
        pointNumber = 0
    }
    
    public func copy() -> Obstacle
    {
        let obstacle = Obstacle()
        obstacle.minPointBoundingBox = minPointBoundingBox
        obstacle.maxPointBoundingBox = maxPointBoundingBox
        obstacle.minWorldPosition = minWorldPosition
        obstacle.maxWorldPosition = maxWorldPosition
        obstacle.pointNumber = pointNumber
        obstacle.closestWorldPosition = closestWorldPosition
        obstacle.distanceFromCamera = distanceFromCamera
        return obstacle
    }
    
    public func getPointNumber() -> Int
    {
        return pointNumber
    }
    
    public func getDistance() -> Double
    {
        return distanceFromCamera
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
        //Calcolo la proiezione del vettore worldPoint (vertice del triangolo) sul vettore camera (la direzione
        //della camera di arkit; la lunghezza di quel vettore rappresenta la distanza dall'ostacolo.
        let cameraTransform = frame.camera.transform
        let cameraWorldPosition = SCNVector3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let viewVector = SCNVector3(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z)
        let distance = SCNVector3(cameraWorldPosition.getSimd()-worldPoint.getSimd()).dotProduct(viewVector)
        //Incremento il numero dei punti dell'ingombro
        pointNumber=pointNumber+1
        //Calcolo lo screen point del corrispondente punto mondo ed eseguo un clamp (nel caso non ricadano in vista)
        var screenPoint = frame.camera.projectPoint(worldPoint.getSimd(), orientation: .portrait, viewportSize: viewportSize)
        screenPoint = clampScreenPoint(screenPoint: screenPoint, viewportSize: viewportSize)
        //Se non ha punti associati, allora li inizializzo
        if(minPointBoundingBox==nil || minWorldPosition==nil
           || maxPointBoundingBox==nil || maxWorldPosition==nil)
        {
            minWorldPosition = worldPoint
            maxWorldPosition = worldPoint
            distanceFromCamera = distance
            closestWorldPosition = worldPoint
            minPointBoundingBox = screenPoint
            maxPointBoundingBox = screenPoint
            return
        }
        //Aggiorno la bounding box dell'ingombro
        if(worldPoint.x<minWorldPosition.x) { minWorldPosition.x = worldPoint.x }
        if(worldPoint.y<minWorldPosition.y) { minWorldPosition.y = worldPoint.y }
        if(worldPoint.z<minWorldPosition.z) { minWorldPosition.z = worldPoint.z }
        if(worldPoint.x>maxWorldPosition.x) { maxWorldPosition.x = worldPoint.x }
        if(worldPoint.y>maxWorldPosition.y) { maxWorldPosition.y = worldPoint.y }
        if(worldPoint.z>maxWorldPosition.z) { maxWorldPosition.z = worldPoint.z }
        //Aggiorno le coordinate schermo dell'ingombro
        if(screenPoint.x<minPointBoundingBox.x) { minPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y<minPointBoundingBox.y) { minPointBoundingBox.y = screenPoint.y }
        if(screenPoint.x>maxPointBoundingBox.x) { maxPointBoundingBox.x = screenPoint.x }
        if(screenPoint.y>maxPointBoundingBox.y) { maxPointBoundingBox.y = screenPoint.y }
        //Aggiorno il closest world point: se il nuovo punto è più vicino alla telefono, allora lo aggiorno
        if(distance<distanceFromCamera)
        {
            closestWorldPosition = worldPoint
            distanceFromCamera = distance
        }
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
        let obstacleRect = getObstacleRect()
        return obstacleRect.width*obstacleRect.height
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
    
    public func mergeWithOther(other : Obstacle)
    {
        pointNumber=pointNumber+other.pointNumber
        
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
        //Se il nuovo punto è più vicino alla telefono, allora lo aggiorno
        if(distanceFromCamera>other.distanceFromCamera)
        {
            closestWorldPosition = other.closestWorldPosition
            distanceFromCamera = other.distanceFromCamera
        }
    }
}
