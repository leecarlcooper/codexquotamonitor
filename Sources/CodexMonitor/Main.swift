import Cocoa
import Combine
import SwiftUI

@main
struct CodexMonitorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var eventMonitor: EventMonitor?
    private let usageService = UsageService()
    private let settingsStore = SettingsStore()
    private let alertCoordinator = UsageAlertCoordinator()
    private var cancellables: Set<AnyCancellable> = []
    private var loginWindowController: LoginWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        bindUsageUpdates()
        settingsStore.applyStartup()
        usageService.startPolling()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = MenuBarIconRenderer.render(fiveHourPercent: nil, weeklyPercent: nil, signedIn: false)
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "Codex usage"
        }
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 320)

        let view = PopoverView(
            usageService: usageService,
            settings: settingsStore,
            onSignIn: { [weak self] in self?.showLoginWindow() },
            onRefresh: { [weak self] in self?.usageService.refresh(force: true) }
        )
        popover.contentViewController = NSHostingController(rootView: view)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.closePopover()
            }
        }
    }

    private func bindUsageUpdates() {
        usageService.$fiveHourLimit
            .combineLatest(usageService.$weeklyLimit)
            .receive(on: RunLoop.main)
            .sink { [weak self] five, weekly in
                guard let self else { return }
                let fivePercent = five?.percentRemaining
                let weeklyPercent = weekly?.percentRemaining
                let signedIn = self.usageService.authState == .authenticated
                self.statusItem.button?.image = MenuBarIconRenderer.render(
                    fiveHourPercent: fivePercent,
                    weeklyPercent: weeklyPercent,
                    signedIn: signedIn
                )
                self.statusItem.button?.toolTip = self.usageService.statusSummary
                if self.settingsStore.notificationsEnabled {
                    self.alertCoordinator.handle(fiveHour: five, weekly: weekly)
                }
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        usageService.pollCurrentPage()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
    }

    private func closePopover() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }

    private func showLoginWindow() {
        if loginWindowController == nil {
            usageService.beginInteractiveSession()
            loginWindowController = LoginWindowController(
                webView: usageService.webView,
                url: UsageService.usageURL,
                onClose: { [weak self] in
                    self?.loginWindowController = nil
                    self?.usageService.endInteractiveSession()
                    self?.usageService.refresh(force: true)
                }
            )
        }
        loginWindowController?.showWindow(nil)
        loginWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
