import Cocoa

class InterfaceItemView: NSView {
    private let nameField = NSTextField(labelWithString: "")
    private let speedField = NSTextField(labelWithString: "")
    private let checkImageView = NSImageView()
    private let checkFallbackField = NSTextField(labelWithString: "✓")
    private var tracking: NSTrackingArea?
    private var hovered: Bool = false

    static let nameFont = NSFont.menuFont(ofSize: 13)
    static let speedFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold)

    static let leftMargin: CGFloat = 16
    static let checkSize: CGFloat = 12
    static let gapAfterCheck: CGFloat = 4
    static let gapBeforeSpeed: CGFloat = 36
    static let rightMargin: CGFloat = 14

    static func measureSpeedWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: speedFont]
        return ceil((text as NSString).size(withAttributes: attrs).width) + 2
    }

    static var speedSampleText: String {
        return "↓999.99 MB/s  ↑999.99 MB/s"
    }

    static var nameStartX: CGFloat { leftMargin + checkSize + gapAfterCheck }

    static func measureNameWidth(_ name: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: nameFont]
        return ceil((name as NSString).size(withAttributes: attrs).width)
    }

    static func totalWidth(for nameColW: CGFloat, speedColW: CGFloat) -> CGFloat {
        return nameStartX + nameColW + gapBeforeSpeed + speedColW + rightMargin
    }

    var interfaceName: String = "" {
        didSet {
            nameField.stringValue = interfaceName
            needsLayout = true
        }
    }

    var speedText: String = "" {
        didSet {
            speedField.stringValue = speedText
            needsLayout = true
        }
    }

    var isChecked: Bool = false {
        didSet {
            checkImageView.isHidden = !isChecked || (checkImageView.image == nil)
            checkFallbackField.isHidden = !isChecked || (checkImageView.image != nil)
            needsLayout = true
        }
    }

    var nameColumnWidth: CGFloat = 80 {
        didSet {
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }

    var speedColumnWidth: CGFloat = 140 {
        didSet {
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(
            width: Self.nameStartX + nameColumnWidth + Self.gapBeforeSpeed + speedColumnWidth + Self.rightMargin,
            height: 22
        )
    }

    var onAction: (() -> Void)?

    override var isFlipped: Bool { true }

    private var highlighted: Bool {
        return (enclosingMenuItem?.isHighlighted ?? false) || hovered
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = false
        autoresizingMask = [.width]

        nameField.font = Self.nameFont
        nameField.lineBreakMode = .byTruncatingTail
        nameField.drawsBackground = false
        nameField.isBordered = false
        nameField.isEditable = false
        nameField.isSelectable = false
        addSubview(nameField)

        speedField.font = Self.speedFont
        speedField.alignment = .left
        speedField.lineBreakMode = .byClipping
        speedField.drawsBackground = false
        speedField.isBordered = false
        speedField.isEditable = false
        speedField.isSelectable = false
        speedField.maximumNumberOfLines = 1
        addSubview(speedField)

        let checkImage = NSImage(named: NSImage.Name("NSMenuOnStateTemplate"))
        if let checkImage = checkImage {
            checkImageView.image = checkImage
            checkImageView.imageScaling = .scaleProportionallyUpOrDown
            checkImageView.isHidden = !isChecked
            addSubview(checkImageView)
        }

        checkFallbackField.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        checkFallbackField.alignment = .center
        checkFallbackField.drawsBackground = false
        checkFallbackField.isBordered = false
        checkFallbackField.isEditable = false
        checkFallbackField.isSelectable = false
        checkFallbackField.isHidden = !isChecked || (checkImageView.image != nil)
        addSubview(checkFallbackField)
    }

    override func layout() {
        super.layout()
        let h = bounds.height

        let nameX = Self.nameStartX
        let speedX = nameX + nameColumnWidth + Self.gapBeforeSpeed
        let nameW = nameColumnWidth
        let speedW = speedColumnWidth

        let checkX = Self.leftMargin
        let checkY = (h - Self.checkSize) / 2
        let textY = (h - 15) / 2

        checkImageView.frame = NSRect(x: checkX - 1, y: checkY - 1, width: Self.checkSize + 2, height: Self.checkSize + 2)
        checkFallbackField.frame = NSRect(x: checkX, y: textY, width: Self.checkSize, height: 16)
        nameField.frame = NSRect(x: nameX, y: textY, width: nameW, height: 16)
        speedField.frame = NSRect(x: speedX, y: textY + 1, width: speedW, height: 14)

        let highlighted = self.highlighted
        let txt: NSColor = highlighted ? .white : .labelColor
        let spd: NSColor = highlighted ? .white : .secondaryLabelColor
        let accent: NSColor = highlighted ? .white : .controlAccentColor
        nameField.textColor = txt
        speedField.textColor = spd
        checkImageView.contentTintColor = accent
        checkFallbackField.textColor = accent
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hovered = true
        needsLayout = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovered = false
        needsLayout = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onAction?()
        enclosingMenuItem?.menu?.cancelTracking()
    }

    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        } else {
            NSColor.clear.setFill()
            bounds.fill()
        }
        super.draw(dirtyRect)
    }
}
