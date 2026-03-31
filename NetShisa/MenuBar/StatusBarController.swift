import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let appState: AppState
    private var cancellable: AnyCancellable?

    init(appState: AppState) {
        self.appState = appState

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient

        let popoverView = PopoverView(appState: appState)
        popover.contentViewController = NSHostingController(rootView: popoverView)

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
            updateIcon(status: .good)
        }

        // Observe status changes
        cancellable = appState.$overallStatus.sink { [weak self] status in
            DispatchQueue.main.async {
                self?.updateIcon(status: status)
            }
        }
    }

    private func updateIcon(status: OverallStatus) {
        guard let button = statusItem.button else { return }

        let tintColor: NSColor
        switch status {
        case .good:     tintColor = .systemGreen
        case .degraded: tintColor = .systemYellow
        case .down:     tintColor = .systemRed
        }

        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        button.contentTintColor = tintColor
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
