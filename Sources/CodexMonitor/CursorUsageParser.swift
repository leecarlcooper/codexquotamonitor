import Foundation

/// Cursor's dashboard endpoint is private; reject missing buckets rather than
/// substituting the combined plan percentage or on-demand spending.
enum CursorUsageParser {
    struct Limits {
        let cursorModels: UsageLimit
        let otherModels: UsageLimit
    }

    static func parseSummary(_ data: Data) throws -> Limits? {
        let summary = try JSONDecoder().decode(Summary.self, from: data)
        guard let plan = summary.individualUsage?.plan,
              let cursor = plan.autoPercentUsed, cursor.isFinite, cursor >= 0,
              let other = plan.apiPercentUsed, other.isFinite, other >= 0,
              let end = summary.billingCycleEnd,
              let reset = parseDate(end)
        else { return nil }
        let resetText = ISO8601DateFormatter().string(from: reset)
        func limit(_ percent: Double) -> UsageLimit {
            let clamped = min(100, percent)
            return UsageLimit(percent: Int(clamped.rounded()), metric: .used,
                              resetText: resetText, precisePercent: clamped)
        }
        return Limits(cursorModels: limit(cursor), otherModels: limit(other))
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    private struct Summary: Decodable {
        let billingCycleEnd: String?
        let individualUsage: IndividualUsage?
    }
    private struct IndividualUsage: Decodable { let plan: Plan? }
    private struct Plan: Decodable {
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }

    // Run in the authenticated dashboard origin. WebKit supplies cookies itself;
    // credentials never leave its data store or get copied into app preferences.
    static let fetchScript = """
    if (location.origin !== 'https://cursor.com') return null;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch('/api/usage-summary', {
        credentials: 'same-origin', cache: 'no-store',
        headers: {Accept: 'application/json'}, signal: controller.signal
      });
      if (!response.ok) return null;
      return await response.text();
    } catch (_) { return null; }
    finally { clearTimeout(timeout); }
    """

    // Fallback reads only the two aggregate rows under Included Usage. It never
    // sums model rows or treats a missing value as zero usage.
    static let dashboardScript = #"""
    (() => {
      const bodyText = document.body ? document.body.innerText : '';
      const headings = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,div,span,p'));
      const heading = headings.find(el => (el.textContent || '').trim() === 'Included Usage');
      let section = heading;
      while (section && !(/Cursor Models/.test(section.innerText || '') && /Other Models/.test(section.innerText || ''))) {
        section = section.parentElement;
      }
      const text = section ? section.innerText : '';
      const datePattern = /([A-Za-z]{3,9}\s+\d{1,2},\s+\d{4})\s*[-–—]\s*([A-Za-z]{3,9}\s+\d{1,2},\s+\d{4})/;
      const cycle = text.match(datePattern);
      // A date-only dashboard cannot establish the billing hour. Keep the
      // date text for display parsing; prefer the API's exact timestamp.
      const resetDate = cycle ? new Date(cycle[2]) : null;
      const resetText = resetDate && !isNaN(resetDate) ? resetDate.toISOString().replace(/\.\d{3}Z$/, 'Z') : '';
      function bucket(label) {
        if (!section || !cycle) return null;
        const elements = Array.from(section.querySelectorAll('td,th,div,span,p,strong'));
        const labels = elements.filter(el => (el.textContent || '').trim() === label);
        for (const el of labels) {
          let row = el.parentElement;
          while (row && row !== section) {
            const rowText = row.innerText || '';
            if (rowText.includes(label === 'Cursor Models' ? 'Other Models' : 'Cursor Models')) break;
            const matches = Array.from(rowText.matchAll(/(\d+(?:[.,]\d+)?)\s*%/g));
            if (matches.length === 1) {
              const value = Number(matches[0][1].replace(',', '.'));
              return {percent: Math.round(Math.min(100, value)), precisePercent: Math.min(100, value), metric: 'used', resetText};
            }
            if (matches.length > 1) break;
            row = row.parentElement;
          }
        }
        return null;
      }
      const fiveHour = bucket('Cursor Models');
      const weekly = bucket('Other Models');
      const hasUsage = !!(fiveHour && weekly);
      const loggedOut = /sign in|log in|continue with google|continue with github/i.test(bodyText);
      return JSON.stringify({fiveHour, weekly, hasUsage, authHint: !hasUsage && loggedOut ? 'loggedOut' : null});
    })();
    """#
}
