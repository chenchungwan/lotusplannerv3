import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iCloud = iCloudManager.shared

    private var deploymentEnvironmentText: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? 
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Lotus Planner"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)
                
                // App Logo
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                // App Name
                Text(appName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // Version Information
                VStack(spacing: 8) {
                    Text("A customizable digital planner and bullet journal for your unique needs.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer(minLength: 24)

                // Additional Info
                VStack(spacing: 12) {
                    Text("Version \(appVersion)")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Build \(buildNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("© 2026 Lotus Planner")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("iCloud Available: \(iCloud.iCloudAvailable ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Status: \(iCloud.syncStatus.description)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastSync = iCloud.lastSyncDate {
                        Text("Last Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Last Sync: Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Environment: \(deploymentEnvironmentText)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(deploymentEnvironmentText == "Development" ? .orange : .green)
                }
                
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Bundle Extension for App Icon
extension Bundle {
    var icon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return nil
    }
}

#Preview {
    AboutView()
}
