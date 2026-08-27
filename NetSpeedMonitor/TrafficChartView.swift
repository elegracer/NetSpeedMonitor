import Cocoa

final class TrafficChartView: NSView {
    var samples: [TrafficSample] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Recent network speed history")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Recent network speed history")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        for fraction in [0.25, 0.5, 0.75] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX, y: bounds.height * fraction))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.height * fraction))
            path.lineWidth = 0.5
            path.stroke()
        }
        drawSeries(samples.map(\.downloadBytesPerSecond), color: .systemCyan)
        drawSeries(samples.map(\.uploadBytesPerSecond), color: .systemPurple)
    }

    private func drawSeries(_ values: [Double], color: NSColor) {
        guard values.count > 1, let maximum = values.max(), maximum > 0 else { return }
        let path = NSBezierPath()
        for (index, value) in values.enumerated() {
            let x = bounds.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = bounds.height - bounds.height * CGFloat(value / maximum)
            index == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
        }
        color.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
