#!/usr/bin/env swift

import Cocoa
import SwiftUI
import WebKit

// MARK: - Usage Model

struct CursorUsage: Equatable {
    let usedCents: Int          // e.g. 10217 = $102.17
    let limitCents: Int         // e.g. 10000 = $100.00
    let billingCycleEnd: String // e.g. "Apr 1, 2026"
    let membershipType: String  // e.g. "enterprise"
    let percentageUsed: Double  // e.g. 102.17
    let lastUpdated: Date
    
    var usedDollars: String {
        let d = Double(usedCents) / 100.0
        return String(format: "$%.2f", d)
    }
    
    var limitDollars: String {
        let d = Double(limitCents) / 100.0
        return String(format: "$%.0f", d)
    }
    
    var usageDisplayText: String {
        return "\(usedDollars) / \(limitDollars)"
    }
    
    static func == (lhs: CursorUsage, rhs: CursorUsage) -> Bool {
        return lhs.usedCents == rhs.usedCents && lhs.limitCents == rhs.limitCents
    }
}

// MARK: - Usage Service

class CursorUsageService: NSObject, ObservableObject {
    @Published var currentUsage: CursorUsage?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var needsLogin: Bool = false
    
    // We use a hidden webview solely to hold the auth cookies from login
    private var webView: WKWebView?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: config)
    }
    
    func fetchUsage(completion: @escaping () -> Void) {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        needsLogin = false
        
        // First load cursor.com so the cookies are in scope
        let url = URL(string: "https://cursor.com")!
        webView?.load(URLRequest(url: url))
        
        // Give the page a moment to set cookies, then call the API
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            // Use XMLHttpRequest (synchronous-style via callback) since evaluateJavaScript
            // doesn't support Promises
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
                        return xhr.responseText;
                    } catch(e) {
                        return JSON.stringify({ error: e.message });
                    }
                })()
            """
            
            self?.webView?.evaluateJavaScript(script) { result, error in
                if let jsonString = result as? String {
                    self?.parseAPIResponse(jsonString, completion: completion)
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = error?.localizedDescription ?? "Failed to fetch usage"
                        self?.isLoading = false
                        completion()
                    }
                }
            }
        }
    }
    
    private func parseAPIResponse(_ jsonString: String, completion: @escaping () -> Void) {
        guard let data = jsonString.data(using: .utf8) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Invalid response"
                self?.isLoading = false
                completion()
            }
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error
                if let err = json["error"] as? String {
                    DispatchQueue.main.async { [weak self] in
                        if err == "login_required" {
                            self?.needsLogin = true
                            self?.errorMessage = "Please log in to Cursor"
                        } else {
                            self?.errorMessage = err
                        }
                        self?.isLoading = false
                        completion()
                    }
                    return
                }
                
                // Parse the usage data
                let individualUsage = json["individualUsage"] as? [String: Any]
                let overall = individualUsage?["overall"] as? [String: Any]
                
                let used = overall?["used"] as? Int ?? 0
                let limit = overall?["limit"] as? Int ?? 0
                let membershipType = json["membershipType"] as? String ?? "unknown"
                
                // Parse billing cycle end date
                var billingEnd = "Unknown"
                if let endStr = json["billingCycleEnd"] as? String {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = isoFormatter.date(from: endStr) {
                        let displayFormatter = DateFormatter()
                        displayFormatter.dateFormat = "MMM d, yyyy"
                        billingEnd = displayFormatter.string(from: date)
                    }
                }
                
                let percentage = limit > 0 ? (Double(used) / Double(limit)) * 100.0 : 0.0
                
                DispatchQueue.main.async { [weak self] in
                    self?.currentUsage = CursorUsage(
                        usedCents: used,
                        limitCents: limit,
                        billingCycleEnd: billingEnd,
                        membershipType: membershipType,
                        percentageUsed: percentage,
                        lastUpdated: Date()
                    )
                    self?.errorMessage = nil
                    self?.isLoading = false
                    completion()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.needsLogin = true
                    self?.errorMessage = "Please log in to Cursor"
                    self?.isLoading = false
                    completion()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.needsLogin = true
                self?.errorMessage = "Please log in to Cursor"
                self?.isLoading = false
                completion()
            }
        }
    }
}

// MARK: - SwiftUI Views

struct UsagePopoverView: View {
    @ObservedObject var usageService: CursorUsageService
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onLogin: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Cursor Usage")
                    .font(.headline)
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .disabled(usageService.isLoading)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Divider()
            
            if usageService.isLoading && usageService.currentUsage == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading usage data...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if usageService.needsLogin {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Login Required")
                        .font(.headline)
                    Text("Click below to log in to your Cursor account.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Login to Cursor") { onLogin() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let usage = usageService.currentUsage {
                UsageDetailView(usage: usage, isRefreshing: usageService.isLoading)
            } else if let error = usageService.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") { onRefresh() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Click refresh to load usage")
                        .font(.caption)
                    Button("Refresh") { onRefresh() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            HStack {
                Button("Open Dashboard") { onOpenDashboard() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                Spacer()
                Button("Quit") { onQuit() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 300, height: 360)
    }
}

struct UsageDetailView: View {
    let usage: CursorUsage
    let isRefreshing: Bool
    
    var usageColor: Color {
        if usage.percentageUsed >= 90 { return .red }
        else if usage.percentageUsed >= 70 { return .orange }
        else if usage.percentageUsed >= 50 { return .yellow }
        else { return .green }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: CGFloat(min(usage.percentageUsed / 100.0, 1.0)))
                    .stroke(usageColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 0) {
                    Text("\(Int(usage.percentageUsed))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if isRefreshing {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Usage")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(usage.usageDisplayText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                            .cornerRadius(3)
                        Rectangle()
                            .fill(usageColor)
                            .frame(width: geometry.size.width * CGFloat(min(usage.percentageUsed / 100.0, 1.0)), height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Text("Plan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(usage.membershipType.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Resets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(usage.billingCycleEnd)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Text("Updated \(timeAgo(from: usage.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        else if seconds < 3600 { return "\(seconds / 60) min ago" }
        else { return "\(seconds / 3600) hours ago" }
    }
}

// MARK: - Login Window Controller

class LoginWindowController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    var onLoginSuccess: (() -> Void)?
    private var hasLoggedIn = false
    
    func showLoginWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 450, height: 600), configuration: config)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView = webView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Login to Cursor"
        window.contentView = webView
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window
        
        NSApp.activate(ignoringOtherApps: true)
        
        if let url = URL(string: "https://cursor.com/dashboard?tab=usage") {
            webView.load(URLRequest(url: url))
        }
    }
    
    func closeWindow() {
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.window = nil
            self?.webView = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasLoggedIn else { return }
        
        // Check if we're on the dashboard (logged in)
        if let url = webView.url?.absoluteString, url.contains("dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, !self.hasLoggedIn else { return }
                
                webView.evaluateJavaScript("document.body.innerText") { result, _ in
                    if let text = result as? String {
                        // Check if we can see usage data (meaning we're logged in)
                        let hasUsageData = text.contains("/") && 
                            (text.lowercased().contains("request") || text.lowercased().contains("usage"))
                        let hasLoginPrompt = text.contains("Sign In") || text.contains("Log In") || text.contains("Sign in") || text.contains("Log in")
                        
                        if hasUsageData && !hasLoginPrompt {
                            self.hasLoggedIn = true
                            let callback = self.onLoginSuccess
                            self.closeWindow()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                callback?()
                            }
                        }
                    }
                }
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        // Window is closing, clean up
        webView?.stopLoading()
    }
}

// MARK: - Menu Bar Controller

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var usageService: CursorUsageService
    private var refreshTimer: Timer?
    private let pollingInterval: TimeInterval = 300
    private var loginController: LoginWindowController?
    
    override init() {
        self.usageService = CursorUsageService()
        super.init()
        setupStatusItem()
        setupPopover()
        startPolling()
        refreshUsage()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            updateMenuBarIcon(percentage: nil)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(
                usageService: usageService,
                onRefresh: { [weak self] in self?.refreshUsage() },
                onOpenDashboard: { [weak self] in self?.openDashboard() },
                onLogin: { [weak self] in self?.showLogin() },
                onQuit: { [weak self] in self?.quitApp() }
            )
        )
    }
    
    private func showLogin() {
        popover.performClose(nil)
        
        let controller = LoginWindowController()
        self.loginController = controller
        
        controller.onLoginSuccess = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshUsage()
            }
        }
        
        DispatchQueue.main.async {
            controller.showLoginWindow()
        }
    }
    
    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }
    
    private func refreshUsage() {
        usageService.fetchUsage { [weak self] in
            DispatchQueue.main.async {
                if let usage = self?.usageService.currentUsage {
                    self?.updateMenuBarIcon(percentage: usage.percentageUsed)
                }
            }
        }
    }
    
    func updateMenuBarIcon(percentage: Double?) {
        guard let button = statusItem.button else { return }
        
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            self.drawDonutIcon(in: rect, percentage: percentage)
            return true
        }
        image.isTemplate = false
        button.image = image
    }
    
    private func drawDonutIcon(in rect: NSRect, percentage: Double?) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius: CGFloat = 9
        let lineWidth: CGFloat = 3.5
        
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: outerRadius - lineWidth/2, startAngle: 0, endAngle: 360)
        backgroundPath.lineWidth = lineWidth
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        backgroundPath.stroke()
        
        if let pct = percentage {
            let usagePath = NSBezierPath()
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - CGFloat(pct / 100.0 * 360)
            
            usagePath.appendArc(withCenter: center, radius: outerRadius - lineWidth/2, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            usagePath.lineWidth = lineWidth
            usagePath.lineCapStyle = .round
            
            let color: NSColor
            if pct >= 90 { color = .systemRed }
            else if pct >= 70 { color = .systemOrange }
            else if pct >= 50 { color = .systemYellow }
            else { color = .systemGreen }
            
            color.setStroke()
            usagePath.stroke()
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
            let string = "?"
            let stringSize = string.size(withAttributes: attrs)
            let stringRect = NSRect(x: center.x - stringSize.width/2, y: center.y - stringSize.height/2, width: stringSize.width, height: stringSize.height)
            string.draw(in: stringRect, withAttributes: attrs)
        }
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    private func openDashboard() {
        if let url = URL(string: "https://cursor.com/dashboard?tab=usage") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Menu bar app, no dock icon
app.run()
