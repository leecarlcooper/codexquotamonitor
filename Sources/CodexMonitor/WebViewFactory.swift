import WebKit

enum WebViewFactory {
    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        configure(webView)
        return webView
    }

    static func configure(_ webView: WKWebView) {
        webView.customUserAgent = safariUserAgent
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
    }

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
