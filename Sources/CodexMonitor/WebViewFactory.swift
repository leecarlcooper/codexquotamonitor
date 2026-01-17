import WebKit

enum WebViewFactory {
    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: config)
    }
}
