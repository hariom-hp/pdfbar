import AppKit
import SwiftUI

/// Verification helpers that run without a display server.
enum Headless {

    // MARK: Dump the right-click menu tree

    static func dumpMenu() -> Bool {
        let state = AppState()
        let menu = MenuBuilder.build(state: state) { }

        func walk(_ menu: NSMenu, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            for item in menu.items {
                if item.isSeparatorItem {
                    print("\(indent)───")
                    continue
                }
                let mark = item.isEnabled ? "" : "  (disabled)"
                print("\(indent)\(item.title)\(mark)")
                if let sub = item.submenu { walk(sub, depth: depth + 1) }
            }
        }

        print("Right-click menu\n================")
        walk(menu, depth: 0)

        let toolCount = ToolRegistry.all.filter { !$0.remoteOnly }.count
        let remoteCount = ToolRegistry.all.filter { $0.remoteOnly }.count
        print("\n\(toolCount) native tools, \(remoteCount) server tools")
        return toolCount >= 25
    }

    // MARK: Render the window to PNG

    static func render(toolID: String, to path: String, dark: Bool = true) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        if dark {
            app.appearance = NSAppearance(named: .darkAqua)
        } else {
            app.appearance = NSAppearance(named: .aqua)
        }

        let state = AppState()
        state.select(toolID: toolID)

        let size = NSSize(width: 1000, height: 680)
        let host = NSHostingView(rootView: RootView(state: state))
        host.appearance = app.appearance

        // SwiftUI only completes layout and drawing once it is in a window.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.appearance = app.appearance
        window.contentView = host
        window.setContentSize(size)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        for _ in 0..<40 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let scale: CGFloat = 2
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? png.write(to: URL(fileURLWithPath: path))
        _ = scale
        window.orderOut(nil)
        return true
    }
}
