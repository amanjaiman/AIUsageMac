import Cocoa
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var usageService: CursorUsageService
    private var refreshTimer: Timer?
    
    // Polling interval in seconds (5 minutes)
    private let pollingInterval: TimeInterval = 300
    
    override init() {
        self.usageService = CursorUsageService()
        super.init()
        
        setupStatusItem()
        setupPopover()
        startPolling()
        
        // Initial fetch
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
        popover.contentSize = NSSize(width: 300, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(usageService: usageService, onRefresh: { [weak self] in
                self?.refreshUsage()
            }, onOpenDashboard: { [weak self] in
                self?.openDashboard()
            }, onQuit: { [weak self] in
                self?.quitApp()
            })
        )
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
        let innerRadius: CGFloat = 5
        let lineWidth: CGFloat = 3.5
        
        // Background circle (gray)
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: outerRadius - lineWidth/2, startAngle: 0, endAngle: 360)
        backgroundPath.lineWidth = lineWidth
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        backgroundPath.stroke()
        
        // Usage arc
        if let pct = percentage {
            let usagePath = NSBezierPath()
            let startAngle: CGFloat = 90  // Start from top
            let endAngle: CGFloat = 90 - CGFloat(pct / 100.0 * 360)  // Clockwise
            
            usagePath.appendArc(withCenter: center, radius: outerRadius - lineWidth/2, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            usagePath.lineWidth = lineWidth
            usagePath.lineCapStyle = .round
            
            // Color based on usage
            let color: NSColor
            if pct >= 90 {
                color = .systemRed
            } else if pct >= 70 {
                color = .systemOrange
            } else if pct >= 50 {
                color = .systemYellow
            } else {
                color = .systemGreen
            }
            color.setStroke()
            usagePath.stroke()
        } else {
            // Draw question mark if no data
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            let string = "?"
            let stringSize = string.size(withAttributes: attrs)
            let stringRect = NSRect(
                x: center.x - stringSize.width/2,
                y: center.y - stringSize.height/2,
                width: stringSize.width,
                height: stringSize.height
            )
            string.draw(in: stringRect, withAttributes: attrs)
        }
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                
                // Make the popover the key window so it receives focus
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
    
    deinit {
        refreshTimer?.invalidate()
    }
}
