//
//  MenuBarManager.swift
//  ExpenseReports
//
//  Puts a status item in the menu bar and shows a popover with a finance snapshot.
//

import SwiftUI
import AppKit

class MenuBarManager: NSObject {
    var statusItem: NSStatusItem?
    var popover = NSPopover()

    func setupMenuBar() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "banknote", accessibilityDescription: "Finance")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 300, height: 220)
        popover.behavior = .transient
    }

    func setPopoverContent(_ view: some View) {
        popover.contentViewController = NSHostingController(rootView: view)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
