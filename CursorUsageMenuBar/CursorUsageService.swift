import Foundation
import WebKit

struct CursorUsage: Equatable {
    let premiumRequestsUsed: Int
    let premiumRequestsLimit: Int
    let usageResetDate: String
    let planName: String
    let percentageUsed: Double
    let lastUpdated: Date
    
    static func == (lhs: CursorUsage, rhs: CursorUsage) -> Bool {
        return lhs.premiumRequestsUsed == rhs.premiumRequestsUsed &&
               lhs.premiumRequestsLimit == rhs.premiumRequestsLimit
    }
}

class CursorUsageService: NSObject, ObservableObject {
    @Published var currentUsage: CursorUsage?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var needsLogin: Bool = false
    
    private var webView: WKWebView?
    private var completion: (() -> Void)?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default() // Use default to share cookies with Safari
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
    }
    
    func fetchUsage(completion: @escaping () -> Void) {
        guard !isLoading else { return }
        
        self.completion = completion
        isLoading = true
        errorMessage = nil
        needsLogin = false
        
        guard let url = URL(string: "https://cursor.com/dashboard?tab=usage") else {
            self.errorMessage = "Invalid URL"
            self.isLoading = false
            completion()
            return
        }
        
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    private func parseUsageFromHTML(_ html: String) {
        // Look for usage patterns in the HTML
        // The Cursor dashboard typically shows usage like "X / Y premium requests"
        
        // Pattern 1: Look for premium requests usage (e.g., "150 / 500")
        let usagePattern = #"(\d+)\s*/\s*(\d+)\s*(?:premium\s*)?(?:fast\s*)?requests?"#
        let usageRegex = try? NSRegularExpression(pattern: usagePattern, options: .caseInsensitive)
        
        var used: Int?
        var limit: Int?
        
        if let match = usageRegex?.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) {
            if let usedRange = Range(match.range(at: 1), in: html),
               let limitRange = Range(match.range(at: 2), in: html) {
                used = Int(html[usedRange])
                limit = Int(html[limitRange])
            }
        }
        
        // Alternative pattern: Look for separate "used" and "limit" values
        if used == nil || limit == nil {
            // Try to find patterns like "Usage: 150" or "Limit: 500"
            let numberPattern = #"(?:used|usage|requests?)[\s:]*(\d+)"#
            let limitPattern = #"(?:limit|total|of)[\s:]*(\d+)"#
            
            if let numberRegex = try? NSRegularExpression(pattern: numberPattern, options: .caseInsensitive),
               let match = numberRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                used = Int(html[range])
            }
            
            if let limitRegex = try? NSRegularExpression(pattern: limitPattern, options: .caseInsensitive),
               let match = limitRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                limit = Int(html[range])
            }
        }
        
        // Look for plan name
        var planName = "Pro" // Default
        let planPattern = #"(?:plan|subscription)[\s:]*["\']?(\w+(?:\s+\w+)?)["\']?"#
        if let planRegex = try? NSRegularExpression(pattern: planPattern, options: .caseInsensitive),
           let match = planRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            planName = String(html[range])
        }
        
        // Look for reset date
        var resetDate = "Unknown"
        let datePattern = #"(?:resets?|renews?)[\s:]*(?:on\s*)?([A-Za-z]+\s+\d+|\d+[/-]\d+[/-]\d+)"#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive),
           let match = dateRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            resetDate = String(html[range])
        }
        
        DispatchQueue.main.async { [weak self] in
            if let used = used, let limit = limit, limit > 0 {
                let percentage = Double(used) / Double(limit) * 100.0
                self?.currentUsage = CursorUsage(
                    premiumRequestsUsed: used,
                    premiumRequestsLimit: limit,
                    usageResetDate: resetDate,
                    planName: planName,
                    percentageUsed: percentage,
                    lastUpdated: Date()
                )
                self?.errorMessage = nil
            } else {
                // Check if user needs to log in
                if html.contains("sign in") || html.contains("log in") || html.contains("Sign In") || html.contains("Log In") {
                    self?.needsLogin = true
                    self?.errorMessage = "Please log in to Cursor"
                } else {
                    self?.errorMessage = "Could not parse usage data"
                }
            }
            self?.isLoading = false
            self?.completion?()
        }
    }
}

extension CursorUsageService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait a moment for JavaScript to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                if let html = result as? String {
                    self?.parseUsageFromHTML(html)
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = error?.localizedDescription ?? "Failed to get page content"
                        self?.isLoading = false
                        self?.completion?()
                    }
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
            self?.isLoading = false
            self?.completion?()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
            self?.isLoading = false
            self?.completion?()
        }
    }
}
