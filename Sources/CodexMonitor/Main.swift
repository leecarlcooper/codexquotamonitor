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
    private let settingsStore = SettingsStore()
    private let quotaStatusStore = QuotaStatusStore.shared
    private var cancellables: Set<AnyCancellable> = []
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
        let codexPublisher = usageStatusPublisher(for: codexUsageService)
        let claudePublisher = usageStatusPublisher(for: claudeUsageService)

        settingsStore.$selectedUsageSource
            .combineLatest(codexPublisher)
            .combineLatest(claudePublisher)
            .receive(on: RunLoop.main)
            .sink { [weak self] selectionAndCodex, claude in
                guard let self else { return }
                self.publishWidgetSnapshot()
                let (selection, codex) = selectionAndCodex
                switch selection {
                case .codex:
                    let (five, weekly, authState, _, _) = codex
                    let signedIn = authState == .authenticated
                    self.statusItem.button?.image = MenuBarIconRenderer.render(
                        fiveHourPercent: five?.percentRemaining,
                        weeklyPercent: weekly?.percentRemaining,
                        signedIn: signedIn,
                        palette: .codex
                    )
                    self.statusItem.button?.toolTip = self.codexUsageService.statusSummary
                case .claude:
                    let (five, weekly, authState, _, _) = claude
                    let signedIn = authState == .authenticated
                    self.statusItem.button?.image = MenuBarIconRenderer.render(
                        fiveHourPercent: five?.percentRemaining,
                        weeklyPercent: weekly?.percentRemaining,
                        signedIn: signedIn,
                        palette: .claude
                    )
                    self.statusItem.button?.toolTip = self.claudeUsageService.statusSummary
                }

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
        QuotaProductSnapshot(
            product: product,
            shortTitle: shortTitle,
            weeklyTitle: weeklyTitle,
            shortLimit: service.fiveHourLimit.map { limit in
                QuotaLimitSnapshot(percentRemaining: limit.percentRemaining, resetText: limit.resetText)
            },
            weeklyLimit: service.weeklyLimit.map { limit in
                QuotaLimitSnapshot(percentRemaining: limit.percentRemaining, resetText: limit.resetText)
            },
            authState: widgetAuthState(for: service.authState),
            errorMessage: service.errorMessage,
            lastUpdated: service.lastUpdated
        )
    }

    private var selectedQuotaProduct: QuotaProduct {
        switch settingsStore.selectedUsageSource {
        case .codex:
            return .codex
        case .claude:
            return .claude
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
            claudeService: claudeUsageService
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

    private func logoutAllAccounts() {
        guard !isLoggingOut else { return }
        isLoggingOut = true

        codexUsageService.resetForLogout()
        claudeUsageService.resetForLogout()

        claudeLoginWindowController?.close()
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
