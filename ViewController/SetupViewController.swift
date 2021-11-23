//
//  SetupViewController.swift
//  ODView
//
//  Created by Pietro Prebianca on 23/11/21.
//
import UIKit

class SetupViewController : UIViewController
{
    private var height : Decimal = 1.5
    
    private let quote : Decimal = 0.1
    
    @IBOutlet weak var heightLabel: UILabel!
    
    @IBAction func IncrementHeight(_ sender: Any) {
        if(height+quote>=2) { return }
        height+=quote
        heightLabel.text = "\(height)"+" m"
    }
    
    @IBAction func DecrementHeight(_ sender: Any) {
        if(height-quote<=0) { return }
        height-=quote
        heightLabel.text = "\(height)"+" m"
    }
    
    @IBAction func ConfirmSettings(_ sender: Any)
    {
        performSegue(withIdentifier: "toObstacleDetectorViewController", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        let destination = segue.destination as! ObstacleFinderViewController
        destination.setChestHeight(height: height)
    }
}
