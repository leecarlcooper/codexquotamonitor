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
    private let codexUsageService = UsageService(configuration: .codex)
    private let claudeUsageService = UsageService(configuration: .claude)
    private let settingsStore = SettingsStore()
    private var cancellables: Set<AnyCancellable> = []
    private var codexLoginWindowController: LoginWindowController?
    private var claudeLoginWindowController: LoginWindowController?
    private var isLoggingOut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        bindUsageUpdates()
        settingsStore.applyStartup()
        codexUsageService.startPolling()
        claudeUsageService.startPolling()
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
        popover.contentSize = NSSize(width: 340, height: 700)

        let view = PopoverView(
            usageService: codexUsageService,
            claudeUsageService: claudeUsageService,
            settings: settingsStore,
            onSignIn: { [weak self] in self?.showCodexLoginWindow() },
            onClaudeSignIn: { [weak self] in self?.showClaudeLoginWindow() },
            onRefresh: { [weak self] in
                self?.codexUsageService.refresh(force: true)
                self?.claudeUsageService.refresh(force: true)
            },
            onLogout: { [weak self] in
                self?.logoutAllAccounts()
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.closePopover()
            }
        }
    }

    private func bindUsageUpdates() {
        let codexPublisher = codexUsageService.$fiveHourLimit
            .combineLatest(codexUsageService.$weeklyLimit, codexUsageService.$authState)
        let claudePublisher = claudeUsageService.$fiveHourLimit
            .combineLatest(claudeUsageService.$weeklyLimit, claudeUsageService.$authState)

        settingsStore.$selectedUsageSource
            .combineLatest(codexPublisher, claudePublisher)
            .receive(on: RunLoop.main)
            .sink { [weak self] selection, codex, claude in
                guard let self else { return }
                switch selection {
                case .codex:
                    let (five, weekly, authState) = codex
                    let signedIn = authState == .authenticated
                    self.statusItem.button?.image = MenuBarIconRenderer.render(
                        fiveHourPercent: five?.percent,
                        weeklyPercent: weekly?.percent,
                        signedIn: signedIn,
                        palette: .codex
                    )
                    self.statusItem.button?.toolTip = self.codexUsageService.statusSummary
                case .claude:
                    let (five, weekly, authState) = claude
                    let signedIn = authState == .authenticated
                    self.statusItem.button?.image = MenuBarIconRenderer.render(
                        fiveHourPercent: five?.percent,
                        weeklyPercent: weekly?.percent,
                        signedIn: signedIn,
                        palette: .claude
                    )
                    self.statusItem.button?.toolTip = self.claudeUsageService.statusSummary
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
        codexUsageService.pollCurrentPage()
        claudeUsageService.pollCurrentPage()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
    }

    private func closePopover() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }

    private func showCodexLoginWindow() {
        if codexLoginWindowController == nil {
            codexUsageService.beginInteractiveSession()
            codexLoginWindowController = LoginWindowController(
                webView: codexUsageService.webView,
                url: codexUsageService.usageURL,
                title: codexUsageService.loginWindowTitle,
                onClose: { [weak self] in
                    guard let self else { return }
                    self.codexLoginWindowController = nil
                    self.codexUsageService.endInteractiveSession()
                    if !self.isLoggingOut {
                        self.codexUsageService.refresh(force: true)
                    }
                }
            )
        }
        codexLoginWindowController?.showWindow(nil)
        codexLoginWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showClaudeLoginWindow() {
        if claudeLoginWindowController == nil {
            claudeUsageService.beginInteractiveSession()
            claudeLoginWindowController = LoginWindowController(
                webView: claudeUsageService.webView,
                url: claudeUsageService.usageURL,
                title: claudeUsageService.loginWindowTitle,
                onClose: { [weak self] in
                    guard let self else { return }
                    self.claudeLoginWindowController = nil
                    self.claudeUsageService.endInteractiveSession()
                    if !self.isLoggingOut {
                        self.claudeUsageService.refresh(force: true)
                    }
                }
            )
        }
        claudeLoginWindowController?.showWindow(nil)
        claudeLoginWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func logoutAllAccounts() {
        guard !isLoggingOut else { return }
        isLoggingOut = true

        codexUsageService.resetForLogout()
        claudeUsageService.resetForLogout()

        codexLoginWindowController?.close()
        claudeLoginWindowController?.close()
        codexLoginWindowController = nil
        claudeLoginWindowController = nil

        WebViewFactory.clearWebsiteData { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoggingOut = false
                self.codexUsageService.refresh(force: true)
                self.claudeUsageService.refresh(force: true)
            }
        }
    }
}
