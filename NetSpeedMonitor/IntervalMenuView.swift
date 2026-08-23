import Cocoa

final class IntervalScaleView: NSView {
    private let labels: [(index: Int, text: String)] = [
        (0, "1s"), (4, "5s"), (6, "15s"), (9, "30s"), (12, "60s"),
    ]

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        for label in labels {
            let size = (label.text as NSString).size(withAttributes: attributes)
            let fraction = CGFloat(label.index) / CGFloat(AppSettings.updateIntervals.count - 1)
            let centerX = bounds.minX + bounds.width * fraction
            let x = min(max(bounds.minX, centerX - size.width / 2), bounds.maxX - size.width)
            (label.text as NSString).draw(at: NSPoint(x: x, y: 0), withAttributes: attributes)
        }
    }
}

final class IntervalMenuView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Update Interval")
    private let subtitleLabel = NSTextField(labelWithString: "Choose refresh cadence")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let scaleView = IntervalScaleView()

    var onIntervalChange: ((Int) -> Void)?

    var intervalSeconds: Int = 1 {
        didSet { syncControls() }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        frame.size = NSSize(width: 340, height: 108)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.textColor = .controlAccentColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        slider.minValue = 0
        slider.maxValue = Double(AppSettings.updateIntervals.count - 1)
        slider.numberOfTickMarks = AppSettings.updateIntervals.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = false
        slider.toolTip = "Choose how often network speed is refreshed"
        slider.setAccessibilityLabel("Update interval")
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slider)

        scaleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scaleView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -8),
            slider.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            scaleView.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: -2),
            scaleView.leadingAnchor.constraint(equalTo: slider.leadingAnchor, constant: 2),
            scaleView.trailingAnchor.constraint(equalTo: slider.trailingAnchor, constant: -2),
            scaleView.heightAnchor.constraint(equalToConstant: 13),
        ])

        syncControls()
    }

    private func syncControls() {
        let normalized = AppSettings.normalizedUpdateInterval(intervalSeconds)
        valueLabel.stringValue = "\(normalized) sec"
        if let index = AppSettings.updateIntervals.firstIndex(of: normalized) {
            slider.doubleValue = Double(index)
        }
        slider.setAccessibilityValue("\(normalized) seconds")
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let index = max(0, min(AppSettings.updateIntervals.count - 1, Int(sender.doubleValue.rounded())))
        let seconds = AppSettings.updateIntervals[index]
        slider.setAccessibilityValue("\(seconds) seconds")
        onIntervalChange?(seconds)
    }
}
