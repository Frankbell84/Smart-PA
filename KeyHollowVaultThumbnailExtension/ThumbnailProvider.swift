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
        guard let approvedIcon = UIImage(
            named: "KeyHollowVaultIcon",
            in: Bundle(for: ThumbnailProvider.self),
            compatibleWith: nil
        ) else {
            assertionFailure("Approved KeyHollow vault icon is missing from the extension bundle")
            return
        }

        let side = min(bounds.width, bounds.height)
        let square = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        let inset = side * 0.045
        let tile = square.insetBy(dx: inset, dy: inset)

        let clip = UIBezierPath(
            roundedRect: tile,
            cornerRadius: side * 0.20
        )
        clip.addClip()
        approvedIcon.draw(in: tile)
    }
}
