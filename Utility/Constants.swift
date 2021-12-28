//
//  Constants.swift
//  ODView
//
//  Created by Pietro Prebianca on 30/09/21.
//
import ARKit

class Constants
{
    public static let PREFERRED_FPS : Int = 15
    public static let PLANE_DISTANCE_THRESHOLD : Float = 0.2
    //All anchors which are farther than 4 meter will be removed
    public static let MAX_ANCHOR_DISTANCE : Float = 4.0
    //All triangles which are farther than 3 meter will be removed
    public static let MAX_TRIANGLE_DISTANCE : Float = 3.0
    /*Bounding boxes whose screen area are lower than this value will not be
    classified.*/
    public static let AREA_THRESHOLD : CGFloat = 0.5
    public static let OBSTACLE_MIN_CONFIDENCE : Float = 0.8
    public static let OBSTACLE_DEFAULT_PREDICTION =  Prediction(classification: "unknown", confidencePercentage: OBSTACLE_MIN_CONFIDENCE)
    public static let MAX_NUMBER_OF_TRIANGLE : Int = 3000
    public static let MIN_BOUNDING_BOX_SIDE : CGFloat = 200
    public static let MIN_NUMBER_OF_PREDICTIONS : Int = 20
    public static let MAX_OBSTACLE_NUMBER : Int = 50
    public static let MERGE_DISTANCE : Float = 0.5
    public static let MIN_PREDICTION_CONFIDENCE : Float = 0.80
    /*
     Un ostacolo dev'essere composto almeno da 16 triangoli (50/3).
     */
    public static let MIN_NUMBER_OF_POINT_FOR_OBSTACLE : Int = 50
    public static let FRAME_PER_SECOND : Float = 30.0
}
