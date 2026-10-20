import AppKit

final class SeamSizeMenuView: NSView {
    enum Dimension {
        case length, width
        var title: String { self == .length ? "光条长度" : "光条宽度" }
        var fractionDigits: Int { self == .length ? 0 : 1 }
    }

    var onChange: (Double) -> Void = { _ in }
    private let label = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let dimension: Dimension

    init(dimension: Dimension = .length) {
        self.dimension = dimension
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 68))
        label.frame = NSRect(x: 16, y: 42, width: 228, height: 18)
        label.font = .menuFont(ofSize: 12)
        addSubview(label)
        slider.frame = NSRect(x: 14, y: 10, width: 232, height: 26)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sizeChanged)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { nil }

    func update(value: Double, range: ClosedRange<Double>) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = min(max(value, range.lowerBound), range.upperBound)
        updateLabel()
    }

    private func updateLabel() {
        let value = slider.doubleValue.formatted(.number.precision(.fractionLength(dimension.fractionDigits)))
        label.stringValue = "\(dimension.title) · \(value) pt"
        slider.setAccessibilityLabel(dimension.title)
        slider.setAccessibilityValueDescription("\(value) pt")
    }

    @objc private func sizeChanged() {
        updateLabel()
        onChange(slider.doubleValue)
    }
}
