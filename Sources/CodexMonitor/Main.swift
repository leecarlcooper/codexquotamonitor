import Cocoa
import Combine
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
struct CodexMonitorMain {
    static func main() {
        if let exitCode = QuotaStatusCommand.runIfRequested() {
            exit(exitCode)
        }

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
    private let cursorUsageService = UsageService(configuration: .cursor)
    private let settingsStore = SettingsStore()
    private let quotaStatusStore = QuotaStatusStore.shared
    private var cancellables: Set<AnyCancellable> = []
    private var claudeLoginWindowController: LoginWindowController?
    private var cursorLoginWindowController: LoginWindowController?
    private var isLoggingOut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        bindUsageUpdates()
        settingsStore.applyStartup()
        codexUsageService.startPolling()
        claudeUsageService.startPolling()
        cursorUsageService.startPolling()
        observeSystemWake()
    }

    /// Timers don't fire while the Mac sleeps, so without this the first reading
    /// after wake can be stale (showing e.g. 99% when the limit has fully reset).
    private func observeSystemWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        // Small delay so the network is back before the WebView reloads.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.codexUsageService.refresh(force: true)
            self?.claudeUsageService.refresh(force: true)
            self?.cursorUsageService.refresh(force: true)
        }
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
        popover.contentSize = NSSize(width: 380, height: 700)

        let view = PopoverView(
            usageService: codexUsageService,
            claudeUsageService: claudeUsageService,
            cursorUsageService: cursorUsageService,
            settings: settingsStore,
            onSignIn: { [weak self] in self?.showCodexLoginWindow() },
            onClaudeSignIn: { [weak self] in self?.showClaudeLoginWindow() },
            onCursorSignIn: { [weak self] in self?.showCursorLoginWindow() },
            onRefresh: { [weak self] in
                self?.codexUsageService.refresh(force: true)
                self?.claudeUsageService.refresh(force: true)
                self?.cursorUsageService.refresh(force: true)
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
        settingsStore.$selectedUsageSource
            .combineLatest(usageStatusPublisher(for: codexUsageService))
            .combineLatest(usageStatusPublisher(for: claudeUsageService))
            .combineLatest(usageStatusPublisher(for: cursorUsageService))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.publishWidgetSnapshot()
                let service: UsageService
                let palette: UsageBarPalette
                switch self.settingsStore.selectedUsageSource {
                case .codex: service = self.codexUsageService; palette = .codex
                case .claude: service = self.claudeUsageService; palette = .claude
                case .cursor: service = self.cursorUsageService; palette = .cursor
                }
                self.statusItem.button?.image = MenuBarIconRenderer.render(
                    fiveHourPercent: service.fiveHourLimit?.percentRemaining,
                    weeklyPercent: service.weeklyLimit?.percentRemaining,
                    signedIn: service.authState == .authenticated,
                    palette: palette
                )
                self.statusItem.button?.toolTip = service.statusSummary
                self.writeQuotaStatusSnapshot()
            }
            .store(in: &cancellables)
    }

    private func publishWidgetSnapshot() {
        let snapshot = QuotaWidgetSnapshot(
            codex: makeProductSnapshot(
                product: .codex,
                service: codexUsageService,
                shortTitle: "5 hour limit",
                weeklyTitle: "Weekly limit"
            ),
            claude: makeProductSnapshot(
                product: .claude,
                service: claudeUsageService,
                shortTitle: "Current session",
                weeklyTitle: "Weekly limits"
            ),
            selectedProduct: selectedQuotaProduct,
            cursor: makeProductSnapshot(product: .cursor, service: cursorUsageService,
                                        shortTitle: "Cursor Models", weeklyTitle: "Other Models"),
            savedAt: Date()
        ).preservingLastKnownValues(from: QuotaWidgetStore.load())
        QuotaWidgetStore.save(snapshot)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: QuotaWidgetStore.widgetKind)
