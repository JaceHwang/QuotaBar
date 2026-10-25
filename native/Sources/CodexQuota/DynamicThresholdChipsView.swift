import AppKit
import QuotaCore

/// Native numeric chips reuse their controls so moving between inputs never loses focus.
@MainActor final class DynamicThresholdChipsView: NSView, NSTextFieldDelegate {
    private final class ValueField: NSTextField { var original: Int? }
    private final class RemoveButton: NSButton { var original: Int? }
    private struct Chip { let view: NSView; let field: ValueField; let remove: RemoveButton }
    private let kind: String
    private let titleText: String
    private let unit: String
    private let range: ClosedRange<Int>
    private let copy: ExperienceCopy
    private let change: (Int?, Int?) -> Bool
    private let error: (String) -> Void
    private var values: [Int] = []
    private var chips: [Int: Chip] = [:]
    private var draft: Chip?
    private var pending: (old: Int?, new: Int, chip: Chip)?
    private var parts: [(NSView, CGFloat)] = []
    private var updating = false
    private var name: NSTextField!
    private var addButton: NSButton!
    private var empty: NSTextField!
    private let rowHeight: CGFloat = 26
    override var isFlipped: Bool { true }
    init(kind: String, title: String, unit: String, range: ClosedRange<Int>, language: CodexDisplayLanguage, change: @escaping (Int?, Int?) -> Bool, error: @escaping (String) -> Void) {
        self.kind = kind; titleText = title; self.unit = unit; self.range = range; copy = ExperienceCopy(language); self.change = change; self.error = error
        super.init(frame: .zero)
        name = NSTextField(labelWithString: titleText); name.font = .systemFont(ofSize: 13); name.identifier = .init("notification.title.\(kind)")
        addButton = NSButton(title: "+", target: self, action: #selector(addTapped)); addButton.bezelStyle = .roundRect; addButton.controlSize = .small
        addButton.identifier = .init("notification.threshold.\(kind).add")
        addButton.setAccessibilityLabel(copy.text("Add \(titleText) threshold", "添加\(titleText)阈值", "新增\(titleText)閾值")); addButton.toolTip = addButton.accessibilityLabel()
        empty = QuotaSettingsStyle.label(copy.text("No thresholds — no reminders", "未设置阈值，不发送此类提醒", "未設定閾值，不傳送此類提醒"), size: 11, secondary: true)
    }
    required init?(coder: NSCoder) { nil }
    func render(_ values: [Int]) {
        updating = true
        var next: [Int: Chip] = [:]
        for value in values {
            let chip: Chip
            if let old = chips[value] { chip = old }
            else if let pending, pending.new == value { chip = pending.chip; update(chip, value: value) }
            else { chip = makeChip(value) }
            next[value] = chip
        }
        for (_, chip) in chips where !next.values.contains(where: { $0.view === chip.view }) { chip.view.removeFromSuperview() }
        if let pending, let draft, pending.chip.view === draft.view, next[pending.new] != nil { self.draft = nil }
        self.values = values; chips = next
        updating = false; arrangeParts()
    }
    private func update(_ chip: Chip, value: Int) {
        chip.field.original = value; chip.field.stringValue = String(value); chip.field.currentEditor()?.string = String(value); chip.remove.original = value
        chip.field.identifier = .init("notification.threshold.\(kind).\(value)")
        chip.remove.identifier = .init("notification.threshold.\(kind).remove.\(value)")
        chip.remove.setAccessibilityLabel(copy.text("Remove \(value) \(unit) threshold", "移除\(value)\(unit)阈值", "移除\(value)\(unit)閾值"))
    }
    private func makeChip(_ value: Int?) -> Chip {
        let view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 6; view.layer?.borderWidth = 0.5
        let field = ValueField(string: value.map(String.init) ?? ""); field.original = value; field.delegate = self
        field.isBezeled = false; field.drawsBackground = false; field.font = .systemFont(ofSize: 12); field.alignment = .center
        field.placeholderString = "…"; field.target = self; field.action = #selector(commit(_:))
        field.identifier = .init("notification.threshold.\(kind).\(value.map(String.init) ?? "draft")")
        field.setAccessibilityLabel(titleText + " " + unit + " (\(range.lowerBound)–\(range.upperBound))")
        let suffix = NSTextField(labelWithString: unit); suffix.font = .systemFont(ofSize: 11); suffix.textColor = .secondaryLabelColor
        let remove = RemoveButton(title: "×", target: self, action: #selector(removeTapped(_:))); remove.original = value; remove.isBordered = false; remove.font = .systemFont(ofSize: 14)
        remove.identifier = .init("notification.threshold.\(kind).remove.\(value.map(String.init) ?? "draft")")
        remove.setAccessibilityLabel(copy.text("Remove \(value.map(String.init) ?? "") \(unit) threshold", "移除\(value.map(String.init) ?? "")\(unit)阈值", "移除\(value.map(String.init) ?? "")\(unit)閾值"))
        let numberWidth: CGFloat = kind == "low" ? 26 : 40
        let unitWidth = max(10, ceil(suffix.intrinsicContentSize.width))
        field.frame = NSRect(x: 3, y: 4, width: numberWidth, height: 18)
        suffix.frame = NSRect(x: 3 + numberWidth, y: 5, width: unitWidth, height: 16)
        remove.frame = NSRect(x: 5 + numberWidth + unitWidth, y: 3, width: 16, height: 20)
        view.addSubview(field); view.addSubview(suffix); view.addSubview(remove)
        view.layer?.borderColor = NSColor.separatorColor.cgColor; view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        return Chip(view: view, field: field, remove: remove)
    }
    private func arrangeParts() {
        let nameWidth = ceil(max(name.intrinsicContentSize.width, name.cell?.cellSize.width ?? 0)) + 4
        parts = [(name, nameWidth)]
        let unitWidth = max(10, ceil((unit as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width))
        let chipWidth = (kind == "low" ? 26.0 : 40.0) + unitWidth + 24
        var controls: [NSView] = []
        for value in values { if let chip = chips[value] { parts.append((chip.view, chipWidth)); controls.append(contentsOf: [chip.field, chip.remove]) } }
        if let draft { parts.append((draft.view, chipWidth)); controls.append(contentsOf: [draft.field, draft.remove]) }
        parts.append((addButton, 24)); addButton.isEnabled = values.count < 32 && draft == nil
        if values.isEmpty && draft == nil { parts.append((empty, 280)) } else { empty.removeFromSuperview() }
        for (view, _) in parts where view.superview !== self { addSubview(view) }
        for (index, control) in controls.enumerated() { control.nextKeyView = index + 1 < controls.count ? controls[index+1] : addButton }
        invalidateIntrinsicContentSize(); needsLayout = true
    }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: arrange(width: bounds.width > 0 ? bounds.width : 320, apply: false)) }
    @discardableResult private func arrange(width: CGFloat, apply: Bool) -> CGFloat {
        var x: CGFloat = 0, y: CGFloat = 0
        for (view, desiredWidth) in parts {
            let w = min(width, desiredWidth)
            if x > 0 && x + w > width + 0.5 { x = 0; y += rowHeight + 6 }
            if apply { view.frame = NSRect(x: x, y: y, width: w, height: rowHeight) }
            x += w + 6
        }
        return y + rowHeight
    }
    override func layout() { super.layout(); let height = arrange(width: max(1, bounds.width), apply: true); if abs(height - bounds.height) > 0.5 { invalidateIntrinsicContentSize() } }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { for (view, _) in parts where view.layer != nil { view.layer?.borderColor = NSColor.separatorColor.cgColor; view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor } }
    }
    @objc private func addTapped() {
        guard values.count < 32, draft == nil else { return }
        let chip = makeChip(nil); draft = chip; arrangeParts(); layoutSubtreeIfNeeded(); window?.makeFirstResponder(chip.field); chip.field.selectText(nil)
    }
    @objc private func removeTapped(_ sender: RemoveButton) {
        if let original = sender.original { _ = change(original, nil) }
        else { draft?.view.removeFromSuperview(); draft = nil; arrangeParts() }
    }
    @objc private func commit(_ sender: ValueField) {
        guard !updating, let chip = chips.values.first(where: { $0.field === sender }) ?? (draft?.field === sender ? draft : nil) else { return }
        let raw = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty, sender.original == nil { draft?.view.removeFromSuperview(); draft = nil; arrangeParts(); return }
        guard let value = Int(raw), range.contains(value), !values.contains(where: { $0 == value && $0 != sender.original }) else {
            error(copy.text("Use unique integers \(range.lowerBound)–\(range.upperBound).", "请输入\(range.lowerBound)–\(range.upperBound)内不重复的整数。", "請輸入\(range.lowerBound)–\(range.upperBound)內不重複的整數。"))
            if let original = sender.original { sender.stringValue = String(original); sender.currentEditor()?.string = String(original) }
            else { draft?.view.removeFromSuperview(); draft = nil; arrangeParts() }
            return
        }
        guard sender.original != value else { sender.stringValue = String(value); sender.currentEditor()?.string = String(value); return }
        pending = (sender.original, value, chip)
        let saved = change(sender.original, value)
        pending = nil
        if !saved { sender.stringValue = sender.original.map(String.init) ?? "" }
    }
    func controlTextDidEndEditing(_ notification: Notification) { if let field = notification.object as? ValueField { commit(field) } }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), let field = control as? ValueField {
            if let original = field.original { field.stringValue = String(original) }
            else { draft?.view.removeFromSuperview(); draft = nil; arrangeParts() }
            return true
        }
        return false
    }
}
