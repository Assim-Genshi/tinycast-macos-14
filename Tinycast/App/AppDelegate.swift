import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Hyper Key's HID-level caps remap outlives the process; give the key back.
        AppCore.shared.hyperKeyTap.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let icon = NSImage(named: "rawLogo") {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Tinycast")
                button.image?.size = NSSize(width: 18, height: 18)
            }
        }

        let appName = Bundle.main.appDisplayName
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open \(appName)", action: #selector(openLauncher), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let clipboardItem = NSMenuItem(title: "Clipboard History", action: #selector(openClipboard), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserDefaultsChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        updateStatusItem()
    }

    @objc private func handleUserDefaultsChange() {
        updateStatusItem()
    }

    private func updateStatusItem() {
        let isInserted = UserDefaults.standard.object(forKey: SettingsKey.showInMenuBar) as? Bool ?? true
        statusItem?.isVisible = isInserted

        if let openItem = statusItem?.menu?.item(at: 0) {
            if let shortcut = AppCore.shared.hotKeys.shortcut(for: .togglePalette) {
                openItem.keyEquivalent = shortcut.keyEquivalent
                openItem.keyEquivalentModifierMask = shortcut.modifierFlags
            } else {
                openItem.keyEquivalent = ""
                openItem.keyEquivalentModifierMask = []
            }
        }
    }

    @objc private func openLauncher() {
        AppCore.shared.showPalette(mode: .launcher)
    }

    @objc private func openClipboard() {
        AppCore.shared.showPalette(mode: .clipboard)
    }

    @objc private func openSettings() {
        AppCore.shared.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