#endif
    }

    private func makeProductSnapshot(
        product: QuotaProduct,
        service: UsageService,
        shortTitle: String,
        weeklyTitle: String
    ) -> QuotaProductSnapshot {
        let lastUpdated = service.lastUpdated
        let hasRecentData = lastUpdated.map {
            Date().timeIntervalSince($0) <= QuotaWidgetSnapshot.maxPreservedValueAge
        } ?? false
        let shortLimit: QuotaLimitSnapshot?
        if hasRecentData, let limit = service.fiveHourLimit {
            shortLimit = QuotaLimitSnapshot(percentRemaining: limit.percentRemaining, resetText: limit.resetText,
                                           precisePercentRemaining: limit.precisePercent.map { _ in limit.precisePercentRemaining })
        } else {
            shortLimit = nil
        }
        let weeklyLimit: QuotaLimitSnapshot?
        if hasRecentData, let limit = service.weeklyLimit {
            weeklyLimit = QuotaLimitSnapshot(percentRemaining: limit.percentRemaining, resetText: limit.resetText,
                                           precisePercentRemaining: limit.precisePercent.map { _ in limit.precisePercentRemaining })
        } else {
            weeklyLimit = nil
        }

        return QuotaProductSnapshot(
            product: product,
            shortTitle: shortTitle,
            weeklyTitle: weeklyTitle,
            shortLimit: shortLimit,
            weeklyLimit: weeklyLimit,
            authState: widgetAuthState(for: service.authState),
            errorMessage: service.errorMessage,
            lastUpdated: lastUpdated
        )
    }

    private var selectedQuotaProduct: QuotaProduct {
        switch settingsStore.selectedUsageSource {
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .cursor:
            return .cursor
        }
    }

    private func widgetAuthState(for authState: UsageService.AuthState) -> QuotaAuthState {
        switch authState {
        case .unknown:
            return .unknown
        case .authenticated:
            return .authenticated
        case .needsLogin:
            return .needsLogin
        }
    }

    private func usageStatusPublisher(
        for service: UsageService
    ) -> AnyPublisher<(UsageLimit?, UsageLimit?, UsageService.AuthState, Date?, String?), Never> {
        Publishers.CombineLatest4(
            service.$fiveHourLimit,
            service.$weeklyLimit,
            service.$authState,
            service.$lastUpdated
        )
        .combineLatest(service.$errorMessage)
        .map { state, errorMessage in
            (state.0, state.1, state.2, state.3, errorMessage)
        }
        .eraseToAnyPublisher()
    }

    private func writeQuotaStatusSnapshot() {
        let snapshot = QuotaStatusSnapshot(
            selectedUsageSource: settingsStore.selectedUsageSource,
            codexService: codexUsageService,
            claudeService: claudeUsageService,
            cursorService: cursorUsageService
        )

        do {
            try quotaStatusStore.write(snapshot)
        } catch {
            NSLog("Failed to write quota status snapshot: \(error.localizedDescription)")
        }
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
        cursorUsageService.pollCurrentPage()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
    }

    private func closePopover() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }

    private func showCodexLoginWindow() {
        codexUsageService.resumeCodexAccount()
        if codexUsageService.authState != .authenticated {
            let alert = NSAlert()
            alert.messageText = "Connect your Codex account"
            alert.informativeText = "This monitor uses your Codex CLI ChatGPT account. Install Codex CLI if needed, run codex login in Terminal, then click Refresh. No API key is needed."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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

    private func showCursorLoginWindow() {
        if cursorLoginWindowController == nil {
            cursorUsageService.beginInteractiveSession()
            cursorLoginWindowController = LoginWindowController(
                webView: cursorUsageService.webView,
                url: cursorUsageService.usageURL,
                title: cursorUsageService.loginWindowTitle,
                onClose: { [weak self] in
                    guard let self else { return }
                    self.cursorLoginWindowController = nil
                    self.cursorUsageService.endInteractiveSession()
                    if !self.isLoggingOut { self.cursorUsageService.refresh(force: true) }
                }
            )
        }
        cursorLoginWindowController?.showWindow(nil)
        cursorLoginWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func logoutAllAccounts() {
        guard !isLoggingOut else { return }
        isLoggingOut = true

        codexUsageService.resetForLogout()
        claudeUsageService.resetForLogout()
        cursorUsageService.resetForLogout()

        claudeLoginWindowController?.close()
        claudeLoginWindowController = nil
        cursorLoginWindowController?.close()
        cursorLoginWindowController = nil

        WebViewFactory.clearWebsiteData { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoggingOut = false
                self.codexUsageService.refresh(force: true)
                self.claudeUsageService.refresh(force: true)
                self.cursorUsageService.refresh(force: true)
            }
        }
    }
}
