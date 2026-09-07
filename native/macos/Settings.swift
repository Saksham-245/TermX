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

    func show() {
        if let window {
            refreshControls()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let documentView = NSView()
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
            key: SettingKey.fontSize
        )
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
        field.delegate = self
        field.target = self
        field.action = #selector(controlChanged(_:))

        controls[key] = field
        stack.addArrangedSubview(
            makeRow(title: title, control: field)
        )
    }

    private func refreshControls() {
        for (key, control) in controls {
            let value = store.value(for: key)

            if let checkbox = control as? NSButton {
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
}
