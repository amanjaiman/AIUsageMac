import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var usageService: UsageDashboardService
    let onRefresh: () -> Void
    let onOpenDashboard: (UsageProviderID) -> Void
    let onQuit: () -> Void
    @State private var isShowingSettings = false

    var body: some View {
        let showingSettings = isShowingSettings || usageService.shouldShowProviderSetup

        VStack(spacing: 0) {
            Color.clear
                .frame(height: 16)

            header(isShowingSettings: showingSettings)

            Color.clear
                .frame(height: 12)

            Divider()
                .opacity(0.55)

            if showingSettings {
                settingsContent
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(usageService.visibleSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        MinimalUsageRow(
                            snapshot: snapshot,
                            onOpenDashboard: {
                                onOpenDashboard(snapshot.id)
                            }
                        )

                        if index < usageService.visibleSnapshots.count - 1 {
                            Divider()
                                .opacity(0.5)
                                .padding(.leading, 16)
                        }
                    }
                }
            }

            Color.clear
                .frame(height: 10)
        }
        .frame(width: 456, height: 286)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.035),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }

    private func header(isShowingSettings: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isShowingSettings ? "Settings" : "AI Usage")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(isShowingSettings ? "Choose what appears in the menu" : enabledProviderSummary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if isShowingSettings {
                    usageService.completeProviderSetup()
                    self.isShowingSettings = false
                    onRefresh()
                } else {
                    self.isShowingSettings = true
                }
            } label: {
                Image(systemName: isShowingSettings ? "checkmark" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isShowingSettings && usageService.enabledProviders.isEmpty)
            .opacity(isShowingSettings && usageService.enabledProviders.isEmpty ? 0.35 : 1)
            .help(isShowingSettings ? "Done" : "Settings")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(usageService.isRefreshing || isShowingSettings)
            .opacity(usageService.isRefreshing || isShowingSettings ? 0.42 : 1)
            .help("Refresh usage")

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Quit")
        }
        .padding(.horizontal, 16)
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(UsageProviderID.allCases.enumerated()), id: \.element.id) { index, provider in
                ProviderToggleRow(
                    provider: provider,
                    isEnabled: Binding(
                        get: {
                            usageService.isProviderEnabled(provider)
                        },
                        set: { isEnabled in
                            usageService.setProvider(provider, enabled: isEnabled)
                        }
                    )
                )

                if index < UsageProviderID.allCases.count - 1 {
                    Divider()
                        .opacity(0.5)
                        .padding(.leading, 16)
                }
            }

            if usageService.enabledProviders.isEmpty {
                Text("Enable at least one app to show usage.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
    }

    private var enabledProviderSummary: String {
        let providers = UsageProviderID.allCases
            .filter { usageService.enabledProviders.contains($0) }
            .map(\.displayName)
        return providers.isEmpty ? "No apps enabled" : providers.joined(separator: ", ")
    }
}

private struct ProviderToggleRow: View {
    let provider: UsageProviderID
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(provider.color)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var detail: String {
        switch provider {
        case .cursor:
            return "Read from Cursor dashboard"
        case .codex:
            return "Estimated from local Codex usage"
        case .claude:
            return "Read from Claude usage page"
        }
    }
}

private struct MinimalUsageRow: View {
    let snapshot: ProviderUsageSnapshot
    let onOpenDashboard: () -> Void

    private var percentage: Double {
        min(max(snapshot.percentageUsed ?? 0, 0), 100)
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .idle:
            return .secondary
        case .ready:
            if let percentage = snapshot.percentageUsed {
                if percentage >= 90 { return .red }
                if percentage >= 70 { return .orange }
            }
            return snapshot.id.color
        case .needsLogin:
            return .orange
        case .failed:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            colorRail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(snapshot.id.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    nameAccessory
                }

                HStack(spacing: 8) {
                    MinimalBar(color: snapshot.id.color, percentage: percentage, isActive: snapshot.percentageUsed != nil)

                    Text(snapshot.percentageUsed == nil ? "--" : percentText(percentage))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: 34, alignment: .trailing)
                }

                Text(secondaryLine)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot.usedLabel)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !snapshot.limitLabel.isEmpty {
                    Text(limitText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(width: 108, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
    }

    private var colorRail: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(snapshot.id.color)
            .frame(width: 3, height: 44)
    }

    @ViewBuilder
    private var nameAccessory: some View {
        if snapshot.isRefreshing {
            ProgressView()
                .scaleEffect(0.48)
                .frame(width: 16, height: 16)
        } else if snapshot.id.dashboardURL != nil {
            Button(action: onOpenDashboard) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Open dashboard")
        } else if snapshot.id == .codex {
            Text("Estimate")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else {
            EmptyView()
        }
    }

    private var secondaryLine: String {
        let pieces = [
            snapshot.detailLabel,
            snapshot.resetLabel,
            snapshot.lastUpdated.map { timeAgoString(from: $0) }
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        return pieces.joined(separator: "  ·  ")
    }

    private var limitText: String {
        if snapshot.limitLabel.hasSuffix("soft cap") {
            return "/ \(snapshot.limitLabel.replacingOccurrences(of: " soft cap", with: ""))"
        }
        if snapshot.limitLabel.hasSuffix("limit") {
            return "/ \(snapshot.limitLabel.replacingOccurrences(of: " limit", with: ""))"
        }
        return "/ \(snapshot.limitLabel)"
    }

    private func timeAgoString(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))

        if seconds < 60 {
            return "now"
        }
        if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        }

        let hours = seconds / 3600
        return "\(hours)h ago"
    }
}

private struct MinimalBar: View {
    let color: Color
    let percentage: Double
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(color)
                    .frame(width: max(5, geometry.size.width * CGFloat(percentage / 100)))
                    .opacity(isActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: percentage)
            }
        }
        .frame(height: 4)
    }
}

private func percentText(_ percentage: Double) -> String {
    "\(Int(percentage.rounded()))%"
}
