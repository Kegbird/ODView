import Foundation
import UIKit
import ARKit

class ObstacleBoundingBoxView
{
    private let shapeLayer: CALayer
    private let textLayer: CATextLayer
    
    init() {
        shapeLayer = CALayer()
        shapeLayer.borderWidth=2.0
        shapeLayer.borderColor = UIColor.clear.cgColor
        shapeLayer.cornerRadius=0
        shapeLayer.isHidden = true
        textLayer = CATextLayer()
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.isHidden = true
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.fontSize = 16
        textLayer.font = UIFont(name: "Avenir", size: textLayer.fontSize)
        textLayer.alignmentMode = CATextLayerAlignmentMode.left
    }
    
    func addToLayer(_ parent: CALayer)
    {
        parent.addSublayer(shapeLayer)
        parent.addSublayer(textLayer)
    }
    
    func removeFromLayer()
    {
        shapeLayer.isHidden = true
        shapeLayer.removeFromSuperlayer()
        textLayer.isHidden = true
        textLayer.removeFromSuperlayer()
    }
    
    func show(rect: CGRect, label: String, color: UIColor)
    {
        CATransaction.setDisableActions(true)
        shapeLayer.frame = rect
        shapeLayer.borderColor = color.cgColor
        shapeLayer.isHidden = false
        textLayer.string = label
        textLayer.backgroundColor=CGColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        textLayer.isHidden = false
        let textOrigin = CGPoint(x: rect.origin.x - 4, y: rect.origin.y)
        let textSize = CGSize(width: 100, height: 50)
        textLayer.frame = CGRect(origin: textOrigin, size: textSize)
    }
    
    func hide()
    {
        shapeLayer.isHidden = true
        textLayer.isHidden = true
    }
    
    func isHide() -> Bool
    {
        return shapeLayer.isHidden
    }
}
