//
//  Constants.swift
//  ODView
//
//  Created by Pietro Prebianca on 30/09/21.
//
import ARKit

class Constants
{
    public static let PREFERRED_FPS : Int = 30
    public static let PLANE_DISTANCE_THRESHOLD : Float = 0.2
    public static let TRIANGLE_DISTANCE_THRESHOLD : Float = 0.2
    //All triangles which are farther than 4 meter will not be considered
    public static let MAX_TRIANGLE_DISTANCE : Float = 4.0
    //All anchors which are farther than 4 meter will be removed
    public static let MAX_ANCHOR_DISTANCE : Float = 4.0
    public static let FORGET_ANCHOR_DISTANCE : Float = 5.0
    //Obstacles that are in a range of 1 meter will be collapsed
    public static let ANCHOR_RANGE : Float = 2.0
    public static let MAX_OBSTACLE_NUMBER : Int = 50
    public static let MERGE_DISTANCE : Float = 0.5
    public static let CLOSE_ANCHOR_DISTANCE : Float = 2.0
    public static let AREA_THRESHOLD : Float = 1.0
    
    public static let MIN_POINTS_NUMBER : Int = 100
    public static let MIN_NUMBER_TRIANGLES_FOR_CLUSTER : Int = 10
    public static let FRAME_PER_SECOND : Float = 30.0
    public static var WIDTH : CGFloat = 0
    public static var HEIGHT : CGFloat = 0
    public static var OFFSET_Y : CGFloat = 0
    public static var SCALE = CGAffineTransform.identity
    public static var TRANSFORM = CGAffineTransform.identity
    public static let OFFSET = -20
}
