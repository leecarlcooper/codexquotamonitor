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
    private let codexClient = CodexRateLimitsClient()
    private var generation = 0
    private var codexPaused = UserDefaults.standard.bool(forKey: "codexMonitoringPaused")
    var usesCodexAccount: Bool { configuration.productName == "Codex" }
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
        generation += 1
        codexClient.cancel()
        if usesCodexAccount {
            codexPaused = true
            UserDefaults.standard.set(true, forKey: "codexMonitoringPaused")
        }
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
        if usesCodexAccount {
            refreshCodexAccount()
            return
        }
        generation += 1
        isLoading = true
        parseAttempts = 0
        let request = URLRequest(url: configuration.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        DispatchQueue.main.async {
            self.webView.load(request)
        }
    }

    func resumeCodexAccount() {
        codexPaused = false
        UserDefaults.standard.set(false, forKey: "codexMonitoringPaused")
        refresh(force: true)
    }

    private func refreshCodexAccount() {
        guard !codexPaused else {
            authState = .needsLogin
            errorMessage = "Codex monitoring disconnected. Click Connect Codex to resume."
            return
        }
        isLoading = true
        codexClient.fetch { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case .success(let response):
                guard let limits = response.limits else { return }
                self.fiveHourLimit = limits.fiveHour
                self.weeklyLimit = limits.weekly
                self.authState = .authenticated
                self.lastUpdated = Date()
                self.errorMessage = nil
            case .failure(let error):
                // Keep last-known data and its original timestamp on transient failures.
                self.recordTransientError(error.localizedDescription)
            }
        }
    }

    func pollCurrentPage() {
        if usesCodexAccount {
            if lastUpdated.map({ Date().timeIntervalSince($0) > 60 }) ?? true { refresh() }
            return
        }
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
        isLoading = false
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
                    let currentGeneration = generation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self, self.generation == currentGeneration else { return }
                        self.attemptParse()
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
        guard !usesCodexAccount else { return }
        let currentGeneration = generation
        webView.evaluateJavaScript(Self.parserScript) { [weak self] result, error in
            guard self?.generation == currentGeneration else { return }
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

      function roundPercent(raw) {
        return Math.round(parseFloat(String(raw).replace(',', '.')));
      }

      function extractPercentAndMetric(text) {
        const afterMatch = text.match(/\\b(\\d+(?:[.,]\\d+)?)\\s*%\\s*[()\\s:,-]*\\s*(remaining|used)\\b/i);
        if (afterMatch) {
          return { percent: roundPercent(afterMatch[1]), metric: afterMatch[2].toLowerCase() };
        }
        const beforeMatch = text.match(/\\b(remaining|used)\\b\\s*[()\\s:,-]*\\s*(\\d+(?:[.,]\\d+)?)\\s*%/i);
        if (beforeMatch) {
          return { percent: roundPercent(beforeMatch[2]), metric: beforeMatch[1].toLowerCase() };
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
        if (!/\\d+\\s*%/.test(lower)) return false;
        if (!lower.includes('remaining') && !lower.includes('used')) return false;
        for (const other of otherLabels) {
          if (lower.includes(other)) return false;
        }
        return true;
      }

      function hasResetText(text) {
        return /\\bresets?\\b/i.test(text);
      }

      function findCardText(label, otherLabels) {
        const elements = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,div,span,p'));
        const labelLower = label.toLowerCase();
        let best = null;
        let bestWithReset = null;
        for (const el of elements) {
          const text = (el.textContent || '').toLowerCase();
          if (!text.includes(labelLower)) continue;
          let node = el;
          let candidate = null;
          while (node) {
            const nodeText = node.innerText || '';
            if (isCardText(nodeText, labelLower, otherLabels)) {
              candidate = nodeText;
              // Keep expanding to ancestors until the card's reset line is included.
              // isCardText stops the expansion before another card's text bleeds in.
              if (hasResetText(nodeText)) break;
            } else if (candidate) {
              break;
            }
            node = node.parentElement;
          }
          if (!candidate) continue;
          if (!best || candidate.length < best.length) {
            best = candidate;
          }
          if (hasResetText(candidate) && (!bestWithReset || candidate.length < bestWithReset.length)) {
            bestWithReset = candidate;
          }
        }
        return bestWithReset || best;
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
          const labelRegex = new RegExp(escapeRegExp(label) + \"[\\\\s\\\\S]*?(\\\\d+(?:[.,]\\\\d+)?)\\\\s*%\", \"i\");
          const percentMatch = cardText.match(labelRegex) || cardText.match(/(\\d+(?:[.,]\\d+)?)\\s*%/);
          let resetText = '';
          const lines = cardText.split(/\\n+/).map(line => line.trim()).filter(Boolean);
          resetText = extractResetTextFromLines(lines);
          if (!resetText) {
            const resetMatch = cardText.match(/(?:next\\s+)?resets?\\b\\s*:?\\s*([^\\n]+)/i);
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
            const rawPercent = percentMetricMatch ? percentMetricMatch.percent : roundPercent(percentMatch[1]);
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
            const lineLower = lines[i].toLowerCase();
            if (!lineLower.includes(labelLower)) continue;
            if (otherLabelLowers.some(other => lineLower.includes(other))) continue;
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
              const percentOnlyMatch = percentMetricMatch ? null : percentLine.match(/(\\d+(?:[.,]\\d+)?)\\s*%/);
              if (percentMetricMatch || percentOnlyMatch) {
                const rawPercent = percentMetricMatch ? percentMetricMatch.percent : roundPercent(percentOnlyMatch[1]);
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
      // Model-specific cards (e.g. \"GPT-5.3-Codex-Spark 5 hour usage limit\") repeat the
      // generic labels, so exclude them to keep the primary account limits.
      const excludedLabels = ['spark', 'code review'];

      const fiveHour = extract(fiveHourLabels, weeklyLabels.concat(excludedLabels));
      const weekly = extract(weeklyLabels, fiveHourLabels.concat(excludedLabels));

      // The card extractor can find percent but miss the reset line (it lives outside
      // the matched node on some layouts); borrow resetText from the line-based parser.
      function withResetFallback(primary, fallback) {
        if (!primary) return fallback;
        if (primary.resetText || !fallback || !fallback.resetText) return primary;
        return { percent: primary.percent, metric: primary.metric || fallback.metric, resetText: fallback.resetText };
      }

      const bodyText = document.body ? (document.body.innerText || '') : '';
      const fiveHourFallback = withResetFallback(fiveHour, extractByLines(bodyText, fiveHourLabels, weeklyLabels.concat(excludedLabels)));
      const weeklyFallback = withResetFallback(weekly, extractByLines(bodyText, weeklyLabels, fiveHourLabels.concat(excludedLabels)));

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
