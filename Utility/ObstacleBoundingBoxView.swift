import Foundation
import UIKit
import ARKit

class ObstacleBoundingBoxView
{
    private let shapeLayer: CAShapeLayer
    private let textLayer: CATextLayer
    
    init() {
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 2
        shapeLayer.isHidden = true
        textLayer = CATextLayer()
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.isHidden = true
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.fontSize = 8
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
    
    func show(frame: CGRect, label: String, color: UIColor)
    {
        CATransaction.setDisableActions(true)
        let path = UIBezierPath(rect: frame)
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.isHidden = false
        
        textLayer.string = label
        textLayer.backgroundColor = color.cgColor
        textLayer.isHidden = false
        let attributes = [
            NSAttributedString.Key.font: textLayer.font as Any
        ]
        let textRect = label.boundingRect(with: CGSize(width: 100, height: 100),
                                          options: .usesFontLeading,
                                          attributes: attributes, context: nil)
        let textSize = CGSize(width: textRect.width, height: textRect.height)
        let textOrigin = CGPoint(x: frame.origin.x - 2, y: frame.origin.y)
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
