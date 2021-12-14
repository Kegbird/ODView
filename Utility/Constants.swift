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
    public static let PLANE_DISTANCE_THRESHOLD : Float = 0.1
    //All triangles which are farther than 4 meter will not be considered
    public static let MAX_TRIANGLE_DISTANCE : Float = 4.0
    //All anchors which are farther than 4 meter will be removed
    public static let MAX_ANCHOR_DISTANCE : Float = 4.0
    /*Bounding boxes whose screen area are lower than this value will not be
    classified.*/
    public static let OBSTACLE_DEFAULT_CONFIDENCE : Float = 0.8
    public static let OBSTACLE_DEFAULT_PREDICTION =  Prediction(classification: "Obstacle", confidencePercentage: OBSTACLE_DEFAULT_CONFIDENCE)
    public static let MIN_BOUNDING_BOX_AREA : CGFloat = 4000
    public static let MIN_NUMBER_OF_PREDICTIONS : Int = 20
    public static let MAX_OBSTACLE_NUMBER : Int = 50
    public static let MERGE_DISTANCE : Float = 0.5
    public static let AREA_THRESHOLD : CGFloat = 1.0
    public static let MIN_PREDICTION_CONFIDENCE : Float = 0.80
    public static let MIN_NUMBER_TRIANGLES_FOR_CLUSTER : Int = 20
    public static let FRAME_PER_SECOND : Float = 30.0
}
