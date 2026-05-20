import AppKit
import Foundation
import SwiftUI
import WebKit

enum UsageProviderID: String, CaseIterable, Identifiable {
    case cursor
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    var shortName: String {
        switch self {
        case .cursor: return "CU"
        case .codex: return "CX"
        case .claude: return "CC"
        }
    }

    var systemImage: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .codex: return "terminal"
        case .claude: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .cursor: return Color(red: 0.38, green: 0.45, blue: 0.98)
        case .codex: return Color(red: 0.16, green: 0.68, blue: 0.44)
        case .claude: return Color(red: 0.93, green: 0.48, blue: 0.20)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .cursor: return NSColor.systemIndigo
        case .codex: return NSColor.systemGreen
        case .claude: return NSColor.systemOrange
        }
    }

    var dashboardURL: URL? {
        switch self {
        case .cursor:
            return URL(string: "https://cursor.com/dashboard?tab=usage")
        case .codex:
            return nil
        case .claude:
            return URL(string: "https://claude.ai/settings/usage")
        }
    }
}

enum UsageLoadState: Equatable {
    case idle
    case ready
    case needsLogin
    case failed(String)

    var errorMessage: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }
}

struct ProviderUsageSnapshot: Identifiable, Equatable {
    let id: UsageProviderID
    var usedLabel: String
    var limitLabel: String
    var detailLabel: String
    var resetLabel: String
    var percentageUsed: Double?
    var lastUpdated: Date?
    var state: UsageLoadState
    var isRefreshing: Bool

    static func placeholder(for provider: UsageProviderID) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            id: provider,
            usedLabel: "No data",
            limitLabel: "",
            detailLabel: "Refresh to load",
            resetLabel: "",
            percentageUsed: nil,
            lastUpdated: nil,
            state: .idle,
            isRefreshing: false
        )
    }
}

final class UsageDashboardService: NSObject, ObservableObject {
    @Published private(set) var snapshots: [ProviderUsageSnapshot]
    @Published private(set) var isRefreshing = false

    private let cursorFetcher = CursorUsageFetcher()
    private let claudeFetcher = ClaudeUsageFetcher()
    private let localUsageFetcher = LocalUsageFetcher()

    override init() {
        snapshots = UsageProviderID.allCases.map { ProviderUsageSnapshot.placeholder(for: $0) }
        super.init()
    }

    func snapshot(for provider: UsageProviderID) -> ProviderUsageSnapshot? {
        snapshots.first { $0.id == provider }
    }

    func refreshAll(completion: @escaping () -> Void) {
        guard !isRefreshing else { return }

        AppLog.write("Starting refresh for all providers")
        isRefreshing = true
        snapshots = snapshots.map { snapshot in
            var updated = snapshot
            updated.isRefreshing = true
            return updated
        }

        let group = DispatchGroup()

        group.enter()
        cursorFetcher.fetchUsage { [weak self] snapshot in
            self?.updateSnapshot(snapshot)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = self?.localUsageFetcher.fetchCodexUsage()
                ?? ProviderUsageSnapshot.placeholder(for: .codex)
            DispatchQueue.main.async {
                self?.updateSnapshot(snapshot)
                group.leave()
            }
        }

        group.enter()
        claudeFetcher.fetchUsage { [weak self] snapshot in
            if let snapshot {
                self?.updateSnapshot(snapshot)
            } else {
                self?.updateSnapshot(ProviderUsageSnapshot(
                    id: .claude,
                    usedLabel: "Unavailable",
                    limitLabel: "",
                    detailLabel: "Could not read Claude usage page",
                    resetLabel: "",
                    percentageUsed: nil,
                    lastUpdated: Date(),
                    state: .failed("Could not read Claude usage page"),
                    isRefreshing: false
                ))
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.isRefreshing = false
            self?.snapshots = self?.snapshots.map { snapshot in
                var updated = snapshot
                updated.isRefreshing = false
                return updated
            } ?? []
            let summary = self?.snapshots
                .map { "\($0.id.displayName)=\($0.usedLabel) \($0.limitLabel)" }
                .joined(separator: "; ") ?? "no snapshots"
            AppLog.write("Completed refresh: \(summary)")
            completion()
        }
    }

    private func updateSnapshot(_ snapshot: ProviderUsageSnapshot) {
        guard let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) else {
            snapshots.append(snapshot)
            return
        }
        snapshots[index] = snapshot
    }
}

