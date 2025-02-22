import AppKit

final class MenuBarIconGenerator {
    
    static func generateIcon(
        text: String,
        font: NSFont = .monospacedSystemFont(ofSize: 8, weight: .semibold)
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: 66, height: 22), flipped: false) { rect in
            
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
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
            return true
        }
        
        image.isTemplate = true
        return image
    }
}
