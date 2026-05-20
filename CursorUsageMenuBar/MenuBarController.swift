import Cocoa
import SwiftUI
import WebKit

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var usageService: UsageDashboardService
    private var refreshTimer: Timer?
    private var webWindows: [UsageProviderID: NSWindow] = [:]

    private let pollingInterval: TimeInterval = 300

    override init() {
        AppLog.write("MenuBarController init")
        usageService = UsageDashboardService()
        super.init()

        setupStatusItem()
        setupPopover()
        startPolling()
        refreshUsage()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 52)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
            AppLog.write("Status item button created with fixed length \(statusItem.length)")
            updateMenuBarIcon(snapshots: usageService.snapshots)
        } else {
            AppLog.write("Status item button was nil")
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 456, height: 286)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(
                usageService: usageService,
                onRefresh: { [weak self] in
                    self?.refreshUsage()
                },
                onOpenDashboard: { [weak self] provider in
                    self?.openDashboard(for: provider)
                },
                onQuit: { [weak self] in
                    self?.quitApp()
                }
            )
        )
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    private func refreshUsage() {
        usageService.refreshAll { [weak self] in
            guard let self else { return }
            self.updateMenuBarIcon(snapshots: self.usageService.snapshots)
        }
    }

    private func updateMenuBarIcon(snapshots: [ProviderUsageSnapshot]) {
        guard let button = statusItem.button else { return }

        let size = NSSize(width: 23, height: 23)
        let image = NSImage(size: size, flipped: false) { rect in
            self.drawSegmentedDonutIcon(in: rect, snapshots: snapshots)
            return true
        }
        image.isTemplate = false
        button.image = image
        button.title = "AI"
        button.toolTip = tooltipText(for: snapshots)
        AppLog.write("Updated menu bar icon: \(tooltipText(for: snapshots))")
    }

    private func drawSegmentedDonutIcon(in rect: NSRect, snapshots: [ProviderUsageSnapshot]) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 8.6
        let lineWidth: CGFloat = 3.2

        let segments: [(provider: UsageProviderID, startAngle: CGFloat, length: CGFloat)] = [
            (.cursor, 140, 100),
            (.codex, 20, 100),
            (.claude, -100, 100)
        ]

        for segment in segments {
            let track = NSBezierPath()
            track.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: segment.startAngle,
                endAngle: segment.startAngle - segment.length,
                clockwise: true
            )
            track.lineWidth = lineWidth
            track.lineCapStyle = .round
            NSColor.systemGray.withAlphaComponent(0.24).setStroke()
            track.stroke()

            guard let snapshot = snapshots.first(where: { $0.id == segment.provider }),
                  let percentage = snapshot.percentageUsed else {
                continue
            }

            let clampedPercentage = max(0, min(percentage, 100))
            let fill = NSBezierPath()
            fill.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: segment.startAngle,
                endAngle: segment.startAngle - (segment.length * CGFloat(clampedPercentage / 100.0)),
                clockwise: true
            )
            fill.lineWidth = lineWidth
            fill.lineCapStyle = .round
            segment.provider.nsColor.setStroke()
            fill.stroke()
        }

        if snapshots.contains(where: { snapshot in
            if case .failed = snapshot.state { return true }
            if case .needsLogin = snapshot.state { return true }
            return false
        }) {
            drawCenterMark(in: rect, text: "!")
        }
    }

    private func drawCenterMark(in rect: NSRect, text: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let stringSize = text.size(withAttributes: attrs)
        let stringRect = NSRect(
            x: rect.midX - stringSize.width / 2,
            y: rect.midY - stringSize.height / 2,
            width: stringSize.width,
            height: stringSize.height
        )
        text.draw(in: stringRect, withAttributes: attrs)
    }

    private func tooltipText(for snapshots: [ProviderUsageSnapshot]) -> String {
        snapshots.map { snapshot in
            if let percentage = snapshot.percentageUsed {
                return "\(snapshot.id.displayName): \(Int(percentage))%"
            }
            return "\(snapshot.id.displayName): \(snapshot.usedLabel)"
        }
        .joined(separator: "  ")
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                AppLog.write("Closing popover")
                popover.performClose(nil)
            } else {
                AppLog.write("Opening popover")
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func openDashboard(for provider: UsageProviderID) {
        guard let url = provider.dashboardURL else { return }
        AppLog.write("Opening dashboard for \(provider.displayName)")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(provider.displayName) Usage"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webWindows[provider] = window
    }

    private func quitApp() {
        AppLog.write("Quit requested")
        NSApplication.shared.terminate(nil)
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
