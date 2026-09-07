import AppKit

private enum SettingKey {
    static let fontFamily = "fontFamily"
    static let fontSize = "fontSize"
    static let lineHeight = "lineHeight"
    static let cursorStyle = "cursorStyle"
    static let cursorBlink = "cursorBlink"
    static let scrollback = "scrollback"
    static let shellPath = "shellPath"
    static let loginShell = "loginShell"
    static let windowOpacity = "windowOpacity"

    static let foreground = "foreground"
    static let background = "background"
    static let cursor = "cursor"
    static let selection = "selection"

    static let black = "black"
    static let red = "red"
    static let green = "green"
    static let yellow = "yellow"
    static let blue = "blue"
    static let magenta = "magenta"
    static let cyan = "cyan"
    static let white = "white"
}

@MainActor
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}

@MainActor
private final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private let defaultValues: [String: Any] = [
        SettingKey.fontFamily: "Menlo",
        SettingKey.fontSize: 14.0,
        SettingKey.lineHeight: 1.25,
        SettingKey.cursorStyle: "bar",
        SettingKey.cursorBlink: true,
        SettingKey.scrollback: 10_000,
        SettingKey.shellPath: "",
        SettingKey.loginShell: true,
        SettingKey.windowOpacity: 1.0,

        SettingKey.foreground: "#edf1f7",
        SettingKey.background: "#00000000",
        SettingKey.cursor: "#a9c9ff",
        SettingKey.selection: "#91b6ff55",

        SettingKey.black: "#38404d",
        SettingKey.red: "#ff8090",
        SettingKey.green: "#a3dfaa",
        SettingKey.yellow: "#f2d49b",
        SettingKey.blue: "#94baff",
        SettingKey.magenta: "#d7b0ff",
        SettingKey.cyan: "#95dce5",
        SettingKey.white: "#edf1f7",
    ]

    private init() {
        defaults.register(defaults: defaultValues)
    }

    func value(for key: String) -> Any {
        defaults.object(forKey: key) ?? defaultValues[key] ?? ""
    }

    func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }

    func reset() {
        for key in defaultValues.keys {
            defaults.removeObject(forKey: key)
        }

        defaults.register(defaults: defaultValues)
    }

    func dictinary() -> [String: Any] {
        var result: [String: Any] = [:]

        for key in defaultValues.keys {
            result[key] = value(for: key)
        }

        return result
    }

    func json() -> String {
        guard JSONSerialization.isValidJSONObject(dictinary()),
            let data = try? JSONSerialization.data(withJSONObject: dictinary(), options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return json
    }
}

