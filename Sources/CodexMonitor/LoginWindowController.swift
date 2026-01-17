import Cocoa
import WebKit

final class LoginWindowController: NSWindowController {
    private let webView: WKWebView
    private let onClose: () -> Void

    init(webView: WKWebView, url: URL, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to ChatGPT"
        window.center()
        window.contentView = webView

        super.init(window: window)
        window.delegate = self
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
