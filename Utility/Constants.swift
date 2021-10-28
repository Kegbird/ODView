//
//  Constants.swift
//  ODView
//
//  Created by Pietro Prebianca on 30/09/21.
//
import ARKit

class Constants
{
    public static let DISTANCE_THRESHOLD : Double = 0.1
    public static let MIN_NUMBER_TRIANGLES : Int = 10
    public static let MIN_NUMBER_POINTS_PER_CLUSTER : Int = 10
    public static let MAX_NUMBER_POINTS_PER_CLUSTER : Int = 100
    public static let MIN_CONFIDENCE_PREDICTION: Float = 0.9
    public static let FRAME_PER_SECOND : Float = 60.0
    public static var WIDTH : CGFloat = 0
    public static var HEIGHT : CGFloat = 0
    public static var OFFSET_Y : CGFloat = 0
    public static var SCALE = CGAffineTransform.identity
    public static var TRANSFORM = CGAffineTransform.identity
    public static let OFFSET = -20
}