private final class CursorUsageFetcher: NSObject {
    private var webView: WKWebView?

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: config)
    }

    func fetchUsage(completion: @escaping (ProviderUsageSnapshot) -> Void) {
        guard let webView else {
            AppLog.write("Cursor fetch failed: no web session")
            completion(Self.errorSnapshot("Could not create Cursor web session"))
            return
        }

        AppLog.write("Cursor fetch started")
        webView.load(URLRequest(url: URL(string: "https://cursor.com")!))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let script = """
                (function() {
                    var xhr = new XMLHttpRequest();
                    xhr.open('GET', 'https://cursor.com/api/usage-summary', false);
                    xhr.withCredentials = true;
                    try {
                        xhr.send();
                        if (xhr.status === 401 || xhr.status === 403) {
                            return JSON.stringify({ error: 'login_required' });
                        }
                        if (xhr.status < 200 || xhr.status >= 300) {
                            return JSON.stringify({ error: 'Cursor returned HTTP ' + xhr.status });
                        }
                        return xhr.responseText;
                    } catch(e) {
                        return JSON.stringify({ error: e.message });
                    }
                })()
            """

            self?.webView?.evaluateJavaScript(script) { result, error in
                if let jsonString = result as? String {
                    completion(Self.parseAPIResponse(jsonString))
                } else {
                    completion(Self.errorSnapshot(error?.localizedDescription ?? "Failed to fetch Cursor usage"))
                }
            }
        }
    }

    private static func parseAPIResponse(_ jsonString: String) -> ProviderUsageSnapshot {
        guard let data = jsonString.data(using: .utf8) else {
            return errorSnapshot("Invalid Cursor response")
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return loginSnapshot()
            }

            if let error = json["error"] as? String {
                return error == "login_required" ? loginSnapshot() : errorSnapshot(error)
            }

            let individualUsage = json["individualUsage"] as? [String: Any]
            let overall = individualUsage?["overall"] as? [String: Any]
            let used = intValue(overall?["used"]) ?? 0
            let limit = intValue(overall?["limit"]) ?? 0
            let percentage = limit > 0 ? (Double(used) / Double(limit)) * 100.0 : nil
            let plan = json["membershipType"] as? String ?? "unknown plan"
            let billingEnd = formattedDate(from: json["billingCycleEnd"] as? String) ?? "Unknown reset"

            return ProviderUsageSnapshot(
                id: .cursor,
                usedLabel: dollars(fromCents: used),
                limitLabel: "\(dollars(fromCents: limit)) limit",
                detailLabel: "\(plan.capitalized) plan",
                resetLabel: "Resets \(billingEnd)",
                percentageUsed: percentage,
                lastUpdated: Date(),
                state: .ready,
                isRefreshing: false
            )
        } catch {
            return loginSnapshot()
        }
    }

    private static func loginSnapshot() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            id: .cursor,
            usedLabel: "Login needed",
            limitLabel: "",
            detailLabel: "Open Cursor dashboard",
            resetLabel: "",
            percentageUsed: nil,
            lastUpdated: nil,
            state: .needsLogin,
            isRefreshing: false
        )
    }

    private static func errorSnapshot(_ message: String) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            id: .cursor,
            usedLabel: "Unavailable",
            limitLabel: "",
            detailLabel: "Cursor usage failed",
            resetLabel: "",
            percentageUsed: nil,
            lastUpdated: Date(),
            state: .failed(message),
            isRefreshing: false
        )
    }
}

