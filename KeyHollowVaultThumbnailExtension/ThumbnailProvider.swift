import QuickLookThumbnailing
import UIKit

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let size = CGSize(
            width: max(request.maximumSize.width, 1),
            height: max(request.maximumSize.height, 1)
        )
        let reply = QLThumbnailReply(
            contextSize: size,
            currentContextDrawing: {
                KeyHollowVaultThumbnailArtwork.draw(in: CGRect(origin: .zero, size: size))
                return true
            }
        )
        reply.extensionBadge = "KHV"
        handler(reply, nil)
    }
}

private enum KeyHollowVaultThumbnailArtwork {
    static func draw(in bounds: CGRect) {
        let side = min(bounds.width, bounds.height)
        let square = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        let inset = side * 0.045
        let tile = square.insetBy(dx: inset, dy: inset)

        UIColor(
            red: 10 / 255,
            green: 30 / 255,
            blue: 58 / 255,
            alpha: 1
        ).setFill()
        UIBezierPath(
            roundedRect: tile,
            cornerRadius: side * 0.20
        ).fill()

        let eyeWidth = side * 0.66
        let eyeHeight = side * 0.34
        let eyeRect = CGRect(
            x: square.midX - eyeWidth / 2,
            y: square.midY - eyeHeight / 2,
            width: eyeWidth,
            height: eyeHeight
        )
        let eye = UIBezierPath()
        eye.move(to: CGPoint(x: eyeRect.minX, y: eyeRect.midY))
        eye.addCurve(
            to: CGPoint(x: eyeRect.maxX, y: eyeRect.midY),
            controlPoint1: CGPoint(x: eyeRect.minX + eyeWidth * 0.25, y: eyeRect.minY),
            controlPoint2: CGPoint(x: eyeRect.maxX - eyeWidth * 0.25, y: eyeRect.minY)
        )
        eye.addCurve(
            to: CGPoint(x: eyeRect.minX, y: eyeRect.midY),
            controlPoint1: CGPoint(x: eyeRect.maxX - eyeWidth * 0.25, y: eyeRect.maxY),
            controlPoint2: CGPoint(x: eyeRect.minX + eyeWidth * 0.25, y: eyeRect.maxY)
        )
        eye.lineWidth = max(2, side * 0.035)
        eye.lineJoinStyle = .round
        UIColor.white.setStroke()
        eye.stroke()

        let gold = UIColor(
            red: 226 / 255,
            green: 183 / 255,
            blue: 73 / 255,
            alpha: 1
        )
        gold.setFill()

        let headRadius = side * 0.085
        let headCenter = CGPoint(
            x: square.midX,
            y: square.midY - side * 0.035
        )
        UIBezierPath(
            ovalIn: CGRect(
                x: headCenter.x - headRadius,
                y: headCenter.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
        ).fill()

        let stemTop = headCenter.y + headRadius * 0.55
        let stemBottom = square.midY + side * 0.18
        let stem = UIBezierPath()
        stem.move(to: CGPoint(x: square.midX - side * 0.035, y: stemTop))
        stem.addLine(to: CGPoint(x: square.midX - side * 0.065, y: stemBottom))
        stem.addLine(to: CGPoint(x: square.midX + side * 0.065, y: stemBottom))
        stem.addLine(to: CGPoint(x: square.midX + side * 0.035, y: stemTop))
        stem.close()
        stem.fill()
    }
}
