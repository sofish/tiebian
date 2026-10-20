import AppKit

final class SeamSizeMenuView: NSView {
    var onChange: (Double) -> Void = { _ in }
    private let label = NSTextField(labelWithString: "")
    private let slider = NSSlider()

    init() {
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
        label.stringValue = "光条长度 · \(Int(slider.doubleValue.rounded())) pt"
        slider.setAccessibilityLabel("光条长度")
        slider.setAccessibilityValueDescription("\(Int(slider.doubleValue.rounded())) pt")
    }

    @objc private func sizeChanged() {
        updateLabel()
        onChange(slider.doubleValue)
    }
}