private final class ClaudeUsageFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((ProviderUsageSnapshot?) -> Void)?
    private var didComplete = false

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
    }

    func fetchUsage(completion: @escaping (ProviderUsageSnapshot?) -> Void) {
        guard let url = UsageProviderID.claude.dashboardURL,
              let webView else {
            completion(nil)
            return
        }

        AppLog.write("Claude web usage fetch started")
        self.completion = completion
        didComplete = false
        webView.load(URLRequest(url: url))

        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            self?.finishIfNeeded(snapshot: nil, reason: "Claude web usage fetch timed out")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak webView] in
            let script = """
                (function() {
                    var chunks = [];
                    function add(value) {
                        if (value && typeof value === 'string') chunks.push(value);
                    }
                    add(document.body && document.body.innerText);
                    add(document.documentElement && document.documentElement.innerText);
                    add(document.body && document.body.textContent);
                    add(document.documentElement && document.documentElement.textContent);
                    Array.from(document.querySelectorAll('[aria-label], [title], [data-testid], [data-test-id]')).forEach(function(el) {
                        add(el.getAttribute('aria-label'));
                        add(el.getAttribute('title'));
                        add(el.getAttribute('data-testid'));
                        add(el.getAttribute('data-test-id'));
                    });
                    add(document.documentElement && document.documentElement.outerHTML);
                    return chunks.join(' ');
                })()
            """

            webView?.evaluateJavaScript(script) { result, error in
                if let error {
                    self?.finishIfNeeded(snapshot: nil, reason: "Claude web usage JS failed: \(error.localizedDescription)")
                    return
                }

                guard let text = result as? String else {
                    self?.finishIfNeeded(snapshot: nil, reason: "Claude web usage returned no text")
                    return
                }

                if let snapshot = Self.parseUsageText(text) {
                    self?.finishIfNeeded(snapshot: snapshot, reason: "Claude web usage parsed")
                } else if Self.looksLoggedOut(text) {
                    self?.finishIfNeeded(snapshot: Self.loginSnapshot(), reason: "Claude web usage needs login")
                } else {
                    self?.finishIfNeeded(snapshot: nil, reason: "Claude web usage could not parse page text")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishIfNeeded(snapshot: nil, reason: "Claude web usage navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishIfNeeded(snapshot: nil, reason: "Claude web usage provisional navigation failed: \(error.localizedDescription)")
    }

    private func finishIfNeeded(snapshot: ProviderUsageSnapshot?, reason: String) {
        guard !didComplete else { return }
        didComplete = true
        AppLog.write(reason)
        completion?(snapshot)
        completion = nil
    }

    private static func parseUsageText(_ text: String) -> ProviderUsageSnapshot? {
        let normalizedText = normalizeUsageText(text)
        let patterns = [
            #"\$([0-9,]+(?:\.[0-9]{2})?).{0,80}\bof\b.{0,80}\$([0-9,]+(?:\.[0-9]{2})?).{0,80}\bspent\b"#,
            #"\$([0-9,]+(?:\.[0-9]{2})?)\s*/\s*\$([0-9,]+(?:\.[0-9]{2})?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(normalizedText.startIndex..., in: normalizedText)
            guard let match = regex.firstMatch(in: normalizedText, options: [], range: range),
                  let usedRange = Range(match.range(at: 1), in: normalizedText),
                  let limitRange = Range(match.range(at: 2), in: normalizedText),
                  let used = dollarsToDouble(String(normalizedText[usedRange])),
                  let limit = dollarsToDouble(String(normalizedText[limitRange])),
                  limit > 0 else {
                continue
            }

            return usageSnapshot(used: used, limit: limit, resetLabel: resetLabel(from: normalizedText))
        }

        if normalizedText.localizedCaseInsensitiveContains("spent"),
           let spentRange = normalizedText.range(of: "spent", options: .caseInsensitive) {
            let prefix = String(normalizedText[..<spentRange.lowerBound])
            let amountPattern = #"\$([0-9,]+(?:\.[0-9]{2})?)"#
            if let regex = try? NSRegularExpression(pattern: amountPattern) {
                let range = NSRange(prefix.startIndex..., in: prefix)
                let matches = regex.matches(in: prefix, options: [], range: range)

                if matches.count >= 2,
                   let usedRange = Range(matches[matches.count - 2].range(at: 1), in: prefix),
                   let limitRange = Range(matches[matches.count - 1].range(at: 1), in: prefix),
                   let used = dollarsToDouble(String(prefix[usedRange])),
                   let limit = dollarsToDouble(String(prefix[limitRange])),
                   limit > 0 {
                    return usageSnapshot(used: used, limit: limit, resetLabel: resetLabel(from: normalizedText))
                }
            }
        }

        AppLog.write("Claude usage text parse failed. Text sample: \(String(normalizedText.prefix(500)))")
        return nil
    }

    private static func usageSnapshot(used: Double, limit: Double, resetLabel: String?) -> ProviderUsageSnapshot {
        let percentage = used / limit * 100
        return ProviderUsageSnapshot(
            id: .claude,
            usedLabel: dollars(from: used),
            limitLabel: "\(dollars(from: limit)) limit",
            detailLabel: "Monthly limit",
            resetLabel: resetLabel ?? estimatedMonthlyResetLabel(),
            percentageUsed: percentage,
            lastUpdated: Date(),
            state: .ready,
            isRefreshing: false
        )
    }

    private static func normalizeUsageText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resetLabel(from text: String) -> String? {
        let datePattern = #"([A-Z][a-z]{2,8}\s+\d{1,2}(?:,\s*\d{4})?)"#
        let patterns = [
            #"\bResets?\s+(?:on\s+)?"# + datePattern,
            #"\bRenews?\s+(?:on\s+)?"# + datePattern,
            #"\bReset date\s*"# + datePattern,
            #"\bNext reset\s*"# + datePattern
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let dateRange = Range(match.range(at: 1), in: text),
                  let date = parseDisplayDate(String(text[dateRange])) else {
                continue
            }

            return "Resets \(formattedDisplayDate(date))"
        }

        return nil
    }

    private static func estimatedMonthlyResetLabel() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: components) ?? now
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
        return "Resets \(formattedDisplayDate(nextMonth))"
    }

    private static func looksLoggedOut(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("log in") ||
            lowercased.contains("sign in") ||
            lowercased.contains("continue with google")
    }

    private static func loginSnapshot() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            id: .claude,
            usedLabel: "Login needed",
            limitLabel: "",
            detailLabel: "Open Claude usage",
            resetLabel: "",
            percentageUsed: nil,
            lastUpdated: nil,
            state: .needsLogin,
            isRefreshing: false
        )
    }
}

