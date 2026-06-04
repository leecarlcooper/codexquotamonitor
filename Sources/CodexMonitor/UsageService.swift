import Foundation
import WebKit
import Combine

struct UsageLimit: Codable {
    let percent: Int
    let metric: UsageMetric
    let resetText: String

    var percentRemaining: Int {
        metric.remainingPercent(from: percent)
    }
}

final class UsageService: NSObject, ObservableObject {
    struct Configuration {
        let productName: String
        let usageURL: URL
        let loginWindowTitle: String
        let defaultMetric: UsageMetric
    }

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

    let configuration: Configuration

    var usageURL: URL { configuration.usageURL }
    var loginWindowTitle: String { configuration.loginWindowTitle }

    var statusSummary: String {
        if authState == .needsLogin {
            return "\(configuration.productName) usage (sign in required)"
        }
        let fiveText: String
        if let fiveHourLimit {
            fiveText = "5h: \(fiveHourLimit.percentRemaining)% remaining"
        } else {
            fiveText = "5h: --"
        }

        let weeklyText: String
        if let weeklyLimit {
            weeklyText = "Weekly: \(weeklyLimit.percentRemaining)% remaining"
        } else {
            weeklyText = "Weekly: --"
        }
        return "\(configuration.productName) usage (\(fiveText), \(weeklyText))"
    }

    private(set) var webView: WKWebView
    private var timer: Timer?
    private var isLoading = false
    private var parseAttempts = 0
    private let maxParseAttempts = 20
    private var isInteractiveSession = false
    private var missingCount = 0
    private let maxMissingCount = 3

    init(configuration: Configuration) {
        self.configuration = configuration
        self.webView = WebViewFactory.makeWebView()
        super.init()
        webView.navigationDelegate = self
    }

