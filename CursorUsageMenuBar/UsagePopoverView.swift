import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var usageService: CursorUsageService
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Cursor Usage")
                    .font(.headline)
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .disabled(usageService.isLoading)
                .opacity(usageService.isLoading ? 0.5 : 1.0)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Divider()
            
            if usageService.isLoading && usageService.currentUsage == nil {
                LoadingView()
            } else if usageService.needsLogin {
                LoginRequiredView(onOpenDashboard: onOpenDashboard)
            } else if let usage = usageService.currentUsage {
                UsageDetailView(usage: usage, isRefreshing: usageService.isLoading)
            } else if let error = usageService.errorMessage {
                ErrorView(message: error, onRetry: onRefresh)
            } else {
                NoDataView(onRefresh: onRefresh)
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Open Dashboard") {
                    onOpenDashboard()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 300, height: 280)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading usage data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoginRequiredView: View {
    let onOpenDashboard: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Login Required")
                .font(.headline)
            
            Text("Please log in to cursor.com in your browser first, then refresh.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Cursor Dashboard") {
                onOpenDashboard()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UsageDetailView: View {
    let usage: CursorUsage
    let isRefreshing: Bool
    
    var usageColor: Color {
        if usage.percentageUsed >= 90 {
            return .red
        } else if usage.percentageUsed >= 70 {
            return .orange
        } else if usage.percentageUsed >= 50 {
            return .yellow
        } else {
            return .green
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Circular progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .frame(width: 80, height: 80)
                
                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(min(usage.percentageUsed / 100.0, 1.0)))
                    .stroke(usageColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: usage.percentageUsed)
                
                // Percentage text
                VStack(spacing: 0) {
                    Text("\(Int(usage.percentageUsed))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
            }
            
            // Usage details
            VStack(spacing: 8) {
                HStack {
                    Text("Premium Requests")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(usage.premiumRequestsUsed) / \(usage.premiumRequestsLimit)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                // Progress bar
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
                            .animation(.easeInOut(duration: 0.5), value: usage.percentageUsed)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Text("Plan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(usage.planName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Resets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(usage.usageResetDate)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Text("Updated \(timeAgoString(from: usage.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoDataView: View {
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Data")
                .font(.headline)
            
            Text("Click refresh to load your Cursor usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    UsagePopoverView(
        usageService: {
            let service = CursorUsageService()
            return service
        }(),
        onRefresh: {},
        onOpenDashboard: {},
        onQuit: {}
    )
}
