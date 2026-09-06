import AppKit

@MainActor
private final class TerminalGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private let glassIdentifier = NSUserInterfaceItemIdentifier("TermX.NativeGlass")
private let terminalTabbingIdentifier = "com.termx.terminal-sessions"

@MainActor
private var cachedInsets: [ObjectIdentifier: CGFloat] = [:]

@MainActor
private var dragMonitors: [ObjectIdentifier: Any] = [:]

@MainActor
private func getView(_ pointer: UnsafeMutableRawPointer) -> NSView {
    return Unmanaged<NSView>
            .fromOpaque(pointer)
            .takeUnretainedValue()
}

@MainActor
private func measureInset(
    _ view: NSView
) -> CGFloat {
    guard let window = view.window else {
        return -1
    }

    let key = ObjectIdentifier(window)

    if window.styleMask.contains(.fullScreen) {
        cachedInsets[key] = 0
        return 0
    }

    window.contentView?.layoutSubtreeIfNeeded()

    let viewBoundsInWindow = view.convert(
        view.bounds,
        to: nil
    )

    let measuredInset = max(
        0,
        viewBoundsInWindow.maxY -
                window.contentLayoutRect.maxY
    ).rounded(.up)

    /*
     An inactive AppKit tab can temporarily report zero even though
     its native title bar and tab bar are still present. Do not let
     that transient value erase the last correct measurement.
    */
    if measuredInset > 0 {
        cachedInsets[key] = measuredInset
        return measuredInset
    }

    if let cachedInset = cachedInsets[key],
       cachedInset > 0 {
        return cachedInset
    }

    return measuredInset
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
private func pointIsInsideWindowButton(_ point: NSPoint,
                                       window: NSWindow) -> Bool {
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
        guard
        let window,
        event.window === window,
        window.isMovable,
        !window.styleMask.contains(.fullScreen)
        else {
            return event
        }

        let point = event.locationInWindow
        let windowTop = window.contentView?.bounds.maxY
                ?? window.frame.height

        /*
         Keep dragging inside the empty strip above the native tabs.
         Do not include the tab capsules themselves.
        */
        let dragStripHeight: CGFloat = 18
        let dragStripBottom = windowTop - dragStripHeight

        guard point.y >= dragStripBottom,
              point.y <= windowTop else {
            // AppKit receives tab, traffic-light and terminal clicks.
            return event
        }

        /*
         Preserve double-clicking the title bar. AppKit handles the
         user's configured "double-click title bar" preference.
        */
        if event.clickCount > 1 {
            return event
        }

        window.performDrag(with: event)
        return nil
    }

    guard let monitor else {
        return
    }

    dragMonitors[key] = monitor

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
            
            cachedInsets.removeValue(forKey: key)
        }
    }
}

@MainActor
private func configureWindow(_ view: NSView) -> Double {
    guard let window = view.window else {
        return -1
    }

    window.styleMask.insert(.titled)
    window.styleMask.insert(.fullSizeContentView)
    window.tabbingIdentifier = terminalTabbingIdentifier

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

@MainActor
private func getWindow(_ pointer: UnsafeMutableRawPointer) -> NSWindow? {
    return getView(pointer).window
}

@_cdecl("termx_configure")
public func termxConfigure(_ pointer: UnsafeMutableRawPointer?) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        configureWindow(getView(pointer))
    }
}

@_cdecl("termx_top_inset")
public func termxTopInset(_ pointer: UnsafeMutableRawPointer?) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        Double(measureInset(getView(pointer)))
    }
}

@_cdecl("termx_add_tab")
public func termxAddTab(_ parentPointer: UnsafeMutableRawPointer?,
                        _ childPointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread,
          let parentPointer,
          let childPointer
    else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let parentWindow = getWindow(parentPointer),
              let childWindow = getWindow(childPointer),
              parentWindow !== childWindow else {
            return -1
        }
        parentWindow.addTabbedWindow(childWindow, ordered: .above)

        return 0
    }
}

@_cdecl("termx_select_next_tab")
public func termxSelectNextTab(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let window = getWindow(pointer) else {
            return -1
        }

        window.selectNextTab(nil)
        return 0
    }
}

@_cdecl("termx_select_previous_tab")
public func termxSelectPreviousTab(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let window = getWindow(pointer) else {
            return -1
        }

        window.selectPreviousTab(nil)
        return 0
    }
}

@_cdecl("termx_show_tab_overview")
public func termxShowTabOverview(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let window = getWindow(pointer) else {
            return -1
        }

        window.toggleTabOverview(nil)
        return 0
    }
}

@_cdecl("termx_move_tab_to_new_window")
public func termxMoveTabToNewWindow(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let window = getWindow(pointer) else {
            return -1
        }

        window.moveTabToNewWindow(nil)
        return 0
    }
}

@_cdecl("termx_merge_all_windows")
public func termxMergeAllWindows(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let window = getWindow(pointer) else {
            return -1
        }

        window.mergeAllWindows(nil)
        return 0
    }
}

@_cdecl("termx_toggle_tab_bar")
public func termxToggleTabBar(
    _ pointer: UnsafeMutableRawPointer?
) -> Double {
    guard Thread.isMainThread, let pointer else {
        return -1
    }

    return MainActor.assumeIsolated {
        guard let window = getWindow(pointer) else {
            return -1
        }

        window.toggleTabBar(nil)
        return 0
    }
}