    func resetForLogout() {
        endInteractiveSession()
        webView.stopLoading()
        isLoading = false
        parseAttempts = 0
        missingCount = 0
        fiveHourLimit = nil
        weeklyLimit = nil
        lastUpdated = nil
        errorMessage = nil
        authState = .needsLogin
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
        let request = URLRequest(url: configuration.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
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
            recordTransientError("Unable to parse usage")
            return
        }

        do {
            let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
            if payload.hasUsage {
                authState = .authenticated
                fiveHourLimit = payload.fiveHour.map { limit in
                    UsageLimit(percent: limit.percent, metric: limit.metric ?? configuration.defaultMetric, resetText: limit.resetText)
                }
                weeklyLimit = payload.weekly.map { limit in
                    UsageLimit(percent: limit.percent, metric: limit.metric ?? configuration.defaultMetric, resetText: limit.resetText)
                }
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
            recordTransientError("Failed to decode usage")
        }
    }

    private func attemptParse() {
        webView.evaluateJavaScript(Self.parserScript) { [weak self] result, error in
            if let error {
                self?.recordTransientError(error.localizedDescription)
                self?.isLoading = false
                return
            }
            self?.handleParseResult(result)
        }
    }

    private func recordTransientError(_ message: String) {
        errorMessage = message
        if authState == .authenticated || authState == .needsLogin {
            return
        }
        authState = .unknown
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
    let fiveHour: ParsedUsageLimit?
    let weekly: ParsedUsageLimit?
    let hasUsage: Bool
    let authHint: String?
}

private struct ParsedUsageLimit: Codable {
    let percent: Int
    let metric: UsageMetric?
    let resetText: String
}

private extension UsageService {
    static let parserScript: String = """
    (() => {
      function escapeRegExp(str) {
        return str.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
      }

      function extractPercentAndMetric(text) {
        const afterMatch = text.match(/\\b(\\d+)\\s*%\\s*[()\\s:,-]*\\s*(remaining|used)\\b/i);
        if (afterMatch) {
          return { percent: parseInt(afterMatch[1], 10), metric: afterMatch[2].toLowerCase() };
        }
        const beforeMatch = text.match(/\\b(remaining|used)\\b\\s*[()\\s:,-]*\\s*(\\d+)\\s*%\\b/i);
        if (beforeMatch) {
          return { percent: parseInt(beforeMatch[2], 10), metric: beforeMatch[1].toLowerCase() };
        }
        return null;
      }

      function metricForPercent(text, percent) {
        const afterPattern = new RegExp(\"\\\\b\" + percent + \"\\\\s*%\\\\s*[()\\\\s:,-]*\\\\s*(remaining|used)\\\\b\", \"i\");
        const afterMatch = text.match(afterPattern);
        if (afterMatch) return afterMatch[1].toLowerCase();

        const beforePattern = new RegExp(\"\\\\b(remaining|used)\\\\b\\\\s*[()\\\\s:,-]*\\\\s*\" + percent + \"\\\\s*%\\\\b\", \"i\");
        const beforeMatch = text.match(beforePattern);
        if (beforeMatch) return beforeMatch[1].toLowerCase();
        return null;
      }

      function isCardText(text, label, otherLabels) {
        const lower = text.toLowerCase();
        if (!lower.includes(label)) return false;
        if (!/\\\\d+\\\\s*%/.test(lower)) return false;
        if (!lower.includes('remaining') && !lower.includes('used')) return false;
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

      function extractResetTextFromLines(lines) {
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          const cleaned = line.replace(/^[•\\-]\\s*/, '');
          const match = cleaned.match(/^(?:next\\s+)?resets?\\b\\s*:?\\s*(.*)/i);
          if (match) {
            const value = (match[1] || '').trim();
            if (value) {
              return value;
            }
            const next = lines[i + 1];
            if (next) {
              return next.trim();
            }
          }
        }
        return '';
      }

      function extract(labelVariants, otherLabels) {
        for (const label of labelVariants) {
          const labelLower = label.toLowerCase();
          const cardText = findCardText(label, otherLabels);
          if (!cardText) continue;
          const labelIndex = cardText.toLowerCase().indexOf(labelLower);
          const searchText = labelIndex >= 0 ? cardText.slice(labelIndex) : cardText;
          const percentMetricMatch = extractPercentAndMetric(searchText) || extractPercentAndMetric(cardText);
          const labelRegex = new RegExp(escapeRegExp(label) + \"[\\\\s\\\\S]*?(\\\\d+)\\\\s*%\", \"i\");
          const percentMatch = cardText.match(labelRegex) || cardText.match(/(\\\\d+)\\\\s*%/);
          let resetText = '';
          const lines = cardText.split(/\\n+/).map(line => line.trim()).filter(Boolean);
          resetText = extractResetTextFromLines(lines);
          if (!resetText) {
            const resetMatch = cardText.match(/(?:next\\\\s+)?resets?\\\\b\\\\s*:?\\\\s*([^\\\\n]+)/i);
            resetText = resetMatch ? resetMatch[1].trim() : '';
          }
          if (!resetText) {
            const fallbackLine = lines.find(line => {
              const lowerLine = line.toLowerCase();
              if (lowerLine.includes(labelLower)) return false;
              if (/\\d+\\s*%/.test(lowerLine)) return false;
              if (lowerLine.includes('remaining')) return false;
              return true;
            });
            resetText = fallbackLine ? fallbackLine.trim() : '';
          }
          if (percentMetricMatch || percentMatch) {
            const rawPercent = percentMetricMatch ? percentMetricMatch.percent : parseInt(percentMatch[1], 10);
            const metric = percentMetricMatch ? percentMetricMatch.metric : metricForPercent(cardText, rawPercent);
            return {
              percent: rawPercent,
              metric,
              resetText
            };
          }
        }
        return null;
      }

      function extractByLines(text, labelVariants, otherLabels) {
        const lines = text.split(/\\n+/).map(line => line.trim()).filter(Boolean);
        const otherLabelLowers = otherLabels.map(label => label.toLowerCase());
        for (const label of labelVariants) {
          const labelLower = label.toLowerCase();
          for (let i = 0; i < lines.length; i++) {
            if (!lines[i].toLowerCase().includes(labelLower)) continue;
            let percentLine = null;
            let percentIndex = null;
            let resetLine = null;
            for (let j = i + 1; j < Math.min(lines.length, i + 10); j++) {
              const lowerLine = lines[j].toLowerCase();
              if (otherLabelLowers.some(other => lowerLine.includes(other))) {
                break;
              }
              if (!percentLine && /\\d+\\s*%/.test(lines[j])) {
                percentLine = lines[j];
                percentIndex = j;
              }
              if (!resetLine && /\\breset(s)?\\b/i.test(lines[j])) {
                resetLine = lines[j];
              }
              if (!resetLine && percentIndex != null && j > percentIndex) {
                if (!/\\d+\\s*%/.test(lines[j]) && !lowerLine.includes('remaining')) {
                  resetLine = lines[j];
                }
              }
            }
            if (percentLine) {
              const percentMetricMatch = extractPercentAndMetric(percentLine);
              const percentOnlyMatch = percentMetricMatch ? null : percentLine.match(/(\\d+)\\s*%/);
              if (percentMetricMatch || percentOnlyMatch) {
                const rawPercent = percentMetricMatch ? percentMetricMatch.percent : parseInt(percentOnlyMatch[1], 10);
                let resetText = '';
                if (resetLine) {
                  resetText = extractResetTextFromLines([resetLine]);
                  if (!resetText) {
                    resetText = resetLine.replace(/^(?:next\\s+)?resets?\\s*:?\\s*/i, '').trim();
                  }
                }
                const context = [lines[i], percentLine, resetLine || ''].join(' ');
                const metric = percentMetricMatch ? percentMetricMatch.metric : metricForPercent(context, rawPercent);
                return { percent: rawPercent, metric, resetText };
              }
            }
          }
        }
        return null;
      }

      const fiveHourLabels = [
        '5 hour usage limit',
        '5-hour usage limit',
        '5 hour limit',
        'current session'
      ];
      const weeklyLabels = [
        'weekly usage limit',
        'weekly limit',
        'weekly limits'
      ];

      const fiveHour = extract(fiveHourLabels, weeklyLabels);
      const weekly = extract(weeklyLabels, fiveHourLabels);

      const bodyText = document.body ? (document.body.innerText || '') : '';
      const fiveHourFallback = fiveHour || extractByLines(bodyText, fiveHourLabels, weeklyLabels);
      const weeklyFallback = weekly || extractByLines(bodyText, weeklyLabels, fiveHourLabels);

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

extension UsageService.Configuration {
    static let codex = UsageService.Configuration(
        productName: "Codex",
        usageURL: URL(string: "https://chatgpt.com/codex/settings/usage")!,
        loginWindowTitle: "Sign in to ChatGPT",
        defaultMetric: .remaining
    )

    static let claude = UsageService.Configuration(
        productName: "Claude",
        usageURL: URL(string: "https://claude.ai/settings/usage")!,
        loginWindowTitle: "Sign in to Claude",
        defaultMetric: .used
    )
}
