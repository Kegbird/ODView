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
    public var label : String!
    public var anchor : ARMeshAnchor!
    public var cluster : [SCNVector3]
    
    init()
    {
        label = ""
        self.cluster=[]
    }
    
    func addNewPoint(point: SCNVector3)
    {
        cluster.append(point)
    }
}
