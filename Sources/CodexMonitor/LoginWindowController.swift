import Cocoa
import WebKit

final class LoginWindowController: NSWindowController {
    private let webView: WKWebView
    private let onClose: () -> Void
    private var popupControllers: [NSWindowController] = []

    init(webView: WKWebView, url: URL, title: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = webView

        super.init(window: window)
        window.delegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        onClose()
    }
}

extension LoginWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        configuration.websiteDataStore = webView.configuration.websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        WebViewFactory.configure(popupWebView)
        popupWebView.uiDelegate = self

        let frame = NSRect(x: 0, y: 0, width: 800, height: 700)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Authentication"
        window.center()
        window.contentView = popupWebView

        let controller = NSWindowController(window: window)
        popupControllers.append(controller)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let index = popupControllers.firstIndex(where: { $0.window?.contentView === webView }) {
            popupControllers.remove(at: index)
        }
    }
}
