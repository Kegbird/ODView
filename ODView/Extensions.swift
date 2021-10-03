//
//  Extensions.swift
//  ODView
//
//  Created by Pietro Prebianca on 30/09/21.
//

import Foundation
import ARKit

extension SCNVector3
{
    public func magnitude() -> Float
    {
        return sqrt(pow(self.x, 2)+pow(self.y, 2)+pow(self.z, 2))
    }
    
    public static func distance(startPoint:SCNVector3, endPoint:SCNVector3) -> Float
    {
        return sqrt(pow(startPoint.x-endPoint.x,2)+pow(startPoint.y-endPoint.y,2)+pow(startPoint.z-endPoint.z,2))
    }
}