private final class LocalUsageFetcher {
    private let codexDailySoftCap = 10_000_000
    private let claudeDailySoftCap = 5_000_000
    private let codexWeeklySpendLimit = 125.0

    func fetchCodexUsage() -> ProviderUsageSnapshot {
        let databasePath = "\(NSHomeDirectory())/.codex/state_5.sqlite"
        guard FileManager.default.fileExists(atPath: databasePath) else {
            AppLog.write("Codex fetch failed: database not found at \(databasePath)")
            return localErrorSnapshot(for: .codex, message: "Codex state database was not found")
        }

        do {
            let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            let startOfWeek = weekInterval?.start ?? Calendar.current.startOfDay(for: Date())
            let startOfWeekMs = Int(startOfWeek.timeIntervalSince1970 * 1000)
            let query = """
                select id, rollout_path, coalesce(model, ''), coalesce(updated_at_ms, 0)
                from threads
                where created_at_ms >= \(startOfWeekMs);
            """
            let output = try runSQLite(databasePath: databasePath, query: query)
            let rows = output
                .split(separator: "\n")
                .map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }

            var totalSpend = 0.0
            var totalTokens = 0
            var pricedThreadCount = 0
            var updatedMs = 0.0

            for row in rows {
                guard row.count >= 4 else { continue }
                let rolloutPath = row[1]
                let model = row[2]
                updatedMs = max(updatedMs, Double(row[3]) ?? 0)

                guard let usage = readCodexTokenUsage(from: rolloutPath) else { continue }

                let rate = codexPricingRate(for: model)
                totalSpend += usage.spend(using: rate)
                totalTokens += usage.totalTokens
                pricedThreadCount += 1
            }

            let updatedAt = updatedMs > 0 ? Date(timeIntervalSince1970: updatedMs / 1000.0) : Date()
            let percentage = codexWeeklySpendLimit > 0 ? totalSpend / codexWeeklySpendLimit * 100 : nil
            let weeklyResetDate = weekInterval?.end ?? Date()

            return ProviderUsageSnapshot(
                id: .codex,
                usedLabel: dollars(from: totalSpend),
                limitLabel: "\(dollars(from: codexWeeklySpendLimit)) weekly",
                detailLabel: "\(abbreviatedNumber(totalTokens)) tokens, \(pricedThreadCount) session\(pricedThreadCount == 1 ? "" : "s")",
                resetLabel: "Resets \(formattedDisplayDate(weeklyResetDate))",
                percentageUsed: percentage,
                lastUpdated: updatedAt,
                state: .ready,
                isRefreshing: false
            )
        } catch {
            AppLog.write("Codex fetch failed: \(error.localizedDescription)")
            return localErrorSnapshot(for: .codex, message: error.localizedDescription)
        }
    }

    func fetchClaudeUsage() -> ProviderUsageSnapshot {
        let projectsURL = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
        guard FileManager.default.fileExists(atPath: projectsURL.path) else {
            AppLog.write("Claude fetch failed: projects folder not found at \(projectsURL.path)")
            return localErrorSnapshot(for: .claude, message: "Claude projects folder was not found")
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        var totalTokens = 0
        var messageCount = 0
        var newestDate: Date?

        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            AppLog.write("Claude fetch failed: could not enumerate projects folder")
            return localErrorSnapshot(for: .claude, message: "Could not read Claude projects folder")
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
               values.isRegularFile != true || (values.contentModificationDate ?? .distantPast) < startOfDay {
                continue
            }

            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for rawLine in contents.split(separator: "\n") {
                guard rawLine.contains("\"usage\""), rawLine.contains("\"timestamp\"") else { continue }
                guard let data = rawLine.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let date = isoFormatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp),
                      date >= startOfDay,
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    continue
                }

                let input = intValue(usage["input_tokens"]) ?? 0
                let output = intValue(usage["output_tokens"]) ?? 0
                let cacheCreation = intValue(usage["cache_creation_input_tokens"]) ?? 0
                let cacheRead = intValue(usage["cache_read_input_tokens"]) ?? 0
                totalTokens += input + output + cacheCreation + cacheRead
                messageCount += 1
                newestDate = max(newestDate ?? date, date)
            }
        }

        return tokenSnapshot(
            for: .claude,
            tokens: totalTokens,
            softCap: claudeDailySoftCap,
            detail: "\(messageCount) assistant message\(messageCount == 1 ? "" : "s") today",
            updatedAt: newestDate ?? Date()
        )
    }

    private func tokenSnapshot(
        for provider: UsageProviderID,
        tokens: Int,
        softCap: Int,
        detail: String,
        updatedAt: Date
    ) -> ProviderUsageSnapshot {
        let percentage = softCap > 0 ? (Double(tokens) / Double(softCap)) * 100.0 : nil
        return ProviderUsageSnapshot(
            id: provider,
            usedLabel: abbreviatedNumber(tokens),
            limitLabel: "\(abbreviatedNumber(softCap)) soft cap",
            detailLabel: detail,
            resetLabel: "Daily local estimate",
            percentageUsed: percentage,
            lastUpdated: updatedAt,
            state: .ready,
            isRefreshing: false
        )
    }

    private func localErrorSnapshot(for provider: UsageProviderID, message: String) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            id: provider,
            usedLabel: "Unavailable",
            limitLabel: "",
            detailLabel: "Local usage failed",
            resetLabel: "",
            percentageUsed: nil,
            lastUpdated: Date(),
            state: .failed(message),
            isRefreshing: false
        )
    }

    private func runSQLite(databasePath: String, query: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databasePath, query]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "UsageDashboard.SQLite",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorOutput.isEmpty ? "sqlite3 failed" : errorOutput]
            )
        }

        return output
    }

    private func readCodexTokenUsage(from rolloutPath: String) -> CodexTokenUsage? {
        guard FileManager.default.fileExists(atPath: rolloutPath),
              let contents = try? String(contentsOfFile: rolloutPath, encoding: .utf8) else {
            return nil
        }

        var latestUsage: CodexTokenUsage?

        for rawLine in contents.split(separator: "\n") {
            guard rawLine.contains("\"token_count\""),
                  rawLine.contains("\"total_token_usage\""),
                  let data = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else {
                continue
            }

            let usage = CodexTokenUsage(
                inputTokens: intValue(total["input_tokens"]) ?? 0,
                cachedInputTokens: intValue(total["cached_input_tokens"]) ?? 0,
                outputTokens: intValue(total["output_tokens"]) ?? 0,
                totalTokens: intValue(total["total_tokens"]) ?? 0
            )

            if usage.inputTokens > 0 || usage.cachedInputTokens > 0 || usage.outputTokens > 0 {
                latestUsage = usage
            }
        }

        return latestUsage
    }

    private func codexPricingRate(for model: String) -> CodexPricingRate {
        let lowercased = model.lowercased()

        if lowercased.contains("auto-review") || lowercased.contains("5.3") {
            return CodexPricingRate(input: 0.4375, cachedInput: 0.04375, output: 3.50)
        }
        if lowercased.contains("5.4-mini") {
            return CodexPricingRate(input: 0.1875, cachedInput: 0.01875, output: 1.13)
        }
        if lowercased.contains("5.4") {
            return CodexPricingRate(input: 0.625, cachedInput: 0.0625, output: 3.75)
        }
        if lowercased.contains("5.5") {
            return CodexPricingRate(input: 1.25, cachedInput: 0.125, output: 7.50)
        }

        return CodexPricingRate(input: 1.25, cachedInput: 0.125, output: 7.50)
    }
}

