import UIKit
import SwiftUI

enum CollageRenderer {
    /// Produces a 4:5 portrait JPEG flat-lay collage from a set of items.
    /// Items are sorted by category (outerwear → top → bottom → footwear → accessories → fullBody).
    @MainActor
    static func render(items: [Item], size: CGSize = CGSize(width: 800, height: 1000)) -> UIImage {
        let order: [ItemCategory] = [.outerwear, .top, .fullBody, .bottom, .footwear, .accessory]
        let sorted = items.sorted { lhs, rhs in
            let lIdx = order.firstIndex(of: lhs.category) ?? 99
            let rIdx = order.firstIndex(of: rhs.category) ?? 99
            return lIdx < rIdx
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let positions = layoutPositions(for: sorted, in: size)
            for (item, rect) in zip(sorted, positions) {
                if let img = ImageStore.load(item.imagePath) {
                    let fitted = aspectFit(img.size, into: rect.size)
                    let origin = CGPoint(
                        x: rect.midX - fitted.width / 2,
                        y: rect.midY - fitted.height / 2
                    )
                    img.draw(in: CGRect(origin: origin, size: fitted))
                }
            }
        }
    }

    private static func layoutPositions(for items: [Item], in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        switch items.count {
        case 1:
            return [CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.8, height: h * 0.8)]
        case 2:
            return [
                CGRect(x: 0, y: 0, width: w, height: h * 0.5),
                CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5),
            ]
        case 3:
            return [
                CGRect(x: 0, y: 0, width: w, height: h * 0.4),
                CGRect(x: 0, y: h * 0.4, width: w, height: h * 0.4),
                CGRect(x: 0, y: h * 0.8, width: w, height: h * 0.2),
            ]
        case 4:
            return [
                CGRect(x: 0, y: 0, width: w, height: h * 0.32),
                CGRect(x: 0, y: h * 0.32, width: w, height: h * 0.32),
                CGRect(x: 0, y: h * 0.64, width: w * 0.55, height: h * 0.36),
                CGRect(x: w * 0.55, y: h * 0.64, width: w * 0.45, height: h * 0.36),
            ]
        default:
            // 5–6 items: 2-column grid
            let rows = Int(ceil(Double(items.count) / 2.0))
            let rowH = h / CGFloat(rows)
            return items.enumerated().map { idx, _ in
                let col = idx % 2
                let row = idx / 2
                return CGRect(
                    x: CGFloat(col) * (w / 2),
                    y: CGFloat(row) * rowH,
                    width: w / 2,
                    height: rowH
                )
            }
        }
    }

    private static func aspectFit(_ source: CGSize, into target: CGSize) -> CGSize {
        let scale = min(target.width / source.width, target.height / source.height) * 0.92  // small padding
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}
