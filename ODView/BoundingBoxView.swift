import Foundation
import UIKit

class BoundingBoxView
{
    let shapeLayer: CAShapeLayer
    let textLayer: CATextLayer
    
    init() {
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 4
        shapeLayer.isHidden = true
        textLayer = CATextLayer()
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.isHidden = true
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.fontSize = 14
        textLayer.font = UIFont(name: "Avenir", size: textLayer.fontSize)
        textLayer.alignmentMode = CATextLayerAlignmentMode.left
    }
    
    func addToLayer(_ parent: CALayer) {
        parent.addSublayer(shapeLayer)
        parent.addSublayer(textLayer)
    }
    
    func removeFromLayer()
    {
        shapeLayer.isHidden = true
        textLayer.isHidden = true
        textLayer.removeFromSuperlayer()
        shapeLayer.removeFromSuperlayer()
    }
    
    func show(frame: CGRect, label: String, color: UIColor) {
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
        let textRect = label.boundingRect(with: CGSize(width: 400, height: 400),
                                          options: .usesFontLeading,
                                          attributes: attributes, context: nil)
        let textSize = CGSize(width: textRect.width + 12, height: textRect.height + 40)
        let textOrigin = CGPoint(x: frame.origin.x - 2, y: frame.origin.y)
        textLayer.frame = CGRect(origin: textOrigin, size: textSize)
    }
    
    func updateShape(frame: CGRect, label: String)
    {
        CATransaction.setDisableActions(true)
        let path = UIBezierPath(rect: frame)
        shapeLayer.path = path.cgPath
        let attributes = [NSAttributedString.Key.font: textLayer.font as Any]
        textLayer.string = label
        let textRect = label.boundingRect(with: CGSize(width: 400, height: 400),
                                          options: .usesFontLeading,
                                          attributes: attributes, context: nil)
        let textSize = CGSize(width: textRect.width + 40, height: textRect.height)
        let textOrigin = CGPoint(x: frame.origin.x - 2, y: frame.origin.y)
        textLayer.frame=CGRect(origin: textOrigin, size: textSize)
    }
}
