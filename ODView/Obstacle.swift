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
    var obstacleNode: SCNNode!
    
    init(name: String, position: SCNVector3) {
        obstacleNode=SCNNode(geometry: SCNSphere(radius: 0.1))
        obstacleNode.geometry?.firstMaterial?.diffuse.contents = UIColor.red
    }
    
    func setPosition()
    {
        
    }
}
