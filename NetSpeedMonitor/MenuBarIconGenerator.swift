import AppKit

final class MenuBarIconGenerator {
    static let horizontalPadding: CGFloat = 4
    static let minimumWidth: CGFloat = 48

    static func imageSize(
        for text: String,
        font: NSFont = .monospacedSystemFont(ofSize: 8, weight: .semibold)
    ) -> NSSize {
        let lines = text.components(separatedBy: "\n")
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = lines.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }.max() ?? 0
        return NSSize(width: max(minimumWidth, width + horizontalPadding * 2), height: lines.count > 1 ? 22 : 18)
    }
    
    static func generateIcon(
        text: String,
        font: NSFont = .monospacedSystemFont(ofSize: 8, weight: .semibold)
    ) -> NSImage {
        let image = NSImage(size: imageSize(for: text, font: font), flipped: false) { rect in
            
            let style = NSMutableParagraphStyle()
            style.alignment = .right
//            style.maximumLineHeight = 10
//            style.paragraphSpacing = -5
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
//                .baselineOffset: 0,
                .paragraphStyle: style
            ]
            
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: Self.horizontalPadding,
                y: (rect.height - textSize.height) / 2,
                width: rect.width - Self.horizontalPadding * 2,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
            return true
        }
        
        image.isTemplate = true
        return image
    }
}
