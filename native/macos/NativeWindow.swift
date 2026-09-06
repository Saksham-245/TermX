import AppKit

@MainActor
private final class TerminalGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private let glassIdentifier = NSUserInterfaceItemIdentifier("TermX.NativeGlass")

@MainActor
private var dragMonitors: [ObjectIdentifier: Any] = [:]

@MainActor
private func getView(
    _ pointer: UnsafeMutableRawPointer
) -> NSView {
    return Unmanaged<NSView>
            .fromOpaque(pointer)
            .takeUnretainedValue()
}

@MainActor
private func measureInset(_ view: NSView) -> CGFloat {
    guard let window = view.window else {
        return -1
    }

    if window.styleMask.contains(.fullScreen) {
        return 0
    }

    let viewBoundsInWindow = view.convert(
        view.bounds,
        to: nil
    )

    return max(
        0,
        viewBoundsInWindow.maxY -
                window.contentLayoutRect.maxY
    ).rounded(.up)
}

@MainActor
private func configureGlass(_ view: NSView) {
    if let existing = view.subviews.first(
        where: { $0.identifier == glassIdentifier }
    ) as? NSGlassEffectView {
        existing.frame = view.bounds
        return
    }

    let glass = TerminalGlassView(frame: view.bounds)

    glass.identifier = glassIdentifier
    glass.autoresizingMask = [.width, .height]
    glass.cornerRadius = 16
    glass.style = .clear

    view.addSubview(
        glass,
        positioned: .below,
        relativeTo: nil
    )
}

@MainActor
private func pointIsInsideWindowButton(
    _ point: NSPoint,
    window: NSWindow
) -> Bool {
    let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]

    for type in buttonTypes {
        guard let button = window.standardWindowButton(type),
              !button.isHidden else {
            continue
        }

        let buttonFrame = button.convert(
            button.bounds,
            to: nil
        )

        // Give the native button a slightly larger click area.
        let hitFrame = buttonFrame.insetBy(
            dx: -4,
            dy: -4
        )

        if hitFrame.contains(point) {
            return true
        }
    }

    return false
}

@MainActor
private func installNativeDragging(
    for window: NSWindow
) {
    let key = ObjectIdentifier(window)

    guard dragMonitors[key] == nil else {
        return
    }

    let monitor = NSEvent.addLocalMonitorForEvents(
        matching: .leftMouseDown
    ) { [weak window] event in
        guard let window,
              event.window === window,
              window.isMovable,
              !window.styleMask.contains(.fullScreen) else {
            return event
        }

        let point = event.locationInWindow

        // contentLayoutRect ends where the native title bar begins.
        let titlebarBottom = window.contentLayoutRect.maxY
        let titlebarTop = window.contentView?.bounds.maxY
                ?? window.frame.height

        guard point.y >= titlebarBottom,
              point.y <= titlebarTop else {
            return event
        }

        // Allow close, minimize and zoom buttons to handle clicks normally.
        if pointIsInsideWindowButton(
               point,
               window: window
           ) {
            return event
        }

        window.performDrag(with: event)

        // The drag was handled by AppKit.
        return nil
    }

    if let monitor {
        dragMonitors[key] = monitor
    }

    NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            if let monitor = dragMonitors.removeValue(
                forKey: key
            ) {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

@MainActor
private func configureWindow(
    _ view: NSView
) -> Double {
    guard let window = view.window else {
        return -1
    }

    window.styleMask.insert(.titled)
    window.styleMask.insert(.fullSizeContentView)

    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = true

    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true

    window.isMovable = true
    window.isMovableByWindowBackground = true

    window.standardWindowButton(
        .closeButton
    )?.isHidden = false

    window.standardWindowButton(
        .miniaturizeButton
    )?.isHidden = false

    window.standardWindowButton(
        .zoomButton
    )?.isHidden = false

    window.contentView?.layoutSubtreeIfNeeded()

    configureGlass(view)
    installNativeDragging(for: window)

    window.invalidateShadow()

    return Double(measureInset(view))
}

@_cdecl("termx_configure")
public func termxConfigure(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        configureWindow(getView(pointer))
    }
}

@_cdecl("termx_top_inset")
public func termxTopInset(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        Double(measureInset(getView(pointer)))
    }
}