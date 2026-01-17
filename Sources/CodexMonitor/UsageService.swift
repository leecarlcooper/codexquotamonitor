import Foundation
import WebKit
import Combine

struct UsageLimit: Codable {
    let percentRemaining: Int
    let resetText: String
}

final class UsageService: NSObject, ObservableObject {
    static let usageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    @Published var fiveHourLimit: UsageLimit?
    @Published var weeklyLimit: UsageLimit?
    @Published var lastUpdated: Date?
    @Published var authState: AuthState = .unknown
    @Published var errorMessage: String?

    enum AuthState {
        case unknown
        case authenticated
        case needsLogin
    }

    var statusSummary: String {
        if authState == .needsLogin {
            return "Codex usage (sign in required)"
        }
        let five = fiveHourLimit?.percentRemaining
        let weekly = weeklyLimit?.percentRemaining
        let fiveText = five != nil ? "5h: \(five!)%" : "5h: --"
        let weeklyText = weekly != nil ? "Weekly: \(weekly!)%" : "Weekly: --"
        return "Codex usage (\(fiveText), \(weeklyText))"
    }

    private(set) var webView: WKWebView
    private var timer: Timer?
    private var isLoading = false
    private var parseAttempts = 0
    private let maxParseAttempts = 20
    private var isInteractiveSession = false
    private var missingCount = 0
    private let maxMissingCount = 3

    override init() {
        self.webView = WebViewFactory.makeWebView()
        super.init()
        webView.navigationDelegate = self
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh(force: Bool = false) {
        guard !isLoading else { return }
        if isInteractiveSession && !force { return }
        isLoading = true
        parseAttempts = 0
        let request = URLRequest(url: Self.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        DispatchQueue.main.async {
            self.webView.load(request)
        }
    }

    func pollCurrentPage() {
        guard !isLoading else { return }
        isLoading = true
        parseAttempts = 0
        attemptParse()
    }

    func beginInteractiveSession() {
        isInteractiveSession = true
    }

    func endInteractiveSession() {
        isInteractiveSession = false
    }

    private func handleParseResult(_ result: Any?) {
        defer { isLoading = false }
        guard let jsonString = result as? String, let data = jsonString.data(using: .utf8) else {
            authState = .needsLogin
            errorMessage = "Unable to parse usage"
            return
        }

        do {
            let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
            if payload.hasUsage {
                authState = .authenticated
                fiveHourLimit = payload.fiveHour
                weeklyLimit = payload.weekly
                lastUpdated = Date()
                errorMessage = nil
                missingCount = 0
            } else {
                let hint = payload.authHint ?? ""
                if hint == "loggedOut" {
                    authState = .needsLogin
                    errorMessage = "Sign in required."
                    missingCount = 0
                    return
                }

                missingCount += 1
                if parseAttempts < maxParseAttempts {
                    parseAttempts += 1
                    isLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.attemptParse()
                    }
                    return
                }
                if parseAttempts >= maxParseAttempts {
                    if missingCount >= maxMissingCount && fiveHourLimit == nil && weeklyLimit == nil {
                        authState = .unknown
                        errorMessage = "Usage data not found."
                    } else {
                        authState = authState == .authenticated ? .authenticated : .unknown
                        errorMessage = "Loading usage…"
                    }
                } else {
                    authState = authState == .authenticated ? .authenticated : .unknown
                    errorMessage = "Loading usage…"
                }
            }
        } catch {
            authState = .needsLogin
            errorMessage = "Failed to decode usage"
        }
    }

    private func attemptParse() {
        webView.evaluateJavaScript(Self.parserScript) { [weak self] result, error in
            if let error {
                self?.errorMessage = error.localizedDescription
                self?.authState = .needsLogin
                self?.isLoading = false
                return
            }
            self?.handleParseResult(result)
        }
    }
}

extension UsageService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        attemptParse()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
    }
}

private struct UsagePayload: Codable {
    let fiveHour: UsageLimit?
    let weekly: UsageLimit?
    let hasUsage: Bool
    let authHint: String?
}