private struct CodexPricingRate {
    let input: Double
    let cachedInput: Double
    let output: Double
}

private struct CodexTokenUsage {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    func spend(using rate: CodexPricingRate) -> Double {
        (Double(inputTokens) / 1_000_000.0 * rate.input) +
            (Double(cachedInputTokens) / 1_000_000.0 * rate.cachedInput) +
            (Double(outputTokens) / 1_000_000.0 * rate.output)
    }
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
        return int
    }
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let string = value as? String {
        return Int(string)
    }
    return nil
}

private func dollars(fromCents cents: Int) -> String {
    String(format: "$%.2f", Double(cents) / 100.0)
}

private func dollars(from value: Double) -> String {
    String(format: "$%.2f", value)
}

private func dollarsToDouble(_ value: String) -> Double? {
    Double(value.replacingOccurrences(of: ",", with: ""))
}

private func abbreviatedNumber(_ value: Int) -> String {
    let doubleValue = Double(value)
    if value >= 1_000_000 {
        return String(format: "%.1fM", doubleValue / 1_000_000.0)
    }
    if value >= 1_000 {
        return String(format: "%.1fk", doubleValue / 1_000.0)
    }
    return "\(value)"
}

private func formattedDate(from isoString: String?) -> String? {
    guard let isoString else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let fallbackFormatter = ISO8601DateFormatter()
    fallbackFormatter.formatOptions = [.withInternetDateTime]

    guard let date = formatter.date(from: isoString) ?? fallbackFormatter.date(from: isoString) else {
        return nil
    }

    return formattedDisplayDate(date)
}

private func formattedDisplayDate(_ date: Date) -> String {
    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "MMM d, yyyy"
    return displayFormatter.string(from: date)
}

private func parseDisplayDate(_ value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: Date())
    let candidates = [
        trimmed,
        "\(trimmed), \(currentYear)"
    ]

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d, yyyy"

    let longFormatter = DateFormatter()
    longFormatter.locale = Locale(identifier: "en_US_POSIX")
    longFormatter.dateFormat = "MMMM d, yyyy"

    for candidate in candidates {
        if let date = formatter.date(from: candidate) ?? longFormatter.date(from: candidate) {
            if date < calendar.startOfDay(for: Date()),
               !trimmed.contains(","),
               let nextYearDate = calendar.date(byAdding: .year, value: 1, to: date) {
                return nextYearDate
            }

            return date
        }
    }

    return nil
}
