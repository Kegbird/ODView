import Foundation
import UIKit
import ARKit

class ObstacleBoundingBoxView
{
    private let shapeLayer: CAShapeLayer
    
    init() {
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 4
        shapeLayer.isHidden = true
    }
    
    func addToLayer(_ parent: CALayer)
    {
        parent.addSublayer(shapeLayer)
    }
    
    func removeFromLayer()
    {
        shapeLayer.isHidden = true
        shapeLayer.removeFromSuperlayer()
    }
    
    func show(frame: CGRect, color: UIColor)
    {
        CATransaction.setDisableActions(true)
        let path = UIBezierPath(rect: frame)
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.isHidden = false
    }
    
    func hide()
    {
        shapeLayer.isHidden = true
    }
    
    func isHide() -> Bool
    {
        return shapeLayer.isHidden
    }
}