private extension UsageService {
    static let parserScript: String = """
    (() => {
      function escapeRegExp(str) {
        return str.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
      }

      function isCardText(text, label, otherLabels) {
        const lower = text.toLowerCase();
        if (!lower.includes(label)) return false;
        if (!/\\\\d+\\\\s*%/.test(lower)) return false;
        if (!lower.includes('remaining')) return false;
        for (const other of otherLabels) {
          if (lower.includes(other)) return false;
        }
        return true;
      }

      function findCardText(label, otherLabels) {
        const elements = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,div,span,p'));
        const labelLower = label.toLowerCase();
        let best = null;
        for (const el of elements) {
          const text = (el.textContent || '').toLowerCase();
          if (!text.includes(labelLower)) continue;
          let node = el;
          while (node) {
            const nodeText = node.innerText || '';
            if (isCardText(nodeText, labelLower, otherLabels)) {
              if (!best || nodeText.length < best.length) {
                best = nodeText;
              }
              break;
            }
            node = node.parentElement;
          }
        }
        return best;
      }

      function extract(labelVariants, otherLabels) {
        for (const label of labelVariants) {
          const cardText = findCardText(label, otherLabels);
          if (!cardText) continue;
          const labelRegex = new RegExp(escapeRegExp(label) + \"[\\\\s\\\\S]*?(\\\\d+)\\\\s*%\\\\s*remaining\", \"i\");
          const percentMatch = cardText.match(labelRegex) || cardText.match(/(\\\\d+)\\\\s*%/);
          const resetMatch = cardText.match(/Resets\\\\s+([^\\\\n]+)/i);
          if (percentMatch) {
            return {
              percentRemaining: parseInt(percentMatch[1], 10),
              resetText: resetMatch ? resetMatch[1].trim() : ''
            };
          }
        }
        return null;
      }

      function extractByLines(text, labelVariants) {
        const lines = text.split(/\\n+/).map(line => line.trim()).filter(Boolean);
        for (const label of labelVariants) {
          const labelLower = label.toLowerCase();
          for (let i = 0; i < lines.length; i++) {
            if (!lines[i].toLowerCase().includes(labelLower)) continue;
            let percentLine = null;
            let resetLine = null;
            for (let j = i + 1; j < Math.min(lines.length, i + 10); j++) {
              if (!percentLine && /\\d+\\s*%/.test(lines[j])) {
                percentLine = lines[j];
              }
              if (!resetLine && /^resets\\b/i.test(lines[j])) {
                resetLine = lines[j];
              }
            }
            if (percentLine) {
              const percentMatch = percentLine.match(/(\\d+)\\s*%/);
              if (percentMatch) {
                const resetText = resetLine ? resetLine.replace(/^Resets\\s*/i, '').trim() : '';
                return { percentRemaining: parseInt(percentMatch[1], 10), resetText };
              }
            }
          }
        }
        return null;
      }

      const fiveHourLabels = ['5 hour usage limit', '5-hour usage limit', '5 hour limit'];
      const weeklyLabels = ['weekly usage limit', 'weekly limit'];

      const fiveHour = extract(fiveHourLabels, weeklyLabels);
      const weekly = extract(weeklyLabels, fiveHourLabels);

      const bodyText = document.body ? (document.body.innerText || '') : '';
      const fiveHourFallback = fiveHour || extractByLines(bodyText, fiveHourLabels);
      const weeklyFallback = weekly || extractByLines(bodyText, weeklyLabels);

      const hasUsage = !!(fiveHourFallback || weeklyFallback);
      let authHint = null;
      if (!hasUsage) {
        const authText = bodyText.toLowerCase();
        const loggedOutSignals = [
          'log in',
          'sign in',
          'sign up',
          'create account',
          'continue with google',
          'continue with apple'
        ];
        if (loggedOutSignals.some(signal => authText.includes(signal))) {
          authHint = 'loggedOut';
        }
      }
      return JSON.stringify({ fiveHour: fiveHourFallback, weekly: weeklyFallback, hasUsage, authHint });
    })();
    """
}