@MainActor
private final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let store = SettingsStore.shared

    private var window: NSWindow?

    private var controls: [String: NSControl] = [:]

    private weak var settingsScrollView: NSScrollView?

    func show() {
        if let window {
            refreshControls()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()

            DispatchQueue.main.async {
                [weak self] in self?.scrollSettingsToTop()
            }

            if let firstField = controls[SettingKey.fontFamily] as? NSTextField {
                window.makeFirstResponder(firstField)
            }

            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0, width: 620, height: 680
            ), styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "TermX Settings"
        window.minSize = NSSize(width: 520, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let scrollView = NSScrollView()

        settingsScrollView = scrollView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        documentView.addSubview(stack)
        scrollView.documentView = documentView
        window.contentView = scrollView

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
        ])

        //add heading
        addHeading("Terminal", to: stack)

        addTextField(
            title: "Font Family",
            key: SettingKey.fontFamily,
            to: stack
        )

        addNumberField(
            title: "Font Size",
            key: SettingKey.fontSize,
            to: stack
        )

        addNumberField(
            title: "Line height",
            key: SettingKey.lineHeight,
            to: stack
        )

        addPopup(
            title: "Cursor style", key: SettingKey.cursorStyle,
            choices: [
                ("Bar", "bar"),
                ("Block", "block"),
                ("Underline", "underline"),
            ], to: stack)

        addCheckbox(
            title: "Blinking Cursor", key: SettingKey.cursorBlink, to: stack
        )

        addNumberField(title: "Scrollback lines", key: SettingKey.scrollback, to: stack)
        addHeading("Shell", to: stack)
        addTextField(
            title: "Shell path", key: SettingKey.shellPath, placeholder: "Use $SHELL", to: stack)

        addCheckbox(title: "Start as login shell", key: SettingKey.loginShell, to: stack)

        addHeading("Window", to: stack)

        addNumberField(title: "Opacity (0.4-1.0)", key: SettingKey.windowOpacity, to: stack)

        addHeading("Colors", to: stack)

        let colors = [
            ("Foreground", SettingKey.foreground),
            ("Background", SettingKey.background),
            ("Cursor", SettingKey.cursor),
            ("Selection", SettingKey.selection),
            ("Black", SettingKey.black),
            ("Red", SettingKey.red),
            ("Green", SettingKey.green),
            ("Yellow", SettingKey.yellow),
            ("Blue", SettingKey.blue),
            ("Magenta", SettingKey.magenta),
            ("Cyan", SettingKey.cyan),
            ("White", SettingKey.white),
        ]

        for (title, key) in colors {
            addTextField(title: title, key: key, placeholder: "#RRGGBB or #RRGGBBAA", to: stack)
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let resetButton = NSButton(
            title: "Restore Defaults", target: self, action: #selector(resetDefaults))

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeSettings))

        doneButton.keyEquivalent = "\r"

        buttonRow.addArrangedSubview(resetButton)
        buttonRow.addArrangedSubview(doneButton)

        stack.addArrangedSubview(buttonRow)

        self.window = window

        refreshControls()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.async {
            [weak self] in self?.scrollSettingsToTop()
        }

        if let firstField = controls[SettingKey.fontFamily] as? NSTextField {
            window.makeFirstResponder(firstField)
        }

    }

    private func addHeading(_ title: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: title)

        label.font = .systemFont(ofSize: 16, weight: .semibold)

        if !stack.arrangedSubviews.isEmpty {
            stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)
        }

        stack.addArrangedSubview(label)
    }

    private func makeRow(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)

        label.alignment = .right
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 170),
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        return row
    }

    private func addTextField(
        title: String, key: String, placeholder: String? = nil, to stack: NSStackView
    ) {
        let field = NSTextField()
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.placeholderString = placeholder

        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isBezeled = true
        field.isBordered = true
        field.drawsBackground = true
        field.focusRingType = .default

        field.delegate = self
        field.target = self
        field.action = #selector(controlChanged(_:))

        controls[key] = field
        stack.addArrangedSubview(
            makeRow(title: title, control: field)
        )
    }

    private func addNumberField(
        title: String,
        key: String,
        to stack: NSStackView
    ) {
        let field = NSTextField()
        field.identifier = NSUserInterfaceItemIdentifier(key)

        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isBezeled = true
        field.isBordered = true
        field.drawsBackground = true
        field.focusRingType = .default

        field.delegate = self
        field.target = self
        field.action = #selector(controlChanged(_:))

        controls[key] = field
        stack.addArrangedSubview(
            makeRow(title: title, control: field)
        )
    }

    private func addCheckbox(title: String, key: String, to stack: NSStackView) {
        let checkbox =
            NSButton(
                checkboxWithTitle: "", target: self, action: #selector(controlChanged(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(key)

        checkbox.isEnabled = true
        checkbox.allowsMixedState = false

        controls[key] = checkbox
        stack.addArrangedSubview(makeRow(title: title, control: checkbox))
    }

    private func addPopup(
        title: String, key: String, choices: [(String, String)], to stack: NSStackView
    ) {
        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier(key)
        popup.target = self
        popup.action = #selector(controlChanged(_:))

        for choice in choices {
            popup.addItem(withTitle: choice.0)
            popup.lastItem?.representedObject = choice.1
        }
        controls[key] = popup
        stack.addArrangedSubview(makeRow(title: title, control: popup))
    }

    private func refreshControls() {
        for (key, control) in controls {
            let value = store.value(for: key)

            if let popup = control as? NSPopUpButton {
                let selectedValue = value as? String ?? ""

                if let item = popup.itemArray.first(where: {
                    $0.representedObject as? String == selectedValue
                }) {
                    popup.select(item)
                }

            } else if let checkbox = control as? NSButton {
                checkbox.state = (value as? Bool ?? false) ? .on : .off
            } else if let popup = control as? NSPopUpButton {
                let selectedValue = value as? String ?? ""

                if let item = popup.itemArray.first(
                    where: { $0.representedObject as? String == selectedValue }
                ) {
                    popup.select(item)
                }
            } else if let field = control as? NSTextField {
                field.stringValue = String(describing: value)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }

        save(control: field)
    }

    @objc
    private func controlChanged(_ sender: NSControl) {
        save(control: sender)
    }

    private func save(control: NSControl) {
        guard let key = control.identifier?.rawValue else {
            return
        }

        switch control {
        case let popup as NSPopUpButton:
            let value = popup.selectedItem?.representedObject as? String ?? ""
            store.set(value, for: key)
        case let checkbox as NSButton:
            store.set(checkbox.state == .on, for: key)
        case let popup as NSPopUpButton:
            let value = popup.selectedItem?.representedObject as? String ?? ""
            store.set(value, for: key)
        case let field as NSTextField:
            save(field: field, key: key)
        default:
            break
        }
    }

    private func save(field: NSTextField, key: String) {
        switch key {
        case SettingKey.fontSize:
            let value = min(72, max(8, field.doubleValue))

            store.set(value, for: key)
        case SettingKey.lineHeight:
            let value = min(
                3,
                max(0.8, field.doubleValue)
            )

            store.set(value, for: key)

        case SettingKey.scrollback:
            let value = min(
                1_000_000,
                max(100, field.integerValue)
            )

            store.set(value, for: key)

        case SettingKey.windowOpacity:
            let value = min(
                1,
                max(0.4, field.doubleValue)
            )

            store.set(value, for: key)

        default:
            store.set(field.stringValue, for: key)

        }
    }

    @objc
    private func resetDefaults() {
        store.reset()
        refreshControls()
    }

    @objc
    private func closeSettings() {
        window?.close()
    }

    private func scrollSettingsToTop() {

    }
}

@MainActor
private let settingsController =
    SettingsWindowController()

@_cdecl("termx_show_settings")
public func termxShowSettings() -> Double {
    guard Thread.isMainThread else {
        return -1
    }

    return MainActor.assumeIsolated {
        settingsController.show()
        return 0
    }
}

@_cdecl("termx_get_settings")
public func termxGetSettings(
    _ buffer: UnsafeMutablePointer<CChar>?,
    _ capacity: Int32
) -> Int32 {
    guard Thread.isMainThread,
        let buffer,
        capacity > 0
    else {
        return -1
    }

    return MainActor.assumeIsolated {
        let json = SettingsStore.shared.json()
        let bytes = Array(json.utf8)
        let available = Int(capacity) - 1
        let count = min(bytes.count, available)

        for index in 0..<count {
            buffer[index] = CChar(bitPattern: bytes[index])
        }

        buffer[count] = 0
        return Int32(count)
    }
}
