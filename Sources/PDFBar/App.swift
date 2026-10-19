import AppKit
import SwiftUI

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController!
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        windowController = MainWindowController(state: state)
        statusController = StatusItemController(state: state) { [weak self] in
            self?.windowController.show()
        }
        statusController.install()

        // A second launch just asks this instance to show its window.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.pdfbar.app.show"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.windowController.show()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// MARK: - Status item

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let state: AppState
    private let openWindow: () -> Void

    init(state: AppState, openWindow: @escaping () -> Void) {
        self.state = state
        self.openWindow = openWindow
        super.init()
    }

    func install() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "PDFBar")
            image?.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
            button.toolTip = "PDFBar — click to open, right-click for every tool"
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRight {
            showMenu()
        } else {
            openWindow()
        }
    }

    private func showMenu() {
        let menu = MenuBuilder.build(state: state) { [weak self] in
            self?.openWindow()
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}

// MARK: - Right-click menu

enum MenuBuilder {

    static func build(state: AppState, openWindow: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "PDFBar", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for category in ToolCategory.allCases {
            let tools = ToolRegistry.tools(in: category)
            guard !tools.isEmpty else { continue }
            let parent = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil)
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for tool in tools {
                let item = NSMenuItem(title: tool.name, action: #selector(MenuActionHandler.fire(_:)), keyEquivalent: "")
                item.target = MenuActionHandler.shared
                item.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
                item.representedObject = tool.id
                item.toolTip = tool.summary
                item.isEnabled = true
                submenu.addItem(item)
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open PDFBar…", action: #selector(MenuActionHandler.openMain(_:)), keyEquivalent: "")
        open.target = MenuActionHandler.shared
        menu.addItem(open)

        let reveal = NSMenuItem(title: "Open output folder", action: #selector(MenuActionHandler.revealOutput(_:)), keyEquivalent: "")
        reveal.target = MenuActionHandler.shared
        menu.addItem(reveal)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PDFBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        MenuActionHandler.shared.state = state
        MenuActionHandler.shared.openWindow = openWindow
        return menu
    }
}

/// Target for menu items. Menu items are transient, so the handler is a singleton
/// that the builder re-points at the live state each time the menu is shown.
final class MenuActionHandler: NSObject {
    static let shared = MenuActionHandler()
    var state: AppState?
    var openWindow: (() -> Void)?

    @objc func fire(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let state else { return }
        state.select(toolID: id)
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openMain(_ sender: NSMenuItem) {
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func revealOutput(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(AppState.defaultOutputDir)
    }
}

// MARK: - Main window

final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: RootView(state: state))
            let win = NSWindow(contentViewController: host)
            win.title = "PDFBar"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.setContentSize(NSSize(width: 1000, height: 680))
            win.minSize = NSSize(width: 860, height: 560)
            win.center()
            win.delegate = self
            win.isReleasedWhenClosed = false
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
